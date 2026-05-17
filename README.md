# Is Talk Cheap? — Replication Package

This repository contains the data processing pipeline and analysis scripts for the paper *"Is Talk Cheap? Peer-Perceived Contribution and Observable Team Behavior in Software Engineering Class Projects"* (ESEM 2026).

The study investigates whether peer evaluations reflect observable contribution behavior in collaborative software engineering teams, combining communication traces (Microsoft Teams), development activity (GitHub), and peer evaluation surveys across three sprints.

## Data Pipeline: What to Run

### Stage 1: Anonymization
Converts raw data with real identifiers to anonymized datasets. **Run in order:**

```bash
cd talk-is-cheap-replication

# 1. Anonymize Teams messages
python anonymization/01_anon_teams_messages.py
# Outputs:
#   - data/derived/teams_messages_anon.csv
#   - data/derived/audit_unmapped_tokens.csv (quality check)

# 2. Anonymize GitHub activity
python anonymization/02_anon_github_activity.py
# Outputs: data/derived/github_activity_anon.csv

# 3. Anonymize peer evaluation data
python anonymization/03_anon_peer_evaluations.py
# Outputs:
#   - data/derived/p3_eval_anonymized.csv
#   - data/derived/p3_eval_anonymization_errors.csv (errors)
```

### Stage 2: Modeling & Classification
Extracts features and classifies threads by development activity. **Run in order:**

```bash
# 1. Tag messages with activity rules and SBERT embeddings
python model/run_thread_classification.py
# Outputs:
#   - data/derived/threads_coded.csv
#   - data/derived/messages_with_thread_codes.csv

# (aggregate_thread.py and sbert_activity_model.py are utility modules, not run directly)
```

### Stage 3: Analysis Preparation
Aggregates data for statistical analysis in R:

```bash
python analysis/prep/prep_analysis_tables.py
# Outputs (in analysis/analysis_inputs/):
#   - student_sprint_analysis.csv
#   - messages_with_progress.csv
#   - github_events_with_progress.csv
```

### Stage 4: Statistical Analysis
Run R scripts in order — each builds on outputs from Stage 3:

```bash
Rscript analysis/r/01_volume_activity.R
# Outputs: Figures/median_weekly.png, Figures/peer_gh_boxenplots.png
#          Tables/art_anova_combined.tex

Rscript analysis/r/02_first_engagement.R
# Outputs: Figures/engagement_survival_by_event.png
#          Tables/log_rank_git.tex, Tables/anova_first_git.tex

Rscript analysis/r/03_coordination_lag.R
# Outputs: Figures/lag_interaction.png
#          Tables/lag_model.tex, Tables/art_anova_lag.tex

Rscript analysis/r/04_early_risk.R
# Outputs: Figures/firth_risk_curves.png
#          Tables/firth_risk_combined.tex
```

## Project Structure

```
anonymization/        # Pseudonymization scripts
  ├── 01_anon_teams_messages.py
  ├── 02_anon_github_activity.py
  └── 03_anon_peer_evaluations.py

model/                # Classification & feature extraction
  ├── run_thread_classification.py  # Main: classify threads & messages
  ├── sbert_activity_model.py       # SBERT activity classifier
  ├── aggregate_thread.py           # Thread-level aggregation logic
  ├── rule_tagging.py               # Rule-based activity tagging
  ├── text_normalization.py         # Text preprocessing
  └── config_analysis.py            # Activity & action keyword rules

analysis/
  ├── prep/                         # Data preparation for R
  │   ├── prep_analysis_tables.py   # Main aggregation script
  │   ├── github_prep.py            # GitHub event processing
  │   └── prep_evals.py             # Peer evaluation processing
  ├── analysis_inputs/              # Outputs from prep/ (input to R)
  ├── r/                            # Statistical analysis
  │   ├── 01_volume_activity.R      # Volume & ART ANOVA
  │   ├── 02_first_engagement.R     # Survival analysis
  │   ├── 03_coordination_lag.R     # Lag & coordination modeling
  │   ├── 04_early_risk.R           # Firth risk models
  │   └── sensitivity_threshold.R   # Sensitivity analysis (R)
  └── sensitivity_hybrid.py         # Sensitivity analysis (Python)

data/
  ├── raw/                          # Raw input data (not included)
  ├── derived/                      # Anonymized & processed data
  └── manual_annotations.csv        # Hand-labeled messages for classifier

Figures/              # Generated figures (outputs of R scripts)
Tables/               # Generated LaTeX tables (outputs of R scripts)

utils.py              # Shared Python utilities (sprint bounds, config)
```

## Data Flow

```
Raw Data (data/raw/)
  ├── teams_messages_raw.csv
  ├── github_classroom_activity.csv
  └── p3_eval_processed.csv
         ↓
    [Anonymization]
         ↓
Anonymized Data (data/derived/)
  ├── participants_pseudonyms.csv
  ├── teams_messages_anon.csv
  ├── github_activity_anon.csv
  └── p3_eval_anonymized.csv
         ↓
    [Classification & Tagging]
         ↓
Coded Data (data/derived/)
  ├── threads_coded.csv
  └── messages_with_thread_codes.csv
         ↓
    [Aggregation — analysis/prep/]
         ↓
Analysis Inputs (analysis/analysis_inputs/)
  ├── student_sprint_analysis.csv
  ├── messages_with_progress.csv
  └── github_events_with_progress.csv
         ↓
    [R Analysis — analysis/r/]
         ↓
Figures/ and Tables/
```

## Key Concepts

### Pseudonymization Strategy
- **Sprint-Specific Names**: Each student has different pseudonyms per sprint
- **Global IDs**: Consistent identifiers across all data sources (Teams, GitHub, peer evals)
- **Team-Scoped Matching**: Peer evaluation names matched only within teams for accuracy

### Thread Classification
Threads are classified by accumulated development weight:
- **DEV**: Threads with significant development activity (weight ≥ 3)
- **COORDINATION_ONLY**: Minimal development activity (0 < weight < 3)
- **NON_DEV**: No development activity (weight = 0)

Development weight is derived from rule-based keyword matching (pull requests, testing, CI, reviews, merges, commits, issues) combined with SBERT semantic classifier confidence scores.

### Temporal Modeling
GitHub and communication activity are each summarized as temporal centroids — weighted means of event timing within a sprint quarter. Lag is computed as the difference between the GitHub centroid and the development discussion centroid, capturing whether implementation followed or preceded discussion.

## Dependencies

### Python
```bash
pip install pandas numpy scikit-learn sentence-transformers
```

- `pandas` — Data manipulation
- `numpy` — Numerical operations
- `scikit-learn` — OneVsRest classifier for SBERT weak supervision
- `sentence-transformers` — SBERT embeddings (`all-MiniLM-L6-v2`)

### R
```r
install.packages(c("dplyr", "tidyr", "ggplot2", "survival", "ARTool",
                   "emmeans", "lmtest", "sandwich", "logistf", "pROC",
                   "xtable", "here", "lubridate", "ragg", "broom"))
```

### System Requirements
- Python 3.8+
- R 4.1+

## Configuration

- **`utils.py`**: Shared constants used by prep scripts (e.g. sprint bounds)
- **`model/config_analysis.py`**: Activity/action keyword rules, text normalization patterns
- All scripts use paths relative to the project root
- `utils.py` at the project root exports shared constants (e.g. `SPRINT_BOUNDS`) used by the prep scripts

## Data Quality

- **`data/derived/audit_unmapped_tokens.csv`** — Flags potential PII missed during anonymization
- **`data/derived/p3_eval_anonymization_errors.csv`** — Failed peer evaluation name matches
- **`data/manual_annotations.csv`** — 200 hand-labeled messages used to refine the SBERT classifier

## Running from Scratch

```bash
# Stage 1: Anonymize
python anonymization/01_anon_teams_messages.py
python anonymization/02_anon_github_activity.py
python anonymization/03_anon_peer_evaluations.py

# Stage 2: Classify
python model/run_thread_classification.py

# Stage 3: Prepare for R
python analysis/prep/prep_analysis_tables.py

# Stage 4: Statistical analysis
Rscript analysis/r/01_volume_activity.R
Rscript analysis/r/02_first_engagement.R
Rscript analysis/r/03_coordination_lag.R
Rscript analysis/r/04_early_risk.R
```

## Troubleshooting

- **`FileNotFoundError: data/raw/...`** — Raw data files are not included in this repository.
- **`ImportError`** — Run `pip install pandas scikit-learn sentence-transformers numpy`.
- **`Cannot merge on column...`** — Data schema mismatch; check raw data column names against `utils/config.py`.
- **Audit warnings** — Check `data/derived/audit_unmapped_tokens.csv` for potential PII.
