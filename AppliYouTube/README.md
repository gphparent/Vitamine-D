# Appli YouTube

Application personnelle, sur iPhone et dans Brave : **YouTube, mais seulement ce
qu'un juge a approuvé.**

Bloquer YouTube complètement ne tient pas : on finit par contourner, et on
replonge. Cette appli remplace le tout-ou-rien par une porte gardée. On colle le
lien d'une vidéo ou d'une chaîne, on explique pourquoi on veut la regarder, et
Claude tranche selon des critères stricts. Seul ce qu'il approuve devient
visible.

> Ce dossier vit dans le dépôt de Vitamine-D sans y toucher : il n'en emprunte
> que les secrets App Store Connect. Son workflow est
> [`appli-youtube.yml`](../.github/workflows/appli-youtube.yml).

---

## Ce qu'elle fait

**Fil.** Les nouvelles vidéos des chaînes approuvées, tirées de leur flux RSS.
Pas de recherche, pas de suggestions : c'est par là que la spirale commence.

**Demander.** Une conversation avec le juge. L'appli lit elle-même la page de la
vidéo ou de la chaîne (titre, description, durée, dernières vidéos) et la lui
transmet ; il ne tranche jamais sur la seule parole de l'utilisateur. On peut
plaider avec des faits, pas avec de l'insistance.

**Approuvé.** Tout ce qui a été ouvert. On peut retirer ; rien ne s'y ajoute
autrement que par un verdict du juge.

**Lecteur.** Le lecteur intégré officiel de YouTube, sans issue vers YouTube.

**Partage.** Les approbations sont communes à l'iPhone et aux ordis, par un Gist
GitHub secret. Chaque conversation avec le juge reste propre à l'appareil.

## Les critères

Dans [`consignes.txt`](AppliYouTube/Resources/consignes.txt), copié à
l'identique dans l'extension (le workflow vérifie qu'ils ne divergent pas). Les
changer exige un commit — c'est voulu : un réglage se contourne en dix secondes,
un commit non.

## Mise en route

**iPhone**

1. Onglet Actions du dépôt → « Appli YouTube » → *Run workflow* : compile,
   teste, puis envoie sur TestFlight.
2. App Store Connect → l'app → TestFlight → Tests internes : s'ajouter comme
   testeur. Aucune revue d'Apple, l'appli n'est jamais publiée.
3. Dans l'appli, onglet Réglages : la clé d'API Anthropic, puis le jeton GitHub.

**Brave (chaque ordi)**

1. Télécharger le dossier `extension-brave/` (ou cloner le dépôt).
2. `brave://extensions` → activer le *Mode développeur* → *Charger l'extension
   non empaquetée* → choisir le dossier `extension-brave`.
3. Cliquer sur l'icône de l'extension, onglet Réglages : la même clé Anthropic
   et le même jeton GitHub.

**Le jeton GitHub** se crée une seule fois : github.com → Settings → Developer
settings → *Fine-grained tokens* → *Generate new token*, permission de compte
**Gists : Read and write**, rien d'autre.

**Le logiciel de blocage** doit laisser passer `youtube-nocookie.com`,
`googlevideo.com` et `i.ytimg.com` (lecteur et miniatures), et, pour Brave,
`www.youtube.com/feeds`, `/oembed` et `/watch` en lecture par l'extension.

**Le vrai site YouTube dans Brave.** L'extension surveille aussi
`www.youtube.com` : seule la recherche s'ouvre, et n'y paraissent que les
chaînes, listes et vidéos approuvées. L'accueil, les abonnements, les Shorts,
les pages de chaîne, les suggestions et les commentaires sont barrés ; une
vidéo ne joue que si elle, sa liste ou sa chaîne est approuvée, et elle est
marquée vue à 90 %. Pour s'en servir, le logiciel de blocage doit permettre
`www.youtube.com` **dans Brave seulement** : ailleurs, rien ne le surveille.
Les approbations se synchronisent en fond aux 15 minutes.

## Développement

Le projet Xcode utilise des groupes synchronisés : tout fichier ajouté dans
`AppliYouTube/` ou `AppliYouTubeTests/` est compilé sans toucher au projet.
`node --test extension-brave/tests/*.test.js` éprouve l'extension.

- `Tools/fabriquer-icone.py` régénère l'icône.
- `Tools/tester-cle-asc.py` éprouve la clé App Store Connect avant l'envoi.
