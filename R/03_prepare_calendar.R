
# ============================================================
# 03_prepare_calendar.R
# French public and school holiday preparation
# ============================================================

library(tidyverse)
library(lubridate)
library(jsonlite)
library(stringr)

project_dir <- getwd()

raw_dir <- file.path(project_dir, "data", "raw", "calendar")
output_dir <- file.path(project_dir, "data", "processed")

# ------------------------------------------------------------
# 1. Create daily calendar
# ------------------------------------------------------------

calendar_daily <- tibble(
  date = seq.Date(
    as.Date("2022-01-01"),
    as.Date("2025-12-31"),
    by = "day"
  )
) %>%
  mutate(
    year = year(date),
    month = month(date),
    day_of_month = day(date),
    day_of_week = wday(date, week_start = 1),

    day_name = wday(
      date,
      label = TRUE,
      abbr = FALSE,
      week_start = 1
    ),

    month_name = month(
      date,
      label = TRUE,
      abbr = FALSE
    ),

    is_weekend = day_of_week %in% c(6, 7),

    season = case_when(
      month %in% c(12, 1, 2) ~ "Winter",
      month %in% c(3, 4, 5) ~ "Spring",
      month %in% c(6, 7, 8) ~ "Summer",
      TRUE ~ "Autumn"
    )
  )

# ------------------------------------------------------------
# 2. Read public holidays JSON
# ------------------------------------------------------------

holiday_file <- file.path(
  raw_dir,
  "public_holidays.json"
)

if (!file.exists(holiday_file)) {
  stop("Missing public_holidays.json")
}

holiday_json <- fromJSON(
  holiday_file,
  simplifyVector = TRUE
)

if (is.null(names(holiday_json))) {
  stop("Unexpected public holiday JSON format.")
}

public_holidays <- tibble(
  date = names(holiday_json),
  public_holiday_name = as.character(holiday_json)
) %>%
  mutate(
    date = as.Date(date)
  ) %>%
  filter(
    !is.na(date),
    year(date) %in% 2022:2025
  ) %>%
  distinct(date, .keep_all = TRUE)

calendar_daily <- calendar_daily %>%
  left_join(
    public_holidays,
    by = "date"
  ) %>%
  mutate(
    is_public_holiday = !is.na(public_holiday_name)
  )

# ------------------------------------------------------------
# 3. Read school holiday ICS file
# ------------------------------------------------------------

ics_file <- file.path(
  raw_dir,
  "Zone-A-B-C-Corse.ics"
)

if (!file.exists(ics_file)) {
  stop("Missing school holiday ICS file.")
}

ics_lines <- readLines(
  ics_file,
  encoding = "UTF-8",
  warn = FALSE
)

# ------------------------------------------------------------
# 4. Unfold ICS continuation lines
# ------------------------------------------------------------

unfold_ics <- function(lines) {

  output <- character()

  for (line in lines) {

    if (grepl("^[ \t]", line) && length(output) > 0) {

      output[length(output)] <- paste0(
        output[length(output)],
        substring(line, 2)
      )

    } else {

      output <- c(output, line)
    }
  }

  output
}

ics_lines <- unfold_ics(ics_lines)

# ------------------------------------------------------------
# 5. Extract ICS events
# ------------------------------------------------------------

start_indices <- which(
  ics_lines == "BEGIN:VEVENT"
)

end_indices <- which(
  ics_lines == "END:VEVENT"
)

if (length(start_indices) != length(end_indices)) {
  stop("Invalid ICS file: unmatched event boundaries.")
}

events <- map2(
  start_indices,
  end_indices,
  ~ ics_lines[.x:.y]
)

# ------------------------------------------------------------
# 6. Extract ICS properties
# ------------------------------------------------------------

get_property <- function(event, property) {

  pattern <- paste0(
    "^",
    property,
    "(?:;[^:]*)?:"
  )

  matching <- grep(
    pattern,
    event,
    value = TRUE,
    ignore.case = TRUE
  )

  if (length(matching) == 0) {
    return(NA_character_)
  }

  sub(
    "^[^:]*:",
    "",
    matching[1]
  )
}

# ------------------------------------------------------------
# 7. Parse ICS dates
# ------------------------------------------------------------

parse_ics_date <- function(x) {

  if (is.na(x)) {
    return(as.Date(NA))
  }

  # Use the date component of the ICS timestamp.
  date_part <- substr(x, 1, 8)

  as.Date(
    date_part,
    format = "%Y%m%d"
  )
}

# ------------------------------------------------------------
# 8. Expand school holiday periods
# ------------------------------------------------------------

school_events <- map_dfr(events, function(event) {

  start_raw <- get_property(event, "DTSTART")
  end_raw <- get_property(event, "DTEND")

  summary <- get_property(event, "SUMMARY")
  description <- get_property(event, "DESCRIPTION")

  if (any(is.na(c(start_raw, end_raw)))) {
    return(tibble())
  }

  start_date <- parse_ics_date(start_raw)
  end_date <- parse_ics_date(end_raw)

  if (is.na(start_date) || is.na(end_date)) {
    return(tibble())
  }

  event_text <- paste(
    summary,
    description
  )

  event_text <- str_replace_all(
    event_text,
    "\\\\[,;]",
    " "
  )

  # Zones concerned by the event. The ICS labels are e.g.
  # "Vacances de Noel - Zones A/B/C - Corse", "... - Zones A/C", "... - Zone B".
  # (The previous version only matched "Zone A" / "Zone B" / "Zone C" and
  # silently dropped every multi-zone event, e.g. all Christmas breaks.)
  # Events naming no zone (Corsica-only events) are ignored on purpose.
  zone_text <- str_match(
    str_to_lower(event_text),
    "zones?\\s*([abc](?:\\s*[/,&]\\s*[abc])*)"
  )[, 2]

  zones <- if (is.na(zone_text)) {
    character()
  } else {
    toupper(unique(str_extract_all(zone_text, "[abc]")[[1]]))
  }

  if (length(zones) == 0) {
    return(tibble())
  }

  # DTEND is exclusive for all-day ICS events.
  # For date-time events, use the calendar date of DTEND.

  end_inclusive <- if (
    grepl("^DTEND(;[^:]*)?:\\d{8}$", event[grepl("^DTEND", event)])
  ) {
    end_date - days(1)
  } else {
    end_date
  }

  if (end_inclusive < start_date) {
    return(tibble())
  }

  expand_grid(
    date = seq.Date(
      start_date,
      end_inclusive,
      by = "day"
    ),
    zone = zones
  )
})

if (nrow(school_events) == 0) {
  stop(
    "No school holidays detected. ",
    "Inspect the SUMMARY and DESCRIPTION fields in the ICS file."
  )
}

school_events <- school_events %>%
  filter(year(date) %in% 2022:2025) %>%
  distinct(date, zone) %>%
  mutate(value = TRUE)

# ------------------------------------------------------------
# 9. Create school holiday indicators
# ------------------------------------------------------------

school_wide <- school_events %>%
  pivot_wider(
    names_from = zone,
    values_from = value,
    names_prefix = "school_holiday_",
    values_fill = FALSE
  )

calendar_daily <- calendar_daily %>%
  left_join(
    school_wide,
    by = "date"
  )

for (zone in c("A", "B", "C")) {

  variable <- paste0(
    "school_holiday_",
    zone
  )

  if (!variable %in% names(calendar_daily)) {
    calendar_daily[[variable]] <- FALSE
  }

  calendar_daily[[variable]] <- replace_na(
    calendar_daily[[variable]],
    FALSE
  )
}

# ------------------------------------------------------------
# 10. Additional calendar variables
# ------------------------------------------------------------

calendar_daily <- calendar_daily %>%
  arrange(date) %>%
  mutate(
    is_school_holiday_national =
      school_holiday_A &
      school_holiday_B &
      school_holiday_C,

    is_holiday_eve = lead(
      is_public_holiday,
      default = FALSE
    )
  )

# ------------------------------------------------------------
# 11. Create DST-aware UTC hourly calendar
# ------------------------------------------------------------

# France is UTC+1 at the start of January 2022.
# The timeline ends immediately before 2026 local midnight.

utc_start <- as.POSIXct(
  "2021-12-31 23:00:00",
  tz = "UTC"
)

utc_end <- as.POSIXct(
  "2025-12-31 22:00:00",
  tz = "UTC"
)

calendar_hourly <- tibble(
  datetime_utc = seq.POSIXt(
    utc_start,
    utc_end,
    by = "hour"
  )
) %>%
  mutate(
    datetime_local_posix = with_tz(
      datetime_utc,
      "Europe/Paris"
    ),

    date = as.Date(
      datetime_local_posix,
      tz = "Europe/Paris"
    ),

    hour = hour(datetime_local_posix),

    datetime_local = format(
      datetime_local_posix,
      "%Y-%m-%dT%H:%M:%S%z",
      tz = "Europe/Paris"
    )
  ) %>%
  left_join(
    calendar_daily,
    by = "date"
  ) %>%
  select(
    -datetime_local_posix
  ) %>%
  arrange(datetime_utc)

# ------------------------------------------------------------
# 12. Validate calendar
# ------------------------------------------------------------

expected_hours <- 35064

if (nrow(calendar_hourly) != expected_hours) {
  stop("Unexpected number of calendar timestamps.")
}

if (anyDuplicated(calendar_hourly$datetime_utc)) {
  stop("Duplicate calendar UTC timestamps.")
}

# ------------------------------------------------------------
# 13. Export
# ------------------------------------------------------------

calendar_export <- calendar_hourly %>%
  mutate(
    datetime_utc = format(
      datetime_utc,
      "%Y-%m-%dT%H:%M:%SZ",
      tz = "UTC"
    )
  )

write_csv(
  calendar_export,
  file.path(output_dir, "calendar_hourly.csv")
)

cat("\nCalendar summary\n")

print(dim(calendar_hourly))

print(
  calendar_daily %>%
    summarise(
      public_holidays = sum(is_public_holiday),
      weekends = sum(is_weekend),
      zone_A = sum(school_holiday_A),
      zone_B = sum(school_holiday_B),
      zone_C = sum(school_holiday_C)
    )
)

# Sanity check of school-holiday coverage: days flagged per year and zone,
# and Christmas Eve must be a national school holiday in every year.
print(
  calendar_daily %>%
    group_by(year) %>%
    summarise(
      zone_A = sum(school_holiday_A),
      zone_B = sum(school_holiday_B),
      zone_C = sum(school_holiday_C)
    )
)

xmas_eve <- calendar_daily %>%
  filter(month == 12, day_of_month == 24)

if (any(!xmas_eve$is_school_holiday_national)) {
  warning("Christmas Eve is not flagged as a national school holiday in some years.")
}

message("Calendar preparation completed.")
