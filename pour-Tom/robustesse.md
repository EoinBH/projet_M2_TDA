# Robustesse du classement et conditions d'utilisation

Validation = 2024 (366 jours), test = 2025. MAE en MW, erreur = prévision - observé. Sources : `rank_by_metric_*.csv`, `rank_by_quarter_*.csv`, `hours_best_*.csv`, `bias_by_month_*.csv`, `errors_by_segment_*.csv`, `paired_tests_*.csv`. `arima_v1` n'existe que sur la validation.

## 1. Le classement est-il stable ?

| Critère | Validation 2024 | Test 2025 | Verdict |
|---|---|---|---|
| Ordre global | {`cal_lags`, `cal_lags_tempJ`} > `arima_v2` > benchmarks | identique | **stable** |
| `cal_lags_tempJ` vs `cal_lags` | tempJ 1er sur les 5 métriques (MAE 1337 vs 1348) | `cal_lags` 1er sur MAE, total journalier et pic (1323 vs 1343) ; tempJ 1er sur RMSE et heure du pic (1828 vs 1875) | **instable** (écart non significatif : p = 0,72 val, p = 0,46 test sur la MAE) |
| Par trimestre | tempJ 1er aux T1, T2, T4 ; `cal_lags` 1er au T3 | tempJ 1er aux T1, T4 ; `cal_lags` 1er aux T2, T3 | **stable pour l'hiver et l'automne (tempJ)**, T2 bascule |
| Par heure (nombre d'heures gagnées sur 24) | tempJ 15, `cal_lags` 6, ARIMA 3 | `cal_lags` 17, tempJ 7, ARIMA 0 | linéaires devant, mais **le gagnant entre les deux change** |
| Benchmarks | B1 > B2 > B3 sur la MAE | B1 > B2 > B3 sur la MAE | stable sur la MAE ; B3 3e sur l'heure du pic dans les deux périodes |

- Les deux modèles linéaires battent `arima_v2` de manière significative sur les deux périodes (+263 MW val, +294 MW test sur la MAE, p < 0,001), et tous les benchmarks de plus de 1700 MW (`cal_lags` vs B1 : -1835 MW val, -1791 MW test).
- Conclusion : la hiérarchie « linéaire > ARIMA > benchmarks » est robuste ; le choix entre `cal_lags` et `cal_lags_tempJ` ne l'est pas. Figures : `mae_by_month_{val,test}.png`, `mae_by_hour_{val,test}.png`.

## 2. Biais mensuel (`bias_by_month_*.csv`, figure `bias_by_month_{val,test}.png`)

- `cal_lags` sur-prévoit dans 9 mois sur 12 les deux années ; les plus forts biais sont en hiver : février 2024 +1324 MW, janvier 2025 +896 MW.
- `arima_v2` reste entre -370 et +360 MW chaque mois, sur les deux années : pas de dérive de niveau.
- Le signe de novembre change (+142 MW en 2024, -379 MW en 2025) : le biais mensuel n'est pas stable.

## 3. Situations où le système ne doit pas être utilisé sans précaution (MAE de `cal_lags`, val / test)

| Situation | Erreur | Repère | Lecture |
|---|---|---|---|
| Jours froids (< 5 °C) : 23 / 32 jours | 2276 / 2004 | 1,5 à 1,7 fois la MAE globale (1348 / 1323) | B2 et B3 s'effondrent (7600 à 10900) ; météo parfaite : 1408 / 1266 |
| Hiver (DJF) | 2197 / 2064 | 2,4 à 2,8 fois l'été (787 / 857) | `cal_lags_tempJ` un peu meilleur (2067 / 1960) |
| Jours fériés : 11 / 11 jours | 2039 / 1637 | 1,2 à 1,5 fois la MAE globale | la météo parfaite n'aide pas (2054 / 1640) : erreur due au calendrier ; effectifs trop faibles pour conclure |
| Rupture de régime météo (24 nov. 2024, 8 janv. 2024) | +9081 / -5026 | 3,7 à 6,7 fois la MAE globale | voir `jours-echec.md` |
| Événement de calendrier rare (24 déc. 2024, mardi) | +5373 | 4 fois la MAE globale | la météo parfaite n'aide pas (4786) |
| Jours chauds (> 20 °C) : 52 / 63 jours | 772 / 952 | le meilleur cas | **n'utiliser que `cal_lags`** : tempJ fait 996 / 1128 (+29 % / +18 %) |

- **Conclusion pratique** : ne pas se fier aux prévisions par vague de froid ou changement brusque de température, au retour de vacances et les jours fériés rares ou tombant en semaine inhabituelle. Utiliser `cal_lags` l'été et `cal_lags_tempJ` seulement en hiver.
- Aucun intervalle de prédiction fiable : les résidus de l'ARIMA sont autocorrélés et deux à trois fois plus variables en hiver (README, script 10).
- Limites : un seul an de validation et un seul de test ; les segments de moins de 30 jours (fériés, jours froids) sont fragiles ; les écarts de moins de 50 MW entre les deux modèles linéaires ne sont pas établis.
