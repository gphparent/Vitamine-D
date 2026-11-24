import SwiftUI

@main
struct PPTerrainApp: App {
    @State private var magasin = Magasin()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environment(magasin)
                // ppterrain://connexion?code=… : le bouton « Ouvrir PP Terrain » de l'admin.
                .onOpenURL { url in
                    guard url.scheme == "ppterrain", url.host == "connexion",
                          let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "code" })?.value
                    else { return }
                    Task { await magasin.connecter(code: code) }
                }
        }
        // Chaque retour dans l'appli, avec du réseau, met la semaine à jour.
        .onChange(of: phase) { _, nouvelle in
            if nouvelle == .active { Task { await magasin.synchroniser() } }
        }
    }
}
