// Un clic sur l'icone ouvre l'appli dans un onglet, ou ramene celui deja ouvert.
chrome.action.onClicked.addListener(async () => {
  const adresse = chrome.runtime.getURL("app.html");
  const [existant] = await chrome.tabs.query({ url: adresse });
  if (existant) {
    await chrome.tabs.update(existant.id, { active: true });
    await chrome.windows.update(existant.windowId, { focused: true });
  } else {
    await chrome.tabs.create({ url: adresse });
  }
});
