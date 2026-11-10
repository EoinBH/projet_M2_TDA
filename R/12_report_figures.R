# 12_report_figures.R -----------------------------------------------------
# Report/slide figures from existing forecasts (no refitting, seconds to run):
#   model_comparison, ablation, segments, typical_weeks, failure_days_chosen (all suffixed
#   with the split) and protocol_timeline.
# Usage: EVAL_SPLIT <- "val"; source("R/12_report_figures.R")   (or "test")
# Optional before sourcing: FAIL_DATES <- as.Date(c("2024-11-24","2024-01-08","2024-12-24"))
#   (on the test split, set FAIL_DATES to test days, or leave unset to plot the 3 worst days)

source("R/load_results.R")
SPL <- EVAL_SPLIT
fig <- function(name, w, h) png(paste0("outputs/figures/", name, "_", SPL, ".png"), width = w, height = h, res = 110)
is_bm <- function(x) grepl("^B[0-9]", x)

# ---- 1. Model comparison (MAE and RMSE) ----
S <- t(sapply(P, function(p) score(obs, p)))
S <- S[order(S[, "MAE"]), , drop = FALSE]
write.csv(round(S, 1), paste0("outputs/scores_all_", SPL, ".csv"))
colr <- ifelse(rownames(S) == "FULL_PERFECT_WX", "grey70", ifelse(is_bm(rownames(S)), "tan", "steelblue"))
fig("model_comparison", 1200, 550); par(mfrow = c(1, 2), mar = c(4, 12, 3, 1))
barplot(rev(S[, "MAE"]), horiz = TRUE, las = 1, col = rev(colr), main = paste("MAE (MW) -", SPL), xlab = "MW")
barplot(rev(S[, "RMSE"]), horiz = TRUE, las = 1, col = rev(colr), main = paste("RMSE (MW) -", SPL), xlab = "MW")
legend("bottomright", c("benchmark", "deployable model", "perfect weather (NOT deployable)"),
       fill = c("tan", "steelblue", "grey70"), cex = 0.8, bg = "white")
dev.off()

# ---- 2. Ablation (perfect-weather groups) and operational ablation ----
mae_of <- function(nm) sapply(nm, function(m) mean(abs(ab$pred[[m]] - obs)))
g <- c(`full model\n(perfect wx)` = "FULL_PERFECT_WX", `- weather` = "cal_lags",
       `- calendar` = "noCal_PERFECT_WX", `- lags` = "noLags_PERFECT_WX")
g <- g[g %in% names(ab$pred)]
o <- c("cal_only", "lags_only", "cal_lags_no13", "cal_lags", "cal_lags_tempJ")
o <- o[o %in% names(ab$pred)]
fig("ablation", 1200, 550); par(mfrow = c(1, 2), mar = c(6, 5, 3, 1))
mg <- mae_of(g); names(mg) <- names(g)
bp <- barplot(mg, col = c("grey70", rep("steelblue", length(mg) - 1)), las = 2, ylab = "MAE (MW)",
              main = "Ablation: remove one group (perfect-weather model)", ylim = c(0, max(mg) * 1.15))
text(bp, mg, round(mg), pos = 3, cex = 0.8)
mo <- mae_of(o)
bp <- barplot(mo, col = "steelblue", las = 2, ylab = "MAE (MW)", main = "Operational models (deployable)",
              ylim = c(0, max(mo) * 1.15))
text(bp, mo, round(mo), pos = 3, cex = 0.8)
dev.off()
write.csv(data.frame(model = c(names(g), o), MAE = round(c(mg, mo), 1)),
          paste0("outputs/ablation_summary_", SPL, ".csv"), row.names = FALSE)

# ---- 3. Performance by segment ----
SEL <- intersect(c("cal_lags", "cal_lags_tempJ", "arima_v2", "B1_prev_day_strict", "B2_same_weekday_lw"), names(P))
dm <- sapply(P, function(p) rowMeans(abs(p - obs)))
seg_mat <- function(by, lev) {
  lev <- lev[lev %in% by]
  M <- sapply(lev, function(l) colMeans(dm[by == l, SEL, drop = FALSE]))
  colnames(M) <- paste0(lev, "\n(n=", sapply(lev, function(l) sum(by == l)), ")")
  M
}
sc <- c("steelblue", "darkorange", "dodgerblue4", "grey60", "tan")[seq_along(SEL)]
fig("segments", 1500, 520); par(mfrow = c(1, 3), mar = c(5, 4, 3, 1))
for (s in list(list(ctx$season, c("DJF", "MAM", "JJA", "SON"), "Season"),
               list(ctx$daytype, c("Weekday", "Saturday", "Sunday", "public_holiday"), "Day type"),
               list(ctx$regime, c("cold (<5C)", "mild", "hot (>20C)"), "Temperature of target day"))) {
  barplot(seg_mat(s[[1]], s[[2]]), beside = TRUE, col = sc, main = s[[3]], ylab = "MAE (MW)", cex.names = 0.8)
}
legend("topright", SEL, fill = sc, cex = 0.7, bg = "white")
dev.off()

# ---- 4. Typical winter and summer weeks ----
mon_after <- function(d) d + (8 - wday(d, week_start = 1)) %% 7
yr <- as.integer(format(median(tg), "%Y"))
starts <- c(winter = mon_after(as.Date(paste0(yr, "-01-15"))), summer = mon_after(as.Date(paste0(yr, "-07-15"))))
WK <- intersect(c("cal_lags", "cal_lags_tempJ", "arima_v2"), names(P))
wc <- c("firebrick", "darkorange", "steelblue")[seq_along(WK)]
fig("typical_weeks", 1400, 520); par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
for (k in seq_along(starts)) {
  s <- as.Date(starts[k], origin = "1970-01-01"); idx <- match(s + 0:6, tg)
  if (anyNA(idx)) { plot.new(); next }
  y <- c(t(obs[idx, ]))
  plot(y, type = "l", lwd = 2.5, xaxt = "n", xlab = "", ylab = "MW",
       ylim = range(y, sapply(WK, function(m) c(t(P[[m]][idx, ])))),
       main = paste(names(starts)[k], "week from", format(s)))
  axis(1, at = seq(1, 169, 24), labels = format(s + 0:7, "%a %d"), cex.axis = 0.7)
  for (j in seq_along(WK)) lines(c(t(P[[WK[j]]][idx, ])), col = wc[j], lwd = 1.5)
  if (k == 1) legend("topright", c("observed", WK), col = c("black", wc), lwd = 2, cex = 0.8, bg = "white")
}
dev.off()

# ---- 5. Failure days (chosen dates) ----
if (!exists("FAIL_DATES")) FAIL_DATES <- as.Date(c("2024-11-24", "2024-01-08", "2024-12-24"))
fd <- match(FAIL_DATES, tg); fd <- fd[!is.na(fd)]
if (length(fd) == 0) {
  message("FAIL_DATES not in this split: plotting the 3 worst days of cal_lags instead.")
  fd <- order(dm[, "cal_lags"], decreasing = TRUE)[1:3]
}
FD <- intersect(c("cal_lags", "cal_lags_tempJ", "arima_v2", "B1_prev_day_strict", "FULL_PERFECT_WX"), names(P))
fc <- c(cal_lags = "firebrick", cal_lags_tempJ = "darkorange", arima_v2 = "steelblue",
        B1_prev_day_strict = "grey50", FULL_PERFECT_WX = "darkgreen")
fig("failure_days_chosen", 480 * length(fd) + 100, 520); par(mfrow = c(1, length(fd)), mar = c(4, 4, 3, 1))
for (k in seq_along(fd)) {
  i <- fd[k]
  plot(0:23, obs[i, ], type = "l", lwd = 3, xlab = "Hour", ylab = "MW",
       ylim = range(obs[i, ], sapply(FD, function(m) P[[m]][i, ])),
       main = paste(tg[i], format(tg[i], "%a"), "| T =", round(ctx$tmean[i], 1), "C"))
  for (m in FD) lines(0:23, P[[m]][i, ], col = fc[m], lwd = 2, lty = ifelse(m == "FULL_PERFECT_WX", 2, 1))
  if (k == 1) legend("topleft", c("observed", FD), col = c("black", fc[FD]), lwd = 2, cex = 0.7, bg = "white")
}
dev.off()

# ---- 6. Protocol timeline (written once, not split-specific) ----
if (!file.exists("outputs/figures/protocol_timeline.png")) {
  yrf <- function(x) as.numeric(format(x, "%Y")) + (as.numeric(format(x, "%j")) - 1) / 365
  png("outputs/figures/protocol_timeline.png", width = 1200, height = 650, res = 110)
  par(mfrow = c(2, 1), mar = c(3, 1, 3, 1))
  plot(NA, xlim = c(2022, 2026), ylim = c(0, 1), yaxt = "n", ylab = "", xlab = "", main = "Chronological split (by target date)")
  rect(2022, 0.2, yrf(cfg$train_end) + 1 / 365, 0.8, col = "steelblue")
  rect(yrf(cfg$train_end) + 1 / 365, 0.2, yrf(cfg$val_end) + 1 / 365, 0.8, col = "darkorange")
  rect(yrf(cfg$val_end) + 1 / 365, 0.2, 2026, 0.8, col = "firebrick")
  text(2023, 0.5, "train (2022-2023)\norders chosen here", col = "white")
  text(2024.5, 0.5, "validation (2024)\nmodel comparison", col = "white")
  text(2025.5, 0.5, "test (2025)\nused ONCE", col = "white")
  plot(NA, xlim = c(-12, 48), ylim = c(0, 1), yaxt = "n", ylab = "", xlab = "hours from 00:00 of day J",
       main = "Information at the forecast origin: 14:00 on day J")
  rect(-12, 0.3, 14, 0.7, col = "darkseagreen3"); text(1, 0.5, "observed: all earlier days + hours 0-13 of J")
  rect(14, 0.3, 24, 0.7, col = "grey85"); text(19, 0.5, "J: 14-23h\nnot yet known")
  rect(24, 0.3, 48, 0.7, col = "gold"); text(36, 0.5, "TARGET: 24 hours of day J+1")
  abline(v = 14, lwd = 2, lty = 2); text(14, 0.9, "origin 14:00", pos = 4)
  dev.off()
}
message("Wrote figures for split '", SPL, "' in outputs/figures/ and outputs/scores_all_, ablation_summary_", SPL, ".csv")
