"""
Sensitivity analysis: hybrid scoring formula × SBERT probability threshold.

Formulas tested (all use rule_conf > 0 as "rule hit"):
  rules_only   — baseline, no SBERT
  union        — rule hit OR sbert >= t   (current approach)
  sbert_only   — sbert >= t
  intersection — rule hit AND sbert >= t

For each combo: recomputes dev_weight per thread (dev_threshold=3 fixed),
then fits the lag model and reports R², n, and key coefficients.
"""

import re, ast
import pandas as pd
import numpy as np
import statsmodels.formula.api as smf
from pathlib import Path
from itertools import product

HERE = Path(__file__).parent.parent

# ── load data ─────────────────────────────────────────────────────────────────
msg = pd.read_csv(HERE / "analysis/analysis_inputs/messages_with_progress.csv")
gh  = pd.read_csv(HERE / "analysis/analysis_inputs/github_events_with_progress.csv")
labels = pd.read_csv(HERE / "data/derived/student_dominant_labels.csv")
labels = labels[~labels["student"].isin(["WITHDRAWN", "OUT_OF_SPRINT"])]

DEV_ACTIVITIES = {"PULL_REQUEST", "TESTING", "CI", "REVIEW", "MERGE", "COMMIT", "ISSUE"}
DEV_THRESH     = 3   # fixed

SPRINTS = ["Sprint 1", "Sprint 2", "Sprint 3"]

# ── parse stored conf dicts ────────────────────────────────────────────────────
def parse_conf(s):
    if not isinstance(s, str) or s in ("{}", "nan"):
        return {}
    matches = re.findall(r"'(\w+)':\s*(?:np\.float64\()?([0-9.e+\-]+)\)?", s)
    return {k: float(v) for k, v in matches}

msg["rule_d"]  = msg["activity_conf"].apply(parse_conf)
msg["sbert_d"] = msg["sbert_conf"].apply(parse_conf)

# ── GitHub centroid (fixed across all combos) ─────────────────────────────────
gh_cent = (
    gh.dropna(subset=["quarter"])
      .groupby(["student", "sprint", "quarter"])["spr_progress"]
      .mean()
      .reset_index()
      .rename(columns={"spr_progress": "gh_centroid"})
)

# ── lag model helper ──────────────────────────────────────────────────────────
def run_lag_model(dev_cent):
    df = (
        gh_cent
        .merge(dev_cent, on=["student", "sprint", "quarter"])
        .assign(dev_lag=lambda d: d["gh_centroid"] - d["dev_centroid"])
        .merge(labels[["student", "sprint", "dominant_contributor"]],
               on=["student", "sprint"])
        .dropna(subset=["dominant_contributor", "dev_lag"])
    )
    df["quarter"]              = pd.Categorical(df["quarter"],
                                                categories=["Q1","Q2","Q3","Q4"])
    df["dominant_contributor"] = pd.Categorical(df["dominant_contributor"],
                                                categories=["higher","lower"])
    df["sprint"]               = pd.Categorical(df["sprint"], categories=SPRINTS)

    if len(df) < 30:
        return None

    m = smf.ols(
        "dev_lag ~ dominant_contributor + quarter + sprint"
        " + dominant_contributor:quarter",
        data=df
    ).fit(cov_type="HC3")

    keep = [c for c in m.params.index if c != "Intercept"]
    rows = pd.DataFrame({
        "term":    keep,
        "coef":    m.params[keep].values,
        "pval":    m.pvalues[keep].values,
    })
    rows["sig"] = rows["pval"].apply(
        lambda p: "**" if p < .01 else ("*" if p < .05 else "")
    )
    return {"r2": m.rsquared, "n": int(m.nobs), "coefs": rows}

# ── scoring combos ────────────────────────────────────────────────────────────
FORMULAS    = ["rules_only", "union", "sbert_only", "intersection",
               "conf_weighted"]
THRESHOLDS  = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7]

def inferred_acts(rule_d, sbert_d, formula, t):
    rule_hit  = {k for k, v in rule_d.items()  if v > 0}
    sbert_hit = {k for k, v in sbert_d.items() if v >= t}
    if formula == "rules_only":
        return rule_hit
    if formula == "union":
        return rule_hit | sbert_hit
    if formula == "sbert_only":
        return sbert_hit
    if formula == "intersection":
        return rule_hit & sbert_hit
    raise ValueError(formula)

# ── main loop ─────────────────────────────────────────────────────────────────
records = []

for formula in FORMULAS:
    thresholds = [None] if formula in ("rules_only", "conf_weighted") else THRESHOLDS

    for t in thresholds:
        label = formula if t is None else f"{formula}_t{t}"

        # message-level dev contribution
        if formula == "conf_weighted":
            # rule hits = 1.0, SBERT-only hits = SBERT probability (uses t=0.5 default)
            SBERT_T = 0.5
            def dev_contrib(row, dev_acts=DEV_ACTIVITIES, st=SBERT_T):
                rule_hit = {k for k, v in row["rule_d"].items() if v > 0}
                sbert_d  = row["sbert_d"]
                union    = rule_hit | {k for k, v in sbert_d.items() if v >= st}
                w = 0.0
                for a in union:
                    if a in dev_acts:
                        w += 1.0 if a in rule_hit else sbert_d.get(a, 0.0)
                return w
        else:
            def dev_contrib(row, f=formula, th=t):
                acts = inferred_acts(row["rule_d"], row["sbert_d"], f,
                                     th if th is not None else 0)
                return len(acts & DEV_ACTIVITIES)

        msg["_dw"] = msg.apply(dev_contrib, axis=1)

        # thread-level dev_weight
        thread_dw = (
            msg.groupby("threadId")["_dw"]
               .sum()
               .reset_index()
               .rename(columns={"_dw": "thread_dw"})
        )

        msg2 = msg.merge(thread_dw, on="threadId")
        msg2["_ttype"] = np.where(
            msg2["thread_dw"] == 0, "NON_DEV",
            np.where(msg2["thread_dw"] < DEV_THRESH, "COORDINATION_ONLY", "DEV")
        )

        # thread type counts (message-level)
        tc = msg2["_ttype"].value_counts().to_dict()
        n_dev   = tc.get("DEV", 0)
        n_coord = tc.get("COORDINATION_ONLY", 0)
        n_non   = tc.get("NON_DEV", 0)

        # dev centroid — also compute collapsed (DEV+COORD) version
        for centroid_mode in ["DEV_only", "DEV_plus_COORD"]:
            if centroid_mode == "DEV_only":
                dev_rows = msg2[(msg2["_ttype"] == "DEV") & msg2["quarter"].notna()]
            else:
                dev_rows = msg2[(msg2["_ttype"] != "NON_DEV") & msg2["quarter"].notna()]

            if len(dev_rows) == 0:
                result = None
            else:
                dev_cent = (
                    dev_rows.groupby(["student", "sprint", "quarter"])["spr_progress"]
                            .mean()
                            .reset_index()
                )
                dev_cent.columns = ["student", "sprint", "quarter", "dev_centroid"]
                result = run_lag_model(dev_cent)

            rec = {
                "formula":        formula,
                "threshold":      t if t is not None else "—",
                "centroid":       centroid_mode,
                "n_DEV":          n_dev,
                "n_COORD":        n_coord,
                "n_NON":          n_non,
                "R2":             round(result["r2"], 3) if result else None,
                "n_lag":          result["n"] if result else None,
            }
            # attach key interaction terms
            if result:
                for row in result["coefs"].itertuples():
                    if "dominant_contributor" in row.term and "quarter" in row.term:
                        rec[row.term] = f"{row.coef:.3f}{row.sig}"
            records.append(rec)
            print(f"  {label:30s}  {centroid_mode:15s}  DEV={n_dev:5d}  R2={rec['R2']}")

# ── print summary ─────────────────────────────────────────────────────────────
df_out = pd.DataFrame(records)

print("\n\n=== Thread classification counts ===")
print(df_out[["formula","threshold","centroid","n_DEV","n_COORD","n_NON"]].to_string(index=False))

print("\n=== Lag model fit ===")
print(df_out[["formula","threshold","centroid","n_lag","R2"]].to_string(index=False))

int_cols = [c for c in df_out.columns if "dominant_contributor" in c]
if int_cols:
    print("\n=== dominant_contributor × quarter interactions (coef, ** p<.01, * p<.05) ===")
    print(df_out[["formula","threshold","centroid"] + int_cols].to_string(index=False))
