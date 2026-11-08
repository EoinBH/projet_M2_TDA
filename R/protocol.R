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
