import AppIntents

/// Les boutons « Arrivé » et « Terminé » de la tuile (Guillaume, 25 nov.), pour le jour où le GPS manque son coup.
/// iOS exécute le geste dans l'appli, réveillée en arrière-plan ; l'extension qui dessine la tuile (TUILE) ne fait
/// que le déclarer.
struct GesteTuile: LiveActivityIntent {
    static let title: LocalizedStringResource = "Geste de la séance"
    static let isDiscoverable = false

    @Parameter(title: "Séance") var seance: Int
    @Parameter(title: "Terminé") var termine: Bool

    init() {}

    init(seance: Int, termine: Bool) {
        self.seance = seance
        self.termine = termine
    }

    func perform() async throws -> some IntentResult {
        #if !TUILE
        await Magasin.partage.toucher(seance: seance, termine: termine)
        #endif
        return .result()
    }
}
