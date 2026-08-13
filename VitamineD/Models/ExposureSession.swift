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

    /// Ce que la journée avait déjà consommé et produit avant cette sortie.
    ///
    /// L'érythème ne se compte pas par sortie mais par journée : la peau
    /// n'oublie pas la dose du matin parce qu'on a rangé le téléphone. Deux
    /// sorties à la moitié du seuil font une rougeur, et les afficher chacune
    /// à 50 % était le plus dangereux des arrondis.
    var carriedMEDFraction: Double = 0
    var carriedVitaminDIU: Double = 0

    var vitaminDPercentOfGoal: Double = 0

    /// Capital cutané dépensé depuis le début de la journée.
    var dayMEDFraction: Double { carriedMEDFraction + medFraction }

    /// Vitamine D synthétisée depuis le début de la journée.
    var dayVitaminDIU: Double { carriedVitaminDIU + vitaminDIU }

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

    /// Niveau d'alerte, jugé sur la journée entière et non sur la seule sortie.
    func burnLevel(alertFraction: Double) -> BurnLevel {
        switch dayMEDFraction {
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
    /// - Parameter carried: charge photochimique déjà présente dans la peau au
    ///   début de la sortie, héritée des expositions précédentes. La sortie ne
    ///   repart donc pas du bas de la courbe de saturation.
    /// - Parameter carriedMED: part de la dose érythémale déjà consommée
    ///   aujourd'hui, avant cette sortie.
    /// - Parameter carriedIU: vitamine D déjà synthétisée aujourd'hui.
    static func progress(for session: ExposureSession,
                         at date: Date,
                         environment: EnvironmentFactors,
                         carried: Double = 0,
                         carriedMED: Double = 0,
                         carriedIU: Double = 0,
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
            vitaminDIU: UVEngine.saturated(rawIU: rawIU, carried: carried, profile: profileNow),
            rawVitaminDIU: rawIU,
            medFraction: medFraction,
            currentRates: lastRates,
            marginalYield: UVEngine.marginalYield(rawIU: carried + rawIU, profile: profileNow)
        )
        progress.carriedMEDFraction = carriedMED
        progress.carriedVitaminDIU = carriedIU
        progress.vitaminDPercentOfGoal = profileNow.dailyGoalIU > 0
            ? progress.dayVitaminDIU / profileNow.dailyGoalIU
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
                              carried: Double = 0,
                              carriedMED: Double = 0,
                              carriedIU: Double = 0,
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
                vitaminDIU: UVEngine.saturated(rawIU: rawIU, carried: carried, profile: profile),
                rawVitaminDIU: rawIU,
                medFraction: medFraction,
                currentRates: rates,
                marginalYield: UVEngine.marginalYield(rawIU: carried + rawIU, profile: profile))
            candidate.carriedMEDFraction = carriedMED
            candidate.carriedVitaminDIU = carriedIU
            candidate.vitaminDPercentOfGoal = profile.dailyGoalIU > 0
                ? candidate.dayVitaminDIU / profile.dailyGoalIU : 0

            if predicate(candidate) { return cursor > now ? cursor : now }
        }
        return nil
    }
}
