import ActivityKit
import Foundation

/// Activité en direct : la sortie reste affichée sur l'écran verrouillé et
/// dans l'île dynamique, avec son décompte.
///
/// L'intérêt n'est pas cosmétique. Une sortie au soleil est précisément le
/// moment où l'on ne regarde pas son téléphone : le compte à rebours doit
/// vivre là où un coup d'œil suffit, sans déverrouiller ni ouvrir quoi que ce
/// soit. Le décompte lui-même est dessiné par `Text(timerInterval:)`, qui
/// s'anime tout seul — l'application n'a donc pas à réveiller le système
/// chaque seconde pour faire avancer des chiffres.
@MainActor
final class LiveActivityService {

    /// Fréquence minimale entre deux mises à jour poussées au système.
    ///
    /// ActivityKit accorde un budget de mises à jour ; les rafraîchir chaque
    /// seconde le consommerait pour rien, puisque le décompte s'anime seul.
    /// Une demi-minute suffit à faire bouger les doses affichées.
    private static let minimumInterval: TimeInterval = 30

    private var lastPush: Date?

    private var activity: Activity<SunSessionAttributes>?

    /// L'utilisateur a-t-il laissé les activités en direct autorisées ?
    var isAvailable: Bool {
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var isRunning: Bool {
        return activity != nil
    }

    /// Une mise à jour serait-elle acceptée maintenant ?
    ///
    /// L'appelant s'en sert pour ne pas calculer un état qu'il jetterait :
    /// projeter l'heure d'arrêt suppose de resimuler la sortie, ce qui ne se
    /// fait pas chaque seconde pour rien.
    var isDue: Bool {
        guard activity != nil else { return false }
        guard let lastPush else { return true }
        return Date().timeIntervalSince(lastPush) >= Self.minimumInterval
    }

    // MARK: - Cycle de vie

    func start(locationName: String,
               exposedBodyPercentage: Double,
               startedAt: Date,
               state: SunSessionAttributes.ContentState) {
        guard isAvailable, activity == nil else { return }

        let attributes = SunSessionAttributes(
            startedAt: startedAt,
            locationName: locationName,
            exposedBodyPercentage: exposedBodyPercentage)

        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: staleDate(for: state)),
            pushType: nil)
        lastPush = Date()
    }

    /// Pousse un nouvel état, en respectant l'intervalle minimal.
    ///
    /// `force` sert aux changements que l'utilisateur vient de provoquer — un
    /// changement de tenue, par exemple — où attendre serait déroutant.
    func update(_ state: SunSessionAttributes.ContentState, force: Bool = false) {
        guard let activity else { return }

        let now = Date()
        if !force, let lastPush, now.timeIntervalSince(lastPush) < Self.minimumInterval {
            return
        }
        lastPush = now

        let content = ActivityContent(state: state, staleDate: staleDate(for: state))
        Task { await activity.update(content) }
    }

    func end(with state: SunSessionAttributes.ContentState? = nil) {
        guard let activity else { return }
        self.activity = nil
        lastPush = nil

        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }

    /// Reprend la main sur une activité survivante, ou la congédie.
    ///
    /// Une activité en direct survit à la fermeture de l'application, et c'est
    /// tout son intérêt : la sortie continue même quand le téléphone est rangé
    /// dans une poche. Au redémarrage, il faut donc distinguer deux cas — la
    /// sortie est toujours en cours et l'on récupère la poignée, ou elle est
    /// finie et l'écran verrouillé garderait sinon un décompte orphelin qui ne
    /// bouge plus.
    func adopt(sessionIsActive: Bool) {
        for existing in Activity<SunSessionAttributes>.activities {
            if sessionIsActive, activity == nil {
                activity = existing
                lastPush = nil
            } else if existing.id != activity?.id {
                Task { await existing.end(nil, dismissalPolicy: .immediate) }
            }
        }
    }

    // MARK: - Détails

    /// Au-delà de cet instant, le système grise l'affichage : les chiffres
    /// montrés ne sont plus dignes de confiance. On le place un peu après la
    /// prochaine mise à jour attendue, ou à l'heure d'arrêt si elle est proche.
    private func staleDate(for state: SunSessionAttributes.ContentState) -> Date {
        let horizon = Date().addingTimeInterval(4 * Self.minimumInterval)
        guard let stopAt = state.stopAt else { return horizon }
        return min(horizon, stopAt.addingTimeInterval(60))
    }
}
