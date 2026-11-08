# Day-ahead forecasting of French electricity consumption

Forecast of the hourly electricity consumption of metropolitan France for all 24 hours of day **J+1**, issued at **14:00 on day J**. Course project (Temporal Data Analysis, M2).

**Status:** data preparation, benchmarks, per-hour ARIMA, ablation, error analysis and diagnostics scripts are written. Validation results are being regenerated after a school-holiday calendar fix (see section 8). Final test evaluation, failure-day write-up and report are still to do.

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
| `08_ablation.R` | fast per-hour linear models: simple operational model, ablation of calendar / lags / weather, perfect-weather bound |
| `09_error_analysis.R` | errors by season / day type / temperature / hour, largest-error days with context and plots (reads outputs of 06-08, no refitting) |
| `10_diagnostics.R` | ADF/KPSS tests and ACF/PACF of the daily series (train), ARIMA residual diagnostics (Ljung-Box, normality, variance by season), autocorrelation of out-of-sample forecast errors; run after 07 and 08 |

## 4. How to run

1. Open R with the **project root as working directory**.
2. Run:
   ```r
   source("R/00_run_pipeline.R")
   ```
   Packages are installed automatically if missing (tidyverse, lubridate, readxl, janitor, jsonlite, stringi, zoo, clock, forecast, tseries).
3. Stages can be switched on/off with the flags `RUN_DATA`, `RUN_BENCHMARKS`, `RUN_ARIMA`, `RUN_ABLATION`, `RUN_ANALYSIS` in `00_run_pipeline.R` (for example set all but `RUN_ANALYSIS` to `FALSE` to re-run only script 09 on existing outputs).

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

## 8. Project status, results and next steps (as of 8 Nov 2026)

> **Update, 8 Nov 2026 (evening) - read this first.**
> - **Calendar bug fixed.** `03_prepare_calendar.R` silently dropped every school-holiday event labelled with several zones ("Zones A/B/C", "Zones A/C", ...): 60 of 76 events, including all Christmas, Toussaint and summer breaks. The zone parser now handles these labels. Corsica-only events are ignored on purpose; "Pont de l'Ascension" and teacher pre-return events are now flagged. After the fix: 121-128 flagged days per zone and year, and Christmas Eve is flagged in every year.
> - **Everything produced before this fix used wrong `school_holiday_*` flags.** All validation numbers and failure-day lists below are pre-fix and must be regenerated. Re-run order: 03, 04, 06, 07 (about 45 min), 08, 09, then 10. The test year (2025) has still not been used.
> - **Checks done:** the identical Saturday/Sunday MAE was a coincidence (14 July 2024, a Sunday public holiday, is excluded from the Sunday segment). `08` now also fits `cal_lags_no13` (no consumption at 13:00 on day J): pre-fix validation MAE about 1485 vs 1345 MW with that lag. About half of the linear model's edge over the ARIMA therefore comes from the 13:00 information and half from combining lags (hours 6-13 are equal; the ARIMA is worse by 400-560 MW in hours 14-23).
> - **Failure days (pre-fix, checked against sources):** 2024-11-24 is a regime break (about 15 degrees warm-up in 72 h after the 21-22 Nov cold spell, storm Bert). 2024-01-08 is the onset of a cold wave plus the return from the Christmas break, with B2 and `lag_w` contaminated by the 1 Jan holiday. 2024-12-24 was caused by the calendar bug (Christmas break unflagged), not a model failure. 2024-05-02 (day after the 1 May holiday) and 2024-01-19 are not verified. Regenerate the list after the fix.
> - **Added:** `outputs/information_availability.md` (information-availability table) and `R/10_diagnostics.R`.
> - **Candidate AI-usage example (error detected):** the school-holiday bug was found by checking the largest-error day (24 Dec 2024) against the official school calendar.

### Status
Scripts 00-09 are written. Scripts 06, 07, 08 and 09 have been run on the **validation year (2024) only**. The **test year (2025) has not been used** and must be evaluated only once, at the very end.

### Results on validation (2024, MAE in MW)
| Model | MAE | Deployable |
|---|---|---|
| Linear, calendar + lags (`cal_lags`) | 1345 | yes (best) |
| ARIMA per hour | 1644 | yes |
| B1 previous day (strict) | 3183 | yes |
| B2 same weekday last week | 3229 | yes |
| B3 mean of 4 weeks | 3707 | yes |
| Linear, calendar + lags + observed J+1 temperature | 864 | **no** (perfect-weather bound) |

Ablation on the perfect-weather model (MAE increase when a group is removed): weather +481, lags +801, calendar +859. Groups overlap, so these are not additive.

### Main findings
- The simple linear model beats the ARIMA on almost every metric. A hypothesis (not yet tested): it uses consumption at 13:00 on day J, which the per-hour ARIMA does not. MAE by hour (`outputs/mae_by_hour_val.csv`) can test this.
- `cal_lags` is the best deployable model in every season, day type and temperature regime. In summer and autumn the margin over the ARIMA and weekly benchmarks is small.
- Errors are largest in winter (DJF 2159 MW vs summer 796) and on cold days (<5 C: 2284 MW). Perfect weather cuts winter error by ~46% but summer error by only ~18%.
- Perfect weather does not help on public holidays (2054 vs 2050 MW, 11 days only): the error there is calendar-related.
- 9 of the 10 largest-error days are flagged by a rough heuristic as weather-driven, with the error bias following the temperature change from the previous day. The 14:00 operational model has no J+1 weather, so this is an information limit.
- Candidate failure days for the report (causes are hypotheses to verify): 2024-11-24 (warm-up after cold, large over-forecast), 2024-12-24 (holiday eve, weather does not help), 2024-01-08 (benchmark B2 contaminated by the 1 Jan holiday).

### Open points and checks
- (Resolved) Saturday and Sunday MAE were identical for both linear models: coincidence, see the update at the top of this section.
- Validation list items still open: repeated autumn hour, school-holiday zones including Corsica, 4 missing consumption hours, 62 missing temperature hours, why solar radiation `sw` is entirely missing.
- SYNOP temperature `t` is in Kelvin (confirmed in the documentation; scripts 08 and 09 convert to deg C automatically).
- `tn12`, `tx12` and `n_stations` missingness is structural (three-hourly SYNOP), not an acquisition error.
- Assumption to document: consumption up to 13:00 on day J is treated as available at 14:00, using final (consolidated) RTE values; operationally these would be provisional.

### Remaining work (from the course brief)
1. Information-availability table: done, see `outputs/information_availability.md` (update if the model changes).
2. Final single evaluation on the test year 2025 (set `EVAL_SPLIT <- "test"` in 07, 08 and 09; 07 takes ~45 min; do not tune anything on it).
3. Analysis of at least three failure days, classified as data limit, model limit, regime break, hard-to-predict event or protocol weakness (verify events on the real dates).
4. Robustness discussion (stability of model ranking across periods, metrics and hours) and situations where the system should not be used.
5. Report (< 10 pages), 10-minute slides, and three documented examples of AI-assistant use (one kept after verification, one modified or rejected, one error detected). Candidate examples are in `statut_projet.txt`.
6. Optional: an ARIMA-based ablation, or a daily ARIMA as a faster alternative; a more realistic operational-weather scenario would need archived forecasts.

### Notes for an AI assistant continuing this work
- The group is on a free plan with limited tokens: deliver work in increments, do not run slow code (script 07 takes ~45 min) and do not read raw data; read only the R scripts and the `outputs/` CSV files when needed.
- Run scripts from the project root; `R/00_run_pipeline.R` has flags `RUN_DATA`, `RUN_BENCHMARKS`, `RUN_ARIMA`, `RUN_ABLATION`, `RUN_ANALYSIS` to run stages separately.
- Column names: time `datetime_utc`, target `consommation`, temperature `t`, calendar `is_public_holiday`, `is_holiday_eve`, `school_holiday_A/B/C`.
- Never use observed J+1 weather in an operational model; it is only a labelled perfect-weather benchmark.
- A French status file for the project partner is `statut_projet.txt` (it predates scripts 08, 09 and 10 and the calendar fix, so it needs updating).
- After re-running 04, check the school-holiday flags in `modelling_dataset.csv` around Christmas (all three zones should be 1 from the start of the break to early January, and 2024-01-08 should be 0).