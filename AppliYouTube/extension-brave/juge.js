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
    propositions: {
      type: "array",
      items: {
        type: "object",
        properties: { url: { type: "string" }, titre: { type: "string" }, pourquoi: { type: "string" } },
        required: ["url", "titre", "pourquoi"],
        additionalProperties: false,
      },
    },
  },
  required: ["reponse", "verdict", "video_id", "chaine_id", "liste_id", "propositions"],
  additionalProperties: false,
};

// La recherche web, limitee a YouTube : c'est ainsi qu'on trouve des chaines
// sans ouvrir YouTube. Declaree des le premier tour et jamais modifiee, pour ne
// pas invalider l'historique.
const OUTILS = [{ type: "web_search_20260209", name: "web_search", max_uses: 5, allowed_domains: ["youtube.com"] }];

let consignes;

// `historique` n'est jamais reecrit, seulement prolonge : les blocs de
// reflexion des tours precedents doivent revenir tels quels.
export async function juger(cle, historique, nouveau) {
  if (!cle) throw new Error("Ajoute ta clé d'API Anthropic dans Réglages.");
  consignes ??= await (await fetch(chrome.runtime.getURL("consignes.txt"))).text();

  // Une recherche longue peut s'interrompre (`pause_turn`) : on renvoie le
  // tour en cours tel quel et le serveur reprend ou il en etait.
  let contenu = [];
  for (let essai = 0; essai < 4; essai++) {
    const messages = [...historique, nouveau];
    if (contenu.length) messages.push({ role: "assistant", content: contenu });
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
        tools: OUTILS,
        output_config: { effort: "medium", format: { type: "json_schema", schema: SCHEMA } },
        messages,
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
    contenu = [...contenu, ...json.content];
    if (json.stop_reason !== "pause_turn") break;
  }

  // La reponse est le texte qui suit la derniere recherche : ce qui precede
  // n'est que le cheminement.
  const derniere = contenu.findLastIndex((b) => b.type?.endsWith("_tool_result"));
  const texte = contenu.slice(derniere + 1).filter((b) => b.type === "text").map((b) => b.text).join("");
  let sortie;
  try { sortie = JSON.parse(texte); } catch { throw new Error("Réponse du juge illisible. Réessaie."); }
  return {
    reponse: sortie.reponse,
    verdict: sortie.verdict,
    videoID: sortie.video_id ?? "",
    chaineID: sortie.chaine_id ?? "",
    listeID: sortie.liste_id ?? "",
    propositions: Array.isArray(sortie.propositions) ? sortie.propositions : [],
    contenuBrut: contenu,
  };
}
