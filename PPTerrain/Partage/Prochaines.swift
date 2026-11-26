import Foundation
import Security
import WidgetKit

/// Une séance telle que la montre le widget « Prochaine séance » : la ville et les heures seulement, comme la tuile,
/// parce que l'écran de l'auto se lit par-dessus l'épaule.
struct ProchaineSeance: Codable, Hashable {
    var ville: String
    var debut: Date
    var fin: Date
    var depart: Date?
}

/// Le widget « Prochaine séance » (Guillaume, 26 nov.), sur l'écran d'accueil et dans CarPlay, qui affiche de lui-même
/// les petits widgets. L'appli y dépose ses séances à venir par un groupe du trousseau partagé avec l'extension : un
/// groupe d'applis demanderait un réglage de plus chez Apple. Le jeton reste dans le groupe de l'appli seule.
enum Prochaines {
    static let genre = "PPTerrainProchaine"
    private static let service = "ca.gphparent.PPTerrain.prochaines"
    private static let compte = "seances"

    /// « ÉQUIPE.ca.gphparent.PPTerrain.partage », écrit dans l'Info.plist de l'appli et de l'extension à la compilation.
    /// Sans équipe devant (compilation sans signature, comme au simulateur des tests), rien ne se dépose.
    private static var groupe: String? {
        guard let valeur = Bundle.main.object(forInfoDictionaryKey: "GroupeTrousseau") as? String,
              !valeur.hasPrefix("ca."), !valeur.hasPrefix("."), !valeur.contains("$") else { return nil }
        return valeur
    }

    /// La séance à montrer à ce moment : la première qui n'est pas finie.
    static func aMontrer(_ seances: [ProchaineSeance], a moment: Date) -> ProchaineSeance? {
        seances.sorted { $0.debut < $1.debut }.first { $0.fin > moment }
    }

    /// Les moments où le widget change : maintenant, puis le début et la fin de chaque séance à venir.
    static func moments(_ seances: [ProchaineSeance], depuis: Date) -> [Date] {
        let suivants = seances.flatMap { [$0.debut, $0.fin] }.filter { $0 > depuis }
        return [depuis] + Array(Set(suivants)).sorted()
    }

    #if !TUILE
    /// Refait au complet à chaque préparation de la journée ; le widget ne se redessine que si quelque chose a changé.
    static func deposer(_ seances: [ProchaineSeance]) {
        guard let groupe, let donnees = try? JSONEncoder().encode(seances) else { return }
        if lire() == seances { return }

        let cle: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
            kSecAttrAccessGroup as String: groupe,
        ]
        SecItemDelete(cle as CFDictionary)
        var attributs = cle
        // Lisible iPhone verrouillé : CarPlay sert surtout le téléphone dans la poche.
        attributs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributs[kSecValueData as String] = donnees
        SecItemAdd(attributs as CFDictionary, nil)

        WidgetCenter.shared.reloadTimelines(ofKind: genre)
    }
    #endif

    static func lire() -> [ProchaineSeance]? {
        guard let groupe else { return nil }
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
            kSecAttrAccessGroup as String: groupe,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultat: AnyObject?
        guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
              let donnees = resultat as? Data else { return nil }
        return try? JSONDecoder().decode([ProchaineSeance].self, from: donnees)
    }
}
