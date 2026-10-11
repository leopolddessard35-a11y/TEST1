# Audit V1, deuxième passe (octobre 2026)

Relecture complète en 4 volets : compilation, organisation de la semaine, données / synchro / nutrition, ergonomie / coach / muscu.
Le code n'a pas pu être compilé ici : tout est à vérifier dans Xcode.

Bonnes nouvelles : aucune erreur de compilation certaine dans l'app, aucun risque de perte de données, la base de données (19 tables) et la table CIQUAL intégrée (3 403 aliments) sont correctes. La plupart des corrections du premier audit tiennent.

## Lot A — Bloquant pour la V1

| # | Problème | Où |
|---|---|---|
| A1 | Les tests automatiques ne compilent plus (ancien paramètre du calendrier) | VigorTests/SyncServiceTests.swift:131, 137 |
| A2 | Un programme Push / Pull / Legs tout fait reste dans le plan : séance « Push (pecs, épaules, triceps) » avec liste d'exercices imposée, et « Démarrer » devine la séance type par son nom (ouvre une séance vide si tes séances s'appellent autrement) | DailyCoach, WeekPlanner, TodayView |
| A3 | Sans objectif renseigné, un plan de saison est quand même inventé (course dans 6 mois, phase « Reprise après blessure ») | Records (valeurs par défaut), SeasonPlanner |
| A4 | Tout le monde a un objectif nutrition « prise de masse » (+300 kcal, insights « ajoute 200 kcal ») | NutritionPlanner, InsightEngine |
| A5 | Progression muscu : ignore les répétitions visées de ta séance type (5×5 jugé « trop lourd », 90 kg proposé) et contredit la page Progression (récup et blessures non prises en compte pendant la séance) | StrengthProgression, WorkoutLogger |
| A6 | Organisation de la semaine : une marche ou n'importe quelle activité Apple Watch valide une séance vélo prévue et bloque le vélo ce jour-là | CoachSnapshot, WeekPlanner |
| A7 | Organisation de la semaine : les séances « choisies » peuvent changer de séance quand le plan se recalcule (fatigue détectée, indisponibilité, semaine suivante différente une fois arrivée) | SeasonPlanner, WeekPlanner |
| A8 | Une fois la séance du jour faite, l'accueil affiche « Jour de repos / rien de prévu » au lieu de « Séance faite : récupère » | CoachSnapshot, DailyCoach, CoachSummary |
| A9 | La course est toujours placée un dimanche, quelle que soit sa vraie date | DailyCoach.template |
| A10 | Bilan du matin envoyé jusqu'à 1 h avant l'heure choisie, avec le son | NotificationScheduler.sendMorningBrief |
| A11 | Raccourci « Synchroniser le matin » : si l'app a été ouverte après minuit, la nuit n'est pas relue au réveil (« Déjà synchronisé ») | SyncService.hasSyncedToday |
| A12 | Repas noté après minuit : compté sur le nouveau jour comme « Dîner », et le rappel du dîner du soir saute | Meal.suggested, AddFoodView |
| A13 | L'écran de quantité affiche les valeurs d'un produit mais enregistre celles d'un produit déjà connu (même nom et marque, ou valeurs mises à jour) | AddFoodView.FoodPortionView.save |

## Lot B — Bugs visibles

**Semaine et calendrier**
- Les habitudes apprises ne déplacent jamais une séance de son jour type (le bonus du jour type l'emporte toujours) : le texte « d'après tes habitudes » est faux.
- Une séance dure replacée peut se retrouver la veille d'une autre séance dure.
- Les séances Intervals.icu et l'organisateur se contredisent (accueil, calendrier et notification du soir peuvent montrer 3 séances différentes).
- Tempo et sweet spot rarement reconnus comme « intenses » (seuil IF 0,82 trop haut).
- Le plan de demain annoncé le soir peut changer le lendemain ; la règle « après 20 h » et les modifications d'indisponibilité ne rafraîchissent pas le calcul.
- Impossible de défaire une mauvaise correspondance (« ne compte pas pour cette séance »).
- Revue de la semaine : compte encore les séances non casées comme un point de vigilance, mélange semaine calendaire et 7 jours glissants, « Muscu x/3 » ignore le nombre réel prévu, point fort « tu as tenu ton entraînement » même à 0 h.
- Le modèle de semaine casse ses propres règles (jambes la veille de la sortie longue ; jambes le même jour que l'intensité à 2 séances).

**Coach et scores**
- Récupération = score de sommeil pendant les 14 premiers jours (pas de mention « calibrage »), et le sommeil compte deux fois dans la capacité du jour.
- La fatigue accumulée (« Forme ») est comptée trois fois (récup, capacité, signal rouge) et le texte de la page Charge dit l'inverse.
- Cible d'effort élevée (14–18) un jour de repos : « Encore ≈ 50 points ».
- Nutrition contradictoire : glucides « bas » sous 5 g/kg alors que l'objectif d'un jour de repos est 3,5 g/kg ; journées partiellement notées traitées comme complètes (« Déficit calorique hier »).
- L'objectif calorique du jour baisse pendant qu'on mange (la journée en cours entre dans la moyenne).
- Trois définitions différentes de la dette de sommeil ; deux calculs différents de l'écart de VFC avec le même libellé ; couleurs de l'historique de récup sur d'anciens seuils (70/45 au lieu de 67/34).
- Charge d'une séance différente entre la liste et le coach (RPE ignoré dans la liste).

**Muscu**
- Séance reprise plus tard ou oubliée : datée du début, durée 4 h, charge gonflée (faux « pic de charge »).
- Repos lancé après la toute dernière série, et repos de 150 s après une série d'échauffement.
- Double alerte de fin de repos (bannière + son dans l'app) et son joué en retard au retour dans l'app.
- Double tap sur « Enregistrer » : séance enregistrée deux fois.
- Faux records avec des séries de 20 répétitions ; décharge annoncée mais pas appliquée ; bouton « Reprendre » pas mis à jour.

**Données**
- VO2max et poids mélangent Garmin et Apple (courbe en dents de scie).
- Ajouter la clé Intervals.icu n'importe que 30 jours d'historique.
- Export : dates décalées d'un jour (UTC), données Garmin et plusieurs tables absentes, CSV illisible dans Excel français.
- Une alerte de seuil peut partir deux fois ; zones FC plus calculées du tout dans un cas de réglages.
- Recherche : « riz » trouve encore « chorizo » dans « Déjà mangés » ; « oeufs » ou « pommes » ne trouvent rien (pluriel).
- « Configurer Vigor » : Apple Santé cochée avec des données Garmin, FTP obligatoire (impossible à finir sans capteur de puissance), poids synchronisé ignoré.
- Textes d'autorisation Apple Santé : promettent la lecture et l'écriture de la nutrition, que l'app ne fait pas.

## Lot C — Finitions

- **Virgule décimale** : 56 textes affichent encore « 7.5 h », « 72.5 kg » (coach, insights, notifications, saisie du poids).
- **Jargon et vocabulaire** : TSS, TSB, 1RM, RIR, « Coaching » ; « Fraîcheur », « Forme », « Condition » pour la même chose ; je / le coach / Vigor.
- **Culpabilité** : « 3 en retard », série fixée à 3 séances par semaine, « séances manquées » (SeasonPlanner), « Pèse-toi… indispensable ».
- **Textes personnels** : gravel, « ta blessure », « prise de muscle ».
- **Chemins faux dans les textes** : « Journal → Hors sport », « onglet Muscu ».
- **Accessibilité** : bouton de validation de série sans libellé VoiceOver ; zones tactiles de 34 à 40 pt dans la séance ; largeurs figées ; gestes cachés (échauffement, suppression) ; anneaux de l'accueil non lus d'un bloc.
- **Notifications** : autorisation demandée au premier lancement sans contexte (à demander à la première série validée) ; réglage de l'heure non pris en compte tout de suite.
- **Nutrition** : pas d'« Annuler » ni de modification d'un aliment noté ; impossible de créer un aliment à 0 kcal (eau, café) ; ancienne invitation « Ajouter 3 000 aliments » inutile.
- **Organisation de la semaine** : choix enregistrés sensibles au fuseau horaire, jamais nettoyés ; « Jour choisi » et « Replacée » affichés ensemble ; temps disponible comparé séance par séance, pas sur la journée.
- **Robustesse** : base de données sans schéma versionné (un futur changement mal fait planterait au lancement) ; séances importées supprimées qui reviennent à la synchro ; code de l'eau encore calculé ; `log(0)` possible sur la VFC.

## Ordre conseillé

1. Lot A (A1 à A13).
2. Lot B : semaine et calendrier, coach et scores, muscu.
3. Lot C : virgule décimale et accessibilité de la séance d'abord.

---

## État après corrections

**Choix retenus**
- **Muscu** : le plan prévoit des séances « Musculation » sans exercices imposés ; au démarrage, tu choisis une de tes séances types (ou une séance libre).
- **Nutrition** : objectif « Prendre du poids » par défaut, réglable (perdre / maintenir / prendre), avec écart calorique, protéines et lipides ajustables, ou calories et macros fixées à la main (Réglages → Objectif nutrition, ou Nutrition → Modifier mes objectifs).
- **Sans objectif de course** : pas de plan inventé, seulement le suivi et l'analyse.

**Lot A** : corrigé (A1 à A13).
- Semaine figée le lundi (les séances ne changent plus en cours de semaine), identifiants de séance par type, cycle charge / récupération qui continue d'une semaine à l'autre.
- Course placée à sa vraie date ; seules les séances de vélo, course et muscu comptent pour le plan.
- « Séance faite » sur l'accueil une fois la séance du jour terminée.

**Lot B** : corrigé, dont :
- habitudes réellement prises en compte, séance replacée jamais collée à une autre séance dure, Intervals.icu seulement sans plan de saison ;
- « ne compte pas pour cette séance » ;
- calibrage de la récup les premiers jours, sommeil et fatigue comptés une seule fois ;
- cible d'effort en plafond les jours sans séance, nutrition de la veille jugée sur l'entraînement réel et les journées complètes ;
- durée réelle des séances de muscu (première → dernière série, modifiable) ;
- repos (dernière série, échauffement, double alerte, son en retard), double enregistrement, records ≤ 12 reps, décharge appliquée ;
- VO2max et poids d'une seule source, export complet en format français, recherche au pluriel, alertes en double, zones FC.

**Lot C** : virgule décimale partout, jargon réduit (Charge au lieu de TSS, Coach du jour), textes culpabilisants et personnels retirés, accessibilité de la séance (zones de 44 pt, libellés VoiceOver, actions), anneaux lus d'un bloc, notifications demandées au bon moment.

**Reste ouvert (non bloquant)**
- Schéma de base de données versionné.
- Règles d'enchaînement entre deux semaines.
- Temps disponible additionné sur la journée.
- Réparation des anciennes valeurs VO2max / poids Garmin déjà stockées dans les champs Apple.
- Une table CIQUAL importée reste prioritaire sur une version plus récente intégrée à l'app.
