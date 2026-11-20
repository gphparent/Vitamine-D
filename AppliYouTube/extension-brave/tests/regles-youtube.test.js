import { test } from "node:test";
import assert from "node:assert/strict";
import "../regles-youtube.js";

const { portes, page, resultat, lien } = globalThis.GardienYouTube;
const doc = {
  chaines: [{ id: "UCaaaaaaaaaaaaaaaaaaaaaa", nom: "Le Jour du Seigneur" }],
  videos: [{ id: "abcdefghijk", chaine: "Autre chaîne" }],
  listes: [{ id: "PLcours" }],
};
const p = portes(doc);
const yt = (chemin) => `https://www.youtube.com${chemin}`;

test("seule la recherche s'ouvre ; accueil, Shorts et chaines sont barres", () => {
  assert.equal(page(yt("/results?search_query=menuiserie"), p), "ok");
  for (const chemin of ["/", "/feed/subscriptions", "/shorts/abcdefghijk", "/@chaine", "/feed/trending"]) {
    assert.equal(page(yt(chemin), p), "bloque", chemin);
  }
});

test("une video s'ouvre si elle ou sa liste est approuvee, sinon la chaine tranche", () => {
  assert.equal(page(yt("/watch?v=abcdefghijk"), p), "ok");
  assert.equal(page(yt("/watch?v=zzzzzzzzzzz&list=PLcours"), p), "ok");
  assert.equal(page(yt("/watch?v=zzzzzzzzzzz"), p), "chaine");
  assert.equal(page(yt("/playlist?list=PLcours"), p), "ok");
  assert.equal(page(yt("/playlist?list=PLautre"), p), "bloque");
});

test("les resultats de recherche : seulement ce qui est approuve", () => {
  assert.equal(resultat({ video: "abcdefghijk", chaine: { nom: "Inconnue" } }, p), true);
  assert.equal(resultat({ video: "zzzzzzzzzzz", chaine: { nom: "  le jour du seigneur " } }, p), true);
  assert.equal(resultat({ video: "zzzzzzzzzzz", chaine: { id: "UCaaaaaaaaaaaaaaaaaaaaaa" } }, p), true);
  assert.equal(resultat({ video: "zzzzzzzzzzz", chaine: { nom: "5-Minute Crafts" } }, p), false);
  assert.equal(resultat({ liste: "PLcours" }, p), true);
  assert.equal(resultat({ liste: "PLautre", chaine: { nom: "Le Jour du Seigneur" } }, p), true);
  assert.equal(resultat({ liste: "PLautre", chaine: { nom: "Inconnue" } }, p), false);
  assert.equal(resultat({ chaine: { nom: "Inconnue" } }, p), false);
});

test("sans approbations, tout reste ferme", () => {
  const vide = portes(undefined);
  assert.equal(page(yt("/watch?v=abcdefghijk"), vide), "chaine");
  assert.equal(resultat({ video: "abcdefghijk", chaine: { nom: "" } }, vide), false);
});

test("les liens YouTube sont lus", () => {
  assert.deepEqual(lien("/channel/UCaaaaaaaaaaaaaaaaaaaaaa"), { video: null, liste: null, chaine: "UCaaaaaaaaaaaaaaaaaaaaaa" });
  assert.equal(lien("/watch?v=abcdefghijk&t=10").video, "abcdefghijk");
  assert.equal(lien("https://www.youtube.com/playlist?list=PLcours").liste, "PLcours");
});
