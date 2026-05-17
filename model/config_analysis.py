PLACEHOLDERS = {
    "[REDACTED_EMAIL]": "<EMAIL>",
    "[REDACTED_NAME]": "<NAME>",
    "[REDACTED_GITHUB]": "<GITHUB>",
}

PHRASE_MAP = [
    (r"\bpull request\b", "pull_request"),
    (r"\bpr\b", "pull_request"),
    (r"\bprs\b", "pull_request"),
    (r"\bmerged pr\b", "merge_pull_request"),
    (r"\bmerge pull request\b", "merge_pull_request"),
    (r"\btest cases\b", "test_case"),
    (r"\buse cases\b", "use_case"),
    (r"\bcommits\b", "commit"),
    (r"\bpushed\b", "push"),
    (r"\bcode review\b", "code_review"),
    (r"\blgtm\b", "review_approved"),
    (r"\bci failed\b", "ci_failure"),
    (r"\bci passing\b", "ci_success"),
    (r"\bbug\b", "issue"),
    (r"\bticket\b", "issue"),
]

ACTIVITY_RULES = {
    "PULL_REQUEST": {"pull_request"},
    "ISSUE": {"issue", "bug", "ticket"},
    "COMMIT": {"commit", "push"},
    "TESTING": {"test", "test_case", "unit_test"},
    "REVIEW": {"review", "code_review", "review_approved"},
    "MERGE": {"merge", "merged", "merge_pull_request"},
    "CI": {"ci_failure", "ci_success"},
}

ACTION_RULES = {
    "OPENED": {"opened", "created"},
    "UPDATED": {"updated", "pushed"},
    "MERGED": {"merged"},
    "REVIEWED": {"reviewed", "review_approved"},
    "FAILED": {"failed", "failure"},
    "PASSED": {"passed", "success"},
}