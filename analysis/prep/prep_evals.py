# prep_peer_evals.py

import pandas as pd
from pathlib import Path

# -------------------------------
# FILES and CONFIG
# -------------------------------

IN_CSV = "data/evaluations.csv"
OUTDIR = Path("data/derived")
OUTDIR.mkdir(parents=True, exist_ok=True)

OUT_CSV = OUTDIR / "peer_eval_by_sprint.csv"


HIGH_CONTRIBUTOR_LABELS = {
    "good teammate",
    "lone wolf",
}

LOW_CONTRIBUTOR_LABELS = {
    "couch potato",
    "hitchhiker",
}


# -------------------------------
# LOAD
# -------------------------------

df = pd.read_csv(IN_CSV)

df = df.rename(columns={
    "Label": "label",
})

# normalize labels
df["label"] = (
    df["label"]
    .str.lower()
    .str.strip()
    .replace({
        "good teammember": "good teammate",
        "gamer": "hitchhiker",   # domain decision you already made
    })
)


def assign_contributor_group(label: str) -> str | None:
    if not isinstance(label, str):
        return None

    label = label.strip().lower()

    if label in HIGH_CONTRIBUTOR_LABELS:
        return "higher"

    if label in LOW_CONTRIBUTOR_LABELS:
        return "lower"

    return None


df["contributor"] = df["label"].apply(assign_contributor_group)

df = df.dropna(subset=["contributor"])


# drop invalid rows
df = df.dropna(subset=["student"])

# -------------------------------
# OPTIONAL: REMOVE SELF‑EVALS
# -------------------------------

df.rename(columns = {"normed":"type"},inplace = True)


dominant_type = (
    df
    .groupby(["student","sprint"])["label"]
    .value_counts()
    .unstack(fill_value=0)
)

dominant_type["dominant_peer_type"] = dominant_type.apply(
    lambda r: r.idxmax(),
    axis=1
)


dominant_group = (
    df
    .groupby(["student","sprint"])["contributor"]
    .value_counts()
    .unstack(fill_value=0)
)


dominant_group["dominant_contributor"] = dominant_group.apply(
    lambda r: "higher" if r.get("higher", 0) >= r.get("lower", 0)
              else "lower",
    axis=1
)


student_dominance = (
    dominant_type[["dominant_peer_type"]]
    .join(dominant_group[["dominant_contributor"]])
    .reset_index()
)



# -------------------------------
# OUTPUT
# -------------------------------
output_df = df[["team", "student", "sprint", "label","contributor"]].copy()
output_df.to_csv(OUT_CSV, index=False)

student_dominance.to_csv(
    "data/derived/student_dominant_labels.csv",
    index=False
)

print(f"PEER EVAL PREP COMPLETE → {OUT_CSV}")