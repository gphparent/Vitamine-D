import Foundation

/// Un instant de la journée, avec tout ce qu'il faut pour en juger.
struct TimelineSample: Identifiable, Equatable, Sendable {
    let date: Date
    let solarElevation: Double
    let uvIndex: Double
    let uvIndexClearSky: Double
    let cloudCover: Double
    let apparentTemperature: Double
    let precipitationProbability: Double
    let rates: DoseRates
    /// Confort météorologique, de 0 à 1.
    let comfort: Double

    var id: Date { date }

    var isSynthesisPossible: Bool { rates.vitaminDIUPerMinute > 0.5 }
}

/// Fenêtre continue pendant laquelle la synthèse est possible.
struct ExposureWindow: Identifiable, Equatable, Sendable {
    enum Quality: Int, Comparable, Sendable {
        case marginal   // synthèse lente, mieux que rien
        case good       // synthèse correcte
        case optimal    // règle de l'ombre satisfaite

        static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .marginal: return "Faible"
            case .good:     return "Bonne"
            case .optimal:  return "Optimale"
            }
        }
    }

    let interval: DateInterval
    let quality: Quality
    let peakUVIndex: Double
    let peakSolarElevation: Double

    var id: Date { interval.start }
}

/// Créneau d'exposition proposé à l'utilisateur.
struct SessionRecommendation: Identifiable, Equatable, Sendable {
    let start: Date
    /// Durée conseillée.
    let duration: TimeInterval
    /// Vitamine D attendue au terme du créneau, plafond compris.
    let expectedIU: Double
    /// Part de la DEM consommée au terme du créneau, de 0 à 1.
    let medFraction: Double
    /// L'objectif quotidien est-il atteint dans ce créneau ?
    let reachesGoal: Bool
    /// Ce qui a mis fin au créneau.
    let limitingFactor: LimitingFactor
    let comfort: Double
    let averageUVIndex: Double
    let score: Double

    enum LimitingFactor: String, Sendable {
        case goalReached
        case burnRisk
        case sunSetting
        case diminishingReturns

        var explanation: String {
            switch self {
            case .goalReached:
                return "Objectif atteint."
            case .burnRisk:
                return "Limite de sécurité cutanée atteinte avant l'objectif."
            case .sunSetting:
                return "Le Soleil descend sous le seuil utile."
            case .diminishingReturns:
                return "La synthèse plafonne : rester plus longtemps n'apporte plus rien."
            }
        }
    }

    var id: Date { start }
    var end: Date { start.addingTimeInterval(duration) }
    var minutes: Int { Int((duration / 60).rounded()) }
}

/// Plan complet d'une journée pour un lieu et un profil donnés.
struct DayPlan: Equatable, Sendable {
    let date: Date
    let latitude: Double
    let longitude: Double
    let timeZone: TimeZone
    let samples: [TimelineSample]
    let windows: [ExposureWindow]
    let recommendations: [SessionRecommendation]
    let sunrise: Date?
    let sunset: Date?
    let solarNoon: Date
    let peakElevation: Double
    let peakUVIndex: Double
    /// Vrai lorsque le Soleil ne monte jamais assez haut de la journée : la
    /// synthèse cutanée est alors impossible, quelle que soit la durée passée
    /// dehors.
    let isVitaminDWinter: Bool
    /// L'objectif quotidien dépasse-t-il ce que la tenue permet de synthétiser ?
    let goalExceedsCeiling: Bool
    /// Plage où la règle de l'ombre est satisfaite : le Soleil dépasse 45° et le
    /// rendement est à son meilleur. `nil` s'il ne monte jamais si haut.
    ///
    /// Définie sur la seule hauteur du Soleil, donc insensible aux nuages : elle
    /// ne bouge pas d'une prévision à l'autre, ce qui est la moindre des choses
    /// pour un décompte.
    let optimalBand: DateInterval?

    var bestRecommendation: SessionRecommendation? { recommendations.first }

    /// Les créneaux dans l'ordre où ils se présentent, et non par mérite.
    ///
    /// Une journée se lit de gauche à droite : c'est ainsi qu'on décide si l'on
    /// sort ce matin ou après le dîner. Le classement reste accessible par
    /// `bestRecommendation`, et l'interface le signale.
    var chronologicalRecommendations: [SessionRecommendation] {
        recommendations.sorted { $0.start < $1.start }
    }

    func sample(nearest date: Date) -> TimelineSample? {
        samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

/// Construit le plan de la journée : échantillonnage de la course du Soleil,
/// croisement avec la météo, et sélection des créneaux à recommander.
enum DayPlanner {

    /// Pas d'échantillonnage de la journée.
    static let sampleInterval: TimeInterval = 5 * 60
    /// Durée maximale d'un créneau proposé.
    static let maximumSessionDuration: TimeInterval = 90 * 60
    /// Rendement marginal en deçà duquel il devient inutile de rester dehors.
    static let diminishingReturnsThreshold = 0.35

    static func makePlan(date: Date,
                         latitude: Double,
                         longitude: Double,
                         timeZone: TimeZone,
                         profile: UserProfile,
                         environment: EnvironmentFactors = .standard,
                         carried: Double = 0,
                         carriedMED: Double = 0,
                         forecast: [UVConditions]) -> DayPlan {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = dayStart.addingTimeInterval(86_400)

        let (sunrise, sunset) = SolarCalculator.sunriseSunset(
            on: date, latitude: latitude, longitude: longitude, calendar: calendar)
        let noon = SolarCalculator.solarNoon(
            on: date, latitude: latitude, longitude: longitude, calendar: calendar)

        // On échantillonne un peu avant le lever et un peu après le coucher pour
        // que la courbe affichée ne soit pas tronquée.
        let from = (sunrise ?? dayStart).addingTimeInterval(-30 * 60)
        let to = (sunset ?? dayEnd).addingTimeInterval(30 * 60)
        let start = max(dayStart, from)
        let end = min(dayEnd, to)

        var samples: [TimelineSample] = []
        var cursor = start
        while cursor <= end {
            let position = SolarCalculator.position(
                date: cursor, latitude: latitude, longitude: longitude)
            let conditions = interpolatedConditions(
                at: cursor, forecast: forecast,
                solarElevation: position.elevation, environment: environment)

            let rates = UVEngine.rates(profile: profile,
                                       uvIndex: conditions.uvIndex,
                                       solarElevation: position.elevation,
                                       environment: environment)

            samples.append(TimelineSample(
                date: cursor,
                solarElevation: position.elevation,
                uvIndex: conditions.uvIndex,
                uvIndexClearSky: conditions.uvIndexClearSky,
                cloudCover: conditions.cloudCover,
                apparentTemperature: conditions.apparentTemperature,
                precipitationProbability: conditions.precipitationProbability,
                rates: rates,
                comfort: comfortScore(conditions)
            ))
            cursor = cursor.addingTimeInterval(sampleInterval)
        }

        let windows = buildWindows(from: samples)
        let recommendations = buildRecommendations(
            samples: samples, profile: profile, carried: carried,
            carriedMED: carriedMED, calendar: calendar)

        let peakElevation = samples.map(\.solarElevation).max() ?? -90
        let peakUV = samples.map(\.uvIndex).max() ?? 0
        let ceiling = UVEngine.synthesisCeiling(profile: profile)

        return DayPlan(
            date: dayStart,
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            samples: samples,
            windows: windows,
            recommendations: recommendations,
            sunrise: sunrise,
            sunset: sunset,
            solarNoon: noon,
            peakElevation: peakElevation,
            peakUVIndex: peakUV,
            isVitaminDWinter: peakElevation < UVEngine.vitaminDWinterElevation,
            goalExceedsCeiling: profile.dailyGoalIU > ceiling,
            optimalBand: yieldBands(from: samples).first { $0.band == .optimal }?.interval
        )
    }

    // MARK: - Météo

    /// Conditions à un instant quelconque, interpolées entre les points horaires
    /// de la prévision. En l'absence de prévision, le modèle de ciel clair prend
    /// le relais, atténué par la dernière couverture nuageuse connue.
    private static func interpolatedConditions(at date: Date,
                                               forecast: [UVConditions],
                                               solarElevation: Double,
                                               environment: EnvironmentFactors) -> UVConditions {
        guard !forecast.isEmpty else {
            let clear = UVEngine.modelledClearSkyUVIndex(
                solarElevation: solarElevation, environment: environment)
            return UVConditions(date: date, uvIndex: clear, uvIndexClearSky: clear,
                                cloudCover: 0, temperature: .nan, apparentTemperature: .nan,
                                precipitationProbability: 0, windSpeed: 0, weatherCode: 0)
        }

        let sorted = forecast.sorted { $0.date < $1.date }
        if let exact = sorted.first(where: { abs($0.date.timeIntervalSince(date)) < 1 }) {
            return exact
        }
        guard let after = sorted.first(where: { $0.date > date }) else { return sorted.last! }
        guard let before = sorted.last(where: { $0.date <= date }) else { return sorted.first! }

        let span = after.date.timeIntervalSince(before.date)
        let ratio = span > 0 ? date.timeIntervalSince(before.date) / span : 0
        func blend(_ a: Double, _ b: Double) -> Double { a + (b - a) * ratio }

        // L'indice UV varie comme le cosinus de l'angle zénithal, pas
        // linéairement : interpoler l'indice brut entre deux points horaires
        // creuserait un faux plateau autour du midi solaire. On interpole donc
        // le rapport à la valeur de ciel clair, qui est lisse, et on le
        // réapplique à la valeur de ciel clair calculée pour cet instant précis.
        let modelled = UVEngine.modelledClearSkyUVIndex(
            solarElevation: solarElevation, environment: environment)
        let beforeRatio = before.uvIndexClearSky > 0.05
            ? before.uvIndex / before.uvIndexClearSky : 1
        let afterRatio = after.uvIndexClearSky > 0.05
            ? after.uvIndex / after.uvIndexClearSky : 1
        let cloudFactor = blend(beforeRatio, afterRatio)

        let clearSky = max(modelled, 0)
        return UVConditions(
            date: date,
            uvIndex: max(0, clearSky * cloudFactor),
            uvIndexClearSky: clearSky,
            cloudCover: blend(before.cloudCover, after.cloudCover),
            temperature: blend(before.temperature, after.temperature),
            apparentTemperature: blend(before.apparentTemperature, after.apparentTemperature),
            precipitationProbability: blend(before.precipitationProbability,
                                            after.precipitationProbability),
            windSpeed: blend(before.windSpeed, after.windSpeed),
            weatherCode: ratio < 0.5 ? before.weatherCode : after.weatherCode
        )
    }

    /// Confort d'une sortie, de 0 à 1 : température ressentie, pluie, vent.
    ///
    /// Un créneau photobiologiquement parfait sous une pluie battante à 4 °C ne
    /// vaut rien : personne ne sortira les avant-bras nus.
    static func comfortScore(_ conditions: UVConditions) -> Double {
        var score = 1.0

        let felt = conditions.apparentTemperature
        if !felt.isNaN {
            switch felt {
            case 18...27:   score *= 1.0
            case 12..<18:   score *= 0.85
            case 27..<32:   score *= 0.8
            case 5..<12:    score *= 0.55
            case 32..<36:   score *= 0.5
            case -5..<5:    score *= 0.3
            default:        score *= 0.15
            }
        }

        score *= 1 - 0.85 * min(1, max(0, conditions.precipitationProbability))

        if conditions.windSpeed > 20 {
            score *= max(0.5, 1 - (conditions.windSpeed - 20) / 60)
        }

        return max(0, min(1, score))
    }

    // MARK: - Fenêtres

    private static func buildWindows(from samples: [TimelineSample]) -> [ExposureWindow] {
        func quality(_ sample: TimelineSample) -> ExposureWindow.Quality? {
            guard sample.isSynthesisPossible else { return nil }
            if sample.solarElevation >= UVEngine.optimalSynthesisElevation && sample.uvIndex >= 3 {
                return .optimal
            }
            if sample.solarElevation >= 30 || sample.uvIndex >= 3 { return .good }
            return .marginal
        }

        var windows: [ExposureWindow] = []
        var runStart: Int?
        var runQuality: ExposureWindow.Quality?

        func closeRun(at endIndex: Int) {
            guard let startIndex = runStart, let q = runQuality, endIndex > startIndex else {
                runStart = nil; runQuality = nil; return
            }
            let slice = samples[startIndex...endIndex]
            windows.append(ExposureWindow(
                interval: DateInterval(start: samples[startIndex].date,
                                       end: samples[endIndex].date),
                quality: q,
                peakUVIndex: slice.map(\.uvIndex).max() ?? 0,
                peakSolarElevation: slice.map(\.solarElevation).max() ?? 0
            ))
            runStart = nil; runQuality = nil
        }

        for (index, sample) in samples.enumerated() {
            let q = quality(sample)
            if q != runQuality {
                if runQuality != nil { closeRun(at: index) }
                if q != nil { runStart = index; runQuality = q }
            }
        }
        if runStart != nil { closeRun(at: samples.count - 1) }

        return windows.filter { $0.interval.duration >= 10 * 60 }
    }

    // MARK: - Recommandations

    // MARK: - Bandes de rendement

    /// Qualité du rendement — vitamine D obtenue par unité de capital cutané
    /// dépensé — sur une plage horaire.
    ///
    /// Dans ce rapport, l'indice UV se simplifie : il figure au numérateur de la
    /// synthèse comme au dénominateur de la dose érythémale. Le rendement ne
    /// dépend donc que de la **hauteur du Soleil**, et il croît avec elle
    /// jusqu'à saturer vers 65°.
    ///
    /// Conséquence contre-intuitive : il n'existe aucun créneau discret où l'on
    /// gagnerait davantage pour moins de risque. Le meilleur rapport est
    /// toujours le Soleil le plus haut — à condition d'y rester peu. À 20° de
    /// hauteur, il faut dépenser huit fois plus de capital cutané pour la même
    /// vitamine D qu'à 65°.
    enum YieldBand: Int, Comparable, Sendable {
        case negligible   // sous 25° : ce qu'on récolte ne vaut pas la dépense
        case partial      // 25 à 45° : utile, mais le rapport reste médiocre
        case optimal      // au-delà de 45° : règle de l'ombre satisfaite

        static func < (lhs: YieldBand, rhs: YieldBand) -> Bool { lhs.rawValue < rhs.rawValue }

        init(solarElevation: Double) {
            switch solarElevation {
            case UVEngine.optimalSynthesisElevation...: self = .optimal
            case UVEngine.vitaminDWinterElevation...:   self = .partial
            default:                                    self = .negligible
            }
        }

        var title: String {
            switch self {
            case .negligible: return "Rendement dérisoire"
            case .partial:    return "Rendement partiel"
            case .optimal:    return "Rendement optimal"
            }
        }

        var shortTitle: String {
            switch self {
            case .negligible: return "Dérisoire"
            case .partial:    return "Partiel"
            case .optimal:    return "Optimal"
            }
        }
    }

    /// Découpe la journée en plages de rendement homogène.
    ///
    /// Seules les plages où le Soleil est levé sont renvoyées : colorer la nuit
    /// n'apprendrait rien.
    static func yieldBands(from samples: [TimelineSample]) -> [(interval: DateInterval, band: YieldBand)] {
        var result: [(DateInterval, YieldBand)] = []
        var runStart: Date?
        var runBand: YieldBand?

        func close(at end: Date) {
            if let start = runStart, let band = runBand, end > start {
                result.append((DateInterval(start: start, end: end), band))
            }
            runStart = nil; runBand = nil
        }

        for sample in samples {
            guard sample.solarElevation > 0 else {
                close(at: sample.date)
                continue
            }
            let band = YieldBand(solarElevation: sample.solarElevation)
            if band != runBand {
                close(at: sample.date)
                runStart = sample.date
                runBand = band
            }
        }
        if let last = samples.last { close(at: last.date) }
        return result.map { (interval: $0.0, band: $0.1) }
    }

    /// Durée d'exposition continue, à partir de `date`, avant d'atteindre la
    /// fraction indiquée de la dose érythémale minimale. `nil` si le Soleil se
    /// couche avant.
    ///
    /// Intègre la course réelle du Soleil au lieu de figer le débit courant.
    /// L'écart n'est pas anecdotique : un matin d'août à Montréal, le débit de
    /// 7 h 30 laisse croire à six heures et demie avant la rougeur, alors que
    /// le Soleil monte si vite qu'il n'en reste que deux. L'erreur va dans le
    /// sens qui rassure, ce qui est le pire des sens pour ce chiffre-ci.
    ///
    /// En fin de journée l'erreur s'inverse : le débit figé annonce encore une
    /// heure et demie alors qu'il devient tout simplement impossible de brûler
    /// avant le coucher.
    static func timeToErythema(from date: Date,
                               samples: [TimelineSample],
                               fraction: Double = 1.0) -> TimeInterval? {
        guard fraction > 0,
              let start = samples.firstIndex(where: { $0.date >= date }) else { return nil }

        var accumulated = 0.0
        var elapsed: TimeInterval = 0

        for index in start..<max(start, samples.count - 1) {
            let sample = samples[index]
            let step = samples[index + 1].date.timeIntervalSince(sample.date)
            let increment = sample.rates.medFractionPerMinute * (step / 60)

            if increment > 0, accumulated + increment >= fraction {
                let ratio = (fraction - accumulated) / increment
                return elapsed + step * ratio
            }
            accumulated += increment
            elapsed += step
        }
        return nil
    }

    /// Vitamine D cumulée du jour à l'instant où le seuil d'érythème serait
    /// franchi, si l'on restait dehors sans interruption à partir de `date`.
    ///
    /// Répond à une question que la durée seule ne pose pas : où en serait la
    /// récolte au moment où la peau rougirait ?
    ///
    /// La réponse est plus sévère qu'on ne l'imagine. Le plafond de synthèse et
    /// la production croissent tous deux avec la surface découverte, si bien
    /// que leur rapport n'en dépend pas : se couvrir ne rapproche ni n'éloigne
    /// la rougeur du plafond, cela rétrécit les deux à la fois. Ce qui déplace
    /// vraiment ce point, c'est le phototype — une peau qui tolère cinq fois
    /// plus d'énergie avant de rougir va cinq fois plus loin sur sa courbe — et
    /// la hauteur du Soleil, qui commande la part d'UVB utile dans le
    /// rayonnement reçu.
    ///
    /// Pour un phototype III sous un Soleil au zénith, la rougeur survient vers
    /// 42 % du plafond. Autrement dit : on ne peut pas remplir la barre en
    /// restant dehors, quelle que soit la tenue. C'est tout l'objet de
    /// l'application, et c'est ce que ce repère rend visible.
    ///
    /// `nil` quand le Soleil se couche avant que la dose suffise : il n'y a
    /// alors rien à signaler, aucune durée d'exposition ne fera rougir.
    static func vitaminDAtErythema(from date: Date,
                                   samples: [TimelineSample],
                                   profile: UserProfile,
                                   carried: Double = 0,
                                   carriedMED: Double = 0,
                                   carriedIU: Double = 0) -> Double? {
        // Ce qui reste de la dose du jour : la peau ne distingue pas les
        // sorties, et deux demi-doses font une rougeur.
        let remaining = 1 - max(0, carriedMED)
        guard remaining > 0 else { return carriedIU }
        guard let start = samples.firstIndex(where: { $0.date >= date }) else { return nil }

        var accumulatedMED = 0.0
        var rawIU = 0.0

        for index in start..<max(start, samples.count - 1) {
            let sample = samples[index]
            let minutes = samples[index + 1].date.timeIntervalSince(sample.date) / 60
            let medIncrement = sample.rates.medFractionPerMinute * minutes
            let rawIncrement = sample.rates.vitaminDIUPerMinute * minutes

            if medIncrement > 0, accumulatedMED + medIncrement >= remaining {
                // Le seuil tombe au milieu du pas : on ne retient que la part
                // de vitamine D produite avant lui.
                let ratio = (remaining - accumulatedMED) / medIncrement
                rawIU += rawIncrement * ratio
                return carriedIU + UVEngine.saturated(
                    rawIU: rawIU, carried: carried, profile: profile)
            }
            accumulatedMED += medIncrement
            rawIU += rawIncrement
        }
        return nil
    }

    /// Simule une sortie démarrant à un instant donné et renvoie ce qu'elle
    /// produirait.
    /// - Parameter carried: charge photochimique déjà installée dans la peau.
    ///   Une sortie qui suit de peu la précédente démarre plus haut sur la
    ///   courbe de saturation, et rapporte donc moins pour le même capital
    ///   cutané dépensé.
    static func simulateSession(startingAt index: Int,
                                samples: [TimelineSample],
                                profile: UserProfile,
                                carried: Double = 0,
                                carriedMED: Double = 0,
                                maximumDuration: TimeInterval = maximumSessionDuration)
    -> SessionRecommendation? {
        guard index < samples.count, samples[index].isSynthesisPossible else { return nil }

        // Ce qui reste de capital cutané pour aujourd'hui, et non l'allocation
        // pleine : la sortie du matin ne se rembourse pas à midi.
        let burnLimit = max(0, profile.burnAlertFraction - max(0, carriedMED))
        guard burnLimit > 0.01 else { return nil }

        // Dose cumulée — charge héritée comprise — à laquelle l'objectif du
        // jour serait atteint. `nil` quand le plafond l'interdit : ni la tenue
        // ni le temps passé dehors n'y changeraient alors quoi que ce soit.
        // Ne dépend pas du déroulement de la sortie, donc calculée une fois.
        let target = min(profile.dailyGoalIU,
                         UVEngine.remainingCapacity(carried: carried, profile: profile) * 0.999)
        let cumulativeNeeded = UVEngine.cumulativeDose(
            toProduce: target, carried: carried, profile: profile)

        var rawIU = 0.0
        var medFraction = 0.0
        var elapsed: TimeInterval = 0
        var comfortSum = 0.0
        var uvSum = 0.0
        var steps = 0
        var limiting: SessionRecommendation.LimitingFactor = .sunSetting

        var cursor = index
        while cursor < samples.count - 1 && elapsed < maximumDuration {
            let sample = samples[cursor]
            let step = samples[cursor + 1].date.timeIntervalSince(sample.date)
            let stepMinutes = step / 60

            comfortSum += sample.comfort
            uvSum += sample.uvIndex
            steps += 1

            if !sample.isSynthesisPossible { limiting = .sunSetting; break }

            let nextRaw = rawIU + sample.rates.vitaminDIUPerMinute * stepMinutes
            let nextMED = medFraction + sample.rates.medFractionPerMinute * stepMinutes

            // Sous un Soleil d'été, un pas de cinq minutes peut à lui seul
            // consommer le quart de la DEM. Les deux seuils — objectif atteint
            // et limite cutanée — tombent donc régulièrement dans le même pas,
            // et il faut déterminer lequel arrive en premier : traiter
            // l'objectif d'office ferait dépasser la limite que l'utilisateur
            // s'est fixée.
            let goalCrossing: Double? = cumulativeNeeded.flatMap { needed in
                (carried + rawIU < needed && carried + nextRaw >= needed)
                    ? (needed - carried - rawIU) / max(nextRaw - rawIU, .leastNonzeroMagnitude)
                    : nil
            }
            let burnCrossing: Double? = (nextMED >= burnLimit)
                ? (burnLimit - medFraction) / max(nextMED - medFraction, .leastNonzeroMagnitude)
                : nil

            if goalCrossing != nil || burnCrossing != nil {
                let goalAt = goalCrossing ?? .infinity
                let burnAt = burnCrossing ?? .infinity
                let fraction = min(goalAt, burnAt)
                elapsed += step * fraction
                rawIU += (nextRaw - rawIU) * fraction
                medFraction += (nextMED - medFraction) * fraction
                limiting = goalAt <= burnAt ? .goalReached : .burnRisk
                break
            }

            if UVEngine.marginalYield(rawIU: carried + nextRaw, profile: profile) < diminishingReturnsThreshold {
                rawIU = nextRaw
                medFraction = nextMED
                elapsed += step
                limiting = .diminishingReturns
                break
            }

            rawIU = nextRaw
            medFraction = nextMED
            elapsed += step
            cursor += 1
        }

        guard elapsed >= 60 else { return nil }

        let produced = UVEngine.saturated(rawIU: rawIU, carried: carried, profile: profile)
        let reachesGoal = produced >= profile.dailyGoalIU * 0.995
        let comfort = steps > 0 ? comfortSum / Double(steps) : 0
        let averageUV = steps > 0 ? uvSum / Double(steps) : 0

        // Un bon créneau apporte beaucoup de vitamine D, vite, en consommant peu
        // de DEM, par temps agréable. La composante « efficacité » favorise
        // naturellement le milieu de journée, où le rapport vitamine D / risque
        // est le meilleur.
        //
        // Le premier facteur est ce qui est réellement produit, rapporté à
        // l'objectif — et non un simple « atteint ou non ». Sans cela, la
        // récompense de brièveté ferait remonter des créneaux dérisoires : cinq
        // minutes au crépuscule sont vite passées et ne coûtent presque rien en
        // capital cutané, mais ne produisent rien non plus.
        let attainment = profile.dailyGoalIU > 0
            ? min(1, produced / profile.dailyGoalIU)
            : 0
        let efficiency = medFraction > 0 ? (rawIU / (medFraction * 100)) : 0
        let brevity = 1.0 / (1.0 + elapsed / (30 * 60))
        var score = attainment
            * (0.55 + 0.45 * comfort)
            * (0.5 + 0.5 * min(1, efficiency / 40))
            * (0.6 + 0.4 * brevity)
        if limiting == .burnRisk { score *= 0.7 }

        return SessionRecommendation(
            start: samples[index].date,
            duration: elapsed,
            expectedIU: produced,
            medFraction: medFraction,
            reachesGoal: reachesGoal,
            limitingFactor: limiting,
            comfort: comfort,
            averageUVIndex: averageUV,
            score: score
        )
    }

    // MARK: - Les deux façons de sortir

    /// Ce qu'il est possible de faire aujourd'hui, ramené aux deux seules
    /// questions qu'on se pose devant une fenêtre.
    ///
    /// Trois créneaux classés par mérite demandaient de comparer trois cartes
    /// pour décider d'une chose simple : est-ce que je sors maintenant, ou est-ce
    /// que j'attends ? On répond donc aux deux questions séparément.
    struct OutingOptions: Equatable, Sendable {
        /// Ce que donnerait une sortie commencée à l'instant. `nil` quand le
        /// Soleil est trop bas, ou quand le capital cutané du jour est épuisé.
        let immediate: SessionRecommendation?
        /// Le meilleur créneau restant de la journée.
        let later: SessionRecommendation?

        static let none = OutingOptions(immediate: nil, later: nil)

        /// Attendre vaut-il mieux que sortir tout de suite ?
        ///
        /// La comparaison porte sur le score, qui pèse déjà l'objectif atteint,
        /// le capital cutané dépensé et le confort. Une marge est exigée : un
        /// avantage de quelques pour cent ne justifie pas de renvoyer quelqu'un
        /// à cet après-midi.
        var laterIsBetter: Bool {
            guard let later else { return false }
            guard let immediate else { return true }
            return later.score > immediate.score * 1.15
        }
    }

    /// Délai minimal avant le créneau « plus tard ».
    ///
    /// Proposer de sortir dans cinq minutes plutôt que maintenant n'aide
    /// personne : les deux options doivent être franchement distinctes.
    static let laterOptionDelay: TimeInterval = 20 * 60

    static func outingOptions(plan: DayPlan,
                              at date: Date,
                              profile: UserProfile,
                              carried: Double = 0,
                              carriedMED: Double = 0) -> OutingOptions {
        // Un jour d'hiver vitaminique ne propose rien, et c'est délibéré. Le
        // modèle continu, lui, rend encore un ou deux UI par minute sous 25° :
        // la table de rendement y est une extrapolation, et proposer « sortez
        // quatre-vingt-dix minutes pour cent soixante unités » contredirait le
        // bandeau qui vient d'annoncer, à raison, que la journée ne produit
        // rien. Sortir reste possible — l'écran garde un bouton pour cela —
        // mais l'application cesse de le recommander.
        guard !plan.isVitaminDWinter else { return .none }

        let samples = plan.samples
        let immediate = samples.firstIndex { $0.date >= date }.flatMap {
            simulateSession(startingAt: $0, samples: samples, profile: profile,
                            carried: carried, carriedMED: carriedMED)
        }

        // Le meilleur créneau restant est cherché à nouveau, plutôt que repris
        // des trois recommandations du plan : à seize heures, ces trois-là
        // peuvent toutes être derrière nous, et « plus tard » n'aurait plus rien
        // à proposer alors qu'il reste du Soleil utile.
        let horizon = date.addingTimeInterval(laterOptionDelay)
        let step = max(1, Int((15 * 60) / sampleInterval))
        var best: SessionRecommendation?
        for index in Swift.stride(from: 0, to: samples.count, by: step)
        where samples[index].date >= horizon {
            guard let candidate = simulateSession(
                startingAt: index, samples: samples, profile: profile,
                carried: carried, carriedMED: carriedMED) else { continue }
            if candidate.score > (best?.score ?? -1) { best = candidate }
        }

        return OutingOptions(immediate: immediate, later: best)
    }

    private static func buildRecommendations(samples: [TimelineSample],
                                             profile: UserProfile,
                                             carried: Double,
                                             carriedMED: Double,
                                             calendar: Calendar) -> [SessionRecommendation] {
        var candidates: [SessionRecommendation] = []
        // Un candidat tous les quarts d'heure : assez fin pour bien placer le
        // créneau, assez grossier pour rester instantané.
        let stride = max(1, Int((15 * 60) / sampleInterval))
        for index in Swift.stride(from: 0, to: samples.count, by: stride) {
            if let session = simulateSession(startingAt: index, samples: samples,
                                             profile: profile, carried: carried,
                                             carriedMED: carriedMED) {
                candidates.append(session)
            }
        }

        let ranked = candidates.sorted { $0.score > $1.score }

        // On ne garde que des créneaux nettement distincts, pour ne pas proposer
        // trois fois la même sortie décalée d'un quart d'heure.
        var kept: [SessionRecommendation] = []
        for candidate in ranked {
            let overlaps = kept.contains { existing in
                abs(existing.start.timeIntervalSince(candidate.start)) < 45 * 60
            }
            if !overlaps { kept.append(candidate) }
            if kept.count == 3 { break }
        }
        return kept
    }
}
