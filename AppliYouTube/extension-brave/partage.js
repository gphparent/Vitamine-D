// Approbations partagees entre l'iPhone et les ordis, par un Gist GitHub
// secret. Meme format et meme fusion que AppliYouTube/Services/Partage.swift.
//
// Le document : { version, chaines, videos, listes, retraits: [{id, le}],
// vus: [{id, le, vu}] }.
// Un retrait est garde comme une pierre tombale : sans lui, un appareil qui
// n'a pas encore vu le retrait remettrait l'element a la prochaine fusion.

const DESCRIPTION = "Appli YouTube — approbations partagées";
const FICHIER = "approbations.json";

export function documentVide() {
  return { version: 1, chaines: [], videos: [], listes: [], retraits: [], vus: [] };
}

export function fusion(a, b) {
  const retraits = new Map();
  for (const r of [...(a.retraits ?? []), ...(b.retraits ?? [])]) {
    const deja = retraits.get(r.id);
    if (!deja || deja.le < r.le) retraits.set(r.id, r);
  }
  const garder = (liste) => {
    const parId = new Map();
    for (const e of liste) {
      const deja = parId.get(e.id);
      if (!deja || deja.approuveeLe < e.approuveeLe) parId.set(e.id, e);
    }
    return [...parId.values()]
      .filter((e) => !(retraits.get(e.id)?.le >= e.approuveeLe))
      .sort((x, y) => (x.approuveeLe < y.approuveeLe ? 1 : -1));
  };
  // Pour les visionnements, le dernier mot l'emporte : vu, remis a voir, revu.
  const vus = new Map();
  for (const v of [...(a.vus ?? []), ...(b.vus ?? [])]) {
    const deja = vus.get(v.id);
    if (!deja || deja.le < v.le) vus.set(v.id, v);
  }
  const parId = (x, y) => (x.id < y.id ? -1 : 1);
  return {
    version: 1,
    chaines: garder([...(a.chaines ?? []), ...(b.chaines ?? [])]),
    videos: garder([...(a.videos ?? []), ...(b.videos ?? [])]),
    listes: garder([...(a.listes ?? []), ...(b.listes ?? [])]),
    retraits: [...retraits.values()].sort(parId),
    vus: [...vus.values()].sort(parId),
  };
}

export async function synchroniser(local, jeton, gistID) {
  const id = gistID ?? (await trouverOuCreer(jeton, local));
  const gist = await appel(jeton, `/gists/${id}`);
  const fichier = gist.files?.[FICHIER];
  let distant = documentVide();
  if (fichier) {
    const texte = fichier.truncated ? await (await fetch(fichier.raw_url)).text() : fichier.content;
    try { distant = JSON.parse(texte); } catch { /* document abime : on le reecrit */ }
  }
  const fusionne = fusion(local, distant);
  const contenu = JSON.stringify(fusionne, null, 2);
  if (contenu !== JSON.stringify(fusion(distant, documentVide()), null, 2)) {
    await appel(jeton, `/gists/${id}`, "PATCH", { files: { [FICHIER]: { content: contenu } } });
  }
  return { document: fusionne, gistID: id };
}

async function trouverOuCreer(jeton, local) {
  for (let page = 1; page <= 5; page++) {
    const liste = await appel(jeton, `/gists?per_page=100&page=${page}`);
    const trouve = liste.find((g) => g.description === DESCRIPTION);
    if (trouve) return trouve.id;
    if (liste.length < 100) break;
  }
  const cree = await appel(jeton, "/gists", "POST", {
    description: DESCRIPTION,
    public: false,
    files: { [FICHIER]: { content: JSON.stringify(fusion(local, documentVide()), null, 2) } },
  });
  return cree.id;
}

async function appel(jeton, chemin, methode = "GET", corps) {
  const reponse = await fetch(`https://api.github.com${chemin}`, {
    method: methode,
    headers: {
      Authorization: `Bearer ${jeton}`,
      Accept: "application/vnd.github+json",
      "X-GitHub-Api-Version": "2022-11-28",
      ...(corps ? { "Content-Type": "application/json" } : {}),
    },
    body: corps ? JSON.stringify(corps) : undefined,
  });
  if (reponse.status === 401 || reponse.status === 403) {
    throw new Error("Jeton GitHub refusé : il doit avoir l'accès en lecture et écriture aux Gists.");
  }
  if (!reponse.ok) throw new Error(`GitHub a répondu ${reponse.status}`);
  return reponse.json();
}
