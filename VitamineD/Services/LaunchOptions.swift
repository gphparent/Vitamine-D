import Foundation

/// Options passées sur la ligne de commande au lancement.
///
/// Elles servent à produire des captures d'écran reproductibles depuis
/// l'intégration continue. Sans elles, il faudrait piloter l'interface à
/// distance et dépendre d'une position GPS simulée — deux sources de fragilité
/// pour une capture qui doit simplement montrer à quoi ressemble l'application.
///
/// Ces options sont inertes en usage normal : personne ne lance une application
/// iOS avec des arguments depuis l'écran d'accueil.
enum LaunchOptions {

    /// `-vdLieu "45.5019,-73.5674,Montréal"`
    static let locationKey = "-vdLieu"
    /// `-vdOnglet today|session|history|profile`
    static let tabKey = "-vdOnglet"

    private static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Position imposée au démarrage, si elle est fournie et bien formée.
    static var forcedLocation: ResolvedLocation? {
        guard let raw = value(for: locationKey) else { return nil }
        let parts = raw.split(separator: ",", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2,
              let latitude = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let longitude = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else { return nil }
        let name = parts.count > 2
            ? String(parts[2]).trimmingCharacters(in: .whitespaces)
            : "Position simulée"
        return ResolvedLocation(latitude: latitude, longitude: longitude,
                                altitude: 0, name: name, isManual: true)
    }

    /// Onglet à afficher au démarrage.
    static var initialTab: String? { value(for: tabKey) }
}
