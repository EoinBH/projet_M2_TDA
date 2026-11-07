
# ============================================================
# 04_merge_datasets.R
# Merge RTE, weather and calendar data
# ============================================================

library(tidyverse)
library(lubridate)

project_dir <- getwd()

input_dir <- file.path(
  project_dir,
  "data",
  "processed"
)

output_dir <- input_dir

diagnostics_dir <- file.path(
  output_dir,
  "diagnostics"
)

# ------------------------------------------------------------
# 1. Load datasets
# ------------------------------------------------------------

rte <- read_csv(
  file.path(input_dir, "rte_hourly.csv"),
  show_col_types = FALSE
)

weather <- read_csv(
  file.path(input_dir, "weather_hourly.csv"),
  show_col_types = FALSE
)

calendar <- read_csv(
  file.path(input_dir, "calendar_hourly.csv"),
  show_col_types = FALSE
)

# ------------------------------------------------------------
# 2. Remove existing local timestamp columns
# ------------------------------------------------------------

rte <- rte %>%
  select(-datetime_local)

calendar <- calendar %>%
  select(-datetime_local)

# ------------------------------------------------------------
# 3. Standardise UTC timestamps
# ------------------------------------------------------------

parse_utc <- function(data) {

  data %>%
    mutate(
      datetime_utc = ymd_hms(
        datetime_utc,
        tz = "UTC",
        quiet = TRUE
      )
    )
}

rte <- parse_utc(rte)
weather <- parse_utc(weather)
calendar <- parse_utc(calendar)

# ------------------------------------------------------------
# 4. Validate timestamps
# ------------------------------------------------------------

datasets <- list(
  RTE = rte,
  Weather = weather,
  Calendar = calendar
)

for (name in names(datasets)) {

  data <- datasets[[name]]

  if (anyNA(data$datetime_utc)) {
    stop(name, " contains invalid UTC timestamps.")
  }

  if (anyDuplicated(data$datetime_utc)) {
    stop(name, " contains duplicate UTC timestamps.")
  }
}

# ------------------------------------------------------------
# 5. Check coverage
# ------------------------------------------------------------

cat("\nTimestamp ranges\n")

for (name in names(datasets)) {

  data <- datasets[[name]]

  cat(
    name,
    ":",
    format(
      min(data$datetime_utc),
      "%Y-%m-%d %H:%M UTC",
      tz = "UTC"
    ),
    "to",
    format(
      max(data$datetime_utc),
      "%Y-%m-%d %H:%M UTC",
      tz = "UTC"
    ),
    "\n"
  )
}

# ------------------------------------------------------------
# 6. Merge datasets using UTC
# ------------------------------------------------------------

modelling_dataset <- rte %>%
  full_join(
    weather,
    by = "datetime_utc"
  ) %>%
  full_join(
    calendar,
    by = "datetime_utc"
  ) %>%
  arrange(datetime_utc)

# ------------------------------------------------------------
# 7. Create local timestamp and temporal features
# ------------------------------------------------------------

modelling_dataset <- modelling_dataset %>%
  mutate(
    datetime_local_posix = with_tz(
      datetime_utc,
      "Europe/Paris"
    ),

    datetime_local = format(
      datetime_local_posix,
      "%Y-%m-%dT%H:%M:%S%z",
      tz = "Europe/Paris"
    ),

    year = year(datetime_local_posix),
    month = month(datetime_local_posix),
    day = day(datetime_local_posix),
    hour = hour(datetime_local_posix),

    day_of_week = wday(
      datetime_local_posix,
      week_start = 1
    ),

    # Cyclical hour encoding
    hour_sin = sin(2 * pi * hour / 24),
    hour_cos = cos(2 * pi * hour / 24),

    # Cyclical weekday encoding
    day_sin = sin(2 * pi * day_of_week / 7),
    day_cos = cos(2 * pi * day_of_week / 7),

    # Cyclical month encoding
    month_sin = sin(2 * pi * month / 12),
    month_cos = cos(2 * pi * month / 12)
  ) %>%
  select(
    -datetime_local_posix
  ) %>%
  relocate(
    datetime_utc,
    datetime_local,
    year,
    month,
    day,
    hour,
    day_of_week
  )

# ------------------------------------------------------------
# 8. Missing value diagnostics
# ------------------------------------------------------------

missing_summary <- modelling_dataset %>%
  summarise(
    across(
      everything(),
      ~ sum(is.na(.x))
    )
  ) %>%
  pivot_longer(
    everything(),
    names_to = "variable",
    values_to = "missing_count"
  ) %>%
  mutate(
    missing_percentage =
      100 * missing_count / nrow(modelling_dataset)
  ) %>%
  arrange(desc(missing_percentage))

write_csv(
  missing_summary,
  file.path(
    diagnostics_dir,
    "missing_values_summary.csv"
  )
)

# ------------------------------------------------------------
# 9. Dataset coverage diagnostics
# ------------------------------------------------------------

coverage_summary <- tibble(
  total_rows = nrow(modelling_dataset),

  unique_timestamps = n_distinct(
    modelling_dataset$datetime_utc
  ),

  first_timestamp = format(
    min(modelling_dataset$datetime_utc),
    "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  ),

  last_timestamp = format(
    max(modelling_dataset$datetime_utc),
    "%Y-%m-%dT%H:%M:%SZ",
    tz = "UTC"
  ),

  missing_consumption = sum(
    is.na(modelling_dataset$consommation)
  ),

  missing_temperature = if ("t" %in% names(modelling_dataset)) {
    sum(is.na(modelling_dataset$t))
  } else {
    NA_integer_
  },

  missing_calendar = sum(
    is.na(modelling_dataset$is_weekend)
  )
)

print(coverage_summary)

write_csv(
  coverage_summary,
  file.path(
    diagnostics_dir,
    "coverage_summary.csv"
  )
)

# ------------------------------------------------------------
# 10. Check hourly continuity
# ------------------------------------------------------------

expected_timestamps <- seq.POSIXt(
  from = min(modelling_dataset$datetime_utc),
  to = max(modelling_dataset$datetime_utc),
  by = "hour"
)

missing_timestamps <- tibble(
  datetime_utc = expected_timestamps
) %>%
  anti_join(
    modelling_dataset %>%
      select(datetime_utc),
    by = "datetime_utc"
  )

write_csv(
  missing_timestamps %>%
    mutate(
      datetime_utc = format(
        datetime_utc,
        "%Y-%m-%dT%H:%M:%SZ",
        tz = "UTC"
      )
    ),
  file.path(
    diagnostics_dir,
    "missing_timestamps.csv"
  )
)

cat(
  "\nMissing hourly timestamps:",
  nrow(missing_timestamps),
  "\n"
)

# ------------------------------------------------------------
# 11. Check RTE completeness
# ------------------------------------------------------------

if ("n_quarters" %in% names(modelling_dataset)) {

  cat("\nRTE quarter-hour completeness:\n")

  print(
    table(
      modelling_dataset$n_quarters,
      useNA = "ifany"
    )
  )
}

# ------------------------------------------------------------
# 12. Export final dataset
# ------------------------------------------------------------

final_export <- modelling_dataset %>%
  mutate(
    datetime_utc = format(
      datetime_utc,
      "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    )
  )

write_csv(
  final_export,
  file.path(
    output_dir,
    "modelling_dataset.csv"
  )
)

message("\nFinal dataset exported successfully.")

cat(
  "\nDimensions:",
  nrow(final_export),
  "rows x",
  ncol(final_export),
  "columns\n"
)
