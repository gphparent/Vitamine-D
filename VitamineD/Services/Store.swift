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
///
/// Plusieurs champs sont facultatifs, et pour la même raison : les
/// enregistrements des versions antérieures ne les portent pas, et un champ
/// obligatoire les rendrait illisibles. Un historique est la seule chose de
/// cette application qui ne se reconstitue pas — le perdre à une mise à jour
/// serait impardonnable.
struct SessionRecord: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var start: Date
    var end: Date
    var vitaminDIU: Double
    var medFraction: Double
    var locationName: String
    var exposedBodyPercentage: Double
    /// Indice UV moyen de la sortie.
    var averageUVIndex: Double?

    /// Dose **brute**, avant plafond de photo-équilibre.
    ///
    /// C'est elle, et non la dose plafonnée, que la peau porte réellement. La
    /// conserver rend la charge photochimique reconstructible à partir du seul
    /// historique : sans elle, corriger une sortie laissait la charge figée sur
    /// une valeur qui ne correspondait plus à rien.
    var rawVitaminDIU: Double?

    /// Coordonnées du lieu, pour pouvoir recalculer la course du Soleil si la
    /// sortie est corrigée après coup. Le nom seul n'y suffit pas.
    var latitude: Double?
    var longitude: Double?

    /// Sortie saisie ou corrigée à la main, plutôt que chronométrée.
    ///
    /// La distinction se voit à l'écran. Une sortie reconstituée repose sur un
    /// indice UV modélisé et sur une tenue déclarée de mémoire : elle vaut
    /// moins qu'une mesure, et l'application n'a pas à faire semblant du
    /// contraire.
    var isRetroactive: Bool

    init(id: UUID = UUID(),
         start: Date,
         end: Date,
         vitaminDIU: Double,
         medFraction: Double,
         locationName: String,
         exposedBodyPercentage: Double,
         averageUVIndex: Double? = nil,
         rawVitaminDIU: Double? = nil,
         latitude: Double? = nil,
         longitude: Double? = nil,
         isRetroactive: Bool = false) {
        self.id = id
        self.start = start
        self.end = end
        self.vitaminDIU = vitaminDIU
        self.medFraction = medFraction
        self.locationName = locationName
        self.exposedBodyPercentage = exposedBodyPercentage
        self.averageUVIndex = averageUVIndex
        self.rawVitaminDIU = rawVitaminDIU
        self.latitude = latitude
        self.longitude = longitude
        self.isRetroactive = isRetroactive
    }

    /// Chaque champ est relu séparément : l'ajout d'un champ obligatoire ne
    /// doit jamais rendre tout un historique indéchiffrable.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        vitaminDIU = (try? c.decode(Double.self, forKey: .vitaminDIU)) ?? 0
        medFraction = (try? c.decode(Double.self, forKey: .medFraction)) ?? 0
        locationName = (try? c.decode(String.self, forKey: .locationName)) ?? "—"
        exposedBodyPercentage =
            (try? c.decode(Double.self, forKey: .exposedBodyPercentage)) ?? 0
        averageUVIndex = try? c.decodeIfPresent(Double.self, forKey: .averageUVIndex)
        rawVitaminDIU = try? c.decodeIfPresent(Double.self, forKey: .rawVitaminDIU)
        latitude = try? c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try? c.decodeIfPresent(Double.self, forKey: .longitude)
        isRetroactive = (try? c.decode(Bool.self, forKey: .isRetroactive)) ?? false
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var minutes: Int { Int((duration / 60).rounded()) }

    /// Dose brute portée par cette sortie.
    ///
    /// À défaut d'avoir été enregistrée — sorties d'avant l'ajout du champ — on
    /// retient la dose plafonnée, qui lui est toujours inférieure. La charge
    /// reconstituée est donc sous-estimée pour ces sorties-là, ce qui pousse à
    /// annoncer un rendement plus élevé qu'il ne l'est. L'erreur n'excède
    /// jamais la part que le plafond avait retranchée, et elle s'efface en un
    /// jour ou deux avec la décroissance.
    var rawOrSaturatedIU: Double { rawVitaminDIU ?? vitaminDIU }
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
