import SwiftUI

struct RacineView: View {

    var body: some View {
        TabView {
            FilView()
                .tabItem { Label("À voir", systemImage: "play.rectangle") }

            DemanderView()
                .tabItem { Label("Demander", systemImage: "bubble.left.and.text.bubble.right") }

            ApprouveView()
                .tabItem { Label("Approuvé", systemImage: "checkmark.shield") }

            ReglagesView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
    }
}
