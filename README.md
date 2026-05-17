# Is Talk Cheap? — Replication Package

Replication package for *"Is Talk Cheap? Peer-Perceived Contribution and Observable Team Behavior in Software Engineering Class Projects"* (ESEM 2026).

> **Note for reviewers:** This repository has been anonymized for double-blind review following the [disclose-data-dbr-first-then-opendata](https://github.com/dgraziotin/disclose-data-dbr-first-then-opendata) guidelines. Author-identifying information has been removed.

---

## Quickstart: Reproduce Paper Results

All processed data is already included in this repository. To reproduce the figures and tables in the paper, only the R scripts need to be run — no raw data or Python environment required.

```bash
cd talk-is-cheap-replication

Rscript analysis/r/01_volume_activity.R        # Figure 3, Figure 4, Table 2
Rscript analysis/r/02_first_engagement.R       # Figure 5, Table 3, Table 4
Rscript analysis/r/03_coordination_lag.R       # Figure 6, Table 5 (lag model + ART ANOVA)
Rscript analysis/r/04_early_risk.R             # Figure 7, Table 6
Rscript analysis/r/sensitivity_threshold.R     # Sensitivity analysis (threshold robustness)
```

Outputs are written to `Figures/` and `Tables/`. Pre-generated versions are included for reference.

### R Dependencies
```r
install.packages(c("dplyr", "tidyr", "ggplot2", "survival", "ARTool",
                   "emmeans", "lmtest", "sandwich", "logistf", "pROC",
                   "xtable", "here", "lubridate", "ragg", "broom"))
```
Requires R 4.1+.

---

## Included Data

The following processed and anonymized datasets are included and sufficient to reproduce all analyses:

### Stage 1 outputs — anonymized source data (input to Stages 2–3)

| File | Description |
|------|-------------|
| `data/teams_messages_anon.csv` | Pseudonymized Teams messages with PII redacted |
| `data/github_activity_anon.csv` | Pseudonymized GitHub events |
| `data/participants.csv` | Participant–pseudonym mapping (team, student ID, sprint, global ID) |
| `data/evaluations.csv` | Pseudonymized peer evaluation responses |

### Stage 2–3 outputs — analysis-ready data (input to R scripts)

| File | Description |
|------|-------------|
| `analysis/analysis_inputs/github_events_with_progress.csv` | GitHub events with sprint-normalized timing |
| `analysis/analysis_inputs/messages_with_progress.csv` | Teams messages with thread classification and timing |
| `analysis/analysis_inputs/student_sprint_analysis.csv` | Student-sprint summary for risk models |
| `data/derived/github_activity_anon.csv` | GitHub events with sprint labels (Stage 3 input) |
| `data/derived/student_dominant_labels.csv` | Peer evaluation labels aggregated per student-sprint |
| `data/derived/peer_eval_by_sprint.csv` | Individual peer evaluations per sprint |
| `data/derived/messages_with_thread_codes.csv` | Classified messages with activity codes |
| `data/manual_annotations.csv` | 200 hand-labeled messages used to train the SBERT classifier |

**Truly raw data (identifiable Teams messages, GitHub usernames, peer evaluation survey responses before anonymization) is not included** due to participant privacy. The IRB-approved anonymization pipeline is provided for transparency; see Stage 1 below.

---

## Classification and Coding Schema

### Activity Keyword Rules (`model/config_analysis.py`)

Messages are matched against the following rule categories to compute a development weight score:

| Category | Keywords / Tokens |
|----------|-------------------|
| `PULL_REQUEST` | pull_request, pr |
| `ISSUE` | issue, bug, ticket |
| `COMMIT` | commit, push |
| `TESTING` | test, test_case, unit_test |
| `REVIEW` | review, code_review, review_approved |
| `MERGE` | merge, merged, merge_pull_request |
| `CI` | ci_failure, ci_success |

Prior to matching, messages are normalized: lowercased, common phrases collapsed to canonical tokens (e.g. "pull request" → `pull_request`, "lgtm" → `review_approved`), and PII placeholders substituted.

### Thread Classification

Each thread accumulates a development weight from its messages. Threads are then classified as:

| Label | Condition |
|-------|-----------|
| `DEV` | weight ≥ 3 |
| `COORDINATION_ONLY` | 0 < weight < 3 |
| `NON_DEV` | weight = 0 |

### Manual Annotation Schema (`data/manual_annotations.csv`)

200 randomly sampled messages were manually annotated with multi-label activity categories (same categories as above) to capture semantic cases not covered by keyword rules — e.g. development references without explicit keywords. These labels replaced automatically generated labels for the sampled messages and were used to retrain the SBERT classifier.

---

## Full Pipeline

The pipeline has four stages. **Stages 1–3 are only needed to reproduce the data processing from scratch and require the raw data, which is not included.**

### Stage 1: Anonymization
Converts raw data to pseudonymized datasets. Raw data required — skip if using included data.

```bash
python anonymization/01_anon_teams_messages.py
# Outputs: data/teams_messages_anon.csv

python anonymization/02_anon_github_activity.py
# Outputs: data/github_activity_anon.csv

python anonymization/03_anon_peer_evaluations.py
# Outputs: data/derived/peer_eval_anon.csv,
#          data/derived/peer_eval_errors.csv
```

### Stage 2: Classification
Classifies threads using rule-based matching + SBERT weak supervision. Skip if using included data.

```bash
python model/run_thread_classification.py
# Outputs: data/derived/threads_coded.csv,
#          data/derived/messages_with_thread_codes.csv
```

### Stage 3: Analysis Preparation
Aggregates classified data into R-ready tables. Skip if using included data.

```bash
python analysis/prep/prep_analysis_tables.py
# Outputs: analysis/analysis_inputs/student_sprint_analysis.csv
#          analysis/analysis_inputs/messages_with_progress.csv
#          analysis/analysis_inputs/github_events_with_progress.csv
```

### Stage 4: Statistical Analysis
See [Quickstart](#quickstart-reproduce-paper-results) above.

---

## Project Structure

```
anonymization/        # Pseudonymization scripts (Stage 1)
  ├── 01_anon_teams_messages.py
  ├── 02_anon_github_activity.py
  └── 03_anon_peer_evaluations.py

model/                # Classification pipeline (Stage 2)
  ├── run_thread_classification.py  # Entry point
  ├── sbert_activity_model.py       # SBERT weak supervision classifier
  ├── aggregate_thread.py           # Thread-level aggregation
  ├── rule_tagging.py               # Keyword rule matching
  ├── text_normalization.py         # Text preprocessing
  └── config_analysis.py            # Activity/action keyword rules (coding schema)

analysis/
  ├── prep/                         # Data preparation (Stage 3)
  │   ├── prep_analysis_tables.py
  │   ├── github_prep.py
  │   └── prep_evals.py
  ├── analysis_inputs/              # ✓ Included — input to R scripts
  ├── r/                            # Statistical analysis (Stage 4)
  │   ├── 01_volume_activity.R      # Volume & ART ANOVA
  │   ├── 02_first_engagement.R     # Survival analysis
  │   ├── 03_coordination_lag.R     # Lag & coordination modeling
  │   ├── 04_early_risk.R           # Firth risk models
  │   └── sensitivity_threshold.R   # Sensitivity analysis
  └── sensitivity_hybrid.py         # Scoring formula sensitivity (Python)

data/
  ├── teams_messages_anon.csv       # ✓ Included — Stage 1 output (pseudonymized messages)
  ├── github_activity_anon.csv      # ✓ Included — Stage 1 output (pseudonymized events)
  ├── participants.csv              # ✓ Included — participant–pseudonym mapping
  ├── evaluations.csv               # ✓ Included — pseudonymized peer evaluation responses
  ├── manual_annotations.csv        # ✓ Included — hand-labeled messages
  ├── derived/                      # ✓ Included — Stages 2–3 outputs
  └── raw/                          # ✗ Not included (participant privacy)

Figures/              # ✓ Included — pre-generated; regenerated by R scripts
  └── centroid_schematic.png        #   Static schematic (not regenerated by scripts)
  └── make_pipeline.py              #   Script used to generate the pipeline diagram figure
Tables/               # ✓ Included — pre-generated; regenerated by R scripts

utils.py              # Shared constants (sprint bounds, config)
```

---

## Python Dependencies (Stages 1–3 only)

```bash
pip install pandas numpy scikit-learn sentence-transformers
```

Requires Python 3.8+.

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `FileNotFoundError: data/raw/...` | Raw data not included; use the pre-processed data in `analysis/analysis_inputs/` |
| `ImportError` | `pip install pandas scikit-learn sentence-transformers numpy` |
| `Cannot merge on column...` | Check raw data column names against `utils.py` |
| Audit warnings | Check `data/derived/audit_unmapped_tokens.csv` for potential PII |

---

## License

The code in this repository is released under the [MIT License](LICENSE). The data files are released for research use only, consistent with the IRB approval under which they were collected.
