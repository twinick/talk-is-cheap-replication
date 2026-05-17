library(dplyr)
library(tidyr)
library(ggplot2)
library(lmtest)
library(sandwich)
library(xtable)
library(here)
library(ARTool)
library(emmeans)

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

msg <- read.csv(here("analysis", "analysis_inputs", "messages_with_progress.csv"),
                stringsAsFactors = FALSE)
gh  <- read.csv(here("analysis", "analysis_inputs", "github_events_with_progress.csv"),
                stringsAsFactors = FALSE)
labels <- read.csv(here("data", "derived", "student_dominant_labels.csv"),
                   stringsAsFactors = FALSE) %>%
  filter(student != "WITHDRAWN", student != "OUT_OF_SPRINT")

SPRINTS     <- c("Sprint 1", "Sprint 2", "Sprint 3")
EVENT_TYPES <- c("commit", "issue_opened", "pr_opened", "pr_review")
event_labels <- c(commit="Commit", issue_opened="Issue Opened",
                  pr_opened="PR Opened", pr_review="PR Review")

# ─────────────────────────────────────────────────────────────
# LAG MODEL: OLS + HC3 robust SEs
# lag ~ contributor + quarter + sprint + contributor:quarter
# Unit of analysis: student × sprint × quarter
# Reference categories: higher contributor, Q1, Sprint 1
# TABLE: lag_model.tex
# FIGURE: lag_interaction.png
# ─────────────────────────────────────────────────────────────

gh_quarter <- gh %>%
  filter(!is.na(quarter)) %>%
  group_by(student, sprint, quarter) %>%
  summarise(gh_centroid = mean(spr_progress, na.rm = TRUE), .groups = "drop")

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

# OLS model with HC3 robust standard errors
m_lag <- lm(
  dev_lag ~ dominant_contributor + quarter + sprint +
            dominant_contributor:quarter,
  data = lag_quarter
)

vcov_hc3 <- vcovHC(m_lag, type = "HC3")
vcov_use  <- if (any(is.nan(diag(vcov_hc3)))) vcovHC(m_lag, type = "HC1") else vcov_hc3
ct <- coeftest(m_lag, vcov = vcov_use)
r2 <- summary(m_lag)$r.squared
n  <- nobs(m_lag)

message(sprintf("Lag OLS: N=%d, R2=%.3f", n, r2))
print(ct)

# Format coefficient table for LaTeX (matching paper's lag_model.tex)
ct_df <- data.frame(
    term     = rownames(ct),
    Estimate = ct[, "Estimate"],
    SE       = ct[, "Std. Error"],
    p        = ct[, "Pr(>|t|)"],
    stringsAsFactors = FALSE
  ) %>%
  filter(term != "(Intercept)") %>%
  mutate(
    term = recode(term,
      "dominant_contributorlower"               = "Lower contributor",
      "quarterQ2"                               = "Sprint quarter Q2",
      "quarterQ3"                               = "Sprint quarter Q3",
      "quarterQ4"                               = "Sprint quarter Q4",
      "sprintSprint 2"                          = "Sprint 2",
      "sprintSprint 3"                          = "Sprint 3",
      "dominant_contributorlower:quarterQ2"     = "Lower contributor $\\times$ Q2",
      "dominant_contributorlower:quarterQ3"     = "Lower contributor $\\times$ Q3",
      "dominant_contributorlower:quarterQ4"     = "Lower contributor $\\times$ Q4"
    ),
    sig     = ifelse(p < .01, "**", ifelse(p < .05, "*", "")),
    coef_se = sprintf("%.3f%s (%.3f)", Estimate, sig, SE)
  ) %>%
  select(term, coef_se)

# Write lag model table manually (matches paper table format)
lag_lines <- c(
  "\\begin{table}[ht]",
  "\\centering",
  "\\scriptsize",
  "\\setlength{\\tabcolsep}{4pt}",
  "\\renewcommand{\\arraystretch}{0.88}",
  "\\caption{OLS regression of discussion--implementation lag by contributor role and sprint phase (HC3 robust SEs).}",
  "\\label{tab:lag_model}",
  "\\begin{tabular}{l r}",
  "\\toprule",
  " & \\textbf{Lag (coef / SE)} \\\\",
  "\\midrule"
)
for (i in seq_len(nrow(ct_df))) {
  lag_lines <- c(lag_lines,
    paste0(ct_df$term[i], " & ", ct_df$coef_se[i], " \\\\"))
}
lag_lines <- c(lag_lines,
  "\\midrule",
  paste0("$N$ & ", n, " \\\\"),
  paste0("$R^2$ & ", sprintf("%.3f", r2), " \\\\"),
  "\\midrule",
  "\\multicolumn{2}{l}{\\textit{Note.} * $p < .05$; ** $p < .01$} \\\\",
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{table}"
)
writeLines(lag_lines, here("Tables", "lag_model.tex"))

# FIGURE: lag_interaction.png
lag_q_summary <- lag_quarter %>%
  group_by(quarter, dominant_contributor) %>%
  summarise(
    med = median(dev_lag, na.rm = TRUE),
    q25 = quantile(dev_lag, .25, na.rm = TRUE),
    q75 = quantile(dev_lag, .75, na.rm = TRUE),
    .groups = "drop"
  )


ggplot(lag_q_summary,
       aes(x = quarter, y = med,
           color = dominant_contributor, group = dominant_contributor)) +
  geom_hline(yintercept = 0, linetype = "dashed", linewidth = 0.4, color = "grey55") +
  geom_line(linewidth = 1) +
  geom_point(size = 2.5) +
  geom_errorbar(aes(ymin = q25, ymax = q75), width = .18, linewidth = 0.55) +
  scale_color_manual(values = c(higher = CLR_HIGHER, lower = CLR_LOWER),
                     labels = c(higher = "Higher", lower = "Lower")) +
  labs(x = "Sprint quarter",
       y = "Median lag\n(GitHub centroid − discussion centroid)",
       color = "Contributor type") +
  theme_paper() +
  theme(legend.title = element_text(size = rel(0.9)))

ggsave(here("Figures", "lag_interaction.png"), width = 5, height = 3.5, dpi = 600)

# ─────────────────────────────────────────────────────────────
# ART ANOVA: within-sprint lag
# Panel A: lag ~ dominant_contributor * sprint  (no sig effects)
# Panel B: lag ~ quarter  (significant; post-hoc Tukey)
# TABLE: art_anova_lag.tex
# ─────────────────────────────────────────────────────────────

fmt_p_lag <- function(p) {
  if (is.na(p)) return("---")
  stars <- if (p < .001) "***" else if (p < .01) "**" else if (p < .05) "*" else ""
  label <- if (p < .001) "$< .001$" else sprintf("%.3f", p)
  paste0(label, stars)
}

extract_art_row <- function(model, term) {
  alm <- artlm(model, term)
  av  <- anova(alm)
  df1  <- av[term, "Df"]
  df2  <- av["Residuals", "Df"]
  fval <- av[term, "F value"]
  pval <- av[term, "Pr(>F)"]
  list(df1 = df1, df2 = df2, F = fval, p = pval)
}

# ── Panel A: contributor × sprint ────────────────────────────
m_contr <- art(dev_lag ~ dominant_contributor * sprint, data = lag_quarter)
a_contr  <- extract_art_row(m_contr, "dominant_contributor")
a_sprint <- extract_art_row(m_contr, "sprint")
a_inter  <- extract_art_row(m_contr, "dominant_contributor:sprint")

message(sprintf("Panel A — contributor: F(%d,%d)=%.2f p=%.3f | sprint: F(%d,%d)=%.2f p=%.3f | interaction: F(%d,%d)=%.2f p=%.3f",
  a_contr$df1,  a_contr$df2,  a_contr$F,  a_contr$p,
  a_sprint$df1, a_sprint$df2, a_sprint$F, a_sprint$p,
  a_inter$df1,  a_inter$df2,  a_inter$F,  a_inter$p))

# ── Panel B: quarter main effect + post-hoc ──────────────────
m_qtr  <- art(dev_lag ~ quarter, data = lag_quarter)
a_qtr  <- extract_art_row(m_qtr, "quarter")

message(sprintf("Panel B — quarter: F(%d,%d)=%.2f p=%.4f",
  a_qtr$df1, a_qtr$df2, a_qtr$F, a_qtr$p))

em_qtr    <- emmeans(artlm(m_qtr, "quarter"), ~ quarter)
contr_qtr <- as.data.frame(summary(contrast(em_qtr, method = "pairwise", adjust = "tukey")))
print(contr_qtr[, c("contrast", "t.ratio", "p.value")])

# ── Build LaTeX table (side-by-side: ANOVA left | Tukey right) ───────────────
# 8 columns: Effect df df_res F p | Contrast t p
# Use table* in the paper for full-width; swap to table for single-column fit.

anova_rows <- list(
  list(label = "\\multicolumn{5}{l}{\\textbf{Panel A: Contributor group $\\times$ Sprint}}"),
  list(label = "Contributor group",          r = a_contr),
  list(label = "Sprint",                     r = a_sprint),
  list(label = "Contributor $\\times$ Sprint", r = a_inter),
  list(label = "\\multicolumn{5}{l}{\\textbf{Panel B: Sprint quarter}}"),
  list(label = "Quarter",                    r = a_qtr)
)

tukey_rows <- contr_qtr  # 6 rows

# Pad anova_rows to same length as tukey_rows (6) with blanks
while (length(anova_rows) < nrow(tukey_rows)) {
  anova_rows <- c(anova_rows, list(list(label = "")))
}

lines <- c(
  "\\begin{table}[ht]",   # switch to table* if full-width needed
  "\\centering",
  "\\scriptsize",
  "\\setlength{\\tabcolsep}{4pt}",
  "\\renewcommand{\\arraystretch}{0.88}",
  "\\caption{ART ANOVA (left) and Tukey post-hoc contrasts (right) for within-sprint discussion--implementation lag. Panel A: contributor group and sprint (all non-significant). Panel B: sprint quarter.}",
  "\\label{tab:art_anova_lag}",
  "\\begin{tabular}{l r r r r @{\\hskip 8pt} l r r}",
  "\\toprule",
  paste0("\\multicolumn{5}{c}{\\textbf{ART ANOVA}}",
         " & \\multicolumn{3}{c}{\\textbf{Tukey Contrasts}} \\\\"),
  "\\cmidrule(r){1-5} \\cmidrule(l){6-8}",
  paste0("\\textbf{Effect} & \\textbf{df} & \\textbf{df\\textsubscript{res}}",
         " & \\textbf{F} & \\textbf{p}",
         " & \\textbf{Contrast} & \\textbf{t} & \\textbf{p} \\\\"),
  "\\midrule"
)

for (i in seq_len(nrow(tukey_rows))) {
  ar <- anova_rows[[i]]
  tr <- tukey_rows[i, ]

  right <- paste0(tr$contrast, " & ", sprintf("%.2f", tr$t.ratio),
                  " & ", fmt_p_lag(tr$p.value), " \\\\")

  if (!is.null(ar$r)) {
    # normal data row: 5 ANOVA cells + 3 Tukey cells = 8
    left <- paste0(ar$label, " & ", ar$r$df1, " & ", ar$r$df2,
                   " & ", sprintf("%.2f", ar$r$F),
                   " & ", fmt_p_lag(ar$r$p))
    lines <- c(lines, paste0(left, " & ", right))
  } else if (grepl("multicolumn", ar$label)) {
    # multicolumn{5} already fills cols 1-5; directly append cols 6-8
    lines <- c(lines, paste0(ar$label, " & ", right))
    # insert a midrule after Panel A header group (before Panel B header)
    if (grepl("Panel B", ar$label)) {
      lines <- c(lines[seq_len(length(lines) - 1)],
                 "\\midrule",
                 lines[length(lines)])
    }
  } else {
    # blank left side
    lines <- c(lines, paste0(" & & & & & ", right))
  }
}

lines <- c(lines,
  "\\midrule",
  paste0("\\multicolumn{8}{l}{\\textit{Note.} * $p < .05$;",
         " ** $p < .01$; *** $p < .001$} \\\\"),
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{table}"
)
writeLines(lines, here("Tables", "art_anova_lag.tex"))
message("art_anova_lag.tex written.")

message("03_coordination_lag.R complete.")
