# 11_tests_and_bias.R -----------------------------------------------------
# Read-only analysis of existing forecasts (no refitting, runs in seconds):
#   1. paired tests of "is model A really better than B?" (Diebold-Mariano with
#      Newey-West variance + moving-block bootstrap CI), on daily losses
#   2. mean error (bias) and MAE by month, per model
#   3. ranking stability: by metric, by quarter, by hour
# Usage: EVAL_SPLIT <- "val"; source("R/11_tests_and_bias.R")   (or "test")
# Sign convention: error = forecast - observed; mean_diff = loss(A) - loss(B), negative = A better.

source("R/load_results.R")
SPL <- EVAL_SPLIT
dm <- sapply(P, function(p) rowMeans(abs(p - obs)))     # daily MAE, days x models
dq <- sapply(P, function(p) rowMeans((p - obs)^2))      # daily MSE
de <- sapply(P, function(p) rowMeans(p - obs))          # daily mean error (bias)

# ---- 1. Paired tests ----
dm_test <- function(d, lag = 7) {
  n <- length(d); dbar <- mean(d); dc <- d - dbar
  g <- function(k) sum(dc[(k + 1):n] * dc[1:(n - k)]) / n
  lrv <- g(0) + 2 * sum(sapply(1:lag, function(k) (1 - k / (lag + 1)) * g(k)))
  if (lrv <= 0) return(c(dbar, NA, NA))
  st <- dbar / sqrt(lrv / n)
  c(dbar, st, 2 * pnorm(-abs(st)))
}
boot_ci <- function(d, block = 7, B = 2000) {
  set.seed(1); n <- length(d); nb <- ceiling(n / block)
  mm <- replicate(B, {
    st <- sample.int(n - block + 1, nb, replace = TRUE)
    mean(unlist(lapply(st, function(s) d[s:(s + block - 1)]))[1:n])
  })
  quantile(mm, c(0.025, 0.975))
}
pairs <- list(c("cal_lags_tempJ", "cal_lags"), c("arima_v2", "cal_lags"),
              c("arima_v2", "arima_v1"), c("cal_lags_tempJ", "arima_v2"),
              c("cal_lags", "B1_prev_day_strict"), c("cal_lags", "B2_same_weekday_lw"))
pairs <- Filter(function(p) all(p %in% colnames(dm)), pairs)
rows <- list()
for (p in pairs) for (loss in c("MAE", "MSE")) {
  L <- if (loss == "MAE") dm else dq
  d <- unname(L[, p[1]] - L[, p[2]])
  r <- dm_test(d); ci <- boot_ci(d)
  rows[[length(rows) + 1]] <- data.frame(
    A = p[1], B = p[2], loss = loss,
    mean_diff = round(r[1], 1), ci95_low = round(ci[[1]], 1), ci95_high = round(ci[[2]], 1),
    dm_stat = round(r[2], 2), p_value = signif(r[3], 3),
    verdict = ifelse(is.na(r[3]) || r[3] >= 0.05, "no significant difference",
                     paste(ifelse(r[1] < 0, p[1], p[2]), "better (p<0.05)")))
}
tests <- do.call(rbind, rows)
write.csv(tests, paste0("outputs/paired_tests_", SPL, ".csv"), row.names = FALSE)
cat("\n== Paired tests (", SPL, ", ", length(tg), " days) ==\n", sep = ""); print(tests, row.names = FALSE)

# ---- 2. Bias and MAE by month ----
mon <- format(tg, "%Y-%m")
by_mon <- function(M) t(sapply(split(seq_along(tg), mon), function(i) colMeans(M[i, , drop = FALSE])))
bias_m <- by_mon(de); mae_m <- by_mon(dm)
write.csv(round(bias_m, 0), paste0("outputs/bias_by_month_", SPL, ".csv"))
write.csv(round(mae_m, 0),  paste0("outputs/mae_by_month_", SPL, ".csv"))
cat("\n== Mean error by model (MW, forecast - observed) ==\n"); print(round(colMeans(de)[OPER], 0))
cat("\n== Mean error by month (MW) ==\n")
print(round(bias_m[, intersect(c("cal_lags", "cal_lags_tempJ", "arima_v2", "FULL_PERFECT_WX"), colnames(bias_m))], 0))

SEL <- intersect(c("cal_lags", "cal_lags_tempJ", "arima_v2", "B1_prev_day_strict"), colnames(dm))
cols <- c("firebrick", "darkorange", "steelblue", "grey40")[seq_along(SEL)]
month_plot <- function(M, file, ylab, main, zero = FALSE) {
  png(file, width = 1100, height = 550, res = 110)
  matplot(M[, SEL], type = "b", pch = 16, lty = 1, col = cols, xaxt = "n", xlab = "", ylab = ylab, main = main)
  axis(1, at = seq_len(nrow(M)), labels = rownames(M), las = 2, cex.axis = 0.8)
  if (zero) abline(h = 0, lty = 2)
  legend("topright", SEL, col = cols, pch = 16, lty = 1, cex = 0.8, bg = "white")
  dev.off()
}
month_plot(bias_m, paste0("outputs/figures/bias_by_month_", SPL, ".png"), "Mean error (MW)",
           paste("Mean error by month (forecast - observed) -", SPL), zero = TRUE)
month_plot(mae_m, paste0("outputs/figures/mae_by_month_", SPL, ".png"), "MAE (MW)",
           paste("MAE by month -", SPL))

# ---- 3. Ranking stability (deployable models only; 1 = best) ----
Sm <- t(sapply(P[OPER], function(p) score(obs, p)))
rank_metric <- apply(Sm, 2, rank)
q <- quarters(tg)
mq <- t(sapply(split(seq_along(tg), q), function(i) colMeans(dm[i, OPER, drop = FALSE])))
rank_q <- t(apply(mq, 1, rank))
mae_h <- sapply(P[OPER], function(p) colMeans(abs(p - obs)))
hours_best <- table(factor(OPER[apply(mae_h, 1, which.min)], levels = OPER))
write.csv(rank_metric, paste0("outputs/rank_by_metric_", SPL, ".csv"))
write.csv(rank_q, paste0("outputs/rank_by_quarter_", SPL, ".csv"))
write.csv(as.data.frame(hours_best), paste0("outputs/hours_best_", SPL, ".csv"), row.names = FALSE)
cat("\n== Rank by metric ==\n"); print(rank_metric)
cat("\n== Rank by quarter (MAE) ==\n"); print(rank_q)
cat("\n== Number of hours (of 24) where each model has the lowest MAE ==\n"); print(hours_best)
message("Wrote outputs/paired_tests_, bias_by_month_, mae_by_month_, rank_by_* and hours_best_ files (", SPL, ") and 2 figures.")
