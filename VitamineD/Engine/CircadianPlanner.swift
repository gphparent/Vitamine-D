import Foundation

/// Calage de l'horloge interne par la lumière.
///
/// ## Pourquoi c'est l'exact inverse de la vitamine D
///
/// La synthèse cutanée réclame des UVB, donc un Soleil haut, donc le milieu de
/// journée. Le calage circadien, lui, ne réclame que de la lumière — beaucoup,
/// et tôt. Le Soleil rasant du matin ne produit aucun UVB utile, mais c'est le
/// meilleur signal horaire de la journée.
///
/// L'application dit donc deux choses différentes à deux moments différents,
/// pour deux raisons qui n'ont aucun mécanisme commun.
///
/// ## Ce qui est établi, et ce qui l'est moins
///
/// Que la lumière soit le principal synchroniseur de l'horloge circadienne ne
/// fait aucun doute : des cellules rétiniennes à mélanopsine informent
/// directement le noyau suprachiasmatique. Que la lumière du matin avance la
/// phase et celle du soir la retarde est également bien établi — c'est la
/// courbe de réponse de phase.
///
/// Les durées précises recommandées ici viennent en revanche de la
/// vulgarisation — celles que popularise Andrew Huberman — et non d'un
/// protocole clinique. Elles sont raisonnables et sans risque ; elles ne sont
/// pas un dosage.
enum CircadianPlanner {

    // MARK: - Éclairement

    /// Éclairement horizontal extérieur, en lux.
    ///
    /// L'efficacité lumineuse du jour avoisine 110 lumens par watt, et
    /// l'éclairement énergétique global suit approximativement 1 000 W/m²
    /// multipliés par le sinus de la hauteur solaire. D'où l'ordre de grandeur
    /// familier : environ 100 000 lux Soleil au zénith, 50 000 lux à 30°.
    ///
    /// Les nuages coupent bien davantage le visible que l'ultraviolet — un ciel
    /// totalement couvert n'en laisse qu'environ 15 %, contre 25 % pour les UV.
    /// C'est l'inverse de l'intuition, et cela reste largement suffisant : même
    /// sous ce ciel-là, l'extérieur écrase n'importe quel intérieur.
    static func illuminance(solarElevation: Double, cloudCover: Double) -> Double {
        let clouds = 1 - 0.85 * pow(min(1, max(0, cloudCover)), 2)

        guard solarElevation > 0 else {
            // Crépuscule : la lumière du ciel décroît vite mais ne s'annule pas
            // brutalement. Utile à connaître, car elle porte encore un signal
            // horaire faible.
            guard solarElevation > -6 else { return 0 }
            return 400 * (1 + solarElevation / 6) * clouds
        }

        let direct = 110_000 * sin(solarElevation * .pi / 180)
        // Le ciel diffus éclaire même quand le Soleil rase l'horizon.
        return (direct + 2_000) * clouds
    }

    /// Ce que vaut la lumière disponible pour caler l'horloge.
    enum LightQuality: Int, Comparable, Sendable {
        case insufficient
        case weak
        case moderate
        case good
        case excellent

        static func < (lhs: LightQuality, rhs: LightQuality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        init(illuminance: Double) {
            switch illuminance {
            case 40_000...:      self = .excellent
            case 15_000..<40_000: self = .good
            case 5_000..<15_000:  self = .moderate
            case 1_000..<5_000:   self = .weak
            default:              self = .insufficient
            }
        }

        /// Durée conseillée, en minutes.
        ///
        /// Reprend les repères de vulgarisation courants : quelques minutes par
        /// grand soleil, une vingtaine sous un ciel couvert. La progression suit
        /// l'idée qu'il faut compenser un éclairement plus faible par une durée
        /// plus longue, sans que le produit soit exactement constant.
        var recommendedMinutes: ClosedRange<Int>? {
            switch self {
            case .excellent:    return 5...10
            case .good:         return 10...20
            case .moderate:     return 20...30
            case .weak:         return 30...45
            case .insufficient: return nil
            }
        }

        var title: String {
            switch self {
            case .excellent:    return "Lumière franche"
            case .good:         return "Bonne lumière"
            case .moderate:     return "Lumière modérée"
            case .weak:         return "Lumière faible"
            case .insufficient: return "Lumière insuffisante"
            }
        }

        var advice: String {
            switch self {
            case .excellent:
                return "Quelques minutes dehors suffisent. Ne fixez pas le Soleil."
            case .good:
                return "Une dizaine à une vingtaine de minutes dehors."
            case .moderate:
                return "Comptez vingt à trente minutes : le ciel est chargé."
            case .weak:
                return "Il faudra une bonne demi-heure, et l'effet restera partiel."
            case .insufficient:
                return "Trop sombre pour porter un signal horaire utile."
            }
        }
    }

    // MARK: - Fenêtre du matin

    /// Recommandation de lumière matinale.
    struct MorningLight: Equatable, Sendable {
        /// Plage pendant laquelle sortir sert le calage.
        let window: DateInterval
        /// Meilleur moment à l'intérieur de cette plage.
        let best: Date
        let quality: LightQuality
        let illuminance: Double
        /// Le Soleil se lève-t-il après l'heure de lever visée ?
        let sunRisesAfterWaking: Bool
    }

    /// Durée pendant laquelle la lumière du matin garde son effet de calage.
    ///
    /// La sensibilité décroît progressivement au fil de la matinée ; deux heures
    /// après le réveil, l'essentiel du bénéfice est passé.
    static let morningWindowDuration: TimeInterval = 2 * 3600

    /// Fenêtre de lumière matinale pour une heure de lever donnée.
    ///
    /// - Parameters:
    ///   - wakeTime: heure de lever visée, ce jour-là.
    ///   - samples: la journée échantillonnée, pour la hauteur du Soleil et les
    ///     nuages.
    static func morningLight(wakeTime: Date,
                             samples: [TimelineSample],
                             sunrise: Date?) -> MorningLight? {
        guard !samples.isEmpty else { return nil }

        // Sortir avant le lever du Soleil n'apporte rien : la fenêtre commence
        // au plus tard des deux.
        let start = max(wakeTime, sunrise ?? wakeTime)
        let end = start.addingTimeInterval(morningWindowDuration)
        guard let last = samples.last?.date, start < last else { return nil }

        let window = DateInterval(start: start, end: min(end, last))
        let inside = samples.filter { window.contains($0.date) }
        guard !inside.isEmpty else { return nil }

        // Le meilleur instant est le plus lumineux de la fenêtre — en pratique
        // sa fin, puisque le Soleil monte. On garde le calcul explicite : sous
        // un ciel qui se dégage, l'ordre peut s'inverser.
        let scored = inside.map { sample -> (TimelineSample, Double) in
            (sample, illuminance(solarElevation: sample.solarElevation,
                                 cloudCover: sample.cloudCover))
        }
        guard let peak = scored.max(by: { $0.1 < $1.1 }) else { return nil }

        return MorningLight(
            window: window,
            best: peak.0.date,
            quality: LightQuality(illuminance: peak.1),
            illuminance: peak.1,
            sunRisesAfterWaking: (sunrise ?? start) > wakeTime)
    }

    // MARK: - Décalage de l'heure de lever

    /// Conseil pour déplacer son heure de lever.
    struct PhaseShiftPlan: Equatable, Sendable {
        /// Écart entre l'heure actuelle et l'heure visée, en minutes.
        /// Négatif pour se lever plus tôt.
        let shiftMinutes: Int
        /// Heure de lever à viser demain, en respectant le pas quotidien.
        let nextWakeMinuteOfDay: Int
        /// Nombre de jours estimé pour arriver à l'heure visée.
        let days: Int
        /// Heure à partir de laquelle éviter la lumière vive, le soir.
        let dimLightMinuteOfDay: Int
    }

    /// Décalage maximal raisonnable d'un jour à l'autre, en minutes.
    ///
    /// L'horloge se déplace d'elle-même de moins d'une heure par jour sous
    /// l'effet de la lumière. Vouloir aller plus vite ne fait que créer un
    /// décalage entre l'heure du réveil et celle du corps — exactement ce qu'on
    /// cherche à éviter.
    static let maximumDailyShift = 30

    /// Délai entre l'extinction des lumières vives et le coucher visé.
    ///
    /// La lumière du soir retarde l'horloge, à l'inverse de celle du matin.
    /// Deux à trois heures de pénombre avant le coucher lui laissent le temps
    /// de libérer la mélatonine.
    static let eveningDimLead: TimeInterval = 2.5 * 3600

    /// Plan de déplacement progressif de l'heure de lever.
    ///
    /// - Parameters:
    ///   - current: heure de lever habituelle, en minutes depuis minuit.
    ///   - target: heure de lever visée, en minutes depuis minuit.
    ///   - sleepDuration: durée de sommeil souhaitée, en heures.
    static func phaseShift(current: Int, target: Int, sleepDuration: Double) -> PhaseShiftPlan {
        // On prend le chemin le plus court sur le cadran : viser 6 h quand on se
        // lève à 23 h est une avance de sept heures, pas un recul de dix-sept.
        var difference = target - current
        if difference > 720 { difference -= 1440 }
        if difference < -720 { difference += 1440 }

        let step = min(abs(difference), maximumDailyShift)
        let direction = difference < 0 ? -1 : 1
        let next = ((current + direction * step) % 1440 + 1440) % 1440

        let days = abs(difference) == 0
            ? 0
            : Int(ceil(Double(abs(difference)) / Double(maximumDailyShift)))

        let bedtime = Double(target) - sleepDuration * 60
        let dim = bedtime - eveningDimLead / 60
        let dimMinute = ((Int(dim.rounded()) % 1440) + 1440) % 1440

        return PhaseShiftPlan(shiftMinutes: difference,
                              nextWakeMinuteOfDay: next,
                              days: days,
                              dimLightMinuteOfDay: dimMinute)
    }
}
