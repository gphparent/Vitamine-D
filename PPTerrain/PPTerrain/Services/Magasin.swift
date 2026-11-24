import Foundation
import Observation
import UIKit

/// La semaine et ses fichiers, gardés sur le iPhone pour les endroits sans réseau.
/// Chaque synchronisation remplace tout : ce que le serveur ne liste plus s'efface d'ici aussi.
@MainActor
@Observable
final class Magasin {

    static let serveur = URL(string: "https://reserver.parentphotographe.com")!

    private(set) var semaine: Semaine?
    private(set) var enCours = false
    private(set) var erreur: String?
    private(set) var connecte: Bool

    private let dossier: URL
    private let session: URLSession

    init(dossier: URL? = nil, session: URLSession = .shared) {
        let base = dossier ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PPTerrain", isDirectory: true)
        self.dossier = base
        self.session = session
        self.connecte = Trousseau.lire() != nil
        try? FileManager.default.createDirectory(at: fichiers, withIntermediateDirectories: true)
        exclureDeLaSauvegarde()
        semaine = (try? Data(contentsOf: copie)).flatMap { try? Format.decodeur.decode(Semaine.self, from: $0) }
    }

    private var copie: URL { dossier.appendingPathComponent("semaine.json") }
    private var fichiers: URL { dossier.appendingPathComponent("fichiers", isDirectory: true) }

    var rendezVous: [RendezVous] { semaine?.rendezVous ?? [] }

    /// Le fichier sur le téléphone, s'il est déjà téléchargé.
    func local(_ piece: Piece) -> URL? {
        let url = fichiers.appendingPathComponent(piece.nomLocal)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: Connexion

    /// Le code du bouton « Ouvrir PP Terrain » de l'admin, échangé une fois contre le jeton de cet iPhone.
    func connecter(code: String) async {
        erreur = nil
        var requete = URLRequest(url: Self.serveur.appendingPathComponent("api/terrain/connexion"))
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue("application/json", forHTTPHeaderField: "Accept")
        requete.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "appareil": UIDevice.current.name])

        do {
            let (donnees, reponse) = try await session.data(for: requete)
            let corps = (try? JSONSerialization.jsonObject(with: donnees)) as? [String: Any]
            guard (reponse as? HTTPURLResponse)?.statusCode == 200, let jeton = corps?["jeton"] as? String else {
                erreur = (corps?["message"] as? String) ?? "La connexion a échoué. Recommencez depuis l’admin."
                return
            }
            Trousseau.ecrire(jeton)
            connecte = true
            await synchroniser()
        } catch {
            erreur = "Pas de réseau. Réessayez quand vous en aurez."
        }
    }

    func deconnecter() async {
        if let jeton = Trousseau.lire() {
            var requete = URLRequest(url: Self.serveur.appendingPathComponent("api/terrain/deconnexion"))
            requete.httpMethod = "POST"
            requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
            requete.setValue("application/json", forHTTPHeaderField: "Accept")
            _ = try? await session.data(for: requete)
        }
        oublier()
    }

    /// Tout ce que l'appli garde part avec le jeton.
    private func oublier() {
        Trousseau.effacer()
        try? FileManager.default.removeItem(at: dossier)
        try? FileManager.default.createDirectory(at: fichiers, withIntermediateDirectories: true)
        semaine = nil
        connecte = false
    }

    // MARK: Synchronisation

    func synchroniser() async {
        guard let jeton = Trousseau.lire(), !enCours else { return }
        enCours = true
        defer { enCours = false }

        var requete = URLRequest(url: Self.serveur.appendingPathComponent("api/terrain/rendez-vous"))
        requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        requete.setValue("application/json", forHTTPHeaderField: "Accept")
        requete.timeoutInterval = 20

        do {
            let (donnees, reponse) = try await session.data(for: requete)
            let statut = (reponse as? HTTPURLResponse)?.statusCode ?? 0

            if statut == 401 {
                oublier()
                erreur = "Cet iPhone a été déconnecté. Reconnectez-le depuis l’admin."
                return
            }
            guard statut == 200 else {
                erreur = "Le serveur ne répond pas comme prévu (\(statut)). Ce qui est déjà ici reste disponible."
                return
            }

            let nouvelle = try Format.decodeur.decode(Semaine.self, from: donnees)
            try donnees.write(to: copie, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            semaine = nouvelle
            erreur = nil
            await telechargerFichiers(nouvelle, jeton: jeton)
        } catch is DecodingError {
            erreur = "La réponse du serveur est illisible. Mettez l’appli à jour dans TestFlight."
        } catch {
            erreur = "Hors ligne. Vous voyez la dernière copie."
        }
    }

    private func telechargerFichiers(_ semaine: Semaine, jeton: String) async {
        let voulus = semaine.rendezVous.flatMap(\.pieces).filter(\.fichier)
        let noms = Set(voulus.map(\.nomLocal))

        // Ce qui n'est plus dans la semaine s'efface.
        for url in (try? FileManager.default.contentsOfDirectory(at: fichiers, includingPropertiesForKeys: nil)) ?? [] where !noms.contains(url.lastPathComponent) {
            try? FileManager.default.removeItem(at: url)
        }

        for piece in voulus where local(piece) == nil {
            var requete = URLRequest(url: Self.serveur.appendingPathComponent("api/terrain/pieces/\(piece.id)"))
            requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
            guard let resultat = try? await session.download(for: requete),
                  (resultat.1 as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let cible = fichiers.appendingPathComponent(piece.nomLocal)
            try? FileManager.default.moveItem(at: resultat.0, to: cible)
        }
    }

    private func exclureDeLaSauvegarde() {
        var url = dossier
        var valeurs = URLResourceValues()
        valeurs.isExcludedFromBackup = true
        try? url.setResourceValues(valeurs)
    }
}
