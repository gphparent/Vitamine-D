import { synchroniser, documentVide, fusion } from "./partage.js";

// Un clic sur l'icone ouvre l'appli dans un onglet, ou ramene celui deja ouvert.
async function ouvrirAppli() {
  const adresse = chrome.runtime.getURL("app.html");
  const [existant] = await chrome.tabs.query({ url: adresse });
  if (existant) {
    await chrome.tabs.update(existant.id, { active: true });
    await chrome.windows.update(existant.windowId, { focused: true });
  } else {
    await chrome.tabs.create({ url: adresse });
  }
}
chrome.action.onClicked.addListener(ouvrirAppli);

// Le gardien du site YouTube a besoin des approbations a jour meme quand
// l'appli n'est pas ouverte : synchronisation au demarrage et aux 15 minutes.
async function synchroniserEnFond() {
  const { approbations, jetonGitHub, gistID } = await chrome.storage.local.get(["approbations", "jetonGitHub", "gistID"]);
  if (!jetonGitHub) return;
  try {
    const resultat = await synchroniser(fusion(approbations ?? documentVide(), documentVide()), jetonGitHub, gistID ?? null);
    await chrome.storage.local.set({ approbations: resultat.document, gistID: resultat.gistID });
  } catch { /* on reessaiera au prochain tour */ }
}
chrome.runtime.onStartup.addListener(synchroniserEnFond);
chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create("synchroniser", { periodInMinutes: 15 });
  synchroniserEnFond();
});
chrome.alarms.onAlarm.addListener((alarme) => {
  if (alarme.name === "synchroniser") synchroniserEnFond();
});

// Messages du gardien de youtube.com.
chrome.runtime.onMessage.addListener((message) => {
  if (message?.type === "ouvrir") ouvrirAppli();
  if (message?.type === "vue" && /^[\w-]{11}$/.test(message.id)) marquerVue(message.id);
});

async function marquerVue(id) {
  const { approbations } = await chrome.storage.local.get("approbations");
  const vus = [{ id, le: new Date().toISOString(), vu: true }];
  await chrome.storage.local.set({ approbations: fusion(approbations ?? documentVide(), { vus }) });
  await synchroniserEnFond();
}
