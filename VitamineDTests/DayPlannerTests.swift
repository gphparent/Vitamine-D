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

    @Test("La nuit ne produit aucun créneau")
    func nightProducesNothing() throws {
        let summer = plan(on: day(2026, 6, 21))
        let firstSample = try #require(summer.samples.first)
        #expect(!firstSample.isSynthesisPossible)
        #expect(DayPlanner.simulateSession(
            startingAt: 0, samples: summer.samples, profile: .default) == nil)
    }
}
