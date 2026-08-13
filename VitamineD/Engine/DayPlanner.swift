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

    var bestRecommendation: SessionRecommendation? { recommendations.first }

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
            samples: samples, profile: profile, calendar: calendar)

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
            goalExceedsCeiling: profile.dailyGoalIU > ceiling
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

    /// Simule une sortie démarrant à un instant donné et renvoie ce qu'elle
    /// produirait.
    static func simulateSession(startingAt index: Int,
                                samples: [TimelineSample],
                                profile: UserProfile,
                                maximumDuration: TimeInterval = maximumSessionDuration)
    -> SessionRecommendation? {
        guard index < samples.count, samples[index].isSynthesisPossible else { return nil }

        let ceiling = UVEngine.synthesisCeiling(profile: profile)
        let burnLimit = profile.burnAlertFraction

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
            let targetSaturated = min(profile.dailyGoalIU, ceiling * 0.999)
            let rawNeeded = -ceiling * log(1 - targetSaturated / ceiling)

            let goalCrossing: Double? = (rawIU < rawNeeded && nextRaw >= rawNeeded)
                ? (rawNeeded - rawIU) / max(nextRaw - rawIU, .leastNonzeroMagnitude)
                : nil
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

            if UVEngine.marginalYield(rawIU: nextRaw, profile: profile) < diminishingReturnsThreshold {
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

        let reachesGoal = UVEngine.saturated(rawIU: rawIU, profile: profile) >= profile.dailyGoalIU * 0.995
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
            ? min(1, UVEngine.saturated(rawIU: rawIU, profile: profile) / profile.dailyGoalIU)
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
            expectedIU: UVEngine.saturated(rawIU: rawIU, profile: profile),
            medFraction: medFraction,
            reachesGoal: reachesGoal,
            limitingFactor: limiting,
            comfort: comfort,
            averageUVIndex: averageUV,
            score: score
        )
    }

    private static func buildRecommendations(samples: [TimelineSample],
                                             profile: UserProfile,
                                             calendar: Calendar) -> [SessionRecommendation] {
        var candidates: [SessionRecommendation] = []
        // Un candidat tous les quarts d'heure : assez fin pour bien placer le
        // créneau, assez grossier pour rester instantané.
        let stride = max(1, Int((15 * 60) / sampleInterval))
        for index in Swift.stride(from: 0, to: samples.count, by: stride) {
            if let session = simulateSession(startingAt: index, samples: samples, profile: profile) {
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
