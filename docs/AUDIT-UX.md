# Audit ergonomique de Vigor (octobre 2026)

Méthode : parcours des écrans au regard des recommandations d'Apple (Human Interface Guidelines), des heuristiques de Nielsen et de la charge cognitive (règle des 5 ± 2 éléments, une décision par écran).

## Diagnostic

Le contenu est bon. Le problème vient de l'organisation : trop de chiffres au même niveau, des doublons d'un onglet à l'autre et une navigation cachée. L'utilisateur ne sait pas où regarder en premier ni où chercher une information.

### 1. Trop de scores concurrents (gravité : forte)
L'accueil affiche 4 pourcentages ou scores au même niveau : Récupération %, Effort /21, Sommeil %, Énergie « % de ta capacité ». Il faut en plus lire 6 mesures dans le moniteur.
- « Énergie » et « Récupération » disent presque la même chose, avec deux chiffres différents.
- Ailleurs s'ajoutent Forme, Condition, Fatigue, Ratio 7 j / 28 j, Monotonie et Efficacité aérobie.

**Recommandation** : 3 scores maximum sur l'accueil. Fusionner Énergie dans la carte Récupération. Garder les indicateurs experts au 3e niveau.

### 2. Une même information à plusieurs endroits (forte)
| Information | Où elle apparaît aujourd'hui |
|---|---|
| Récupération | anneau de l'accueil, tuile Santé, page de détail |
| Effort | anneau de l'accueil, carte Activité |
| Sommeil | anneau, moniteur de l'accueil, tuile Santé, tuile « Besoin cette nuit » |
| Semaine | bande dans Activité, carte dans Plan |

**Recommandation** : un seul « domicile » par information. Ailleurs, on garde au plus un lien vers ce domicile.

### 3. Navigation cachée à deux niveaux (forte)
- Chaque onglet contient des segments : Santé en a 4, Activité en a 4. Cela fait une 2e barre d'onglets cachée, dont le contenu change sans que l'utilisateur le voie.
- Le **Plan** (Traka, semaines, blessures) n'est accessible que par une petite icône calendrier dans Activité.
- La **musculation**, utilisée 3 fois par semaine, demande 2 taps puis un défilement (Activité → Muscu).

**Recommandation** : pas de segments sur l'écran principal d'un onglet. Les tâches fréquentes doivent être à un tap.

### 4. L'accueil mélange décider, surveiller et saisir (moyenne)
L'accueil contient 6 blocs : anneaux et coaching, moniteur de santé, énergie, aliments du jour, revue de la semaine, statut de synchro. Le matin, l'utilisateur veut seulement savoir comment il va et quoi faire.

**Recommandation** : l'accueil répond à 3 questions (forme du jour, séance du jour, choses à faire aujourd'hui). La surveillance va dans Santé.

### 5. Jargon (moyenne)
VFC, ACWR (« ratio 7 j / 28 j »), monotonie, condition (CTL), forme (TSB), efficacité aérobie, effort sur 21.

**Recommandation** : des libellés en langage courant au premier niveau (« Charge de la semaine : normale »). Le terme technique reste dans la page de détail, avec son explication.

### 6. La couleur a deux sens (moyenne)
Chaque mesure a sa couleur d'identité (FC rouge, VFC verte…) et les statuts utilisent aussi du vert, de l'orange et du rouge. Une FC au repos « Normal » se retrouve affichée en rouge.

**Recommandation** : la couleur ne sert qu'au statut (vert = OK, orange = à surveiller, rouge = alerte). L'identité d'une mesure passe par son icône, en gris.

### 7. Horaires faux (forte, confiance) — corrigé
Une nuit à cheval sur minuit était coupée en deux journées. Les heures de coucher et de lever étaient donc absurdes, et le conseil de coucher aussi. C'est corrigé : un an d'historique est relu automatiquement et les heures suivent le format et le fuseau de l'iPhone.

### 8. Réglages longs, pas d'accueil guidé (moyenne)
Le formulaire de réglages fait 10 sections, et rien n'indique ce qui manque (FTP, clé Intervals.icu, programme de muscu).

**Recommandation** : une liste « Configurer Vigor » avec des coches, affichée tant qu'elle n'est pas complète. Ranger les réglages en 4 groupes : Profil, Connexions, Notifications, Données.

### 9. Accessibilité (faible à moyenne)
- La réduction automatique de texte est très utilisée : avec de grandes tailles de texte, l'information devient minuscule au lieu de passer à la ligne.
- Le texte « tertiaire » gris clair sur fond blanc manque de contraste.
- Certaines pastilles et puces font moins de 44 pt de haut, la taille minimale conseillée pour une zone tactile.

## Proposition : nouvelle organisation (rien n'est supprimé, tout est déplacé)

```
Aujourd'hui          Santé                Entraînement          Nutrition        (+)
───────────          ─────                ────────────          ─────────
Forme du jour        Moniteur (6 mesures) Cette semaine         Aliments du jour
 (3 anneaux)         Sommeil              Séance du jour ▶      Repas
Coaching (2 phrases) Symptômes, blessures Muscu : programmes    Eau, poids
Séance du jour ▶     Analyses ›           Vélo : sorties, FTP
À faire aujourd'hui   (tendances,          Saison Traka ›
 ✓ repas  ✓ eau        corrélations,        (plan, jalons)
 ✓ coucher 22:40       jour par jour)      Charge et fatigue ›
                                            (indicateurs experts)
```

- **Aujourd'hui** : 3 cartes au maximum. La séance du jour a un bouton ▶ qui lance directement la séance de muscu.
- **Santé** : reprend le moniteur de santé, déplacé depuis l'accueil. Tendances, corrélations et jour par jour passent dans « Analyses », au 2e niveau.
- **Entraînement** : réunit Activité et Plan. Plus de segments : des sections empilées dans l'ordre d'usage. Les indicateurs experts sont regroupés dans « Charge et fatigue ».
- **Le +** : les saisies récentes en premier.
- **Réglages** : 4 groupes et une liste de configuration à cocher.

Règle de lecture partout : 1 chiffre clé, 1 phrase, 1 action par carte. Le détail est au tap.
