-- ============================================================
-- CreditIQ — PostgreSQL Schema
-- ============================================================

CREATE TABLE mortgage_market (
    year                      SMALLINT PRIMARY KEY,
    new_loans_total           INT,
    new_lending_value_eur_m   NUMERIC(8,1),
    avg_loan_size_eur         INT,
    ftb_share_pct             NUMERIC(5,1),
    ftb_loans                 INT,
    ssb_loans                 INT,
    avg_lti_ftb               NUMERIC(5,2),
    avg_ltv_ftb               NUMERIC(5,1),
    avg_loan_ftb_eur          INT,
    pct_above_lti_limit       NUMERIC(5,1),
    lti_limit_ftb             NUMERIC(5,1)
);

CREATE TABLE arrears (
    year                           SMALLINT PRIMARY KEY,
    pdh_total_accounts             INT,
    pdh_arrears_90d                INT,
    pdh_arrears_rate_pct           NUMERIC(5,2),
    pdh_long_term_arrears          INT,
    pdh_long_term_rate_pct         NUMERIC(5,2),
    pdh_restructured               INT,
    pdh_restructured_rate_pct      NUMERIC(5,1),
    pdh_restructured_performing_pct NUMERIC(5,1),
    btl_arrears_90d                INT,
    btl_arrears_rate_pct           NUMERIC(5,2)
);

CREATE TABLE consumer_credit (
    year                           SMALLINT PRIMARY KEY,
    total_outstanding_eur_b        NUMERIC(6,1),
    personal_loans_eur_b           NUMERIC(6,1),
    credit_cards_overdrafts_eur_b  NUMERIC(6,1),
    npl_rate_pct                   NUMERIC(5,1),
    npl_value_eur_b                NUMERIC(6,2),
    avg_new_loan_interest_rate_pct NUMERIC(5,2)
);

CREATE TABLE sme_lending (
    id                    SERIAL PRIMARY KEY,
    year                  SMALLINT,
    sector                VARCHAR(40),
    new_lending_eur_b     NUMERIC(6,2),
    sector_share_pct      NUMERIC(5,1),
    npl_rate_pct          NUMERIC(5,1),
    npl_value_eur_b       NUMERIC(6,3),
    at_risk_flag          BOOLEAN
);

CREATE INDEX idx_sme_year_sector ON sme_lending(year, sector);
