# ------------------------------------------------------------
# anonymize_peer_eval.py
# Anonymizes peer evaluation data across all three sprints
# using fuzzy name matching against participants.csv.
#
# Inputs:  data/peer_eval_sprint1.csv
#          data/peer_eval_sprint2.csv
#          data/peer_eval_sprint3.csv
#          data/participants.csv
# Outputs: data/derived/peer_eval_anon.csv    (successfully matched)
#          data/derived/peer_eval_errors.csv  (rows that failed matching)
# ------------------------------------------------------------

import re
import sys
import pandas as pd
from pathlib import Path
from difflib import SequenceMatcher

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from config import (
    PARTICIPANTS_CSV,
    PEER_EVAL_SPRINT1_CSV,
    PEER_EVAL_SPRINT2_CSV,
    PEER_EVAL_SPRINT3_CSV,
    PEER_EVAL_OUTPUT_CSV,
    PEER_EVAL_ERRORS_CSV,
    EVAL_TEAM_COL,
    EVAL_EVALUATOR_COL,
    EVAL_TARGET_COL,
    PARTICIPANTS_FIRST_COL,
    PARTICIPANTS_LAST_COL,
    PARTICIPANTS_NICKNAMES_COL,
    FUZZY_MATCH_THRESHOLD,
)

# ------------------------------------------------------------
# LOAD PARTICIPANTS
# ------------------------------------------------------------

participants = pd.read_csv(PARTICIPANTS_CSV, dtype=str)
participants = participants.loc[:, ~participants.columns.duplicated()]
participants = participants.fillna("")

print(f"Loaded {len(participants):,} participants")

# ------------------------------------------------------------
# BUILD PER-SPRINT, PER-TEAM NAME LOOKUP
#
# Structure: lookup[sprint][team][normalized_name] = pseudonym
# Also tracks withdrawn students globally per sprint so they
# can be identified without being added to the match pool.
# ------------------------------------------------------------

def normalize_name(s):
    """Lowercase, strip all non-alpha characters."""
    return re.sub(r"[^a-z]", "", str(s).lower())


def name_variants(first, last, nicknames_str):
    """Generate all name variants for a participant."""
    variants = set()
    if first and last:
        variants |= {
            first,
            last,
            f"{first} {last}",
            f"{last} {first}",
        }
    elif first:
        variants.add(first)
    elif last:
        variants.add(last)

    for nick in nicknames_str.split(";"):
        nick = nick.strip()
        if nick:
            variants.add(nick)
            if last:
                variants.add(f"{nick} {last}")

    return variants


SPRINT_COLS = {
    "Sprint 1": "Sprint 1",
    "Sprint 2": "Sprint 2",
    "Sprint 3": "Sprint 3",
}

# lookup[sprint][team] = {norm_name: pseudonym}
lookup    = {s: {} for s in SPRINT_COLS}
withdrawn = {s: set() for s in SPRINT_COLS}

for _, r in participants.iterrows():
    first         = str(r.get(PARTICIPANTS_FIRST_COL, "")).strip()
    last          = str(r.get(PARTICIPANTS_LAST_COL, "")).strip()
    nicknames_str = str(r.get(PARTICIPANTS_NICKNAMES_COL, ""))

    for sprint, col in SPRINT_COLS.items():
        pseudo = str(r.get(col, "")).strip()

        if not pseudo:
            continue

        if pseudo.upper() in {"OUT_OF_SPRINT", "WITHDRAWN"}:
            withdrawn[sprint].add(normalize_name(f"{first} {last}"))
            continue

        # Extract team from pseudonym (e.g. t03_s02 -> t03)
        m = re.match(r"(t\d+)_", pseudo.lower())
        if not m:
            continue
        team = m.group(1)

        lookup[sprint].setdefault(team, {})

        for variant in name_variants(first, last, nicknames_str):
            lookup[sprint][team][normalize_name(variant)] = pseudo


# ------------------------------------------------------------
# FUZZY MATCHING
# ------------------------------------------------------------

def match_name(name, team, sprint):
    """
    Match a raw name string to a pseudonym for a given team and sprint.
    Returns (pseudonym, matched_key, score).
    """
    n = normalize_name(name)

    # Withdrawn override
    if n in withdrawn.get(sprint, set()):
        return "WITHDRAWN", None, 1.0

    candidates = lookup.get(sprint, {}).get(team)
    if not candidates:
        return None, None, None

    # Exact match
    if n in candidates:
        return candidates[n], n, 1.0

    # Fuzzy match
    best_score, best_key = 0, None
    for k in candidates:
        score = SequenceMatcher(None, n, k).ratio()
        if score > best_score:
            best_score, best_key = score, k

    if best_score >= FUZZY_MATCH_THRESHOLD:
        return candidates[best_key], best_key, best_score

    return None, best_key, best_score


def match_reason(label, pseudo, best_key, score):
    if pseudo == "WITHDRAWN":
        return f"{label}: withdrawn"
    if pseudo is None:
        hint = f" (closest: '{best_key}', score={score:.2f})" if best_key else ""
        return f"{label}: unmatched{hint}"
    return None


# ------------------------------------------------------------
# PROCESS EACH SPRINT FILE
# ------------------------------------------------------------

SPRINT_FILES = {
    "Sprint 1": PEER_EVAL_SPRINT1_CSV,
    "Sprint 2": PEER_EVAL_SPRINT2_CSV,
    "Sprint 3": PEER_EVAL_SPRINT3_CSV,
}

anon_rows   = []
error_rows  = []

for sprint, filepath in SPRINT_FILES.items():
    df = pd.read_csv(filepath, dtype=str)
    df = df.loc[:, ~df.columns.duplicated()]
    df["sprint"] = sprint

    print(f"Processing {sprint}: {len(df):,} rows from {filepath}")

    for _, r in df.iterrows():
        team = str(r.get(EVAL_TEAM_COL, "")).strip().lower()
        evaluator_raw = str(r.get(EVAL_EVALUATOR_COL, "")).strip()
        target_raw    = str(r.get(EVAL_TARGET_COL, "")).strip()

        eval_pseudo,  eval_key,  eval_score  = match_name(evaluator_raw, team, sprint)
        targ_pseudo,  targ_key,  targ_score  = match_name(target_raw,    team, sprint)

        row_dict = r.to_dict()

        if eval_pseudo and targ_pseudo:
            anon_rows.append({
                **row_dict,
                "evaluator_pseudo": eval_pseudo,
                "target_pseudo":    targ_pseudo,
            })
        else:
            reasons = [
                r for r in [
                    match_reason("Evaluator", eval_pseudo, eval_key, eval_score),
                    match_reason("Target",    targ_pseudo, targ_key, targ_score),
                ]
                if r
            ]
            error_rows.append({
                **row_dict,
                "evaluator_pseudo": eval_pseudo,
                "target_pseudo":    targ_pseudo,
                "error_reason":     "; ".join(reasons),
            })

# ------------------------------------------------------------
# OUTPUT
# ------------------------------------------------------------

Path(PEER_EVAL_OUTPUT_CSV).parent.mkdir(parents=True, exist_ok=True)

anon_df = pd.DataFrame(anon_rows)
anon_df.drop(
    columns=[EVAL_EVALUATOR_COL, EVAL_TARGET_COL],
    errors="ignore",
    inplace=True,
)
anon_df.to_csv(PEER_EVAL_OUTPUT_CSV, index=False)

error_df = pd.DataFrame(error_rows)
error_df.to_csv(PEER_EVAL_ERRORS_CSV, index=False)

print(f"\nPEER EVAL ANONYMIZATION COMPLETE")
print(f"  Successfully anonymized: {len(anon_df):,}")
print(f"  Rows with errors:        {len(error_df):,}")
print(f"  Output:                  {PEER_EVAL_OUTPUT_CSV}")
print(f"  Errors:                  {PEER_EVAL_ERRORS_CSV}")
