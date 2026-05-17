# ------------------------------------------------------------
# utils.py
# Shared utilities for all anonymization pipelines.
# ------------------------------------------------------------

import re
import sys
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))

from config import (
    TIMEZONE_LOCAL,
    SPRINT_WINDOWS,
    PARTICIPANTS_FIRST_COL,
    PARTICIPANTS_LAST_COL,
    PARTICIPANTS_NICKNAMES_COL,
    PARTICIPANTS_GLOBAL_ID_COL,
    PARTICIPANTS_SPRINT_COLS,
    PARTICIPANTS_GITHUB_COL,
)


# ------------------------------------------------------------
# SPRINT ASSIGNMENT
# ------------------------------------------------------------

def mt_to_utc(ts):
    """Convert a Mountain Time timestamp string to UTC. Returns None if blank."""
    if ts is None or ts == "":
        return None
    return (
        pd.Timestamp(ts)
        .tz_localize(TIMEZONE_LOCAL)
        .tz_convert("UTC")
    )


# Pre-built DataFrame of sprint boundaries in UTC — used by analysis scripts.
SPRINT_BOUNDS = pd.DataFrame([
    {
        "sprint":       w["sprint"],
        "sprint_start": mt_to_utc(w["start_mt"]),
        "sprint_end":   mt_to_utc(w["end_mt"]),
    }
    for w in SPRINT_WINDOWS
])


def assign_sprint(df, time_col):
    """
    Add a 'sprint' column to df based on SPRINT_WINDOWS.
    Rows outside all windows will have pd.NA.
    """
    df = df.copy()
    df["sprint"] = pd.NA

    for w in SPRINT_WINDOWS:
        start_utc = mt_to_utc(w["start_mt"])
        end_utc   = mt_to_utc(w["end_mt"])

        mask = df[time_col].notna()
        if start_utc is not None:
            mask &= df[time_col] >= start_utc
        if end_utc is not None:
            mask &= df[time_col] < end_utc

        df.loc[mask, "sprint"] = w["sprint"]

    return df


# ------------------------------------------------------------
# PARTICIPANTS HELPERS
# ------------------------------------------------------------

def build_github_lookup(participants):
    """
    Build a deduplicated github handle -> global_id lookup.

    Handles two legitimate multi-row patterns:
      1. Two handles: 2 rows, different github, same global_id.
         Both rows are preserved so both handles resolve.
      2. Team transfer: 1 row, sprint pseudonyms reflect each
         team across the sprint columns. No special handling needed.

    Raises ValueError if a handle maps to more than one global_id.
    """
    lookup = (
        participants[
            participants[PARTICIPANTS_GITHUB_COL].notna() &
            participants[PARTICIPANTS_GITHUB_COL].ne("") &
            participants[PARTICIPANTS_GLOBAL_ID_COL].str.upper().ne("NON_STUDENT")
        ]
        [[PARTICIPANTS_GITHUB_COL, PARTICIPANTS_GLOBAL_ID_COL]]
        .drop_duplicates(subset=[PARTICIPANTS_GITHUB_COL, PARTICIPANTS_GLOBAL_ID_COL])
    )

    ambiguous = lookup.groupby(PARTICIPANTS_GITHUB_COL).filter(lambda x: len(x) > 1)
    if not ambiguous.empty:
        raise ValueError(
            f"GitHub handle(s) map to more than one global_id — fix participants.csv:\n"
            f"{ambiguous.to_string(index=False)}"
        )

    return lookup


def build_participants_long(participants):
    """
    Melt participants into long format: one row per (global_id, sprint, student).
    Deduplicates on (global_id, sprint) to handle dual-handle participants
    whose two rows produce identical sprint pseudonym entries.

    Sentinel values that are dropped:
      - blank / NaN         : no pseudonym assigned
      - OUT_OF_SPRINT       : student was not active this sprint
      - NON_STUDENT         : not a student (instructor, bot, etc.)
    """
    SENTINELS = {"OUT_OF_SPRINT", "NON_STUDENT"}

    long = (
        participants
        .melt(
            id_vars=[PARTICIPANTS_GLOBAL_ID_COL],
            value_vars=PARTICIPANTS_SPRINT_COLS,
            var_name="sprint",
            value_name="student",
        )
        .replace({"student": {"": pd.NA}})
        .dropna(subset=["student"])
    )

    # Drop sentinel values (case-insensitive)
    long = long[~long["student"].str.upper().isin(SENTINELS)]

    long = long.drop_duplicates(subset=[PARTICIPANTS_GLOBAL_ID_COL, "sprint"])

    return long


def build_name_tokens(participants):
    """
    Build sorted list of all known name tokens (displayName, first, last,
    nicknames) for text normalization and redaction.
    Sorted longest-first to prevent partial matches.
    """
    tokens = set()
    for _, r in participants.iterrows():
        for field in [PARTICIPANTS_FIRST_COL, PARTICIPANTS_LAST_COL]:
            val = str(r.get(field, "")).strip()
            if val:
                tokens.add(val)
        for nick in str(r.get(PARTICIPANTS_NICKNAMES_COL, "")).split(";"):
            nick = nick.strip()
            if nick:
                tokens.add(nick)
    return sorted(tokens, key=len, reverse=True)


# ------------------------------------------------------------
# TEXT NORMALIZATION
# ------------------------------------------------------------

def normalize_whitespace(series):
    """Normalize unicode spaces, &nbsp;, and runs of whitespace."""
    return (
        series.astype(str)
        .str.replace("&nbsp;", " ", regex=False)
        .str.replace("\u00A0", " ", regex=False)
        .str.replace(r"\s+", " ", regex=True)
        .str.strip()
    )


def normalize_glued_names(series, tokens):
    """
    Insert spaces between glued known-name tokens.
    Example: 'JaneDoe' -> 'Jane Doe'
    """
    if series.empty or not tokens:
        return series

    escaped = [re.escape(t) for t in tokens]
    pattern = re.compile(
        rf"({'|'.join(escaped)})({'|'.join(escaped)})",
        flags=re.IGNORECASE,
    )
    return series.str.replace(pattern, r"\1 \2", regex=True)


# ------------------------------------------------------------
# REDACTION
# ------------------------------------------------------------

def build_redaction_regexes(participants):
    """Build compiled regexes for email, netid, github url, github handle, and names."""

    # Email
    email_re = re.compile(
        r"(?<![\w@])[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}(?![\w@])",
        flags=re.IGNORECASE,
    )

    # NetIDs (extracted from userPrincipalName)
    netids = (
        participants["userPrincipalName"]
        .str.lower()
        .str.extract(r"^([^@]+)@")
        .dropna()[0]
        .tolist()
    )
    netid_re = re.compile(
        r"(?<![A-Za-z0-9])(" + "|".join(map(re.escape, netids)) + r")(?![A-Za-z0-9])",
        flags=re.IGNORECASE,
    ) if netids else None

    # GitHub URLs
    github_url_re = re.compile(
        r'(https?://github\.com/)([A-Za-z0-9-]+)([.,)\]\\"' + "'" + r'`]?)',
        flags=re.IGNORECASE,
    )

    # GitHub handles (standalone mentions)
    github_users = (
        participants[PARTICIPANTS_GITHUB_COL]
        .str.lower()
        .str.strip()
        .dropna()
    )
    github_users = github_users[github_users != ""].tolist()
    github_handle_re = re.compile(
        r"(?<![A-Za-z0-9])(" + "|".join(map(re.escape, github_users)) + r")(?![A-Za-z0-9])",
        flags=re.IGNORECASE,
    ) if github_users else None

    # Names
    name_tokens = build_name_tokens(participants)
    name_re = re.compile(
        r"(?<!\w)(" + "|".join(map(re.escape, name_tokens)) + r")(?!\w)",
        flags=re.IGNORECASE,
    ) if name_tokens else None

    return {
        "email":         email_re,
        "netid":         netid_re,
        "github_url":    github_url_re,
        "github_handle": github_handle_re,
        "name":          name_re,
    }


def redact_series(series, regexes):
    """Apply all redaction regexes to a text series in order."""
    if regexes.get("email"):
        series = series.str.replace(regexes["email"], "[REDACTED_EMAIL]", regex=True)
    if regexes.get("github_url"):
        series = series.str.replace(regexes["github_url"], r"\1[REDACTED_GITHUB]\3", regex=True)
    if regexes.get("github_handle"):
        series = series.str.replace(regexes["github_handle"], "[REDACTED_GITHUB]", regex=True)
    if regexes.get("netid"):
        series = series.str.replace(regexes["netid"], "[REDACTED_NETID]", regex=True)
    if regexes.get("name"):
        series = series.str.replace(regexes["name"], "[REDACTED_NAME]", regex=True)
    return series