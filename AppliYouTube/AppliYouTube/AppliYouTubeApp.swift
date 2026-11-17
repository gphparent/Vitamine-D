import AVFoundation
import SwiftUI

@main
struct AppliYouTubeApp: App {

    @State private var modele = AppModel()

    /// Session audio de lecture : le son continue ecran verrouille ou appli en
    /// arriere-plan (avec le mode `audio` declare dans Info.plist).
    init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
    }

    var body: some Scene {
        WindowGroup {
            RacineView()
                .environment(modele)
                .task { await modele.demarrer() }
        }
    }
}
