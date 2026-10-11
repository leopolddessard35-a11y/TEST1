# Audit V1 de Vigor (octobre 2026)

Relecture complète du code en 4 volets (accueil et santé, sport et muscu, nutrition et réglages, algorithmes, données et projet).
Aucune erreur de compilation certaine n'a été trouvée, mais le code n'a pas pu être compilé ici : il faut le vérifier dans Xcode.

## Lot 1 — Bloquant pour une V1 (données fausses ou perdues)

| # | Problème | Où |
|---|---|---|
| 1 | « Charger des données de démo » et « Effacer toutes les données » effacent les vraies données sans confirmation (aussi en version finale) | SettingsView, DemoData |
| 2 | Séance de muscu : un exercice sans série cochée est enregistré comme fait (séries pré-remplies), ce qui fausse le volume, les records et la fraîcheur | WorkoutLogger.save |
| 3 | Impossible de supprimer une séance muscu ou une séance d'endurance saisie à la main | TrainingView, SessionDetailViews |
| 4 | Glisser vers le bas ferme la séance en cours sans confirmation, et le repos est perdu | WorkoutLogger |
| 5 | « Démarrer » une séance type reprend en silence un ancien brouillon d'une autre séance | WorkoutLogger.onAppear |
| 6 | Les champs numériques (kg, reps, quantité, FTP) ne prennent la valeur qu'à la perte du focus : ±2,5 et « Ajouter » partent de l'ancienne valeur | WorkoutLogger, AddFoodView, Settings |
| 7 | Les siestes se mélangent à la nuit (heures dormies, heure de réveil) | HealthKitService.sleepNights |
| 8 | Sommeil, FC au repos et respiration : Garmin (Intervals.icu) et Apple Santé écrivent dans le même champ et s'écrasent l'un l'autre | DataStore |
| 9 | Charge (ACWR, CTL) sans démarrage progressif : faux « pic de charge » le premier mois | Robust.ewma, TrainingLoad |
| 10 | Une journée normale (récupération ≈ 60–66, zone « moyenne ») réduit déjà la capacité de 15 % | DailyCoach |
| 11 | Ouvrir l'app tôt le matin annule le bilan du matin du jour, et les rappels ne sont programmés qu'un jour à l'avance | NotificationScheduler |
| 12 | Synchros (réparation, auto, Raccourcis, arrière-plan) lancées en même temps sur la même base | ContentView, AppModel |
| 13 | L'import CIQUAL ignore les erreurs XML (encodage windows-1252) : un import vide ou partiel ne le signale pas | CiqualParser |
| 14 | Ouvrir les réglages Profil inscrit 1995 comme année de naissance (faux métabolisme de base) | SettingsView |

## Lot 2 — Bugs visibles

- La recherche d'aliments garde les résultats Open Food Facts d'une recherche précédente. « œuf » n'est pas trouvé quand on tape « oeuf » (pas d'équivalence œ/oe), et « riz » remonte aussi « chorizo ».
- Le scan de code-barres peut afficher « Scanner indisponible » au premier lancement : il faut demander l'accès à la caméra avant.
- Un aliment créé à la main est perdu si on annule à l'étape de la quantité, et deux feuilles s'ouvrent l'une derrière l'autre.
- « Configurer Vigor » : les étapes Objectif et FTP sont toujours cochées (valeurs par défaut), et l'étape Apple Santé est cochée même en cas d'échec.
- Le moniteur de santé affiche une mesure vieille de 3 semaines comme si elle était du jour.
- Le détail de la récupération affiche des poids fixes au lieu des poids réels (renormalisés).
- La page Effort affiche « cible atteinte » un jour de repos. La revue hebdo inverse « prévu / réalisé ».
- Santé : le texte dit « tire vers le bas » alors que l'écran n'a pas de rafraîchissement.
- Calendrier : un défilement vertical en biais change de mois. Une semaine de maladie casse la série. Identifiants en double possibles dans les listes.
- Records muscu calculés sur les 80 dernières séances seulement. L'historique d'exercices est sensible à la casse.
- Recalcul du coach manqué après un effort ressenti noté via Siri ou un changement de profil.
- Le simulateur écrit de fausses nuits dans la base.

## Lot 3 — Nettoyage (code mort)

- Accueil : HeroRing, EnergyCard, TodayNutritionCard, ReadinessCard, CoachCard, WellnessGrid, NutritionSummaryCard, MacroBar, LoadCard, ThisWeekCard, RaceCountdownCard, HydrationCard, ScoreTrio, DailyBriefCard.
- Santé : RecoveryTodaySection, ContextTile, MetricContext, TrackingView, branche « pas ».
- Sport : WeekOverviewCard, WeekStrip, LoadChartCard, ratioCaption, routineID jamais enregistré, suggestedTitle (pré-remplit Push/Pull/Legs).
- Eau : QuickEntryBar, QuickActions.addWater, calculs d'hydratation, insight hydratation, données de démo, colonne d'export.
- Annulation globale jamais appelée (AppModel.undoItem) ; Live Activity désactivée ; JournalView ; RingStat, VerticalGauge, MetricTile.
- Propriétés et fonctions inutiles : todayAdvice, sleepScoreHistory, fosterStrain, socialJetlag, advice(), Robust.z, edwardsTRIMP.

## Lot 4 — Finitions V1

- **Textes personnels codés en dur** : Traka, FTP 206, ischio, Fenix, prise de masse. Ils doivent venir du profil.
- **Textes qui contredisent le code** : 30 j au lieu de 60 j, dette sur 7 j au lieu de 14 j, sans VFC, versions des formules, README, numéros de version (0.1, 0.2 et 0.8 selon les endroits).
- **Jargon restant** : PPL, Efficiency Factor, TSS, CTL, 1RM, Spearman, « Coaching », « Score Garmin ».
- **Séparateur décimal** : « 72.5 » au lieu de « 72,5 », formats mélangés.
- **Petites zones tactiles** (menus « … », crayon, puces, « Réessayer », « Masquer ») et icônes sans libellé VoiceOver. Tailles figées qui ignorent la taille de texte.
- **Suppressions sans confirmation ni Annuler** : symptômes, activités, indisponibilités, table CIQUAL.
- **Nommage** : « Imprévu », « Je ne peux pas » et « Indisponibilité » désignent la même chose.
- **Notifications** : rien n'explique un refus, et l'autorisation est demandée au premier lancement sans contexte.
- **Nutrition** : pas d'état vide sans poids renseigné. La date ne change pas à minuit si l'app reste ouverte.
- **Apple Santé** : l'app demande des autorisations inutiles (lecture nutrition, texte d'écriture des repas).

---

## État après corrections (V1.0)

- **Lots 1 et 2** : corrigés (confirmations, séries cochées, suppression de séance, séance protégée, champs numériques, siestes, sources Garmin et Apple séparées, démarrage de la charge, coach recalé, notifications sur 3 jours, synchros en série, import CIQUAL, recherche d'aliments, scan, configuration, mesures anciennes).
- **Lot 3** : code mort retiré.
- **Lot 4** : textes personnels neutralisés, explications alignées sur les formules, virgule décimale, zones tactiles et VoiceOver, version 1.0.
- **Table CIQUAL** : la version 2025 (3 403 aliments) est intégrée à l’app ; l’import accepte le .xlsx de l’ANSES pour les mises à jour.
- **Reste à vérifier dans Xcode** : compilation, focus kg → reps dans la séance.
