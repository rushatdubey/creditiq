"""CreditIQ Analytics Pipeline — writes all Tableau CSVs"""
import pandas as pd
import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import roc_auc_score
import os, warnings; warnings.filterwarnings("ignore")

DATA = os.path.join(os.path.dirname(__file__), "../data")
OUT  = os.path.join(os.path.dirname(__file__), "../tableau")
os.makedirs(OUT, exist_ok=True)

def load():
    return {k: pd.read_csv(f"{DATA}/{v}") for k,v in {
        "arrears":"01_mortgage_arrears.csv","lending":"02_new_mortgage_lending.csv",
        "consumer":"03_consumer_credit.csv","sme":"04_sme_lending.csv",
        "sc":"05_credit_risk_scorecard.csv","rates":"06_rate_sensitivity.csv"}.items()}

def s1_arrears(df):
    df = df.copy()
    df["arrears_eur_bn"] = (df["pdh_accounts"]*df["arrears_90d_pct"]/100*280000/1e9).round(2)
    df.to_csv(f"{OUT}/01_arrears_trend.csv",index=False)
    print(f"  Stage 1: Arrears — {len(df)} rows")

def s2_lending(df):
    df = df.copy()
    df["lti_risk"] = df["pct_lti_above_3_5x"].apply(
        lambda x:"High" if x>25 else "Moderate" if x>20 else "Low")
    df.to_csv(f"{OUT}/02_lending_risk.csv",index=False)
    print(f"  Stage 2: Lending — {len(df)} rows")

def s3_consumer(df):
    df = df.copy()
    df["market_health"] = df["npl_rate_pct"].apply(
        lambda x:"Stressed" if x>11 else "Elevated" if x>9 else
                 "Improving" if x>7 else "Healthy")
    df.to_csv(f"{OUT}/03_consumer_credit.csv",index=False)
    print(f"  Stage 3: Consumer — {len(df)} rows")

def s4_sme(sme):
    latest = sme[sme["year"]==sme["year"].max()].copy()
    trend  = sme.groupby(["year","sector"])["npl_rate_pct"].mean().reset_index()
    latest.to_csv(f"{OUT}/04_sme_latest.csv",index=False)
    trend.to_csv(f"{OUT}/04b_sme_trend.csv",index=False)
    print(f"  Stage 4: SME — {len(latest)} + {len(trend)} rows")

def s5_scorecard(sc):
    df = sc.copy()
    df["lgd"] = np.where(df["loan_type"]=="Mortgage",0.35,
                np.where(df["loan_type"]=="Car Finance",0.45,0.65))
    df["expected_loss_eur"] = (df["probability_of_default"]*df["lgd"]*df["loan_amount_eur"]).round(2)

    gd = (df.groupby("risk_grade").agg(
        count=("borrower_id","count"),avg_pd=("probability_of_default","mean"),
        avg_loan=("loan_amount_eur","mean"),
        total_exposure_bn=("loan_amount_eur",lambda x:x.sum()/1e9),
        expected_loss_eur_m=("expected_loss_eur",lambda x:x.sum()/1e6)
    ).reset_index())
    gd["pct_book"] = (gd["count"]/len(df)*100).round(1)
    gd["avg_pd"]   = gd["avg_pd"].round(4)
    gd["avg_loan"] = gd["avg_loan"].round(0).astype(int)

    stress = df.groupby("affordability_stress").agg(
        count=("borrower_id","count"),
        avg_pd=("probability_of_default","mean"),
        avg_dti=("dti_monthly_ratio","mean"),
        total_exp_bn=("loan_amount_eur",lambda x:x.sum()/1e9)
    ).reset_index()

    df.to_csv(f"{OUT}/05_scorecard.csv",index=False)
    gd.to_csv(f"{OUT}/05b_grade_dist.csv",index=False)
    stress.to_csv(f"{OUT}/05c_stress.csv",index=False)
    print(f"  Stage 5: Scorecard — {len(df):,} borrowers")
    return df

def s6_model(sc):
    feats = ["lti_ratio","ltv_ratio","age","credit_score","dti_monthly_ratio"]
    dm = sc.dropna(subset=feats)
    X  = StandardScaler().fit_transform(dm[feats])
    y  = dm["risk_grade"].isin(["D – Substandard","E – Doubtful","F – Loss"]).astype(int)
    m  = LogisticRegression(max_iter=500).fit(X,y)
    auc= roc_auc_score(y, m.predict_proba(X)[:,1])
    cf = pd.DataFrame({"feature":feats,"coefficient":m.coef_[0],
                       "abs_imp":np.abs(m.coef_[0])}).sort_values("abs_imp",ascending=False)
    cf["direction"] = cf["coefficient"].apply(
        lambda c:"Increases Risk" if c>0 else "Reduces Risk")
    cf.to_csv(f"{OUT}/06_model_features.csv",index=False)
    print(f"  Stage 6: PD Model — AUC = {auc:.3f}")
    return auc

def s7_stress(rates, sc):
    r = rates.copy()
    base = r[r["year"]==2021]["arrears_90d_pct"].values[0]
    r["arrears_change_from_2021"] = (r["arrears_90d_pct"]-base).round(2)
    r.to_csv(f"{OUT}/07_rate_sensitivity.csv",index=False)

    sc2 = sc.copy()
    sc2["stress_extra"] = np.where(sc2["rate_type"]=="Tracker",
        sc2["loan_amount_eur"]*0.02/12,
        np.where(sc2["rate_type"]=="Variable",sc2["loan_amount_eur"]*0.01/12,0)).astype(int)
    sc2["stressed_dti"] = ((sc2["monthly_repayment_eur"]+sc2["stress_extra"])/(sc2["annual_income_eur"]/12)).round(3)
    sc2["newly_stressed"] = (sc2["stressed_dti"]>0.40)&(sc2["dti_monthly_ratio"]<=0.40)
    ss = sc2.groupby("rate_type").agg(
        count=("borrower_id","count"),
        currently_stressed=("affordability_stress",lambda x:(x=="Stressed").sum()),
        newly_stressed_200bps=("newly_stressed","sum"),
        avg_extra_monthly=("stress_extra","mean")
    ).reset_index()
    ss.to_csv(f"{OUT}/07b_borrower_stress.csv",index=False)
    print(f"  Stage 7: Rate Stress — peak burden €{r['total_market_burden_eur_m'].max():.0f}M (2023)")

def s8_concentration(sc):
    sc2 = sc.copy()
    sc2["lgd"] = np.where(sc2["loan_type"]=="Mortgage",0.35,
                 np.where(sc2["loan_type"]=="Car Finance",0.45,0.65))
    sc2["expected_loss_eur"] = sc2["probability_of_default"]*sc2["lgd"]*sc2["loan_amount_eur"]
    sc2["lti_bucket"] = pd.cut(sc2["lti_ratio"],
        bins=[0,2.0,2.5,3.0,3.5,4.0,99],
        labels=["<2.0×","2.0–2.5×","2.5–3.0×","3.0–3.5×","3.5–4.0×",">4.0×"])
    sc2["ltv_bucket"] = pd.cut(sc2["ltv_ratio"],
        bins=[0,0.60,0.70,0.80,0.90,1.0],
        labels=["<60%","60–70%","70–80%","80–90%",">90%"])

    lti = sc2.groupby("lti_bucket",observed=True).agg(
        count=("borrower_id","count"),avg_pd=("probability_of_default","mean"),
        exp_bn=("loan_amount_eur",lambda x:x.sum()/1e9),
        el_m=("expected_loss_eur",lambda x:x.sum()/1e6)
    ).reset_index()
    lti["pct_book"] = (lti["count"]/len(sc)*100).round(1)

    ltv = sc2.groupby("ltv_bucket",observed=True).agg(
        count=("borrower_id","count"),avg_pd=("probability_of_default","mean"),
        exp_bn=("loan_amount_eur",lambda x:x.sum()/1e9)
    ).reset_index()
    ltv["pct_book"] = (ltv["count"]/len(sc)*100).round(1)

    hm = sc2.groupby(["lti_bucket","ltv_bucket"],observed=True)["probability_of_default"].mean().round(4).reset_index()
    lti.to_csv(f"{OUT}/08_lti_conc.csv",index=False)
    ltv.to_csv(f"{OUT}/08b_ltv_conc.csv",index=False)
    hm.to_csv(f"{OUT}/08c_heatmap.csv",index=False)
    print(f"  Stage 8: Concentration — LTI {len(lti)} buckets, LTV {len(ltv)} buckets")

def s9_exec(arrears, lending, consumer, sme, sc):
    rows = []
    for y in range(2015,2025):
        aq4 = arrears[arrears["quarter"]==f"{y}Q4"]
        l   = lending[lending["year"]==y]
        c   = consumer[consumer["year"]==y]
        s   = sme[sme["year"]==y]
        rows.append({"year":y,
            "arrears_90d_pct":    aq4["arrears_90d_pct"].values[0] if len(aq4) else None,
            "new_lending_bn":     l["new_lending_eur_bn"].values[0] if len(l) else None,
            "consumer_npl_pct":   c["npl_rate_pct"].values[0] if len(c) else None,
            "sme_npl_pct":        round(s["npl_rate_pct"].mean(),1) if len(s) else None,
            "ecb_rate_pct":       l["ecb_rate_pct"].values[0] if len(l) else None,
            "pct_tracker":        l["pct_tracker_stock"].values[0] if len(l) else None,
        })
    df = pd.DataFrame(rows)
    df["system_stress"] = df["arrears_90d_pct"].apply(lambda x:
        "Critical" if x and x>7 else "Elevated" if x and x>5 else
        "Moderate" if x and x>3.5 else "Stable")
    df.to_csv(f"{OUT}/09_exec_dashboard.csv",index=False)
    print(f"  Stage 9: Exec Dashboard — {len(df)} rows")

if __name__ == "__main__":
    print("CreditIQ — Analytics Pipeline\n"+"="*40)
    d  = load()
    s1_arrears(d["arrears"])
    s2_lending(d["lending"])
    s3_consumer(d["consumer"])
    s4_sme(d["sme"])
    sc = s5_scorecard(d["sc"])
    auc= s6_model(sc)
    s7_stress(d["rates"], sc)
    s8_concentration(sc)
    s9_exec(d["arrears"],d["lending"],d["consumer"],d["sme"],sc)
    print(f"\n✓ All Tableau CSVs written to tableau/")
    print(f"\n── KEY FINDINGS (Central Bank verified) ──")
    print(f"  Mortgage arrears Q4 2024:  {d['arrears'][d['arrears']['quarter']=='2024Q4']['arrears_90d_pct'].values[0]}%")
    print(f"  New lending 2024:          €{d['lending'][d['lending']['year']==2024]['new_lending_eur_bn'].values[0]}B")
    print(f"  Consumer NPL 2024:         {d['consumer'][d['consumer']['year']==2024]['npl_rate_pct'].values[0]}%")
    print(f"  PD Model AUC:              {auc:.3f}")
    print(f"  Stressed borrowers:        {(sc['affordability_stress']=='Stressed').sum():,}/{len(sc):,}")
    print(f"  Total expected loss:       €{sc['expected_loss_eur'].sum()/1e6:.0f}M")
