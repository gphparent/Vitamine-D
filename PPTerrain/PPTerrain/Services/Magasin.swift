import CoreLocation
import Foundation
import Observation
import UIKit

/// « Arrivé » ou « Terminé », gardé sur le iPhone tant que le serveur ne l'a pas reçu.
struct Geste: Codable, Hashable {
    enum Sorte: String, Codable { case arrivee, termine }

    let rendezVous: Int
    let sorte: Sorte
    let a: Date
    var km: Double?
    var minutes: Int?
}

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

    /// La vraie route de chaque séance confirmée d'aujourd'hui et de demain, depuis la maison ou la séance d'avant.
    private(set) var routes: [Int: Trajet] = [:]

    /// « Arrivé » et « Terminé » pas encore reçus par le serveur (sans réseau) : ils partent à la prochaine synchronisation.
    private(set) var gestes: [Geste] = []

    private let dossier: URL
    private let session: URLSession
    private let itineraires = Itineraires()

    init(dossier: URL? = nil, session: URLSession = .shared) {
        let base = dossier ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PPTerrain", isDirectory: true)
        self.dossier = base
        self.session = session
        self.connecte = Trousseau.lire() != nil
        try? FileManager.default.createDirectory(at: fichiers, withIntermediateDirectories: true)
        exclureDeLaSauvegarde()
        semaine = (try? Data(contentsOf: copie)).flatMap { try? Format.decodeur.decode(Semaine.self, from: $0) }
        gestes = (try? Data(contentsOf: fichierGestes)).flatMap { try? Format.decodeur.decode([Geste].self, from: $0) } ?? []
    }

    private var copie: URL { dossier.appendingPathComponent("semaine.json") }
    private var fichierGestes: URL { dossier.appendingPathComponent("gestes.json") }
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
        gestes = []
        routes = [:]
        connecte = false
        Task {
            await AvisDepart.programmer([])
            await Tuile.afficher(nil, jour: .now)
        }
    }

    // MARK: Synchronisation

    func synchroniser() async {
        guard let jeton = Trousseau.lire(), !enCours else { return }
        enCours = true
        defer { enCours = false }

        // Les gestes faits sans réseau d'abord : la semaine qui revient les contient alors déjà.
        await envoyerGestes(jeton: jeton)
        // Hors ligne aussi, les avis et la tuile se refont avec la copie gardée.
        defer { Task { await preparerJournee() } }

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

    // MARK: Sur le terrain

    func arrivee(de seance: RendezVous) -> Date? {
        seance.arriveAt ?? gestes.last(where: { $0.rendezVous == seance.id && $0.sorte == .arrivee })?.a
    }

    func fin(de seance: RendezVous) -> Date? {
        seance.termineAt ?? gestes.last(where: { $0.rendezVous == seance.id && $0.sorte == .termine })?.a
    }

    /// L'heure où partir pour cette séance, quand la route est connue.
    func depart(pour seance: RendezVous) -> Date? {
        guard let debut = seance.debut, let route = routes[seance.id] else { return nil }
        return Planification.depart(debut: debut, routeMinutes: route.minutes)
    }

    /// « Arrivé » : l'heure, et le trajet au carnet de kilométrage (la route depuis la maison ou la séance d'avant).
    func marquerArrivee(_ seance: RendezVous) async {
        let route = routes[seance.id]
        await ajouter(Geste(rendezVous: seance.id, sorte: .arrivee, a: .now, km: route?.km, minutes: route?.minutes))
    }

    /// « Terminé » : l'heure ; après la dernière séance de la journée, le retour à la maison part aussi au carnet.
    func marquerFin(_ seance: RendezVous) async {
        var geste = Geste(rendezVous: seance.id, sorte: .termine, a: .now)
        let journee = Planification.journee(rendezVous, le: seance.debut ?? .now)

        if journee.last?.id == seance.id, let maison = semaine?.depart, let ici = await itineraires.coordonnees(de: seance),
           let retour = await itineraires.trajet(de: ici, vers: CLLocationCoordinate2D(latitude: maison.latitude, longitude: maison.longitude)) {
            geste.km = retour.km
            geste.minutes = retour.minutes
        }

        await ajouter(geste)
    }

    private func ajouter(_ geste: Geste) async {
        gestes.append(geste)
        garderGestes()
        await preparerJournee()
        if let jeton = Trousseau.lire() { await envoyerGestes(jeton: jeton) }
    }

    private func garderGestes() {
        if let donnees = try? Format.encodeur.encode(gestes) {
            try? donnees.write(to: fichierGestes, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    /// Un à un, dans l'ordre ; le premier qui échoue faute de réseau garde les suivants pour plus tard.
    private func envoyerGestes(jeton: String) async {
        while let geste = gestes.first {
            var requete = URLRequest(url: Self.serveur.appendingPathComponent("api/terrain/rendez-vous/\(geste.rendezVous)/\(geste.sorte.rawValue)"))
            requete.httpMethod = "POST"
            requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
            requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
            requete.setValue("application/json", forHTTPHeaderField: "Accept")
            requete.timeoutInterval = 15

            var corps: [String: Any] = ["a": ISO8601DateFormatter().string(from: geste.a)]
            switch geste.sorte {
            case .arrivee:
                if let km = geste.km { corps["km"] = (km * 10).rounded() / 10 }
                if let minutes = geste.minutes { corps["minutes"] = minutes }
            case .termine:
                if let km = geste.km { corps["retour_km"] = (km * 10).rounded() / 10 }
                if let minutes = geste.minutes { corps["retour_minutes"] = minutes }
            }
            requete.httpBody = try? JSONSerialization.data(withJSONObject: corps)

            guard let resultat = try? await session.data(for: requete) else { return }
            let statut = (resultat.1 as? HTTPURLResponse)?.statusCode ?? 0
            // Réussi, ou refusé pour de bon (séance retirée) : il ne repartira pas. Le reste attend le prochain essai.
            let definitif = statut == 200 || ((400..<500).contains(statut) && statut != 401 && statut != 429)
            guard definitif else { return }
            gestes.removeFirst()
            garderGestes()
        }
    }

    /// Les routes d'aujourd'hui et de demain, les avis de départ et la tuile, refaits à chaque retour dans l'appli.
    func preparerJournee() async {
        let maintenant = Date.now
        let jours = [maintenant, Format.calendrier.date(byAdding: .day, value: 1, to: maintenant)!]
        var nouvelles: [Int: Trajet] = [:]
        var rappels: [Rappel] = []

        for jour in jours {
            let journee = Planification.journee(rendezVous, le: jour)
            var origine = semaine?.depart.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }

            for seance in journee {
                let ici = await itineraires.coordonnees(de: seance)
                if let depuis = origine, let ici, let debut = seance.debut {
                    // Partir environ une heure avant suffit pour que Plans prévoie la circulation du bon moment.
                    nouvelles[seance.id] = await itineraires.trajet(de: depuis, vers: ici, partant: debut.addingTimeInterval(-3600)) ?? routes[seance.id]
                } else if let connue = routes[seance.id] {
                    nouvelles[seance.id] = connue
                }
                origine = ici ?? origine
            }

            let faites = Set(journee.filter { arrivee(de: $0) != nil || fin(de: $0) != nil }.map(\.id))
            rappels += Planification.rappels(journee: journee, routes: nouvelles, faites: faites, maintenant: maintenant)
        }

        routes = nouvelles
        await AvisDepart.programmer(rappels, maintenant: maintenant)

        let aujourdhui = Planification.journee(rendezVous, le: maintenant)
        var arrivees: [Int: Date] = [:]
        var fins: [Int: Date] = [:]
        for seance in aujourdhui {
            arrivees[seance.id] = arrivee(de: seance)
            fins[seance.id] = fin(de: seance)
        }
        let etat = Planification.etat(journee: aujourdhui, routes: routes, arrivees: arrivees, fins: fins, maintenant: maintenant)
        await Tuile.afficher(etat, jour: maintenant)
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
