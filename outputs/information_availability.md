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
| Temperature up to 14:00 on J | Meteo-France SYNOP | Yes, after a delay | Observed | Not used | Low. Note that hourly values interpolated from 3-hourly data may use later observations |
| Production, exchanges, CO2 intensity | RTE eCO2mix | Same as consumption | Observed | Not used | Medium. Contemporaneous with the target |
| `tn12`, `tx12`, `sw`, number of stations | SYNOP | Partly | Observed | Not used | High missingness (structural for 3-hourly data, `sw` entirely missing) |
| Weather forecast for J+1 issued before 14:00 on J | Not in the dataset | Yes in reality | Forecast | Not used | Would need archived forecasts. Main protocol limitation |

## Notes

- **Provisional vs definitive data:** consumption up to 13:00 on J is treated as available at 14:00 using definitive RTE values. In operation these would be provisional.
- **Sensitivity to the 13:00 information (validation 2024):** removing `lag_last` (consumption at 13:00 on J) from the linear model raises MAE from about 1345 MW to about 1485 MW. The assumption therefore matters for the result and should be stated in the report.
- **Perfect-weather scenario:** the J+1 temperature model is an upper bound only and is never presented as deployable.
