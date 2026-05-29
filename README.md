# CreditIQ

### Irish Credit Risk and Lending Intelligence Platform

> Institutional-grade credit risk analytics built on real Central Bank of Ireland data.
> SQL · Python · Scikit-learn · HTML · CSS · JavaScript · Chart.js

**Author:** [Rushat Dubey](https://linkedin.com/in/rushat) · rushatdubey16@gmail.com · Dublin, Ireland
**Live Demo:** Coming Soon
**Repository:** [github.com/rushatdubey/creditiq](https://github.com/rushatdubey/creditiq)

---

---

## What CreditIQ Is

CreditIQ is a credit risk and lending intelligence platform built on regulator-published Irish market data. It models borrower default probability, stress-tests portfolio exposure against the ECB hiking cycle, maps SME sector concentration risk, and surfaces the macroprudential signals that matter to lenders, risk teams, and credit analysts.

The platform covers the full Irish credit stack: mortgage arrears recovery, new lending trajectory, LTI and LTV concentration, tracker mortgage burden, consumer NPL trends, SME sector risk, and a logistic regression PD model trained on 5,000 synthetic borrowers calibrated to Central Bank of Ireland figures.

This is not a reporting tool. It is a risk intelligence system.

---

## Business Problem

Every bank, credit union, and fintech lender operating in Ireland is navigating the same three tensions:

1. **Portfolio resilience** — which borrowers will default if the ECB rate stays elevated or rises further?
2. **Concentration exposure** — which LTI and LTV segments are building systemic risk above macroprudential limits?
3. **Rate sensitivity** — how much has the 2022 to 2024 hiking cycle already stressed the book, and who remains exposed?

CreditIQ answers all three with a unified analytics architecture across five modules, sourced directly from the Central Bank of Ireland.

---

## Key Findings

| Signal | Detail |
|---|---|
| PDH arrears at historic low | 2.8% in Q4 2024, down from a 12.9% crisis peak in 2013 |
| Long-term arrears concentration | 55% of remaining arrears are structural, concentrated in non-bank entities |
| ECB hiking cycle burden | €1.2B annual extra cost on tracker mortgage holders at the 2023 peak |
| Financially stressed borrowers | 43.8% of the synthetic book has a monthly DTI above 40% |
| PD model performance | Logistic regression AUC of 0.945 across five credit features |
| Hotels and Restaurants NPL | 15.5% in 2024, 65% above the overall SME average |
| Macroprudential concentration | 29.2% of new 2024 lending is above the 3.5x LTI regulatory limit |
| Consumer credit improvement | NPL rate fell from 12.8% in 2015 to 6.4% in 2024 |

---

## Platform Modules

### Mortgage Arrears Intelligence
40 quarters of PDH arrears data from the Central Bank. Tracks the recovery trajectory from the 2013 crisis peak, decomposes short-term versus long-term arrears (LTMA above 720 days), and isolates the COVID moratorium effect in 2020. 55% of remaining arrears are structural legacy cases in non-bank entities, resolving through legal proceedings rather than organic cure.

### Credit Portfolio Risk
5,000-borrower synthetic loan book calibrated to real CB Ireland market figures. Risk grade distribution across six PD bands (Prime through Loss), expected loss by segment using PD times LGD times EAD, affordability stress by rate type, and new lending volume from 2015 to 2024. Grade D Substandard accounts for 46.8% of the book and drives the majority of expected loss concentration.

### ECB Rate Stress Testing
Direct quantification of the 2022 to 2024 ECB hiking cycle on 244,000 Irish tracker mortgage holders. The annual extra burden peaked at €1.2B in 2023, equivalent to €385 per household per month. LTI trend analysis shows the average loan-to-income ratio rising from 2.85x in 2015 to 3.35x in 2024, with 29.2% of new lending now above the macroprudential 3.5x limit. Fixed rate adoption has tripled from 22% to 72%, creating a refinancing cliff exposure in 2025 to 2027 as fixed terms expire.

### SME and Consumer Risk
8-sector SME NPL ranking on €18.5B of outstanding SME lending. Hotels and Restaurants (15.5%) and Construction (14.6%) are the highest-risk sectors. Consumer credit NPL has halved over the decade to 6.4%, though the rate spread between consumer lending rates and ECB remains wide, sustaining net interest margin pressure on borrowers.

### PD Model Explorer
Logistic regression probability of default model with an AUC of 0.945. Feature importance analysis reveals DTI as the dominant predictor, followed by LTI and LTV. SQL query showcase across nine analytical patterns covering window functions, CTEs, expected loss calculation, and macroprudential concentration flagging.

---

## Platform Preview

## Data Architecture

```
Source: Central Bank of Ireland
  Mortgage Arrears Statistics       Q4 2024     40 quarters, PDH and BTL
  Consumer Credit Market Report     2024        10 years, NPL and balances
  New Mortgage Lending Statistics   2024        LTI, LTV, fixed rate mix
  SME Credit Statistics             2024        8 sectors, 10-year NPL
  Synthetic Loan Book               CB-calibrated    5,000 borrowers
```

All datasets are either direct Central Bank publications or synthetic data generated from published CB Ireland market parameters using `data/generate_data.py`. Every figure is traceable to a regulator source.

---

## SQL Intelligence Layer

Nine production-grade analytical queries covering the full credit risk domain. Built for PostgreSQL, designed to run against live credit book data.

**Portfolio Risk Grade with Expected Loss**
```sql
SELECT risk_grade,
    COUNT(*)                                          AS borrowers,
    ROUND(AVG(probability_of_default)*100, 2)        AS avg_pd_pct,
    ROUND(SUM(loan_amount_eur)/1e9, 3)               AS exposure_bn,
    ROUND(SUM(probability_of_default * 0.40 *
              loan_amount_eur)/1e6, 1)               AS expected_loss_eur_m
FROM credit_risk_scorecard
GROUP BY risk_grade
ORDER BY avg_pd_pct;
```

**Tracker Mortgage Rate Shock**
```sql
WITH tracker AS (
    SELECT borrower_id, monthly_repayment_eur,
           ecb_shock_monthly_eur, annual_income_eur,
           (monthly_repayment_eur + ecb_shock_monthly_eur) /
           (annual_income_eur / 12.0)                AS post_shock_dti
    FROM credit_risk_scorecard
    WHERE rate_type = 'Tracker'
)
SELECT COUNT(*)                                       AS tracker_borrowers,
    SUM(CASE WHEN post_shock_dti > 0.40 THEN 1 ELSE 0 END)
                                                      AS post_shock_stressed,
    ROUND(SUM(ecb_shock_monthly_eur * 12) / 1e6, 1)  AS annual_burden_eur_m
FROM tracker;
```

**LTI Concentration and Macroprudential Exposure**
```sql
SELECT
    CASE WHEN lti_ratio > 3.5 THEN 'Above Limit'
         ELSE 'Within Limit' END                     AS lti_status,
    COUNT(*)                                          AS borrowers,
    ROUND(SUM(loan_amount_eur)/1e9, 3)               AS exposure_bn,
    ROUND(AVG(probability_of_default)*100, 2)        AS avg_pd_pct
FROM credit_risk_scorecard
GROUP BY lti_status;
```

**Additional queries cover:** arrears recovery with FIRST_VALUE and LAG, long-term arrears composition, COVID baseline comparison, restructure effectiveness, SME sector NPL ranking with RANK() OVER PARTITION BY, age band risk profiling, and the dual high-LTI plus high-LTV concentration segment.

---

## Python Risk Pipeline

Nine-stage analytics pipeline from raw Central Bank data to fully processed risk outputs.

| Stage | Module | Output |
|---|---|---|
| 1 | Arrears processing | 40-quarter PDH trend with recovery metrics |
| 2 | Lending risk flags | LTI and LTV bands with macroprudential breach flags |
| 3 | Consumer credit health | NPL trends, rate spreads, market health classification |
| 4 | SME sector ranking | Sector NPL ranking plus 10-year trend |
| 5 | Scorecard and expected loss | Grade distribution, EL by segment, affordability stress |
| 6 | PD model features | Logistic regression coefficients and feature importance |
| 7 | Rate stress test | ECB burden quantification, 200bps borrower-level shock |
| 8 | Concentration analytics | LTI and LTV buckets, risk heatmap |
| 9 | Executive scorecard | One-row-per-year system health with stress signal |

---

## Machine Learning Layer

**Model:** Logistic Regression (scikit-learn, `max_iter=500`)
**Target:** Binary classification — borrowers in risk grades D Substandard, E Doubtful, or F Loss
**Features:** LTI ratio, LTV ratio, age, credit score, monthly DTI ratio
**Preprocessing:** StandardScaler normalisation across all features
**Performance:** AUC 0.945 on the full 5,000-borrower synthetic book

**Feature Importance (ranked by absolute standardised coefficient)**

| Rank | Feature | Direction | Signal Strength |
|---|---|---|---|
| 1 | DTI monthly ratio | Increases risk | Highest |
| 2 | LTI ratio | Increases risk | High |
| 3 | LTV ratio | Increases risk | Mid |
| 4 | Credit score | Reduces risk | Mid |
| 5 | Age | Mixed | Low |

The model validates what practitioners already know: affordability strain (DTI) and leverage (LTI) are the two dominant signals for borrower deterioration. LTV matters but less so once income stress is controlled for. Credit score provides a protective signal but with lower standalone predictive power in an elevated-rate environment.

The AUC of 0.945 reflects a well-separated risk distribution across the synthetic book, consistent with a portfolio calibrated to real Irish market default rates rather than a random synthetic dataset.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Data generation and processing | Python, Pandas, NumPy |
| Risk modelling | Scikit-learn (LogisticRegression, StandardScaler, roc_auc_score) |
| SQL analytics | PostgreSQL-compatible SQL, window functions, CTEs |
| Frontend | HTML5, CSS3, Vanilla JavaScript |
| Charting | Chart.js 4.4 |
| UI system | Custom neumorphic design system |
| Data sources | Central Bank of Ireland (published statistics) |

---

## Design Philosophy

CreditIQ is built on a custom neumorphic fintech design system. Every surface shares the background colour and depth is created entirely through dual box-shadows, producing an interface that reads as a native institutional application rather than a generic analytics dashboard.

The visual language draws from Bloomberg Terminal's information density, Moody's Analytics risk layering, and the clean execution of modern fintech intelligence tooling. The result is a premium product interface: animated landing page, responsive analytics modules, executive KPI architecture, interactive chart system, and a dark mode that renders correctly across all components without a rebuild.

Design decisions include SF Pro Display system typography with aggressive negative letter-spacing, a light-green euro note accent colour, semantic colour coding across all risk signals (green for improving, amber for watch, red for elevated risk), and neumorphic shadow states for interactive elements.

---

## Repository Structure

```
creditiq/
├── index.html              # Animated landing page and full dashboard
├── assets/
│   └── screenshots/        # Product screenshots
├── data/
│   ├── generate_data.py    # Synthetic data generator (CB Ireland calibrated)
│   ├── 01_mortgage_arrears.csv
│   ├── 02_new_mortgage_lending.csv
│   ├── 03_consumer_credit.csv
│   ├── 04_sme_lending.csv
│   ├── 05_credit_risk_scorecard.csv
│   └── 06_rate_sensitivity.csv
├── sql/
│   ├── 01_schema.sql
│   ├── 02_credit_risk_queries.sql
│   └── creditiq_queries.sql
├── python/
│   ├── generate_data.py
│   └── analytics.py
├── screenshots/
├── README.md
└── LICENSE
```

---

## Business Insights

**The arrears story is structural, not cyclical.**
The headline 2.8% PDH arrears rate looks healthy. The 55% long-term arrears share does not. More than half of remaining mortgage distress is above 720 days past due, sitting in non-bank entities, and working through courts rather than resolution. The recovery metric masks a permanent impairment layer that will take years to clear.

**The ECB hiking cycle created a balance sheet shock that most institutions are still absorbing.**
€1.2B of annual extra interest cost landed on 244,000 Irish households in 2023, equivalent to €385 per tracker household per month. The ECB cuts in 2024 provided partial relief but did not eliminate the exposure. Any reversal of the rate cycle would immediately reprice this entire segment.

**LTI concentration is the forward-looking risk signal.**
Average LTI on new lending has risen from 2.85x to 3.35x over the decade. 29.2% of 2024 new lending is already above the 3.5x CB macroprudential limit. In a stress scenario, this is the segment with the highest probability of default and the lowest recoverable equity. The model confirms it: above-limit LTI borrowers carry a materially higher expected loss than the rest of the book.

**SME risk is concentrated, not distributed.**
The SME average NPL of 9.4% conceals a bimodal distribution. Hotels and Restaurants at 15.5% and Construction at 14.6% are carrying legacy post-COVID debt at a time when operating margins remain thin. Professional Services at 6.6% is an entirely different credit story. A lender treating these sectors as one book is mispricing risk systematically.

**Fixed rate adoption has bought time, not immunity.**
72% of 2024 new lending is at fixed rates, up from 22% in 2015. This insulates new originations from the current rate environment. It also creates a refinancing cliff as those fixed terms expire in 2025 to 2027, at which point borrowers locked in below 3% face a materially different rate environment.

---

## Skills Demonstrated

**SQL:** Window functions (FIRST_VALUE, LAG, RANK), CTEs, conditional aggregation, expected loss calculation, cohort comparison, sector ranking

**Python:** Multi-source data pipeline, 9-stage analytics architecture, logistic regression (scikit-learn), stress testing, borrower segmentation, cohort analysis

**Machine Learning:** Binary classification, StandardScaler preprocessing, AUC-ROC evaluation, feature importance interpretation, model calibration

**Credit Domain:** PD / LGD / EAD modelling, LTI and LTV macroprudential limits, arrears classification, affordability DTI analysis, tracker mortgage exposure, NPL monitoring, concentration risk, stress testing

**Frontend Engineering:** Custom HTML and CSS design system, vanilla JavaScript interactive architecture, Chart.js integration, neumorphic UI, dark mode, responsive layout, animated transitions

**Business Analysis:** Executive-level insight writing, institutional risk framing, Central Bank data interpretation, regulatory context (CB Ireland macroprudential rules)

---

## Author

**Rushat Dubey**
Dublin, Ireland

[linkedin.com/in/rushat](https://linkedin.com/in/rushat) · rushatdubey16@gmail.com · [github.com/rushatdubey/creditiq](https://github.com/rushatdubey/creditiq)

---

*Data: Central Bank of Ireland. Mortgage Arrears Statistics Q4 2024, Consumer Credit Market Report 2024, New Mortgage Lending Statistics, SME Credit Statistics. Synthetic loan book calibrated to published CB Ireland market parameters.*
