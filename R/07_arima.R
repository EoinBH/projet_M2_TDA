# 07_arima.R --------------------------------------------------------------
# One seasonal ARIMA (regression with ARIMA errors) per hour of the day, for each
# model version listed in ARIMA_SPECS (defined in protocol.R):
#   arima_v1 : calendar + annual Fourier regressors, no weather
#   arima_v2 : v1 + operational temperature available at 14:00 on day J
# Series for hour h = daily values of consumption at hour h, weekly period 7.
#
# Availability at 14:00 on day J for target day D = J+1:
#   hour h <= 13 : series known up to day J   -> 1-step-ahead forecast
#   hour h >= 14 : series known up to day J-1 -> 2-step-ahead forecast
#
# Each version is saved separately (outputs/<version>_<split>.rds). A version whose
# results already exist is skipped, so v1 is never recomputed unless FORCE_RERUN.
# Expensive step (about 45 min per version on the validation year): the script
# prints the progress of every hour and every block, with an estimated time left.
# Usage: source("R/07_arima.R")

source("R/protocol.R")
if (!requireNamespace("forecast", quietly = TRUE))
  stop("Package 'forecast' is required (install.packages('forecast')).")
suppressPackageStartupMessages(library(forecast))
dir.create("outputs", showWarnings = FALSE)

# ---- Settings ----
EVAL_SPLIT   <- "val"                 # use "test" ONLY once, for the final evaluation
REFIT_EVERY  <- 28                    # re-estimate coefficients every 28 target days
K_ANNUAL     <- 2                     # number of annual Fourier pairs
SPECS_TO_RUN <- names(ARIMA_SPECS)    # e.g. "arima_v2" to run only the new version
FORCE_RERUN  <- FALSE                 # TRUE recomputes versions whose results exist

W <- load_wide(cfg); M <- W$M; dates <- W$dates
pos <- function(d) match(d, dates)
idx_tr  <- which(dates <= cfg$train_end)
targets <- dates[29:length(dates)]
tg  <- targets[split_of(targets, cfg) == EVAL_SPLIT]
obs <- M[pos(tg), ]

elapsed <- function(t0) as.numeric(difftime(Sys.time(), t0, units = "secs"))
fmt_min <- function(sec) sprintf("%.1f min", sec / 60)
rds_path <- function(name) sprintf("outputs/%s_%s.rds", name, EVAL_SPLIT)

run_spec <- function(name) {
  spec <- ARIMA_SPECS[[name]]
  if (!FORCE_RERUN && file.exists(rds_path(name))) {
    message("[", name, "] results already exist (", rds_path(name),
            "): skipped. Set FORCE_RERUN <- TRUE to recompute.")
    return(invisible(FALSE))
  }
  t0 <- Sys.time()
  message("\n==== ", name, ": ", spec$description, " ====")
  Xm <- build_xreg(dates, cfg, op_temp = spec$op_temp, k_annual = K_ANNUAL)
  message("[", name, "] ", ncol(Xm), " regressors: ", paste(colnames(Xm), collapse = ", "))

  # ---- Step 1: select ARIMA orders on TRAIN ONLY (one per hour) ----
  message("[", name, "] Step 1/2: selecting the order of each of the 24 hourly models ",
          "on the training period (this step can take several minutes) ...")
  orders <- vector("list", 24)
  for (h in 0:23) {
    f <- auto.arima(ts(M[idx_tr, h + 1], frequency = 7),
                    xreg = Xm[idx_tr, , drop = FALSE],
                    seasonal = TRUE, stepwise = TRUE, approximation = TRUE)
    orders[[h + 1]] <- arimaorder(f)            # p d q P D Q period
    el <- elapsed(t0)
    message(sprintf("[%s] order selection: hour %02d/24 done, order (%s) | elapsed %s | step 1 ETA %s",
                    name, h, paste(orders[[h + 1]][1:6], collapse = ","),
                    fmt_min(el), fmt_min(el / (h + 1) * (23 - h))))
    flush.console()
  }
  ord_tab <- do.call(rbind, orders); rownames(ord_tab) <- paste0("h", 0:23)
  print(ord_tab)
  write.csv(ord_tab, sprintf("outputs/%s_orders.csv", name))

  # ---- Step 2: rolling forecasts with periodic re-estimation ----
  P <- matrix(NA_real_, length(tg), 24, dimnames = list(as.character(tg), paste0("h", 0:23)))
  fits <- vector("list", 24)
  starts <- seq(1, length(tg), by = REFIT_EVERY)
  t1 <- Sys.time()
  for (b in seq_along(starts)) {
    s <- starts[b]
    i1 <- min(s + REFIT_EVERY - 1, length(tg))
    fit_end <- pos(tg[s]) - 2          # last day complete for all hours at first origin
    message(sprintf("[%s] Step 2/2: block %d/%d, targets %s .. %s (refit + daily forecasts, hours 0-23)",
                    name, b, length(starts), tg[s], tg[i1]))
    cat("    hours done:")
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
      cat(" ", h, sep = ""); flush.console()
    }
    cat("\n")
    el <- elapsed(t1)
    message(sprintf("[%s] block %d/%d done | elapsed %s | step 2 ETA %s",
                    name, b, length(starts), fmt_min(el),
                    fmt_min(el / b * (length(starts) - b))))
  }

  saveRDS(list(targets = tg, pred = P, obs = obs, orders = ord_tab,
               spec = name, description = spec$description), rds_path(name))
  message("[", name, "] finished in ", fmt_min(elapsed(t0)), " -> ", rds_path(name))
  invisible(TRUE)
}

for (nm in SPECS_TO_RUN) run_spec(nm)

# ---- Evaluation against benchmarks on identical dates (all versions found) ----
res <- list()
for (nm in names(ARIMA_SPECS)) {
  if (!file.exists(rds_path(nm))) next
  ar <- readRDS(rds_path(nm))
  stopifnot(all(ar$targets == tg))
  res[[nm]] <- score(obs, ar$pred)
  log_model(nm, "ARIMA per hour", ARIMA_SPECS[[nm]]$description,
            ARIMA_SPECS[[nm]]$hypothesis, EVAL_SPLIT, res[[nm]]["MAE"], res[[nm]]["RMSE"])
}
if (file.exists("outputs/benchmarks.rds")) {
  B <- readRDS("outputs/benchmarks.rds")
  ib <- match(tg, B$targets)
  for (nm in names(B$preds)) res[[nm]] <- score(obs, B$preds[[nm]][ib, , drop = FALSE])
}
tab <- round(do.call(rbind, res), 1)
print(tab)
write.csv(tab, paste0("outputs/scores_", EVAL_SPLIT, ".csv"))
