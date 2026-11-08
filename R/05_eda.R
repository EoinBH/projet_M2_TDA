# 05_eda.R ----------------------------------------------------------------
# Exploratory analysis of the modelling dataset, TRAINING PERIOD ONLY (nothing
# is learned from the validation or test years).
# Shows: daily and weekly cycles, annual seasonality, relation with temperature,
# calendar effects, level shift between 2022 and 2023, atypical days.
# Needs: data/processed/modelling_dataset.csv (step 04).
# Writes: outputs/figures/eda_*.png, outputs/eda_summary.csv, outputs/eda_atypical_days.csv
# Usage: source("R/05_eda.R")

source("R/protocol.R")
dir.create("outputs/figures", recursive = TRUE, showWarnings = FALSE)

invisible(local({

  season_of <- function(dt) {
    m <- month(dt)
    ifelse(m %in% c(12, 1, 2), "DJF", ifelse(m %in% 3:5, "MAM",
           ifelse(m %in% 6:8, "JJA", "SON")))
  }
  to_bin <- function(x) {
    if (is.numeric(x) || is.logical(x)) as.numeric(x > 0)
    else as.numeric(toupper(as.character(x)) %in% c("TRUE", "1", "OUI", "YES"))
  }

  # ---- Hourly data, training period ----
  d <- read_csv(cfg$data_path, show_col_types = FALSE)
  d$local <- with_tz(as.POSIXct(d[[cfg$col_time_utc]], tz = "UTC"), cfg$tz)
  d$date  <- as.Date(d$local, tz = cfg$tz)
  d$hour  <- hour(d$local)
  d <- d[d$date <= cfg$train_end, ]
  d$temp_c <- if (median(d$t, na.rm = TRUE) > 150) d$t - 273.15 else d$t  # SYNOP in Kelvin
  d$wd     <- wday(d$date, week_start = 1)
  d$season <- season_of(d$date)

  # ---- Daily table ----
  daily <- d |>
    group_by(date) |>
    summarise(cons = mean(consommation, na.rm = TRUE),
              temp = mean(temp_c, na.rm = TRUE),
              holiday = max(c(0, to_bin(is_public_holiday)), na.rm = TRUE),
              school  = max(c(0, to_bin(school_holiday_A), to_bin(school_holiday_B),
                              to_bin(school_holiday_C)), na.rm = TRUE),
              .groups = "drop")
  daily$wd     <- wday(daily$date, week_start = 1)
  daily$season <- season_of(daily$date)
  daily$year   <- year(daily$date)
  daily$roll7  <- zoo::rollmean(daily$cons, 7, fill = NA, align = "center")

  # Deviation from the median of the same weekday 1-3 weeks before and after
  n <- nrow(daily); k <- c(-21, -14, -7, 7, 14, 21)
  daily$ref <- sapply(seq_len(n), function(i) {
    j <- i + k
    median(daily$cons[j[j >= 1 & j <= n]], na.rm = TRUE)
  })
  daily$dev  <- daily$cons / daily$ref - 1
  daily$type <- ifelse(daily$holiday == 1, "public holiday",
                ifelse(daily$wd >= 6, "weekend",
                ifelse(daily$school == 1, "school holiday weekday", "ordinary weekday")))

  # ---- 1. Daily profile by season, weekday vs weekend ----
  prof <- d |>
    group_by(season, weekend = wd >= 6, hour) |>
    summarise(m = mean(consommation, na.rm = TRUE), .groups = "drop")
  seas <- c("DJF", "MAM", "JJA", "SON")
  cols <- c("royalblue", "forestgreen", "orange", "firebrick")
  png("outputs/figures/eda_daily_profile.png", width = 1200, height = 500)
  par(mfrow = c(1, 2))
  for (w in c(FALSE, TRUE)) {
    plot(NA, xlim = c(0, 23), ylim = range(prof$m), xlab = "hour (local)", ylab = "MW",
         main = if (w) "Weekend (Sat-Sun)" else "Weekday (Mon-Fri)")
    for (i in 1:4) {
      p <- prof[prof$season == seas[i] & prof$weekend == w, ]
      lines(p$hour, p$m, col = cols[i], lwd = 2)
    }
    legend("topleft", seas, col = cols, lwd = 2, bty = "n")
  }
  dev.off()

  # ---- 2. Weekly cycle ----
  png("outputs/figures/eda_weekly_cycle.png", width = 700, height = 500)
  boxplot(cons ~ factor(wd, labels = c("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")),
          data = daily, xlab = "", ylab = "Daily mean consumption (MW)", main = "Weekly cycle")
  dev.off()

  # ---- 3. Annual seasonality and level shift between years ----
  png("outputs/figures/eda_annual_level.png", width = 1200, height = 500)
  par(mfrow = c(1, 2))
  plot(daily$date, daily$cons, type = "l", col = "grey70", xlab = "", ylab = "MW",
       main = "Daily mean consumption (training)")
  lines(daily$date, daily$roll7, lwd = 2)
  hol <- daily[daily$holiday == 1, ]
  points(hol$date, hol$cons, col = "red", pch = 16, cex = 0.7)
  legend("topright", c("daily", "7-day mean", "public holiday"), col = c("grey70", "black", "red"),
         lwd = c(1, 2, NA), pch = c(NA, NA, 16), bty = "n")
  yrs <- sort(unique(daily$year))
  plot(NA, xlim = c(1, 366), ylim = range(daily$roll7, na.rm = TRUE), xlab = "day of year",
       ylab = "MW (7-day mean)", main = "Annual seasonality by year")
  for (i in seq_along(yrs)) {
    x <- daily[daily$year == yrs[i], ]
    lines(yday(x$date), x$roll7, col = i + 1, lwd = 2)
  }
  legend("topright", as.character(yrs), col = seq_along(yrs) + 1, lwd = 2, bty = "n")
  dev.off()

  # ---- 4. Relation with temperature ----
  ok <- complete.cases(daily$cons, daily$temp)
  wk <- daily$wd <= 5 & daily$holiday == 0
  png("outputs/figures/eda_temperature.png", width = 800, height = 600)
  plot(daily$temp[ok], daily$cons[ok], pch = 16, cex = 0.6,
       col = ifelse(wk[ok], "steelblue", "tomato"),
       xlab = "National mean temperature (deg C)", ylab = "Daily mean consumption (MW)",
       main = "Consumption vs temperature (training)")
  okw <- ok & wk
  lines(lowess(daily$temp[okw], daily$cons[okw]), lwd = 2)
  legend("topright", c("working day", "weekend / holiday"), col = c("steelblue", "tomato"),
         pch = 16, bty = "n")
  dev.off()

  # ---- 5. Calendar effects ----
  png("outputs/figures/eda_calendar_effects.png", width = 900, height = 550)
  boxplot(100 * dev ~ type, data = daily, xlab = "",
          ylab = "% deviation from same weekday, +-1 to 3 weeks", main = "Calendar effects (training)")
  abline(h = 0, lty = 2)
  dev.off()

  # ---- Atypical days and key numbers ----
  atyp <- daily[order(-abs(daily$dev)), ][1:15, c("date", "wd", "type", "temp", "cons", "ref", "dev")]
  atyp$temp <- round(atyp$temp, 1); atyp$cons <- round(atyp$cons); atyp$ref <- round(atyp$ref)
  atyp$dev  <- round(100 * atyp$dev, 1)
  names(atyp)[c(2, 7)] <- c("weekday_1_is_mon", "dev_pct")
  write.csv(atyp, "outputs/eda_atypical_days.csv", row.names = FALSE)
  print(atyp)

  fit <- lm(cons ~ temp, data = daily[wk & !is.na(daily$temp) & daily$temp < 15, ])
  by_year <- tapply(daily$cons, daily$year, mean, na.rm = TRUE)
  summ <- data.frame(
    quantity = c("working-day / weekend mean consumption ratio",
                 "winter (DJF) / summer (JJA) mean consumption ratio",
                 "correlation daily consumption - temperature",
                 "heating gradient below 15 deg C, working days (MW per deg C)",
                 "median deviation on public holidays (%)",
                 paste0("mean consumption ", names(by_year)[length(by_year)], " vs ",
                        names(by_year)[1], " (%, raw)")),
    value = round(c(mean(daily$cons[wk]) / mean(daily$cons[daily$wd >= 6]),
                    mean(daily$cons[daily$season == "DJF"]) / mean(daily$cons[daily$season == "JJA"]),
                    cor(daily$cons[ok], daily$temp[ok]),
                    unname(coef(fit)[2]),
                    100 * median(daily$dev[daily$holiday == 1], na.rm = TRUE),
                    100 * unname(by_year[length(by_year)] / by_year[1] - 1)), 2))
  write.csv(summ, "outputs/eda_summary.csv", row.names = FALSE)
  print(summ)

  message("Wrote outputs/figures/eda_*.png, outputs/eda_summary.csv, outputs/eda_atypical_days.csv")
}))
