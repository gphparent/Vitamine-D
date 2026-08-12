import SwiftUI

struct RootView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = Tab(launchArgument: LaunchOptions.initialTab)

    enum Tab: Hashable {
        case today, session, history, profile

        init(launchArgument: String?) {
            switch launchArgument {
            case "session":  self = .session
            case "history":  self = .history
            case "profile":  self = .profile
            default:         self = .today
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Aujourd'hui", systemImage: "sun.max") }
                .tag(Tab.today)

            SessionView()
                .tabItem { Label("Sortie", systemImage: "figure.walk") }
                .tag(Tab.session)
                .badge(model.isSessionActive ? Text("•") : nil)

            HistoryView()
                .tabItem { Label("Historique", systemImage: "chart.bar") }
                .tag(Tab.history)

            ProfileView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
        .tint(Theme.vitaminD)
        .onChange(of: model.locationService.location) { _, _ in
            model.onLocationChanged()
        }
        .onChange(of: scenePhase) { _, phase in
            // Au retour au premier plan, la prévision peut dater de plusieurs
            // heures et la position avoir changé : on remet tout à jour.
            if phase == .active {
                model.locationService.refresh()
                Task { await model.refresh() }
            }
        }
        .onChange(of: model.isSessionActive) { _, active in
            if active { selection = .session }
        }
    }
}

#Preview {
    RootView().environment(AppModel())
}
