# 07_arima.R --------------------------------------------------------------
# One seasonal ARIMA (regression with ARIMA errors) per hour of the day.
# Series for hour h = daily values of consumption at hour h, weekly period 7.
# Regressors known in advance only: holidays, holiday eve, school-holiday
# zones A/B/C, annual Fourier terms. NO observed weather (operational model).
#
# Availability at 14:00 on day J for target day D = J+1:
#   hour h <= 13 : series known up to day J   -> 1-step-ahead forecast
#   hour h >= 14 : series known up to day J-1 -> 2-step-ahead forecast
#
# Expensive step: ~ several minutes (24 models x daily one/two-step forecasts).
# Usage: source("R/07_arima.R")

source("R/05_protocol.R")
if (!requireNamespace("forecast", quietly = TRUE))
  stop("Package 'forecast' is required (install.packages('forecast')).")
suppressPackageStartupMessages(library(forecast))
dir.create("outputs", showWarnings = FALSE)

# ---- Settings ----
EVAL_SPLIT  <- "val"   # use "test" ONLY once, for the final evaluation
REFIT_EVERY <- 28      # re-estimate coefficients every 28 target days
K_ANNUAL    <- 2       # number of annual Fourier pairs
# Calendar column names in modelling_dataset.csv (checked against 03_prepare_calendar.R):
cal_cols <- c(holiday = "is_public_holiday", eve = "is_holiday_eve",
              vacA = "school_holiday_A", vacB = "school_holiday_B",
              vacC = "school_holiday_C")

W <- load_wide(cfg); M <- W$M; dates <- W$dates
pos <- function(d) match(d, dates)

# ---- Daily calendar regressors ----
d <- read_csv(cfg$data_path, show_col_types = FALSE)
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
for (k in seq_len(K_ANNUAL)) {
  X[[paste0("s", k)]] <- sin(2 * pi * k * tt / 365.25)
  X[[paste0("c", k)]] <- cos(2 * pi * k * tt / 365.25)
}
Xm <- as.matrix(X[, -1, drop = FALSE])
Xm <- Xm[, apply(Xm[dates <= cfg$train_end, , drop = FALSE], 2, sd) > 0, drop = FALSE]

# ---- Step 1: select ARIMA orders on TRAIN ONLY (one per hour) ----
message("Selecting orders on the training period...")
idx_tr <- which(dates <= cfg$train_end)
orders <- lapply(0:23, function(h) {
  f <- auto.arima(ts(M[idx_tr, h + 1], frequency = 7),
                  xreg = Xm[idx_tr, , drop = FALSE],
                  seasonal = TRUE, stepwise = TRUE, approximation = TRUE)
  arimaorder(f)   # p d q P D Q period
})
ord_tab <- do.call(rbind, orders); rownames(ord_tab) <- paste0("h", 0:23)
print(ord_tab)
write.csv(ord_tab, "outputs/arima_orders.csv")

# ---- Step 2: rolling forecasts with periodic re-estimation ----
targets <- dates[29:length(dates)]
tg <- targets[split_of(targets, cfg) == EVAL_SPLIT]
P  <- matrix(NA_real_, length(tg), 24, dimnames = list(as.character(tg), paste0("h", 0:23)))
fits <- vector("list", 24)

starts <- seq(1, length(tg), by = REFIT_EVERY)
for (s in starts) {
  i1 <- min(s + REFIT_EVERY - 1, length(tg))
  fit_end <- pos(tg[s]) - 2          # last day complete for all hours at first origin
  message("Refit for targets ", tg[s], " .. ", tg[i1])
  for (h in 0:23) {
    o <- orders[[h + 1]]
    idx <- 1:fit_end
    f <- tryCatch(
      Arima(ts(M[idx, h + 1], frequency = 7), order = o[1:3],
            seasonal = list(order = o[4:6], period = 7),
            xreg = Xm[idx, , drop = FALSE]),
      error = function(e) NULL)
    if (!is.null(f)) fits[[h + 1]] <- f        # otherwise keep previous fit
    for (i in s:i1) {
      D   <- pos(tg[i])
      cut <- if (h <= cfg$last_obs_h) D - 1 else D - 2   # last day known at 14:00 on J
      m  <- Arima(ts(M[1:cut, h + 1], frequency = 7), model = fits[[h + 1]],
                  xreg = Xm[1:cut, , drop = FALSE])
      fc <- forecast(m, h = D - cut, xreg = Xm[(cut + 1):D, , drop = FALSE])
      P[i, h + 1] <- as.numeric(fc$mean)[D - cut]
    }
  }
}

# ---- Step 3: evaluation against benchmarks on identical dates ----
obs <- M[pos(tg), ]
saveRDS(list(targets = tg, pred = P, obs = obs, orders = ord_tab),
        paste0("outputs/arima_", EVAL_SPLIT, ".rds"))

res <- list(ARIMA_per_hour = score(obs, P))
if (file.exists("outputs/benchmarks.rds")) {
  B <- readRDS("outputs/benchmarks.rds")
  ib <- match(tg, B$targets)
  for (nm in names(B$preds)) res[[nm]] <- score(obs, B$preds[[nm]][ib, , drop = FALSE])
}
tab <- round(do.call(rbind, res), 1)
print(tab)
write.csv(tab, paste0("outputs/scores_", EVAL_SPLIT, ".csv"))
