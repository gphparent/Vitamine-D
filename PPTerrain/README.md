# PP Terrain

L'appli iPhone des photographes de Parent Photographe : les séances des huit
prochains jours, avec leurs plans, cartes et fichiers, **gardés sur le
téléphone** pour les endroits sans réseau.

> Ce dossier vit dans le dépôt de Vitamine-D sans y toucher : il n'en emprunte
> que les secrets App Store Connect. Son workflow est
> [`pp-terrain.yml`](../.github/workflows/pp-terrain.yml) : chaque poussée sur
> `main` qui touche ce dossier compile, teste et envoie une version sur
> TestFlight.

## Ce qu'elle fait

- **Séances.** Celles du photographe connecté, par jour, à partir d'aujourd'hui.
  Chaque retour dans l'appli, avec du réseau, remplace la copie gardée sur le
  téléphone.
- **Semaine.** Le calendrier du lundi au dimanche, cette semaine et la suivante ;
  toucher une séance ouvre sa fiche.
- **Tâches.** Comme « Mes tâches » de l'admin : photos à envoyer (étapes à
  cocher, puis « Photos envoyées »), retouches demandées par les clients (faites,
  en avisant le client ou non), tâches données par la coordination. Avec du
  réseau seulement. Jamais la facture ni le paiement.
- **Fiche.** Heure, adresse et itinéraire dans Google Maps, contacts (appel, texto),
  commande, précisions, accès (personne sur place, code reçu ou non).
- **Fichiers et notes.** Ceux déposés sur le rendez-vous dans l'admin, téléchargés
  d'avance et ouverts sans réseau.
- **Avis de départ.** Le iPhone calcule la vraie route avec Plans (circulation
  prévue), depuis le point de départ de Réglages ou la séance d'avant, et programme
  ses propres avis : 30 minutes avant de partir, à l'heure de partir, puis pour
  chaque séance suivante. La route ne part jamais de la position du téléphone.
- **Tuile.** La séance en cours sur l'écran verrouillé, dans l'île dynamique et
  dans CarPlay (iOS 26, petite version), avec le bouton « Arrivé » puis
  « Terminé » (extension `PPTerrainActivite`, code commun dans `Partage/`). Apple
  ne la laisse paraître qu'appli ouverte : au toucher d'un avis, ou à l'ouverture.
- **Arrivé et Terminé.** Notés seuls par le GPS (`Presence.swift`) : un cercle de
  150 m autour de chaque séance d'aujourd'hui et de demain ; l'entrée note
  l'arrivée (d'une heure avant à une heure après la fin prévue), la sortie note la
  fin (au moins 10 min plus tard). Permission « Toujours » ; aucune position ne
  quitte le téléphone. Les boutons de la fiche et de la tuile restent pour les
  ratés. Le trajet part au carnet de kilométrage (Réglages, « Kilométrage »), en
  kilomètres de la route. Sans réseau, le geste attend.

## Ce qu'elle ne fait jamais

- Recevoir un code de porte ou d'alarme du serveur. Les codes restent dans
  l'agenda Google, que le iPhone synchronise lui-même.
- Garder un mot de passe. La connexion se fait dans l'admin (double
  authentification), qui ouvre l'appli avec un code à usage unique de dix
  minutes ; l'appli l'échange contre un jeton gardé dans le trousseau.

## Connecter un iPhone

1. Installer PP Terrain par TestFlight.
2. Sur ce iPhone, dans Safari : l'admin, Réglages, « Appli iPhone ».
3. Toucher « Ouvrir PP Terrain ».

Un iPhone perdu se déconnecte depuis la même page ; tout ce qu'il a téléchargé
s'efface à sa prochaine ouverture avec du réseau.

## Côté serveur

`gphparent/pp-rendez-vous`, `app/Http/Controllers/Api/TerrainController.php` :
`POST /api/terrain/connexion`, `GET /api/terrain/rendez-vous`,
`GET /api/terrain/pieces/{id}`, `POST /api/terrain/rendez-vous/{id}/arrivee`,
`POST /api/terrain/rendez-vous/{id}/termine`,
`POST /api/terrain/rendez-vous/{id}/etape`, `POST /api/terrain/rendez-vous/{id}/photos-envoyees`,
`POST /api/terrain/taches/{id}/faite`, `POST /api/terrain/retouches/{id}/faite`,
`POST /api/terrain/deconnexion`. Les tâches arrivent avec les séances, sous `taches`.

## Développement

Le projet Xcode utilise des groupes synchronisés : tout fichier ajouté dans
`PPTerrain/` ou `PPTerrainTests/` est compilé sans toucher au projet.
L'icône est le « mini logo » de Parent Photographe, agrandi à 1024 px sans
transparence.
