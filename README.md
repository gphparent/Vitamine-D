# Vitamine D

Application iOS qui répond à une question précise : **à quel moment sortir dehors, aujourd'hui, à l'endroit où je suis, dans la tenue que je porte** — et **quand rentrer** avant le coup de soleil.

Elle croise quatre choses que les applications météo traitent séparément : la géométrie solaire, l'indice UV réel, votre peau, et vos vêtements.

---

## Ce qu'elle fait

**Aujourd'hui.** Position du Soleil en direct, indice UV, et la phrase qui compte : *votre ombre est-elle plus courte que vous ?* En dessous de 45° de hauteur solaire, le rendement s'effondre ; en dessous de 25°, il n'y a plus rien à récolter — c'est l'hiver vitaminique, signalé explicitement.

**Quand sortir.** Jusqu'à trois créneaux classés, chacun avec sa durée, la vitamine D attendue, la part de capital cutané dépensée, et ce qui met fin au créneau (objectif atteint, limite de sécurité, ou plafond de synthèse). Le classement tient compte du confort : un créneau photobiologiquement parfait sous la pluie à 4 °C ne vaut rien.

**Une sortie en direct.** Chronomètre, dose accumulée, débit instantané, rendement marginal restant. Deux barres côte à côte — vitamine D gagnée, capital cutané dépensé — parce que la question n'est jamais « combien de soleil » mais « combien de vitamine D pour combien de peau ».

**Des alertes qui arrivent même téléphone rangé.** Les trois seuils d'une sortie — objectif atteint, seuil d'alerte cutanée, arrêt — sont projetés et déposés auprès du système dès le départ. Plus une alerte à l'ouverture de la fenêtre UVB, et un plan du matin. Changez de tenue ou appliquez de la crème en cours de route : les alertes sont recalculées.

**Un historique.** Total du jour, des sept derniers jours, et deux semaines de barres avec la ligne d'objectif.

---

## Les entrées du calcul

| | |
|---|---|
| **Phototype** | Fitzpatrick I à VI, avec un questionnaire d'aide fondé sur la réaction au soleil plutôt que sur la couleur perçue |
| **Âge** | La concentration cutanée en 7-déhydrocholestérol décroît d'environ 1 % par an après vingt ans |
| **Acclimatation** | Le bronzage accumulé relève la dose érythémale minimale jusqu'à 60 % |
| **Tenue** | Six tenues prédéfinies, ou onze régions corporelles à cocher, plus chapeau et crème solaire |
| **Lieu** | Position réelle, ou lieu fixé à la main pour préparer un déplacement |
| **Météo** | Nuages, température ressentie, probabilité de pluie, vent, neige au sol |
| **Environnement** | Altitude, albédo, colonne d'ozone |

---

## Ouvrir et lancer

```bash
open VitamineD.xcodeproj
```

Xcode 16 ou plus récent, iOS 18 minimum. Le projet utilise des groupes synchronisés avec le système de fichiers : ajouter un fichier Swift dans `VitamineD/` suffit, il n'y a pas de liste de sources à tenir à jour.

Deux réglages à faire avant de lancer sur un appareil :

1. **Équipe de signature** — `DEVELOPMENT_TEAM` est vide dans les deux cibles. Choisissez la vôtre dans *Signing & Capabilities*.
2. **Identifiant de paquet** — `ca.gphparent.VitamineD`, à changer si vous n'êtes pas le propriétaire de ce domaine.

Les tests :

```bash
xcodebuild test -scheme VitamineD -destination 'platform=iOS Simulator,name=iPhone 16'
```

---

## Architecture

```
VitamineD/
├── Models/         SkinType · BodyExposure · UserProfile · ExposureSession
├── Engine/         SolarCalculator · UVEngine · DayPlanner
├── Services/       AppModel · WeatherService · LocationService
│                   NotificationService · Store
└── Views/          Today · Session · History · Profile · Clothing · DayChart
```

`Engine/` ne dépend que de Foundation : aucun accès réseau, aucun état global, aucune interface. C'est là que vit toute la physique, et c'est ce qui la rend testable — 64 tests, répartis en quatre suites, couvrent la position solaire, les doses et le planificateur.

`AppModel` est le seul état partagé, exposé via `@Observable` et l'environnement SwiftUI.

---

## Le modèle scientifique

### Position du Soleil

Algorithme du NOAA Solar Calculator, dérivé des *Astronomical Algorithms* de Meeus. Précision de l'ordre de la minute d'arc entre 1900 et 2100. Entièrement hors ligne.

Vérifié contre les éphémérides publiées : hauteur maximale à Montréal au solstice d'été 67,94° (référence 67,9°), midi solaire 12 h 56, lever 5 h 07 contre 5 h 06 en référence. Les cas polaires — nuit polaire et Soleil de minuit à Tromsø — sont couverts par des tests.

Le seuil conventionnel de lever et coucher (−0,833°) intègre déjà la réfraction : il est donc comparé à la hauteur *géométrique*, pas à la hauteur apparente. Compter la réfraction deux fois allongerait la journée de quatre minutes.

### Indice UV

Prévisions Open-Meteo — API météo pour la surface, API qualité de l'air pour l'indice UV, fusionnées sur l'horodatage. Sans réseau, l'application retombe sur la paramétrisation de Fioletov :

```
UVI ≈ 12,5 · μ^2,42 · (Ω/300)^−1,23
```

où μ est le cosinus de l'angle zénithal et Ω la colonne d'ozone en unités Dobson, corrigée de l'altitude (+6 %/km), de l'albédo et des aérosols. L'application le signale alors clairement : les heures restent exactes, seuls les nuages manquent.

L'interpolation entre points horaires ne porte pas sur l'indice brut mais sur le rapport au ciel clair — sans quoi un faux plateau se creuserait autour du midi solaire.

### Érythème

Un point d'indice UV vaut 25 mW/m² pondérés par le spectre d'action de l'érythème (CIE). La dose érythémale minimale va de 200 J/m² (phototype I) à 1 000 J/m² (phototype VI).

La crème solaire est comptée à la **racine carrée** de son indice nominal. L'IP affiché sur le tube est mesuré à 2 mg/cm², une épaisseur que presque personne n'applique ; un IP 30 mal étalé protège comme un IP 5. Mieux vaut sous-estimer sa protection que l'inverse.

### Synthèse de vitamine D

```
UI/min = 55 · UVI · η(h) · surface exposée · facteur phototype · facteur âge · transmission
```

où `η(h)` est l'efficacité spectrale en fonction de la hauteur solaire. Le spectre d'action de la vitamine D culmine vers 297 nm, plus court que celui de l'érythème : l'absorption par l'ozone l'attaque donc plus vite quand le trajet atmosphérique s'allonge. C'est pourquoi la synthèse s'éteint alors que l'indice UV reste mesurable.

La constante 55 est calée sur le repère clinique classique : phototype III, un quart du corps découvert, indice UV 7, Soleil haut → environ 1 000 UI en douze minutes. Les valeurs qui en découlent sont cohérentes avec la littérature : 8 minutes au midi de juin à Montréal en t-shirt et short, trois à cinq fois plus pour un phototype VI, et une impossibilité pratique de novembre à février.

### Le plafond

Au-delà d'une certaine dose, la prévitamine D3 se photo-isomérise en lumistérol et en tachystérol au lieu de s'accumuler. La synthèse sature — modélisée par `plafond · (1 − e^(−dose/plafond))` — pendant que la dose érythémale, elle, continue de croître linéairement.

C'est le mécanisme qui rend impossible une intoxication à la vitamine D par le seul soleil, et qui rend toute exposition prolongée inutile. L'application le montre par le « rendement marginal restant ».

---

## Ce que l'application ignore

L'orientation du corps par rapport au Soleil. L'ombre des bâtiments et des arbres. La réflexion par l'eau ou le sable. Les vitres, qui bloquent la totalité des UVB. L'état des réserves hépatiques de 25-hydroxyvitamine D. Les médicaments photosensibilisants. Et la variabilité individuelle, qui atteint couramment un facteur deux ou trois entre personnes de même phototype.

**Ce n'est pas un dispositif médical.** Les durées affichées sont des ordres de grandeur, pas des mesures. Elles ne remplacent ni un dosage sanguin, ni l'avis d'un professionnel de la santé.

---

## Points à traiter avant une diffusion

- **Licence Open-Meteo** — gratuite pour l'usage non commercial. Une publication sur l'App Store demanderait un abonnement, ou un basculement vers WeatherKit (déjà inclus dans un compte développeur Apple, et qui fournit l'indice UV).
- **Alertes prioritaires** — l'alerte d'arrêt est marquée `.timeSensitive`. Sans l'autorisation `com.apple.developer.usernotifications.time-sensitive`, iOS la traite comme une notification ordinaire.
- **Icône** — le catalogue contient un emplacement 1024×1024 vide.
- **Mode langage Swift** — le projet est en Swift 5 avec concurrence stricte en mode `targeted`. Le code est écrit pour Swift 6 ; passer `SWIFT_VERSION` à `6.0` est la prochaine étape naturelle, une fois les avertissements résiduels traités.
- **Activité en direct** — une Live Activity sur l'écran verrouillé, montrant les deux barres pendant la sortie, serait le prolongement évident du suivi de séance.
