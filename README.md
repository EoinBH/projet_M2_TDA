# Day-ahead forecasting of French electricity consumption

Forecast of the hourly electricity consumption of metropolitan France for all 24 hours of day **J+1**, issued at **14:00 on day J**. Course project (Temporal Data Analysis, M2).

**Status (8 Nov 2026):** data preparation, benchmarks, per-hour ARIMA, linear ablation models, error analysis and time-series diagnostics are done on the validation year (2024), after a school-holiday calendar fix. Still to do: choice of a more elaborate model, the single final evaluation on the test year 2025, the failure-day write-up, robustness discussion, report and slides.

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
outputs/             benchmark and model results, figures/
pour-Tom/            status files for the project partner (French)
```

| Script | Role |
|---|---|
| `00_run_pipeline.R` | master script: installs packages, runs everything (stages switched by `RUN_*` flags) |
| `01_prepare_RTE.R` | import and hourly aggregation of RTE data |
| `02_prepare_weather.R` | import, filtering, aggregation and interpolation of SYNOP data |
| `03_prepare_calendar.R` | holidays, school holidays, calendar features |
| `04_merge_datasets.R` | UTC merge, local timestamps, diagnostics -> `modelling_dataset.csv` |
| `05_eda.R` | exploratory analysis on the **training period only**: daily and weekly cycles, annual seasonality, relation with temperature, calendar effects, 2022 level shift, atypical days (figures `outputs/figures/eda_*.png`, tables `outputs/eda_*.csv`) |
| `protocol.R` | not run directly: configuration, hourly matrix (days x 24 hours), availability rule, splits, metrics; sourced by scripts 05-10 |
| `06_benchmarks.R` | three simple benchmarks respecting the 14:00 constraint |
| `07_arima.R` | one seasonal ARIMA with calendar regressors per hour of the day |
| `08_ablation.R` | fast per-hour linear models: simple operational model, ablation of calendar / lags / weather, perfect-weather bound |
| `09_error_analysis.R` | errors by season / day type / temperature / hour, largest-error days with context and plots (reads outputs of 06-08, no refitting) |
| `10_diagnostics.R` | ADF/KPSS tests and ACF/PACF of the daily series (train), ARIMA residual diagnostics (Ljung-Box, normality, variance by season), autocorrelation of out-of-sample forecast errors; needs the outputs of 07 and 08 |

## 4. How to run

1. Open R with the **project root as working directory**.
2. Run:
   ```r
   source("R/00_run_pipeline.R")
   ```
   Packages are installed automatically if missing (tidyverse, lubridate, readxl, janitor, jsonlite, stringi, zoo, clock, forecast, tseries).
3. Stages can be switched on/off with the flags `RUN_DATA` (01-04), `RUN_EDA` (05), `RUN_BENCHMARKS` (06), `RUN_ARIMA` (07), `RUN_ABLATION` (08), `RUN_ANALYSIS` (09), `RUN_DIAGNOSTICS` (10) in `00_run_pipeline.R` (for example set all but `RUN_ANALYSIS` to `FALSE` to re-run only script 09 on existing outputs).

**Run time:** data preparation is quick; `07_arima.R` is the expensive step (about 45 minutes on the author's machine for the validation year, together with `06`).

## 5. Models

- **Benchmarks (06):** B1 previous day (day J for hours 0-13, day J-1 for hours 14-23, because the rest of day J is unknown at 14:00); B2 same weekday last week; B3 mean of the same weekday over the last 4 weeks.
- **ARIMA (07):** for each hour h, a regression with seasonal ARIMA errors on the daily series of hour h (weekly period 7). Regressors: public holiday, holiday eve, school-holiday zones A/B/C, 2 annual Fourier pairs. Orders chosen on the training period only; coefficients re-estimated every 28 days on an expanding window; between re-estimations the model is only updated with new observations. Hours 0-13 are 1-step-ahead forecasts, hours 14-23 are 2-step-ahead forecasts.
- **Linear models (08):** one OLS regression per hour of the target day, re-fitted every 28 days (same protocol). Groups of regressors: calendar (weekday, holidays, school holidays, annual Fourier terms), lags (`lag_last` = consumption at 13:00 on day J, `lag_d`, `lag_w`, `lag_mean2`) and weather (observed J+1 temperature, perfect-weather scenarios only, labelled non-deployable). `cal_lags` (calendar + lags) is the simple operational model; `cal_lags_no13` is the same without `lag_last`.

## 6. Outputs

| File | Content |
|---|---|
| `outputs/benchmarks_validation.csv`, `outputs/scores_val.csv` | benchmark scores; ARIMA vs benchmarks on the same dates |
| `outputs/arima_orders.csv` | selected ARIMA order per hour |
| `outputs/benchmarks.rds`, `outputs/arima_val.rds`, `outputs/ablation_val.rds` | forecasts and observations (R binary format; read with `readRDS()`) |
| `outputs/errors_by_segment_val.csv`, `mae_by_hour_val.csv`, `failure_days_val.csv` | error analysis (script 09) |
| `outputs/stationarity_tests_train.csv`, `residual_diagnostics_train.csv`, `forecast_error_diagnostics_val.csv` | time-series diagnostics (script 10) |
| `outputs/figures/` | plots from scripts 09 and 10 (`acf_pacf_train.png`, `residuals_train.png`, `forecast_errors_val.png`, ...) |
| `outputs/information_availability.md` | information-availability table required by the brief |

## 7. Known limitations

- Observed weather is not used in the operational models; an operational weather model would need archived forecasts available at 14:00.
- Missing consumption values (4 hours) are filled by last observation carried forward; the repeated autumn hour is averaged.
- Variables with high missingness in SYNOP (`tn12`, `tx12`, `sw`, station count) are not used by the models.
- 2022 is atypical (energy crisis, reduced nuclear availability) and is part of the training data.
- School holidays: events naming only Corsica are ignored; "Pont de l'Ascension" and teacher pre-return events are flagged as school holidays for the zones listed.
- Consumption up to 13:00 on day J is treated as available at 14:00 using final RTE values; operationally these would be provisional.

## 8. Project status, results and next steps (as of 8 Nov 2026)

### Status
Scripts 00-10 are written. Scripts 06-10 have been run on the **validation year (2024) only**, after the calendar fix below. `05_eda.R` (training period only) is written but has not been run yet; check its figures and tables before writing the exploration section of the report. The **test year (2025) has not been used** and must be evaluated only once, at the very end.

### Calendar bug (fixed)
`03_prepare_calendar.R` silently dropped every school-holiday event labelled with several zones ("Zones A/B/C", "Zones A/C", ...): 60 of 76 events, including all Christmas, Toussaint and summer breaks. It was found by checking the largest-error day (24 Dec 2024) against the official school calendar. After the fix: 121-128 flagged days per zone and year, and Christmas Eve is flagged in every year. The fix changed the scores very little (ARIMA MAE 1643.5 -> 1654.2, `cal_lags` 1345 -> 1348), and the ranking of models is unchanged. It did **not** explain the 24 Dec error (5364 -> 5373 MW), see failure days.

### Results on validation (2024, MW)
| Model | MAE | RMSE | MAE daily total | MAE peak value | MAE peak hour (h) | Deployable |
|---|---|---|---|---|---|---|
| Linear, calendar + lags (`cal_lags`) | 1348.3 | 1967.6 | 28710.9 | 1400.0 | 1.7 | yes (best) |
| Linear, calendar + lags without 13:00 lag (`cal_lags_no13`) | 1499.3 | 2236.5 | 31422.1 | 1442.3 | 2.1 | yes |
| ARIMA per hour | 1654.2 | 2419.6 | 32468.0 | 1545.9 | 2.5 | yes |
| Linear, lags only | 2176.8 | 3067.0 | 47737.4 | 2505.0 | 2.3 | yes |
| Linear, calendar only | 2852.8 | 3970.7 | 64970.1 | 2927.0 | 1.9 | yes |
| B1 previous day (strict) | 3183.0 | 4362.1 | 72276.1 | 3278.6 | 2.4 | yes |
| B2 same weekday last week | 3229.4 | 4845.7 | 74799.7 | 3394.5 | 2.1 | yes |
| B3 mean of 4 weeks | 3706.5 | 5354.4 | 86534.6 | 3804.8 | 1.9 | yes |
| Linear, calendar + lags + observed J+1 temperature | 866.9 | 1242.3 | 16114.9 | 921.9 | 1.3 | **no** (perfect-weather bound) |

Ablation on the perfect-weather model (MAE increase when a group is removed): weather +481, lags +711, calendar +856 (perfect-weather MAE without calendar 1723, without lags 1578). Groups overlap, so these are not additive.

### Main findings
- **13:00 information:** the linear model beats the ARIMA (1348 vs 1654, gap 306 MW). Removing `lag_last` (consumption at 13:00 on day J) raises its MAE to 1499, so about half of the gap (151 MW) comes from the 13:00 information and half from combining lags and calendar in one regression. The hourly profile of the gap (pre-fix run, to re-check in `mae_by_hour_val.csv`): hours 6-13 equal, ARIMA worse by roughly 400-560 MW in hours 0-5 and 14-23.
- **Segments (`cal_lags` MAE):** winter 2197 (ARIMA 2767), spring 1308, summer 787, autumn 1107; Saturday 1264, Sunday 1259, weekday 1354, public holiday 2039 (11 days only); cold days (<5 C) 2276 (23 days), mild 1378, hot (>20 C) 772. `cal_lags` is the best deployable model in every segment; in autumn the ARIMA is close (1148 vs 1107).
- **Weather:** perfect weather cuts winter error by about 48% (2197 -> 1134) but summer error by only 17% (787 -> 656), and does not help on public holidays (2054 vs 2039 MW): the error there is calendar-related.
- **Stationarity (script 10, training period):** the raw daily series of every hour is non-stationary (KPSS p = 0.01; ADF only rejects a unit root for hours 10-17). After removing calendar and annual effects (OLS) and a lag-7 difference, all hours are stationary (ADF p = 0.01, KPSS p = 0.1; `tseries` truncates p-values to 0.01-0.1). `ndiffs` gives 1 for all hours; `nsdiffs` (weekly) gives 1 for hours 6-22 and 0 for hours 0-5 and 23. The automatically selected orders agree (D = 1 for hours 6-21, d = 1 for the night hours), except hour 22.
- **ARIMA residuals (training period):** Ljung-Box (lag 14) rejects white noise for 23 of 24 hours (only hour 3 passes); the remaining autocorrelation is small but significant (max |ACF| 0.11-0.30 vs band 0.073). Residuals are not normal (Shapiro p < 0.0001 for all hours) and their standard deviation is 2.2-3.4 times larger in winter than in summer (heteroscedasticity; e.g. hour 8: 3460 vs 1173 MW). The per-hour ARIMA is therefore misspecified, which fits the missing temperature effect; prediction intervals from it would be unreliable.
- **Validation forecast errors (daily mean error):** lag-1 autocorrelation 0.36 (ARIMA), 0.32 (`cal_lags`), 0.50 (`cal_lags_no13`) and 0.38 even with perfect weather; lag-7 autocorrelation -0.09 (ARIMA), 0.18-0.23 (linear models); Ljung-Box p < 0.0001 for all (read the ARIMA with care: its 2-step errors are autocorrelated by construction). Mean error is small (-53 to +366 MW vs a daily standard deviation of 1700-2000 MW). Day-to-day persistence of the errors is a lead for the more elaborate model.
- **Heuristic from script 09:** 9 of the 10 largest-error days are flagged as weather-driven (error follows the temperature change from the previous day). The operational model has no J+1 weather, so this is an information limit.

### Failure days (validation 2024, `cal_lags`; bias = forecast minus observed)
| Date | Mean error (MW) | With perfect weather | What happened | Class | Status |
|---|---|---|---|---|---|
| 2024-11-24 (Sun) | +9081 | 1937 | About 15 degrees of warm-up in 72 h (21 -> 24 Nov), after the 21-22 Nov cold spell with snow (storm Caetano), then record mild air (storm Bert, 24-25 Nov); lags from the cold Saturday | regime break / information limit | weather events verified |
| 2024-01-08 (Mon) | -5026 | 2305 | Onset of the January cold wave (negative temperatures from 8 Jan, consumption peak 83.5 GW on 10 Jan) and first working Monday after the Christmas break; the 1 Jan holiday contaminates B2 (error 20750) and probably `lag_w` | regime break + model limit | cold wave and calendar verified |
| 2024-12-24 (Tue) | +5373 | 4786 (no help) | Holiday eve inside the Christmas school break; B1 (previous day) does best (2493). In the training years 24 Dec fell on a Saturday (2022) and a Sunday (2023), so a Tuesday Christmas Eve was never seen and the additive calendar model cannot represent it. Not caused by the calendar bug (error unchanged after the fix) | model limit / rare calendar event | reasoning checked by calendar arithmetic, effect itself not tested |
| 2024-11-21 (Thu) | -5849 | 2721 | Cold snap and snow (storm Caetano, 21-22 Nov) | regime break | weather event verified |
| 2024-01-19 (Fri) | -7363 | 2495 | Cold day (1.4 C, 4.9 C colder than the day before) | weather-driven | specific event not verified |
| 2024-05-02 (Thu) | -6797 | 1811 | Bridge day after the Wednesday 1 May holiday; day J is a holiday so its lags are low; cool day (11.3 C) | calendar + weather | not verified |

Suggested three for the report (one per class, facts verified): 2024-11-24, 2024-01-08, 2024-12-24.

### Open points and checks
- Validation list items still open: repeated autumn hour, 4 missing consumption hours, 62 missing temperature hours, why solar radiation `sw` is entirely missing.
- SYNOP temperature `t` is in Kelvin (confirmed in the documentation; scripts 08 and 09 convert to deg C automatically).
- `tn12`, `tx12` and `n_stations` missingness is structural (three-hourly SYNOP), not an acquisition error.
- Resolved: identical Saturday/Sunday MAE (coincidence: 14 July 2024, a Sunday public holiday, is excluded from the Sunday segment); school-holiday flags (see calendar bug); information-availability table.

### Remaining work (from the course brief)
1. Choose the "more elaborate model" for the benchmark / simple / elaborate comparison. Leads from the diagnostics: a regression with AR/ARMA errors or an error correction using the morning (hours 0-13) of day J, because daily errors are autocorrelated even with perfect weather; a machine-learning model on the same lag features; variance stabilisation (winter errors are 2-3 times larger). Keep everything deployable at 14:00. Decided: add the operational temperature available at 14:00 (raw 3-hourly SYNOP observations up to a conservative cut-off, no hourly interpolation, which would use later observations) to the linear model and the ARIMA as new model versions, keeping the previous versions for comparison.
2. Final single evaluation on the test year 2025 (set `EVAL_SPLIT <- "test"` in 07, 08, 09 and 10; 07 takes ~45 min; do not tune anything on it). By season, working / non-working days and public holidays.
3. Write up the three failure days (table above).
4. Robustness discussion (stability of model ranking across periods, metrics and hours) and situations where the system should not be used (cold snaps, rare calendar events, regime breaks).
5. Report (< 10 pages), 10-minute slides, and three documented examples of AI-assistant use (one kept after verification, one modified or rejected, one error detected). Candidate examples are in `pour-Tom/statut_projet.txt`.
6. Optional: a daily ARIMA as a faster alternative; a more realistic operational-weather scenario would need archived forecasts.

### Notes for an AI assistant continuing this work
- The group is on a free plan with limited tokens: deliver work in increments, do not run slow code (script 07 takes ~45 min) and do not read raw data; read only the R scripts and the `outputs/` CSV files when needed. Long conversations use the allowance faster, so start a new chat when the context gets long.
- Run scripts from the project root; `R/00_run_pipeline.R` has one `RUN_*` flag per stage (data, EDA, benchmarks, ARIMA, ablation, analysis, diagnostics). `R/protocol.R` is sourced by scripts 05-10 and is not run on its own.
- Column names: time `datetime_utc`, target `consommation`, temperature `t`, calendar `is_public_holiday`, `is_holiday_eve`, `school_holiday_A/B/C`.
- Never use observed J+1 weather in an operational model; it is only a labelled perfect-weather benchmark.
- French status file for the project partner (who writes the report): `pour-Tom/statut_projet.txt` (updated 8 Nov 2026 evening).
