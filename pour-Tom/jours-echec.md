# Analyse de trois jours d'échec (validation 2024)

Modèle de référence : `cal_lags` (linéaire, calendrier + retards). Erreur = prévision - observé, en MW, moyenne sur les 24 heures du jour cible. MAE de `cal_lags` sur toute la validation : 1348 MW (366 jours). Source des chiffres : `outputs/failure_days_val.csv` (script 09) et README, section « Failure days ».

**Légende des statuts**
- **[DONNÉES]** : lu directement dans `failure_days_val.csv` ou déduit d'un calcul de calendrier.
- **[EXTERNE]** : événement météo ou calendaire vérifié sur une source extérieure, d'après le README. Je ne l'ai pas revérifié ici : à citer avec sa source (Météo-France, RTE) dans le rapport.
- **[HYPOTHÈSE]** : explication plausible, non testée.

## Résumé

| Date | Erreur `cal_lags` | Avec météo parfaite | Meilleur modèle ce jour-là | Classe |
|---|---|---|---|---|
| Dim. 2024-11-24 | +9081 (x6,7 la MAE moyenne) | 1937 | B2 : 1624 | rupture de régime / limite d'information |
| Lun. 2024-01-08 | -5026 (x3,7) | 2305 | `cal_lags_tempJ` : 4870 | rupture de régime + limite du modèle |
| Mar. 2024-12-24 | +5373 (x4,0) | 4786 | B1 : 2493 | limite du modèle (événement de calendrier rare) |

Dans les trois cas, l'erreur moyenne est égale à l'erreur absolue moyenne (9081, 5026 et 5373 MW) : **[DONNÉES]** l'erreur a le même signe sur les 24 heures. Il s'agit d'un décalage de niveau de toute la journée, pas d'une erreur de forme de la courbe journalière.

Figure pour les trois jours : `outputs/figures/failure_days_chosen_val.png` (observé en noir, `cal_lags`, `cal_lags_tempJ`, `arima_v2`, B1 et météo parfaite en pointillés). Je n'ai pas vu l'image : vérifier que les trois titres de panneau sont bien ces trois dates.

---

## 1. Dimanche 24 novembre 2024 : sur-prévision de +9081 MW

**Ce qui s'est passé.** Journée douce (13,5 °C en moyenne, +7,3 °C de variation) après le coup de froid neigeux des 21-22 novembre.
- **[EXTERNE]** réchauffement d'environ 15 degrés en 72 h (21 → 24 nov.), puis air très doux (tempêtes Caetano puis Bert).
- **[DONNÉES]** les modèles prévoient un niveau de consommation de temps froid, observé trop bas de 9 GW en moyenne.

**Classe : rupture de régime / limite d'information.**

**Preuves**
- **[DONNÉES]** avec la météo parfaite de J+1, l'erreur tombe à 1937 MW (-79 %) : l'essentiel vient de la météo du jour cible, inconnue à 14 h.
- **[DONNÉES]** tous les modèles opérationnels sont au même niveau : `cal_lags_tempJ` 9126, `arima_v1` 9098, `arima_v2` 9175. La température du matin de J et de la veille ne contient pas le réchauffement.
- **[DONNÉES]** B1 (veille) fait 13033 MW : copier la veille froide est pire. B2 (dimanche précédent) fait 1624 MW, le meilleur résultat de la journée.

**Hypothèses**
- **[HYPOTHÈSE]** les retards (`lag_d`, `lag_mean2`) viennent de la veille froide (samedi 23) et entraînent la prévision vers le haut. Cohérent avec l'erreur de B1, non testé séparément.
- **[HYPOTHÈSE]** le réchauffement n'est pas encore visible dans les observations disponibles à 14 h le samedi (observations jusqu'à 09:00 UTC). Il faudrait regarder les valeurs de `op_t_last` et `op_t_morn` ce jour-là pour le vérifier.

---

## 2. Lundi 8 janvier 2024 : sous-prévision de -5026 MW

**Ce qui s'est passé.** Premier lundi ouvré après les vacances de Noël, au début de la vague de froid de janvier (1,7 °C, -2,7 °C par rapport à la veille).
- **[DONNÉES]** jour sans férié, sans veille de férié, `vac = 0` : le calendrier ne signale rien de spécial.
- **[EXTERNE]** températures négatives à partir du 8 janvier et pic de consommation de 83,5 GW le 10 janvier.

**Classe : rupture de régime (froid) + limite du modèle (calendrier).**

**Preuves**
- **[DONNÉES]** la météo parfaite réduit l'erreur de 54 % (5026 → 2305 MW), donc la météo compte, mais 2305 MW reste 2,7 fois l'erreur moyenne du même modèle (867 MW) : une partie de l'erreur n'est pas météorologique.
- **[DONNÉES]** B2 (lundi précédent) : 20750 MW ; B3 (moyenne de 4 lundis) : 16285 MW. Calcul de calendrier **[DONNÉES]** : le lundi 1er janvier 2024 et le lundi 25 décembre 2023 étaient fériés, donc B2 copie un jour férié et B3 en moyenne deux sur quatre.
- **[DONNÉES]** `arima_v1` (8819) et `arima_v2` (8178) sont bien plus mauvais que les modèles linéaires (~5000 MW) ; B1 fait 13593 MW.

**Hypothèses**
- **[HYPOTHÈSE]** le retard hebdomadaire `lag_w` (lundi 1er janvier, férié) tire la prévision vers le bas. Le README parle de « probablement ».
- **[HYPOTHÈSE]** les ARIMA, qui utilisent une différenciation hebdomadaire pour les heures 6 à 21 (`D = 1`), reproduisent le niveau du lundi férié, d'où leur sur-erreur par rapport aux modèles linéaires. Même mécanisme que B2, non testé.
- **[HYPOTHÈSE]** les retards du dimanche 7 et du samedi 6 (dernier jour de vacances) sous-estiment la reprise d'activité du lundi.

---

## 3. Mardi 24 décembre 2024 : sur-prévision de +5373 MW

**Ce qui s'est passé.** Veille de Noël en semaine, pendant les vacances scolaires (`eve = 1`, `vac = 1`, 7,3 °C, +1,1 °C de variation). La consommation observée est bien plus basse que ce que prévoit un mardi ordinaire.

**Classe : limite du modèle / événement de calendrier rare.**

**Preuves**
- **[DONNÉES]** la météo parfaite n'aide presque pas : 4786 MW contre 5373 (-11 %). Ce n'est pas un problème de météo.
- **[DONNÉES]** tous les modèles opérationnels se trompent de 5400 à 6500 MW (`cal_lags_tempJ` 5678, `arima_v1` 5747, `arima_v2` 6076, B2 6453), sauf B1 (2493 MW) et B3 (4247). B1 recopie les jours de la semaine de Noël (lundi 23 et dimanche 22) : le niveau « jours de fête » vient des retards immédiats, pas du calendrier appris.
- **[DONNÉES]** calcul de calendrier : le 24 décembre était un samedi en 2022 et un dimanche en 2023. Un 24 décembre en semaine n'apparaît jamais dans les années d'apprentissage.
- **[DONNÉES]** le bug de calendrier (vacances scolaires mal détectées) a été corrigé et ne change pas l'erreur de ce jour (5364 → 5373 MW), il n'en est donc pas la cause.

**Hypothèses**
- **[HYPOTHÈSE]** le calendrier du modèle est additif (jour de la semaine + férié + veille + vacances) : il ne peut pas représenter la combinaison « mardi + veille de Noël », jamais vue à l'apprentissage. Le raisonnement est vérifié par le calcul de calendrier ci-dessus, mais l'effet lui-même n'a pas été testé.
- **[HYPOTHÈSE]** la variable « veille de férié » moyenne des veilles très différentes (veille de week-end, veille de Noël).

---

## À retenir pour le rapport

- **Deux causes distinctes** : l'information manquante (météo de J+1, jours 1 et 2) et la structure du modèle (calendrier additif et retards hebdomadaires, jours 2 et 3). Ce ne sont pas des erreurs de données.
- **Utilisation du système : à éviter ou à surveiller** lors des changements brusques de température, au retour de vacances, et à la veille ou au lendemain de fêtes rares dans la semaine.
- **Pistes, non implémentées ni testées (aucune nouvelle version de modèle avant le test, par protocole)** : prévision météo de J+1 archivée à 14 h ; indicateurs spécifiques pour la période de Noël ; retard hebdomadaire ignorant les jours fériés.
- **Contrôle possible sans rien relancer** : le 24 décembre 2025 est un mercredi et se trouve dans l'année de test. Si besoin, regarder l'erreur de ce jour dans les prévisions test (`failure_days_test.csv` ou les `.rds`) pour voir si l'effet « Noël en semaine » se répète. C'est une lecture de résultats existants, sans ajustement.

## Limites de cette analyse

- Trois jours sur 366, choisis parmi les dix plus grosses erreurs pour couvrir trois classes : ils illustrent des mécanismes, ils ne mesurent pas leur fréquence. Le script 09 classe 9 des 10 plus grosses erreurs comme dominées par la météo.
- Les événements externes (tempêtes, vague de froid) viennent du README et sont à sourcer.
- Les hypothèses n'ont pas été testées par des modèles supplémentaires.
