import SwiftUI
import UserNotifications

@main
struct PPTerrainApp: App {
    @State private var magasin = Magasin.partage
    @Environment(\.scenePhase) private var phase

    init() {
        UNUserNotificationCenter.current().delegate = DelegueAvis.partage
        // Relancée en arrière-plan par le GPS, l'appli doit avoir de quoi recevoir l'entrée ou la sortie.
        _ = Presence.partage
    }

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
        // Chaque retour dans l'appli, avec du réseau, met la semaine à jour ; puis les avis de départ et la tuile.
        .onChange(of: phase) { _, nouvelle in
            guard nouvelle == .active else { return }
            Task {
                if magasin.connecte {
                    await AvisDepart.demanderPermission()
                    Presence.partage.demanderPermission()
                }
                await magasin.synchroniser()
            }
        }
    }
}
