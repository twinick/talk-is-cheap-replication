"""
Pipeline diagram matching Image #2 layout.

Top row:    Raw messages  →  Rule-based keywords  ─┐
                                                    ├─►  [Weight Computation dashed box]  →  Thread-level Agg
Mid row:    SBERT         →  Logistic regression  ─┘         Confidence aggregation
                                                              +
Bottom-left dashed:                                           Indirect cues
  200 sampled → Retrain ─► (arrow up to Logistic)

Outputs fan downward from Thread-level Agg:
  Non-developmental  |  Coordination-only  |  Development-oriented
"""

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

fig, ax = plt.subplots(figsize=(21, 5.0))
ax.set_xlim(0, 21)
ax.set_ylim(0.2, 5.4)
ax.axis("off")

C_DARK   = "#2E2E3A"
C_PURPLE = "#5B4A8A"
C_INDIGO = "#6B5FAA"
C_OLIVE  = "#6B6B2A"
C_GREY_D = "#4A4A4A"
C_GREEN_D= "#2E6B3E"
C_OUT_ND = "#3A3A3A"
C_OUT_CO = "#2E4A6B"
C_OUT_DO = "#2E6B3E"
C_DASHED = "#888888"
C_WHITE  = "white"

FONT = "DejaVu Sans"
FS   = 9.0

def box(cx, cy, w, h, label, color, sublabel=None, fontsize=FS):
    ax.add_patch(FancyBboxPatch(
        (cx - w/2, cy - h/2), w, h,
        boxstyle="round,pad=0.08",
        facecolor=color, edgecolor=color,
        linewidth=1.6, zorder=3
    ))
    if sublabel:
        ax.text(cx, cy + 0.13, label, ha="center", va="center",
                fontsize=fontsize, fontfamily=FONT, color=C_WHITE,
                fontweight="bold", zorder=4)
        ax.text(cx, cy - 0.20, sublabel, ha="center", va="center",
                fontsize=fontsize - 1.8, fontfamily=FONT, color=C_WHITE, zorder=4)
    else:
        ax.text(cx, cy, label, ha="center", va="center",
                fontsize=fontsize, fontfamily=FONT, color=C_WHITE,
                fontweight="bold", zorder=4)

AW = dict(arrowstyle="-|>", color="#999999", lw=1.3, mutation_scale=12, zorder=2)

def arrow(x0, y0, x1, y1):
    ax.annotate("", xy=(x1, y1), xytext=(x0, y0), arrowprops=dict(**AW))

def seg(x0, y0, x1, y1):
    ax.plot([x0, x1], [y0, y1], color="#999999", lw=1.3, zorder=2)

# ── coordinates ───────────────────────────────────────────────────────────────
BW, BH   = 2.6, 0.72
BW_SM    = 2.2
BW_OUT   = 2.1

# x
X_LEFT  = 1.6    # Raw messages / SBERT
X_MID   = 5.5    # Rule-based / Logistic
X_200   = 3.0    # 200 sampled messages
X_RET   = 6.5    # Retrain classifier
X_CONF  = 12.2   # Confidence agg / Indirect cues (weight computation)
X_TA    = 17.0   # Thread-level aggregation

# y
Y_TOP   = 4.3    # Raw messages / Rule-based
Y_MID   = 3.0    # SBERT / Logistic
Y_CONF  = 3.65   # Confidence aggregation (inside weight computation)
Y_INDIR = 2.35   # Indirect cues (inside weight computation)
Y_MANUAL= 1.2    # Manual annotation row
Y_TA    = 3.65   # Thread-level aggregation (same height as conf agg)

# output positions (below thread-level, fanning down)
Y_OUT   = 1.6
X_OUT_ND = 15.0
X_OUT_CO = 17.5
X_OUT_DO = 20.0

# ── Weight Computation dashed enclosure ───────────────────────────────────────
WC_PAD = 0.35
wc_x0 = X_CONF - BW/2 - WC_PAD
wc_x1 = X_CONF + BW/2 + WC_PAD
wc_y0 = Y_INDIR - BH/2 - WC_PAD
wc_y1 = Y_CONF  + BH/2 + WC_PAD + 0.26
ax.add_patch(Rectangle(
    (wc_x0, wc_y0), wc_x1 - wc_x0, wc_y1 - wc_y0,
    fill=False, edgecolor=C_DASHED, linewidth=1.5,
    linestyle="--", zorder=1
))
ax.text(X_CONF, wc_y1 - 0.16,
        "Weight Computation",
        ha="center", va="center", style="italic",
        fontsize=FS - 1.0, fontfamily=FONT, color=C_DASHED, zorder=4)

# ── Manual annotation dashed enclosure (bottom left) ─────────────────────────
MA_PAD = 0.32
ma_x0 = X_200 - BW/2 - MA_PAD
ma_x1 = X_RET + BW/2 + MA_PAD
ma_y0 = Y_MANUAL - BH/2 - MA_PAD
ma_y1 = Y_MANUAL + BH/2 + MA_PAD + 0.26
ax.add_patch(Rectangle(
    (ma_x0, ma_y0), ma_x1 - ma_x0, ma_y1 - ma_y0,
    fill=False, edgecolor=C_DASHED, linewidth=1.5,
    linestyle="--", zorder=1
))
ax.text((ma_x0 + ma_x1) / 2, ma_y1 - 0.15,
        "Manual annotation & retraining",
        ha="center", va="center", style="italic",
        fontsize=FS - 1.0, fontfamily=FONT, color=C_DASHED, zorder=4)

# ── boxes ─────────────────────────────────────────────────────────────────────
box(X_LEFT, Y_TOP,  BW_SM, BH,      "Raw messages",            C_DARK)
box(X_LEFT, Y_MID,  BW_SM, BH+0.12, "Sentence-BERT encoding",  C_DARK,
    sublabel="all-MiniLM-L6-v2")

box(X_MID, Y_TOP, BW, BH, "Rule-based keywords", C_GREEN_D,
    sublabel="PR, issue, commit…")
box(X_MID, Y_MID, BW, BH, "Logistic regression",  C_GREEN_D,
    sublabel="One-vs-rest, multi-label")

box(X_200, Y_MANUAL, BW, BH, "200 sampled messages", C_PURPLE,
    sublabel="Multi-label annotation")
box(X_RET, Y_MANUAL, BW, BH, "Retrain classifier",   C_PURPLE,
    sublabel="Replace generated labels")

box(X_CONF, Y_CONF,  BW, BH, "Confidence aggregation", C_OLIVE,
    sublabel="Hybrid activity score")
box(X_CONF, Y_INDIR, BW, BH, "Indirect cues",           C_INDIGO,
    sublabel="Capped at 1")

box(X_TA, Y_TA, BW+0.2, BH, "Thread-level aggregation", C_GREY_D)

# output boxes (below thread-level, fan down)
box(X_OUT_ND, Y_OUT, BW_OUT, 0.62, "Non-developmental",    C_OUT_ND, fontsize=FS-0.5)
box(X_OUT_CO, Y_OUT, BW_OUT, 0.62, "Coordination-only",    C_OUT_CO, fontsize=FS-0.5)
box(X_OUT_DO, Y_OUT, BW_OUT, 0.62, "Development-oriented", C_OUT_DO, fontsize=FS-0.5)

# "+" between Confidence Agg and Indirect Cues
ax.text(X_CONF, (Y_CONF + Y_INDIR) / 2, "+",
        ha="center", va="center",
        fontsize=14, fontfamily=FONT, color=C_DASHED,
        fontweight="bold", zorder=4)

# ── arrows ────────────────────────────────────────────────────────────────────

# Raw messages → Rule-based (horizontal)
arrow(X_LEFT + BW_SM/2, Y_TOP, X_MID - BW/2, Y_TOP)

# Raw messages → SBERT (down)
arrow(X_LEFT, Y_TOP - BH/2, X_LEFT, Y_MID + (BH+0.12)/2)

# SBERT → Logistic regression (horizontal)
arrow(X_LEFT + BW_SM/2, Y_MID, X_MID - BW/2, Y_MID)

# Rule-based → Confidence agg (right, then elbow down)
x_rb_r = X_MID + BW/2
x_conf_l = X_CONF - BW/2
seg  (x_rb_r, Y_TOP, x_rb_r + 0.4, Y_TOP)
seg  (x_rb_r + 0.4, Y_TOP, x_rb_r + 0.4, Y_CONF)
arrow(x_rb_r + 0.4, Y_CONF, x_conf_l, Y_CONF)

# Logistic → Confidence agg (right, elbow up)
seg  (X_MID + BW/2, Y_MID, x_conf_l, Y_MID)
arrow(x_conf_l, Y_MID, x_conf_l, Y_CONF - BH/2)

# Rule-based → Indirect cues (fork: right then down-right)
x_fork = x_rb_r + 0.4
seg  (x_fork, Y_TOP, x_fork, Y_INDIR)
arrow(x_fork, Y_INDIR, x_conf_l, Y_INDIR)

# 200 sampled → Retrain classifier
arrow(X_200 + BW/2, Y_MANUAL, X_RET - BW/2, Y_MANUAL)

# Retrain classifier → Logistic regression (arrow going up)
x_ret_cx = X_RET
y_ret_top = Y_MANUAL + BH/2
seg  (x_ret_cx, y_ret_top, x_ret_cx, Y_MID - BH/2 - 0.1)
arrow(x_ret_cx, Y_MID - BH/2 - 0.1, x_ret_cx, Y_MID - BH/2)

# Weight Computation → Thread-level aggregation
arrow(X_CONF + BW/2, (Y_CONF + Y_INDIR)/2, X_TA - (BW+0.2)/2, Y_TA)

# Thread-level agg → 3 outputs (fan down)
y_ta_bot = Y_TA - BH/2
y_bus    = (y_ta_bot + Y_OUT + 0.31) / 2
seg(X_TA, y_ta_bot, X_TA, y_bus)
seg(X_OUT_ND, y_bus, X_OUT_DO, y_bus)
arrow(X_OUT_ND, y_bus, X_OUT_ND, Y_OUT + 0.31)
arrow(X_OUT_CO, y_bus, X_OUT_CO, Y_OUT + 0.31)
arrow(X_OUT_DO, y_bus, X_OUT_DO, Y_OUT + 0.31)

# ── save ──────────────────────────────────────────────────────────────────────
import os as _os
out = _os.path.join(_os.path.dirname(__file__), "pipeline_horizontal.png")
fig.savefig(out, dpi=220, bbox_inches="tight",
            facecolor="#1a1a2e", edgecolor="none")
print(f"Saved: {out}")
