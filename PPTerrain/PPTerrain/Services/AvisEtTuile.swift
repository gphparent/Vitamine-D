import ActivityKit
import Foundation
import UserNotifications

/// Les avis de départ programmés sur le iPhone. Chaque synchronisation les refait au complet.
enum AvisDepart {
    static let prefixe = "pp-depart-"

    static func demanderPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func programmer(_ rappels: [Rappel], maintenant: Date = .now) async {
        let centre = UNUserNotificationCenter.current()
        let anciens = await centre.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefixe) }
        centre.removePendingNotificationRequests(withIdentifiers: anciens)

        // iOS en garde 64 au plus, toutes applis confondues pour celle-ci.
        for rappel in rappels.sorted(by: { $0.quand < $1.quand }).prefix(40) {
            let delai = rappel.quand.timeIntervalSince(maintenant)
            guard delai > 1 else { continue }

            let contenu = UNMutableNotificationContent()
            contenu.title = rappel.titre
            contenu.body = rappel.corps
            contenu.sound = .default
            let demande = UNNotificationRequest(identifier: prefixe + rappel.id, content: contenu, trigger: UNTimeIntervalNotificationTrigger(timeInterval: delai, repeats: false))
            try? await centre.add(demande)
        }
    }

    /// Tout de suite et sans son : le GPS vient de noter un geste, pour qu'on sache que c'est fait.
    static func signaler(id: String, titre: String, corps: String) async {
        let contenu = UNMutableNotificationContent()
        contenu.title = titre
        contenu.body = corps
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "pp-gps-" + id, content: contenu, trigger: nil))
    }
}

/// Montre l'avis même quand l'appli est ouverte ; le toucher ouvre l'appli, qui fait alors paraître la tuile.
final class DelegueAvis: NSObject, UNUserNotificationCenterDelegate {
    static let partage = DelegueAvis()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

/// La tuile de la séance. Apple ne laisse une appli la faire paraître que lorsqu'elle est ouverte : elle paraît au
/// toucher d'un avis de départ ou à l'ouverture de l'appli, puis se met à jour seule jusqu'à la fin de la journée.
@MainActor
enum Tuile {
    static func afficher(_ etat: ActiviteSeance.ContentState?, jour: Date) async {
        let actives = Activity<ActiviteSeance>.activities

        guard let etat else {
            for activite in actives { await activite.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let contenu = ActivityContent(state: etat, staleDate: etat.cible.addingTimeInterval(2 * 3600))
        let duJour = actives.filter { Format.calendrier.isDate($0.attributes.jour, inSameDayAs: jour) }

        for vieille in actives where !duJour.contains(where: { $0.id == vieille.id }) {
            await vieille.end(nil, dismissalPolicy: .immediate)
        }

        if let active = duJour.first {
            await active.update(contenu)
            for doublon in duJour.dropFirst() { await doublon.end(nil, dismissalPolicy: .immediate) }
        } else if ActivityAuthorizationInfo().areActivitiesEnabled {
            _ = try? Activity.request(attributes: ActiviteSeance(jour: jour), content: contenu, pushType: nil)
        }
    }
}
