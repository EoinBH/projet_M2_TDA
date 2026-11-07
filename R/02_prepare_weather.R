
# ============================================================
# 02_prepare_weather.R
# SYNOP weather data preparation
# ============================================================

library(tidyverse)
library(lubridate)
library(janitor)
library(zoo)

project_dir <- getwd()

raw_dir <- file.path(project_dir, "data", "raw", "meteo")
output_dir <- file.path(project_dir, "data", "processed")

years <- 2022:2025

# ------------------------------------------------------------
# 1. Read annual SYNOP files
# ------------------------------------------------------------

read_synop <- function(year) {

  file <- file.path(
    raw_dir,
    paste0("synop_", year, ".csv")
  )

  if (!file.exists(file)) {
    stop("Missing SYNOP file: ", file)
  }

  read_delim(
    file,
    delim = ";",
    locale = locale(encoding = "UTF-8"),
    na = c("", "NA", "mq"),
    show_col_types = FALSE,
    trim_ws = TRUE
  ) %>%
    clean_names()
}

synop_raw <- map_dfr(years, read_synop)

# ------------------------------------------------------------
# 2. Parse SYNOP timestamps
# ------------------------------------------------------------

if (!"validity_time" %in% names(synop_raw)) {
  stop("Missing validity_time column.")
}

synop_raw <- synop_raw %>%
  mutate(
    datetime_utc = ymd_hms(
      as.character(validity_time),
      tz = "UTC",
      quiet = TRUE
    )
  )

if (all(is.na(synop_raw$datetime_utc))) {
  stop("Could not parse SYNOP validity_time.")
}

# ------------------------------------------------------------
# 3. Filter metropolitan stations
# ------------------------------------------------------------

synop_raw <- synop_raw %>%
  mutate(
    lat = as.numeric(lat),
    lon = as.numeric(lon)
  ) %>%
  filter(
    between(lat, 41, 51.5),
    between(lon, -5.5, 10),
    !is.na(datetime_utc)
  )

# ------------------------------------------------------------
# 4. Select meteorological variables
# ------------------------------------------------------------

weather_variables <- c(
  "t", "td", "u",
  "ff", "dd", "vv",
  "pres", "pmer",
  "rr1", "rr3", "rr6",
  "rr12", "rr24",
  "sw", "raf10", "rafper",
  "tn12", "tx12", "tn24", "tx24"
)

weather_variables <- intersect(
  weather_variables,
  names(synop_raw)
)

# ------------------------------------------------------------
# 5. Convert values to numerical measurements
# ------------------------------------------------------------

synop_raw <- synop_raw %>%
  mutate(
    across(
      all_of(weather_variables),
      ~ suppressWarnings(
        as.numeric(as.character(.x))
      )
    )
  )

# IMPORTANT:
# Do not assume that every negative value is missing.
# The official SYNOP technical documentation must be used
# to identify sentinel values for each individual variable.

# ------------------------------------------------------------
# 6. Circular mean for wind direction
# ------------------------------------------------------------

circular_mean <- function(x) {

  x <- x[!is.na(x)]

  if (length(x) == 0) {
    return(NA_real_)
  }

  radians <- x * pi / 180

  sin_mean <- mean(sin(radians))
  cos_mean <- mean(cos(radians))

  if (sqrt(sin_mean^2 + cos_mean^2) < 1e-8) {
    return(NA_real_)
  }

  result <- atan2(sin_mean, cos_mean) * 180 / pi

  result %% 360
}

# ------------------------------------------------------------
# 7. Aggregate station observations nationally
# ------------------------------------------------------------

ordinary_variables <- setdiff(
  weather_variables,
  "dd"
)

weather_3hourly <- synop_raw %>%
  group_by(datetime_utc) %>%
  summarise(

    across(
      all_of(ordinary_variables),
      ~ if (all(is.na(.x))) {
        NA_real_
      } else {
        mean(.x, na.rm = TRUE)
      }
    ),

    dd = if ("dd" %in% names(synop_raw)) {
      circular_mean(dd)
    } else {
      NULL
    },

    n_stations = n_distinct(geo_id_wmo),

    .groups = "drop"
  ) %>%
  arrange(datetime_utc)

# ------------------------------------------------------------
# 8. Export original three-hourly observations
# ------------------------------------------------------------

weather_3hourly_export <- weather_3hourly %>%
  mutate(
    datetime_utc = format(
      datetime_utc,
      "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    )
  )

write_csv(
  weather_3hourly_export,
  file.path(output_dir, "weather_3hourly.csv")
)

# ------------------------------------------------------------
# 9. Construct continuous hourly UTC timeline
# ------------------------------------------------------------

hourly_grid <- tibble(
  datetime_utc = seq.POSIXt(
    from = min(weather_3hourly$datetime_utc),
    to = max(weather_3hourly$datetime_utc),
    by = "hour"
  )
)

weather_hourly <- hourly_grid %>%
  left_join(
    weather_3hourly,
    by = "datetime_utc"
  ) %>%
  arrange(datetime_utc)

# ------------------------------------------------------------
# 10. Interpolate numerical variables
# ------------------------------------------------------------

# Interpolate only gaps of at most two hours.
# No extrapolation beyond the first/last actual observation.

interpolated_variables <- setdiff(
  weather_variables,
  "dd"
)

for (variable in interpolated_variables) {

  weather_hourly[[variable]] <- zoo::na.approx(
    weather_hourly[[variable]],
    x = as.numeric(weather_hourly$datetime_utc),
    na.rm = FALSE,
    maxgap = 2
  )
}

# ------------------------------------------------------------
# 11. Interpolate wind direction circularly
# ------------------------------------------------------------

if ("dd" %in% weather_variables) {

  direction <- weather_hourly$dd

  radians <- direction * pi / 180

  sin_values <- sin(radians)
  cos_values <- cos(radians)

  sin_interpolated <- zoo::na.approx(
    sin_values,
    x = as.numeric(weather_hourly$datetime_utc),
    na.rm = FALSE,
    maxgap = 2
  )

  cos_interpolated <- zoo::na.approx(
    cos_values,
    x = as.numeric(weather_hourly$datetime_utc),
    na.rm = FALSE,
    maxgap = 2
  )

  weather_hourly$dd <- (
    atan2(
      sin_interpolated,
      cos_interpolated
    ) * 180 / pi
  ) %% 360
}

# ------------------------------------------------------------
# 12. Identify actual and interpolated observations
# ------------------------------------------------------------

observed_timestamps <- weather_3hourly$datetime_utc

weather_hourly <- weather_hourly %>%
  mutate(
    is_interpolated = !datetime_utc %in%
      observed_timestamps
  )

# ------------------------------------------------------------
# 13. Export hourly weather dataset
# ------------------------------------------------------------

weather_hourly_export <- weather_hourly %>%
  mutate(
    datetime_utc = format(
      datetime_utc,
      "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    )
  )

write_csv(
  weather_hourly_export,
  file.path(output_dir, "weather_hourly.csv")
)

# ------------------------------------------------------------
# 14. Diagnostics
# ------------------------------------------------------------

cat("\nWeather preparation summary\n")

print(dim(weather_3hourly))
print(dim(weather_hourly))

cat("\nStations per observation:\n")
print(summary(weather_3hourly$n_stations))

cat("\nInterpolated observations:\n")
print(table(weather_hourly$is_interpolated))

message("Weather preparation completed.")
