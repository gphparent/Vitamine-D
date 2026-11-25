import CoreLocation
import UIKit

/// L'arrivée et la fin notées par le GPS (Guillaume, 25 nov.) : iOS surveille un cercle de 150 m autour de chaque
/// séance d'aujourd'hui et de demain, et réveille l'appli, même fermée, quand le iPhone y entre ou en sort.
/// Le iPhone ne garde ni n'envoie aucune position : seulement l'heure, comme les boutons « Arrivé » et « Terminé ».
@MainActor
final class Presence: NSObject, CLLocationManagerDelegate {
    static let partage = Presence()

    nonisolated static let prefixe = "pp-seance-"
    /// Assez large pour un grand terrain et l'imprécision du GPS, assez petit pour ne pas couvrir le voisin.
    static let rayon: CLLocationDistance = 150
    /// iOS en surveille 20 au plus par appli.
    static let maximum = 18

    private let gestionnaire = CLLocationManager()

    /// Créé au lancement de l'appli : c'est ce qui reçoit l'entrée ou la sortie quand iOS la relance en arrière-plan.
    override init() {
        super.init()
        gestionnaire.delegate = self
    }

    /// « Toujours » : sans elle, iOS ne réveille pas l'appli fermée. Accordée « pendant l'utilisation », iOS
    /// propose lui-même « Toujours » plus tard.
    func demanderPermission() {
        switch gestionnaire.authorizationStatus {
        case .notDetermined, .authorizedWhenInUse: gestionnaire.requestAlwaysAuthorization()
        default: break
        }
    }

    /// Les cercles voulus remplacent les anciens ; une séance terminée n'en a plus.
    func surveiller(_ lieux: [(id: Int, centre: CLLocationCoordinate2D)]) {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else { return }

        let voulus = lieux.prefix(Self.maximum).map { (identifiant: Self.prefixe + String($0.id), centre: $0.centre) }
        let noms = Set(voulus.map(\.identifiant))

        for region in gestionnaire.monitoredRegions where region.identifier.hasPrefix(Self.prefixe) && !noms.contains(region.identifier) {
            gestionnaire.stopMonitoring(for: region)
        }

        for voulu in voulus {
            if let deja = gestionnaire.monitoredRegions.first(where: { $0.identifier == voulu.identifiant }) as? CLCircularRegion,
               abs(deja.center.latitude - voulu.centre.latitude) < 0.00001, abs(deja.center.longitude - voulu.centre.longitude) < 0.00001 {
                // Déjà là : on demande seulement si le iPhone y est en ce moment.
                gestionnaire.requestState(for: deja)
                continue
            }
            let cercle = CLCircularRegion(center: voulu.centre, radius: Self.rayon, identifier: voulu.identifiant)
            cercle.notifyOnEntry = true
            cercle.notifyOnExit = true
            gestionnaire.startMonitoring(for: cercle)
        }
    }

    private nonisolated static func seance(_ region: CLRegion) -> Int? {
        guard region.identifier.hasPrefix(prefixe) else { return nil }
        return Int(region.identifier.dropFirst(prefixe.count))
    }

    /// Le temps d'envoyer au serveur quand iOS a réveillé l'appli pour l'occasion.
    private func enArrierePlan(_ travail: () async -> Void) async {
        let tache = UIApplication.shared.beginBackgroundTask(withName: "pp-presence")
        await travail()
        if tache != .invalid { UIApplication.shared.endBackgroundTask(tache) }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didStartMonitoringFor region: CLRegion) {
        // Déjà sur place quand le cercle se pose (appli ouverte en arrivant) : compte comme une entrée.
        manager.requestState(for: region)
    }

    /// Appelé à chaque entrée, et en réponse à requestState : c'est ici que l'arrivée se note.
    nonisolated func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        guard state == .inside, let id = Self.seance(region) else { return }
        Task { @MainActor in
            await self.enArrierePlan { await Magasin.partage.entree(id) }
        }
    }

    /// Seule une vraie sortie note la fin ; un « dehors » répondu à requestState la noterait en retard.
    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard let id = Self.seance(region) else { return }
        Task { @MainActor in
            await self.enArrierePlan { await Magasin.partage.sortie(id) }
        }
    }
}
