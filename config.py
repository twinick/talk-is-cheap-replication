# ------------------------------------------------------------
# config.py
# Shared configuration for all pipelines.
# Edit the FILE PATHS and SPRINT BOUNDS sections before running.
# ------------------------------------------------------------

# ------------------------------------------------------------
# FILE PATHS
# Set PARTICIPANTS_CSV and the *_INPUT_CSV paths to your
# unanonymized raw data before running the anonymization scripts.
# The *_OUTPUT_CSV paths write into data/ and are safe defaults.
# ------------------------------------------------------------

# Path to the unanonymized participant key (stud_key.csv).
# This file is NOT included in the repository.
PARTICIPANTS_CSV       = "data/stud_key.csv"

MESSAGES_INPUT_CSV     = "data/messages_raw.csv"
MESSAGES_OUTPUT_CSV    = "data/teams_messages_anon.csv"

GITHUB_INPUT_CSV       = "data/github_raw.csv"
GITHUB_OUTPUT_CSV      = "data/github_activity_anon.csv"

PEER_EVAL_SPRINT1_CSV  = "data/peer_eval_sprint1.csv"
PEER_EVAL_SPRINT2_CSV  = "data/peer_eval_sprint2.csv"
PEER_EVAL_SPRINT3_CSV  = "data/peer_eval_sprint3.csv"
PEER_EVAL_OUTPUT_CSV   = "data/derived/peer_eval_anon.csv"
PEER_EVAL_ERRORS_CSV   = "data/derived/peer_eval_errors.csv"

# ------------------------------------------------------------
# COLUMN NAMES IN RAW FILES
# ------------------------------------------------------------

# messages_raw.csv
MSG_TIMESTAMP_COL   = "timestamp"
MSG_TEAM_COL        = "channelName"
MSG_STUDENT_COL     = "fromDisplayName"
MSG_BODY_COL        = "body"

# github_raw.csv
GH_TIMESTAMP_COL    = "timestamp"
GH_ACTOR_COL        = "actor"
GH_TEAM_COL         = "team"
GH_EVENT_TYPE_COL   = "event_type"

# peer_eval raw files (all three have identical structure)
EVAL_TIMESTAMP_COL  = "timestamp"
EVAL_TEAM_COL       = "team"
EVAL_EVALUATOR_COL  = "evaluator_name"
EVAL_TARGET_COL     = "target_name"
EVAL_SCORE_COL      = "score"
EVAL_LABEL_COL      = "label"

# participants.csv
PARTICIPANTS_DISPLAY_NAME_COL = "displayName"
PARTICIPANTS_FIRST_COL        = "first"
PARTICIPANTS_LAST_COL         = "last"
PARTICIPANTS_GITHUB_COL       = "github"
PARTICIPANTS_NETID_COL        = "userPrincipalName"
PARTICIPANTS_NICKNAMES_COL    = "Nicknames"
PARTICIPANTS_GLOBAL_ID_COL    = "global_id"
PARTICIPANTS_SPRINT_COLS      = ["Sprint 1", "Sprint 2", "Sprint 3"]

# ------------------------------------------------------------
# SPRINT BOUNDS (Mountain Time)
# SEMESTER_START_MT is the first day of Sprint 1.
# SEMESTER_END_MT   is the last day of Sprint 3.
# ------------------------------------------------------------

TIMEZONE_LOCAL    = "America/Denver"

SEMESTER_START_MT = "2024-01-15 00:00"
SEMESTER_END_MT   = "2024-05-03 00:00"

SPRINT_WINDOWS = [
    {
        "sprint":   "Sprint 1",
        "start_mt": SEMESTER_START_MT,
        "end_mt":   "2024-02-28 00:00",
    },
    {
        "sprint":   "Sprint 2",
        "start_mt": "2024-02-28 00:00",
        "end_mt":   "2024-04-05 00:00",
    },
    {
        "sprint":   "Sprint 3",
        "start_mt": "2024-04-05 00:00",
        "end_mt":   SEMESTER_END_MT,
    },
]

# ------------------------------------------------------------
# FUZZY MATCH THRESHOLD (peer eval name matching)
# ------------------------------------------------------------

FUZZY_MATCH_THRESHOLD = 0.80
