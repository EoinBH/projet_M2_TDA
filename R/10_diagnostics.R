# 10_diagnostics.R --------------------------------------------------------
# Box-Jenkins style diagnostics (cheap: no rolling re-estimation).
#   A. Stationarity tests and ACF/PACF of the daily series of each hour (TRAIN only)
#   B. For each ARIMA version in ARIMA_SPECS (protocol.R): residual diagnostics of the
#      per-hour model fitted on TRAIN with the orders written by 07_arima.R
#      (Ljung-Box, normality, residual variance by season)
#   C. Autocorrelation of the out-of-sample forecast errors (outputs/*.rds, no refitting):
#      ARIMA versions vs linear models, and correlation of errors across hours
# Nothing is tuned here. Needs the outputs of 07 and 08.
# Usage: source("R/10_diagnostics.R")

source("R/protocol.R")
for (p in c("forecast", "tseries"))
  if (!requireNamespace(p, quietly = TRUE)) stop("Package '", p, "' is required.")
suppressPackageStartupMessages(library(forecast))
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

# ---- Settings ----
EVAL_SPLIT <- "val"             # split used in part C ("test" only for the final run)
H_SHOW     <- c(3, 8, 13, 19)   # hours shown in the figures
LB_LAG     <- 14                # Ljung-Box lag (two weeks)
K_ANNUAL   <- 2

W <- load_wide(cfg); M <- W$M; dates <- W$dates
idx_tr <- which(dates <= cfg$train_end)

season_of <- function(dt) {
  m <- month(dt)
  ifelse(m %in% c(12, 1, 2), "DJF", ifelse(m %in% 3:5, "MAM",
         ifelse(m %in% 6:8, "JJA", "SON")))
}

# ======================= A. Stationarity and ACF/PACF (train) ===============
# Raw daily series are not stationary (weekly + annual seasonality, 2022 level),
# so tests are also run after removing calendar/annual effects (OLS) and a lag-7
# difference. ADF: H0 = unit root (small p -> stationary).
# KPSS: H0 = stationary (small p -> NOT stationary).
Xm1 <- build_xreg(dates, cfg, op_temp = FALSE, k_annual = K_ANNUAL)
adj_series <- function(y, Xtr) diff(residuals(lm(y ~ Xtr)), lag = 7)
safe_p <- function(f, x) tryCatch(suppressWarnings(f(x)$p.value), error = function(e) NA_real_)

stat_tab <- do.call(rbind, lapply(0:23, function(h) {
  y <- M[idx_tr, h + 1]
  a <- adj_series(y, Xm1[idx_tr, , drop = FALSE])
  data.frame(hour = h,
             adf_raw_p   = safe_p(tseries::adf.test, y),
             kpss_raw_p  = safe_p(tseries::kpss.test, y),
             adf_adj_p   = safe_p(tseries::adf.test, a),
             kpss_adj_p  = safe_p(tseries::kpss.test, a),
             ndiffs_raw  = ndiffs(y, test = "kpss"),
             nsdiffs_raw = nsdiffs(ts(y, frequency = 7)))
}))
stat_tab[, 2:5] <- round(stat_tab[, 2:5], 3)
print(stat_tab)
write.csv(stat_tab, "outputs/stationarity_tests_train.csv", row.names = FALSE)

png("outputs/figures/acf_pacf_train.png", width = 1400, height = 900)
par(mfrow = c(3, length(H_SHOW)))
for (h in H_SHOW)
  acf(M[idx_tr, h + 1], lag.max = 35, main = paste("ACF raw series, hour", h))
for (h in H_SHOW)
  acf(adj_series(M[idx_tr, h + 1], Xm1[idx_tr, , drop = FALSE]), lag.max = 35,
      main = paste("ACF adjusted + diff 7, hour", h))
for (h in H_SHOW)
  pacf(adj_series(M[idx_tr, h + 1], Xm1[idx_tr, , drop = FALSE]), lag.max = 35,
       main = paste("PACF adjusted + diff 7, hour", h))
dev.off()

# ======================= B. ARIMA residuals (train), per version ============
keep <- -(1:14)                                   # drop start-up residuals
for (spec in names(ARIMA_SPECS)) {
  ord_file <- sprintf("outputs/%s_orders.csv", spec)
  if (!file.exists(ord_file)) {
    message("Part B: skipping ", spec, " (", ord_file, " not found, run 07_arima.R)")
    next
  }
  message("Part B: residual diagnostics of ", spec, " ...")
  ord <- as.matrix(read.csv(ord_file, row.names = 1))
  Xm  <- build_xreg(dates, cfg, op_temp = ARIMA_SPECS[[spec]]$op_temp, k_annual = K_ANNUAL)
  fits_tr <- lapply(0:23, function(h) {
    o <- ord[h + 1, ]
    Arima(ts(M[idx_tr, h + 1], frequency = 7), order = o[1:3],
          seasonal = list(order = o[4:6], period = 7),
          xreg = Xm[idx_tr, , drop = FALSE])
  })
  ssn <- season_of(dates[idx_tr])[keep]
  res_tab <- do.call(rbind, lapply(0:23, function(h) {
    r <- as.numeric(residuals(fits_tr[[h + 1]]))[keep]
    o <- ord[h + 1, ]
    data.frame(
      hour        = h,
      order       = sprintf("(%d,%d,%d)(%d,%d,%d)[7]", o[1], o[2], o[3], o[4], o[5], o[6]),
      lb_p        = Box.test(r, lag = LB_LAG, type = "Ljung-Box",
                             fitdf = o[1] + o[3] + o[4] + o[6])$p.value,
      shapiro_p   = shapiro.test(r)$p.value,
      sd_resid    = sd(r),
      sd_DJF      = sd(r[ssn == "DJF"]),
      sd_JJA      = sd(r[ssn == "JJA"]),
      sd_ratio    = sd(r[ssn == "DJF"]) / sd(r[ssn == "JJA"]),
      max_abs_acf = max(abs(acf(r, lag.max = 28, plot = FALSE)$acf[-1])),
      acf_band    = 1.96 / sqrt(length(r))
    )
  }))
  res_tab[, c(3, 4)]  <- round(res_tab[, c(3, 4)], 4)
  res_tab[, c(5:7)]   <- round(res_tab[, c(5:7)], 0)
  res_tab[, c(8:10)]  <- round(res_tab[, c(8:10)], 3)
  print(res_tab)
  write.csv(res_tab, sprintf("outputs/residual_diagnostics_train_%s.csv", spec), row.names = FALSE)
  message(spec, ": Ljung-Box rejects white noise (p < 0.05) for ",
          sum(res_tab$lb_p < 0.05), " of 24 hours")

  png(sprintf("outputs/figures/residuals_train_%s.png", spec), width = 1400, height = 900)
  par(mfrow = c(3, length(H_SHOW)))
  for (h in H_SHOW)
    plot(dates[idx_tr], as.numeric(residuals(fits_tr[[h + 1]])), type = "l",
         xlab = "", ylab = "MW", main = paste(spec, "residuals, hour", h))
  for (h in H_SHOW)
    acf(as.numeric(residuals(fits_tr[[h + 1]]))[keep], lag.max = 28,
        main = paste(spec, "residual ACF, hour", h))
  for (h in H_SHOW) {
    r <- as.numeric(residuals(fits_tr[[h + 1]]))[keep]
    qqnorm(r, main = paste(spec, "QQ plot, hour", h)); qqline(r)
  }
  dev.off()
}

# ======================= C. Out-of-sample forecast errors ===================
# NB: a 2-step-ahead error (hours 14-23) is expected to be autocorrelated at lag 1
# by construction, so read the ARIMA numbers with that in mind.
ab <- readRDS(paste0("outputs/ablation_", EVAL_SPLIT, ".rds"))
obs <- ab$obs
E <- list()
for (spec in names(ARIMA_SPECS)) {
  f <- sprintf("outputs/%s_%s.rds", spec, EVAL_SPLIT)
  if (file.exists(f)) {
    ar <- readRDS(f)
    stopifnot(all(ar$targets == ab$targets))
    E[[spec]] <- ar$pred - obs
  }
}
for (nm in intersect(c("cal_lags", "cal_lags_tempJ", "cal_lags_no13", "FULL_PERFECT_WX"),
                     names(ab$pred)))
  E[[nm]] <- ab$pred[[nm]] - obs

acf_at <- function(x, k) acf(x, lag.max = k, plot = FALSE)$acf[k + 1]
err_tab <- do.call(rbind, lapply(names(E), function(nm) {
  b <- rowMeans(E[[nm]])                              # daily mean signed error
  data.frame(model = nm, mean_error = round(mean(b), 0), sd_daily_error = round(sd(b), 0),
             acf_lag1 = round(acf_at(b, 1), 3), acf_lag7 = round(acf_at(b, 7), 3),
             lb_p_lag14 = round(Box.test(b, lag = 14, type = "Ljung-Box")$p.value, 4))
}))
print(err_tab)
write.csv(err_tab, paste0("outputs/forecast_error_diagnostics_", EVAL_SPLIT, ".csv"),
          row.names = FALSE)

show <- intersect(c(names(ARIMA_SPECS)[length(ARIMA_SPECS)], "cal_lags", "cal_lags_tempJ"),
                  names(E))
ref  <- E[[tail(intersect(c("cal_lags", "cal_lags_tempJ"), names(E)), 1)]]
png(paste0("outputs/figures/forecast_errors_", EVAL_SPLIT, ".png"),
    width = 450 * (length(show) + 1), height = 450)
par(mfrow = c(1, length(show) + 1))
for (nm in show) acf(rowMeans(E[[nm]]), lag.max = 21, main = paste("ACF daily mean error:", nm))
image(0:23, 0:23, cor(ref), col = hcl.colors(20), zlim = c(-1, 1),
      xlab = "hour", ylab = "hour", main = "Error correlation across hours")
dev.off()

message("Wrote outputs/stationarity_tests_train.csv, residual_diagnostics_train_<version>.csv, ",
        "forecast_error_diagnostics_", EVAL_SPLIT, ".csv and figures/")
