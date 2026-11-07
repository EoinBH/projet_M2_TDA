
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
  "clock"
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

scripts <- c(
  "01_prepare_rte.R",
  "02_prepare_weather.R",
  "03_prepare_calendar.R",
  "04_merge_datasets.R"
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
message("DATA PREPARATION SUCCESSFULLY COMPLETED")
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
