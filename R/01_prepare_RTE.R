
# ============================================================
# 01_prepare_rte.R
# RTE electricity data preparation
# ============================================================

library(tidyverse)
library(lubridate)
library(readxl)
library(janitor)
library(clock)

project_dir <- getwd()

raw_dir <- file.path(project_dir, "data", "raw", "rte")
output_dir <- file.path(project_dir, "data", "processed")

years <- 2022:2025

# ------------------------------------------------------------
# 1. Read annual RTE files
# ------------------------------------------------------------

read_rte_file <- function(year) {

  files <- list.files(
    raw_dir,
    pattern = paste0(year, ".*\\.xls$"),
    full.names = TRUE,
    ignore.case = TRUE
  )

  if (length(files) != 1) {
    stop("Expected one RTE file for ", year)
  }

  file <- files[1]

  # Try genuine Excel format first
  data <- tryCatch(
    read_excel(file, sheet = 1),
    error = function(e) NULL
  )

  # Fallback for tab-separated .xls files
  if (is.null(data)) {

    data <- read_delim(
      file,
      delim = "\t",
      locale = locale(encoding = "Latin1"),
      na = c("", "NA", "N/A"),
      show_col_types = FALSE,
      trim_ws = TRUE
    )
  }

  data %>%
    clean_names()
}

rte_raw <- map_dfr(years, read_rte_file)

# ------------------------------------------------------------
# 2. Verify required columns
# ------------------------------------------------------------

required_cols <- c(
  "perimetre",
  "nature",
  "date",
  "heures",
  "consommation"
)

missing_cols <- setdiff(
  required_cols,
  names(rte_raw)
)

if (length(missing_cols) > 0) {
  stop(
    "Missing RTE columns: ",
    paste(missing_cols, collapse = ", ")
  )
}

# ------------------------------------------------------------
# 3. Filter definitive French observations
# ------------------------------------------------------------

rte_raw <- rte_raw %>%
  filter(
    str_to_lower(str_trim(perimetre)) == "france",
    str_detect(
      str_to_lower(str_trim(nature)),
      "donn[ée]es définitives|donnees definitives"
    )
  )

# ------------------------------------------------------------
# 4. Parse local timestamps
# ------------------------------------------------------------

# Expected format:
# Date  = dd/mm/yyyy
# Heures = hh:mm

date_string <- as.character(rte_raw$date)

# Handle dates that Excel may have imported as Date objects
if (inherits(rte_raw$date, "Date")) {
  date_string <- format(rte_raw$date, "%d/%m/%Y")
}

time_string <- str_trim(
  as.character(rte_raw$heures)
)

time_string <- str_replace(
  time_string,
  "^([0-9]):",
  "0\\1:"
)

wall_time <- paste(
  date_string,
  time_string
)

# Detect repeated local timestamps.
# In autumn, the same local quarter-hour occurs twice.

duplicated_time <- duplicated(wall_time)

if (any(duplicated_time) &&
    anyDuplicated(wall_time) > 0) {

  counts <- table(wall_time)

  if (any(counts > 2)) {
    stop(
      "More than two identical RTE local timestamps detected. ",
      "Check for duplicated source observations."
    )
  }
}

# First occurrence = earliest instant (summer time)
# Second occurrence = latest instant (winter time)

ambiguity <- ifelse(
  duplicated_time,
  "latest",
  "earliest"
)

rte_raw$datetime_utc <- clock::date_time_parse(
  wall_time,
  format = "%d/%m/%Y %H:%M",
  zone = "Europe/Paris",
  ambiguous = ambiguity,
  nonexistent = "NA"
)

# ------------------------------------------------------------
# 5. Remove invalid timestamps
# ------------------------------------------------------------

rte_raw <- rte_raw %>%
  filter(!is.na(datetime_utc))

# Store timestamps in UTC
rte_raw <- rte_raw %>%
  mutate(
    datetime_utc = as.POSIXct(
      datetime_utc,
      tz = "UTC"
    )
  )

# ------------------------------------------------------------
# 6. Identify numerical variables
# ------------------------------------------------------------

# All remaining RTE columns represent numerical measurements
# except the metadata and original date/time fields.

metadata_cols <- c(
  "perimetre",
  "nature",
  "date",
  "heures",
  "datetime_utc"
)

measurement_cols <- setdiff(
  names(rte_raw),
  metadata_cols
)

# Convert French numerical values
rte_raw <- rte_raw %>%
  mutate(
    across(
      all_of(measurement_cols),
      ~ parse_number(
        as.character(.x),
        locale = locale(decimal_mark = ",")
      )
    )
  )

# ------------------------------------------------------------
# 7. Aggregate 15-minute data to hourly data
# ------------------------------------------------------------

# Power is measured in MW.
# The hourly value is the mean of the four quarter-hourly
# power observations, not their sum.

rte_hourly <- rte_raw %>%
  mutate(
    datetime_utc = floor_date(
      datetime_utc,
      unit = "hour"
    )
  ) %>%
  group_by(datetime_utc) %>%
  summarise(
    across(
      all_of(measurement_cols),
      ~ if (all(is.na(.x))) {
        NA_real_
      } else {
        mean(.x, na.rm = TRUE)
      }
    ),

    n_quarters = n(),

    .groups = "drop"
  ) %>%
  arrange(datetime_utc)

# ------------------------------------------------------------
# 8. Add local timestamp for interpretation
# ------------------------------------------------------------

rte_hourly <- rte_hourly %>%
  mutate(
    datetime_local = format(
      with_tz(
        datetime_utc,
        "Europe/Paris"
      ),
      "%Y-%m-%dT%H:%M:%S%z",
      tz = "Europe/Paris"
    )
  ) %>%
  relocate(
    datetime_utc,
    datetime_local,
    n_quarters
  )

# ------------------------------------------------------------
# 9. Diagnostics
# ------------------------------------------------------------

cat("\nRTE preparation summary\n")

print(dim(rte_hourly))

cat("\nNumber of quarter-hour observations per hour:\n")

print(table(rte_hourly$n_quarters))

cat("\nIncomplete hourly observations:\n")

print(
  rte_hourly %>%
    filter(n_quarters != 4) %>%
    select(datetime_utc, n_quarters)
)

# ------------------------------------------------------------
# 10. Export
# ------------------------------------------------------------

rte_export <- rte_hourly %>%
  mutate(
    datetime_utc = format(
      datetime_utc,
      "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    )
  )

write_csv(
  rte_export,
  file.path(output_dir, "rte_hourly.csv")
)

message("RTE preparation completed.")
