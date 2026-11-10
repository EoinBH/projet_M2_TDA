
# ============================================================
# 00_run_pipeline.R
# Master script: install packages and execute the pipeline
# ============================================================

# IMPORTANT:
# Run this script with the project root as working directory.

project_dir <- normalizePath(
  getwd(),
  winslash = "/",
  mustWork = TRUE
)

if (!dir.exists(file.path(project_dir, "R")) ||
    !dir.exists(file.path(project_dir, "data", "raw"))) {
  stop(
    "Please set the working directory to the temporal_project folder."
  )
}

# ------------------------------------------------------------
# 1. Install required packages
# ------------------------------------------------------------

packages <- c(
  "tidyverse",
  "lubridate",
  "readxl",
  "janitor",
  "jsonlite",
  "stringi",
  "zoo",
  "clock",
  "forecast",
  "tseries"
)

missing_packages <- packages[
  !packages %in% installed.packages()[, "Package"]
]

if (length(missing_packages) > 0) {

  install.packages(
    missing_packages,
    repos = "https://cloud.r-project.org"
  )
}

# ------------------------------------------------------------
# 2. Load packages
# ------------------------------------------------------------

invisible(
  lapply(packages, library, character.only = TRUE)
)

# ------------------------------------------------------------
# 3. Create output directories
# ------------------------------------------------------------

dir.create(
  file.path(project_dir, "data", "processed"),
  recursive = TRUE,
  showWarnings = FALSE
)

dir.create(
  file.path(project_dir, "data", "processed", "diagnostics"),
  recursive = TRUE,
  showWarnings = FALSE
)

# ------------------------------------------------------------
# 4. Execute scripts in order
# ------------------------------------------------------------

# Set a flag to FALSE to skip a stage (e.g. RUN_DATA <- FALSE reuses data/processed/).
RUN_DATA   <- FALSE   # steps 01-04: data cleaning and merging
RUN_EDA        <- TRUE   # step 05: exploratory analysis (training period only, figures)
RUN_BENCHMARKS <- TRUE   # step 06: simple benchmarks
RUN_ARIMA      <- TRUE   # step 07: per-hour ARIMA versions v1, v2 (slow, ~45 min each; versions with existing results are skipped, see FORCE_RERUN in 07)
RUN_ABLATION   <- TRUE   # step 08: ablation study + perfect-weather benchmark
RUN_ANALYSIS   <- TRUE   # step 09: errors by segment/hour, failure days (needs outputs of 06-08)
RUN_DIAGNOSTICS <- TRUE  # step 10: stationarity, ACF/PACF, residual and forecast-error checks (needs 07 and 08)

data_scripts <- c(
  "01_prepare_RTE.R",
  "02_prepare_weather.R",
  "03_prepare_calendar.R",
  "04_merge_datasets.R"
)

scripts <- c(
  if (RUN_DATA) data_scripts,
  if (RUN_EDA) "05_eda.R",
  if (RUN_BENCHMARKS) "06_benchmarks.R",
  if (RUN_ARIMA) "07_arima.R",
  if (RUN_ABLATION) "08_ablation.R",
  if (RUN_ANALYSIS) "09_error_analysis.R",
  if (RUN_DIAGNOSTICS) "10_diagnostics.R"
)

for (script in scripts) {

  script_path <- file.path(
    project_dir,
    "R",
    script
  )

  if (!file.exists(script_path)) {
    stop("Script not found: ", script_path)
  }

  message("\n========================================")
  message("Running: ", script)
  message("========================================\n")

  source(
    script_path,
    local = FALSE,
    echo = FALSE
  )

  message("\nCompleted: ", script)
}

# ------------------------------------------------------------
# 5. Final message
# ------------------------------------------------------------

message("\n========================================")
message("PIPELINE SUCCESSFULLY COMPLETED")
message("========================================")

message(
  "Final dataset: ",
  file.path(
    project_dir,
    "data",
    "processed",
    "modelling_dataset.csv"
  )
)
