# Day-ahead forecasting of French electricity consumption

Forecast of the hourly electricity consumption of metropolitan France for all 24 hours of day **J+1**, issued at **14:00 on day J**. Course project (Temporal Data Analysis, M2).

**Status:** data preparation, benchmarks and per-hour ARIMA (validation period) are done. Ablation study, perfect-weather benchmark, a more elaborate model, final test evaluation and failure analysis are still to do.

## 1. Forecast protocol

- **Origin / horizon:** 14:00 local time on day J; the 24 hours of J+1.
- **Information at 14:00 on J:** consumption of all days before J plus hours 0-13 of day J (hours 14-23 of J are not yet observed). Calendar variables are known in advance. Observed weather of J+1 is **never** used in the operational scenario.
- **Chronological split (by target date):** train 2022-2023, validation 2024, test 2025. The test period must be used only once, for the final evaluation.
- **Metrics:** MAE, RMSE, error on daily total, error on peak value, error on peak hour.

## 2. Data

| Source | Content |
|---|---|
| RTE eCO2mix (definitive annual files 2022-2025) | consumption, production, exchanges, CO2 intensity (15 min, aggregated to hourly means) |
| Météo-France SYNOP | observed weather, aggregated nationally (3-hourly + hourly interpolation) |
| Calendar | public holidays (JSON), school holidays zones A/B/C (ICS), temporal features |

Raw files go in `data/raw/` and are never modified; the exact file names expected are given at the top of scripts `01`-`03`. All timestamps are merged in UTC; local (Europe/Paris) timestamps are kept to handle daylight-saving changes.

## 3. Project structure

```
data/raw/            raw inputs (unchanged)
data/processed/      cleaned datasets, modelling_dataset.csv, diagnostics/
R/                   all scripts (see below)
outputs/             benchmark and model results
```

| Script | Role |
|---|---|
| `00_run_pipeline.R` | master script: installs packages, runs everything |
| `01_prepare_RTE.R` | import and hourly aggregation of RTE data |
| `02_prepare_weather.R` | import, filtering, aggregation and interpolation of SYNOP data |
| `03_prepare_calendar.R` | holidays, school holidays, calendar features |
| `04_merge_datasets.R` | UTC merge, local timestamps, diagnostics -> `modelling_dataset.csv` |
| `05_protocol.R` | configuration, hourly matrix (days x 24 hours), availability rule, splits, metrics (sourced by 06/07) |
| `06_benchmarks.R` | three simple benchmarks respecting the 14:00 constraint |
| `07_arima.R` | one seasonal ARIMA with calendar regressors per hour of the day |

## 4. How to run

1. Open R with the **project root as working directory**.
2. Run:
   ```r
   source("R/00_run_pipeline.R")
   ```
   Packages are installed automatically if missing (tidyverse, lubridate, readxl, janitor, jsonlite, stringi, zoo, clock, forecast, tseries).
3. Stages can be skipped with the flags `RUN_DATA` / `RUN_MODELS` at the top of the execution section of `00_run_pipeline.R` (for example `RUN_DATA <- FALSE` to reuse `data/processed/`).

**Run time:** data preparation is quick; `07_arima.R` is the expensive step (about 45 minutes on the author's machine for the validation year, together with `06`).

## 5. Models

- **Benchmarks (06):** B1 previous day (day J for hours 0-13, day J-1 for hours 14-23, because the rest of day J is unknown at 14:00); B2 same weekday last week; B3 mean of the same weekday over the last 4 weeks.
- **ARIMA (07):** for each hour h, a regression with seasonal ARIMA errors on the daily series of hour h (weekly period 7). Regressors: public holiday, holiday eve, school-holiday zones A/B/C, 2 annual Fourier pairs. Orders chosen on the training period only; coefficients re-estimated every 28 days on an expanding window; between re-estimations the model is only updated with new observations. Hours 0-13 are 1-step-ahead forecasts, hours 14-23 are 2-step-ahead forecasts.

## 6. Outputs

| File | Content |
|---|---|
| `outputs/benchmarks_validation.csv` | benchmark scores on validation |
| `outputs/scores_val.csv` | ARIMA vs benchmarks, same dates |
| `outputs/arima_orders.csv` | selected ARIMA order per hour |
| `outputs/benchmarks.rds`, `outputs/arima_val.rds` | forecasts and observations (R binary format; read with `readRDS()`) |

Validation results (2024, MW):

| Model | MAE | RMSE | MAE daily total | MAE peak value | MAE peak hour (h) |
|---|---|---|---|---|---|
| ARIMA per hour | 1643.5 | 2420.8 | 32528.9 | 1568.4 | 2.4 |
| B1 previous day (strict) | 3183.0 | 4362.1 | 72276.1 | 3278.6 | 2.4 |
| B2 same weekday last week | 3229.4 | 4845.7 | 74799.7 | 3394.5 | 2.1 |
| B3 mean of 4 weeks | 3706.5 | 5354.4 | 86534.6 | 3804.8 | 1.9 |

## 7. Known limitations

- Observed weather is not used; an operational weather model would need archived forecasts available at 14:00.
- Missing consumption values (4 hours) are filled by last observation carried forward; the repeated autumn hour is averaged.
- Variables with high missingness in SYNOP (`tn12`, `tx12`, `sw`, station count) are not used by the models.
- 2022 is atypical (energy crisis, reduced nuclear availability) and is part of the training data.
