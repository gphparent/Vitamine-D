import Foundation

/// Approbations partagees entre l'iPhone et les ordis, par un Gist GitHub
/// secret. Meme format et meme fusion que `extension-brave/partage.js`.
///
/// Un retrait est garde comme une pierre tombale : sans lui, un appareil qui
/// n'a pas encore vu le retrait remettrait l'element a la prochaine fusion.
struct DocumentPartage: Codable, Equatable {
    var version = 1
    var chaines: [Chaine] = []
    var videos: [VideoApprouvee] = []
    var retraits: [Retrait] = []

    /// Garde, pour chaque identifiant, la plus recente approbation, puis
    /// retire ce qu'un retrait posterieur a ferme.
    static func fusion(_ a: DocumentPartage, _ b: DocumentPartage) -> DocumentPartage {
        var retraits: [String: Retrait] = [:]
        for r in a.retraits + b.retraits where (retraits[r.id]?.le ?? .distantPast) < r.le {
            retraits[r.id] = r
        }
        func garder<T: Identifiable<String>>(_ liste: [T], date: (T) -> Date) -> [T] {
            var parId: [String: T] = [:]
            for e in liste where parId[e.id].map({ date($0) < date(e) }) ?? true {
                parId[e.id] = e
            }
            return parId.values
                .filter { e in !(retraits[e.id].map { $0.le >= date(e) } ?? false) }
                .sorted { date($0) > date($1) }
        }
        return DocumentPartage(
            chaines: garder(a.chaines + b.chaines, date: \.approuveeLe),
            videos: garder(a.videos + b.videos, date: \.approuveeLe),
            retraits: retraits.values.sorted { $0.id < $1.id })
    }

    /// Dates en ISO 8601 a la milliseconde, comme `toISOString()` cote
    /// extension : les deux cotes comparent les memes chaines.
    static let encodeur: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .custom { date, encodeur in
            var c = encodeur.singleValueContainer()
            try c.encode(formatDate.string(from: date))
        }
        return e
    }()

    static let decodeur: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decodeur in
            let texte = try decodeur.singleValueContainer().decode(String.self)
            if let date = formatDate.date(from: texte) ?? formatSansFraction.date(from: texte) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(codingPath: decodeur.codingPath,
                                                    debugDescription: "Date illisible : \(texte)"))
        }
        return d
    }()

    private static let formatDate: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let formatSansFraction = ISO8601DateFormatter()
}

struct Retrait: Codable, Hashable {
    let id: String
    let le: Date
}

/// Lecture et ecriture du Gist. Le Gist est retrouve par sa description : un
/// seul jeton suffit a configurer un nouvel appareil.
struct PartageGist {

    enum Erreur: LocalizedError {
        case jetonRefuse, http(Int)
        var errorDescription: String? {
            switch self {
            case .jetonRefuse: "Jeton GitHub refusé : il doit avoir l'accès en lecture et écriture aux Gists."
            case .http(let code): "GitHub a répondu \(code)."
            }
        }
    }

    static let description = "Appli YouTube — approbations partagées"
    static let fichier = "approbations.json"

    let jeton: String
    var session: URLSession = .shared

    func synchroniser(_ local: DocumentPartage, gistID: String?) async throws -> (DocumentPartage, String) {
        let id: String
        if let gistID { id = gistID } else { id = try await trouverOuCreer(local) }

        let gist = try await appel("/gists/\(id)")
        var distant = DocumentPartage()
        if let fichier = (gist["files"] as? [String: Any])?[Self.fichier] as? [String: Any] {
            var contenu = fichier["content"] as? String ?? ""
            if fichier["truncated"] as? Bool == true, let brut = (fichier["raw_url"] as? String).flatMap({ URL(string: $0) }) {
                contenu = String(decoding: try await session.data(from: brut).0, as: UTF8.self)
            }
            // Un document abime est simplement reecrit.
            distant = (try? DocumentPartage.decodeur.decode(DocumentPartage.self, from: Data(contenu.utf8))) ?? distant
        }

        // Comparaison sur le texte encode : les dates y sont arrondies a la
        // milliseconde, comme dans le Gist.
        let fusionne = DocumentPartage.fusion(local, distant)
        let contenu = String(decoding: try DocumentPartage.encodeur.encode(fusionne), as: UTF8.self)
        let actuel = try DocumentPartage.encodeur.encode(DocumentPartage.fusion(distant, DocumentPartage()))
        if contenu != String(decoding: actuel, as: UTF8.self) {
            _ = try await appel("/gists/\(id)", methode: "PATCH",
                                corps: ["files": [Self.fichier: ["content": contenu]]])
        }
        return (fusionne, id)
    }

    private func trouverOuCreer(_ local: DocumentPartage) async throws -> String {
        for page in 1...5 {
            let liste = try await appelListe("/gists?per_page=100&page=\(page)")
            if let trouve = liste.first(where: { $0["description"] as? String == Self.description }),
               let id = trouve["id"] as? String {
                return id
            }
            if liste.count < 100 { break }
        }
        let contenu = String(decoding: try DocumentPartage.encodeur.encode(local), as: UTF8.self)
        let cree = try await appel("/gists", methode: "POST", corps: [
            "description": Self.description,
            "public": false,
            "files": [Self.fichier: ["content": contenu]],
        ])
        guard let id = cree["id"] as? String else { throw Erreur.http(0) }
        return id
    }

    private func appel(_ chemin: String, methode: String = "GET", corps: [String: Any]? = nil) async throws -> [String: Any] {
        let donnees = try await requete(chemin, methode: methode, corps: corps)
        return (try JSONSerialization.jsonObject(with: donnees) as? [String: Any]) ?? [:]
    }

    private func appelListe(_ chemin: String) async throws -> [[String: Any]] {
        let donnees = try await requete(chemin, methode: "GET", corps: nil)
        return (try JSONSerialization.jsonObject(with: donnees) as? [[String: Any]]) ?? []
    }

    private func requete(_ chemin: String, methode: String, corps: [String: Any]?) async throws -> Data {
        var requete = URLRequest(url: URL(string: "https://api.github.com\(chemin)")!)
        requete.httpMethod = methode
        requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        requete.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        requete.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let corps {
            requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
            requete.httpBody = try JSONSerialization.data(withJSONObject: corps)
        }
        let (donnees, reponse) = try await session.data(for: requete)
        let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 || code == 403 { throw Erreur.jetonRefuse }
        guard (200..<300).contains(code) else { throw Erreur.http(code) }
        return donnees
    }
}
