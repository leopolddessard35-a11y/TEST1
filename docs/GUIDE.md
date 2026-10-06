# Vigor — guide de démarrage pas à pas

Durée : ~45 min la première fois. Ensuite : 2 min par semaine.

---

## Étape 1 — Relier la montre Garmin à Apple Santé (5 min)

1. Sur l'iPhone, ouvre **Garmin Connect**.
2. **Plus** (ou ton avatar) → **Réglages** → **Applications connectées** → **Apple Santé** (ou « Santé »).
3. Active tout : activités, sommeil, fréquence cardiaque, FC au repos, pas, calories, poids, respiration.
4. iOS ouvre la fenêtre Santé : **Tout activer** → Autoriser.
5. Vérifie : Réglages iPhone → **Santé** → **Accès aux données et appareils** → **Garmin Connect** : tout doit être vert.

> La HRM 600 passe par la montre : rien à faire de plus, ses données arrivent avec tes séances.

## Étape 2 — Relier Garmin à Intervals.icu (10 min)

Apple Santé ne reçoit pas tout de Garmin (VFC nocturne, score de sommeil, puissance détaillée). Intervals.icu (gratuit) récupère tout.

1. Sur **intervals.icu**, crée un compte gratuit.
2. **Settings** → **Connections** → **Garmin Connect** → **Connect** → connecte-toi avec ton compte Garmin.
3. Coche l'import des **activités** et des **données wellness** (sommeil, VFC, FC au repos, poids).
4. Toujours dans **Settings**, tout en bas : **Developer Settings**.
   - note ton **Athlete ID** (de la forme `i123456`) ;
   - clique **Generate** à côté de **API Key** et copie la clé.
5. Attends 10 minutes : l'historique Garmin se charge dans Intervals.icu.

## Étape 3 — Home trainer (MyWhoosh / Zwift)

- **MyWhoosh** : Réglages → Connexions → **Garmin Connect**.
- **Zwift** : Réglages → Connexions → **Garmin Connect**.
- Tes séances arrivent dans Garmin, puis dans Intervals.icu et Apple Santé, donc dans Vigor.
- ⚠️ N'enregistre **pas** la même séance aussi sur la montre (sinon doublon). Vigor détecte les doublons proches, mais mieux vaut une seule source.

## Étape 4 — Installer Vigor sur l'iPhone (15 min)

Sur le Mac :
1. **GitHub Desktop** → dépôt **TEST1** → branche `claude/health-app-ios-integration-wes09g` → **Pull origin**.
2. Ouvre `Vigor.xcodeproj` dans **Xcode**.
3. Clique sur **Vigor** (en haut à gauche) → cible **Vigor** → **Signing & Capabilities** :
   - **Team** : ton nom (Personal Team) ;
   - **Bundle Identifier** : unique, ex. `fr.leopolddessard.vigor`.

Sur l'iPhone (première fois seulement) :
4. Branche l'iPhone au Mac en USB, déverrouille-le, **Faire confiance** à l'ordinateur.
5. Réglages → **Confidentialité et sécurité** → **Mode développeur** → activer → l'iPhone redémarre → confirme.

Dans Xcode :
6. En haut, choisis **iPhone de Léopold** comme destination, puis ▶︎.
7. Si l'app ne s'ouvre pas : Réglages iPhone → **Général** → **VPN et gestion de l'appareil** → ton identifiant Apple → **Faire confiance**. Relance ▶︎.

> ⚠️ Compte gratuit : 3 apps maximum signées avec ton identifiant (AltStore et Pokémon GO en prennent déjà 2).

## Étape 5 — Premier lancement de Vigor (10 min)

1. **Notifications** : Autoriser.
2. **Apple Santé** : **Tout activer** → Autoriser (sinon pas de sommeil, VFC, séances).
3. Si tu as testé « Charger des données de démo » : ⚙️ (roue en haut à gauche de l'Accueil) → **Effacer toutes les données**, pour repartir propre.
4. Dans ⚙️ **Réglages**, remplis :
   - **Objectif** : The Traka 100, date de fin avril 2027 ;
   - **Morphologie** : sexe, taille, année de naissance, poids ;
   - **Disponibilités** : heures par semaine, 3 séances de muscu, besoin de sommeil ;
   - **Seuils** : FTP 206 W (à re-tester), FC max, FC seuil (laisse 0 si inconnu) ;
   - **Garmin via Intervals.icu** : colle la **clé d'API** et l'**Athlete ID** → **Enregistrer la clé** ;
   - **Agenda** : minutes disponibles chaque jour ;
   - **Notifications** : heure du plan du matin, rappels de repas si tu les veux.
5. **Tout synchroniser** (en bas des Réglages). La première fois, un an d'historique : patiente une minute.
6. Plan → **Blessure** : déclare l'ischio gauche (course en pause, le plan s'adapte).
7. Activité → **Muscu** → **Créer mon programme PPL** (ou tes propres séances types).
8. (Facultatif) Récupérer ton historique Hevy : dans Hevy, Profil → Réglages → Exporter les séances, puis en bas de Activité → Muscu → **Récupérer mon historique Hevy**. Une seule fois.

## Étape 6 — Synchro automatique au réveil (3 min)

1. Ouvre l'app **Raccourcis** → **Automatisation** → **+**.
2. **Mode Sommeil** → **Lorsqu'il se désactive**.
3. Action : cherche **Vigor** → **Synchroniser les données du matin**.
4. Choisis **Exécuter immédiatement** → OK.

> Il faut que le mode Sommeil soit utilisé (app Santé → Sommeil → horaires). Sinon, la synchro se fait à l'ouverture de Vigor.

---

## Au quotidien

| Quand | Quoi | Temps |
|---|---|---|
| Au réveil | Ouvre Vigor : anneaux, coaching du jour, séance adaptée | 30 s |
| À chaque repas | **+** → Repas (scan, favoris, récents) | 10 s |
| Après une séance vélo | **+** → Effort ressenti | 5 s |
| En salle | Activité → Muscu → **Démarrer** une séance type | — |
| Si gêne / douleur | **+** → Symptôme | 10 s |
| Imprévu (malade, voyage, flemme) | **+** → Imprévu | 10 s |
| Le dimanche soir | Accueil → Revue de la semaine | 2 min |

## Chaque semaine (compte gratuit)

L'app expire au bout de **7 jours** (elle refuse de s'ouvrir, **les données restent**).
1. Branche l'iPhone au Mac.
2. GitHub Desktop → **Pull origin** (récupère les nouveautés). Si `project.pbxproj` bloque : clic droit → **Discard changes**, puis Pull, et remets la Team dans Xcode.
3. Xcode → ▶︎. C'est reparti pour 7 jours.

⚠️ Ne supprime **jamais** l'app de l'iPhone : ses données partiraient avec.

## Si quelque chose ne remonte pas

| Problème | Vérifie |
|---|---|
| Pas de sommeil / VFC | Garmin Connect → Applications connectées → Santé ; et la clé Intervals.icu dans Réglages Vigor |
| Pas de séances vélo | Garmin Connect synchronisé (ouvre l'app Garmin) ; Intervals.icu → Connections → Garmin |
| Pas de notifications | Réglages iPhone → Notifications → Vigor ; mode Concentration |
| « Nuit pas encore synchronisée » | Ouvre Garmin Connect pour qu'il envoie la nuit, puis tire l'Accueil vers le bas |
| Recherche d'aliment en erreur | Scanne le code-barres, ou utilise Favoris / Récents |
