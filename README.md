# Vigor — coach santé & entraînement perso (iPhone)

App iOS personnelle façon Bevel : elle réunit sommeil, récupération, sport, musculation et (bientôt) nutrition,
puis **croise les données** pour te dire quoi faire : augmenter ou baisser les charges, allonger les sorties,
lever le pied, adapter le plan quand tu es malade, blessé ou en déplacement.

Objectif actuel : **The Traka 100 (fin avril 2027)** + prise de masse (PPL 3×/semaine) + VO2max.

## Ce que fait la version 0.2

| Onglet | Contenu |
|---|---|
| **Aujourd'hui** | Score de récupération + conseil du jour (croisé avec la séance prévue), **analyse du coach**, sommeil, VFC, FC repos, pas, poids, VO2max, nutrition du jour, charge, semaine en cours. **Chaque carte s'ouvre** sur un écran détaillé : courbes 30 j / 90 j / 1 an, ta zone normale, tendance, explication du calcul et sources scientifiques |
| **Entraînement** | Import Hevy (CSV complet), volume par muscle, prochaines charges conseillées, courbes de charge, sorties |
| **Plan** | Plan vélo jusqu'à la Traka (reprise → foncier → développement → spécifique → affûtage), indisponibilités et blessures, recalcul automatique |
| **Nutrition** | Journal par repas, **scan de code-barres** (Open Food Facts), recherche, aliments de référence, création manuelle, objectifs calories / protéines / glucides / lipides calculés chaque jour |
| **Réglages** | Profil, seuils, morphologie, **connexion Garmin via Intervals.icu**, synchronisation, mode démo |

Mode clair / sombre automatique (suit le réglage de l'iPhone).


## Couverture fonctionnelle (checklist « app de suivi santé & sport »)

| Domaine | Dans Vigor |
|---|---|
| Décision quotidienne | Carte « Plan du jour » en tête d'accueil : jauge d'énergie, verdict go / ajuster / repos, séance adaptée, 3 priorités |
| Charge & fatigue | Ratio 7 j / 28 j global **et par discipline** (vélo, course, muscu, hors sport) · volume hebdo (heures, km, tonnage) avec alerte > 10 % · **charge hors sport** (travaux, journées debout, pas > 12 000) · **RPE** après chaque séance (corrige la charge et détecte la fatigue) |
| Récupération | VFC 7 j vs base 60 j · FC repos vs normale · sommeil : durée, dette, **régularité du coucher** · score détaillé |
| Endurance | **Temps par zone de FC**, % Z1–Z2, **dérive cardiaque**, cadence, dénivelé, puissance, allure ajustée (GAP estimée) · **chaussures** (km, alerte 600 km) et **terrain** |
| Musculation | Charges, reps, RIR, 1RM estimé, **records**, stagnation, volume par muscle, tonnage, lien Legs → vélo |
| Nutrition & poids | Calories / macros, glucides autour des séances, **hydratation**, **poids en moyenne mobile 7 j croisé avec les apports** et la dépense mesurée |
| Journal de symptômes | Saisie rapide (zone, côté, type, intensité, minute d'apparition, sport, chaussures, terrain, fatigue) · analyse : chaussure, terrain, fatigue, sommeil, évolution · alerte si récurrent |
| Objectifs & plan | **Plusieurs échéances** (A / B / C) · forme attendue vs réelle · **prévu vs réalisé** de la semaine (séances manquées) · **jalons** de fin de phase |
| Tendances & croisements | Onglet Suivi : courbes 30 j / 90 j / 1 an avec moyennes mobiles · corrélations sommeil ↔ VFC, charge ↔ VFC, hors sport ↔ VFC, sommeil ↔ RPE, glucides / protéines / calories ↔ récupération |
| Technique | Sync auto à l'ouverture (> 1 h) et en arrière-plan · saisie rapide en 1 geste · données 100 % locales · alertes limitées aux seuils critiques (1 fois/jour max) |

Pas de gamification, de badges ni de classement.

### Scores quotidiens (inspirés de Whoop / Bevel)
- **Effort 0–21** (logarithmique) : séances + muscu + hors sport + pas · 1 h facile ≈ 9, 1 h au seuil ≈ 14, 3 h de sortie longue ≈ 18 · **cible du jour** selon la récupération (14–18 / 10–14 / 4–9).
- **Besoin de sommeil** recalculé chaque jour : base + 4 min par point d'effort au-delà de 10 + ¼ de la dette (max 1 h) · **heure de coucher conseillée** selon ton réveil habituel et ton efficacité de sommeil · **performance de sommeil** (sommeil / besoin).
- **Fréquence respiratoire nocturne** : + 1 resp/min au-dessus de ta normale (30 j) = signal précoce de maladie, renforcé si la FC de repos monte aussi → intensité supprimée + alerte.
- **Bilan hebdomadaire** (7 derniers jours vs précédents) : récup, effort, sommeil, performance, volume, calories, faits marquants · notification le dimanche à 19 h.

### Le coach du jour (`Coach/DailyCoach.swift`)
Chaque matin, Vigor part de ta séance prévue (plan Traka réparti en semaine type PPL + vélo, ou calendrier Intervals.icu)
et estime ta **capacité du jour** en croisant :
- **Santé** : score de récupération, nuit dernière, dette de sommeil sur 7 jours ;
- **Entraînement** : fatigue accumulée, pic de charge, séance Legs de moins de 30 h, blessures ;
- **Nutrition** : déficit calorique, glucides et protéines de la veille.

Il en déduit un verdict (performer / feu vert / ajuster / lever le pied / repos), **adapte chaque séance** (type, durée,
watts cibles calculés sur ta FTP, séries et RPE en muscu), te donne la nutrition autour de la séance et tes 3 priorités.
Une nuit de moins de 6 h ou une fatigue extrême suppriment l'intensité quel que soit le score.

### Notifications
- **Matin** : verdict, séance adaptée, priorité n° 1 (iOS réveille l'app pour synchroniser Intervals.icu avant).
- **Soir** : protéines / calories manquantes, préparation de la séance du lendemain (glucides, heure de coucher).
Réglables dans *Réglages → Notifications*.

### Le « cerveau » (dossier `Vigor/Coach`)
- `InsightEngine.swift` : **analyse critique** de tes données, règle par règle, chacune justifiée par une publication :
  surmenage (VFC ↓ + FC repos ↑, Plews 2013 / Buchheit 2014), dette et irrégularité du sommeil, progression de charge trop rapide
  et ratio aigu/chronique (Gabbett 2016), monotonie (Foster 1998), répartition 80/20 (Seiler 2010), volume par muscle
  (Schoenfeld 2017), stagnation, jambes trop proches du vélo intense (Wilson 2012), protéines (Morton 2018), glucides des jours longs
  (Burke 2011), vitesse de prise de masse (Iraki 2019), qualité des données (VFC manquante, mesure aberrante, FTP sous-estimée…).
- `NutritionPlanner.swift` : métabolisme de base (Mifflin-St Jeor), objectifs du jour selon l'entraînement et la phase,
  puis **dépense énergétique réelle mesurée** (apports − variation de poids lissé × 7 700 kcal/kg) dès 3 semaines de données.
- `Readiness.swift`, `TrainingLoad.swift`, `StrengthProgression.swift`, `MuscleMap.swift`, `SeasonPlanner.swift` : voir version 0.1.
- `Science.swift` : toutes les références citées dans l'app.

### Connecter Garmin (Intervals.icu, gratuit)
1. Crée un compte sur [intervals.icu](https://intervals.icu) et relie Garmin Connect (*Settings → Connections*).
2. *Settings → Developer Settings* : copie l'**Athlete ID** et génère une **API Key**.
3. Dans Vigor : *Réglages → Garmin via Intervals.icu* → colle les deux → *Enregistrer la clé* → *Tout synchroniser*.

Tu récupères : séances complètes (TSS, puissance normalisée, IF), VFC nocturne (rMSSD), score de sommeil, readiness Garmin,
FC de repos, SpO2, respiration, VO2max, poids, et le calendrier des séances prévues.

## Design (v0.7, style Bevel)

- Fond gris très clair, cartes blanches très arrondies avec ombre douce ; mode sombre automatique (cartes gris foncé sur fond noir).
- Accueil : trois anneaux à dégradé (Effort, Récupération, Sommeil) et le « Coaching » du jour dessous ; « Moniteur de santé » en grille (respiration, FC repos, VFC, sommeil, poids, VO2max), avec une mini-jauge verticale et un statut Normal / Supérieur / Inférieur par rapport à ta médiane sur 30 jours ; énergie du jour ; aliments du jour (anneau des calories et grilles de points pour les macros).
- Activité : calendrier de la semaine, effort du jour, fraîcheur musculaire par muscle (fatigue qui s'efface en 48 à 72 h, sorties vélo et course comptées pour les jambes). Le Plan s'ouvre avec le bouton calendrier.
- Barre d'onglets flottante (Accueil, Santé, Activité, Nutrition) et bouton « + » rond, classé par thème :
  - Nutrition : repas, eau, pesée ;
  - Entraînement : séance de muscu en direct (façon Hevy : exercices, séries kg × reps, échauffement, charges proposées par le coach, valeurs de la séance précédente, minuteur de repos avec notification, brouillon sauvegardé), séance d'endurance manuelle (avec alerte doublon), effort ressenti, import Hevy CSV ;
  - Corps et santé : symptôme, blessure ;
  - Quotidien : activité hors sport, imprévu.

## Musculation intégrée (v0.9, plus besoin de Hevy)

- **Banque d'exercices** : ~70 exercices en français (filtres par groupe musculaire et matériel, recherche par nom ou muscle), exercices perso avec leurs muscles, fiche par exercice (historique, records, 1RM estimé).
- **Programmes et séances types** : programme PPL prêt à l'emploi en un tap, ou tes propres séances (exercices, séries, plage de répétitions, repos, notes, réordonnables).
- **Séance en direct** : lancée depuis une séance type ou en libre ; charges proposées d'après la dernière séance, colonne « Précédent », échauffements, records détectés à la fin.
- **Repos** : compte à rebours dans l'app (±15 s) et notification à la fin du repos avec la prochaine série. La Dynamic Island est prête mais désactivée (voir `Extras/VigorWidgets`) : l'extension prendrait une 4e place d'app sur le compte gratuit.
- **Historique** par mois (exercices, séries, tonnage, durée).
- L'import Hevy reste disponible une fois, pour récupérer l'ancien historique.

## Synchro du sommeil au réveil (SyncService + Raccourcis)

- `SyncService` (`Vigor/Services/Sync/`) : `syncSleepData(force:allowPrompt:)` lit la nuit dans Apple Santé (`sleepAnalysis`), sinon via l'API Intervals.icu ; une seule synchro réussie par jour (date en cache dans UserDefaults) ; état observable `isSyncing` / `syncError` / `lastSyncDate`. Sources, cache et stockage derrière des protocoles (mock pour le simulateur, les aperçus et les tests).
- Au premier plan : synchro à l'ouverture et au retour dans l'app si rien n'a réussi aujourd'hui ; indicateur discret en haut de l'accueil ; tirer pour forcer.
- Raccourcis : action **« Synchroniser les données du matin »**. Automatisation conseillée : Raccourcis → Automatisation → **Mode Sommeil → Lorsqu'il se désactive** → action Vigor « Synchroniser les données du matin » → **Exécuter immédiatement**.

## Installer l'app sur ton iPhone (gratuit, sans compte développeur payant)

1. **Installe Xcode** sur ton Mac depuis l'App Store (gratuit, ~10 Go).
2. **Récupère le code** : installe [GitHub Desktop](https://desktop.github.com), connecte ton compte GitHub,
   *File → Clone repository* → `TEST1`, puis choisis la branche `claude/health-app-ios-integration-wes09g`.
3. **Ouvre** `Vigor.xcodeproj` (double-clic).
4. Dans Xcode : **Xcode → Settings → Accounts → +** → ajoute ton identifiant Apple habituel.
5. Clique sur le projet **Vigor** (en haut à gauche) → cible **Vigor** → onglet **Signing & Capabilities** :
   - **Team** : choisis « *Ton nom* (Personal Team) ».
   - Si Xcode signale que l'identifiant est déjà pris, change **Bundle Identifier** (ex. `fr.tonprenom.vigor`).
6. **Sur l'iPhone** : branche-le au Mac, accepte « Faire confiance », puis active
   *Réglages → Confidentialité et sécurité → Mode développeur* (l'iPhone redémarre).
7. En haut d'Xcode, sélectionne **ton iPhone** comme destination, puis clique sur **▶︎**.
8. Première fois seulement : *Réglages → Général → VPN et gestion de l'appareil* → fais confiance à ton profil développeur.
9. Ouvre Vigor → onglet **Aujourd'hui** → bouton ⟳ en haut à droite → autorise l'accès à Apple Santé.

> ⏱ Avec un compte gratuit, l'app doit être **réinstallée tous les 7 jours** : rebranche l'iPhone et clique ▶︎
> (30 secondes, tes données sont conservées). Pour éviter ça : SideStore (gratuit) ou compte développeur (99 €/an).

### Essayer sans iPhone (simulateur)
1. Ouvre `Vigor.xcodeproj` dans Xcode.
2. En haut de la fenêtre, à la place de ton iPhone, choisis un simulateur (ex. **iPhone 17 Pro**).
   S'il n'y en a pas : *Xcode → Settings → Components* → télécharge la plateforme iOS.
3. Clique sur **▶︎** : un iPhone virtuel s'ouvre sur ton Mac.
4. Dans l'app : **Réglages → Démo → Charger des données de démo** pour voir tous les écrans remplis.

Pas besoin de choisir une *Team* pour le simulateur. Aperçu encore plus rapide : ouvre un fichier de vue
(ex. `TodayView.swift`) et affiche le **Canvas** (`⌥⌘↩`).

**Lancer les tests** : dans Xcode, `⌘U`.

## Importer tes séances Hevy
Hevy → Profil → ⚙️ Réglages → *Exporter et importer des données* → **Exporter les séances** → enregistre le CSV dans *Fichiers*.
Puis Vigor → Entraînement → **Importer l'export Hevy**. Tu peux réimporter l'export complet chaque semaine : rien n'est dupliqué.

## Feuille de route
- [x] **Étape 1** — Socle : design Liquid Glass, Apple Santé, import Hevy, charge d'entraînement, récupération, progression muscu, plan Traka adaptatif
- [x] **Étape 2** — Nutrition : scan code-barres (Open Food Facts), aliments sans code-barres (table Ciqual), macros au gramme, repas favoris, bilan apports / dépenses
- [x] **Étape 3** — Intervals.icu : données Garmin complètes (Body Battery, Training Readiness, score de sommeil, puissance seconde par seconde), calendrier des séances vélo
- [ ] **Étape 4** — Programmes PPL dans l'app (prévu vs réalisé), carte du corps, tests FTP / VO2max, alertes croisées (jambes lourdes la veille d'une séance vélo intense, déficit calorique en semaine chargée…)

⚠️ Les conseils de l'app ne remplacent pas un avis médical, en particulier pour la blessure aux ischios.


## Architecture et méthodes (v0.6)

**Design** : 5 onglets au pouce — Aujourd'hui (verdict → 3–4 raisons → détail au tap), Charge, Récup, Journal, Plan.
Chaque chiffre est accompagné de son écart à ta base et d'une tendance. Courbes avec bande de normalité (médiane ± MAD),
événements annotés (maladie, voyage, travaux, chaussures, blessure), trous de données visibles, explorateur jour par jour
à axe synchronisé. Chiffres à chasse fixe, Dynamic Type, états jamais codés par la seule couleur.
Notifications rares par défaut : verdict du matin, alertes de seuil, revue du dimanche (repas et soir : optionnels).

**Moteur** :
- Récupération : médiane / MAD 60 j, score z (ln VFC 7 j, FC repos), contributions affichées.
- Charge : TSS (puissance / FC / RPE), sRPE = RPE × minutes, TRIMP d'Edwards (zones), tonnage ; ACWR en moyennes exponentielles 7/28 j par discipline ; monotonie et strain de Foster ; Banister CTL/ATL/TSB.
- Sommeil : besoin dynamique, dette 14 j pondérée (× 0,85/jour), régularité (coucher, lever week-end vs semaine).
- Endurance : zones de FC, % Z2, découplage, Efficiency Factor à conditions comparables.
- Muscu : 1RM (Epley), stagnation par régression 6 semaines avec test de significativité, règle d'interférence Legs → sortie longue.
- Nutrition : tendance de poids exponentielle, dépense adaptative, alerte déficit (poids ↓ et charge ↑).
- Symptômes : délai d'apparition médian par chaussure, terrain, fatigue, sommeil, charge de la veille ; export PDF.
- Décision : capacité + règles hiérarchisées (2 signaux rouges → adapter, 3 ou douleur → repos), agenda par jour, semaine allégée automatique si fatigue accumulée ; règles déclenchées affichées.
- Statistiques : Spearman décalé J/J+1/J+2, n et IC 95 %, « indice » si < 30 points ; expériences N = 1 (avant / pendant, d de Cohen).
- Qualité : score de confiance du jour, parsing strict (« 1:23:45 », « -- », virgules), dédoublonnage multi-sources, journées physiques non déclarées.
- Technique : 100 % local (SwiftData), formules versionnées, export CSV/JSON, Raccourcis Siri (plan du jour, effort, eau),
  narration de la revue par le modèle Apple Intelligence local (il reformule, il ne calcule pas).

Non inclus (compte développeur payant nécessaire) : widgets écran verrouillé et complication Apple Watch.
