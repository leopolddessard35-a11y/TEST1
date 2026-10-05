# Vigor — coach santé & entraînement perso (iPhone)

App iOS personnelle façon Bevel : elle réunit sommeil, récupération, sport, musculation et (bientôt) nutrition,
puis **croise les données** pour te dire quoi faire : augmenter ou baisser les charges, allonger les sorties,
lever le pied, adapter le plan quand tu es malade, blessé ou en déplacement.

Objectif actuel : **The Traka 100 (fin avril 2027)** + prise de masse (PPL 3×/semaine) + VO2max.

## Ce que fait la version 0.1

| Onglet | Contenu |
|---|---|
| **Aujourd'hui** | Score de récupération (VFC, FC repos, sommeil comparés à TA moyenne), condition/fatigue/forme, programme de la semaine, compte à rebours course |
| **Entraînement** | Import Hevy (CSV complet : séries, charges, reps, RPE, notes, supersets), volume par muscle sur 7 jours, **prochaines charges conseillées** par exercice, courbes de charge vélo, liste des sorties |
| **Plan** | Plan vélo semaine par semaine jusqu'à la course (reprise → foncier → développement → spécifique → affûtage), déclaration d'indisponibilités et de blessures, recalcul automatique |
| **Nutrition** | Objectif nutritionnel de la phase (le scan code-barres arrive à l'étape 2) |
| **Réglages** | FTP, FC seuil, poids, heures dispo, date de course, connexion Apple Santé |

### Le « cerveau » (dossier `Vigor/Coach`)
- `TrainingLoad.swift` : TSS par séance (puissance → FC → durée), condition (CTL 42 j), fatigue (ATL 7 j), forme (TSB).
- `Readiness.swift` : score de récupération sur 100.
- `StrengthProgression.swift` : double progression, 1RM estimé, décharge si 3 séances en baisse, blocage si récup basse ou zone blessée.
- `MuscleMap.swift` : exercice → muscles (noms Hevy anglais et français).
- `SeasonPlanner.swift` : progression de la condition limitée à +3 à +5 points/semaine, 1 semaine de récup sur 4, sortie longue +15 min/semaine (jusqu'à 4 h 30), retour progressif après maladie, adaptation aux blessures.

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
- [ ] **Étape 2** — Nutrition : scan code-barres (Open Food Facts), aliments sans code-barres (table Ciqual), macros au gramme, repas favoris, bilan apports / dépenses
- [ ] **Étape 3** — Intervals.icu : données Garmin complètes (Body Battery, Training Readiness, score de sommeil, puissance seconde par seconde), calendrier des séances vélo
- [ ] **Étape 4** — Programmes PPL dans l'app (prévu vs réalisé), carte du corps, tests FTP / VO2max, alertes croisées (jambes lourdes la veille d'une séance vélo intense, déficit calorique en semaine chargée…)

⚠️ Les conseils de l'app ne remplacent pas un avis médical, en particulier pour la blessure aux ischios.
