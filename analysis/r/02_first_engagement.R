library(dplyr)
library(tidyr)
library(ggplot2)
library(survival)
library(ARTool)
library(xtable)
library(here)

dir.create(here("Figures"), showWarnings = FALSE)
dir.create(here("Tables"),  showWarnings = FALSE)

# ── Design system ──────────────────────────────────────────────
CLR_HIGHER <- "#0072B2"
CLR_LOWER  <- "#D55E00"
CLR_PEER   <- c(
  "good teammate" = "#009E73",
  "lone wolf"     = "#56B4E9",
  "couch potato"  = "#E69F00",
  "hitchhiker"    = "#D55E00"
)

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

gh <- read.csv(here("analysis", "analysis_inputs", "github_events_with_progress.csv"),
               stringsAsFactors = FALSE)
labels <- read.csv(here("data", "derived", "student_dominant_labels.csv"),
                   stringsAsFactors = FALSE) %>%
  filter(student != "WITHDRAWN", student != "OUT_OF_SPRINT")

EVENT_TYPES <- c("commit", "issue_opened", "pr_opened", "pr_review")
SPRINTS     <- c("Sprint 1", "Sprint 2", "Sprint 3")

# First engagement per student × sprint × event_type
first_gh <- gh %>%
  group_by(student, sprint, event_type) %>%
  summarise(first_spr = min(spr_progress, na.rm = TRUE), .groups = "drop")

# All student-sprint-event_type combinations with labels
all_combos <- labels %>%
  filter(!is.na(dominant_contributor)) %>%
  select(student, sprint, dominant_peer_type, dominant_contributor) %>%
  crossing(event_type = EVENT_TYPES)

# Join; students with no events get first_spr = NA (censored)
surv_data <- all_combos %>%
  left_join(first_gh, by = c("student", "sprint", "event_type")) %>%
  mutate(
    engaged = as.integer(!is.na(first_spr)),
    time    = if_else(is.na(first_spr), 1.0, first_spr),
    sprint  = factor(sprint, levels = SPRINTS, ordered = TRUE),
    dominant_peer_type   = factor(dominant_peer_type,
      levels = c("good teammate", "lone wolf", "couch potato", "hitchhiker")),
    dominant_contributor = factor(dominant_contributor, levels = c("higher", "lower"))
  )

# ------------------------------------------------------------
# FIGURE: engagement_survival_by_event.png
# Survival curves (1 – ECDF) by contributor group, per event type
# Narrower CI bands reflect less variability among higher contributors
# ------------------------------------------------------------

event_labels <- c(
  commit       = "Commit",
  issue_opened = "Issue Opened",
  pr_opened    = "PR Opened",
  pr_review    = "PR Review"
)

surv_long <- surv_data %>%
  mutate(event_type = factor(event_type, levels = EVENT_TYPES,
                             labels = event_labels))

# Compute survival curves and log-rank p-values per event type
surv_list <- lapply(levels(surv_long$event_type), function(et) {
  sub <- surv_long %>% filter(event_type == et)
  fit <- survfit(Surv(time, engaged) ~ dominant_contributor, data = sub)
  broom::tidy(fit) %>% mutate(event_type = et)
})
surv_df <- bind_rows(surv_list)

logrank_pvals <- bind_rows(lapply(levels(surv_long$event_type), function(et) {
  sub  <- surv_long %>% filter(event_type == et)
  test <- survdiff(Surv(time, engaged) ~ dominant_contributor, data = sub)
  pval <- pchisq(test$chisq, df = length(test$n) - 1, lower.tail = FALSE)
  label <- if (pval < .001) "p < 0.001" else sprintf("p = %.3f", pval)
  data.frame(event_type = et, label = label)
}))

ggplot(surv_df, aes(x = time, y = estimate,
                    color = strata, fill = strata)) +
  geom_ribbon(aes(ymin = conf.low, ymax = conf.high), alpha = .18, color = NA) +
  geom_step(linewidth = .45) +
  geom_text(data = logrank_pvals,
            aes(x = 0.05, y = 0.06, label = label),
            inherit.aes = FALSE,
            hjust = 0, size = 2.5, color = "grey30", fontface = "italic") +
  facet_wrap(~event_type, nrow = 1) +
  scale_color_manual(values = c(
    "dominant_contributor=higher" = CLR_HIGHER,
    "dominant_contributor=lower"  = CLR_LOWER
  ), labels = c("Higher", "Lower")) +
  scale_fill_manual(values = c(
    "dominant_contributor=higher" = CLR_HIGHER,
    "dominant_contributor=lower"  = CLR_LOWER
  ), labels = c("Higher", "Lower")) +
  scale_x_continuous(labels = scales::percent_format(), breaks = c(0, .5, 1)) +
  scale_y_continuous(labels = scales::percent_format()) +
  labs(x = "Normalized sprint progression",
       y = "Proportion not yet engaged",
       color = "Contributor type", fill = "Contributor type") +
  theme_paper(base_size = 9) +
  theme(
    axis.text.x      = element_text(size = rel(0.85)),
    legend.key.size  = unit(0.6, "lines"),
    plot.margin      = margin(2, 2, 1, 2, "mm"),
    panel.spacing    = unit(0.3, "lines")
  )

ggsave(here("Figures", "engagement_survival_by_event.png"),
       width = 7, height = 2.6, dpi = 600)

# ------------------------------------------------------------
# TABLE: log_rank_git.tex
# Log-rank test: higher vs lower first engagement, per event type
# ------------------------------------------------------------

fmt_p_lr <- function(p) {
  stars <- if (p < .001) "***" else if (p < .01) "**" else if (p < .05) "*" else ""
  label <- if (p < .001) "$< .001$" else sprintf("%.3f", p)
  paste0(label, stars)
}

logrank_rows <- lapply(EVENT_TYPES, function(et) {
  sub  <- surv_data %>% filter(event_type == et)
  test <- survdiff(Surv(time, engaged) ~ dominant_contributor, data = sub)
  pval <- pchisq(test$chisq, df = length(test$n) - 1, lower.tail = FALSE)
  et_label <- c(commit = "Commit", issue_opened = "Issue Opened",
                pr_opened = "PR Opened", pr_review = "PR Review")[et]
  list(et = et_label, chisq = round(test$chisq, 2), pval = pval)
})

lr_lines <- c(
  "\\begin{table}[ht]",
  "\\centering",
  "\\scriptsize",
  "\\setlength{\\tabcolsep}{4pt}",
  "\\renewcommand{\\arraystretch}{0.88}",
  "\\caption{Log-rank test of time to first GitHub engagement by contributor group (higher vs.\\ lower).}",
  "\\label{tab:logrank_git}",
  "\\begin{tabular}{l r r}",
  "\\toprule",
  "\\textbf{Event type} & \\textbf{$\\chi^2$} & \\textbf{p-value} \\\\",
  "\\midrule"
)
for (r in logrank_rows) {
  lr_lines <- c(lr_lines,
    paste0(r$et, " & ", r$chisq, " & ", fmt_p_lr(r$pval), " \\\\"))
}
lr_lines <- c(lr_lines,
  "\\midrule",
  "\\multicolumn{3}{l}{\\textit{Note.} * $p < .05$; ** $p < .01$; *** $p < .001$} \\\\",
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{table}"
)
writeLines(lr_lines, here("Tables", "log_rank_git.tex"))

# ------------------------------------------------------------
# TABLE: anova_first_git.tex
# ART ANOVA: first_spr ~ contributor × event_type × sprint
# ------------------------------------------------------------

art_data <- surv_data %>%
  filter(engaged == 1) %>%
  mutate(
    sprint     = factor(sprint, levels = SPRINTS, ordered = TRUE),
    event_type = factor(event_type)
  )

m_first <- art(
  time ~ dominant_contributor * event_type * sprint,
  data = art_data
)

first_anova_raw <- tryCatch(
  anova(m_first) %>% as.data.frame(),
  error = function(e) {
    fmla   <- as.formula(deparse(m_first$call$formula))
    tterms <- attr(terms(fmla), "term.labels")
    bind_rows(lapply(tterms, function(tm) {
      tryCatch({
        a <- anova(m_first, response = tm)
        data.frame(Term = tm, Df = a$Df[1], Df.res = a$Df[2],
                   F = a$`F value`[1], `Pr(>F)` = a$`Pr(>F)`[1],
                   check.names = FALSE)
      }, error = function(e2) {
        data.frame(Term = tm, Df = NA, Df.res = NA, F = NA,
                   `Pr(>F)` = NA, check.names = FALSE)
      })
    }))
  }
)
fmt_p_fa <- function(p) {
  if (is.na(p)) return("---")
  stars <- if (p < .001) "***" else if (p < .01) "**" else if (p < .05) "*" else ""
  label <- if (p < .001) "$< .001$" else sprintf("%.3f", p)
  paste0(label, stars)
}

clean_effect_fa <- function(nm) {
  nm <- gsub("dominant_contributor", "Contributor group", nm)
  nm <- gsub("event_type",           "Event type",        nm)
  nm <- gsub("sprint",               "Sprint",            nm)
  nm <- gsub(":",                    " $\\\\times$ ",     nm)
  nm
}

f_col <- grep("^F", names(first_anova_raw), value = TRUE)[1]
p_col <- grep("^Pr",  names(first_anova_raw), value = TRUE)[1]
first_anova <- first_anova_raw

fa_lines <- c(
  "\\begin{table}[ht]",
  "\\centering",
  "\\footnotesize",
  "\\caption{ART ANOVA: normalized sprint progression of first GitHub engagement by contributor group.}",
  "\\label{tab:anova_first_git}",
  "\\begin{tabular}{l r r r}",
  "\\toprule",
  "\\textbf{Effect} & \\textbf{df} & \\textbf{F} & \\textbf{p-value} \\\\",
  "\\midrule"
)
for (i in seq_len(nrow(first_anova))) {
  r    <- first_anova[i, ]
  eff  <- clean_effect_fa(as.character(r[["Term"]]))
  df   <- if (is.na(r[["Df"]])) "---" else as.character(r[["Df"]])
  fval <- if (is.na(r[[f_col]])) "---" else sprintf("%.2f", r[[f_col]])
  pval <- fmt_p_fa(r[[p_col]])
  fa_lines <- c(fa_lines, paste0(eff, " & ", df, " & ", fval, " & ", pval, " \\\\"))
}
fa_lines <- c(fa_lines,
  "\\midrule",
  "\\multicolumn{4}{l}{\\textit{Note.} * $p < .05$; ** $p < .01$; *** $p < .001$} \\\\",
  "\\bottomrule",
  "\\end{tabular}",
  "\\end{table}"
)
writeLines(fa_lines, here("Tables", "anova_first_git.tex"))

message("02_first_engagement.R complete.")
