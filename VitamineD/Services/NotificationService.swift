import Foundation
import Observation
import UserNotifications

/// Programmation des alertes locales.
///
/// Toutes les alertes de séance sont calculées et déposées auprès du système au
/// moment où la sortie commence. Elles se déclenchent donc même si
/// l'application est déchargée de la mémoire, ce qui est le cas normal quand on
/// range son téléphone dans sa poche pour aller marcher.
@MainActor
@Observable
final class NotificationService {

    enum Identifier {
        static let sessionGoal = "session.goal"
        static let sessionCaution = "session.caution"
        static let sessionStop = "session.stop"
        static let dailyPlan = "daily.plan"
        static let windowOpening = "window.opening"

        static let allSession = [sessionGoal, sessionCaution, sessionStop]
    }

    private(set) var authorisationStatus: UNAuthorizationStatus = .notDetermined

    private let centre = UNUserNotificationCenter.current()

    func refreshAuthorisationStatus() async {
        authorisationStatus = await centre.notificationSettings().authorizationStatus
    }

    @discardableResult
    func requestAuthorisation() async -> Bool {
        do {
            let granted = try await centre.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorisationStatus()
            return granted
        } catch {
            await refreshAuthorisationStatus()
            return false
        }
    }

    // MARK: - Alertes de séance

    /// Dépose les alertes d'une sortie qui commence.
    /// - Parameter carried: charge photochimique de la peau au début de la
    ///   sortie ; - Parameter carriedMED et carriedIU : ce que la journée avait
    ///   déjà dépensé et produit avant elle.
    func scheduleSessionAlerts(session: ExposureSession,
                               environment: EnvironmentFactors,
                               carried: Double = 0,
                               carriedMED: Double = 0,
                               carriedIU: Double = 0,
                               uvIndexAt: @Sendable (Date) -> Double) async {
        cancelSessionAlerts()
        guard authorisationStatus == .authorized || authorisationStatus == .provisional else { return }

        let now = Date()
        let profile = session.profileSnapshot
        let goal = profile.dailyGoalIU
        let alertFraction = profile.burnAlertFraction
        let stopFraction = min(0.9, alertFraction * 1.35)

        // Toutes les échéances se jugent sur la journée entière : la peau ne
        // distingue pas les sorties, et deux demi-doses font une rougeur.
        if let goalDate = SessionIntegrator.projectedDate(
            for: session, from: now, environment: environment,
            carried: carried, carriedMED: carriedMED, carriedIU: carriedIU,
            uvIndexAt: uvIndexAt,
            reaching: { $0.dayVitaminDIU >= goal }) {
            schedule(
                identifier: Identifier.sessionGoal,
                title: "Objectif atteint",
                body: "Vous avez synthétisé vos \(Int(goal)) UI de vitamine D. "
                    + "Rester plus longtemps n'ajoute presque rien, mais continue d'user la peau.",
                at: goalDate,
                sound: .default)
        }

        if let cautionDate = SessionIntegrator.projectedDate(
            for: session, from: now, environment: environment,
            carried: carried, carriedMED: carriedMED, carriedIU: carriedIU,
            uvIndexAt: uvIndexAt,
            reaching: { $0.dayMEDFraction >= alertFraction }) {
            schedule(
                identifier: Identifier.sessionCaution,
                title: "Couvrez-vous bientôt",
                body: "Vous êtes à \(Int(alertFraction * 100)) % de votre seuil d'érythème. "
                    + "Cherchez l'ombre ou remettez un vêtement.",
                at: cautionDate,
                sound: .default)
        }

        if let stopDate = SessionIntegrator.projectedDate(
            for: session, from: now, environment: environment,
            carried: carried, carriedMED: carriedMED, carriedIU: carriedIU,
            uvIndexAt: uvIndexAt,
            reaching: { $0.dayMEDFraction >= stopFraction }) {
            schedule(
                identifier: Identifier.sessionStop,
                title: "Rentrez maintenant",
                body: "Risque de coup de soleil. À ce rythme, la rougeur apparaîtra "
                    + "dans les prochaines minutes.",
                at: stopDate,
                sound: .default)
        }
    }

    func cancelSessionAlerts() {
        centre.removePendingNotificationRequests(withIdentifiers: Identifier.allSession)
    }

    // MARK: - Alertes du jour

    /// Notification matinale annonçant le meilleur créneau de la journée.
    func scheduleDailyPlan(minuteOfDay: Int, plan: DayPlan?) {
        centre.removePendingNotificationRequests(withIdentifiers: [Identifier.dailyPlan])
        guard authorisationStatus == .authorized || authorisationStatus == .provisional else { return }

        let content = UNMutableNotificationContent()
        content.title = "Votre fenêtre du jour"
        content.sound = .default

        if let plan {
            if plan.isVitaminDWinter {
                content.body = "Le Soleil ne montera pas assez haut aujourd'hui : "
                    + "aucune synthèse cutanée possible. Pensez à votre supplément."
            } else if let best = plan.bestRecommendation {
                let formatter = DateFormatter()
                formatter.timeZone = plan.timeZone
                formatter.dateFormat = "HH:mm"
                content.body = "Meilleur moment : \(formatter.string(from: best.start)) — "
                    + "\(best.minutes) min pour \(Int(best.expectedIU)) UI."
            } else {
                content.body = "Conditions défavorables aujourd'hui. Ouvrez l'application pour le détail."
            }
        } else {
            content.body = "Ouvrez l'application pour connaître votre meilleur créneau."
        }

        var components = DateComponents()
        components.hour = minuteOfDay / 60
        components.minute = minuteOfDay % 60

        let request = UNNotificationRequest(
            identifier: Identifier.dailyPlan,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true))
        centre.add(request)
    }

    /// Alerte au moment où le Soleil franchit la hauteur à partir de laquelle les
    /// UVB traversent l'atmosphère en quantité utile.
    func scheduleWindowOpening(at date: Date, elevation: Double, uvIndex: Double) {
        centre.removePendingNotificationRequests(withIdentifiers: [Identifier.windowOpening])
        guard authorisationStatus == .authorized || authorisationStatus == .provisional else { return }
        guard date > Date().addingTimeInterval(60) else { return }

        schedule(
            identifier: Identifier.windowOpening,
            title: "La fenêtre UVB s'ouvre",
            body: String(format: "Le Soleil passe %.0f° de hauteur, indice UV %.1f. "
                         + "Votre ombre est maintenant plus courte que vous : c'est le moment.",
                         elevation, uvIndex),
            at: date,
            sound: .default)
    }

    func cancelAll() {
        centre.removeAllPendingNotificationRequests()
    }

    // MARK: - Utilitaire

    private func schedule(identifier: String, title: String, body: String,
                          at date: Date, sound: UNNotificationSound) {
        let delay = date.timeIntervalSinceNow
        guard delay > 5 else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = sound
        content.interruptionLevel = identifier == Identifier.sessionStop ? .timeSensitive : .active

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
        centre.add(request)
    }
}
