# Vigor — coach santé & entraînement perso (iPhone)

Version **1.0**. App iOS personnelle façon Bevel : elle réunit sommeil, récupération, sport, musculation et nutrition,
puis **croise les données** pour te dire quoi faire : augmenter ou baisser les charges, allonger les sorties,
lever le pied, adapter le plan quand tu es malade, blessé ou en déplacement.

L'objectif (nom et date de la course, FTP, morphologie) se règle dans *Réglages → Profil et objectif* :
aucune valeur personnelle n'est pré-remplie (FTP 0 = inconnue, aucun TSS calculé depuis la puissance tant qu'elle n'est pas saisie).

## Organisation

| Onglet | Contenu |
|---|---|
| **Aujourd'hui** | Trois anneaux (Effort, Récupération, Sommeil), coaching du jour (verdict, séance adaptée, 3 priorités), « À faire aujourd'hui », configuration guidée. Chaque carte s'ouvre sur un écran détaillé (courbes 30 j / 90 j / 1 an, zone normale, explication du calcul, sources) |
| **Santé** | Moniteur (respiration, FC repos, VFC, sommeil, poids, VO2max vs ta normale), sommeil, blessures et symptômes, analyses |
| **Sport** | Semaine / mois, musculation (programmes, séance en direct, progression), vélo, saison, charge et hors-sport |
| **Nutrition** | Journal par repas, scan de code-barres (Open Food Facts), table Ciqual, objectifs calories / macros du jour |
| **+** | Saisies rapides (repas, pesée, séance, effort ressenti, symptôme, blessure, hors sport, imprévu) |

Réglages en 4 groupes : Profil et objectif, Connexions, Notifications, Données. Pas de gamification, de badges ni de classement.

## Sources de données

- **Apple Santé** : nuits (nuit principale seulement, voir plus bas), VFC (SDNN), FC de repos, respiration, pas, énergie active, poids, VO2max, séances. Aucune donnée nutritionnelle n'est lue dans Santé (le journal est tenu dans l'app).
- **Garmin via Intervals.icu** (gratuit) : séances complètes (TSS, puissance normalisée, IF, zones), VFC nocturne (rMSSD), durée et score de sommeil, readiness Garmin, FC de repos, SpO2, respiration, VO2max, poids, calendrier des séances prévues.
- Les valeurs Garmin sont stockées **à part** (`sleepHoursGarmin`, `restingHeartRateGarmin`, `respirationGarmin`) : elles n'écrasent jamais les valeurs Apple. Le coach choisit **une source par métrique sur tout l'historique** :
  - VFC, FC de repos, respiration : Garmin s'il y a au moins 14 valeurs Garmin sur 60 jours, sinon Apple Santé (source affichée) ;
  - durée de sommeil : nuit Apple Santé quand elle existe (cohérente avec coucher, réveil et stades), sinon durée Garmin.
- **Nuits** : les échantillons sont regroupés en sessions (plus de 90 min entre deux échantillons = nouvelle session) ; pour chaque jour on garde la session la plus longue qui se termine entre 3 h et 14 h (à défaut la plus longue). Les **siestes** sont exclues de la durée, du coucher, du réveil et des stades.

### Connecter Garmin (Intervals.icu)
1. Crée un compte sur [intervals.icu](https://intervals.icu) et relie Garmin Connect (*Settings → Connections*).
2. *Settings → Developer Settings* : copie l'**Athlete ID** et génère une **API Key**.
3. Dans Vigor : *Réglages → Connexions → Garmin via Intervals.icu* → colle les deux → *Enregistrer la clé* → *Tout synchroniser*.

## Synchronisation

- À l'ouverture et au retour dans l'app, **l'une après l'autre** (jamais en parallèle) : sommeil du jour s'il n'a pas encore été lu, réparation unique de l'historique après une mise à jour, puis synchro complète si la dernière date de plus d'une heure.
- `SyncService` (`Vigor/Services/Sync/`) : lit la nuit dans Apple Santé (simulateur compris), sinon via Intervals.icu ; une seule synchro réussie par jour ; état observable `isSyncing` / `syncError` / `lastSyncDate`. Les sources factices ne servent qu'aux aperçus SwiftUI et aux tests.
- Arrière-plan : iOS est sollicité pour réveiller l'app 1 h avant le bilan du matin (le jour même si l'heure n'est pas passée, sinon le lendemain).
- Raccourcis : action **« Synchroniser les données du matin »**. Automatisation conseillée : Raccourcis → Automatisation → **Mode Sommeil → Lorsqu'il se désactive** → action Vigor → **Exécuter immédiatement**. Aussi : « Plan du jour » et « Noter l'effort ».

## Notifications

- **Matin** : verdict, séance adaptée, priorité n° 1. Programmé pour aujourd'hui si l'heure n'est pas encore passée, sinon annonce du lendemain (remplacée par le vrai bilan si l'app est réveillée en arrière-plan).
- **Repas** (optionnels) et **soir** (optionnel) : programmés sur les 3 prochains jours, pour ne pas s'arrêter si l'app n'est pas rouverte.
- **Revue du dimanche** à 19 h (suit l'interrupteur du bilan du matin).
- **Alertes de seuil** : surcharge, fatigue très élevée, dette de sommeil, symptôme récurrent, maladie probable (une fois par jour au plus).
Réglables dans *Réglages → Notifications*. Pas de pastille sur l'icône.

## Méthodes et formules (versionnées, affichées dans Réglages et dans l'export)

- **Récupération (readiness-3)** : VFC 50 % (nuit 70 % + moyenne 7 j 30 %, en ln, médiane / MAD 60 j), FC de repos 25 %, sommeil 25 % (score de sommeil). Zones : ≥ 67 prêt, 34–66 moyen, < 34 bas ; une journée « dans ta normale » ≈ 60. Fatigue d'entraînement (forme < −25) : malus de 10 ou 20 points, affiché comme tel.
- **Charge (load-3)** : TSS (puissance si FTP connue, sinon FC, sinon RPE, sinon durée), sRPE = RPE × minutes ; CTL/ATL/forme (Banister, 42 j / 7 j) et ACWR en moyennes exponentielles 7 / 28 j, **amorcées par la moyenne des premiers jours** (pas de départ à 0) ; ACWR global et par discipline seulement à partir de 21 jours d'historique ; seuil d'alerte ACWR **> 1,5** partout ; monotonie de Foster.
- **Effort (effort-1)** : 0–21 logarithmique (séances + muscu + hors sport + pas > 12 000).
- **Sommeil (sleep-4)** : nuit principale (siestes exclues) ; score = durée vs besoin (−25 points par 10 % manquants), efficacité, stades, régularité du coucher ; besoin = base + effort + part de la dette ; **dette sur 14 nuits pondérées** (× 0,85 par jour d'ancienneté).
- **Décision (decision-3)** : capacité du jour = somme des facteurs. Récupération : ≥ 67 → +5 %, 45–66 → neutre, moyenne < 45 → −15 %, basse → −40 %. Puis règles hiérarchisées (2 signaux rouges → adapter, 3 ou douleur → repos), nuit < 6 h ou fatigue extrême → pas d'intensité.
- **Corrélations (corr-2)** : Spearman, décalages J / J+1 / J+2, IC 95 %.
- **Nutrition** : Mifflin-St Jeor, glucides selon le volume (Burke 2011), protéines 1,8 g/kg, dépense réelle mesurée (apports − variation du poids lissé × 7 700 kcal/kg) dès 3 semaines de données ; vitesse de prise de poids : idéal 0,25–0,5 %/semaine, alerte au-delà de 0,5 %.
- **Analyse critique** (`Coach/InsightEngine.swift`, `AdvancedInsights.swift`) : surmenage (VFC ↓ + FC repos ↑), dette et irrégularité du sommeil, progression de charge, ACWR, monotonie, répartition 80/20, volume par muscle, stagnation, interférence Legs → vélo, protéines, glucides des jours longs, zones de FC, dérive cardiaque, chaussures, symptômes récurrents, qualité des données (VFC manquante, mesure aberrante, FTP probablement sous-estimée sur les 60 derniers jours).
- `Science.swift` : toutes les références citées dans l'app.

L'hydratation n'est plus suivie par le coach (pas d'alerte).

## Musculation intégrée

Banque d'exercices en français (filtres, exercices perso), séances types personnelles, séance en direct (charges proposées, colonne « Précédent », échauffements, minuteur de repos avec notification, records), historique par mois. L'import Hevy reste disponible pour récupérer l'ancien historique.

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
Puis Vigor → Sport → Progression → **Récupérer mon historique Hevy**. Tu peux réimporter l'export complet chaque semaine : rien n'est dupliqué.

## Non inclus

- Widgets écran verrouillé, complication Apple Watch, Dynamic Island (extension prête mais désactivée : compte développeur payant ou place d'app supplémentaire nécessaire).
- Body Battery et puissance seconde par seconde Garmin (non lus).
- Lecture de la nutrition depuis Apple Santé.

⚠️ Les conseils de l'app ne remplacent pas un avis médical, en particulier en cas de blessure.
