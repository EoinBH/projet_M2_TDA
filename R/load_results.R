# load_results.R ----------------------------------------------------------
# Shared read-only loader for scripts 11 and 12 (no model is refitted).
# Set EVAL_SPLIT <- "val" or "test" BEFORE sourcing (default "val").
# Provides: obs, tg, P (named list of n x 24 forecast matrices), OPER (deployable
# models), ab (ablation object), ctx (daily context: season, day type, temperature).

source("R/protocol.R")
if (!exists("EVAL_SPLIT")) EVAL_SPLIT <- "val"
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

ab <- readRDS(paste0("outputs/ablation_", EVAL_SPLIT, ".rds"))
arima_files <- Sys.glob(paste0("outputs/arima_v*_", EVAL_SPLIT, ".rds"))
stopifnot("no arima_v*_<split>.rds found" = length(arima_files) > 0)
AR <- setNames(lapply(arima_files, readRDS),
               sub(paste0("_", EVAL_SPLIT, "\\.rds$"), "", basename(arima_files)))
bm <- readRDS("outputs/benchmarks.rds")
tg <- ab$targets; obs <- ab$obs
stopifnot(all(sapply(AR, function(a) all(a$targets == tg))))
ib <- match(tg, bm$targets)
stopifnot("benchmarks.rds does not cover these target dates (re-run 06 for this split?)" = !anyNA(ib))

lin <- intersect(c("cal_lags", "cal_lags_tempJ"), names(ab$pred))
P <- c(ab$pred[lin],
       lapply(AR, function(a) a$pred),
       lapply(bm$preds, function(p) p[ib, , drop = FALSE]),
       list(FULL_PERFECT_WX = ab$pred$FULL_PERFECT_WX))
OPER <- setdiff(names(P), "FULL_PERFECT_WX")

# ---- daily context ----
to_bin <- function(x) {
  if (is.numeric(x) || is.logical(x)) as.numeric(x > 0)
  else as.numeric(toupper(as.character(x)) %in% c("TRUE", "1", "OUI", "YES"))
}
d <- read_csv(cfg$data_path, show_col_types = FALSE,
              col_select = any_of(c(cfg$col_time_utc, "t", "is_public_holiday")))
d$date <- as.Date(with_tz(as.POSIXct(d[[cfg$col_time_utc]], tz = "UTC"), cfg$tz), tz = cfg$tz)
temp <- d$t
if (median(temp, na.rm = TRUE) > 100) temp <- temp - 273.15
tmean <- tapply(temp, d$date, mean, na.rm = TRUE)
hol <- tapply(to_bin(d$is_public_holiday), d$date, max)
ctx <- data.frame(date = tg, tmean = as.numeric(tmean[as.character(tg)]),
                  holiday = as.numeric(hol[as.character(tg)]))
wd <- wday(tg, week_start = 1); m <- month(tg)
ctx$daytype <- ifelse(ctx$holiday == 1, "public_holiday",
                ifelse(wd == 6, "Saturday", ifelse(wd == 7, "Sunday", "Weekday")))
ctx$season <- ifelse(m %in% c(12, 1, 2), "DJF", ifelse(m %in% 3:5, "MAM",
               ifelse(m %in% 6:8, "JJA", "SON")))
ctx$regime <- ifelse(ctx$tmean < 5, "cold (<5C)", ifelse(ctx$tmean > 20, "hot (>20C)", "mild"))
message("Loaded split '", EVAL_SPLIT, "': ", length(tg), " target days, models: ",
        paste(names(P), collapse = ", "))
