# Sensitivity analysis: dev_weight threshold (1–5) on lag model coefficients
# Varies which threads are classified as DEV and checks coefficient stability.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(lmtest)
  library(sandwich)
  library(here)
})

SPRINTS <- c("Sprint 1", "Sprint 2", "Sprint 3")

msg_raw <- read.csv(
  here("analysis", "analysis_inputs", "messages_with_progress.csv"),
  stringsAsFactors = FALSE
)
gh <- read.csv(
  here("analysis", "analysis_inputs", "github_events_with_progress.csv"),
  stringsAsFactors = FALSE
)
labels <- read.csv(
  here("data", "derived", "student_dominant_labels.csv"),
  stringsAsFactors = FALSE
) %>%
  filter(student != "WITHDRAWN", student != "OUT_OF_SPRINT")

gh_quarter <- gh %>%
  filter(!is.na(quarter)) %>%
  group_by(student, sprint, quarter) %>%
  summarise(gh_centroid = mean(spr_progress, na.rm = TRUE), .groups = "drop")

THRESHOLDS <- 1:5

key_terms <- c(
  "dominant_contributorlower",
  "quarterQ2", "quarterQ3", "quarterQ4",
  "sprintSprint 2", "sprintSprint 3",
  "dominant_contributorlower:quarterQ2",
  "dominant_contributorlower:quarterQ3",
  "dominant_contributorlower:quarterQ4"
)

results <- lapply(THRESHOLDS, function(thresh) {
  # Re-classify thread_type using this threshold
  msg <- msg_raw %>%
    mutate(
      thread_type = case_when(
        dev_weight == 0           ~ "NON_DEV",
        dev_weight < thresh       ~ "COORDINATION_ONLY",
        TRUE                      ~ "DEV"
      )
    )

  n_dev   <- sum(msg$thread_type == "DEV")
  n_coord <- sum(msg$thread_type == "COORDINATION_ONLY")
  n_nondev <- sum(msg$thread_type == "NON_DEV")

  dev_quarter <- msg %>%
    filter(thread_type == "DEV", !is.na(quarter)) %>%
    group_by(student, sprint, quarter, threadId) %>%
    summarise(tc = mean(spr_progress, na.rm = TRUE), .groups = "drop") %>%
    group_by(student, sprint, quarter) %>%
    summarise(dev_centroid = mean(tc, na.rm = TRUE), .groups = "drop")

  lag_quarter <- gh_quarter %>%
    inner_join(dev_quarter, by = c("student", "sprint", "quarter")) %>%
    mutate(dev_lag = gh_centroid - dev_centroid) %>%
    inner_join(labels, by = c("student", "sprint")) %>%
    filter(!is.na(dominant_contributor)) %>%
    mutate(
      quarter              = factor(quarter, levels = c("Q1","Q2","Q3","Q4")),
      dominant_contributor = factor(dominant_contributor, levels = c("higher","lower")),
      sprint               = factor(sprint, levels = SPRINTS)
    )

  m <- lm(
    dev_lag ~ dominant_contributor + quarter + sprint +
              dominant_contributor:quarter,
    data = lag_quarter
  )

  vcov_hc3 <- vcovHC(m, type = "HC3")
  vcov_use  <- if (any(is.nan(diag(vcov_hc3)))) vcovHC(m, type = "HC1") else vcov_hc3
  ct <- coeftest(m, vcov = vcov_use)
  r2 <- summary(m)$r.squared
  n  <- nobs(m)

  coef_rows <- as.data.frame(ct[key_terms, , drop = FALSE])
  coef_rows$term      <- rownames(coef_rows)
  coef_rows$threshold <- thresh
  coef_rows$n_obs     <- n
  coef_rows$r2        <- r2
  coef_rows$n_DEV     <- n_dev
  coef_rows$n_COORD   <- n_coord
  coef_rows$n_NONDEV  <- n_nondev
  rownames(coef_rows) <- NULL
  coef_rows
})

all_results <- bind_rows(results)

# ── Print comparison table ──────────────────────────────────────
cat("\n=== DEV thread classification by threshold ===\n")
summary_tbl <- all_results %>%
  select(threshold, n_DEV, n_COORD, n_NONDEV) %>%
  distinct()
print(summary_tbl, row.names = FALSE)

cat("\n=== Model fit by threshold ===\n")
fit_tbl <- all_results %>%
  select(threshold, n_obs, r2) %>%
  distinct() %>%
  mutate(r2 = round(r2, 3))
print(fit_tbl, row.names = FALSE)

cat("\n=== Key coefficients across thresholds ===\n")
coef_wide <- all_results %>%
  mutate(
    summary = sprintf("%.3f%s",
      Estimate,
      ifelse(`Pr(>|t|)` < .01, "**",
             ifelse(`Pr(>|t|)` < .05, "*", "")))
  ) %>%
  select(term, threshold, summary) %>%
  pivot_wider(names_from = threshold, values_from = summary,
              names_prefix = "t=")

print(as.data.frame(coef_wide), row.names = FALSE)

cat("\n** p<.01  * p<.05\n")
cat(sprintf("Chosen threshold: 3  (n_DEV=%d, n_COORD=%d, N_model=%d, R2=%.3f)\n",
  summary_tbl$n_DEV[summary_tbl$threshold == 3],
  summary_tbl$n_COORD[summary_tbl$threshold == 3],
  fit_tbl$n_obs[fit_tbl$threshold == 3],
  fit_tbl$r2[fit_tbl$threshold == 3]
))
