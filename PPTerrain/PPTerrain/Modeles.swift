import Foundation

/// Ce que le serveur envoie : les séances de la semaine du photographe connecté.
/// Jamais de code de porte ni d'alarme : ceux-là restent dans l'agenda du iPhone.
struct Semaine: Codable {
    let genereLe: Date
    let photographe: String?
    /// Le point de départ inscrit dans Réglages (le milieu de la rue) ; absent des copies d'avant le 25 nov.
    let depart: Point?
    let rendezVous: [RendezVous]

    struct Point: Codable, Hashable {
        let latitude: Double
        let longitude: Double
    }
}

struct RendezVous: Codable, Identifiable, Hashable {
    let id: Int
    let statut: String
    let debut: Date?
    let fin: Date?
    /// « Arrivé » et « Terminé », touchés dans la fiche.
    let arriveAt: Date?
    let termineAt: Date?
    let adresse: String?
    let unite: String?
    let ville: String?
    let latitude: Double?
    let longitude: Double?
    let googleEventId: String?
    let forfait: String?
    let ajouts: [String]
    let prix: Double?
    let precisions: String?
    let notePlanification: String?
    let client: Personne
    let proprietaire: Proprietaire?
    let surPlace: Bool?
    let quiSurPlace: String?
    let codeRecu: Bool
    let pieces: [Piece]

    struct Personne: Codable, Hashable {
        let nom: String?
        let telephone: String?
        let courriel: String?
    }

    struct Proprietaire: Codable, Hashable {
        let nom: String?
        let contact: String?
    }

    var enAttente: Bool { statut == "en_attente" }

    /// « 12 rue des Pins, app. 3, Oka »
    var lieu: String {
        var morceaux: [String] = []
        if let adresse, !adresse.isEmpty { morceaux.append(adresse) }
        if let unite, !unite.isEmpty { morceaux.append("app. \(unite)") }
        if let ville, !ville.isEmpty, !(adresse ?? "").localizedCaseInsensitiveContains(ville) { morceaux.append(ville) }
        return morceaux.isEmpty ? "Adresse à venir" : morceaux.joined(separator: ", ")
    }

    /// L'itinéraire dans Google Maps (Guillaume, 25 nov. : pas Plans). Le lien universel ouvre l'appli Google Maps,
    /// ou le navigateur quand elle n'est pas installée. Par l'adresse d'abord : Google trouve le numéro civique,
    /// alors que nos coordonnées ne sont parfois que le milieu de la rue.
    var lienPlans: URL? {
        var parties = URLComponents(string: "https://www.google.com/maps/dir/")!
        let destination: String?
        if let adresse, !adresse.isEmpty {
            destination = [adresse, ville].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        } else if let latitude, let longitude {
            destination = "\(latitude),\(longitude)"
        } else {
            destination = nil
        }
        guard let destination else { return nil }
        parties.queryItems = [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "destination", value: destination), URLQueryItem(name: "travelmode", value: "driving")]
        return parties.url
    }
}

struct Piece: Codable, Identifiable, Hashable {
    let id: Int
    let nom: String?
    let taille: Int?
    let note: String?
    let fichier: Bool
    let ajouteLe: Date?

    /// Le nom sur le disque : l'identifiant d'abord, pour qu'aucun nom de fichier ne se marche dessus.
    var nomLocal: String {
        let propre = (nom ?? "fichier").replacingOccurrences(of: "/", with: "-")
        return "\(id)-\(propre)"
    }
}

enum Format {
    static let fuseau = TimeZone(identifier: "America/Toronto")!
    static let langue = Locale(identifier: "fr_CA")

    static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = fuseau
        c.locale = langue
        return c
    }

    static let decodeur: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decodeur in
            let texte = try decodeur.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: texte) { return date }
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: texte) { return date }
            throw DecodingError.dataCorruptedError(in: try decodeur.singleValueContainer(), debugDescription: "Date illisible : \(texte)")
        }
        return d
    }()

    static let encodeur: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// « 10 h 30 »
    static func heure(_ date: Date) -> String {
        let c = calendrier.dateComponents([.hour, .minute], from: date)
        return String(format: "%d h %02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// « Aujourd'hui », « Demain », ou « jeudi 26 novembre »
    static func jour(_ date: Date, maintenant: Date = .now) -> String {
        let cal = calendrier
        if cal.isDate(date, inSameDayAs: maintenant) { return "Aujourd’hui" }
        if let demain = cal.date(byAdding: .day, value: 1, to: maintenant), cal.isDate(date, inSameDayAs: demain) { return "Demain" }
        let f = DateFormatter()
        f.locale = langue
        f.timeZone = fuseau
        f.dateFormat = "EEEE d MMMM"
        return f.string(from: date)
    }

    static func taille(_ octets: Int?) -> String? {
        guard let octets else { return nil }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(octets))
    }

    struct Journee: Identifiable {
        let jour: Date
        let seances: [RendezVous]
        var id: Date { jour }
    }

    /// Les séances regroupées par jour, dans l'ordre.
    static func parJour(_ seances: [RendezVous]) -> [Journee] {
        let cal = calendrier
        let groupes = Dictionary(grouping: seances.filter { $0.debut != nil }) { cal.startOfDay(for: $0.debut!) }
        return groupes.keys.sorted().map { jour in
            Journee(jour: jour, seances: groupes[jour]!.sorted { $0.debut! < $1.debut! })
        }
    }
}
