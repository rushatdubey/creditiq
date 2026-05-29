-- ============================================================
-- CreditIQ — Core Credit Risk Analytics
-- ============================================================

-- ── 1. MORTGAGE MARKET GROWTH — NEW LENDING TRAJECTORY ───────────────────────
SELECT year,
    new_loans_total,
    new_lending_value_eur_m,
    avg_loan_ftb_eur,
    avg_lti_ftb,
    ROUND(LAG(new_lending_value_eur_m) OVER (ORDER BY year), 1)  AS prev_year_lending,
    ROUND((new_lending_value_eur_m -
        LAG(new_lending_value_eur_m) OVER (ORDER BY year)) * 100.0 /
        NULLIF(LAG(new_lending_value_eur_m) OVER (ORDER BY year), 0), 1)
                                                                  AS lending_yoy_growth_pct,
    SUM(new_lending_value_eur_m) OVER (
        ORDER BY year ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                             AS cumulative_lending_eur_m
FROM mortgage_market
ORDER BY year;


-- ── 2. ARREARS RECOVERY — HOW FAR HAS IRELAND COME? ──────────────────────────
WITH peak AS (
    SELECT MAX(pdh_arrears_90d) AS peak_arrears FROM arrears
)
SELECT a.year,
    a.pdh_arrears_90d,
    a.pdh_arrears_rate_pct,
    a.pdh_long_term_arrears,
    a.pdh_long_term_rate_pct,
    a.pdh_restructured,
    p.peak_arrears,
    ROUND((p.peak_arrears - a.pdh_arrears_90d) * 100.0 /
          p.peak_arrears, 1)                                      AS reduction_from_peak_pct,
    a.pdh_arrears_90d - LAG(a.pdh_arrears_90d)
        OVER (ORDER BY a.year)                                    AS yoy_change,
    ROUND((a.pdh_arrears_90d - LAG(a.pdh_arrears_90d)
        OVER (ORDER BY a.year)) * 100.0 /
        NULLIF(LAG(a.pdh_arrears_90d) OVER (ORDER BY a.year), 0), 1)
                                                                  AS yoy_pct_change
FROM arrears a
CROSS JOIN peak p
ORDER BY a.year;


-- ── 3. RESTRUCTURE EFFECTIVENESS ─────────────────────────────────────────────
-- Are restructures working? % meeting terms vs in arrears
SELECT year,
    pdh_restructured,
    pdh_restructured_rate_pct,
    pdh_restructured_performing_pct,
    ROUND(100 - pdh_restructured_performing_pct, 1)               AS pct_restructured_failing,
    ROUND(pdh_restructured * pdh_restructured_performing_pct / 100, 0)
                                                                  AS n_meeting_terms,
    ROUND(pdh_restructured * (100-pdh_restructured_performing_pct) / 100, 0)
                                                                  AS n_failing_restructure,
    -- Year-over-year improvement in performing rate
    pdh_restructured_performing_pct -
        LAG(pdh_restructured_performing_pct) OVER (ORDER BY year) AS performing_pct_change
FROM arrears
ORDER BY year;


-- ── 4. CONSUMER CREDIT HEALTH — NPL TREND ────────────────────────────────────
SELECT year,
    total_outstanding_eur_b,
    npl_rate_pct,
    npl_value_eur_b,
    avg_new_loan_interest_rate_pct,
    ROUND(npl_rate_pct - LAG(npl_rate_pct) OVER (ORDER BY year), 1)
                                                                  AS npl_yoy_change,
    -- Rolling 3yr average NPL
    ROUND(AVG(npl_rate_pct) OVER (
        ORDER BY year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2)                                                         AS rolling_3yr_npl,
    CASE
        WHEN npl_rate_pct > 7.0 THEN 'Stressed'
        WHEN npl_rate_pct > 5.0 THEN 'Watch'
        WHEN npl_rate_pct > 3.0 THEN 'Healthy'
        ELSE 'Very Healthy'
    END                                                           AS portfolio_health
FROM consumer_credit
ORDER BY year;


-- ── 5. SME SECTOR RISK CONCENTRATION ─────────────────────────────────────────
SELECT s.year,
    s.sector,
    s.new_lending_eur_b,
    s.sector_share_pct,
    s.npl_rate_pct,
    s.npl_value_eur_b,
    s.at_risk_flag,
    -- Rank by NPL within year
    RANK() OVER (PARTITION BY s.year ORDER BY s.npl_rate_pct DESC) AS npl_rank,
    -- NPL vs sector average
    ROUND(s.npl_rate_pct - AVG(s.npl_rate_pct) OVER (PARTITION BY s.year), 1)
                                                                  AS npl_vs_sector_avg,
    CASE
        WHEN s.npl_rate_pct >= 9.0 THEN 'High Risk — monitor exposure'
        WHEN s.npl_rate_pct >= 6.5 THEN 'Elevated — tighten criteria'
        WHEN s.npl_rate_pct >= 4.0 THEN 'Moderate'
        ELSE 'Low Risk'
    END                                                           AS risk_action
FROM sme_lending s
WHERE s.year = (SELECT MAX(year) FROM sme_lending)
ORDER BY s.npl_rate_pct DESC;


-- ── 6. MACRO-PRUDENTIAL — LTI LIMIT UTILISATION ───────────────────────────────
SELECT mp.year,
    mp.avg_lti_ftb,
    mp.lti_limit_ftb,
    mp.lti_headroom,
    mp.lti_utilisation_pct,
    mp.pct_ftb_above_lti_limit,
    mp.exception_volume,
    -- How much headroom before systemic risk?
    ROUND(mp.lti_limit_ftb - mp.avg_lti_ftb, 2)                  AS lti_buffer,
    CASE
        WHEN mp.lti_utilisation_pct >= 90 THEN 'Near Limit — systemic caution'
        WHEN mp.lti_utilisation_pct >= 80 THEN 'High Utilisation'
        WHEN mp.lti_utilisation_pct >= 70 THEN 'Moderate'
        ELSE 'Comfortable'
    END                                                           AS utilisation_status,
    -- Flag year of LTI limit change
    CASE WHEN mp.year = 2023 THEN 'LTI raised to 4× (FTB)' ELSE NULL END
                                                                  AS policy_event
FROM macro_prudential mp
ORDER BY mp.year;


-- ── 7. INTEREST RATE STRESS TEST ─────────────────────────────────────────────
-- What does a +200bps shock do to FTB affordability?
SELECT year,
    scenario,
    interest_rate_pct,
    monthly_payment_eur,
    monthly_income_eur,
    monthly_dti_pct,
    affordability_flag,
    -- Payment increase vs base
    monthly_payment_eur -
        MIN(monthly_payment_eur) OVER (PARTITION BY year)        AS payment_increase_vs_base,
    ROUND((monthly_payment_eur -
        MIN(monthly_payment_eur) OVER (PARTITION BY year)) * 100.0 /
        NULLIF(MIN(monthly_payment_eur) OVER (PARTITION BY year), 0), 1)
                                                                  AS payment_increase_pct
FROM rate_stress_test
ORDER BY year, interest_rate_pct;


-- ── 8. COMBINED CREDIT RISK VIEW ──────────────────────────────────────────────
-- One-row-per-year system-wide credit health
SELECT
    m.year,
    m.new_lending_value_eur_m,
    a.pdh_arrears_rate_pct,
    a.pdh_long_term_rate_pct,
    c.npl_rate_pct                                                AS consumer_npl_pct,
    c.avg_new_loan_interest_rate_pct,
    -- Aggregate risk signal
    CASE
        WHEN a.pdh_arrears_rate_pct > 8
             OR c.npl_rate_pct > 6  THEN 'System Stress'
        WHEN a.pdh_arrears_rate_pct > 5
             OR c.npl_rate_pct > 4  THEN 'Elevated Risk'
        ELSE 'Stable'
    END                                                           AS system_risk_signal
FROM mortgage_market m
JOIN arrears         a USING(year)
JOIN consumer_credit c USING(year)
ORDER BY m.year;
