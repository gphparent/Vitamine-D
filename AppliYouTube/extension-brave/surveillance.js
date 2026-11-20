// Le gardien du vrai site YouTube : seule la recherche s'ouvre, et n'y
// paraissent que les chaines, listes et videos approuvees. Une video ne joue
// que si elle, sa liste ou sa chaine est approuvee. Tout le reste (accueil,
// abonnements, Shorts, pages de chaine, suggestions) est barre.
const { portes, page, chaineApprouvee, resultat, lien } = globalThis.GardienYouTube;

let p = portes(null);
let adresse = null;
let verdict = "attente";      // "ok", "bloque" ou "attente"
let signalee = null;          // derniere video signalee comme vue

// MARK: Approbations

chrome.storage.local.get("approbations").then(({ approbations }) => {
  p = portes(approbations);
  evaluer(true);
});
chrome.storage.onChanged.addListener((changements) => {
  if (!changements.approbations) return;
  p = portes(changements.approbations.newValue);
  evaluer(true);
});

// MARK: Page

// YouTube change de page sans recharger : on surveille l'adresse.
setInterval(() => evaluer(false), 300);
document.addEventListener("yt-navigate-finish", () => evaluer(true));

async function evaluer(forcer) {
  if (!forcer && location.href === adresse) {
    if (verdict === "ok") filtrer();
    return;
  }
  const cetteAdresse = (adresse = location.href);
  let decision = page(cetteAdresse, p);
  if (decision === "chaine") {
    poser("attente");
    decision = (await chaineDeLaVideo()) ? "ok" : "bloque";
    if (cetteAdresse !== location.href) return;
  }
  poser(decision);
}

// La chaine d'une video, d'apres l'oEmbed de YouTube (meme origine).
async function chaineDeLaVideo() {
  try {
    const oembed = new URL("/oembed", location.origin);
    oembed.searchParams.set("url", location.href);
    oembed.searchParams.set("format", "json");
    const r = await fetch(oembed);
    if (!r.ok) return false;
    const { author_name: nom, author_url: url } = await r.json();
    return chaineApprouvee({ id: lien(url).chaine, nom }, p);
  } catch {
    return false;
  }
}

function poser(decision) {
  verdict = decision;
  document.documentElement.dataset.gardien = decision;
  document.getElementById("gardien-barrage")?.remove();
  if (decision !== "ok") for (const v of document.querySelectorAll("video")) v.pause();
  if (decision === "bloque") barrer();
  if (decision === "ok") filtrer();
}

// MARK: Barrage

function barrer() {
  const recherche = new URL(location.href).searchParams.get("search_query") ?? "";
  const barrage = document.createElement("div");
  barrage.id = "gardien-barrage";
  barrage.innerHTML = `<h1>Pas par ici.</h1>
    <p>Sur YouTube, seule la recherche est ouverte, et seul ce que le juge a approuvé s'y affiche.</p>
    <form><input type="search" placeholder="Chercher sur YouTube" autocomplete="off"><button>Chercher</button></form>
    <div><button class="secondaire" data-appli>Ouvrir l'Appli YouTube</button></div>`;
  const champ = barrage.querySelector("input");
  champ.value = recherche;
  barrage.querySelector("form").addEventListener("submit", (e) => {
    e.preventDefault();
    if (champ.value.trim()) location.assign(`/results?search_query=${encodeURIComponent(champ.value.trim())}`);
  });
  barrage.querySelector("[data-appli]").addEventListener("click", () => chrome.runtime.sendMessage({ type: "ouvrir" }));
  (document.body ?? document.documentElement).append(barrage);
  setTimeout(() => champ.focus(), 0);
}

// MARK: Resultats et lecteur

function filtrer() {
  const { pathname } = location;
  if (pathname === "/results") filtrerResultats();
  if (pathname === "/watch") surveillerLecteur();
}

function filtrerResultats() {
  let caches = 0;
  for (const el of document.querySelectorAll("ytd-search ytd-video-renderer, ytd-search ytd-channel-renderer, ytd-search ytd-playlist-renderer, ytd-search yt-lockup-view-model")) {
    const ok = approuve(el);
    if (ok) el.dataset.gardien = "ok"; else { delete el.dataset.gardien; caches++; }
  }
  noter(caches);
}

// Ce qu'un resultat designe, d'apres ses liens.
function approuve(el) {
  const canaux = [...el.querySelectorAll("a[href^='/@'], a[href^='/channel/']")];
  const chaine = {
    id: canaux.map((a) => lien(a.getAttribute("href")).chaine).find(Boolean) ?? null,
    nom: [el.querySelector("ytd-channel-name #text, #channel-title #text"), ...canaux]
      .map((x) => x?.textContent.trim()).find(Boolean),
  };
  if (el.matches("ytd-channel-renderer")) return resultat({ chaine }, p);
  const urls = [...el.querySelectorAll("a[href]")].map((a) => new URL(a.getAttribute("href"), location.origin));
  const liste = el.matches("ytd-playlist-renderer, yt-lockup-view-model")
    ? urls.map((u) => u.searchParams.get("list")).find(Boolean) ?? null
    : null;
  const video = urls.find((u) => u.pathname === "/watch")?.searchParams.get("v");
  return resultat({ video, liste, chaine }, p);
}

function noter(caches) {
  const ou = document.querySelector("ytd-search #contents");
  if (!ou) return;
  let note = document.getElementById("gardien-note");
  if (!note) {
    note = document.createElement("div");
    note.id = "gardien-note";
    ou.before(note);
  }
  const texte = caches === 0
    ? "Le gardien filtre cette recherche : seul ce qui est approuvé s'affiche."
    : `${caches} résultat${caches > 1 ? "s" : ""} non approuvé${caches > 1 ? "s" : ""} masqué${caches > 1 ? "s" : ""}. Pour en faire approuver un, demande au juge dans l'Appli YouTube.`;
  if (note.textContent !== texte) note.textContent = texte;
}

// Une video regardee a 90 % ou jusqu'au bout est marquee vue, comme dans
// l'appli. Tant que la page n'est pas permise, rien ne joue.
function surveillerLecteur() {
  const video = document.querySelector("video.html5-main-video, video");
  if (!video || video.dataset.gardien) return;
  video.dataset.gardien = "1";
  const verifier = () => {
    const id = new URL(location.href).searchParams.get("v");
    if (verdict !== "ok") { video.pause(); return; }
    if (!id || id === signalee || !(video.duration > 0)) return;
    if (video.currentTime / video.duration >= 0.9 || video.ended) {
      signalee = id;
      chrome.runtime.sendMessage({ type: "vue", id });
    }
  };
  video.addEventListener("timeupdate", verifier);
  video.addEventListener("play", verifier);
  video.addEventListener("ended", verifier);
}

// Rien ne joue tant que le gardien n'a pas dit oui.
document.addEventListener("play", (e) => {
  if (verdict !== "ok" && e.target instanceof HTMLMediaElement) e.target.pause();
}, true);
