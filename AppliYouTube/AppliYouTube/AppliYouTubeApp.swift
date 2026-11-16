import SwiftUI

@main
struct AppliYouTubeApp: App {

    @State private var modele = AppModel()

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environment(modele)
                .task { await modele.demarrer() }
        }
    }
}
