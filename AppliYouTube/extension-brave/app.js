import * as youtube from "./youtube.js";
import { juger, MODELE } from "./juge.js";
import { synchroniser, documentVide, fusion } from "./partage.js";

// Etat de l'appli, garde dans chrome.storage.local. Comme sur l'iPhone, rien
// n'entre dans les listes approuvees autrement que par un verdict du juge.
const TOUR_MAXIMUM = 30;
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

const $ = (s) => document.querySelector(s);
const maintenant = () => new Date().toISOString();

// MARK: Demarrage

async function demarrer() {
  etat = { ...etat, ...(await chrome.storage.local.get(null)) };
  for (const bouton of document.querySelectorAll("nav button")) {
    bouton.addEventListener("click", () => afficherOnglet(bouton.dataset.onglet));
  }
  $("#formulaire").addEventListener("submit", (e) => { e.preventDefault(); envoyer(); });
  $("#saisie").addEventListener("keydown", (e) => {
    if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); envoyer(); }
  });
  $("#nouvelle").addEventListener("click", () => nouvelleConversation());
  $("#fermer-lecteur").addEventListener("click", fermerLecteur);
  $("#lecteur").addEventListener("click", (e) => { if (e.target.id === "lecteur") fermerLecteur(); });
  $("#rafraichir").addEventListener("click", () => rafraichirFil());
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

async function envoyer() {
  const texte = $("#saisie").value.trim();
  if (!texte || enAttente) return;
  $("#saisie").value = "";
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
  const fichesVideo = (await Promise.all(idsVideo.map((id) => youtube.ficheVideo(id).catch(() => null)))).filter(Boolean);
  const fichesChaine = (await Promise.all(adresses.map((a) => youtube.ficheChaine(a).catch(() => null)))).filter(Boolean);

  const nouveau = { role: "user", content: composer(texte, fichesVideo, fichesChaine, idsVideo.length + adresses.length) };
  try {
    const decision = await juger(etat.cleAnthropic, etat.messagesAPI, nouveau);
    etat.messagesAPI.push(nouveau, { role: "assistant", content: decision.contenuBrut });
    const change = appliquer(decision, fichesVideo, fichesChaine);
    etat.echanges.push({ auteur: "juge", texte: decision.reponse, verdict: decision.verdict, date: maintenant() });
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

function composer(texte, fichesVideo, fichesChaine, liensFournis) {
  const parties = [texte];
  for (const f of fichesVideo) parties.push(`<fiche_video>${JSON.stringify(f)}</fiche_video>`);
  for (const f of fichesChaine) parties.push(`<fiche_chaine>${JSON.stringify(f)}</fiche_chaine>`);
  if (liensFournis > 0 && fichesVideo.length + fichesChaine.length === 0) {
    parties.push("<note>L'appli n'a pas pu lire le lien fourni.</note>");
  }
  const { chaines, videos } = etat.approbations;
  parties.push(`<etat>Chaînes approuvées : ${chaines.length ? chaines.map((c) => c.nom).join(", ") : "aucune"}. Vidéos approuvées à l'unité : ${videos.length}.</etat>`);
  return parties.join("\n\n");
}

function appliquer(decision, fichesVideo, fichesChaine) {
  const doc = etat.approbations;
  if (decision.verdict === "approuve_video") {
    // L'identifiant doit sortir d'une fiche lue par l'appli a ce tour-ci.
    const fiche = fichesVideo.find((f) => f.id === decision.videoID);
    if (!fiche || doc.videos.some((v) => v.id === fiche.id)) return false;
    etat.approbations = fusion(doc, { videos: [{
      id: fiche.id, titre: fiche.titre, chaine: fiche.chaine, approuveeLe: maintenant(), raison: decision.reponse }] });
    return true;
  }
  if (decision.verdict === "approuve_chaine") {
    const nom = fichesChaine.find((f) => f.id === decision.chaineID)?.nom
      ?? fichesVideo.find((f) => f.chaineID === decision.chaineID)?.chaine;
    if (!nom || doc.chaines.some((c) => c.id === decision.chaineID)) return false;
    etat.approbations = fusion(doc, { chaines: [{
      id: decision.chaineID, nom, approuveeLe: maintenant(), raison: decision.reponse }] });
    return true;
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
  await enregistrer();
  rendre();
  await synchroniserSiPossible();
  await rafraichirFil();
}

// MARK: Lecteur

function ouvrirLecteur(id, titre) {
  const parametres = "playsinline=1&rel=0&modestbranding=1&iv_load_policy=3&autoplay=1";
  const cadre = document.createElement("iframe");
  cadre.src = `https://www.youtube-nocookie.com/embed/${id}?${parametres}`;
  cadre.allow = "autoplay; encrypted-media; picture-in-picture; fullscreen";
  cadre.allowFullscreen = true;
  // Pas d'`allow-popups` : « Regarder sur YouTube » et les liens sortants ne
  // mènent nulle part.
  cadre.sandbox = "allow-scripts allow-same-origin allow-presentation";
  $("#cadre").replaceChildren(cadre);
  $("#titre-lecteur").textContent = titre;
  $("#lecteur").hidden = false;
}

function fermerLecteur() {
  $("#cadre").replaceChildren();
  $("#lecteur").hidden = true;
}

// MARK: Rendu

function rendre() {
  rendreFil();
  rendreConversation();
  rendreApprouve();
}

function carteVideo({ id, titre, chaine, publieeLe }) {
  const carte = document.createElement("button");
  carte.className = "carte";
  carte.innerHTML = `<img alt="" loading="lazy"><span class="titre"></span><span class="chaine"></span>`;
  carte.querySelector("img").src = youtube.miniature(id);
  carte.querySelector(".titre").textContent = titre;
  carte.querySelector(".chaine").textContent = publieeLe
    ? `${chaine} · ${new Date(publieeLe).toLocaleDateString("fr-CA", { day: "numeric", month: "long" })}`
    : chaine;
  carte.addEventListener("click", () => ouvrirLecteur(id, titre));
  return carte;
}

function rendreFil() {
  const liste = $("#fil-liste");
  if (etat.approbations.chaines.length === 0) {
    liste.innerHTML = `<p class="vide">Aucune chaîne approuvée. Colle le lien d'une chaîne dans l'onglet Demander : si le juge l'approuve, ses nouvelles vidéos arriveront ici.</p>`;
    return;
  }
  liste.replaceChildren(...fil.map(carteVideo));
}

function rendreConversation() {
  const conteneur = $("#conversation");
  if (etat.echanges.length === 0) {
    conteneur.innerHTML = `<p class="vide">Colle le lien d'une vidéo ou d'une chaîne et dis pourquoi tu veux la regarder.</p>`;
  } else {
    const etiquettes = {
      approuve_video: ["Vidéo approuvée", "ok"],
      approuve_chaine: ["Chaîne approuvée", "ok"],
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

function rendreApprouve() {
  const { videos, chaines } = etat.approbations;
  const ligne = (titre, sousTitre, id, surClic) => {
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
  };
  $("#videos-approuvees").replaceChildren(...(videos.length
    ? videos.map((v) => ligne(v.titre, v.chaine, v.id, () => ouvrirLecteur(v.id, v.titre)))
    : [Object.assign(document.createElement("li"), { className: "vide", textContent: "Aucune vidéo approuvée à l'unité." })]));
  $("#chaines-approuvees").replaceChildren(...(chaines.length
    ? chaines.map((c) => ligne(c.nom, c.raison, c.id))
    : [Object.assign(document.createElement("li"), { className: "vide", textContent: "Aucune chaîne approuvée." })]));
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
