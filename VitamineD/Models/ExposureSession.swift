import Foundation

/// Moitié du corps tournée vers le Soleil.
///
/// Debout ou en marche, la question ne se pose pas : le corps pivote, et la
/// peau découverte se traite comme une seule pièce. Couché, elle se pose
/// entièrement — la moitié qui regarde le ciel prend toute la dose, l'autre
/// n'en prend aucune.
///
/// La distinction n'est pas cosmétique, parce que les deux comptes de
/// l'application ne se comportent pas de la même façon. L'érythème est **local** :
/// il s'accumule sur un morceau de peau donné, et le morceau qui vient
/// d'arriver au Soleil part de zéro. La vitamine D, elle, est **systémique** :
/// c'est la même molécule dans le même sang, d'où qu'elle vienne, et le total
/// continue de monter.
///
/// D'où le geste : se retourner ne remet aucun compteur à zéro, il en ouvre un
/// second. À vitamine D égale, le capital cutané dépensé sur la moitié la plus
/// exposée est deux fois moindre.
enum BodySide: Int, Codable, CaseIterable, Identifiable, Sendable {
    /// Debout, assis, en mouvement : toute la peau découverte compte.
    case whole
    /// Couché sur le dos : le ventre au Soleil.
    case front
    /// Couché sur le ventre : le dos au Soleil.
    case back

    var id: Int { rawValue }

    /// Part de la surface découverte réellement tournée vers le Soleil.
    ///
    /// Couché, c'est une moitié. Le débit de synthèse est donc divisé par deux
    /// — pas celui de l'érythème, qui ne dépend pas de la surface exposée mais
    /// de l'éclairement reçu par la peau qui l'est.
    var illuminatedShare: Double { self == .whole ? 1 : 0.5 }

    var isLyingDown: Bool { self != .whole }

    var title: String {
        switch self {
        case .whole: return "Debout"
        case .front: return "Ventre au Soleil"
        case .back:  return "Dos au Soleil"
        }
    }

    var shortTitle: String {
        switch self {
        case .whole: return "Debout"
        case .front: return "Ventre"
        case .back:  return "Dos"
        }
    }

    var symbolName: String {
        switch self {
        case .whole: return "figure.stand"
        case .front: return "figure.wave"
        case .back:  return "figure.flexibility"
        }
    }

    /// L'autre face. Se relever depuis une position couchée demande un choix
    /// explicite, pas un retournement.
    var flipped: BodySide {
        switch self {
        case .whole: return .front
        case .front: return .back
        case .back:  return .front
        }
    }
}

/// Dose accumulée, ventilée selon la moitié du corps qui l'a reçue.
///
/// Deux conventions cohabitent ici, et les confondre serait une faute de
/// physique. Ce qui est reçu debout vaut pour toute la peau découverte, mais
/// pas de la même manière selon le compte :
///
/// - côté érythème, **chaque moitié en prend la totalité** : c'est un
///   éclairement par unité de surface, et il ne se partage pas ;
/// - côté vitamine D, **chaque moitié en fabrique la moitié** : c'est une
///   quantité de molécules, et elle se partage.
struct SidedDose: Equatable, Sendable {
    /// Reçu debout, donc par toute la peau découverte.
    var whole = 0.0
    /// Reçu couché sur le dos.
    var front = 0.0
    /// Reçu couché sur le ventre.
    var back = 0.0

    mutating func add(_ amount: Double, facing side: BodySide) {
        switch side {
        case .whole: whole += amount
        case .front: front += amount
        case .back:  back += amount
        }
    }

    /// Dose érythémale portée par une moitié : la sienne, plus tout ce qui a
    /// été pris debout.
    func erythemal(of side: BodySide) -> Double {
        switch side {
        case .whole: return worstErythemal
        case .front: return whole + front
        case .back:  return whole + back
        }
    }

    /// Dose de la moitié la plus exposée — celle qui rougira la première, et
    /// donc la seule qui doive déclencher une alerte.
    var worstErythemal: Double { whole + max(front, back) }

    /// Dose brute de vitamine D produite par une moitié : la sienne, plus la
    /// moitié de ce qui a été produit debout.
    func synthetic(of side: BodySide) -> Double {
        switch side {
        case .whole: return whole / 2
        case .front: return whole / 2 + front
        case .back:  return whole / 2 + back
        }
    }

    /// Produit par le corps entier.
    var total: Double { whole + front + back }
}

/// Une sortie au soleil, en cours ou terminée.
///
/// La dose n'est pas accumulée par un minuteur qui tourne : elle est recalculée
/// à la demande en intégrant les débits sur la période écoulée. L'application
/// peut donc être mise en arrière-plan, tuée par le système ou relancée sans
/// que le compte soit faussé.
struct ExposureSession: Identifiable, Codable, Equatable, Sendable {

    /// Tranche de la sortie pendant laquelle ni la tenue ni la position n'ont
    /// changé.
    struct Segment: Codable, Equatable, Sendable {
        var start: Date
        var exposure: BodyExposure
        /// Moitié du corps tournée vers le Soleil pendant cette tranche.
        var side: BodySide

        init(start: Date, exposure: BodyExposure, side: BodySide = .whole) {
            self.start = start
            self.exposure = exposure
            self.side = side
        }

        /// Une sortie enregistrée par une version antérieure n'a pas de face :
        /// elle s'est faite debout, par définition.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            start = try container.decode(Date.self, forKey: .start)
            exposure = try container.decode(BodyExposure.self, forKey: .exposure)
            side = (try? container.decodeIfPresent(BodySide.self, forKey: .side)) ?? .whole
        }
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

    /// Face présentée au Soleil à un instant donné.
    func side(at date: Date) -> BodySide {
        segments.last { $0.start <= date }?.side ?? .whole
    }

    /// Face présentée en ce moment.
    var currentSide: BodySide { segments.last?.side ?? .whole }

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

    /// Capital cutané ventilé par moitié du corps. `medFraction` en est la
    /// valeur la plus haute — la moitié qui rougira la première.
    var medBySide = SidedDose()
    /// Face présentée au Soleil en ce moment.
    var currentSide: BodySide = .whole

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

        var raw = SidedDose()
        var med = SidedDose()
        var cursor = session.startDate
        var lastRates = DoseRates.zero

        while cursor < end {
            let slice = min(step, end.timeIntervalSince(cursor))
            let midpoint = cursor.addingTimeInterval(slice / 2)
            let profile = session.profile(at: midpoint)
            let side = session.side(at: midpoint)
            let position = SolarCalculator.position(date: midpoint,
                                                    latitude: session.latitude,
                                                    longitude: session.longitude)
            let rates = UVEngine.rates(profile: profile,
                                       uvIndex: uvIndexAt(midpoint),
                                       solarElevation: position.elevation,
                                       environment: environment,
                                       illuminatedShare: side.illuminatedShare)
            let minutes = slice / 60
            raw.add(rates.vitaminDIUPerMinute * minutes, facing: side)
            med.add(rates.medFractionPerMinute * minutes, facing: side)
            lastRates = rates
            cursor = cursor.addingTimeInterval(slice)
        }

        let profileNow = session.profile(at: end)
        let currentSide = session.side(at: end)

        var progress = SessionProgress(
            elapsed: end.timeIntervalSince(session.startDate),
            vitaminDIU: synthesised(raw: raw, carried: carried, profile: profileNow),
            rawVitaminDIU: raw.total,
            // La moitié la plus chargée : c'est elle qui rougira, et une
            // moyenne des deux masquerait exactement ce qu'il faut voir.
            medFraction: med.worstErythemal,
            currentRates: lastRates,
            marginalYield: marginalYield(raw: raw, carried: carried,
                                         profile: profileNow, side: currentSide)
        )
        progress.carriedMEDFraction = carriedMED
        progress.carriedVitaminDIU = carriedIU
        progress.medBySide = med
        progress.currentSide = currentSide
        progress.vitaminDPercentOfGoal = profileNow.dailyGoalIU > 0
            ? progress.dayVitaminDIU / profileNow.dailyGoalIU
            : 0
        return progress
    }

    // MARK: - Saturation, moitié par moitié

    /// Le photo-équilibre s'installe dans un morceau de peau, pas dans un
    /// corps. Chaque moitié suit donc sa propre courbe, avec la moitié du
    /// plafond, et l'on additionne ce que les deux ont produit.
    ///
    /// Une sortie passée entièrement debout redonne exactement la formule
    /// d'origine : les deux moitiés y portent la même charge, et deux demi-
    /// plafonds à demi-charge valent un plafond entier à charge entière.
    /// C'est en se retournant que les chemins divergent — et c'est tout
    /// l'intérêt du geste, puisque la moitié fraîche repart au plein
    /// rendement.
    private static func synthesised(raw: SidedDose,
                                    carried: Double,
                                    profile: UserProfile) -> Double {
        let half = UVEngine.synthesisCeiling(profile: profile) / 2
        // La charge héritée des sorties précédentes se partage : on ne sait
        // plus dans quelle position elles ont été faites.
        let inherited = max(0, carried) / 2
        let base = UVEngine.saturated(rawIU: inherited, ceiling: half)

        return [BodySide.front, .back].reduce(0.0) { total, side in
            total + UVEngine.saturated(rawIU: inherited + raw.synthetic(of: side),
                                       ceiling: half) - base
        }
    }

    /// Rendement de la moitié actuellement présentée au Soleil : c'est celle
    /// dont dépend la minute suivante.
    private static func marginalYield(raw: SidedDose,
                                      carried: Double,
                                      profile: UserProfile,
                                      side: BodySide) -> Double {
        let half = UVEngine.synthesisCeiling(profile: profile) / 2
        let inherited = max(0, carried) / 2
        // Debout, les deux moitiés portent la même charge : l'une vaut l'autre.
        let presented = side == .whole ? BodySide.front : side
        return UVEngine.marginalYield(rawIU: inherited + raw.synthetic(of: presented),
                                      ceiling: half)
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

        var raw = SidedDose()
        var med = SidedDose()
        var cursor = session.startDate
        let limit = now.addingTimeInterval(horizon)

        while cursor < limit {
            let midpoint = cursor.addingTimeInterval(step / 2)
            let profile = session.profile(at: midpoint)
            // Au-delà du dernier segment, la projection suppose que rien ne
            // change : ni la tenue, ni la position. Un retournement à venir ne
            // se devine pas — c'est lui qui, le moment venu, fera reprogrammer
            // les alertes.
            let side = session.side(at: midpoint)
            let position = SolarCalculator.position(date: midpoint,
                                                    latitude: session.latitude,
                                                    longitude: session.longitude)
            let rates = UVEngine.rates(profile: profile,
                                       uvIndex: uvIndexAt(midpoint),
                                       solarElevation: position.elevation,
                                       environment: environment,
                                       illuminatedShare: side.illuminatedShare)
            raw.add(rates.vitaminDIUPerMinute * (step / 60), facing: side)
            med.add(rates.medFractionPerMinute * (step / 60), facing: side)
            cursor = cursor.addingTimeInterval(step)

            var candidate = SessionProgress(
                elapsed: cursor.timeIntervalSince(session.startDate),
                vitaminDIU: synthesised(raw: raw, carried: carried, profile: profile),
                rawVitaminDIU: raw.total,
                medFraction: med.worstErythemal,
                currentRates: rates,
                marginalYield: marginalYield(raw: raw, carried: carried,
                                             profile: profile, side: side))
            candidate.carriedMEDFraction = carriedMED
            candidate.carriedVitaminDIU = carriedIU
            candidate.medBySide = med
            candidate.currentSide = side
            candidate.vitaminDPercentOfGoal = profile.dailyGoalIU > 0
                ? candidate.dayVitaminDIU / profile.dailyGoalIU : 0

            if predicate(candidate) { return cursor > now ? cursor : now }
        }
        return nil
    }
}
