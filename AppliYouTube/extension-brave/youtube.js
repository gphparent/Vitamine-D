// Lecture de YouTube sans cle Google : la page publique d'une video, la page
// d'une chaine et le flux RSS de chaque chaine. Meme logique que
// AppliYouTube/Services/YouTube.swift. Pas de recherche, volontairement.

export function identifiantsVideo(texte) {
  const motif = /(?:youtu\.be\/|youtube\.com\/(?:watch\?(?:[^\s]*&)?v=|shorts\/|live\/|embed\/))([A-Za-z0-9_-]{11})/g;
  return [...new Set([...texte.matchAll(motif)].map((m) => m[1]))];
}

export function adressesChaine(texte) {
  const motif = /(https?:\/\/(?:www\.|m\.)?youtube\.com\/(?:@[\w.\-]+|channel\/UC[\w-]{22}|c\/[\w.\-]+|user\/[\w.\-]+))/g;
  return [...new Set([...texte.matchAll(motif)].map((m) => m[1].replace("://m.", "://www.")))];
}

export async function ficheVideo(id) {
  const page = await telecharger(`https://www.youtube.com/watch?v=${id}&hl=fr`).catch(() => "");
  const json = objetJSON("ytInitialPlayerResponse = ", page);
  const details = json?.videoDetails;
  if (details?.title) {
    const micro = json.microformat?.playerMicroformatRenderer;
    return {
      id,
      titre: details.title,
      chaine: details.author ?? "",
      chaineID: details.channelId,
      description: details.shortDescription?.slice(0, 2000),
      dureeSecondes: Number(details.lengthSeconds) || undefined,
      categorie: micro?.category,
      motsCles: details.keywords?.slice(0, 20),
    };
  }
  // Repli : oEmbed ne donne que le titre et la chaine.
  const oembed = JSON.parse(await telecharger(
    `https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=${id}`));
  return { id, titre: oembed.title, chaine: oembed.author_name ?? "" };
}

export async function ficheChaine(adresse) {
  const page = await telecharger(adresse);
  const id = identifiantChaine(page);
  if (!id) throw new Error("Chaîne introuvable");
  const videos = await flux(id).catch(() => []);
  return {
    id,
    nom: meta("og:title", page) ?? id,
    description: meta("og:description", page),
    dernieresVideos: videos.slice(0, 15).map((v) => v.titre),
  };
}

export async function flux(chaineID) {
  const xml = await telecharger(`https://www.youtube.com/feeds/videos.xml?channel_id=${chaineID}`);
  const doc = new DOMParser().parseFromString(xml, "application/xml");
  return [...doc.getElementsByTagName("entry")].map((e) => ({
    id: e.getElementsByTagName("yt:videoId")[0]?.textContent ?? "",
    titre: e.getElementsByTagName("title")[0]?.textContent ?? "",
    chaine: e.querySelector("author > name")?.textContent ?? "",
    publieeLe: e.getElementsByTagName("published")[0]?.textContent ?? null,
  })).filter((v) => v.id);
}

export const miniature = (id) => `https://i.ytimg.com/vi/${id}/mqdefault.jpg`;

function identifiantChaine(page) {
  for (const motif of [/"externalId":"(UC[\w-]{22})"/, /itemprop="identifier" content="(UC[\w-]{22})"/,
                       /youtube\.com\/channel\/(UC[\w-]{22})"/]) {
    const m = page.match(motif);
    if (m) return m[1];
  }
  return null;
}

function meta(propriete, page) {
  const echappe = propriete.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const m = page.match(new RegExp(`<meta property="${echappe}" content="([^"]*)"`));
  if (!m) return null;
  const t = document.createElement("textarea");
  t.innerHTML = m[1];
  return t.value;
}

// L'objet JSON qui suit `marqueur`, en comptant les accolades hors des chaines.
function objetJSON(marqueur, page) {
  const debut = page.indexOf(marqueur);
  if (debut < 0) return null;
  let i = debut + marqueur.length;
  if (page[i] !== "{") return null;
  let profondeur = 0, dansChaine = false, echappe = false;
  for (let j = i; j < page.length; j++) {
    const c = page[j];
    if (dansChaine) {
      if (echappe) echappe = false;
      else if (c === "\\") echappe = true;
      else if (c === '"') dansChaine = false;
      continue;
    }
    if (c === '"') dansChaine = true;
    else if (c === "{") profondeur++;
    else if (c === "}" && --profondeur === 0) {
      try { return JSON.parse(page.slice(i, j + 1)); } catch { return null; }
    }
  }
  return null;
}

async function telecharger(adresse) {
  const reponse = await fetch(adresse, {
    headers: { "Accept-Language": "fr-CA,fr;q=0.9" },
    credentials: "omit",
  });
  if (!reponse.ok) throw new Error(`YouTube a répondu ${reponse.status}`);
  return reponse.text();
}
