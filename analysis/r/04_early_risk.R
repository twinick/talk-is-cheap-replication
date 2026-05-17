library(dplyr)
library(tidyr)
library(ggplot2)
library(logistf)
library(pROC)
library(here)

dir.create(here("Figures"), showWarnings = FALSE)
dir.create(here("Tables"),  showWarnings = FALSE)

# ── Design system ──────────────────────────────────────────────
CLR_HIGHER <- "#0072B2"
CLR_LOWER  <- "#D55E00"

theme_paper <- function(base_size = 11) {
  theme_minimal(base_size = base_size) %+replace%
    theme(
      panel.grid.minor  = element_blank(),
      panel.grid.major  = element_line(linewidth = 0.3, color = "grey88"),
      panel.border      = element_rect(color = "grey75", fill = NA, linewidth = 0.4),
      strip.background  = element_blank(),
      strip.text        = element_text(face = "bold", size = rel(0.95)),
      legend.position   = "bottom",
      legend.key.size   = unit(0.8, "lines"),
      axis.ticks        = element_line(linewidth = 0.3, color = "grey60"),
      axis.ticks.length = unit(2.5, "pt")
    )
}

# ------------------------------------------------------------
# LOAD
# ------------------------------------------------------------

gh     <- read.csv(here("analysis", "analysis_inputs", "github_events_with_progress.csv"),
                   stringsAsFactors = FALSE)
msg    <- read.csv(here("analysis", "analysis_inputs", "messages_with_progress.csv"),
                   stringsAsFactors = FALSE)
labels <- read.csv(here("data", "derived", "student_dominant_labels.csv"),
                   stringsAsFactors = FALSE) %>%
  filter(student != "WITHDRAWN", student != "OUT_OF_SPRINT")
peer   <- read.csv(here("data", "derived", "peer_eval_by_sprint.csv"),
                   stringsAsFactors = FALSE)
sprint_analysis <- read.csv(here("analysis", "analysis_inputs", "student_sprint_analysis.csv"),
                   stringsAsFactors = FALSE) %>%
  select(student, sprint, dev_lag) %>%
  distinct(student, sprint, .keep_all = TRUE)

SPRINTS              <- c("Sprint 1", "Sprint 2", "Sprint 3")
DISENGAGEMENT_LABELS <- c("hitchhiker", "couch potato")

# Sprint-specific student → global_id mapping (1-1 within each sprint).
# Six students transferred teams; their team-slot changes across sprints but
# global_id is stable. All outcomes and predictors use global_id as primary key.
gid_map <- gh %>%
  select(student, sprint, global_id) %>%
  distinct() %>%
  mutate(team = sub("_.*", "", student))   # t01_s01 → t01; stable for transfers

# Sprint-level contributor status with global_id attached
sprint_status <- labels %>%
  select(student, sprint, dominant_peer_type, dominant_contributor) %>%
  left_join(gid_map, by = c("student", "sprint")) %>%
  mutate(
    team      = coalesce(team,      sub("_.*", "", student)),  # fill for students with no GH events
    global_id = coalesce(global_id, student)                   # fill stable ID when no GH record
  )

# ------------------------------------------------------------
# HELPER: build outcome for a given source → target sprint pair
# Joins on global_id so team-transfer students are tracked correctly.
# "withdrew" = present in source sprint, absent from target sprint labels.
# ------------------------------------------------------------

build_outcome <- function(source_spr, target_spr) {
  source_students <- sprint_status %>%
    filter(sprint == source_spr) %>%
    select(global_id)

  target_status <- sprint_status %>%
    filter(sprint == target_spr) %>%
    select(global_id, target_contributor = dominant_contributor)

  source_students %>%
    left_join(target_status, by = "global_id") %>%
    mutate(
      risk = as.integer(is.na(target_contributor) | target_contributor == "lower"),
      outcome_ord = factor(
        case_when(
          is.na(target_contributor)       ~ "withdrew",
          target_contributor == "lower"   ~ "lower",
          target_contributor == "higher"  ~ "higher"
        ),
        levels = c("withdrew", "lower", "higher"),
        ordered = TRUE
      )
    )
}

# ------------------------------------------------------------
# HELPER: build predictors for a given sprint, keyed by global_id
# ------------------------------------------------------------

build_predictors <- function(spr) {
  # Students active in this sprint (with their global_id)
  base <- sprint_status %>%
    filter(sprint == spr) %>%
    select(student, global_id, team,
           prev_contributor = dominant_contributor) %>%
    mutate(prev_contributor = as.integer(prev_contributor == "lower"))

  n_gh <- gh %>%
    filter(sprint == spr) %>%
    count(student, name = "n_gh") %>%
    mutate(n_gh = log1p(n_gh))

  # Team-normalized GitHub: log-count minus team mean log-count
  n_gh_rel <- gh %>%
    filter(sprint == spr) %>%
    count(student, name = "n_gh_raw") %>%
    right_join(base %>% select(student, team), by = "student") %>%
    mutate(n_gh_raw = replace_na(n_gh_raw, 0L)) %>%
    group_by(team) %>%
    mutate(n_gh_rel = log1p(n_gh_raw) - mean(log1p(n_gh_raw))) %>%
    ungroup() %>%
    select(student, n_gh_rel)

  any_risk <- peer %>%
    filter(sprint == spr, student != "WITHDRAWN") %>%
    group_by(student) %>%
    summarise(
      any_risk         = as.integer(any(label %in% DISENGAGEMENT_LABELS)),
      pct_peer_risk    = mean(label %in% DISENGAGEMENT_LABELS),
      pct_hitchhiker   = mean(label == "hitchhiker"),
      pct_couch_potato = mean(label == "couch potato"),
      .groups = "drop"
    )

  centroid_gh <- gh %>%
    filter(sprint == spr) %>%
    group_by(student) %>%
    summarise(centroid_gh = mean(spr_progress, na.rm = TRUE), .groups = "drop")

  n_msg <- msg %>%
    filter(sprint == spr) %>%
    count(student, name = "n_msg") %>%
    mutate(n_msg = log1p(n_msg))

  first_gh <- gh %>%
    filter(sprint == spr) %>%
    group_by(student) %>%
    summarise(first_gh = min(spr_progress, na.rm = TRUE), .groups = "drop")

  q4_conc <- gh %>%
    filter(sprint == spr) %>%
    group_by(student) %>%
    summarise(
      q4_conc = mean(spr_progress >= 0.75, na.rm = TRUE),
      .groups = "drop"
    )

  # Skewness of GitHub event timing: positive = back-loaded (procrastination signal)
  gh_skew <- gh %>%
    filter(sprint == spr) %>%
    group_by(student) %>%
    filter(n() >= 3) %>%   # need ≥3 events for stable skewness
    summarise(
      gh_skew = {
        x <- spr_progress
        n <- length(x)
        m <- mean(x); s <- sd(x)
        if (s == 0) 0 else (sum((x - m)^3) / n) / s^3
      },
      .groups = "drop"
    )

  first_dev_msg <- msg %>%
    filter(sprint == spr, thread_type == "DEV") %>%
    group_by(student) %>%
    summarise(first_dev_msg = min(spr_progress, na.rm = TRUE), .groups = "drop")

  first_coord_msg <- msg %>%
    filter(sprint == spr, thread_type == "COORDINATION_ONLY") %>%
    group_by(student) %>%
    summarise(first_coord_msg = min(spr_progress, na.rm = TRUE), .groups = "drop")

  # First message in any DEV or COORDINATION_ONLY thread (not NON_DEV)
  first_discussion_msg <- msg %>%
    filter(sprint == spr, thread_type %in% c("DEV", "COORDINATION_ONLY")) %>%
    group_by(student) %>%
    summarise(first_discussion_msg = min(spr_progress, na.rm = TRUE), .groups = "drop")

  lag <- sprint_analysis %>%
    filter(sprint == spr) %>%
    select(student, dev_lag)

  base %>%
    left_join(n_gh,                by = "student") %>%
    left_join(any_risk,            by = "student") %>%
    left_join(centroid_gh,         by = "student") %>%
    left_join(n_msg,               by = "student") %>%
    left_join(first_gh,            by = "student") %>%
    left_join(first_dev_msg,       by = "student") %>%
    left_join(first_coord_msg,     by = "student") %>%
    left_join(first_discussion_msg,by = "student") %>%
    left_join(n_gh_rel,            by = "student") %>%
    left_join(q4_conc,             by = "student") %>%
    left_join(gh_skew,             by = "student") %>%
    mutate(
      n_gh                 = replace_na(n_gh, 0),
      any_risk             = as.integer(replace_na(any_risk, 0L)),
      pct_peer_risk        = replace_na(pct_peer_risk, 0),
      pct_hitchhiker       = replace_na(pct_hitchhiker, 0),
      pct_couch_potato     = replace_na(pct_couch_potato, 0),
      centroid_gh          = replace_na(centroid_gh, 1.0),
      n_msg                = replace_na(n_msg, 0),
      first_gh             = replace_na(first_gh, 1.0),
      first_dev_msg        = replace_na(first_dev_msg, 1.0),
      first_coord_msg      = replace_na(first_coord_msg, 1.0),
      first_discussion_msg = replace_na(first_discussion_msg, 1.0),
      q4_conc              = replace_na(q4_conc, 0),
      gh_skew              = replace_na(gh_skew, 0)   # 0 = symmetric (no events / <3 events)
    ) %>%
    select(-student)    # drop team-slot; global_id + team are the join/grouping keys
}

# ------------------------------------------------------------
# HELPER: cluster-robust sandwich SEs for a logistf fit
# Returns a data frame with one row per coefficient:
#   term, coef (log-OR), se_cr, z_cr, p_cr, ci_lo, ci_hi (log scale)
# ------------------------------------------------------------

firth_crse <- function(fit, data, cluster_var) {
  mf       <- model.frame(fit$formula, data = data)
  X        <- model.matrix(fit$formula, data = mf)
  y        <- model.response(mf)
  pi_hat   <- as.vector(plogis(X %*% coef(fit)))
  scores   <- sweep(X, 1, as.numeric(y - pi_hat), `*`)
  clusters <- data[rownames(mf), cluster_var]

  G <- length(unique(clusters))
  n <- nrow(mf)
  p <- ncol(X)

  meat <- matrix(0, p, p)
  for (g in unique(clusters)) {
    s_g  <- colSums(scores[clusters == g, , drop = FALSE])
    meat <- meat + outer(s_g, s_g)
  }

  # Small-sample HC correction (G/(G-1) * (n-1)/(n-p))
  correction <- (G / (G - 1)) * ((n - 1) / (n - p))
  bread <- as.matrix(fit$var)
  V_cr  <- bread %*% meat %*% bread * correction
  se_cr <- sqrt(diag(V_cr))
  coefs <- coef(fit)
  z_cr  <- coefs / se_cr
  p_cr  <- 2 * pnorm(-abs(z_cr))

  data.frame(
    term  = names(coefs),
    coef  = coefs,
    se_cr = se_cr,
    z_cr  = z_cr,
    p_cr  = p_cr,
    ci_lo = coefs - 1.96 * se_cr,
    ci_hi = coefs + 1.96 * se_cr,
    row.names = NULL
  )
}

# ------------------------------------------------------------
# HELPER: leave-one-out cross-validated AUC for a logistf model
# ------------------------------------------------------------

loocv_preds <- function(formula, data) {
  fmla  <- as.formula(formula)
  rhs   <- delete.response(terms(fmla))
  n     <- nrow(data)
  preds <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    fit <- tryCatch(
      logistf(fmla, data = data[-i, ], firth = TRUE, family = binomial),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    X_i <- tryCatch(model.matrix(rhs, data = data[i, , drop = FALSE]),
                    error = function(e) NULL)
    if (is.null(X_i)) next
    preds[i] <- plogis(drop(X_i %*% coef(fit)))
  }
  preds
}

loocv_auc <- function(formula, data) {
  preds <- loocv_preds(formula, data)
  valid <- !is.na(preds)
  round(as.numeric(auc(data$risk[valid], preds[valid], quiet = TRUE)), 3)
}

# ------------------------------------------------------------
# HELPER: run Firth + PPO, print diagnostics, write tables/figures
# ------------------------------------------------------------

run_risk_models <- function(preds, outcome_df, spr_label, source_spr) {

  model_data <- outcome_df %>%
    left_join(preds, by = "global_id")

  message(sprintf("\n  Outcome counts [%s]: %s",
                  spr_label,
                  paste(names(table(model_data$outcome_ord)),
                        table(model_data$outcome_ord), sep = "=", collapse = ", ")))

  # ── Firth logistic: primary model ───────────────────────
  message(sprintf("\n=== Firth logistic: %s ===", spr_label))

  fit_firth <- logistf(
    risk ~ n_gh + any_risk,
    data   = model_data,
    firth  = TRUE,
    family = binomial
  )
  summary(fit_firth)

  lr_stat <- 2 * (fit_firth$loglik[1] - fit_firth$loglik[2])
  lr_df   <- length(coef(fit_firth)) - 1
  lr_pval <- pchisq(lr_stat, df = lr_df, lower.tail = FALSE)
  message(sprintf("Firth LR: chi2(%d) = %.2f, p = %.4f | AIC = %.1f",
                  lr_df, lr_stat, lr_pval,
                  -2 * fit_firth$loglik[1] + 2 * length(coef(fit_firth))))

  n_teams  <- n_distinct(model_data$team)
  cr       <- firth_crse(fit_firth, model_data, "team")
  loo_base <- loocv_auc(risk ~ n_gh + any_risk, model_data)
  message(sprintf("Cluster-robust SEs: %d teams | LOO-AUC (base): %.3f", n_teams, loo_base))

  invisible(list(firth = fit_firth, cr = cr, loo_auc = loo_base, n_teams = n_teams))
}

# ------------------------------------------------------------
# RUN: Sprint 1 → Sprint 2
# ------------------------------------------------------------

preds_s1     <- build_predictors("Sprint 1")
outcome_s1s2 <- build_outcome("Sprint 1", "Sprint 2")
res_s1s2     <- run_risk_models(preds_s1, outcome_s1s2, "S1S2", "Sprint 1")

# ------------------------------------------------------------
# RUN: Sprint 1 → Sprint 3
# ------------------------------------------------------------

outcome_s1s3 <- build_outcome("Sprint 1", "Sprint 3")
res_s1s3     <- run_risk_models(preds_s1, outcome_s1s3, "S1S3", "Sprint 1")

# ------------------------------------------------------------
# RUN: Sprint 2 → Sprint 3
# ------------------------------------------------------------

preds_s2     <- build_predictors("Sprint 2")
outcome_s2s3 <- build_outcome("Sprint 2", "Sprint 3")
res_s2s3     <- run_risk_models(preds_s2, outcome_s2s3, "S2S3", "Sprint 2")

# ------------------------------------------------------------
# FIGURE: firth_risk_curves.png
# Predicted risk from Model 1 (n_gh + any_risk) and
# Model 2 (any_risk + first_coord_msg) for S1→S2 and S2→S3
# ------------------------------------------------------------

# Build predicted risk curves for all three transitions
# x-axis: raw GitHub event count (back-transformed); lines split by peer flag
# S1→S3 uses n_gh only (peer flag adds no signal at 2-sprint horizon)

risk_curve_specs <- list(
  list(preds=preds_s1, outcome=outcome_s1s2, label="Sprint 1 → Sprint 2"),
  list(preds=preds_s1, outcome=outcome_s1s3, label="Sprint 1 → Sprint 3"),
  list(preds=preds_s2, outcome=outcome_s2s3, label="Sprint 2 → Sprint 3")
)

risk_curve_data <- bind_rows(lapply(risk_curve_specs, function(x) {
  md  <- x$outcome %>% left_join(x$preds, by = "global_id")
  fit <- logistf(risk ~ n_gh + any_risk, data=md, firth=TRUE, family=binomial)

  grid <- expand.grid(
    n_gh     = seq(min(md$n_gh), max(md$n_gh), length.out = 200),
    any_risk = c(0L, 1L)
  )
  grid$pred <- plogis(coef(fit)["(Intercept)"] +
                      coef(fit)["n_gh"]     * grid$n_gh +
                      coef(fit)["any_risk"] * grid$any_risk)
  grid$gh_events  <- expm1(grid$n_gh)
  grid$transition <- x$label
  grid
})) %>%
  mutate(
    peer_label = factor(any_risk, levels=c(0L,1L),
                        labels=c("No peer flag","Peer-flagged at risk")),
    transition = factor(transition,
                        levels = c("Sprint 1 → Sprint 2",
                                   "Sprint 1 → Sprint 3",
                                   "Sprint 2 → Sprint 3"))
  )

ggplot(risk_curve_data,
       aes(x = gh_events, y = pred, color = peer_label, linetype = peer_label)) +
  geom_line(linewidth = 0.75) +
  facet_wrap(~ transition, nrow = 1) +
  scale_color_manual(values = c("No peer flag"=CLR_HIGHER, "Peer-flagged at risk"=CLR_LOWER)) +
  scale_linetype_manual(values = c("No peer flag"="solid", "Peer-flagged at risk"="dashed")) +
  scale_x_continuous(breaks = c(0, 50, 150, 300, 500),
                     labels = c("0","50","150","300","500")) +
  scale_y_continuous(labels = scales::percent_format(accuracy = 1),
                     limits = c(0, 1)) +
  labs(x     = "GitHub events in current sprint (count)",
       y     = "Predicted probability of low contribution\nor withdrawal next sprint",
       color = NULL, linetype = NULL) +
  theme_paper(base_size = 9) +
  theme(
    legend.position  = "bottom",
    legend.key.size  = unit(0.7, "lines"),
    legend.text      = element_text(size = rel(0.88)),
    strip.text       = element_text(size = rel(0.92)),
    panel.spacing    = unit(0.5, "lines"),
    plot.margin      = margin(2, 3, 1, 2, "mm")
  )

ggsave(here("Figures", "firth_risk_curves.png"),
       width = 7, height = 3.2, dpi = 600)

# ------------------------------------------------------------
# COMBINED TABLE: firth_risk_combined.tex
# Three transitions side by side (S1→S2, S2→S3, S1→S3)
# ------------------------------------------------------------

fmt_p_firth_comb <- function(p) {
  stars <- if (p < .001) "***" else if (p < .01) "**" else if (p < .05) "*" else ""
  label <- if (p < .001) "$< .001$" else sprintf("%.3f", p)
  paste0(label, stars)
}

fmt_or_comb <- function(cr, term) {
  r <- cr[cr$term == term, ]
  if (nrow(r) == 0) return("---")
  sprintf("%.2f [%.2f, %.2f]", exp(r$coef), exp(r$ci_lo), exp(r$ci_hi))
}

fmt_p_comb <- function(cr, term) {
  r <- cr[cr$term == term, ]
  if (nrow(r) == 0) return("---")
  fmt_p_firth_comb(r$p_cr)
}

transitions <- list(
  list(res = res_s1s2, label = "S1$\\to$S2"),
  list(res = res_s2s3, label = "S2$\\to$S3"),
  list(res = res_s1s3, label = "S1$\\to$S3")
)

predictors_comb <- list(
  list(key = "n_gh",     label = "GitHub events (log)"),
  list(key = "any_risk", label = "Any peer-risk flag")
)

header_cols <- paste(
  sapply(transitions, function(t)
    paste0("\\multicolumn{2}{c}{\\textbf{", t$label, "}}")),
  collapse = " & "
)
cmidrule <- paste(
  c("\\cmidrule(lr){2-3}", "\\cmidrule(lr){4-5}", "\\cmidrule(lr){6-7}"),
  collapse = " "
)
subheader <- paste(
  rep("\\textbf{OR [95\\% CI]} & \\textbf{p}", 3),
  collapse = " & "
)

comb_lines <- c(
  "\\begin{table}[ht]",
  "\\centering",
  "\\scriptsize",
  "\\setlength{\\tabcolsep}{4pt}",
  "\\renewcommand{\\arraystretch}{0.88}",
  "\\caption{Firth-penalized logistic regression predicting low contribution or withdrawal across sprint transitions (cluster-robust SEs, 24 teams). GitHub events are log-transformed; peer-risk flag indicates any peer evaluation of hitchhiker or couch potato in the current sprint.}",
  "\\label{tab:firth_combined}",
  "\\begin{tabular}{l r r r r r r}",
  "\\toprule",
  paste0("\\textbf{Predictor} & ", header_cols, " \\\\"),
  cmidrule,
  paste0(" & ", subheader, " \\\\"),
  "\\midrule"
)

for (pred in predictors_comb) {
  row_cells <- sapply(transitions, function(t)
    paste0(fmt_or_comb(t$res$cr, pred$key), " & ", fmt_p_comb(t$res$cr, pred$key))
  )
  comb_lines <- c(comb_lines,
    paste0(pred$label, " & ", paste(row_cells, collapse = " & "), " \\\\"))
}

auc_cells <- paste(
  sapply(transitions, function(t) sprintf("\\multicolumn{2}{c}{%.3f}", t$res$loo_auc)),
  collapse = " & "
)
comb_lines <- c(comb_lines,
  "\\midrule",
  paste0("LOO-AUC & ", auc_cells, " \\\\"),
  "\\midrule",
  "\\multicolumn{7}{l}{\\textit{Note.} * $p < .05$; ** $p < .01$; *** $p < .001$} \\\\",
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{table}"
)
writeLines(comb_lines, here("Tables", "firth_risk_combined.tex"))
message("firth_risk_combined.tex written.")

message("04_early_risk.R complete.")
