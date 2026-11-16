import * as youtube from "./youtube.js";
import { juger, MODELE } from "./juge.js";
import { synchroniser, documentVide, fusion } from "./partage.js";

// Etat de l'appli, garde dans chrome.storage.local. Comme sur l'iPhone, rien
// n'entre dans les listes approuvees autrement que par un verdict du juge.
const TOUR_MAXIMUM = 30;
// L'historique d'une version anterieure a ete produit sans l'outil de
// recherche : le changement d'outils invaliderait ses blocs de reflexion.
const VERSION_CONVERSATION = 2;
let etat = {
  approbations: documentVide(),
  echanges: [],
  messagesAPI: [],
  cleAnthropic: "",
  jetonGitHub: "",
  gistID: null,
};
let fil = [];
let enAttente = false;
let montrerVues = false;
let listeOuverte = null;      // { liste, fiche } quand une liste est affichee

const $ = (s) => document.querySelector(s);
const maintenant = () => new Date().toISOString();

// MARK: Demarrage

async function demarrer() {
  etat = { ...etat, ...(await chrome.storage.local.get(null)) };
  // Un etat enregistre par une version anterieure n'a ni listes ni vus.
  etat.approbations = fusion(etat.approbations, documentVide());
  if (etat.versionConversation !== VERSION_CONVERSATION) {
    etat.versionConversation = VERSION_CONVERSATION;
    etat.messagesAPI = [];
    etat.echanges = [];
  }
  for (const bouton of document.querySelectorAll("nav button")) {
    bouton.addEventListener("click", () => afficherOnglet(bouton.dataset.onglet));
  }
  $("#formulaire").addEventListener("submit", (e) => { e.preventDefault(); envoyer(); });
  $("#saisie").addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); envoyer(); }
  });
  // Examiner une proposition revient a coller son lien : l'appli lit la page,
  // puis le juge tranche sur pieces.
  $("#conversation").addEventListener("click", (e) => {
    const bouton = e.target.closest("[data-examiner]");
    if (bouton && !enAttente) envoyer(`Examine : ${bouton.dataset.examiner}`);
  });
  $("#nouvelle").addEventListener("click", () => nouvelleConversation());
  $("#fermer-lecteur").addEventListener("click", fermerLecteur);
  $("#lecteur").addEventListener("click", (e) => { if (e.target.id === "lecteur") fermerLecteur(); });
  $("#basculer-vue").addEventListener("click", basculerVueEnCours);
  $("#rafraichir").addEventListener("click", () => rafraichirFil());
  for (const case_ of document.querySelectorAll(".montrer-vues")) {
    case_.addEventListener("change", () => {
      montrerVues = case_.checked;
      for (const autre of document.querySelectorAll(".montrer-vues")) autre.checked = montrerVues;
      rendre();
    });
  }
  window.addEventListener("message", ecouterLecteur);
  brancherReglages();
  rendre();
  await synchroniserSiPossible();
  await rafraichirFil();
}

async function enregistrer() {
  await chrome.storage.local.set(etat);
}

function afficherOnglet(nom) {
  for (const b of document.querySelectorAll("nav button")) b.classList.toggle("actif", b.dataset.onglet === nom);
  for (const s of document.querySelectorAll("main > section")) s.hidden = s.id !== nom;
  if (nom === "demander") $("#saisie").focus();
}

// MARK: Partage

async function synchroniserSiPossible() {
  if (!etat.jetonGitHub) return;
  try {
    const { document: doc, gistID } = await synchroniser(etat.approbations, etat.jetonGitHub, etat.gistID);
    etat.approbations = doc;
    etat.gistID = gistID;
    $("#etat-partage").textContent = `Synchronisé à ${new Date().toLocaleTimeString("fr-CA")}.`;
    await enregistrer();
    rendre();
  } catch (erreur) {
    $("#etat-partage").textContent = erreur.message;
  }
}

// MARK: Visionnements

const estVue = (id) => etat.approbations.vus.find((v) => v.id === id)?.vu ?? false;

async function marquer(id, vue) {
  if (estVue(id) === vue) return;
  etat.approbations = fusion(etat.approbations, { vus: [{ id, le: maintenant(), vu: vue }] });
  await enregistrer();
  rendre();
  await synchroniserSiPossible();
}

// MARK: Fil

async function rafraichirFil() {
  const chaines = etat.approbations.chaines;
  if (chaines.length === 0) { fil = []; rendreFil(); return; }
  $("#fil-liste").setAttribute("aria-busy", "true");
  const lots = await Promise.all(chaines.map((c) => youtube.flux(c.id).catch(() => [])));
  fil = lots.flat().sort((a, b) => ((a.publieeLe ?? "") < (b.publieeLe ?? "") ? 1 : -1));
  $("#fil-liste").removeAttribute("aria-busy");
  rendreFil();
}

// MARK: Juge

async function envoyer(texteImpose) {
  const texte = (texteImpose ?? $("#saisie").value).trim();
  if (!texte || enAttente) return;
  if (texteImpose === undefined) $("#saisie").value = "";
  enAttente = true;
  if (etat.messagesAPI.length >= TOUR_MAXIMUM * 2) {
    nouvelleConversation("Conversation recommencée : elle était devenue trop longue.");
  }
  etat.echanges.push({ auteur: "moi", texte, date: maintenant() });
  rendreConversation();

  // L'appli lit elle-meme ce que pointent les liens : le juge ne tranche que
  // sur des faits, jamais sur la seule parole de l'utilisateur.
  const idsVideo = youtube.identifiantsVideo(texte).slice(0, 3);
  const adresses = youtube.adressesChaine(texte).slice(0, 2);
  const idsListe = youtube.identifiantsListe(texte).slice(0, 2);
  const lire = (ids, f) => Promise.all(ids.map((x) => f(x).catch(() => null))).then((l) => l.filter(Boolean));
  const [fichesVideo, fichesChaine, fichesListe] = await Promise.all([
    lire(idsVideo, youtube.ficheVideo), lire(adresses, youtube.ficheChaine), lire(idsListe, youtube.ficheListe)]);

  const fiches = { fichesVideo, fichesChaine, fichesListe };
  const liensFournis = idsVideo.length + adresses.length + idsListe.length;
  const nouveau = { role: "user", content: composer(texte, fiches, liensFournis) };
  try {
    const decision = await juger(etat.cleAnthropic, etat.messagesAPI, nouveau);
    etat.messagesAPI.push(nouveau, { role: "assistant", content: decision.contenuBrut });
    const change = appliquer(decision, fiches);
    // Seuls les liens que l'appli sait lire sont proposes a l'examen.
    const propositions = decision.propositions.filter((p) => typeof p.url === "string"
      && youtube.identifiantsVideo(p.url).length + youtube.adressesChaine(p.url).length
         + youtube.identifiantsListe(p.url).length > 0).slice(0, 5);
    etat.echanges.push({ auteur: "juge", texte: decision.reponse, verdict: decision.verdict, propositions, date: maintenant() });
    await enregistrer();
    if (change) { await synchroniserSiPossible(); await rafraichirFil(); }
  } catch (erreur) {
    // Le tour echoue n'entre pas dans l'historique de l'API.
    etat.echanges.push({ auteur: "systeme", texte: erreur.message, date: maintenant() });
  }
  enAttente = false;
  await enregistrer();
  rendre();
}

function composer(texte, { fichesVideo, fichesChaine, fichesListe }, liensFournis) {
  const parties = [texte];
  for (const f of fichesVideo) parties.push(`<fiche_video>${JSON.stringify(f)}</fiche_video>`);
  for (const f of fichesListe) parties.push(`<fiche_liste>${JSON.stringify(f)}</fiche_liste>`);
  for (const f of fichesChaine) parties.push(`<fiche_chaine>${JSON.stringify(f)}</fiche_chaine>`);
  if (liensFournis > 0 && fichesVideo.length + fichesChaine.length + fichesListe.length === 0) {
    parties.push("<note>L'appli n'a pas pu lire le lien fourni.</note>");
  }
  const { chaines, listes, videos } = etat.approbations;
  const noms = (l, f) => (l.length ? l.map(f).join(", ") : "aucune");
  parties.push(`<etat>Chaînes approuvées : ${noms(chaines, (c) => c.nom)}. Listes approuvées : ${noms(listes, (l) => l.titre)}. Vidéos approuvées à l'unité : ${videos.length}.</etat>`);
  return parties.join("\n\n");
}

function appliquer(decision, { fichesVideo, fichesChaine, fichesListe }) {
  const doc = etat.approbations;
  const ajout = (cle, element) => {
    etat.approbations = fusion(doc, { [cle]: [{ ...element, approuveeLe: maintenant(), raison: decision.reponse }] });
    return true;
  };
  // Chaque identifiant doit sortir d'une fiche lue par l'appli a ce tour-ci.
  if (decision.verdict === "approuve_video") {
    const f = fichesVideo.find((x) => x.id === decision.videoID);
    if (!f || doc.videos.some((v) => v.id === f.id)) return false;
    return ajout("videos", { id: f.id, titre: f.titre, chaine: f.chaine });
  }
  if (decision.verdict === "approuve_liste") {
    const f = fichesListe.find((x) => x.id === decision.listeID);
    if (!f || doc.listes.some((l) => l.id === f.id)) return false;
    return ajout("listes", { id: f.id, titre: f.titre, chaine: f.chaine });
  }
  if (decision.verdict === "approuve_chaine") {
    const nom = fichesChaine.find((f) => f.id === decision.chaineID)?.nom
      ?? fichesVideo.find((f) => f.chaineID === decision.chaineID)?.chaine;
    if (!nom || doc.chaines.some((c) => c.id === decision.chaineID)) return false;
    return ajout("chaines", { id: decision.chaineID, nom });
  }
  return false;
}

function nouvelleConversation(note) {
  etat.messagesAPI = [];
  etat.echanges = note ? [{ auteur: "systeme", texte: note, date: maintenant() }] : [];
  enregistrer();
  rendreConversation();
}

// Retirer est toujours permis : fermer une porte ne demande personne.
async function retirer(id) {
  etat.approbations = fusion(etat.approbations, { retraits: [{ id, le: maintenant() }] });
  if (listeOuverte?.liste.id === id) listeOuverte = null;
  await enregistrer();
  rendre();
  await synchroniserSiPossible();
  await rafraichirFil();
}

// MARK: Lecteur

let suivi = null;   // ce que le lecteur a dit de la video en cours

function ouvrirLecteur({ videoID, listeID, titre }) {
  const parametres = new URLSearchParams({
    playsinline: "1", rel: "0", modestbranding: "1", iv_load_policy: "3", autoplay: "1",
    enablejsapi: "1", origin: location.origin,
  });
  if (listeID) parametres.set("list", listeID);
  const cadre = document.createElement("iframe");
  cadre.src = `https://www.youtube-nocookie.com/embed/${videoID ?? "videoseries"}?${parametres}`;
  cadre.allow = "autoplay; encrypted-media; picture-in-picture; fullscreen";
  cadre.allowFullscreen = true;
  // Pas d'`allow-popups` : « Regarder sur YouTube » et les liens sortants ne
  // menent nulle part.
  cadre.sandbox = "allow-scripts allow-same-origin allow-presentation";
  suivi = { cadre, id: videoID ?? null, t: 0, d: 0, signale: null, entendu: false };
  // Le lecteur ne parle qu'apres qu'on s'est annonce ; on insiste jusqu'a
  // la premiere reponse.
  const ecouter = () => cadre.contentWindow?.postMessage(JSON.stringify({ event: "listening", id: 1, channel: "widget" }), "*");
  cadre.addEventListener("load", ecouter);
  suivi.relance = setInterval(() => (suivi?.entendu ? clearInterval(suivi.relance) : ecouter()), 1000);
  $("#cadre").replaceChildren(cadre);
  $("#titre-lecteur").textContent = titre;
  $("#lecteur").hidden = false;
  rendreBoutonVue();
}

// Le protocole de messages du lecteur integre, celui de l'API iframe de
// YouTube : position, duree, video en cours, etat. Regardee a 90 % ou jusqu'au
// bout, une video est marquee vue.
function ecouterLecteur(e) {
  if (!suivi || e.source !== suivi.cadre.contentWindow) return;
  let m;
  try { m = JSON.parse(e.data); } catch { return; }
  suivi.entendu = true;
  const info = m.info ?? {};
  if (m.event === "infoDelivery") {
    const id = info.videoData?.video_id;
    if (id && id !== suivi.id) { suivi.id = id; suivi.t = 0; suivi.d = 0; rendreBoutonVue(); }
    if (typeof info.currentTime === "number") suivi.t = info.currentTime;
    if (typeof info.duration === "number" && info.duration > 0) suivi.d = info.duration;
  }
  const etatLecteur = m.event === "onStateChange" ? info : info.playerState;
  if (suivi.id && suivi.id !== suivi.signale && ((suivi.d > 0 && suivi.t / suivi.d >= 0.9) || etatLecteur === 0)) {
    suivi.signale = suivi.id;
    marquer(suivi.id, true).then(rendreBoutonVue);
  }
}

function rendreBoutonVue() {
  const bouton = $("#basculer-vue");
  bouton.hidden = !suivi?.id;
  if (suivi?.id) bouton.textContent = estVue(suivi.id) ? "Remettre à voir" : "Marquer comme vue";
}

async function basculerVueEnCours() {
  if (!suivi?.id) return;
  await marquer(suivi.id, !estVue(suivi.id));
  rendreBoutonVue();
}

function fermerLecteur() {
  if (suivi) clearInterval(suivi.relance);
  suivi = null;
  $("#cadre").replaceChildren();
  $("#lecteur").hidden = true;
}

// MARK: Rendu

function rendre() {
  rendreFil();
  rendreConversation();
  rendreApprouve();
}

function carteVideo({ id, titre, chaine, publieeLe }, listeID) {
  const carte = document.createElement("div");
  carte.className = "carte" + (estVue(id) ? " vue" : "");
  carte.innerHTML = `<button class="ouvrir"><img alt="" loading="lazy"><span class="titre"></span><span class="chaine"></span></button>
    <button class="marque" title=""></button>`;
  carte.querySelector("img").src = youtube.miniature(id);
  carte.querySelector(".titre").textContent = titre;
  carte.querySelector(".chaine").textContent = publieeLe
    ? `${chaine} · ${new Date(publieeLe).toLocaleDateString("fr-CA", { day: "numeric", month: "long" })}`
    : chaine;
  carte.querySelector(".ouvrir").addEventListener("click", () => ouvrirLecteur({ videoID: id, listeID, titre }));
  const marque = carte.querySelector(".marque");
  marque.textContent = estVue(id) ? "✓ Vue" : "Marquer vue";
  marque.addEventListener("click", () => marquer(id, !estVue(id)));
  return carte;
}

const aVoir = (videos) => (montrerVues ? videos : videos.filter((v) => !estVue(v.id)));

// Ce qui reste a voir : les nouvelles videos des chaines approuvees, puis les
// videos approuvees a l'unite qui n'y figurent pas deja.
function rendreFil() {
  const zone = $("#fil-liste");
  const { chaines, videos } = etat.approbations;
  if (chaines.length === 0 && videos.length === 0) {
    zone.innerHTML = `<p class="vide">Rien d'approuvé pour l'instant. Dans l'onglet Demander, colle un lien ou demande au juge de chercher : ce qu'il approuve arrivera ici.</p>`;
    return;
  }
  const nouveautes = aVoir(fil);
  const dansLeFil = new Set(fil.map((v) => v.id));
  const approuvees = aVoir(videos.filter((v) => !dansLeFil.has(v.id)))
    .sort((a, b) => (a.approuveeLe === b.approuveeLe ? a.titre.localeCompare(b.titre, "fr") : a.approuveeLe < b.approuveeLe ? 1 : -1));
  if (nouveautes.length === 0 && approuvees.length === 0) {
    zone.innerHTML = `<p class="vide">Tout est vu. Rien de nouveau à voir pour l'instant.</p>`;
    return;
  }
  const section = (titre, cartes) => {
    const s = document.createElement("div");
    s.className = "section-fil";
    s.innerHTML = `<h3></h3><div class="grille"></div>`;
    s.querySelector("h3").textContent = titre;
    s.querySelector(".grille").replaceChildren(...cartes);
    return s;
  };
  zone.replaceChildren(
    ...(nouveautes.length ? [section("Nouveautés des chaînes", nouveautes.map((v) => carteVideo(v)))] : []),
    ...(approuvees.length ? [section(`Vidéos approuvées (${approuvees.length})`, approuvees.map((v) => carteVideo(v)))] : []));
}

function rendreConversation() {
  const conteneur = $("#conversation");
  if (etat.echanges.length === 0) {
    conteneur.innerHTML = `<p class="vide">Colle le lien d'une vidéo, d'une liste de lecture ou d'une chaîne, ou demande au juge de chercher : « trouve-moi des conférences sur… »</p>`;
  } else {
    const etiquettes = {
      approuve_video: ["Vidéo approuvée", "ok"],
      approuve_chaine: ["Chaîne approuvée", "ok"],
      approuve_liste: ["Liste approuvée", "ok"],
      refuse: ["Refusé", "non"],
    };
    conteneur.replaceChildren(...etat.echanges.map((e) => {
      const bulle = document.createElement("div");
      bulle.className = `bulle ${e.auteur}`;
      const etiquette = etiquettes[e.verdict];
      if (etiquette) {
        const span = document.createElement("span");
        span.className = `verdict ${etiquette[1]}`;
        span.textContent = etiquette[0];
        bulle.append(span);
      }
      const p = document.createElement("p");
      p.textContent = e.texte;
      bulle.append(p);
      for (const prop of e.propositions ?? []) {
        const carte = document.createElement("div");
        carte.className = "proposition";
        carte.innerHTML = `<strong></strong><small></small><button></button>`;
        carte.querySelector("strong").textContent = prop.titre;
        carte.querySelector("small").textContent = prop.pourquoi;
        const bouton = carte.querySelector("button");
        bouton.textContent = "Examiner";
        bouton.dataset.examiner = prop.url;
        bouton.disabled = enAttente;
        bulle.append(carte);
      }
      return bulle;
    }));
  }
  if (enAttente) {
    const attente = document.createElement("div");
    attente.className = "attente";
    attente.textContent = "Le juge réfléchit…";
    conteneur.append(attente);
  }
  conteneur.scrollTop = conteneur.scrollHeight;
  $("#nouvelle").disabled = etat.echanges.length === 0 || enAttente;
  $("#envoyer").disabled = enAttente;
}

function ligne(titre, sousTitre, id, surClic) {
  const li = document.createElement("li");
  const texte = document.createElement(surClic ? "button" : "div");
  texte.className = "texte";
  texte.innerHTML = `<strong></strong><small></small>`;
  texte.querySelector("strong").textContent = titre;
  texte.querySelector("small").textContent = sousTitre;
  if (surClic) texte.addEventListener("click", surClic);
  const retrait = document.createElement("button");
  retrait.className = "retirer";
  retrait.textContent = "Retirer";
  retrait.addEventListener("click", () => retirer(id));
  li.append(texte, retrait);
  return li;
}

const vide = (texte) => Object.assign(document.createElement("li"), { className: "vide", textContent: texte });

function rendreApprouve() {
  const { videos, chaines, listes } = etat.approbations;

  $("#listes-approuvees").replaceChildren(...(listes.length
    ? listes.map((l) => ligne(l.titre, l.chaine, l.id, () => ouvrirListe(l)))
    : [vide("Aucune liste approuvée.")]));
  rendreListeOuverte();

  const visibles = aVoir(videos);
  $("#videos-approuvees").replaceChildren(...(visibles.length
    ? visibles.map((v) => {
        const li = ligne(v.titre, v.chaine + (estVue(v.id) ? " · vue" : ""), v.id,
          () => ouvrirLecteur({ videoID: v.id, titre: v.titre }));
        const marque = document.createElement("button");
        marque.textContent = estVue(v.id) ? "À voir" : "Vue";
        marque.addEventListener("click", () => marquer(v.id, !estVue(v.id)));
        li.insertBefore(marque, li.lastChild);
        return li;
      })
    : [vide(videos.length ? "Toutes les vidéos approuvées sont vues." : "Aucune vidéo approuvée à l'unité.")]));

  $("#chaines-approuvees").replaceChildren(...(chaines.length
    ? chaines.map((c) => ligne(c.nom, c.raison, c.id))
    : [vide("Aucune chaîne approuvée.")]));
}

async function ouvrirListe(liste) {
  listeOuverte = { liste, fiche: null, erreur: null };
  rendreListeOuverte();
  try { listeOuverte.fiche = await youtube.ficheListe(liste.id); }
  catch { if (listeOuverte) listeOuverte.erreur = "Impossible de lire cette liste pour l'instant."; }
  rendreListeOuverte();
}

function rendreListeOuverte() {
  const zone = $("#liste-ouverte");
  zone.hidden = !listeOuverte;
  if (!listeOuverte) return;
  const { liste, fiche, erreur } = listeOuverte;
  $("#liste-titre").textContent = liste.titre;
  const grille = $("#liste-videos");
  if (!fiche) {
    $("#liste-progres").textContent = erreur ?? "Lecture de la liste…";
    grille.replaceChildren();
    $("#liste-lire").hidden = true;
    return;
  }
  const restantes = fiche.videos.filter((v) => !estVue(v.id));
  $("#liste-progres").textContent = `${fiche.videos.length - restantes.length} vue(s) sur ${fiche.videos.length}`;
  const lire = $("#liste-lire");
  lire.hidden = false;
  lire.textContent = restantes.length === fiche.videos.length ? "Tout lire" : "Reprendre";
  lire.onclick = () => ouvrirLecteur({ videoID: restantes[0]?.id, listeID: liste.id, titre: liste.titre });
  grille.replaceChildren(...aVoir(fiche.videos).map((v) => carteVideo({ ...v, chaine: fiche.chaine }, liste.id)));
}

// MARK: Reglages

function brancherReglages() {
  $("#modele").textContent = MODELE;
  const champs = [["#cle-anthropic", "cleAnthropic"], ["#jeton-github", "jetonGitHub"]];
  for (const [selecteur, cle] of champs) {
    const champ = $(selecteur);
    champ.placeholder = etat[cle] ? "Enregistré sur cet ordi" : champ.dataset.exemple;
  }
  $("#reglages-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    for (const [selecteur, cle] of champs) {
      const valeur = $(selecteur).value.trim();
      if (valeur) etat[cle] = valeur;
      $(selecteur).value = "";
      $(selecteur).placeholder = etat[cle] ? "Enregistré sur cet ordi" : $(selecteur).dataset.exemple;
    }
    if (etat.jetonGitHub) etat.gistID = null;   // le jeton a pu changer de compte
    await enregistrer();
    await synchroniserSiPossible();
    await rafraichirFil();
  });
}

demarrer();
