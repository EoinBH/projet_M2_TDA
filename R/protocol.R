# protocol.R --------------------------------------------------------------
# Forecast protocol: configuration, data loading, availability rules,
# chronological splits and evaluation metrics.
# Not run on its own: sourced at the start of scripts 05 to 10 (source("R/protocol.R")).

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(lubridate)
})

# ---- 1. Configuration (EDIT column names after checking names(read_csv(...))) ----
cfg <- list(
  data_path    = "data/processed/modelling_dataset.csv",
  col_time_utc = "datetime_utc",    # UTC timestamp column of modelling_dataset.csv
  col_target   = "consommation",    # RTE consumption column (MW, hourly mean)
  tz           = "Europe/Paris",
  origin_hour  = 14,                # forecast issued at 14:00 local on day J
  last_obs_h   = 13,                # last COMPLETE hour known at 14:00 = hour 13 (13:00-14:00)
  train_end    = as.Date("2023-12-31"),
  val_end      = as.Date("2024-12-31")   # test = 2025 (do NOT tune on it)
)

# ---- 2. Load and reshape: one row per local date, 24 columns (hours 0..23) ----
load_wide <- function(cfg) {
  d <- read_csv(cfg$data_path, show_col_types = FALSE)
  stopifnot(cfg$col_time_utc %in% names(d), cfg$col_target %in% names(d))

  d <- tibble(
    t_utc = as.POSIXct(d[[cfg$col_time_utc]], tz = "UTC"),
    y     = d[[cfg$col_target]]
  )
  d$loc  <- with_tz(d$t_utc, cfg$tz)
  d$date <- as.Date(d$loc, tz = cfg$tz)
  d$h    <- hour(d$loc)

  # Autumn repeated hour -> averaged; spring missing hour -> NA (filled below)
  long <- d |>
    group_by(date, h) |>
    summarise(y = mean(y, na.rm = TRUE), .groups = "drop")
  long$y[is.nan(long$y)] <- NA_real_

  dates <- seq(min(long$date), max(long$date), by = "day")
  M <- matrix(NA_real_, length(dates), 24,
              dimnames = list(as.character(dates), paste0("h", 0:23)))
  M[cbind(match(long$date, dates), long$h + 1)] <- long$y

  # Gap filling by last observation carried forward (uses only the past: no leakage)
  v  <- as.vector(t(M))
  ok <- !is.na(v)
  n_filled <- sum(!ok)
  idx <- cummax(ifelse(ok, seq_along(v), 0L))
  v[idx > 0] <- v[idx[idx > 0]]
  M <- matrix(v, nrow = length(dates), ncol = 24, byrow = TRUE,
              dimnames = dimnames(M))
  message("Gap-filled hourly values (LOCF): ", n_filled)

  list(dates = dates, M = M)
}

# ---- 3. Information available at the forecast origin ----
# For origin day J, the consumption known at 14:00 is: all days < J,
# plus hours 0..last_obs_h of day J. Returns a numeric hourly vector.
available_series <- function(W, J, cfg) {
  j <- match(J, W$dates)
  stopifnot(!is.na(j))
  past  <- if (j > 1) as.vector(t(W$M[1:(j - 1), , drop = FALSE])) else numeric(0)
  today <- W$M[j, 1:(cfg$last_obs_h + 1)]
  c(past, today)
}

# ---- 4. Chronological split, defined on the TARGET date (J+1) ----
split_of <- function(target_dates, cfg) {
  ifelse(target_dates <= cfg$train_end, "train",
         ifelse(target_dates <= cfg$val_end, "val", "test"))
}

# ---- 4b. ARIMA model versions (shared by scripts 07 and 10) ----
# Each version is saved separately (outputs/<name>_<split>.rds, <name>_orders.csv)
# and logged in outputs/model_log.csv. Add a new version here, never overwrite one.
ARIMA_SPECS <- list(
  arima_v1 = list(
    op_temp     = FALSE,
    description = "calendar + annual Fourier regressors, no weather",
    hypothesis  = "time-series baseline (seasonal ARIMA per hour)"),
  arima_v2 = list(
    op_temp     = TRUE,
    description = "v1 + operational temperature known at 14:00 on day J (3-hourly SYNOP up to 09:00 UTC, mean of day J-1)",
    hypothesis  = "v1 residuals are autocorrelated and 2-3 times more variable in winter (script 10): missing temperature effect")
)

# ---- 4c. Operational temperature (deployable at 14:00) ----
# One row per TARGET date D = J+1, built only from observations available at 14:00
# on day J: RAW 3-hourly national SYNOP observations (no hourly interpolation, which
# would use later observations) up to 09:00 UTC on day J, and the full day J-1.
#   op_t_last  : last observation <= 09:00 UTC on day J
#   op_t_morn  : mean of the observations 00-09 UTC on day J
#   op_t_prev  : mean of all observations of day J-1
#   op_hdd_*   : heating degrees below t_heat for the two means
# Missing values are carried forward (leading gaps filled backwards: first day only).
op_temp_features <- function(dates, cfg, path = "data/processed/weather_3hourly.csv",
                             cutoff_utc_hour = 9, t_heat = 15) {
  w <- read_csv(path, show_col_types = FALSE,
                col_select = all_of(c(cfg$col_time_utc, "t")))
  tu   <- as.POSIXct(w[[cfg$col_time_utc]], tz = "UTC")
  temp <- w$t
  if (median(temp, na.rm = TRUE) > 100) temp <- temp - 273.15     # Kelvin -> deg C
  day <- as.Date(tu); hr <- hour(tu); ok <- !is.na(temp)
  morn   <- ok & hr <= cutoff_utc_hour
  t_morn <- tapply(temp[morn], day[morn], mean)
  t_last <- tapply(temp[morn], day[morn], function(x) x[length(x)])
  t_full <- tapply(temp[ok],   day[ok],   mean)
  pick <- function(v, d) as.numeric(v[as.character(d)])
  J <- dates - 1
  out <- data.frame(op_t_last = pick(t_last, J),
                    op_t_morn = pick(t_morn, J),
                    op_t_prev = pick(t_full, J - 1))
  for (nm in names(out)) {
    x <- zoo::na.locf(out[[nm]], na.rm = FALSE)
    out[[nm]] <- zoo::na.locf(x, fromLast = TRUE, na.rm = FALSE)
  }
  out$op_hdd_morn <- pmax(t_heat - out$op_t_morn, 0)
  out$op_hdd_prev <- pmax(t_heat - out$op_t_prev, 0)
  out
}

# ---- 4d. Daily regressors for the ARIMA models (rows aligned with `dates`) ----
build_xreg <- function(dates, cfg, op_temp = FALSE, k_annual = 2) {
  cal_cols <- c(holiday = "is_public_holiday", eve = "is_holiday_eve",
                vacA = "school_holiday_A", vacB = "school_holiday_B",
                vacC = "school_holiday_C")
  d <- read_csv(cfg$data_path, show_col_types = FALSE,
                col_select = any_of(c(cfg$col_time_utc, unname(cal_cols))))
  d$date <- as.Date(with_tz(as.POSIXct(d[[cfg$col_time_utc]], tz = "UTC"), cfg$tz),
                    tz = cfg$tz)
  found <- cal_cols[cal_cols %in% names(d)]
  if (length(found) < length(cal_cols))
    warning("Missing calendar columns: ", paste(setdiff(cal_cols, found), collapse = ", "))
  to_bin <- function(x) {
    if (is.numeric(x) || is.logical(x)) as.numeric(x > 0)
    else as.numeric(toupper(as.character(x)) %in% c("TRUE", "1", "OUI", "YES"))
  }
  cal <- d |>
    group_by(date) |>
    summarise(across(all_of(unname(found)), ~ max(c(0, to_bin(.x)), na.rm = TRUE)),
              .groups = "drop")
  names(cal)[-1] <- names(found)
  X <- left_join(data.frame(date = dates), cal, by = "date")
  X[is.na(X)] <- 0
  tt <- as.numeric(dates - as.Date("2022-01-01"))
  for (k in seq_len(k_annual)) {
    X[[paste0("s", k)]] <- sin(2 * pi * k * tt / 365.25)
    X[[paste0("c", k)]] <- cos(2 * pi * k * tt / 365.25)
  }
  if (op_temp) X <- cbind(X, op_temp_features(dates, cfg))
  Xm <- as.matrix(X[, -1, drop = FALSE])
  keep <- apply(Xm[dates <= cfg$train_end, , drop = FALSE], 2, sd) > 0
  Xm[, keep, drop = FALSE]
}

# ---- 4e. Model log: one row per (version, split), replaced when re-run ----
log_model <- function(version, family, description, hypothesis, split, mae, rmse,
                      file = "outputs/model_log.csv") {
  row <- data.frame(version = version, family = family, description = description,
                    hypothesis = hypothesis, split = split,
                    MAE = round(unname(mae), 1), RMSE = round(unname(rmse), 1),
                    run_at = format(Sys.time(), "%Y-%m-%d %H:%M"),
                    stringsAsFactors = FALSE)
  old <- if (file.exists(file)) read.csv(file, stringsAsFactors = FALSE) else NULL
  if (!is.null(old)) old <- old[!(old$version == version & old$split == split), ]
  dir.create(dirname(file), showWarnings = FALSE)
  write.csv(rbind(old, row), file, row.names = FALSE)
}

# ---- 5. Metrics (obs, pred = n x 24 matrices, one row per target day) ----
score <- function(obs, pred) {
  e <- pred - obs
  c(
    MAE            = mean(abs(e)),
    RMSE           = sqrt(mean(e^2)),
    MAE_daily_tot  = mean(abs(rowSums(pred) - rowSums(obs))),
    MAE_peak_value = mean(abs(apply(pred, 1, max) - apply(obs, 1, max))),
    MAE_peak_hour  = mean(abs(apply(pred, 1, which.max) - apply(obs, 1, which.max)))
  )
}
