import Foundation
import Testing
@testable import VitamineD

struct DayPlannerTests {

    private let montrealLat = 45.5019
    private let montrealLon = -73.5674
    private let montreal = TimeZone(identifier: "America/Montreal")!

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = dayOfMonth
        components.hour = 12
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        return calendar.date(from: components)!
    }

    /// Prévision synthétique : ciel clair, température agréable, pas de pluie.
    /// Isole le comportement du planificateur de celui du réseau.
    private func clearSkyForecast(around date: Date,
                                  latitude: Double,
                                  longitude: Double,
                                  temperature: Double = 22,
                                  cloudCover: Double = 0,
                                  rainProbability: Double = 0) -> [UVConditions] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        let start = calendar.startOfDay(for: date)

        return (0...24).map { hour in
            let moment = start.addingTimeInterval(TimeInterval(hour) * 3600)
            let position = SolarCalculator.position(
                date: moment, latitude: latitude, longitude: longitude)
            let clear = UVEngine.modelledClearSkyUVIndex(
                solarElevation: position.elevation, environment: .standard)
            return UVConditions(
                date: moment,
                uvIndex: clear * UVEngine.cloudTransmission(cloudCoverFraction: cloudCover),
                uvIndexClearSky: clear,
                cloudCover: cloudCover,
                temperature: temperature,
                apparentTemperature: temperature,
                precipitationProbability: rainProbability,
                windSpeed: 5,
                weatherCode: cloudCover > 0.5 ? 3 : 0)
        }
    }

    private func plan(on date: Date,
                      profile: UserProfile = .default,
                      cloudCover: Double = 0,
                      temperature: Double = 22,
                      rainProbability: Double = 0,
                      latitude: Double? = nil,
                      longitude: Double? = nil) -> DayPlan {
        let lat = latitude ?? montrealLat
        let lon = longitude ?? montrealLon
        return DayPlanner.makePlan(
            date: date,
            latitude: lat,
            longitude: lon,
            timeZone: montreal,
            profile: profile,
            forecast: clearSkyForecast(around: date, latitude: lat, longitude: lon,
                                       temperature: temperature,
                                       cloudCover: cloudCover,
                                       rainProbability: rainProbability))
    }

    // MARK: - Structure du plan

    @Test("Une journée d'été produit des fenêtres et des créneaux")
    func summerDayHasWindows() throws {
        let summer = plan(on: day(2026, 6, 21))

        #expect(!summer.isVitaminDWinter)
        #expect(summer.peakElevation > 65)
        #expect(summer.windows.contains { $0.quality == .optimal })
        #expect(!summer.recommendations.isEmpty)

        let best = try #require(summer.bestRecommendation)
        #expect(best.reachesGoal)
        #expect(best.minutes > 0 && best.minutes <= 90)
    }

    @Test("Le meilleur créneau d'été se place autour du midi solaire")
    func bestSlotIsNearSolarNoon() throws {
        // Le rapport vitamine D / dose érythémale culmine quand le Soleil est au
        // plus haut : le planificateur doit y converger de lui-même.
        let summer = plan(on: day(2026, 6, 21))
        let best = try #require(summer.bestRecommendation)
        let gap = abs(best.start.timeIntervalSince(summer.solarNoon))
        #expect(gap < 3 * 3600)
    }

    @Test("Décembre à Montréal est un hiver vitaminique")
    func winterIsFlagged() {
        let winter = plan(on: day(2026, 12, 21))
        #expect(winter.isVitaminDWinter)
        #expect(winter.peakElevation < UVEngine.vitaminDWinterElevation)
        #expect(!winter.windows.contains { $0.quality == .optimal })
    }

    @Test("Aucune fenêtre optimale sous la nuit polaire")
    func polarNightHasNothing() {
        let polar = plan(on: day(2026, 12, 21), latitude: 69.65, longitude: 18.96)
        #expect(polar.isVitaminDWinter)
        #expect(polar.windows.isEmpty)
        #expect(polar.recommendations.isEmpty)
    }

    @Test("Les fenêtres sont ordonnées et ne se chevauchent pas")
    func windowsAreDisjoint() {
        let summer = plan(on: day(2026, 7, 15))
        let sorted = summer.windows.sorted { $0.interval.start < $1.interval.start }
        for (previous, next) in zip(sorted, sorted.dropFirst()) {
            #expect(previous.interval.end <= next.interval.start.addingTimeInterval(1))
        }
    }

    @Test("Les créneaux proposés sont bien distincts")
    func recommendationsAreSpacedOut() {
        let summer = plan(on: day(2026, 7, 15))
        let starts = summer.recommendations.map(\.start).sorted()
        for (previous, next) in zip(starts, starts.dropFirst()) {
            #expect(next.timeIntervalSince(previous) >= 45 * 60)
        }
        #expect(summer.recommendations.count <= 3)
    }

    // MARK: - Influence du profil

    @Test("Un phototype clair reçoit un créneau plus court qu'un phototype foncé")
    func lightSkinNeedsLessTime() throws {
        var light = UserProfile.default
        light.skinType = .ii
        var dark = UserProfile.default
        dark.skinType = .v

        let lightPlan = plan(on: day(2026, 6, 21), profile: light)
        let darkPlan = plan(on: day(2026, 6, 21), profile: dark)

        let lightBest = try #require(lightPlan.bestRecommendation)
        let darkBest = try #require(darkPlan.bestRecommendation)
        #expect(lightBest.duration < darkBest.duration)
    }

    @Test("Se couvrir allonge le créneau nécessaire")
    func moreClothingMeansLongerSession() throws {
        var bare = UserProfile.default
        bare.exposure = BodyExposure(preset: .tankTopShorts)
        var covered = UserProfile.default
        covered.exposure = BodyExposure(preset: .tShirtTrousers)

        let barePlan = plan(on: day(2026, 6, 21), profile: bare)
        let coveredPlan = plan(on: day(2026, 6, 21), profile: covered)

        let bareBest = try #require(barePlan.bestRecommendation)
        let coveredBest = try #require(coveredPlan.bestRecommendation)
        #expect(coveredBest.duration > bareBest.duration)
    }

    @Test("Un objectif hors de portée est signalé")
    func unreachableGoalIsFlagged() {
        var ambitious = UserProfile.default
        ambitious.dailyGoalIU = 4000
        ambitious.exposure = BodyExposure(preset: .longSleevesTrousers)

        let summer = plan(on: day(2026, 6, 21), profile: ambitious)
        #expect(summer.goalExceedsCeiling)
        #expect(summer.recommendations.allSatisfy { !$0.reachesGoal })
    }

    // MARK: - Influence de la météo

    @Test("Les nuages allongent le temps nécessaire")
    func cloudsSlowThingsDown() throws {
        let clear = try #require(plan(on: day(2026, 6, 21), cloudCover: 0).bestRecommendation)
        let overcast = try #require(plan(on: day(2026, 6, 21), cloudCover: 1.0).bestRecommendation)
        #expect(overcast.duration > clear.duration)
        #expect(overcast.averageUVIndex < clear.averageUVIndex)
    }

    @Test("Le froid et la pluie font baisser la note de confort")
    func comfortReflectsWeather() {
        let pleasant = UVConditions(date: Date(), uvIndex: 6, uvIndexClearSky: 6,
                                    cloudCover: 0, temperature: 22, apparentTemperature: 22,
                                    precipitationProbability: 0, windSpeed: 5, weatherCode: 0)
        let freezing = UVConditions(date: Date(), uvIndex: 6, uvIndexClearSky: 6,
                                    cloudCover: 0, temperature: -12, apparentTemperature: -18,
                                    precipitationProbability: 0, windSpeed: 30, weatherCode: 0)
        let rainy = UVConditions(date: Date(), uvIndex: 6, uvIndexClearSky: 6,
                                 cloudCover: 1, temperature: 20, apparentTemperature: 20,
                                 precipitationProbability: 0.9, windSpeed: 10, weatherCode: 61)

        #expect(DayPlanner.comfortScore(pleasant) > 0.95)
        #expect(DayPlanner.comfortScore(freezing) < 0.2)
        #expect(DayPlanner.comfortScore(rainy) < 0.3)
    }

    @Test("Une prévision absente n'empêche pas de bâtir un plan")
    func planWorksWithoutForecast() {
        let offline = DayPlanner.makePlan(
            date: day(2026, 6, 21),
            latitude: montrealLat, longitude: montrealLon,
            timeZone: montreal, profile: .default, forecast: [])

        #expect(!offline.samples.isEmpty)
        #expect(offline.peakUVIndex > 5)
        #expect(!offline.recommendations.isEmpty)
    }

    // MARK: - Simulation d'une sortie

    @Test("La simulation s'arrête pour une raison explicite")
    func simulationTerminatesForAReason() throws {
        let summer = plan(on: day(2026, 6, 21))
        let noonIndex = try #require(summer.samples.firstIndex { $0.date >= summer.solarNoon })
        let session = try #require(DayPlanner.simulateSession(
            startingAt: noonIndex, samples: summer.samples, profile: .default))

        #expect(session.duration > 0)
        #expect(session.duration <= DayPlanner.maximumSessionDuration)
        #expect(session.medFraction <= UserProfile.default.burnAlertFraction + 1e-6)
        #expect(session.limitingFactor == .goalReached)
    }

    @Test("Un phototype très clair est arrêté par le risque cutané, pas par l'objectif")
    func fairSkinIsLimitedByBurnRisk() throws {
        var fragile = UserProfile.default
        fragile.skinType = .i
        fragile.dailyGoalIU = 4000
        fragile.exposure = BodyExposure(preset: .tShirtTrousers)

        let summer = plan(on: day(2026, 6, 21), profile: fragile)
        let noonIndex = try #require(summer.samples.firstIndex { $0.date >= summer.solarNoon })
        let session = try #require(DayPlanner.simulateSession(
            startingAt: noonIndex, samples: summer.samples, profile: fragile))

        #expect(session.limitingFactor != .goalReached)
        #expect(!session.reachesGoal)
        #expect(session.medFraction <= fragile.burnAlertFraction + 1e-6)
    }

    @Test("Aucune sortie ne dépasse le seuil d'alerte que l'utilisateur s'est fixé")
    func noRecommendationExceedsAlertThreshold() {
        for month in 1...12 {
            let daily = plan(on: day(2026, month, 15))
            for recommendation in daily.recommendations {
                #expect(recommendation.medFraction <= UserProfile.default.burnAlertFraction + 1e-6)
            }
        }
    }

    // MARK: - Bandes de rendement

    @Test("Les bandes de rendement suivent la hauteur du Soleil")
    func yieldBandsFollowElevation() {
        #expect(DayPlanner.YieldBand(solarElevation: 10) == .negligible)
        #expect(DayPlanner.YieldBand(solarElevation: 24.9) == .negligible)
        #expect(DayPlanner.YieldBand(solarElevation: 25) == .partial)
        #expect(DayPlanner.YieldBand(solarElevation: 44.9) == .partial)
        #expect(DayPlanner.YieldBand(solarElevation: 45) == .optimal)
        #expect(DayPlanner.YieldBand(solarElevation: 80) == .optimal)
        #expect(DayPlanner.YieldBand(solarElevation: 10) < .optimal)
    }

    @Test("Une journée d'été traverse les trois bandes, symétriquement")
    func summerCrossesEveryBand() throws {
        let summer = plan(on: day(2026, 6, 21))
        let bands = DayPlanner.yieldBands(from: summer.samples)

        let kinds = bands.map(\.band)
        #expect(kinds.contains(.negligible))
        #expect(kinds.contains(.partial))
        #expect(kinds.contains(.optimal))

        // Le Soleil monte puis redescend : la séquence doit être un aller-retour.
        #expect(kinds == [.negligible, .partial, .optimal, .partial, .negligible])

        // Les plages se suivent sans trou ni chevauchement.
        for (previous, next) in zip(bands, bands.dropFirst()) {
            #expect(abs(previous.interval.end.timeIntervalSince(next.interval.start)) < 1)
        }
    }

    @Test("Décembre à Montréal ne quitte jamais la bande dérisoire")
    func winterStaysNegligible() {
        let winter = plan(on: day(2026, 12, 21))
        let bands = DayPlanner.yieldBands(from: winter.samples)
        #expect(!bands.isEmpty)
        #expect(bands.allSatisfy { $0.band == .negligible })
    }

    @Test("La nuit polaire ne produit aucune bande")
    func polarNightHasNoBands() {
        let polar = plan(on: day(2026, 12, 21), latitude: 69.65, longitude: 18.96)
        #expect(DayPlanner.yieldBands(from: polar.samples).isEmpty)
    }

    @Test("La bande optimale encadre le midi solaire")
    func optimalBandSurroundsSolarNoon() throws {
        let summer = plan(on: day(2026, 6, 21))
        let optimal = try #require(
            DayPlanner.yieldBands(from: summer.samples).first { $0.band == .optimal })
        #expect(optimal.interval.contains(summer.solarNoon))
    }

    @Test("Le plan expose la bande optimale, et elle correspond aux bandes calculées")
    func planCarriesTheOptimalBand() throws {
        let summer = plan(on: day(2026, 6, 21))
        let band = try #require(summer.optimalBand)
        let computed = try #require(
            DayPlanner.yieldBands(from: summer.samples).first { $0.band == .optimal })

        #expect(band == computed.interval)
        #expect(band.contains(summer.solarNoon))

        // Le décompte doit être stable d'une prévision à l'autre : la bande ne
        // dépend que de la hauteur du Soleil, jamais des nuages.
        let overcast = plan(on: day(2026, 6, 21), cloudCover: 1.0)
        #expect(overcast.optimalBand == band)
    }

    @Test("Aucune bande optimale en hiver vitaminique")
    func winterHasNoOptimalBand() {
        let winter = plan(on: day(2026, 12, 21))
        #expect(winter.optimalBand == nil)
        #expect(winter.isVitaminDWinter)
    }

    @Test("L'ordre chronologique conserve les mêmes créneaux que le classement")
    func chronologicalOrderKeepsEveryRecommendation() throws {
        let summer = plan(on: day(2026, 6, 21))
        let chronological = summer.chronologicalRecommendations

        #expect(chronological.count == summer.recommendations.count)
        #expect(Set(chronological.map(\.id)) == Set(summer.recommendations.map(\.id)))
        #expect(chronological.map(\.start) == chronological.map(\.start).sorted())

        // Le meilleur créneau reste identifiable : l'interface le signale par sa
        // teinte, puisque sa position ne le dit plus.
        let best = try #require(summer.bestRecommendation)
        #expect(chronological.contains { $0.id == best.id })
        #expect(summer.recommendations.allSatisfy { $0.score <= best.score })
    }

    // MARK: - Temps avant rougeur

    @Test("Le temps avant rougeur tient compte de la montée du Soleil")
    func burnTimeFollowsTheRisingSun() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        let summer = plan(on: day(2026, 8, 13))
        let morning = try #require(calendar.date(
            bySettingHour: 7, minute: 30, second: 0, of: day(2026, 8, 13)))

        let integrated = try #require(DayPlanner.timeToErythema(
            from: morning, samples: summer.samples))

        // Le débit figé de 7 h 30 annoncerait près de sept heures ; en suivant
        // la course réelle du Soleil il n'en reste que deux. C'est tout l'objet
        // de ce calcul, et l'écart va dans le sens qui rassure à tort.
        let sample = try #require(summer.sample(nearest: morning))
        let frozen = 1.0 / sample.rates.medFractionPerMinute * 60
        #expect(integrated < frozen / 2)
        #expect(integrated > 60 * 60)
        #expect(integrated < 3 * 60 * 60)
    }

    @Test("Brûler devient impossible quand le Soleil descend")
    func burnBecomesImpossibleLateInTheDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        let summer = plan(on: day(2026, 8, 13))
        let evening = try #require(calendar.date(
            bySettingHour: 17, minute: 0, second: 0, of: day(2026, 8, 13)))

        // Le débit est encore non nul, donc la formule figée annoncerait un
        // délai fini — mais le Soleil se couche avant que la dose suffise.
        let sample = try #require(summer.sample(nearest: evening))
        #expect(sample.rates.medFractionPerMinute > 0)
        #expect(DayPlanner.timeToErythema(from: evening, samples: summer.samples) == nil)
    }

    @Test("Une fraction plus faible est atteinte plus tôt")
    func lowerFractionComesFirst() throws {
        let summer = plan(on: day(2026, 6, 21))
        let noon = summer.solarNoon
        let half = try #require(DayPlanner.timeToErythema(
            from: noon, samples: summer.samples, fraction: 0.5))
        let full = try #require(DayPlanner.timeToErythema(
            from: noon, samples: summer.samples, fraction: 1.0))
        #expect(half < full)
    }

    @Test("La nuit ne produit aucun créneau")
    func nightProducesNothing() throws {
        let summer = plan(on: day(2026, 6, 21))
        let firstSample = try #require(summer.samples.first)
        #expect(!firstSample.isSynthesisPossible)
        #expect(DayPlanner.simulateSession(
            startingAt: 0, samples: summer.samples, profile: .default) == nil)
    }
}
