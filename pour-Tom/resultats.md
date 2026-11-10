# Résultats : validation (2024) vs test (2025)

Protocole : origine de prévision 14h le jour J, cible les 24 h de J+1. Modèles et règle de choix figés avant le test (voir README, section « Frozen protocol before test »). Le test a été exécuté une seule fois. Erreur = prévision - observé, en MW. Sources : `outputs/scores_all_val.csv`, `scores_all_test.csv`.

## 1. Tableau principal (MAE / RMSE, MW)

| Modèle | Utilisable à 14h ? | Val 2024 MAE | Val RMSE | Test 2025 MAE | Test RMSE |
|---|---|---|---|---|---|
| B1 veille stricte | oui | 3183 | 4362 | 3114 | 4275 |
| B2 même jour semaine dernière | oui | 3229 | 4846 | 3449 | 5136 |
| B3 moyenne 4 semaines | oui | 3707 | 5354 | 3631 | 5116 |
| `arima_v2` (ARIMA par heure + température opérationnelle) | oui | 1611 | 2324 | 1617 | 2291 |
| `cal_lags` (linéaire : calendrier + retards) | oui | 1348 | 1968 | **1323** | 1875 |
| `cal_lags_tempJ` (idem + température opérationnelle) | oui | **1337** | **1880** | 1343 | **1828** |
| `FULL_PERFECT_WX` (météo de J+1 parfaite) | **non** (borne haute) | 867 | 1242 | 875 | 1192 |

`arima_v1` n'a été évalué que sur la validation (MAE 1654, RMSE 2420). Figure : `outputs/figures/model_comparison_val.png` et `model_comparison_test.png`. Scores complets : `scores_all_*.csv`.

Points à retenir :
- Les deux modèles linéaires réduisent la MAE d'environ 57 à 58 % par rapport au meilleur benchmark (B1) sur les deux périodes (test : 1323 et 1343 vs 3114). Test apparié `cal_lags` vs B1 : -1791 MW, IC95 [-1936 ; -1653], p < 0,001 (`paired_tests_test.csv`).
- Les résultats test sont très proches de la validation (écarts de quelques dizaines de MW), ce qui indique une bonne stabilité du protocole.
- La borne « météo parfaite » (875) montre le potentiel d'une vraie prévision météo de J+1, absente du jeu de données.

## 2. Tests appariés (`paired_tests_*.csv`)

| Comparaison (perte quotidienne) | Val : écart MAE (p) | Test : écart MAE (p) | Test : écart MSE (p) |
|---|---|---|---|
| `cal_lags_tempJ` - `cal_lags` | -11 (0,72) | +20 (0,46) | -173 000 (0,12) |
| `arima_v2` - `cal_lags` | +263 (< 0,001) | +294 (< 0,001) | +1,73 M (< 0,001) |
| `cal_lags_tempJ` - `arima_v2` | -274 (< 0,001) | -275 (< 0,001) | -1,91 M (< 0,001) |

Lecture :
- `arima_v2` est **significativement moins bon** que les deux modèles linéaires, sur les deux périodes.
- Entre `cal_lags` et `cal_lags_tempJ`, **aucune différence significative sur le test**. Sur la validation, `cal_lags_tempJ` était significativement meilleur sur l'erreur quadratique (p = 0,029), ce qui avait motivé sa désignation comme modèle recommandé selon la règle fixée à l'avance. Le test **ne confirme pas** cet avantage : `cal_lags` a même la MAE la plus faible (1323 vs 1343), `cal_lags_tempJ` garde le meilleur RMSE (1828 vs 1875) sans que cela soit significatif (p = 0,12). Conclusion honnête pour le rapport : les deux modèles linéaires sont statistiquement équivalents, `cal_lags` est le plus simple. La recommandation n'a pas été modifiée après le test (règle du protocole).

## 3. Ablation (`ablation_summary_*.csv`, figure `outputs/figures/ablation_val.png` / `ablation_test.png`)

MAE du modèle complet à météo parfaite, puis retrait d'un groupe de variables :

| Modèle | Val | Test | Hausse de MAE (val / test) |
|---|---|---|---|
| Complet, météo parfaite | 867 | 875 | - |
| Sans météo (= `cal_lags`) | 1348 | 1323 | +481 / +448 |
| Sans calendrier | 1723 | 1696 | +856 / +821 |
| Sans retards | 1578 | 1544 | +711 / +669 |

Modèles utilisables : calendrier seul 2853 / 2653 ; retards seuls 2177 / 2200 ; `cal_lags` sans la conso de 13h de J (`cal_lags_no13`) 1499 / 1476 contre 1348 / 1323 avec.
- Ordre d'importance **identique** sur val et test : calendrier > retards > météo (météo parfaite).
- L'information de 13h le jour J compte (+151 MW val, +154 MW test) : hypothèse de disponibilité à signaler (voir `outputs/information_availability.md`).
- La température opérationnelle (J et J-1) n'apporte presque rien par rapport à la météo parfaite de J+1 : l'essentiel du gain potentiel vient d'une prévision météo, non disponible ici.

## 4. Stabilité du classement (`rank_by_metric_*.csv`, `rank_by_quarter_*.csv`)

- Ordre global identique sur val et test : {`cal_lags`, `cal_lags_tempJ`} > `arima_v2` > benchmarks. Entre les deux premiers, l'ordre dépend de la métrique (MAE : `cal_lags` 1er au test, `cal_lags_tempJ` 1er à la validation ; RMSE : `cal_lags_tempJ` 1er sur les deux).
- Par trimestre (test) : `cal_lags_tempJ` 1er aux trimestres 1 et 4, `cal_lags` 1er aux trimestres 2 et 3, `arima_v2` toujours 3e parmi les modèles actuels. Proche de la validation (`cal_lags_tempJ` 1er aux trimestres 1, 2 et 4, `cal_lags` 1er au trimestre 3) : seul le trimestre 2 change de leader, l'écart entre les deux étant faible.
- L'ordre entre les benchmarks B1, B2 et B3 varie selon la métrique et la période : sans importance pour la conclusion.
- Figures : `outputs/figures/mae_by_month_*.png` (stabilité mois par mois), `mae_by_hour_*.png` (par heure).

## 5. Performance par segment (`errors_by_segment_*.csv`, figure `segments_val.png` / `segments_test.png`)

MAE test (MW) pour les deux modèles linéaires :

| Segment | n jours | `cal_lags` | `cal_lags_tempJ` |
|---|---|---|---|
| Hiver (DJF) | 90 | 2064 | **1960** |
| Été (JJA) | 92 | **857** | 1042 |
| Jours froids (< 5 °C) | 32 | 2004 | **1888** |
| Jours chauds (> 20 °C) | 63 | **952** | 1128 |
| Jours fériés | 11 | 1637 | 1566 (`arima_v2` : 1505) |
| Samedi / Dimanche | 51 / 52 | 1461 / 1206 | 1381 / 1317 |

- La température opérationnelle aide en hiver et par temps froid (val et test) et dégrade l'été et les jours chauds (val et test) : schéma stable.
- Pour les trois modèles opérationnels (`cal_lags`, `cal_lags_tempJ`, `arima_v2`), l'erreur hivernale est environ 1,9 à 2,4 fois celle de l'été.
- Jours fériés : seulement 11 jours, résultats peu fiables.
- Les benchmarks B2 et B3 s'effondrent par temps froid (MAE 7600 à 8200 MW).

## 6. Limites à signaler dans le rapport

- Biais moyen des modèles linéaires en validation : +366 / +405 MW (sur-prévision), concentré en février (+1324), octobre et décembre (`outputs/bias_by_month_val.csv`, figure `bias_by_month_val.png`). Le biais du test est dans `bias_by_month_test.csv` : non commenté ici.
- Hypothèse de données définitives à la place des valeurs provisoires RTE ; pas de météo prévue pour J+1 (borne « météo parfaite » non opérationnelle).
- Un seul jeu de test d'un an : les conclusions sur les petits écarts (< 50 MW) ne sont pas statistiquement établies.

## 7. Figures disponibles (à vérifier visuellement avant de les insérer)

`protocol_timeline.png` (découpage et information à 14h) ; `model_comparison_{val,test}.png` ; `ablation_{val,test}.png` ; `segments_{val,test}.png` ; `typical_weeks_{val,test}.png` ; `failure_days_chosen_{val,test}.png` ; `mae_by_hour_{val,test}.png` ; `mae_by_month_{val,test}.png` ; `bias_by_month_{val,test}.png` ; figures d'EDA, `acf_pacf_train.png`, `residuals_train*.png`, `forecast_errors_val.png`. Tous dans `outputs/figures/`.
