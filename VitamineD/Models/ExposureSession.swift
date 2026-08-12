import Foundation

/// Une sortie au soleil, en cours ou terminée.
///
/// La dose n'est pas accumulée par un minuteur qui tourne : elle est recalculée
/// à la demande en intégrant les débits sur la période écoulée. L'application
/// peut donc être mise en arrière-plan, tuée par le système ou relancée sans
/// que le compte soit faussé.
struct ExposureSession: Identifiable, Codable, Equatable, Sendable {

    /// Tranche de la sortie pendant laquelle la tenue n'a pas changé.
    struct Segment: Codable, Equatable, Sendable {
        var start: Date
        var exposure: BodyExposure
    }

    var id: UUID
    var startDate: Date
    var endDate: Date?
    var segments: [Segment]
    /// Profil au moment de la sortie, hors tenue : celle-ci vit dans les
    /// segments, puisqu'elle peut changer en cours de route.
    var profileSnapshot: UserProfile
    var locationName: String
    var latitude: Double
    var longitude: Double

    init(id: UUID = UUID(),
         startDate: Date = Date(),
         profile: UserProfile,
         location: ResolvedLocation) {
        self.id = id
        self.startDate = startDate
        self.endDate = nil
        self.segments = [Segment(start: startDate, exposure: profile.exposure)]
        self.profileSnapshot = profile
        self.locationName = location.name
        self.latitude = location.latitude
        self.longitude = location.longitude
    }

    var isActive: Bool { endDate == nil }

    func duration(at date: Date = Date()) -> TimeInterval {
        (endDate ?? date).timeIntervalSince(startDate)
    }

    /// Tenue en vigueur à un instant donné.
    func exposure(at date: Date) -> BodyExposure {
        segments.last { $0.start <= date }?.exposure ?? segments[0].exposure
    }

    /// Profil complet en vigueur à un instant donné.
    func profile(at date: Date) -> UserProfile {
        var profile = profileSnapshot
        profile.exposure = exposure(at: date)
        return profile
    }
}

/// Résultat de l'intégration d'une séance à un instant donné.
struct SessionProgress: Equatable, Sendable {
    let elapsed: TimeInterval
    /// Vitamine D synthétisée, plafond de photo-équilibre compris, en UI.
    let vitaminDIU: Double
    /// Dose brute, avant plafonnement — sert au calcul du rendement marginal.
    let rawVitaminDIU: Double
    /// Part de la dose érythémale minimale consommée, de 0 à 1.
    let medFraction: Double
    /// Débits instantanés au moment de l'évaluation.
    let currentRates: DoseRates
    /// Rendement marginal restant, de 0 à 1.
    let marginalYield: Double

    var vitaminDPercentOfGoal: Double = 0

    static let zero = SessionProgress(elapsed: 0, vitaminDIU: 0, rawVitaminDIU: 0,
                                      medFraction: 0, currentRates: .zero, marginalYield: 1)

    /// Niveau d'alerte cutanée.
    enum BurnLevel: Int, Comparable, Sendable {
        case safe, caution, warning, danger

        static func < (lhs: BurnLevel, rhs: BurnLevel) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .safe:    return "Sécuritaire"
            case .caution: return "Surveiller"
            case .warning: return "Rentrer bientôt"
            case .danger:  return "Rentrer maintenant"
            }
        }
    }

    func burnLevel(alertFraction: Double) -> BurnLevel {
        switch medFraction {
        case ..<(alertFraction * 0.6):  return .safe
        case ..<alertFraction:          return .caution
        case ..<(alertFraction * 1.35): return .warning
        default:                        return .danger
        }
    }
}

/// Intègre les débits de dose sur la durée d'une séance.
enum SessionIntegrator {

    /// Pas d'intégration. Une minute est largement suffisante : l'indice UV
    /// varie de quelques pour cent au plus sur cet intervalle.
    static let step: TimeInterval = 60

    /// Progression de la séance à l'instant `date`.
    ///
    /// - Parameter uvIndexAt: fournit l'indice UV à un instant donné, en général
    ///   par interpolation de la prévision horaire.
    static func progress(for session: ExposureSession,
                         at date: Date,
                         environment: EnvironmentFactors,
                         uvIndexAt: (Date) -> Double) -> SessionProgress {

        let end = min(date, session.endDate ?? date)
        guard end > session.startDate else { return .zero }

        var rawIU = 0.0
        var medFraction = 0.0
        var cursor = session.startDate
        var lastRates = DoseRates.zero

        while cursor < end {
            let slice = min(step, end.timeIntervalSince(cursor))
            let midpoint = cursor.addingTimeInterval(slice / 2)
            let profile = session.profile(at: midpoint)
            let position = SolarCalculator.position(date: midpoint,
                                                    latitude: session.latitude,
                                                    longitude: session.longitude)
            let rates = UVEngine.rates(profile: profile,
                                       uvIndex: uvIndexAt(midpoint),
                                       solarElevation: position.elevation,
                                       environment: environment)
            let minutes = slice / 60
            rawIU += rates.vitaminDIUPerMinute * minutes
            medFraction += rates.medFractionPerMinute * minutes
            lastRates = rates
            cursor = cursor.addingTimeInterval(slice)
        }

        let profileNow = session.profile(at: end)
        var progress = SessionProgress(
            elapsed: end.timeIntervalSince(session.startDate),
            vitaminDIU: UVEngine.saturated(rawIU: rawIU, profile: profileNow),
            rawVitaminDIU: rawIU,
            medFraction: medFraction,
            currentRates: lastRates,
            marginalYield: UVEngine.marginalYield(rawIU: rawIU, profile: profileNow)
        )
        progress.vitaminDPercentOfGoal = profileNow.dailyGoalIU > 0
            ? progress.vitaminDIU / profileNow.dailyGoalIU
            : 0
        return progress
    }

    /// Instant projeté auquel une grandeur atteindra un seuil, en poursuivant la
    /// séance dans les conditions prévues.
    ///
    /// Sert à programmer les notifications dès le début de la sortie : le
    /// système les délivre même si l'application n'est plus en mémoire.
    static func projectedDate(for session: ExposureSession,
                              from now: Date,
                              environment: EnvironmentFactors,
                              horizon: TimeInterval = 4 * 3600,
                              uvIndexAt: (Date) -> Double,
                              reaching predicate: (SessionProgress) -> Bool) -> Date? {

        var rawIU = 0.0
        var medFraction = 0.0
        var cursor = session.startDate
        let limit = now.addingTimeInterval(horizon)

        while cursor < limit {
            let midpoint = cursor.addingTimeInterval(step / 2)
            let profile = session.profile(at: midpoint)
            let position = SolarCalculator.position(date: midpoint,
                                                    latitude: session.latitude,
                                                    longitude: session.longitude)
            let rates = UVEngine.rates(profile: profile,
                                       uvIndex: uvIndexAt(midpoint),
                                       solarElevation: position.elevation,
                                       environment: environment)
            rawIU += rates.vitaminDIUPerMinute * (step / 60)
            medFraction += rates.medFractionPerMinute * (step / 60)
            cursor = cursor.addingTimeInterval(step)

            var candidate = SessionProgress(
                elapsed: cursor.timeIntervalSince(session.startDate),
                vitaminDIU: UVEngine.saturated(rawIU: rawIU, profile: profile),
                rawVitaminDIU: rawIU,
                medFraction: medFraction,
                currentRates: rates,
                marginalYield: UVEngine.marginalYield(rawIU: rawIU, profile: profile))
            candidate.vitaminDPercentOfGoal = profile.dailyGoalIU > 0
                ? candidate.vitaminDIU / profile.dailyGoalIU : 0

            if predicate(candidate) { return cursor > now ? cursor : now }
        }
        return nil
    }
}
