import Foundation
import Testing
@testable import VitamineD

struct CircadianPlannerTests {

    // MARK: - Éclairement

    @Test("L'éclairement extérieur écrase celui d'une pièce, même sous les nuages")
    func outdoorsAlwaysBeatsIndoors() {
        // Une pièce bien éclairée plafonne vers 300 à 500 lux. C'est l'argument
        // central du calage circadien : une fenêtre ne suffit pas.
        let clearNoon = CircadianPlanner.illuminance(solarElevation: 60, cloudCover: 0)
        let overcastMorning = CircadianPlanner.illuminance(solarElevation: 20, cloudCover: 1)

        #expect(clearNoon > 80_000)
        // Même ciel bouché, Soleil bas : dix fois une pièce bien éclairée.
        #expect(overcastMorning > 10 * 500)
    }

    @Test("L'éclairement croît avec la hauteur du Soleil")
    func illuminanceRisesWithTheSun() {
        var previous = 0.0
        for elevation in stride(from: 0.0, through: 80.0, by: 5.0) {
            let value = CircadianPlanner.illuminance(solarElevation: elevation, cloudCover: 0)
            #expect(value > previous)
            previous = value
        }
    }

    @Test("Les nuages coupent le visible plus fort que l'ultraviolet")
    func cloudsCutVisibleMoreThanUltraviolet() {
        let clear = CircadianPlanner.illuminance(solarElevation: 40, cloudCover: 0)
        let overcast = CircadianPlanner.illuminance(solarElevation: 40, cloudCover: 1)
        let visibleTransmission = overcast / clear
        let ultravioletTransmission = UVEngine.cloudTransmission(cloudCoverFraction: 1)

        #expect(visibleTransmission < ultravioletTransmission)
        #expect(abs(visibleTransmission - 0.15) < 0.02)
    }

    @Test("La nuit ne porte aucun signal")
    func nightCarriesNothing() {
        #expect(CircadianPlanner.illuminance(solarElevation: -10, cloudCover: 0) == 0)
        #expect(CircadianPlanner.LightQuality(
            illuminance: CircadianPlanner.illuminance(solarElevation: -10, cloudCover: 0))
                == .insufficient)
    }

    @Test("Les paliers de qualité sont ordonnés et proposent des durées croissantes")
    func qualityBandsAreOrdered() throws {
        let bands: [CircadianPlanner.LightQuality] = [
            .init(illuminance: 500),
            .init(illuminance: 3_000),
            .init(illuminance: 8_000),
            .init(illuminance: 25_000),
            .init(illuminance: 60_000),
        ]
        #expect(bands == [.insufficient, .weak, .moderate, .good, .excellent])
        #expect(bands[0] < bands[4])

        // Moins de lumière, plus de temps : les durées vont en décroissant
        // quand la qualité monte.
        let durations = try bands.dropFirst().map {
            try #require($0.recommendedMinutes).lowerBound
        }
        #expect(durations == durations.sorted(by: >))
        #expect(CircadianPlanner.LightQuality.insufficient.recommendedMinutes == nil)
    }

    // MARK: - Fenêtre du matin

    private let montreal = TimeZone(identifier: "America/Montreal")!

    private func summerPlan(_ month: Int = 6, _ dayOfMonth: Int = 21) -> DayPlan {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        var components = DateComponents()
        components.year = 2026; components.month = month; components.day = dayOfMonth
        components.hour = 12
        let date = calendar.date(from: components)!

        return DayPlanner.makePlan(
            date: date, latitude: 45.5019, longitude: -73.5674,
            timeZone: montreal, profile: .default, forecast: [])
    }

    private func moment(_ hour: Int, _ minute: Int, on plan: DayPlan) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: plan.date)!
    }

    @Test("La fenêtre commence au réveil quand le Soleil est déjà levé")
    func windowStartsAtWakingInSummer() throws {
        let plan = summerPlan()
        let wake = moment(7, 0, on: plan)
        let light = try #require(CircadianPlanner.morningLight(
            wakeTime: wake, samples: plan.samples, sunrise: plan.sunrise))

        // Le Soleil se lève vers 5 h en juin : le réveil est bien postérieur.
        #expect(abs(light.window.start.timeIntervalSince(wake)) < 60)
        #expect(!light.sunRisesAfterWaking)
        #expect(light.window.duration == CircadianPlanner.morningWindowDuration)
    }

    @Test("La fenêtre attend le lever quand on se réveille avant lui")
    func windowWaitsForSunriseInWinter() throws {
        let plan = summerPlan(12, 21)
        let sunrise = try #require(plan.sunrise)
        let wake = moment(5, 30, on: plan)
        let light = try #require(CircadianPlanner.morningLight(
            wakeTime: wake, samples: plan.samples, sunrise: sunrise))

        #expect(light.sunRisesAfterWaking)
        #expect(light.window.start >= sunrise)
        // Sortir avant le lever n'apporterait rien : la fenêtre ne commence pas
        // au réveil.
        #expect(light.window.start > wake)
    }

    @Test("Le meilleur moment de la fenêtre est le plus lumineux")
    func bestMomentIsTheBrightest() throws {
        let plan = summerPlan()
        let light = try #require(CircadianPlanner.morningLight(
            wakeTime: moment(7, 0, on: plan), samples: plan.samples, sunrise: plan.sunrise))

        #expect(light.window.contains(light.best))
        // Le Soleil monte tout au long de la matinée : le meilleur instant est
        // donc vers la fin de la fenêtre.
        #expect(light.best > light.window.start.addingTimeInterval(3600))
        #expect(light.quality >= .good)
    }

    @Test("La nuit polaire ne produit aucune fenêtre exploitable")
    func polarNightHasNoUsefulWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        var components = DateComponents()
        components.year = 2026; components.month = 12; components.day = 21
        components.hour = 12
        let plan = DayPlanner.makePlan(
            date: calendar.date(from: components)!,
            latitude: 69.65, longitude: 18.96,
            timeZone: montreal, profile: .default, forecast: [])

        let light = CircadianPlanner.morningLight(
            wakeTime: calendar.date(bySettingHour: 8, minute: 0, second: 0, of: plan.date)!,
            samples: plan.samples, sunrise: plan.sunrise)

        // Soit aucune fenêtre, soit une fenêtre où il n'y a rien à capter.
        if let light { #expect(light.quality == .insufficient) }
    }

    // MARK: - Déplacement de phase

    @Test("Le déplacement respecte le pas quotidien")
    func shiftRespectsTheDailyStep() {
        // Vouloir se lever une heure et demie plus tôt.
        let plan = CircadianPlanner.phaseShift(current: 8 * 60, target: 6 * 60 + 30,
                                               sleepDuration: 8)
        #expect(plan.shiftMinutes == -90)
        #expect(plan.nextWakeMinuteOfDay == 8 * 60 - CircadianPlanner.maximumDailyShift)
        #expect(plan.days == 3)
    }

    @Test("Aucun déplacement demandé, aucun jour annoncé")
    func noShiftMeansNoDays() {
        let plan = CircadianPlanner.phaseShift(current: 7 * 60, target: 7 * 60, sleepDuration: 8)
        #expect(plan.shiftMinutes == 0)
        #expect(plan.days == 0)
        #expect(plan.nextWakeMinuteOfDay == 7 * 60)
    }

    @Test("Le chemin le plus court sur le cadran est choisi")
    func shortestPathAroundTheClock() {
        // Se lever à 23 h et viser 6 h : c'est une avance de sept heures,
        // pas un recul de dix-sept.
        let plan = CircadianPlanner.phaseShift(current: 23 * 60, target: 6 * 60,
                                               sleepDuration: 8)
        #expect(plan.shiftMinutes == 420)
        // On avance donc l'heure du lever de trente minutes : 23 h 30, et non
        // un recul vers 22 h 30.
        #expect(plan.nextWakeMinuteOfDay == 23 * 60 + 30)
    }

    @Test("L'heure de pénombre précède le coucher visé")
    func dimLightPrecedesBedtime() {
        let plan = CircadianPlanner.phaseShift(current: 7 * 60, target: 7 * 60, sleepDuration: 8)
        // Lever 7 h, huit heures de sommeil → coucher 23 h ; pénombre deux
        // heures et demie avant, soit 20 h 30.
        #expect(plan.dimLightMinuteOfDay == 20 * 60 + 30)
    }

    @Test("Un coucher après minuit ne déborde pas du cadran")
    func lateBedtimeWrapsCorrectly() {
        // Lever 6 h, cinq heures de sommeil → coucher 1 h du matin ;
        // pénombre à 22 h 30 la veille.
        let plan = CircadianPlanner.phaseShift(current: 6 * 60, target: 6 * 60, sleepDuration: 5)
        #expect((0..<1440).contains(plan.dimLightMinuteOfDay))
        #expect(plan.dimLightMinuteOfDay == 22 * 60 + 30)
    }
}
