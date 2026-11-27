import Foundation

/// Ce que le serveur envoie : les séances de la semaine du photographe connecté.
/// Jamais de code de porte ni d'alarme : ceux-là restent dans l'agenda du iPhone.
struct Semaine: Codable {
    let genereLe: Date
    let photographe: String?
    /// Le point de départ inscrit dans Réglages (le milieu de la rue) ; absent des copies d'avant le 25 nov.
    let depart: Point?
    /// Du lundi de cette semaine à la fin de la suivante (depuis le 25 nov.) ; la liste ne montre qu'à partir d'aujourd'hui.
    let rendezVous: [RendezVous]
    /// Absentes des copies d'avant le 25 nov.
    let taches: Taches?
    /// Le mois en cours, pour qui voit l'argent seulement (27 nov.) ; sinon absent, et l'onglet aussi.
    let finances: Finances?

    struct Point: Codable, Hashable {
        let latitude: Double
        let longitude: Double
    }
}

/// Ses séances faites dans le mois, facturées ou non, et la part qui lui revient, avant taxes (Guillaume, 27 nov.).
/// Un aperçu, à revoir quand QuickBooks fera les factures.
struct Finances: Codable, Hashable {
    let mois: String
    let total: Double
    let nombre: Int
    /// Séances dont la part n'est pas encore connue (pourcentage pas inscrit) : hors du total.
    let aRegler: Int?
    let factures: [Facture]

    struct Facture: Codable, Identifiable, Hashable {
        let id: Int
        let le: Date
        let client: String?
        let adresse: String?
        let ville: String?
        let photographe: String?
        /// Sa part ; nil tant qu'elle n'est pas connue.
        let montant: Double?
        /// « À facturer », « Facturée » ou « Payée ».
        let etat: String
    }
}

/// Ce qui attend le photographe après ses séances (Guillaume, 25 nov.), comme « Mes tâches » de l'admin.
/// Jamais la facture ni le paiement : c'est la coordination.
struct Taches: Codable, Hashable {
    let photos: [PhotosAEnvoyer]
    let retouches: [Retouche]
    let equipe: [DeLaCoordination]

    var nombre: Int { photos.count + retouches.count + equipe.count }

    struct PhotosAEnvoyer: Codable, Identifiable, Hashable {
        let id: Int
        let debut: Date?
        let adresse: String?
        let ville: String?
        let forfait: String?
        /// Téléversées, HDR, retouchées, plan… selon le forfait.
        let etapes: [Etape]

        var faites: Int { etapes.filter(\.faite).count }
    }

    struct Etape: Codable, Hashable {
        let cle: String
        let nom: String
        let faite: Bool
    }

    struct Retouche: Codable, Identifiable, Hashable {
        let id: Int
        let adresse: String?
        let ville: String?
        let soumiseAt: Date?
        let message: String?
        let photos: [Photo]

        struct Photo: Codable, Hashable {
            let nom: String?
            let note: String?
        }
    }

    struct DeLaCoordination: Codable, Identifiable, Hashable {
        let id: Int
        let titre: String
        let details: String?
        /// « 2026-11-26 »
        let echeance: String?

        var jour: Date? {
            guard let echeance else { return nil }
            let f = DateFormatter()
            f.timeZone = Format.fuseau
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: echeance)
        }

        func enRetard(maintenant: Date = .now) -> Bool {
            guard let jour else { return false }
            return jour < Format.calendrier.startOfDay(for: maintenant)
        }
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

    /// Le lundi de la semaine de cette date, à minuit.
    static func lundi(de date: Date) -> Date {
        let cal = calendrier
        let jour = cal.startOfDay(for: date)
        // weekday : 1 = dimanche, 2 = lundi…
        let recul = (cal.component(.weekday, from: jour) + 5) % 7
        return cal.date(byAdding: .day, value: -recul, to: jour)!
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
