# 09_error_analysis.R -----------------------------------------------------
# Error analysis of the forecasts already produced by scripts 06, 07 and 08:
#   1. performance by season, day type and temperature regime (robustness)
#   2. MAE by hour of the day
#   3. the largest-error days ("failure days") with context and a diagnostic hint
# No model is refitted: this script only reads outputs/*.rds (cheap).
# Requires: outputs/benchmarks.rds, arima_<split>.rds, ablation_<split>.rds
# Usage: source("R/09_error_analysis.R")

source("R/protocol.R")
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

# ---- Settings ----
EVAL_SPLIT  <- "val"
REF_MODEL   <- "cal_lags"     # operational model whose failures are analysed
N_FAIL      <- 10             # failure days listed
N_FAIL_PLOT <- 3              # failure days plotted
col_temp    <- "t"
cal_cols <- c(holiday = "is_public_holiday", eve = "is_holiday_eve",
              vacA = "school_holiday_A", vacB = "school_holiday_B",
              vacC = "school_holiday_C")

# ---- Load forecasts and align on identical dates ----
ab <- readRDS(paste0("outputs/ablation_", EVAL_SPLIT, ".rds"))
ar <- readRDS(paste0("outputs/arima_", EVAL_SPLIT, ".rds"))
bm <- readRDS("outputs/benchmarks.rds")
tg <- ab$targets; obs <- ab$obs
stopifnot(all(tg == ar$targets), REF_MODEL %in% names(ab$pred))
ib <- match(tg, bm$targets)
P <- c(list(cal_lags = ab$pred$cal_lags, ARIMA_per_hour = ar$pred),
       lapply(bm$preds, function(p) p[ib, , drop = FALSE]),
       list(FULL_PERFECT_WX = ab$pred$FULL_PERFECT_WX))
OPER <- setdiff(names(P), "FULL_PERFECT_WX")   # deployable models

# ---- Daily context (calendar, temperature) ----
d <- read_csv(cfg$data_path, show_col_types = FALSE,
              col_select = any_of(c(cfg$col_time_utc, col_temp, unname(cal_cols))))
d$date <- as.Date(with_tz(as.POSIXct(d[[cfg$col_time_utc]], tz = "UTC"), cfg$tz), tz = cfg$tz)
temp <- d[[col_temp]]
if (median(temp, na.rm = TRUE) > 100) temp <- temp - 273.15
tmean <- tapply(temp, d$date, mean, na.rm = TRUE)
to_bin <- function(x) {
  if (is.numeric(x) || is.logical(x)) as.numeric(x > 0)
  else as.numeric(toupper(as.character(x)) %in% c("TRUE", "1", "OUI", "YES"))
}
flag <- function(col) {
  if (!col %in% names(d)) return(rep(0, length(tg)))
  as.numeric(tapply(to_bin(d[[col]]), d$date, max, na.rm = TRUE)[as.character(tg)])
}
ctx <- data.frame(
  date    = tg,
  weekday = format(tg, "%a"),
  tmean   = round(as.numeric(tmean[as.character(tg)]), 1),
  dT      = round(as.numeric(tmean[as.character(tg)]) - as.numeric(tmean[as.character(tg - 1)]), 1),
  holiday = flag(cal_cols[["holiday"]]),
  eve     = flag(cal_cols[["eve"]]),
  vac     = pmax(flag(cal_cols[["vacA"]]), flag(cal_cols[["vacB"]]), flag(cal_cols[["vacC"]]))
)
wd <- wday(tg, week_start = 1)
ctx$daytype <- ifelse(ctx$holiday == 1, "public_holiday",
                ifelse(wd == 6, "Saturday", ifelse(wd == 7, "Sunday", "Weekday")))
m <- month(tg)
ctx$season <- ifelse(m %in% c(12, 1, 2), "DJF", ifelse(m %in% 3:5, "MAM",
               ifelse(m %in% 6:8, "JJA", "SON")))
ctx$regime <- ifelse(ctx$tmean < 5, "cold (<5C)", ifelse(ctx$tmean > 20, "hot (>20C)", "mild"))

# ---- 1. Daily MAE per model, performance by segment ----
dm <- sapply(P, function(p) rowMeans(abs(p - obs)))        # days x models
seg <- function(by, name) {
  do.call(rbind, lapply(split(seq_along(tg), by), function(i) {
    r <- colMeans(dm[i, , drop = FALSE])
    data.frame(segment = name, level = by[i[1]], n_days = length(i), t(round(r, 0)),
               best_operational = names(which.min(r[OPER])), check.names = FALSE)
  }))
}
seg_tab <- rbind(seg(ctx$season, "season"), seg(ctx$daytype, "day_type"),
                 seg(ctx$regime, "temperature"))
rownames(seg_tab) <- NULL
print(seg_tab)
write.csv(seg_tab, paste0("outputs/errors_by_segment_", EVAL_SPLIT, ".csv"), row.names = FALSE)

# ---- 2. MAE by hour of the day ----
mae_h <- sapply(P, function(p) colMeans(abs(p - obs)))
rownames(mae_h) <- 0:23
write.csv(round(mae_h, 0), paste0("outputs/mae_by_hour_", EVAL_SPLIT, ".csv"))
png("outputs/figures/mae_by_hour.png", width = 900, height = 500)
matplot(0:23, mae_h[, OPER], type = "l", lty = 1, lwd = 2, col = seq_along(OPER),
        xlab = "Hour of target day (local)", ylab = "MAE (MW)",
        main = paste("MAE by hour -", EVAL_SPLIT))
legend("topleft", OPER, col = seq_along(OPER), lty = 1, lwd = 2, cex = 0.8)
dev.off()

# ---- 3. Failure days of the reference model ----
ord <- order(dm[, REF_MODEL], decreasing = TRUE)
sel <- integer(0)
for (i in ord) {                                   # keep days at least 3 days apart
  if (all(abs(as.numeric(tg[i] - tg[sel])) >= 3)) sel <- c(sel, i)
  if (length(sel) == N_FAIL) break
}
others <- setdiff(OPER, REF_MODEL)
fail <- cbind(
  ctx[sel, c("date", "weekday", "daytype", "tmean", "dT", "holiday", "eve", "vac")],
  MAE_ref        = round(dm[sel, REF_MODEL], 0),
  bias_ref       = round(rowMeans(P[[REF_MODEL]][sel, , drop = FALSE] - obs[sel, , drop = FALSE]), 0),
  peak_err_ref   = round(apply(P[[REF_MODEL]][sel, , drop = FALSE], 1, max) -
                         apply(obs[sel, , drop = FALSE], 1, max), 0),
  round(dm[sel, c(others, "FULL_PERFECT_WX")], 0)
)
# Heuristic hint only: must be checked manually before use in the report
fail$hint <- ifelse(fail$FULL_PERFECT_WX < 0.6 * fail$MAE_ref, "weather explains most of the error",
              ifelse(apply(dm[sel, others, drop = FALSE], 1, min) < 0.7 * fail$MAE_ref,
                     "model-specific (another model does better)",
                     "all models fail: event / regime / data issue?"))
rownames(fail) <- NULL
print(fail)
write.csv(fail, paste0("outputs/failure_days_", EVAL_SPLIT, ".csv"), row.names = FALSE)

# Plot the top failure days: observed vs forecasts
png("outputs/figures/failure_days.png", width = 1300, height = 450)
par(mfrow = c(1, N_FAIL_PLOT))
for (k in seq_len(N_FAIL_PLOT)) {
  i <- sel[k]
  yl <- range(obs[i, ], P[[REF_MODEL]][i, ], P$ARIMA_per_hour[i, ], P$FULL_PERFECT_WX[i, ])
  plot(0:23, obs[i, ], type = "l", lwd = 3, ylim = yl, xlab = "Hour", ylab = "MW",
       main = paste(tg[i], ctx$weekday[i], "| T =", ctx$tmean[i], "C"))
  lines(0:23, P[[REF_MODEL]][i, ], col = "red", lwd = 2)
  lines(0:23, P$ARIMA_per_hour[i, ], col = "blue", lwd = 2)
  lines(0:23, P$FULL_PERFECT_WX[i, ], col = "darkgreen", lwd = 2, lty = 2)
  if (k == 1) legend("topleft", c("observed", REF_MODEL, "ARIMA", "perfect weather"),
                     col = c("black", "red", "blue", "darkgreen"), lwd = 2, lty = c(1, 1, 1, 2), cex = 0.8)
}
dev.off()
message("Wrote outputs/errors_by_segment_*.csv, mae_by_hour_*.csv, failure_days_*.csv and figures/")
