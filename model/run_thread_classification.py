import pandas as pd
from pathlib import Path

from .sbert_activity_model import SBERTActivityClassifier
from .rule_tagging import tag_message
from .text_normalization import normalize_text
from .aggregate_thread import aggregate_thread


OUTDIR = Path("data/derived")
OUTDIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------
# LOAD DATA
# ---------------------------------------------

df = pd.read_csv("data/teams_messages_anon.csv")

df = df.dropna(subset=["student"])

# ---------------------------------------------
# MESSAGE-LEVEL FEATURES
# ---------------------------------------------

df["normalized"] = df["body"].apply(normalize_text)

df["activity_conf"], df["action_conf"] = zip(
    *df["normalized"].apply(tag_message)
)

df["inferred_activities"] = df["activity_conf"].apply(
    lambda d: {k for k, v in d.items() if v > 0}
)
df["inferred_actions"] = df["action_conf"].apply(
    lambda d: {k for k, v in d.items() if v > 0}
)

# ---------------------------------------------
# MANUAL ANNOTATION OVERRIDE
# ---------------------------------------------
# 185 messages hand-labelled in Group 8 repo (tagged_bert_model3.ipynb).
# Where a manual label exists it replaces the rule-based label;
# otherwise the rule-based label is used as weak supervision.

anno = pd.read_csv("data/manual_annotations.csv")
anno["activities_set"] = anno["activities"].apply(
    lambda x: set(x.split("|")) if isinstance(x, str) and x else set()
)
anno_map = dict(zip(anno["row_idx"], anno["activities_set"]))

df["training_activities"] = [
    anno_map.get(i, rule_acts)
    for i, rule_acts in zip(df.index, df["inferred_activities"])
]

# ---------------------------------------------
# SBERT (WEAK SUPERVISION + MANUAL ANNOTATION)
# ---------------------------------------------

SBERT_THRESHOLD = 0.5  # intersection: require both rule hit AND sbert >= 0.5

sbert_model = SBERTActivityClassifier(threshold=SBERT_THRESHOLD)

sbert_model.fit(
    df["normalized"].tolist(),
    df["training_activities"].tolist(),
)

df["sbert_conf"] = sbert_model.predict_proba(
    df["normalized"].tolist()
)

# Union: keep activities from rules OR SBERT (rules are precise; SBERT adds semantic coverage)
df["inferred_activities"] = [
    {k for k, v in rule_d.items() if v > 0} | set(sbert_d.keys())
    for rule_d, sbert_d in zip(df["activity_conf"], df["sbert_conf"])
]

# ---------------------------------------------
# THREAD-LEVEL AGGREGATION
# ---------------------------------------------

thread_summary = (
    df.groupby("threadId")
      .apply(aggregate_thread)
      .apply(pd.Series)
      .reset_index()
)

df = df.merge(
    thread_summary[["threadId", "thread_type", "dev_weight", "dominant_activity", "num_messages"]],
    on="threadId",
    how="left",
    validate="many_to_one",
)

df.to_csv(OUTDIR / "messages_with_thread_codes.csv", index=False)

print("Thread classification complete and exported.")
