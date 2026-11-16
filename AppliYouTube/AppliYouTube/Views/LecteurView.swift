import SwiftUI
import WebKit

/// Le lecteur integre officiel de YouTube, dans une vue web qui ne mene nulle
/// part ailleurs : pas de suggestions d'autres chaines, pas de lien vers
/// l'appli YouTube, pas de nouvel onglet.
struct LecteurView: View {

    let videoID: String
    let titre: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LecteurWeb(videoID: videoID)
                .aspectRatio(16 / 9, contentMode: .fit)
                .background(.black)
            Text(titre)
                .font(.headline)
                .padding(.horizontal)
            Spacer()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct LecteurWeb: UIViewRepresentable {

    let videoID: String

    /// L'origine declaree au lecteur. YouTube refuse de lire une video integree
    /// dont la page hote n'a pas d'origine identifiable (erreur 153).
    static let origine = "https://ca.appliyoutube"

    func makeCoordinator() -> Gardien { Gardien() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let vue = WKWebView(frame: .zero, configuration: configuration)
        vue.navigationDelegate = context.coordinator
        vue.uiDelegate = context.coordinator
        vue.scrollView.isScrollEnabled = false
        vue.isOpaque = false
        vue.backgroundColor = .black
        return vue
    }

    func updateUIView(_ vue: WKWebView, context: Context) {
        guard context.coordinator.charge != videoID else { return }
        context.coordinator.charge = videoID
        // `rel=0` limite les suggestions de fin a la meme chaine ; le gardien
        // empeche de toute facon d'en ouvrir une.
        let parametres = "playsinline=1&rel=0&modestbranding=1&iv_load_policy=3&origin=\(Self.origine)"
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000}iframe{border:0;width:100%;height:100%}</style>
        </head><body>
        <iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?\(parametres)"
          allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
          referrerpolicy="strict-origin-when-cross-origin"></iframe>
        </body></html>
        """
        vue.loadHTMLString(html, baseURL: URL(string: Self.origine))
    }

    final class Gardien: NSObject, WKNavigationDelegate, WKUIDelegate {

        var charge: String?

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
