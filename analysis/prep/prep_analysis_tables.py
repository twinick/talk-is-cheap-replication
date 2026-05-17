import sys
import pandas as pd
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from utils import SPRINT_BOUNDS

# --------------------------------------------------
# CONFIG
# --------------------------------------------------

IN_MSG = "data/derived/messages_with_thread_codes.csv"
IN_GH  = "data/derived/github_events_with_progress.csv"
IN_PEER = "data/derived/peer_eval_by_sprint.csv"

OUTDIR = Path("analysis/analysis_inputs")
OUTDIR.mkdir(parents=True, exist_ok=True)

# --------------------------------------------------
# HELPERS
# --------------------------------------------------


def sprint_progress(ts, start, end):
    ts = pd.to_datetime(ts, utc=True, errors="coerce")
    start = pd.to_datetime(start, utc=True, errors="coerce")
    end = pd.to_datetime(end, utc=True, errors="coerce")
    return ((ts - start) / (end - start)).clip(0, 1)


def assign_quarter(p):
    if pd.isna(p):
        return None
    elif p < 0.25:
        return "Q1"
    elif p < 0.50:
        return "Q2"
    elif p < 0.75:
        return "Q3"
    else:
        return "Q4"


# --------------------------------------------------
# LOAD DATA
# --------------------------------------------------

msg = pd.read_csv(IN_MSG)
gh = pd.read_csv(IN_GH)
peer = pd.read_csv(IN_PEER)

# --------------------------------------------------
# MESSAGE PREP
# --------------------------------------------------

msg = msg.drop(columns=["sprint_start", "sprint_end", "spr_progress"], errors="ignore")

msg["msg_time"] = pd.to_datetime(msg["msg_time"], utc=True, errors="coerce")

msg = msg.merge(
    SPRINT_BOUNDS,
    on="sprint",
    how="left",
    validate="many_to_one"
)

msg["spr_progress"] = sprint_progress(
    msg["msg_time"],
    msg["sprint_start"],
    msg["sprint_end"]
)

msg["quarter"] = msg["spr_progress"].apply(assign_quarter)

# --------------------------------------------------
# GITHUB PREP
# --------------------------------------------------

gh = gh.drop(columns=["sprint_start", "sprint_end", "spr_progress"], errors="ignore")


gh["gh_time"] = pd.to_datetime(gh["gh_time"], utc=True, errors="coerce")

gh = gh.merge(
    SPRINT_BOUNDS,
    on="sprint",
    how="left",
    validate="many_to_one"
)

gh["spr_progress"] = sprint_progress(
    gh["gh_time"],
    gh["sprint_start"],
    gh["sprint_end"]
)
gh["quarter"] = gh["spr_progress"].apply(assign_quarter)

# --------------------------------------------------
# MESSAGE → STUDENT‑SPRINT AGGREGATES
# --------------------------------------------------

msg_student = (
    msg.groupby(["student", "sprint"], as_index=False)
       .agg(
           n_messages=("body", "count"),
           dev_weight_sum=("dev_weight", "sum"),
           dev_centroid=("spr_progress", "mean"),
       )
)

msg_student["dev_centroid_bin"] = pd.cut(
    msg_student["dev_centroid"],
    bins=[0, 0.25, 0.50, 0.75, 1.0],
    labels=["0–25%", "25–50%", "50–75%", "75–100%"]
)

# --------------------------------------------------
# GITHUB → STUDENT‑SPRINT AGGREGATES
# --------------------------------------------------

gh_student = (
    gh.groupby(["student", "sprint"], as_index=False)
      .agg(
          n_gh_events=("event_type", "count"),
          gh_dev_centroid=("spr_progress", "mean"),
      )
)

# --------------------------------------------------
# MERGE ALL SOURCES
# --------------------------------------------------

analysis_df = (
    msg_student
      .merge(gh_student, on=["student", "sprint"], how="left")
      .merge(peer, on=["student", "sprint"], how="left")
)

analysis_df["dev_lag"] = (
    analysis_df["gh_dev_centroid"]
    - analysis_df["dev_centroid"]
)

# --------------------------------------------------
# WRITE OUTPUTS
# --------------------------------------------------

analysis_df.to_csv(OUTDIR / "student_sprint_analysis.csv", index=False)
msg.to_csv(OUTDIR / "messages_with_progress.csv", index=False)
gh.to_csv(OUTDIR / "github_events_with_progress.csv", index=False)

print("✅ Analysis input tables written to:", OUTDIR)