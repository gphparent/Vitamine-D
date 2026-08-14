import SwiftUI

struct RootView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Tab = Tab(launchArgument: LaunchOptions.initialTab)

    /// L'accueil s'impose tant que le profil n'a pas été rempli, et se referme
    /// de lui-même dès qu'il l'est.
    private var onboarding: Binding<Bool> {
        Binding(get: { !model.profile.hasCompletedOnboarding },
                set: { showing in
                    if !showing { model.profile.hasCompletedOnboarding = true }
                })
    }

    /// Deux raisons de sortir, deux mécanismes sans rapport, deux onglets.
    ///
    /// Les mêler sur un même écran, comme le faisait la version précédente,
    /// laissait croire que la lumière du matin sert à la vitamine D. C'est le
    /// contraire : à cette heure-là le Soleil est trop bas pour le moindre UVB,
    /// et c'est justement l'horloge interne qu'elle règle.
    ///
    /// La sortie, en revanche, n'a jamais mérité son onglet : il répétait la
    /// moitié de l'écran principal — mêmes barres, même tenue, même météo — à
    /// deux endroits qui pouvaient se contredire. Elle est revenue là où la
    /// décision se prend. `session` reste accepté au lancement pour les
    /// captures d'écran de l'intégration continue, et mène à l'écran principal.
    enum Tab: Hashable {
        case today, sleep, history, profile

        init(launchArgument: String?) {
            switch launchArgument {
            case "sleep":    self = .sleep
            case "history":  self = .history
            case "profile":  self = .profile
            default:         self = .today
            }
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Vitamine D", systemImage: "sun.max") }
                .tag(Tab.today)
                .badge(model.isSessionActive ? Text("•") : nil)

            NavigationStack { CircadianView() }
                .tabItem { Label("Sommeil", systemImage: "moon.zzz") }
                .tag(Tab.sleep)

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
            // Le suivi en direct s'affiche sur l'écran principal : on y ramène
            // qui aurait démarré une sortie depuis un autre onglet.
            if active { selection = .today }
        }
        .fullScreenCover(isPresented: onboarding) { OnboardingView() }
    }
}

#Preview {
    RootView().environment(AppModel())
}
