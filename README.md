# Day-ahead forecasting of French electricity consumption

Forecast of the hourly electricity consumption of metropolitan France for all 24 hours of day **J+1**, issued at **14:00 on day J**. Course project (Temporal Data Analysis, M2).

**Status (10 Nov 2026):** all analyses are done on validation (2024) and on the single test run (2025). What remains is the written report and slides (partner), completing `pour-Tom/usage-ia.md`, and repository clean-up. Partner-facing summaries (French) are in `pour-Tom/`.

## 1. Forecast protocol

- **Origin / horizon:** 14:00 local time on day J; the 24 hours of J+1.
- **Information at 14:00 on J:** consumption of all days before J plus hours 0-13 of day J (hours 14-23 of J are not yet observed). Calendar variables are known in advance. Operational temperature: raw 3-hourly SYNOP observations up to 09:00 UTC on day J and the mean of day J-1. Observed weather of J+1 is **never** used in an operational model.
- **Chronological split (by target date):** train 2022-2023, validation 2024, test 2025. The test period was used once, for the final evaluation.
- **Metrics:** MAE, RMSE, error on daily total, error on peak value, error on peak hour. Error = forecast - observed, in MW.

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
outputs/             results (CSV, RDS) and figures/
pour-Tom/            French summaries for the project partner (status, results, failure days, robustness, AI usage)
```

| Script | Role |
|---|---|
| `00_run_pipeline.R` | master script: packages, **single switch `EVAL_SPLIT`** (`"val"` or `"test"`), `SPECS_TO_RUN` (ARIMA versions), one `RUN_*` flag per stage (01-10) |
| `01_prepare_RTE.R` ... `04_merge_datasets.R` | data preparation -> `data/processed/modelling_dataset.csv` |
| `05_eda.R` | exploratory analysis, **training period only** |
| `protocol.R` | not run directly: configuration, hourly matrix (days x 24), availability rule, splits, metrics, `ARIMA_SPECS`, operational temperature features; sourced by 05-10 and `load_results.R` |
| `06_benchmarks.R` | benchmarks B1-B3 (covers all target dates, validation and test) |
| `07_arima.R` | one seasonal ARIMA per hour for each version in `SPECS_TO_RUN`; re-uses the orders in `outputs/<version>_orders.csv` when present (chosen on training only) |
| `08_ablation.R` | per-hour linear models: `cal_lags`, `cal_lags_tempJ`, ablation (calendar / lags / weather), perfect-weather bound |
| `09_error_analysis.R` | errors by season / day type / temperature / hour, largest-error days |
| `10_diagnostics.R` | ADF/KPSS, ACF/PACF, ARIMA residual diagnostics, autocorrelation of forecast errors |
| `load_results.R` | helper, sourced by 11 and 12: loads saved forecasts (no refitting) |
| `11_tests_and_bias.R` | paired Diebold-Mariano tests + block bootstrap, bias and MAE by month, ranking stability |
| `12_report_figures.R` | report figures: model comparison, ablation, segments, typical weeks, chosen failure days, protocol timeline |

## 4. How to run

1. Open R with the **project root as working directory**. Packages are installed automatically by `00_run_pipeline.R` if missing.
2. **Validation run** (`EVAL_SPLIT <- "val"`, the default): `source("R/00_run_pipeline.R")`, with the `RUN_*` flags set to the stages wanted. Scripts 11 and 12 are **not** wired into `00_run_pipeline.R`; run them by hand:
   ```r
   EVAL_SPLIT <- "val"; source("R/11_tests_and_bias.R")
   EVAL_SPLIT <- "val"; source("R/12_report_figures.R")
   ```
3. **Test run (once, after the protocol is frozen)**, in a fresh R session at the project root:
   ```r
   EVAL_SPLIT <- "test"; SPECS_TO_RUN <- "arima_v2"; source("R/07_arima.R")
   source("R/08_ablation.R")       # reads the scores written by 07, so 07 comes first
   source("R/09_error_analysis.R")
   source("R/10_diagnostics.R")    # optional: only part C depends on the split
   source("R/11_tests_and_bias.R")
   FAIL_DATES <- NULL; source("R/12_report_figures.R")   # NULL = plot the 3 worst test days
   ```
   `06_benchmarks.R` need not be re-run (`benchmarks.rds` already covers 2025). `EVAL_SPLIT` lives in the R session: check the "Evaluation split:" message at the start of each script, and set it again after restarting R (default is `"val"`).

**Expensive steps:** `07_arima.R` (one ARIMA per hour, refitted every 28 days): about 45 minutes per ARIMA version on the validation year on the author's machine; on the test year only `arima_v2` was run with its orders re-used, which is faster. Everything else runs in seconds to a few minutes; scripts 11 and 12 run in seconds because they only read saved forecasts.

## 5. Models

- **Benchmarks (06):** B1 previous day, strict (day J for hours 0-13, day J-1 for hours 14-23, because the rest of day J is unknown at 14:00); B2 same weekday last week; B3 mean of the same weekday over the last 4 weeks.
- **ARIMA (07):** for each hour h, a regression with seasonal ARIMA errors on the daily series of hour h (weekly period 7). Regressors: public holiday, holiday eve, school-holiday zones A/B/C, 2 annual Fourier pairs; `arima_v2` adds the operational temperature. Orders chosen on the training period only; coefficients re-estimated every 28 days on an expanding window. Hours 0-13 are 1-step-ahead forecasts, hours 14-23 are 2-step-ahead.
- **Linear models (08):** one OLS regression per hour of the target day, refitted every 28 days. Groups: calendar (weekday, holidays, school holidays, annual Fourier terms), lags (`lag_last` = consumption at 13:00 on day J, `lag_d`, `lag_w`, `lag_mean2`), weather. `cal_lags` (= linear_v1) is the simple operational model; `cal_lags_tempJ` (= linear_v2) adds the operational temperature; `cal_lags_no13` drops `lag_last`; perfect-weather models (observed J+1 temperature) are **non-deployable bounds**.
- **Versions and log:** old versions are kept, never overwritten (`arima_v1`, `arima_v2` in `ARIMA_SPECS`; `linear_v1`, `linear_v2` in 08). `outputs/model_log.csv` records the hypothesis and validation score of each version.
- **Operational temperature:** national mean of the raw 3-hourly SYNOP observations (`data/processed/weather_3hourly.csv`); only what is available at 14:00 on day J (observations up to 09:00 UTC on J, mean of J-1), plus heating degrees below 15 C. The 12:00 UTC observation and hourly interpolated values are not used.

## 6. Results

### Scores (MW; test used once)

| Model | Deployable | Val MAE | Val RMSE | Test MAE | Test RMSE |
|---|---|---|---|---|---|
| B1 previous day (strict) | yes | 3183 | 4362 | 3114 | 4275 |
| B2 same weekday last week | yes | 3229 | 4846 | 3449 | 5136 |
| B3 mean of 4 weeks | yes | 3707 | 5354 | 3631 | 5116 |
| `arima_v1` (calendar only) | yes | 1654 | 2420 | not run | not run |
| `arima_v2` (+ operational temperature) | yes | 1611 | 2324 | 1617 | 2291 |
| `cal_lags` | yes | 1348 | 1968 | **1323** | 1875 |
| `cal_lags_tempJ` | yes | **1337** | **1880** | 1343 | **1828** |
| Perfect J+1 weather (bound) | **no** | 867 | 1242 | 875 | 1192 |

Full scores: `outputs/scores_all_val.csv`, `scores_all_test.csv`.

### Main findings
- **Linear vs ARIMA vs benchmarks:** same order on both periods: linear models > `arima_v2` > benchmarks. Both linear models cut MAE by about 57-58% relative to the best benchmark (B1). `arima_v2` is significantly worse than `cal_lags` (+263 MW val, +294 MW test on MAE, p < 0.001).
- **`cal_lags` vs `cal_lags_tempJ`:** statistically equivalent. Val: MAE -11 MW (p = 0.72), squared error significantly lower (p = 0.029). Test: MAE +20 MW (p = 0.46), squared error -173,000 (p = 0.12), not significant. The frozen recommendation (see below) was `cal_lags_tempJ`; the test did not confirm its advantage, and `cal_lags` is simpler with an equal or lower MAE.
- **Ablation** (perfect-weather model, MAE increase when a group is removed, val / test): calendar +856 / +821, lags +711 / +669, weather +481 / +448; same order on both periods. Removing the 13:00 lag costs +151 / +154 MW. The operational temperature recovers little of the perfect-weather potential.
- **Segments:** operational temperature helps in winter and on cold days and hurts in summer and on hot days (val and test); winter error is about 1.9-2.8 times the summer error for the operational models; perfect weather does not help on public holidays (calendar-driven error).
- **Bias:** linear models over-forecast on average in validation (+366 / +405 MW), positive in 9 of 12 months in both years; ARIMA is close to unbiased.
- **Time-series diagnostics (training period):** raw hourly series are non-stationary (KPSS); after calendar/annual effects and a lag-7 difference all hours are stationary. ARIMA residuals are autocorrelated (Ljung-Box rejects for 23 of 24 hours in v1 and v2), non-normal, and 2.2-3.4 (v1) / 1.8-2.3 (v2) times more variable in winter than in summer: prediction intervals would be unreliable. Daily forecast errors are autocorrelated (lag 1: 0.28-0.50), a lead for future work.
- **Failure days** (validation, `cal_lags`): 2024-11-24 (+9081 MW, abrupt warm-up), 2024-01-08 (-5026 MW, cold wave and holiday-contaminated lags), 2024-12-24 (+5373 MW, Christmas Eve on a Tuesday, never seen in training). Details and evidence status in `pour-Tom/jours-echec.md`.
- **Robustness and conditions of use:** `pour-Tom/robustesse.md`. Do not rely on the system during cold snaps and abrupt temperature changes, after holiday breaks, and on rare calendar days; on hot days use `cal_lags` rather than `cal_lags_tempJ`.

## 7. Outputs

### Tables and results (`outputs/`)
| File(s) | Content | Script |
|---|---|---|
| `scores_all_{val,test}.csv` | all models, 5 metrics (main results table) | 12 |
| `scores_{val,test}.csv`, `benchmarks_validation.csv` | ARIMA vs benchmarks on the same dates; benchmark scores | 06, 07 |
| `ablation_scores_*.csv`, `ablation_groups_*.csv`, `ablation_summary_*.csv` | linear models and ablation (MAE increase per removed group, summary used for the ablation figure) | 08, 12 |
| `paired_tests_{val,test}.csv` | Diebold-Mariano tests with bootstrap CI | 11 |
| `rank_by_metric_*.csv`, `rank_by_quarter_*.csv`, `hours_best_*.csv` | ranking stability by metric, quarter, hour | 11 |
| `bias_by_month_*.csv`, `mae_by_month_*.csv` | monthly bias and MAE per model | 11 |
| `errors_by_segment_*.csv`, `mae_by_hour_*.csv`, `failure_days_*.csv` | error analysis: season, day type, temperature, hour, largest-error days | 09 |
| `forecast_error_diagnostics_*.csv` | mean error, daily error sd, autocorrelation of forecast errors | 10 |
| `stationarity_tests_train.csv`, `residual_diagnostics_train*.csv` | stationarity tests; ARIMA residual diagnostics per version | 10 |
| `eda_summary.csv`, `eda_atypical_days.csv` | exploratory analysis (training) | 05 |
| `arima_v1_orders.csv`, `arima_v2_orders.csv` | ARIMA order per hour, chosen on training | 07 |
| `model_log.csv` | one row per model version: description, hypothesis, validation score | 07, 08 |
| `information_availability.md` | information-availability table required by the brief | by hand |
| `*.rds` (`benchmarks`, `arima_v1_val`, `arima_v2_{val,test}`, `ablation_{val,test}`) | saved forecasts and observations; read with `readRDS()` | 06-08 |

### Figures (`outputs/figures/`; suggested report section in brackets)
| File | Content |
|---|---|
| `protocol_timeline.png` | chronological split and information available at the 14:00 origin [Protocol] |
| `eda_daily_profile`, `eda_weekly_cycle`, `eda_annual_level`, `eda_temperature`, `eda_calendar_effects` `.png` | daily and weekly cycle, annual level and 2022 shift, consumption vs temperature, calendar effects, training period [Exploration] |
| `model_comparison_{val,test}.png` | MAE and RMSE of all models, perfect-weather bound separated [Results] |
| `ablation_{val,test}.png` | MAE increase when removing a variable group; operational models [Results] |
| `typical_weeks_{val,test}.png` | observed vs predicted, one ordinary winter and one summer week [Results] |
| `segments_{val,test}.png` | MAE by season, day type, temperature regime [Error analysis] |
| `mae_by_hour_{val,test}.png` | MAE by hour of the target day [Error analysis] |
| `failure_days_{val,test}.png` | the 3 largest-error days of `cal_lags` (script 09) [Error analysis] |
| `failure_days_chosen_{val,test}.png` | val: the 3 chosen failure days; test: the 3 worst test days (script 12) [Failure days] |
| `mae_by_month_{val,test}.png`, `bias_by_month_{val,test}.png` | monthly MAE and bias per model [Robustness] |
| `acf_pacf_train.png`, `residuals_train*.png`, `forecast_errors_{val,test}.png` | ACF/PACF of the training series, ARIMA residuals per version, forecast-error autocorrelation [Time-series diagnostics] |

Figures were produced by the scripts; check each visually before inserting it in the report.

## 8. Frozen protocol before test (10 Nov 2026, decided on validation 2024 only)

**Lineup evaluated once on the test year (2025):**
- Benchmarks `B1_prev_day_strict`, `B2_same_weekday_lw`, `B3_mean_4_weeks`; simple model `cal_lags`; simple model + operational temperature `cal_lags_tempJ`; time-series model `arima_v2`. `arima_v1` is not re-run on test (not significantly different from v2 on MAE on validation).
- Not deployable, for the ablation only: `FULL_PERFECT_WX`, `noCal_PERFECT_WX`, `noLags_PERFECT_WX`, plus `cal_only`, `lags_only`, `cal_lags_no13`.

**Selection rule (fixed before looking at test):** the recommended model is the deployable model with the lowest validation MAE and RMSE, provided it beats the simpler model with a paired Diebold-Mariano test (daily losses, Newey-West lag 7, p < 0.05) on MAE or on squared error; otherwise the simpler model is recommended. Test results are reported for all models but not used to change the recommendation, the models or the hyperparameters.

**Validation evidence (366 days):** `cal_lags_tempJ` best on all 5 metrics, in 3 of 4 quarters and for 15 of 24 hours; vs `cal_lags` the squared error is significantly lower (p = 0.029) but the MAE gain is not (p = 0.72). `arima_v2` is significantly worse than both linear models. **Recommended model: `cal_lags_tempJ`** (passes the rule on squared error). **Outcome on test:** not confirmed (see section 6); both linear models are reported, `cal_lags` being the parsimonious alternative.

**Known limitations, documented and not fixed before test:** linear models over-forecast on average in 2024 (+366 / +405 MW), concentrated in February, December and October; `cal_lags_tempJ` is worse than `cal_lags` in summer and on hot days; no weather forecast for J+1 is available, so the operational temperature is only a proxy.

## 9. Known limitations

- Observed weather is not used in the operational models; a real operational weather model would need archived forecasts available at 14:00. The perfect-weather bound (MAE about 870 MW) shows the potential.
- Consumption up to 13:00 on day J is treated as available at 14:00 using final RTE values; operationally these would be provisional. Sensitivity: about 150 MW of MAE (`cal_lags_no13`).
- Missing consumption values (4 hours) are filled by last observation carried forward; the repeated autumn hour is averaged.
- Variables with high missingness in SYNOP (`tn12`, `tx12`, `sw`, station count) are not used. SYNOP temperature `t` is in Kelvin (scripts convert to deg C automatically).
- 2022 is atypical (energy crisis, reduced nuclear availability) and is part of the training data.
- School holidays: events naming only Corsica are ignored; "Pont de l'Ascension" and teacher pre-return events are flagged as school holidays for the zones listed. A calendar bug (events labelled "Zones A/B/C" silently dropped, 60 of 76 events) was found on 8 Nov and fixed; all results were recomputed after the fix.
- One validation year and one test year: differences below about 50 MW between the two linear models are not statistically established; segments with fewer than 30 days (public holidays, cold days) are fragile.
- Open checks: repeated autumn hour, 4 missing consumption hours, 62 missing temperature hours, why solar radiation `sw` is entirely missing.

## 10. Remaining deliverables (non-code)

- Report (< 10 pages) and 10-minute slides, written by the partner from `pour-Tom/`.
- Complete the `[À COMPLÉTER]` items in `pour-Tom/usage-ia.md`.
- Repository clean-up before submission (ignore `.RData`, `.Rhistory`, `.DS_Store`, large `.rds`; remove `TODO_PROMPTS.md` if not wanted), then tag the final commit.

## Conventions
- Column names: time `datetime_utc`, target `consommation`, temperature `t`, calendar `is_public_holiday`, `is_holiday_eve`, `school_holiday_A/B/C`.
- Run scripts from the project root. Never use observed J+1 weather in an operational model; it is only a labelled perfect-weather benchmark.
- French files for the partner: `pour-Tom/statut_projet.txt` (status, file map), `resultats.md`, `jours-echec.md`, `robustesse.md`, `usage-ia.md`, `data-prep-summary.txt`.
