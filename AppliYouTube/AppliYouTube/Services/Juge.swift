import Foundation

/// Le juge : Claude, par l'API Messages. Il n'existe pas de SDK Anthropic
/// officiel pour Swift, d'ou l'appel HTTP direct.
///
/// Les criteres vivent dans le depot, et nulle part dans l'appli : les
/// changer exige un commit et un nouveau build TestFlight. C'est voulu. Un
/// reglage modifiable dans l'appli se contourne en dix secondes un soir de
/// faiblesse ; un commit, non.
struct Juge {

    struct Decision {
        let reponse: String
        let verdict: Verdict
        let videoID: String
        let chaineID: String
        let listeID: String
        /// Le contenu brut de la reponse, a renvoyer tel quel au tour suivant.
        let contenuBrut: Any
    }

    enum Erreur: LocalizedError {
        case pasDeCle, cleRefusee, surcharge, refus, illisible
        case http(Int, String)

        var errorDescription: String? {
            switch self {
            case .pasDeCle: "Ajoute ta clé d'API Anthropic dans Réglages."
            case .cleRefusee: "La clé d'API Anthropic est refusée. Vérifie-la dans Réglages."
            case .surcharge: "Le juge est surchargé. Réessaie dans une minute."
            case .refus: "Le juge a décliné cette demande."
            case .illisible: "Réponse du juge illisible. Réessaie."
            case .http(let code, let message): "Erreur \(code) : \(message)"
            }
        }
    }

    static let modele = "claude-opus-5-5"

    /// Lues dans `Resources/consignes.txt`, le meme fichier que l'extension
    /// Brave : un seul juge, quel que soit l'appareil.
    static let consignes: String = {
        guard let url = Bundle.main.url(forResource: "consignes", withExtension: "txt"),
              let texte = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("consignes.txt manque au paquet de l'appli")
        }
        return texte
    }()

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "reponse": ["type": "string", "description": "Ce que tu réponds à l'utilisateur."],
            "verdict": ["type": "string",
                        "enum": ["approuve_video", "approuve_chaine", "approuve_liste", "refuse", "discussion"]],
            "video_id": ["type": "string"],
            "chaine_id": ["type": "string"],
            "liste_id": ["type": "string"],
        ],
        "required": ["reponse", "verdict", "video_id", "chaine_id", "liste_id"],
        "additionalProperties": false,
    ]

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// `historique` est la suite des messages deja echanges, au format de
    /// l'API, et `nouveau` le message utilisateur a ajouter. L'historique
    /// n'est jamais reecrit : on ne fait qu'y ajouter, sans quoi les blocs de
    /// reflexion des tours precedents seraient refuses.
    func juger(historique: [Any], nouveau: [String: Any]) async throws -> Decision {
        guard let cle = Trousseau.lire(), !cle.isEmpty else { throw Erreur.pasDeCle }

        var requete = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        requete.httpMethod = "POST"
        requete.timeoutInterval = 180
        requete.setValue("application/json", forHTTPHeaderField: "content-type")
        requete.setValue(cle, forHTTPHeaderField: "x-api-key")
        requete.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        // Si un filtre de securite declinait la demande, l'API la relance
        // d'elle-meme sur le modele de repli recommande.
        requete.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let corps: [String: Any] = [
            "model": Self.modele,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": Self.consignes,
            "output_config": [
                "effort": "medium",
                "format": ["type": "json_schema", "schema": Self.schema],
            ],
            "messages": historique + [nouveau as Any],
        ]
        requete.httpBody = try JSONSerialization.data(withJSONObject: corps)

        let (donnees, reponse) = try await session.data(for: requete)
        let code = (reponse as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: donnees) as? [String: Any]

        switch code {
        case 200: break
        case 401, 403: throw Erreur.cleRefusee
        case 429, 500...: throw Erreur.surcharge
        default:
            let message = (json?["error"] as? [String: Any])?["message"] as? String ?? ""
            throw Erreur.http(code, message)
        }

        guard let json, let contenu = json["content"] as? [[String: Any]] else {
            throw Erreur.illisible
        }
        if json["stop_reason"] as? String == "refusal" { throw Erreur.refus }

        let texte = contenu
            .filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard let sortie = try? JSONSerialization.jsonObject(with: Data(texte.utf8)) as? [String: Any],
              let reponseTexte = sortie["reponse"] as? String,
              let verdict = (sortie["verdict"] as? String).flatMap(Verdict.init(rawValue:))
        else { throw Erreur.illisible }

        return Decision(
            reponse: reponseTexte,
            verdict: verdict,
            videoID: sortie["video_id"] as? String ?? "",
            chaineID: sortie["chaine_id"] as? String ?? "",
            listeID: sortie["liste_id"] as? String ?? "",
            contenuBrut: contenu)
    }
}
