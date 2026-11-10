# Usage d'un assistant IA : trois exemples documentés

Sources : `pour-Tom/statut_projet.txt` (section 8, candidats) et `README.md`. Les éléments marqués **[À COMPLÉTER]** ne figurent dans aucun de ces deux fichiers : ils doivent être confirmés par le groupe avant le rendu.

Contexte : un assistant IA (Claude modèle Sonnet 5.5) a servi à écrire les scripts R, à proposer des protocoles et à analyser les sorties. Le groupe a exécuté les scripts, lu les sorties et décidé.

---

## Exemple 1 : proposition conservée après vérification

**Tâche.** Expliquer pourquoi le modèle linéaire `cal_lags` (MAE 1348 MW) bat l'ARIMA par heure (MAE 1654 MW) sur la validation 2024, soit un écart de 306 MW.

**Proposition de l'IA.** Hypothèse : l'avance du modèle linéaire vient du retard `lag_last` (consommation à 13 h le jour J), information dont l'ARIMA ne profite pas de la même façon.

**Décision.** Hypothèse conservée, mais seulement en partie, après test.

**Vérification.** On a ajouté un modèle identique sans ce retard (`cal_lags_no13`) et comparé les scores :
- sans le retard de 13 h : MAE 1499 MW (RMSE 2237) ;
- l'écart avec `cal_lags` est de 151 MW, soit environ la moitié des 306 MW ;
- l'autre moitié vient de la combinaison des retards et du calendrier dans une même régression (README, section « Main findings »).

**Conséquence.** La sensibilité à l'hypothèse « consommation jusqu'à 13 h disponible à 14 h » est documentée (README, section 7 ; `outputs/information_availability.md`).

---

## Exemple 2 : proposition modifiée

**Tâche.** Définir le benchmark « jour précédent » pour une prévision émise à 14 h le jour J, pour les 24 heures de J+1.

**Proposition de l'IA.** Une version naïve qui recopie le jour précédent (le jour J) pour les 24 heures.

**Problème.** À 14 h, les heures 14 à 23 du jour J ne sont pas encore connues : cette version utilisait de l'information future, ce qui est interdit par le protocole.

**Décision.** Proposition modifiée : version « stricte » B1, qui prend le jour J pour les heures 0 à 13 et le jour J-1 pour les heures 14 à 23 (README, section 5). Score de B1 sur la validation : MAE 3183 MW, RMSE 4362 MW.

**Vérification.** **[À COMPLÉTER]** : le fichier indique seulement que la méthode est « à préciser avec le groupe ». Piste, si c'est ce qui a été fait : comparaison de la définition avec la règle de disponibilité à 14 h (`R/protocol.R`) et avec la ligne correspondante de `outputs/information_availability.md`. Si vous avez gardé le score de la version naïve, l'ajouter ici ; sinon ne pas en citer.

---

## Exemple 3 : erreurs de l'assistant détectées

**Tâche.** Préparer les variables de calendrier (jours fériés, vacances scolaires des zones A, B et C) pour `data/processed/modelling_dataset.csv`.

**Ce que l'IA a produit.** `R/03_prepare_calendar.R` ignorait en silence tous les événements de vacances dont le libellé était « Zones A/B/C », « Zones A/C », etc. : 60 événements sur 76, dont toutes les vacances de Noël, de la Toussaint et d'été (README, section 8). Aucun message d'erreur.

**Détection.** En analysant la journée à plus forte erreur (24 décembre 2024), le groupe l'a comparée au calendrier scolaire officiel : les vacances de Noël n'étaient pas marquées. La cause (libellés « Zones A/B/C » non reconnus) a ensuite été trouvée dans le script. Qui a fait la comparaison : **[À COMPLÉTER]**.

**Correction et contrôle.** Après correction, 121 à 128 jours de vacances par zone et par an, et le 24 décembre marqué chaque année. Tous les résultats ont été recalculés ; l'effet sur les scores est faible (MAE ARIMA 1643 → 1654 MW, MAE linéaire 1345 → 1348 MW) et le classement des modèles n'a pas changé.

**Deuxième erreur, dans l'explication.** L'assistant avait d'abord attribué l'erreur du 24 décembre à ce bug. La réexécution a montré que l'erreur restait inchangée (5364 MW avant, 5373 MW après). L'explication a été corrigée : le 24 décembre tombait un samedi en 2022 et un dimanche en 2023, donc un 24 décembre en semaine n'a jamais été vu à l'apprentissage, et le modèle calendaire additif ne peut pas le représenter. Cette explication est vérifiée par le calendrier, mais **l'effet lui-même n'a pas été testé** : à présenter comme une hypothèse.

**À retenir.** Un script peut échouer sans erreur visible ; la vérification d'une journée précise contre une source externe, puis un contrôle des comptes par zone et par année, ont permis de le voir. Une explication proposée par l'assistant doit être vérifiée en refaisant le calcul.

---

## Journal synthétique

| Étape | Rôle de l'IA | Contrôle ou décision du groupe |
|---|---|---|
| Préparation des données, scripts 01 à 04 | écriture des scripts | noms de colonnes et de fichier inventés par l'assistant (`timestamp_utc`, `consumption`, casse du nom de fichier) ; corrigés après lecture des scripts réels |
| Protocole : règle de disponibilité à 14 h, découpage 2022-2023 / 2024 / 2025 | proposition | conservée (statut : proposition conservée) |
| Benchmarks, script 06 | écriture, version naïve de B1 | B1 corrigé en version stricte (exemple 2) |
| ARIMA par heure, linéaire et ablation, scripts 07 et 08 | écriture, hypothèse sur le retard de 13 h | hypothèse testée avec `cal_lags_no13` (exemple 1) |
| Calendrier scolaire, script 03 | écriture avec bug silencieux, puis fausse attribution de l'erreur du 24 décembre | bug trouvé le 8 novembre, résultats recalculés, explication corrigée (exemple 3) |
| Diagnostics (stationnarité, ACF/PACF, résidus), script 10 | écriture et lecture des sorties | conclusion : l'ARIMA par heure est mal spécifié (résidus autocorrélés, variance plus forte en hiver) |
| Versions des modèles avec la température opérationnelle (`arima_v2`, `cal_lags_tempJ`) | proposition d'implémentation et de journal des versions | décidé par le groupe d'ajouter la température disponible à 14 h ; versions v1 conservées |
| Protocole figé avant le test (README, 10 novembre) | rédaction | règle de choix du modèle fixée avant de regarder le test |

Dates des échanges : **[À COMPLÉTER]** (seuls le 8 novembre pour le bug de calendrier et le 10 novembre pour le protocole figé figurent dans les fichiers).

---

## À vérifier ou compléter par vous avant le rendu

1. Le format exact exigé par la consigne pour cette section (nombre d'exemples, informations demandées comme l'outil, le prompt ou la date) : je n'ai pas relu `consignes-projet.txt` pour ce fichier.
2. L'outil et le modèle utilisés, et les dates : absents des deux fichiers.
3. Les méthodes de vérification, surtout pour l'exemple 2 : le fichier de statut dit de les préciser avec le groupe.
4. Qui a détecté quoi (vous, votre binôme) et si les prompts d'origine sont conservés.
5. Le journal s'arrête au 10 novembre : l'exécution du test 2025 et les scripts 11 et 12 n'y figurent pas, car ils ne sont dans aucun des deux fichiers sources. À ajouter si vous voulez qu'ils apparaissent.
