import Foundation
import Security

/// Le jeton de l'appli vit dans le trousseau du iPhone, jamais dans le dépôt : il est public.
/// Il ne quitte pas cet appareil, même par une sauvegarde iCloud.
enum Trousseau {

    private static let service = "ca.gphparent.PPTerrain"
    private static let compte = "jeton"

    static func lire() -> String? {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultat: AnyObject?
        guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
              let donnees = resultat as? Data else { return nil }
        return String(data: donnees, encoding: .utf8)
    }

    static func ecrire(_ jeton: String) {
        effacer()
        let attributs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(jeton.utf8),
        ]
        SecItemAdd(attributs as CFDictionary, nil)
    }

    static func effacer() {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte,
        ]
        SecItemDelete(requete as CFDictionary)
    }
}
