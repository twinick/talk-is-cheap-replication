import sys
import pandas as pd
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from utils import SPRINT_BOUNDS


OUTPUT_DIR = Path("data/derived")
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

gh = pd.read_csv("data/derived/github_activity_anon.csv")

# --------------------------------------------------
# CLEAN SCHEMA
# --------------------------------------------------

# fix timestamp column

gh["gh_time"] = pd.to_datetime(
    gh["gh_time"],
    utc=True,
    errors="coerce"
)

# drop junk columns
gh = gh.loc[:, ~gh.columns.str.contains("^Unnamed")]


# --------------------------------------------------
# COMPUTE SPRINT PROGRESS (CORRECT PLACE)
# --------------------------------------------------

gh = gh.merge(
    SPRINT_BOUNDS,
    on="sprint",
    how="left",
    validate="many_to_one"
)

gh["spr_progress"] = (
    (gh["gh_time"] - gh["sprint_start"]) /
    (gh["sprint_end"] - gh["sprint_start"])
).clip(0, 1)

gh["quarter"] = pd.cut(
    gh["spr_progress"],
    bins=[0, 0.25, 0.5, 0.75, 1.01],
    labels=["Q1", "Q2", "Q3", "Q4"],
    right=False,
)

# --------------------------------------------------
# FINAL SANITY CHECK
# --------------------------------------------------

required = {
    "global_id", "student", "team",
    "sprint", "gh_time", "event_type", "spr_progress", "quarter"
}
missing = required - set(gh.columns)
if missing:
    raise KeyError(f"Missing required columns: {missing}")

# --------------------------------------------------
# WRITE ANALYSIS‑READY OUTPUT
# --------------------------------------------------

gh.to_csv(OUTPUT_DIR / "github_events_with_progress.csv", index=False)
