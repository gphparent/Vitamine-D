import { test } from "node:test";
import assert from "node:assert/strict";
import { fusion, documentVide } from "../partage.js";
import { identifiantsVideo, adressesChaine, identifiantsListe, analyserListe } from "../youtube.js";

const chaine = (id, approuveeLe) => ({ id, nom: id, approuveeLe, raison: "" });

test("la fusion reunit les approbations des deux appareils", () => {
  const iphone = { ...documentVide(), chaines: [chaine("UCa", "2026-11-01T10:00:00.000Z")] };
  const ordi = { ...documentVide(), chaines: [chaine("UCb", "2026-11-02T10:00:00.000Z")] };
  assert.deepEqual(fusion(iphone, ordi).chaines.map((c) => c.id), ["UCb", "UCa"]);
});

test("un retrait posterieur ferme la porte, meme vu d'un seul appareil", () => {
  const iphone = { ...documentVide(), chaines: [chaine("UCa", "2026-11-01T10:00:00.000Z")] };
  const ordi = { ...documentVide(), retraits: [{ id: "UCa", le: "2026-11-03T10:00:00.000Z" }] };
  const resultat = fusion(iphone, ordi);
  assert.equal(resultat.chaines.length, 0);
  assert.equal(resultat.retraits.length, 1);
});

test("une nouvelle approbation apres un retrait rouvre la porte", () => {
  const avant = { ...documentVide(), retraits: [{ id: "UCa", le: "2026-11-03T10:00:00.000Z" }] };
  const apres = { ...documentVide(), chaines: [chaine("UCa", "2026-11-05T10:00:00.000Z")] };
  assert.equal(fusion(avant, apres).chaines.length, 1);
});

test("la fusion est stable : refusionner ne change rien", () => {
  const doc = fusion(
    { ...documentVide(), chaines: [chaine("UCa", "2026-11-01T10:00:00.000Z")] },
    { ...documentVide(), retraits: [{ id: "x", le: "2026-11-01T10:00:00.000Z" }] });
  assert.deepEqual(fusion(doc, documentVide()), doc);
});

test("les liens de video sous toutes leurs formes", () => {
  const texte = `https://www.youtube.com/watch?v=dQw4w9WgXcQ https://youtu.be/abcdefghijk?t=3
    https://m.youtube.com/watch?feature=share&v=ABCDEFGHIJK youtu.be/abcdefghijk`;
  assert.deepEqual(identifiantsVideo(texte), ["dQw4w9WgXcQ", "abcdefghijk", "ABCDEFGHIJK"]);
});

test("les liens de chaine, sans confondre une video", () => {
  assert.deepEqual(adressesChaine("https://m.youtube.com/@ChaineTest"), ["https://www.youtube.com/@ChaineTest"]);
  assert.deepEqual(adressesChaine("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), []);
});

test("le dernier visionnement l'emporte, dans un sens comme dans l'autre", () => {
  const iphone = { vus: [{ id: "v", le: "2026-11-01T10:00:00.000Z", vu: true }] };
  const ordi = { vus: [{ id: "v", le: "2026-11-02T10:00:00.000Z", vu: false }] };
  assert.equal(fusion(iphone, ordi).vus[0].vu, false);
  assert.equal(fusion(ordi, iphone).vus[0].vu, false);
});

test("un document anterieur, sans listes ni vus, se complete", () => {
  const ancien = { version: 1, chaines: [chaine("UCa", "2026-11-01T10:00:00.000Z")], videos: [], retraits: [] };
  const doc = fusion(ancien, documentVide());
  assert.deepEqual(doc.listes, []);
  assert.deepEqual(doc.vus, []);
  assert.equal(doc.chaines.length, 1);
});

test("les listes de lecture, sans les Mix", () => {
  const texte = `https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf
    https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabcdefghij12345
    https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=RDdQw4w9WgXcQ`;
  assert.deepEqual(identifiantsListe(texte), ["PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", "PLabcdefghij12345"]);
});

test("la fiche d'une liste, sous les deux formes de YouTube", () => {
  const page = `<meta property="og:title" content="Cours de grec">
    <script>var ytInitialData = {"header":{"avatarStack":{"x":1},"text":{"content":"de Prof Untel"}},"contents":[
    {"lockupViewModel":{"contentId":"aaaaaaaaaaa","contentType":"LOCKUP_CONTENT_TYPE_VIDEO","metadata":{"lockupMetadataViewModel":{"title":{"content":"Leçon 1"}}}}},
    {"lockupViewModel":{"contentId":"PLzzz","contentType":"LOCKUP_CONTENT_TYPE_PLAYLIST","metadata":{"lockupMetadataViewModel":{"title":{"content":"Autre"}}}}},
    {"playlistVideoRenderer":{"videoId":"bbbbbbbbbbb","title":{"runs":[{"text":"Leçon 2"}]}}}
    ]};</script>`;
  const fiche = analyserListe(page, "PL123");
  assert.equal(fiche.titre, "Cours de grec");
  assert.equal(fiche.chaine, "Prof Untel");
  assert.deepEqual(fiche.videos, [{ id: "aaaaaaaaaaa", titre: "Leçon 1" }, { id: "bbbbbbbbbbb", titre: "Leçon 2" }]);
});
