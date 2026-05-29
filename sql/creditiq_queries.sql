-- ============================================================
-- CreditIQ — SQL Analytics
-- Irish Credit Risk & Lending Intelligence
-- Sources: Central Bank Ireland NCID, Mortgage Arrears Statistics,
--          Consumer Credit Market Report, SME Credit Statistics
-- ============================================================


-- ══════════════════════════════════════════════════════════
-- FILE 1: SCHEMA
-- ══════════════════════════════════════════════════════════

CREATE TABLE mortgage_arrears (
    quarter            VARCHAR(7) PRIMARY KEY,
    year               SMALLINT,
    qtr                CHAR(2),
    pdh_accounts       INT,
    arrears_90d_count  INT,
    arrears_90d_pct    NUMERIC(5,2),
    ltma_count         INT,
    ltma_pct           NUMERIC(5,2),
    performing_pct     NUMERIC(5,1),
    yoy_change_pp      NUMERIC(5,2),
    trend              VARCHAR(15)
);

CREATE TABLE new_mortgage_lending (
    year                           SMALLINT PRIMARY KEY,
    new_lending_eur_bn             NUMERIC(6,1),
    avg_lti                        NUMERIC(5,2),
    avg_ltv_pct                    NUMERIC(5,1),
    pct_lti_above_3_5x             NUMERIC(5,1),
    pct_fixed_rate                 NUMERIC(5,1),
    ecb_rate_pct                   NUMERIC(5,2),
    pct_tracker_stock              NUMERIC(5,1),
    tracker_monthly_increase_eur   INT
);

CREATE TABLE credit_risk_scorecard (
    borrower_id                INT PRIMARY KEY,
    age                        SMALLINT,
    annual_income_eur          INT,
    loan_amount_eur            INT,
    loan_type                  VARCHAR(20),
    lti_ratio                  NUMERIC(6,2),
    ltv_ratio                  NUMERIC(5,3),
    rate_type                  VARCHAR(10),
    credit_score               SMALLINT,
    probability_of_default     NUMERIC(6,4),
    risk_grade                 VARCHAR(20),
    monthly_repayment_eur      INT,
    dti_monthly_ratio          NUMERIC(5,3),
    ecb_shock_monthly_eur      INT,
    affordability_stress       VARCHAR(15)
);

CREATE INDEX idx_arr_year    ON mortgage_arrears(year);
CREATE INDEX idx_sc_grade    ON credit_risk_scorecard(risk_grade);
CREATE INDEX idx_sc_stress   ON credit_risk_scorecard(affordability_stress);
CREATE INDEX idx_sc_type     ON credit_risk_scorecard(loan_type, rate_type);


-- ══════════════════════════════════════════════════════════
-- FILE 2: MORTGAGE ARREARS ANALYSIS
-- ══════════════════════════════════════════════════════════

-- 1. ARREARS RECOVERY — HOW FAST IS THE MARKET HEALING? ──────────────────────
WITH recovery AS (
    SELECT year, qtr,
        arrears_90d_pct,
        FIRST_VALUE(arrears_90d_pct) OVER (ORDER BY quarter) AS peak_arrears,
        MAX(arrears_90d_pct) OVER ()                          AS all_time_peak,
        LAG(arrears_90d_pct, 4) OVER (ORDER BY quarter)      AS same_qtr_prior_year
    FROM mortgage_arrears
)
SELECT *,
    ROUND(arrears_90d_pct - same_qtr_prior_year, 2)          AS yoy_improvement,
    ROUND((all_time_peak - arrears_90d_pct) /
          all_time_peak * 100, 1)                             AS pct_recovered_from_peak
FROM recovery
ORDER BY quarter;


-- 2. LONG-TERM ARREARS AS % OF TOTAL ARREARS ─────────────────────────────────
SELECT quarter, year,
    arrears_90d_count,
    ltma_count,
    ROUND(ltma_count * 100.0 /
          NULLIF(arrears_90d_count, 0), 1)                    AS ltma_pct_of_arrears,
    arrears_90d_count - ltma_count                            AS short_term_arrears,
    CASE WHEN ltma_count * 100.0 /
              NULLIF(arrears_90d_count, 0) > 55
         THEN 'Structural Problem — majority long-term'
         ELSE 'Manageable — majority short-term'
    END                                                       AS arrears_quality
FROM mortgage_arrears
ORDER BY quarter;


-- 3. COVID IMPACT ON ARREARS ──────────────────────────────────────────────────
WITH pre_covid AS (
    SELECT AVG(arrears_90d_pct) AS avg_pre
    FROM mortgage_arrears
    WHERE year BETWEEN 2018 AND 2019
)
SELECT ma.quarter, ma.year, ma.arrears_90d_pct,
    pc.avg_pre                                                AS pre_covid_baseline,
    ROUND(ma.arrears_90d_pct - pc.avg_pre, 2)                AS vs_pre_covid
FROM mortgage_arrears ma
CROSS JOIN pre_covid pc
WHERE ma.year BETWEEN 2019 AND 2024
ORDER BY ma.quarter;


-- ══════════════════════════════════════════════════════════
-- FILE 3: CREDIT RISK SCORECARD ANALYSIS
-- ══════════════════════════════════════════════════════════

-- 1. PORTFOLIO RISK GRADE SUMMARY ────────────────────────────────────────────
SELECT risk_grade,
    COUNT(*)                                                  AS borrower_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)       AS pct_of_portfolio,
    ROUND(AVG(probability_of_default) * 100, 2)              AS avg_pd_pct,
    ROUND(AVG(loan_amount_eur) / 1000, 1)                    AS avg_loan_k,
    ROUND(SUM(loan_amount_eur) / 1e9, 3)                     AS total_exposure_bn,
    -- Expected loss (PD × LGD × EAD; assume 40% LGD avg)
    ROUND(SUM(probability_of_default * 0.40 *
              loan_amount_eur) / 1e6, 1)                     AS expected_loss_eur_m
FROM credit_risk_scorecard
GROUP BY risk_grade
ORDER BY avg_pd_pct;


-- 2. AFFORDABILITY STRESS BY RATE TYPE ───────────────────────────────────────
-- Who is most exposed to ECB rate shock?
SELECT rate_type,
    COUNT(*)                                                  AS borrowers,
    SUM(CASE WHEN affordability_stress = 'Stressed'
             THEN 1 ELSE 0 END)                              AS stressed_count,
    ROUND(SUM(CASE WHEN affordability_stress = 'Stressed'
                   THEN 1 ELSE 0 END) * 100.0 /
          COUNT(*), 1)                                        AS stressed_pct,
    ROUND(AVG(ecb_shock_monthly_eur), 0)                     AS avg_ecb_shock_monthly,
    ROUND(AVG(probability_of_default) * 100, 2)              AS avg_pd_pct,
    RANK() OVER (ORDER BY AVG(probability_of_default) DESC)  AS risk_rank
FROM credit_risk_scorecard
GROUP BY rate_type
ORDER BY avg_pd_pct DESC;


-- 3. LTI CONCENTRATION — MACROPRUDENTIAL RISK ────────────────────────────────
SELECT
    CASE WHEN lti_ratio < 2.0  THEN '< 2.0×'
         WHEN lti_ratio < 2.5  THEN '2.0–2.5×'
         WHEN lti_ratio < 3.0  THEN '2.5–3.0×'
         WHEN lti_ratio < 3.5  THEN '3.0–3.5×'
         WHEN lti_ratio < 4.0  THEN '3.5–4.0×'
         ELSE '> 4.0×'
    END                                                       AS lti_bucket,
    COUNT(*)                                                  AS borrowers,
    ROUND(SUM(loan_amount_eur)/1e9, 3)                       AS exposure_bn,
    ROUND(AVG(probability_of_default)*100, 2)                AS avg_pd_pct,
    -- Flag borrowers above macroprudential 3.5× LTI limit
    SUM(CASE WHEN lti_ratio > 3.5 THEN 1 ELSE 0 END)        AS above_macro_limit,
    ROUND(AVG(dti_monthly_ratio)*100, 1)                     AS avg_dti_pct
FROM credit_risk_scorecard
GROUP BY lti_bucket
ORDER BY MIN(lti_ratio);


-- 4. YOUNG BORROWER RISK PROFILE ─────────────────────────────────────────────
SELECT
    CASE WHEN age < 30 THEN 'Under 30'
         WHEN age < 40 THEN '30–39'
         WHEN age < 50 THEN '40–49'
         WHEN age < 60 THEN '50–59'
         ELSE '60+'
    END                                                       AS age_band,
    COUNT(*)                                                  AS borrowers,
    ROUND(AVG(lti_ratio), 2)                                  AS avg_lti,
    ROUND(AVG(ltv_ratio) * 100, 1)                           AS avg_ltv_pct,
    ROUND(AVG(probability_of_default) * 100, 2)              AS avg_pd_pct,
    ROUND(AVG(annual_income_eur) / 1000, 1)                  AS avg_income_k,
    ROUND(AVG(loan_amount_eur) / 1000, 1)                    AS avg_loan_k,
    SUM(CASE WHEN affordability_stress='Stressed' THEN 1 ELSE 0 END) AS stressed
FROM credit_risk_scorecard
GROUP BY age_band
ORDER BY MIN(age);


-- 5. WORST COMBINATION — HIGH LTI + HIGH LTV ─────────────────────────────────
-- The dual-risk segment: extended AND highly leveraged
SELECT
    COUNT(*)                                                  AS borrowers,
    ROUND(AVG(probability_of_default) * 100, 2)              AS avg_pd_pct,
    ROUND(SUM(loan_amount_eur) / 1e9, 3)                     AS exposure_bn,
    ROUND(AVG(ecb_shock_monthly_eur), 0)                     AS avg_ecb_shock,
    ROUND(SUM(probability_of_default * 0.45 *
              loan_amount_eur) / 1e6, 1)                     AS expected_loss_m,
    'High LTI (>3.5×) AND High LTV (>80%)'                  AS segment_label
FROM credit_risk_scorecard
WHERE lti_ratio > 3.5 AND ltv_ratio > 0.80

UNION ALL

SELECT COUNT(*), ROUND(AVG(probability_of_default)*100,2),
    ROUND(SUM(loan_amount_eur)/1e9,3),
    ROUND(AVG(ecb_shock_monthly_eur),0),
    ROUND(SUM(probability_of_default*0.45*loan_amount_eur)/1e6,1),
    'Rest of Portfolio'
FROM credit_risk_scorecard
WHERE NOT (lti_ratio > 3.5 AND ltv_ratio > 0.80);


-- 6. TRACKER MORTGAGE INTEREST RATE SHOCK IMPACT ─────────────────────────────
WITH tracker_stress AS (
    SELECT borrower_id, annual_income_eur, loan_amount_eur,
        monthly_repayment_eur, dti_monthly_ratio,
        ecb_shock_monthly_eur,
        -- Post-shock DTI
        ROUND((monthly_repayment_eur + ecb_shock_monthly_eur) /
              (annual_income_eur / 12.0), 3)                 AS post_shock_dti,
        affordability_stress
    FROM credit_risk_scorecard
    WHERE rate_type = 'Tracker'
)
SELECT
    COUNT(*)                                                  AS tracker_borrowers,
    SUM(CASE WHEN affordability_stress='Stressed' THEN 1 ELSE 0 END) AS pre_shock_stressed,
    SUM(CASE WHEN post_shock_dti > 0.40 THEN 1 ELSE 0 END)  AS post_shock_stressed,
    SUM(CASE WHEN post_shock_dti > 0.40
             AND affordability_stress != 'Stressed'
             THEN 1 ELSE 0 END)                              AS newly_stressed,
    ROUND(AVG(ecb_shock_monthly_eur), 0)                     AS avg_shock_eur_month,
    ROUND(SUM(ecb_shock_monthly_eur * 12) / 1e6, 1)         AS total_annual_burden_eur_m
FROM tracker_stress;
