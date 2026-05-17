# ------------------------------------------------------------
# anonymize_github.py
# Anonymizes GitHub activity events.
#
# Inputs:  data/github_raw.csv
#          data/participants.csv
# Output:  data/derived/github_activity_anon.csv
# ------------------------------------------------------------

import sys
import pandas as pd
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import (
    PARTICIPANTS_CSV,
    GITHUB_INPUT_CSV,
    GITHUB_OUTPUT_CSV,
    GH_TIMESTAMP_COL,
    GH_ACTOR_COL,
    PARTICIPANTS_GLOBAL_ID_COL,
)
from utils import (
    assign_sprint,
    build_github_lookup,
    build_participants_long,
)

# ------------------------------------------------------------
# LOAD
# ------------------------------------------------------------

events       = pd.read_csv(GITHUB_INPUT_CSV, dtype=str)
participants = pd.read_csv(PARTICIPANTS_CSV, dtype=str)

events       = events.loc[:, ~events.columns.duplicated()]
participants = participants.loc[:, ~participants.columns.duplicated()]

print(f"Loaded {len(events):,} events, {len(participants):,} participants")

# ------------------------------------------------------------
# PARSE TIMESTAMPS + ASSIGN SPRINT
# ------------------------------------------------------------

events["gh_time"] = pd.to_datetime(events[GH_TIMESTAMP_COL], utc=True, errors="coerce")

n_bad = events["gh_time"].isna().sum()
if n_bad:
    print(f"WARNING: {n_bad:,} rows have unparseable timestamps — dropping.")
events = events.dropna(subset=["gh_time"])

events = assign_sprint(events, "gh_time")

# Drop events outside all sprint windows
n_unmapped = events["sprint"].isna().sum()
if n_unmapped:
    print(f"INFO: {n_unmapped:,} rows fall outside all sprint windows — dropping.")
events = events.dropna(subset=["sprint"])

# ------------------------------------------------------------
# JOIN GLOBAL ID
# ------------------------------------------------------------

github_lookup = build_github_lookup(participants)

events = events.merge(
    github_lookup,
    how="left",
    left_on=GH_ACTOR_COL,
    right_on="github",
)

# Drop events with no matching participant
n_unmatched = events[PARTICIPANTS_GLOBAL_ID_COL].isna().sum()
if n_unmatched:
    print(f"INFO: {n_unmatched:,} events had no matching participant (actor not in participants.csv) — dropping.")
events = events.dropna(subset=[PARTICIPANTS_GLOBAL_ID_COL])

# Drop non-student rows (e.g. global_id = NON_STUDENT)
n_non_student = (events[PARTICIPANTS_GLOBAL_ID_COL].str.upper() == "NON_STUDENT").sum()
if n_non_student:
    print(f"INFO: {n_non_student:,} NON_STUDENT rows — dropping.")
events = events[events[PARTICIPANTS_GLOBAL_ID_COL].str.upper() != "NON_STUDENT"]

# ------------------------------------------------------------
# JOIN SPRINT PSEUDONYMS
# ------------------------------------------------------------

participants_long = build_participants_long(participants)

events = events.merge(
    participants_long,
    how="left",
    on=[PARTICIPANTS_GLOBAL_ID_COL, "sprint"],
)

n_no_pseudo = events["student"].isna().sum()
if n_no_pseudo:
    print(f"WARNING: {n_no_pseudo:,} events matched a participant but have no sprint pseudonym — check participants.csv.")

# ------------------------------------------------------------
# CLEAN + OUTPUT
# ------------------------------------------------------------

assert PARTICIPANTS_GLOBAL_ID_COL in events.columns
assert "student" in events.columns

events.drop(
    columns=[GH_ACTOR_COL, "github", "repo", GH_TIMESTAMP_COL, "gh_time"],
    errors="ignore",
    inplace=True,
)

events.rename(columns={PARTICIPANTS_GLOBAL_ID_COL: "global_id"}, inplace=True)

Path(GITHUB_OUTPUT_CSV).parent.mkdir(parents=True, exist_ok=True)
events.to_csv(GITHUB_OUTPUT_CSV, index=False)

print(f"\nGITHUB ANONYMIZATION COMPLETE")
print(f"  Rows output: {len(events):,}")
print(f"  Output:      {GITHUB_OUTPUT_CSV}")