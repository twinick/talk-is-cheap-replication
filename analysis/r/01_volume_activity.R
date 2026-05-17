library(dplyr)
library(tidyr)
library(ggplot2)
library(ARTool)
library(emmeans)
library(xtable)
library(here)
library(lubridate)
library(ragg)

dir.create(here("Figures"), showWarnings = FALSE)
dir.create(here("Tables"),  showWarnings = FALSE)

# ── Design system ──────────────────────────────────────────────
CLR_HIGHER <- "#0072B2"   # Okabe-Ito blue
CLR_LOWER  <- "#D55E00"   # Okabe-Ito vermilion
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

gh     <- read.csv(here("analysis", "analysis_inputs", "github_events_with_progress.csv"),
                   stringsAsFactors = FALSE)
msg    <- read.csv(here("analysis", "analysis_inputs", "messages_with_progress.csv"),
                   stringsAsFactors = FALSE)
labels <- read.csv(here("data", "derived", "student_dominant_labels.csv"),
                   stringsAsFactors = FALSE) %>%
  filter(student != "WITHDRAWN", student != "OUT_OF_SPRINT")

gh$gh_time   <- as.POSIXct(gh$gh_time,   tz = "UTC")
msg$msg_time <- as.POSIXct(msg$msg_time,  tz = "UTC")

gh  <- left_join(gh,  labels, by = c("student", "sprint"))
msg <- left_join(msg, labels, by = c("student", "sprint"))

# ------------------------------------------------------------
# FIGURE: median_weekly.png
# Median weekly activity counts by contributor type
# ------------------------------------------------------------

course_start <- as.POSIXct("2024-01-15", tz = "UTC")

summarise_weekly <- function(df, time_col, contributor_col) {
  df %>%
    filter(!is.na(.data[[contributor_col]])) %>%
    mutate(week = as.integer(floor(
      as.numeric(difftime(.data[[time_col]], course_start, units = "weeks"))
    ))) %>%
    count(student, week, .data[[contributor_col]]) %>%
    group_by(week, .data[[contributor_col]]) %>%
    summarise(med = median(n), q25 = quantile(n, .25), q75 = quantile(n, .75),
              .groups = "drop") %>%
    rename(dominant_contributor = .data[[contributor_col]])
}

gh_w  <- summarise_weekly(gh,  "gh_time",  "dominant_contributor") %>% mutate(modality = "GitHub Events")
msg_w <- summarise_weekly(msg, "msg_time", "dominant_contributor") %>% mutate(modality = "Messages")
weekly <- bind_rows(gh_w, msg_w)

sprint_bounds <- as.integer(floor(as.numeric(difftime(
  as.POSIXct(c("2024-02-28", "2024-04-05"), tz = "UTC"),
  course_start, units = "weeks"
))))

sprint_lines <- data.frame(week = sprint_bounds)

sprint_section_labels <- data.frame(
  x     = c(sprint_bounds[1] / 2,
             (sprint_bounds[1] + sprint_bounds[2]) / 2,
             sprint_bounds[2] + (max(weekly$week) - sprint_bounds[2]) / 2),
  label = c("Sprint 1", "Sprint 2", "Sprint 3")
)

ggplot(weekly, aes(week, med,
                   color = dominant_contributor,
                   fill  = dominant_contributor,
                   shape = dominant_contributor)) +
  geom_ribbon(aes(ymin = q25, ymax = q75), alpha = .18, color = NA) +
  geom_line(linewidth = 0.45) +
  geom_point(size = 0.5) +
  geom_vline(data = sprint_lines, aes(xintercept = week),
             linetype = "dashed", linewidth = 0.4, color = "grey55", inherit.aes = FALSE) +
  geom_text(data = sprint_section_labels,
            aes(x = x, y = Inf, label = label),
            hjust = 0.5, vjust = 1.4, size = 1.4, color = "grey45",
            fontface = "italic", inherit.aes = FALSE) +
  facet_wrap(~modality, scales = "free_y", ncol = 2) +
  scale_color_manual(values = c(higher = CLR_HIGHER, lower = CLR_LOWER),
                     labels = c(higher = "Higher", lower = "Lower")) +
  scale_fill_manual(values  = c(higher = CLR_HIGHER, lower = CLR_LOWER),
                    labels  = c(higher = "Higher", lower = "Lower")) +
  scale_shape_manual(values = c(higher = 17, lower = 16),
                     labels = c(higher = "Higher", lower = "Lower")) +
  labs(x = "Course week", y = "Median weekly count",
       color = "Contributor type", fill = "Contributor type",
       shape = "Contributor type") +
  theme_paper(base_size = 5) +
  theme(
    legend.position      = c(0.99, 0.99),
    legend.justification = c("right", "top"),
    legend.background    = element_rect(fill = alpha("white", 0.75), color = NA),
    legend.margin        = margin(1, 2, 1, 2),
    legend.title         = element_text(size = 4),
    legend.text          = element_text(size = 4),
    legend.key.size      = unit(0.35, "lines"),
    strip.text           = element_text(size = 5, face = "bold"),
    axis.title           = element_text(size = 4),
    axis.text            = element_text(size = 4),
    panel.spacing        = unit(0.3, "lines")
  )

ggsave(here("Figures", "median_weekly.png"),
       device = agg_png, width = 3.5, height = 1.0, dpi = 600)

EVENT_LABELS <- c(
  commit       = "Commit",
  issue_opened = "Issue Opened",
  pr_opened    = "PR Opened",
  pr_review    = "PR Review"
)

# ------------------------------------------------------------
# FIGURE: cont_event_boxplots.png
# Per-student-sprint totals by peer-identified type
# ------------------------------------------------------------

gh_agg <- gh %>%
  filter(!is.na(dominant_contributor)) %>%
  count(student, sprint, event_type, dominant_contributor, name = "count") %>%
  mutate(
    dominant_contributor = factor(dominant_contributor, levels = c("higher", "lower")),
    event_type = factor(event_type, levels = names(EVENT_LABELS), labels = EVENT_LABELS)
  )

ggplot(gh_agg, aes(x = dominant_contributor, y = count, fill = dominant_contributor)) +
  geom_boxplot(outlier.size = .5, outlier.alpha = .4, linewidth = 0.4) +
  facet_wrap(~event_type, scales = "free_y", nrow = 1) +
  scale_fill_manual(values = c(higher = CLR_HIGHER, lower = CLR_LOWER)) +
  scale_x_discrete(labels = c(higher = "Higher", lower = "Lower")) +
  scale_y_continuous(trans = "log1p",
                     breaks = c(0, 1, 5, 10, 25, 50, 100, 250),
                     labels = c("0", "1", "5", "10", "25", "50", "100", "250")) +
  labs(x = NULL, y = "GitHub events per student-sprint (log scale)") +
  theme_paper(base_size = 10) +
  theme(legend.position = "none")

ggsave(here("Figures", "cont_event_boxplots.png"),
       device = agg_png, width = 8, height = 3.5, dpi = 600)

# ------------------------------------------------------------
# ART ANOVA tables
# Aggregate to student × sprint × event_type counts, attach labels
# ------------------------------------------------------------

gh_counts <- gh %>%
  filter(!is.na(dominant_peer_type)) %>%
  count(student, global_id, sprint, event_type,
        dominant_peer_type, dominant_contributor, name = "n_events") %>%
  mutate(
    dominant_peer_type   = factor(dominant_peer_type),
    dominant_contributor = factor(dominant_contributor),
    event_type = factor(event_type),
    sprint     = factor(sprint, levels = c("Sprint 1","Sprint 2","Sprint 3"), ordered = TRUE)
  )

fmt_p <- function(p) {
  if (is.na(p)) return("---")
  stars <- if (p < .001) "***" else if (p < .01) "**" else if (p < .05) "*" else ""
  label <- if (p < .001) "$< .001$" else sprintf("%.3f", p)
  paste0(label, stars)
}

fmt_ss <- function(ss) {
  if (is.na(ss)) return("---")
  s     <- formatC(ss, format = "e", digits = 2)
  parts <- strsplit(s, "e")[[1]]
  exp   <- as.integer(parts[2])
  paste0("$", parts[1], " \\times 10^{", exp, "}$")
}

clean_effect <- function(nm) {
  nm <- gsub("dominant_peer_type",   "Dominant peer type",  nm)
  nm <- gsub("dominant_contributor", "Contributor group",   nm)
  nm <- gsub("event_type",           "Event type",          nm)
  nm <- gsub("sprint",               "Sprint",              nm)
  nm <- gsub(":",                    " $\\\\times$ ",       nm)
  nm
}

save_anova_tex <- function(model, caption, label, file, note = NULL) {
  fmla   <- as.formula(deparse(model$call$formula))
  tterms <- attr(terms(fmla), "term.labels")

  rows <- lapply(tterms, function(tm) {
    tryCatch({
      alm <- artlm(model, tm)
      av  <- anova(alm)
      row <- av[rownames(av) == tm, , drop = FALSE]
      data.frame(
        Effect = tm,
        Df     = row$Df,
        F      = row$`F value`,
        p      = row$`Pr(>F)`,
        check.names = FALSE
      )
    }, error = function(e2) {
      data.frame(Effect = tm, Df = NA, F = NA, p = NA, check.names = FALSE)
    })
  })
  tbl <- bind_rows(rows)

  lines <- c(
    "\\begin{table}[ht]",
    "\\centering",
    "\\footnotesize",
    paste0("\\caption{", caption, "}"),
    paste0("\\label{", label, "}"),
    "\\begin{tabular}{l r r r}",
    "\\toprule",
    "\\textbf{Effect} & \\textbf{df} & \\textbf{F} & \\textbf{p-value} \\\\",
    "\\midrule"
  )

  for (i in seq_len(nrow(tbl))) {
    r      <- tbl[i, ]
    effect <- clean_effect(r$Effect)
    df     <- if (is.na(r$Df)) "---" else as.character(r$Df)
    fval   <- if (is.na(r$F))  "---" else sprintf("%.2f", r$F)
    pval   <- fmt_p(r$p)
    lines  <- c(lines, paste0(effect, " & ", df, " & ", fval, " & ", pval, " \\\\"))
  }

  sig_note <- "\\multicolumn{4}{l}{\\textit{Note.} * $p < .05$; ** $p < .01$; *** $p < .001$} \\\\"
  lines <- c(lines, "\\midrule", sig_note, "\\bottomrule", "\\end{tabular}")

  if (!is.null(note)) {
    lines <- c(lines, "\\medskip", paste0("\\textit{Note.} ", note))
  }

  lines <- c(lines, "\\end{table}")
  writeLines(lines, file)
}

extract_anova_rows <- function(model) {
  fmla   <- as.formula(deparse(model$call$formula))
  tterms <- attr(terms(fmla), "term.labels")
  rows <- lapply(tterms, function(tm) {
    tryCatch({
      alm <- artlm(model, tm)
      av  <- anova(alm)
      row <- av[rownames(av) == tm, , drop = FALSE]
      data.frame(Effect = tm, Df = row$Df,
                 F = row$`F value`, p = row$`Pr(>F)`,
                 check.names = FALSE)
    }, error = function(e2) {
      data.frame(Effect = tm, Df = NA, F = NA, p = NA, check.names = FALSE)
    })
  })
  bind_rows(rows)
}

save_two_panel_anova_tex <- function(model_a, panel_a_label,
                                     model_b, panel_b_label,
                                     caption, label, file) {
  tbl_a <- extract_anova_rows(model_a)
  tbl_b <- extract_anova_rows(model_b)

  panel_rows <- function(tbl) {
    out <- c()
    for (i in seq_len(nrow(tbl))) {
      r    <- tbl[i, ]
      eff  <- clean_effect(r$Effect)
      df   <- if (is.na(r$Df)) "---" else as.character(r$Df)
      fval <- if (is.na(r$F))  "---" else sprintf("%.2f", r$F)
      pval <- fmt_p(r$p)
      out  <- c(out, paste0(eff, " & ", df, " & ", fval, " & ", pval, " \\\\"))
    }
    out
  }

  sig_note <- "\\multicolumn{4}{l}{\\textit{Note.} * $p < .05$; ** $p < .01$; *** $p < .001$} \\\\"

  lines <- c(
    "\\begin{table}[ht]",
    "\\centering",
    "\\footnotesize",
    paste0("\\caption{", caption, "}"),
    paste0("\\label{", label, "}"),
    "\\begin{tabular}{l r r r}",
    "\\toprule",
    "\\textbf{Effect} & \\textbf{df} & \\textbf{F} & \\textbf{p-value} \\\\",
    "\\midrule",
    paste0("\\multicolumn{4}{l}{\\textbf{Panel A: ", panel_a_label, "}} \\\\"),
    "\\midrule",
    panel_rows(tbl_a),
    "\\midrule",
    paste0("\\multicolumn{4}{l}{\\textbf{Panel B: ", panel_b_label, "}} \\\\"),
    "\\midrule",
    panel_rows(tbl_b),
    "\\midrule",
    sig_note,
    "\\bottomrule",
    "\\end{tabular}",
    "\\end{table}"
  )
  writeLines(lines, file)
}

m_peer <- art(
  n_events ~ dominant_peer_type * event_type * sprint,
  data = gh_counts
)

m_contr <- art(
  n_events ~ dominant_contributor * event_type * sprint,
  data = gh_counts
)

# TABLE: art_anova_combined.tex
save_two_panel_anova_tex(
  model_a       = m_peer,
  panel_a_label = "Peer-identified teammate type",
  model_b       = m_contr,
  panel_b_label = "Contributor group (higher/lower)",
  caption       = "ART ANOVA results for GitHub event counts by (A) peer-identified teammate type and (B) contributor group.",
  label         = "tab:gh-anova-combined",
  file          = here("Tables", "art_anova_combined.tex")
)

# ------------------------------------------------------------
# ROBUSTNESS: Kruskal-Wallis + pairwise Wilcoxon (Holm)
# Reproduces chi2(3)=33.32 cited in paper (line 212)
# ------------------------------------------------------------

gh_totals <- gh_counts %>%
  group_by(student, sprint, dominant_peer_type) %>%
  summarise(total_events = sum(n_events), .groups = "drop")

kw <- kruskal.test(total_events ~ dominant_peer_type, data = gh_totals)
cat(sprintf("Kruskal-Wallis: chi2(%.0f) = %.3f, p = %.4f\n",
            kw$parameter, kw$statistic, kw$p.value))

pw <- pairwise.wilcox.test(
  gh_totals$total_events,
  gh_totals$dominant_peer_type,
  p.adjust.method = "holm",
  exact = FALSE
)
print(pw)

message("01_volume_activity.R complete.")