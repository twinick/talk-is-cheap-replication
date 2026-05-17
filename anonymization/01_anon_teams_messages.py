# ------------------------------------------------------------
# anonymize_messages.py
# Anonymizes Teams chat messages and redacts PII from body text.
#
# Inputs:  data/messages_raw.csv
#          data/participants.csv
# Output:  data/derived/messages_anon.csv
# ------------------------------------------------------------

import sys
import pandas as pd
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import (
    PARTICIPANTS_CSV,
    MESSAGES_INPUT_CSV,
    MESSAGES_OUTPUT_CSV,
    MSG_TIMESTAMP_COL,
    MSG_TEAM_COL,
    MSG_STUDENT_COL,
    MSG_BODY_COL,
    PARTICIPANTS_DISPLAY_NAME_COL,
    PARTICIPANTS_GLOBAL_ID_COL,
)
from utils import (
    assign_sprint,
    build_participants_long,
    build_redaction_regexes,
    redact_series,
    normalize_whitespace,
    normalize_glued_names,
    build_name_tokens,
)

# ------------------------------------------------------------
# LOAD
# ------------------------------------------------------------

messages     = pd.read_csv(MESSAGES_INPUT_CSV, dtype=str)
participants = pd.read_csv(PARTICIPANTS_CSV, dtype=str)

messages     = messages.loc[:, ~messages.columns.duplicated()]
participants = participants.loc[:, ~participants.columns.duplicated()]

print(f"Loaded {len(messages):,} messages, {len(participants):,} participants")

# Validate required columns
required = [MSG_TIMESTAMP_COL, MSG_STUDENT_COL, MSG_BODY_COL]
missing  = [c for c in required if c not in messages.columns]
if missing:
    raise ValueError(f"Missing required columns in messages file: {missing}")

# ------------------------------------------------------------
# PARSE TIMESTAMPS + ASSIGN SPRINT
# ------------------------------------------------------------

messages["msg_time"] = pd.to_datetime(messages[MSG_TIMESTAMP_COL], utc=True, errors="coerce")

n_bad = messages["msg_time"].isna().sum()
if n_bad:
    print(f"WARNING: {n_bad:,} rows have unparseable timestamps — dropping.")
messages = messages.dropna(subset=["msg_time"])

messages = assign_sprint(messages, "msg_time")

n_unmapped = messages["sprint"].isna().sum()
if n_unmapped:
    print(f"WARNING: {n_unmapped:,} messages fall outside all sprint windows.")

# ------------------------------------------------------------
# NORMALIZE TEXT BEFORE MATCHING
# ------------------------------------------------------------

name_tokens = build_name_tokens(participants)

messages[MSG_BODY_COL]    = normalize_glued_names(messages[MSG_BODY_COL], name_tokens)
messages[MSG_BODY_COL]    = normalize_whitespace(messages[MSG_BODY_COL])
messages[MSG_STUDENT_COL] = normalize_whitespace(messages[MSG_STUDENT_COL])

# Align display name column for join
messages = messages.rename(columns={MSG_STUDENT_COL: PARTICIPANTS_DISPLAY_NAME_COL})

# ------------------------------------------------------------
# JOIN GLOBAL ID
# ------------------------------------------------------------

messages = messages.merge(
    participants[[PARTICIPANTS_DISPLAY_NAME_COL, PARTICIPANTS_GLOBAL_ID_COL]],
    how="left",
    on=PARTICIPANTS_DISPLAY_NAME_COL,
)

n_unmatched = messages[PARTICIPANTS_GLOBAL_ID_COL].isna().sum()
if n_unmatched:
    print(f"WARNING: {n_unmatched:,} messages had no matching participant (displayName not in participants.csv) — dropping.")
messages = messages.dropna(subset=[PARTICIPANTS_GLOBAL_ID_COL])

# ------------------------------------------------------------
# JOIN SPRINT PSEUDONYMS
# ------------------------------------------------------------

participants_long = build_participants_long(participants)

messages = messages.merge(
    participants_long,
    how="left",
    on=[PARTICIPANTS_GLOBAL_ID_COL, "sprint"],
)

n_no_pseudo = messages["student"].isna().sum()
if n_no_pseudo:
    print(f"WARNING: {n_no_pseudo:,} messages matched a participant but have no sprint pseudonym — check participants.csv.")

# ------------------------------------------------------------
# REDACT PII FROM BODY
# ------------------------------------------------------------

regexes = build_redaction_regexes(participants)
messages["body_redacted"] = redact_series(messages[MSG_BODY_COL], regexes)

# ------------------------------------------------------------
# CLEAN + OUTPUT
# ------------------------------------------------------------

assert PARTICIPANTS_GLOBAL_ID_COL in messages.columns
assert "student" in messages.columns

messages.drop(
    columns=[
        PARTICIPANTS_DISPLAY_NAME_COL,
        MSG_TIMESTAMP_COL,
        MSG_BODY_COL,
        "msg_time",
    ],
    errors="ignore",
    inplace=True,
)

messages.rename(columns={"body_redacted": "body"}, inplace=True)

Path(MESSAGES_OUTPUT_CSV).parent.mkdir(parents=True, exist_ok=True)
messages.to_csv(MESSAGES_OUTPUT_CSV, index=False)

print(f"\nMESSAGES ANONYMIZATION COMPLETE")
print(f"  Rows output: {len(messages):,}")
print(f"  Output:      {MESSAGES_OUTPUT_CSV}")
