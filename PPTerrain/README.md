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

- **Séances.** Celles du photographe connecté, par jour. Chaque retour dans
  l'appli, avec du réseau, remplace la copie gardée sur le téléphone.
- **Fiche.** Heure, adresse et itinéraire dans Plans, contacts (appel, texto),
  commande, précisions, accès (personne sur place, code reçu ou non).
- **Fichiers et notes.** Ceux déposés sur le rendez-vous dans l'admin, téléchargés
  d'avance et ouverts sans réseau.

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
`GET /api/terrain/pieces/{id}`, `POST /api/terrain/deconnexion`.

## Développement

Le projet Xcode utilise des groupes synchronisés : tout fichier ajouté dans
`PPTerrain/` ou `PPTerrainTests/` est compilé sans toucher au projet.
L'icône est le « mini logo » de Parent Photographe, agrandi à 1024 px sans
transparence.
