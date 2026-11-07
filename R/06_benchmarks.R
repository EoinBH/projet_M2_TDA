# 06_benchmarks.R ---------------------------------------------------------
# Simple benchmarks respecting the 14:00 information constraint.
# Usage: source("R/06_benchmarks.R")   (sources 05_protocol.R itself)

source("R/05_protocol.R")
dir.create("outputs", showWarnings = FALSE)

W <- load_wide(cfg)
M <- W$M
dates <- W$dates

# Target days D = J+1; start after 28 days of history
targets <- dates[29:length(dates)]
sp <- split_of(targets, cfg)
row_of <- function(d) match(d, dates)

# --- B1: "strict" previous day -------------------------------------------
# Naive D-1 (value of day J, same hour) is NOT fully available at 14:00:
# hours 14..23 of day J are still in the future. We use day J for hours
# 0..13 and day J-1 for hours 14..23 (documented leakage trap for the audit).
b1 <- t(sapply(targets, function(D) {
  j <- row_of(D) - 1                     # day J
  c(M[j, 1:14], M[j - 1, 15:24])
}))

# --- B2: same weekday last week (D-7), fully known at 14:00 ----------------
b2 <- t(sapply(targets, function(D) M[row_of(D) - 7, ]))

# --- B3: mean of the same weekday over the last 4 weeks -------------------
b3 <- t(sapply(targets, function(D) {
  r <- row_of(D) - c(7, 14, 21, 28)
  colMeans(M[r, , drop = FALSE])
}))

obs <- M[row_of(targets), ]
preds <- list(B1_prev_day_strict = b1, B2_same_weekday_lw = b2, B3_mean_4_weeks = b3)

# --- Evaluation on VALIDATION only (test set stays untouched) --------------
ev <- sp == "val"
res <- t(sapply(preds, function(p) score(obs[ev, ], p[ev, ])))
print(round(res, 1))
write.csv(round(res, 2), "outputs/benchmarks_validation.csv")

# Store benchmark forecasts for later model comparison on identical dates
saveRDS(list(targets = targets, split = sp, obs = obs, preds = preds),
        "outputs/benchmarks.rds")
