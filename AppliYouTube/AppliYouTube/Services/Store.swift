import Foundation

/// Persistance locale. Quelques chaines, quelques videos et une conversation :
/// UserDefaults suffit. Le partage entre appareils passe par `PartageGist`.
struct Store {

    enum Cle: String {
        case chaines = "chaines.v1"
        case videos = "videos.v1"
        case echanges = "echanges.v2"
        case messagesAPI = "messages.api.v2"
        case retraits = "retraits.v1"
        case listes = "listes.v1"
        case vus = "vus.v1"
        case gistID = "gist.id.v1"
    }

    private let defaults: UserDefaults
    private let encodeur = JSONEncoder()
    private let decodeur = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func charger<T: Decodable>(_ type: T.Type, pour cle: Cle) -> T? {
        guard let donnees = defaults.data(forKey: cle.rawValue) else { return nil }
        return try? decodeur.decode(T.self, from: donnees)
    }

    func enregistrer<T: Encodable>(_ valeur: T, pour cle: Cle) {
        guard let donnees = try? encodeur.encode(valeur) else { return }
        defaults.set(donnees, forKey: cle.rawValue)
    }

    /// Pour l'historique envoye a l'API, garde tel quel : les blocs de
    /// reflexion du modele doivent revenir octet pour octet.
    func chargerBrut(_ cle: Cle) -> Data? {
        defaults.data(forKey: cle.rawValue)
    }

    func enregistrerBrut(_ donnees: Data, pour cle: Cle) {
        defaults.set(donnees, forKey: cle.rawValue)
    }

    func retirer(_ cle: Cle) {
        defaults.removeObject(forKey: cle.rawValue)
    }
}
