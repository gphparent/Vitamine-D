import Foundation
import Security

/// Les cles (Anthropic, GitHub) vivent dans le trousseau de l'appareil, jamais
/// dans le depot : il est public.
enum Trousseau {

    enum Compte: String {
        case anthropic, github
    }

    private static let service = "ca.appliyoutube"

    static func lire(_ compte: Compte = .anthropic) -> String? {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var resultat: AnyObject?
        guard SecItemCopyMatching(requete as CFDictionary, &resultat) == errSecSuccess,
              let donnees = resultat as? Data else { return nil }
        return String(data: donnees, encoding: .utf8)
    }

    static func ecrire(_ cle: String, _ compte: Compte = .anthropic) {
        effacer(compte)
        let attributs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte.rawValue,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(cle.utf8),
        ]
        SecItemAdd(attributs as CFDictionary, nil)
    }

    static func effacer(_ compte: Compte = .anthropic) {
        let requete: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: compte.rawValue,
        ]
        SecItemDelete(requete as CFDictionary)
    }
}
