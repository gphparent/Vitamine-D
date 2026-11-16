// Le juge : Claude, par l'API Messages. Meme requete que
// AppliYouTube/Services/Juge.swift, memes consignes (consignes.txt).

export const MODELE = "claude-opus-5-5";

const SCHEMA = {
  type: "object",
  properties: {
    reponse: { type: "string", description: "Ce que tu réponds à l'utilisateur." },
    verdict: { type: "string", enum: ["approuve_video", "approuve_chaine", "approuve_liste", "refuse", "discussion"] },
    video_id: { type: "string" },
    chaine_id: { type: "string" },
    liste_id: { type: "string" },
  },
  required: ["reponse", "verdict", "video_id", "chaine_id", "liste_id"],
  additionalProperties: false,
};

let consignes;

// `historique` n'est jamais reecrit, seulement prolonge : les blocs de
// reflexion des tours precedents doivent revenir tels quels.
export async function juger(cle, historique, nouveau) {
  if (!cle) throw new Error("Ajoute ta clé d'API Anthropic dans Réglages.");
  consignes ??= await (await fetch(chrome.runtime.getURL("consignes.txt"))).text();

  const reponse = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": cle,
      "anthropic-version": "2026-10-21",
      // Si un filtre de securite declinait la demande, l'API la relance
      // d'elle-meme sur le modele de repli recommande.
      "anthropic-beta": "server-side-fallback-2026-07-01",
      "anthropic-dangerous-direct-browser-access": "true",
    },
    body: JSON.stringify({
      model: MODELE,
      max_tokens: 16000,
      fallbacks: "default",
      system: consignes,
      output_config: { effort: "medium", format: { type: "json_schema", schema: SCHEMA } },
      messages: [...historique, nouveau],
    }),
  });

  const json = await reponse.json().catch(() => null);
  if (reponse.status === 401 || reponse.status === 403) {
    throw new Error("La clé d'API Anthropic est refusée. Vérifie-la dans Réglages.");
  }
  if (reponse.status === 429 || reponse.status >= 500) {
    throw new Error("Le juge est surchargé. Réessaie dans une minute.");
  }
  if (!reponse.ok) throw new Error(`Erreur ${reponse.status} : ${json?.error?.message ?? ""}`);
  if (json.stop_reason === "refusal") throw new Error("Le juge a décliné cette demande.");

  const texte = json.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  let sortie;
  try { sortie = JSON.parse(texte); } catch { throw new Error("Réponse du juge illisible. Réessaie."); }
  return {
    reponse: sortie.reponse,
    verdict: sortie.verdict,
    videoID: sortie.video_id ?? "",
    chaineID: sortie.chaine_id ?? "",
    listeID: sortie.liste_id ?? "",
    contenuBrut: json.content,
  };
}
