# 08_ablation.R -----------------------------------------------------------
# Ablation study + perfect-weather benchmark, using a fast linear model
# (one OLS regression per hour of the day, same 14:00 availability rules).
#
# Groups of variables:
#   cal   : weekday, public holiday, holiday eve, school zones A/B/C, annual Fourier terms
#   lags  : consumption lags available at 14:00 on day J
#   wx    : OBSERVED weather of J+1 (temperature) -> "perfect weather", NOT deployable
#
# Full model = cal + lags + wx. Removing one group at a time shows its contribution.
# Does not need outputs of 06/07 (it only compares with them if they exist).
# Usage: source("R/08_ablation.R")

source("R/protocol.R")
dir.create("outputs", showWarnings = FALSE)

# ---- Settings ----
EVAL_SPLIT  <- "val"    # use "test" ONLY once, for the final evaluation
REFIT_EVERY <- 28       # same re-estimation frequency as 07_arima.R
K_ANNUAL    <- 2
col_temp    <- "t"      # SYNOP temperature column (Kelvin in Météo-France files; auto-converted)
T_HEAT      <- 15       # heating threshold (deg C)
T_COOL      <- 22       # cooling threshold (deg C)
cal_cols <- c(holiday = "is_public_holiday", eve = "is_holiday_eve",
              vacA = "school_holiday_A", vacB = "school_holiday_B",
              vacC = "school_holiday_C")

W <- load_wide(cfg); M <- W$M; dates <- W$dates; N <- length(dates)
pos <- function(d) match(d, dates)

# ---- Read dataset once (calendar + temperature) ----
d <- read_csv(cfg$data_path, show_col_types = FALSE)
d$loc  <- with_tz(as.POSIXct(d[[cfg$col_time_utc]], tz = "UTC"), cfg$tz)
d$date <- as.Date(d$loc, tz = cfg$tz)
d$h    <- hour(d$loc)

# Helper: hourly values -> matrix (days x 24), gaps filled by LOCF
to_wide <- function(date, h, v) {
  long <- tibble(date = date, h = h, v = v) |>
    group_by(date, h) |> summarise(v = mean(v, na.rm = TRUE), .groups = "drop")
  long$v[is.nan(long$v)] <- NA_real_
  long <- long[!is.na(match(long$date, dates)), ]
  A <- matrix(NA_real_, N, 24)
  A[cbind(match(long$date, dates), long$h + 1)] <- long$v
  x <- as.vector(t(A)); ok <- !is.na(x)
  idx <- cummax(ifelse(ok, seq_along(x), 0L))
  x[idx > 0] <- x[idx[idx > 0]]
  matrix(x, N, 24, byrow = TRUE)
}

# ---- Observed temperature (used ONLY in the perfect-weather group) ----
if (!col_temp %in% names(d))
  stop("Temperature column '", col_temp, "' not found. Columns: ",
       paste(head(names(d), 60), collapse = ", "))
temp <- d[[col_temp]]
if (median(temp, na.rm = TRUE) > 100) {
  message("Temperature looks like Kelvin -> converted to deg C.")
  temp <- temp - 273.15
}
TT <- to_wide(d$date, d$h, temp)

# ---- Daily calendar regressors ----
found <- cal_cols[cal_cols %in% names(d)]
if (length(found) < length(cal_cols))
  warning("Missing calendar columns: ", paste(setdiff(cal_cols, found), collapse = ", "))
to_bin <- function(x) {
  if (is.numeric(x) || is.logical(x)) as.numeric(x > 0)
  else as.numeric(toupper(as.character(x)) %in% c("TRUE", "1", "OUI", "YES"))
}
cal <- d |> group_by(date) |>
  summarise(across(all_of(unname(found)), ~ max(c(0, to_bin(.x)), na.rm = TRUE)),
            .groups = "drop")
names(cal)[-1] <- names(found)
CAL <- left_join(data.frame(date = dates), cal, by = "date")
CAL[is.na(CAL)] <- 0
tt <- as.numeric(dates - as.Date("2022-01-01"))
for (k in seq_len(K_ANNUAL)) {
  CAL[[paste0("s", k)]] <- sin(2 * pi * k * tt / 365.25)
  CAL[[paste0("c", k)]] <- cos(2 * pi * k * tt / 365.25)
}
CAL$wd <- factor(wday(dates, week_start = 1), levels = 1:7)

# ---- Features, one table per hour h (rows = target days D = dates[29..N]) ----
Dp <- 29:N
build_h <- function(h) {
  ci <- h + 1
  f <- data.frame(
    lag_w     = M[Dp - 7, ci],                                   # same weekday last week
    lag_d     = if (h <= cfg$last_obs_h) M[Dp - 1, ci] else M[Dp - 2, ci],  # latest known same hour
    lag_mean2 = rowMeans(M[Dp - 2, ]),                           # mean of last fully known day
    lag_last  = M[Dp - 1, cfg$last_obs_h + 1],                   # consumption at 13:00 on day J
    temp      = TT[Dp, ci],                                      # OBSERVED temperature of J+1
    hdd       = pmax(T_HEAT - TT[Dp, ci], 0),
    cdd       = pmax(TT[Dp, ci] - T_COOL, 0),
    hdd_day   = pmax(T_HEAT - rowMeans(TT[Dp, ]), 0),
    y         = M[Dp, ci]
  )
  cbind(f, CAL[Dp, setdiff(names(CAL), "date"), drop = FALSE])
}
F <- lapply(0:23, build_h)

grp <- list(
  cal  = intersect(c("wd", "holiday", "eve", "vacA", "vacB", "vacC", "s1", "c1", "s2", "c2"),
                   names(CAL)),
  lags = c("lag_w", "lag_d", "lag_mean2", "lag_last"),
  lags_no13 = c("lag_w", "lag_d", "lag_mean2"),
  wx   = c("temp", "hdd", "cdd", "hdd_day")
)
models <- list(
  cal_only            = "cal",
  lags_only           = "lags",
  cal_lags_no13       = c("cal", "lags_no13"),
  cal_lags            = c("cal", "lags"),          # simple OPERATIONAL linear model
  FULL_PERFECT_WX     = c("cal", "lags", "wx"),    # upper bound, not deployable
  noCal_PERFECT_WX    = c("lags", "wx"),
  noLags_PERFECT_WX   = c("cal", "wx")
)

# ---- Rolling forecasts with periodic re-estimation ----
targets <- dates[29:N]
tg <- targets[split_of(targets, cfg) == EVAL_SPLIT]
P  <- lapply(models, function(m) matrix(NA_real_, length(tg), 24))

for (s in seq(1, length(tg), by = REFIT_EVERY)) {
  i1 <- min(s + REFIT_EVERY - 1, length(tg))
  D0 <- pos(tg[s])
  train_rows <- which(Dp <= D0 - 2)             # outcomes fully known at the first origin
  test_rows  <- match(pos(tg[s:i1]), Dp)
  message("Refit for targets ", tg[s], " .. ", tg[i1])
  for (h in 0:23) {
    Fh <- F[[h + 1]]
    for (nm in names(models)) {
      vars <- unlist(grp[models[[nm]]])
      tr <- Fh[train_rows, c("y", vars)]
      tr <- tr[complete.cases(tr), ]
      fit <- lm(y ~ ., data = tr)
      P[[nm]][s:i1, h + 1] <- suppressWarnings(predict(fit, Fh[test_rows, vars, drop = FALSE]))
    }
  }
}

# ---- Evaluation ----
obs <- M[pos(tg), ]
sc <- t(sapply(P, function(p) score(obs, p)))
res <- data.frame(model = rownames(sc), sc, deployable = !grepl("PERFECT", rownames(sc)),
                  row.names = NULL)

ref_file <- paste0("outputs/scores_", EVAL_SPLIT, ".csv")   # ARIMA + benchmarks from 06/07
if (file.exists(ref_file)) {
  ref <- read.csv(ref_file, row.names = 1)
  res <- rbind(res, data.frame(model = rownames(ref), ref, deployable = TRUE, row.names = NULL))
}
res[, 2:6] <- round(res[, 2:6], 1)
print(res)
write.csv(res, paste0("outputs/ablation_scores_", EVAL_SPLIT, ".csv"), row.names = FALSE)

# Ablation table: remove one group from the full (perfect-weather) model
mae <- setNames(res$MAE, res$model)
abl <- data.frame(
  removed_group = c("none (full model)", "weather", "calendar", "lags"),
  MAE = mae[c("FULL_PERFECT_WX", "cal_lags", "noCal_PERFECT_WX", "noLags_PERFECT_WX")]
)
abl$MAE_increase <- round(abl$MAE - abl$MAE[1], 1)
print(abl)
write.csv(abl, paste0("outputs/ablation_groups_", EVAL_SPLIT, ".csv"), row.names = FALSE)

saveRDS(list(targets = tg, obs = obs, pred = P),
        paste0("outputs/ablation_", EVAL_SPLIT, ".rds"))
