# Information-availability table

Forecast origin: 14:00 local time on day J. Target: the 24 hours of day J+1.

| Variable | Source | Available at 14:00 on J? | Observed / forecast | Used in | Leakage risk |
|---|---|---|---|---|---|
| Consumption, days <= J-1 | RTE eCO2mix (definitive annual files) | Yes (provisional values in practice) | Observed | All models (lags, ARIMA, benchmarks) | Low. Definitive values replace provisional ones |
| Consumption, hours 0-13 of day J | RTE eCO2mix | Yes, after a short publication delay (assumed) | Observed | `lag_last` and `lag_d` in the linear model, ARIMA (1-step hours), B1 | Medium. Definitive values used where provisional ones would exist |
| Consumption, hours 14-23 of day J | RTE eCO2mix | **No** | Observed | Never used (B1 and the lags fall back to J-1) | High if used. Excluded by construction |
| Weekday, public holiday, holiday eve | Public-holiday JSON, calendar | Yes, known in advance | Known | Calendar group, ARIMA regressors | Low |
| School holidays, zones A/B/C | School-holiday ICS | Yes, published in advance | Known | Calendar group, ARIMA regressors | Low (but check data coverage, see notes) |
| Annual Fourier terms (2 pairs) | Computed from the date | Yes | Deterministic | Calendar group, ARIMA regressors | None |
| Temperature of J+1 (`t`, hdd, cdd) | Meteo-France SYNOP, observed | **No** | Observed | Perfect-weather benchmark only | High. Never used in an operational model |
| Operational temperature: `op_t_last` (last raw observation <= 09:00 UTC on J), `op_t_morn` (mean of raw observations 00-09 UTC on J) | Meteo-France SYNOP, raw 3-hourly file `weather_3hourly.csv` | Yes, assumed available well before 14:00 local (09:00 UTC = 10:00 or 11:00 local; cutoff leaves a delay margin) | Observed | `cal_lags_tempJ`, `arima_v2` | Low. Raw 3-hourly values only: no hourly interpolation, which would use later observations. Gaps carried forward (past values only) |
| Operational temperature: `op_t_prev` (mean of all observations of day J-1) | Same | Yes, complete day | Observed | `cal_lags_tempJ`, `arima_v2` | Low |
| Operational heating degrees: `op_hdd_morn`, `op_hdd_prev` (= max(15 - mean temperature, 0)) | Computed from the two means above | Yes | Derived from observed | `cal_lags_tempJ`, `arima_v2` | Low. Threshold 15 C fixed from the training-period EDA |
| Lags: `lag_w` (same hour, J+1-7), `lag_d` (same hour, latest known day), `lag_mean2` (mean of day J-1), `lag_last` (13:00 on J) | Computed from consumption | Yes by construction (hours >= 14 use J-1) | Observed | `cal_lags`, `cal_lags_tempJ`, perfect-weather models | Low, except the provisional-data caveat in the notes |
| `hdd_day`, `cdd` (thresholds 15 C and 22 C) on J+1 observations | Computed from observed SYNOP of J+1 | **No** | Observed | Perfect-weather benchmark only | High. Never used in an operational model |
| Production, exchanges, CO2 intensity | RTE eCO2mix | Same as consumption | Observed | Not used | Medium. Contemporaneous with the target |
| `tn12`, `tx12`, `sw`, number of stations | SYNOP | Partly | Observed | Not used | High missingness (structural for 3-hourly data, `sw` entirely missing) |
| Weather forecast for J+1 issued before 14:00 on J | Not in the dataset | Yes in reality | Forecast | Not used | Would need archived forecasts. Main protocol limitation |

## Notes

- **Provisional vs definitive data:** consumption up to 13:00 on J is treated as available at 14:00 using definitive RTE values. In operation these would be provisional.
- **Sensitivity to the 13:00 information (validation 2024):** removing `lag_last` (consumption at 13:00 on J) from the linear model raises MAE from 1348 MW (`cal_lags`) to 1499 MW (`cal_lags_no13`). The assumption therefore matters for the result and should be stated in the report.
- **Operational temperature (added with v2):** it is a proxy, not a forecast: it describes day J and day J-1, not the target day J+1. Its gain is small (`cal_lags_tempJ` MAE 1337 vs 1348 MW). A real weather forecast for J+1 (see last table row) would be needed for a larger gain; the perfect-weather bound (MAE 867 MW) shows the potential.
- **First-day gap filling:** missing operational temperatures are carried forward; only leading gaps at the very start of the series are filled backwards (first days of 2022, far from the training end), so no leakage affects forecasts.
- **Perfect-weather scenario:** the J+1 temperature model is an upper bound only and is never presented as deployable.
