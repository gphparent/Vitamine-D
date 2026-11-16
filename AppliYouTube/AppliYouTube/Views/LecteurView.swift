import SwiftUI
import WebKit

/// Le lecteur integre officiel de YouTube, dans une vue web qui ne mene nulle
/// part ailleurs : pas de suggestions d'autres chaines, pas de lien vers
/// l'appli YouTube, pas de nouvel onglet.
///
/// Avec `listeID`, il joue la liste et reste a l'interieur de celle-ci. Il
/// signale chaque video regardee a 90 % ou jusqu'au bout.
struct LecteurView: View {

    @Environment(AppModel.self) private var modele

    var videoID: String? = nil
    var listeID: String? = nil
    let titre: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LecteurWeb(videoID: videoID, listeID: listeID) { vue in
                modele.marquer(vue, vue: true)
            }
            .aspectRatio(16 / 9, contentMode: .fit)
            .background(.black)

            Text(titre)
                .font(.headline)
                .padding(.horizontal)

            if let videoID {
                let vue = modele.estVue(videoID)
                Button {
                    modele.marquer(videoID, vue: !vue)
                } label: {
                    Label(vue ? "Remettre à voir" : "Marquer comme vue",
                          systemImage: vue ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
                .buttonStyle(.bordered)
                .padding(.horizontal)
            }
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LecteurWeb: UIViewRepresentable {

    let videoID: String?
    let listeID: String?
    let surVue: (String) -> Void

    /// L'origine declaree au lecteur. YouTube refuse de lire une video integree
    /// dont la page hote n'a pas d'origine identifiable (erreur 153), et n'envoie
    /// ses messages de progression qu'a cette origine.
    static let origine = "https://ca.appliyoutube"

    func makeCoordinator() -> Gardien { Gardien() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "vue")
        let vue = WKWebView(frame: .zero, configuration: configuration)
        vue.navigationDelegate = context.coordinator
        vue.uiDelegate = context.coordinator
        vue.scrollView.isScrollEnabled = false
        vue.isOpaque = false
        vue.backgroundColor = .black
        return vue
    }

    static func dismantleUIView(_ vue: WKWebView, coordinator: Gardien) {
        vue.configuration.userContentController.removeScriptMessageHandler(forName: "vue")
    }

    func updateUIView(_ vue: WKWebView, context: Context) {
        context.coordinator.surVue = surVue
        let cle = "\(videoID ?? "")|\(listeID ?? "")"
        guard context.coordinator.charge != cle else { return }
        context.coordinator.charge = cle

        // `rel=0` limite les suggestions de fin a la meme chaine ; le gardien
        // empeche de toute facon d'en ouvrir une. `enablejsapi` fait parler le
        // lecteur : c'est ainsi qu'on sait ce qui a ete vu.
        var parametres = "playsinline=1&rel=0&modestbranding=1&iv_load_policy=3&enablejsapi=1&origin=\(Self.origine)"
        if let listeID { parametres += "&list=\(listeID)" }
        let chemin = videoID ?? "videoseries"
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
        </head><body>
        <iframe id="lecteur" src="https://www.youtube-nocookie.com/embed/\(chemin)?\(parametres)"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin"></iframe>
        <script>\(Self.suivi)</script>
        </body></html>
        """
        vue.loadHTMLString(html, baseURL: URL(string: Self.origine))
    }

    /// Le protocole de messages du lecteur integre, celui qu'emploie l'API
    /// iframe de YouTube : on s'annonce, il repond par des `infoDelivery`
    /// (position, duree, video en cours, etat). Pas de script externe a charger.
    static let suivi = """
    const cadre = document.getElementById('lecteur');
    const s = { id: null, t: 0, d: 0, signale: null, entendu: false };
    const ecouter = () => cadre.contentWindow.postMessage(JSON.stringify({ event: 'listening', id: 1, channel: 'widget' }), '*');
    const relance = setInterval(() => { if (s.entendu) clearInterval(relance); else ecouter(); }, 1000);
    cadre.addEventListener('load', ecouter);
    window.addEventListener('message', (e) => {
      if (!/youtube/.test(e.origin)) return;
      let m; try { m = JSON.parse(e.data); } catch { return; }
      s.entendu = true;
      const info = m.info ?? {};
      if (m.event === 'infoDelivery') {
        if (info.videoData?.video_id && info.videoData.video_id !== s.id) { s.id = info.videoData.video_id; s.t = 0; s.d = 0; }
        if (typeof info.currentTime === 'number') s.t = info.currentTime;
        if (typeof info.duration === 'number' && info.duration > 0) s.d = info.duration;
      }
      const etat = m.event === 'onStateChange' ? info : info.playerState;
      if (s.id && s.id !== s.signale && ((s.d > 0 && s.t / s.d >= 0.9) || etat === 0)) {
        s.signale = s.id;
        window.webkit.messageHandlers.vue.postMessage(s.id);
      }
    });
    """

    final class Gardien: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {

        var charge: String?
        var surVue: (String) -> Void = { _ in }

        func userContentController(_ controleur: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let id = message.body as? String, id.count == 11 else { return }
            surVue(id)
        }

        /// La page hote ne quitte jamais sa propre origine. Ce qui se passe dans
        /// le cadre du lecteur est laisse a YouTube ; tout clic qui tenterait
        /// d'emmener la page entiere ailleurs est annule.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            let principal = action.targetFrame?.isMainFrame ?? true
            let hote = action.request.url.map { $0.absoluteString.hasPrefix(LecteurWeb.origine) } ?? false
            decisionHandler(!principal || hote || action.request.url?.scheme == "about" ? .allow : .cancel)
        }

        /// « Regarder sur YouTube » et les liens qui ouvrent un nouvel onglet :
        /// refuses.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }
    }
}
