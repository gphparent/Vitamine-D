import Foundation

/// Persistance locale. Le volume de données est minuscule et strictement privé :
/// un fichier JSON dans le conteneur de l'application suffit, sans base de
/// données ni synchronisation réseau.
struct Store {

    enum Key: String {
        case profile = "profile.v1"
        case manualLocation = "location.manual.v1"
        case activeSession = "session.active.v1"
        case history = "session.history.v1"
        case environment = "environment.v1"
        case photosaturation = "skin.photosaturation.v1"
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Encodable>(_ value: T, for key: Key) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    func remove(_ key: Key) {
        defaults.removeObject(forKey: key.rawValue)
    }
}

/// Séance archivée, réduite à ce qui mérite d'être conservé.
struct SessionRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var start: Date
    var end: Date
    var vitaminDIU: Double
    var medFraction: Double
    var locationName: String
    var exposedBodyPercentage: Double

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var minutes: Int { Int((duration / 60).rounded()) }
}

extension Array where Element == SessionRecord {
    /// Total de vitamine D synthétisée sur une journée donnée.
    func totalIU(on day: Date, calendar: Calendar) -> Double {
        filter { calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0) { $0 + $1.vitaminDIU }
    }

    /// Capital cutané dépensé sur une journée donnée, en fractions de DEM.
    ///
    /// Les fractions s'additionnent : la dose érythémale est cumulative sur la
    /// journée, et c'est la somme qui décide de la rougeur, non le maximum.
    func totalMEDFraction(on day: Date, calendar: Calendar) -> Double {
        filter { calendar.isDate($0.start, inSameDayAs: day) }
            .reduce(0) { $0 + $1.medFraction }
    }

    /// Total sur les sept derniers jours.
    func totalIU(lastDays days: Int, from date: Date = Date()) -> Double {
        let cutoff = date.addingTimeInterval(-Double(days) * 86_400)
        return filter { $0.start >= cutoff }.reduce(0) { $0 + $1.vitaminDIU }
    }
}
