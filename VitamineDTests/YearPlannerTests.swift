import Foundation
import Testing
@testable import VitamineD

struct YearPlannerTests {

    private let montreal = TimeZone(identifier: "America/Montreal")!
    private let montrealLat = 45.5019
    private let montrealLon = -73.5674

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = dayOfMonth
        components.hour = 12
        return calendar.date(from: components)!
    }

    private func outlook(on date: Date,
                         latitude: Double? = nil,
                         longitude: Double? = nil) -> YearOutlook {
        YearPlanner.outlook(containing: date,
                            latitude: latitude ?? montrealLat,
                            longitude: longitude ?? montrealLon,
                            timeZone: montreal)
    }

    // MARK: - La courbe

    @Test("L'année civile est complète et va d'un solstice à l'autre")
    func theYearIsComplete() {
        let year = outlook(on: day(2026, 8, 13))

        #expect(year.year == 2026)
        #expect(year.days.count >= 365)
        #expect(year.days.allSatisfy { calendar.component(.year, from: $0.date) == 2026 })

        // 90° − |latitude − déclinaison|, aux deux solstices.
        #expect(abs(year.highestElevation - 67.9) < 1.0)
        #expect(abs(year.lowestElevation - 21.1) < 1.0)
    }

    @Test("La courbe culmine au solstice d'été et touche le fond à celui d'hiver")
    func theCurvePeaksAtTheSolstices() throws {
        let year = outlook(on: day(2026, 8, 13))
        let highest = try #require(year.days.max { $0.peakElevation < $1.peakElevation })
        let lowest = try #require(year.days.min { $0.peakElevation < $1.peakElevation })

        #expect(calendar.component(.month, from: highest.date) == 6)
        #expect(abs(calendar.component(.day, from: highest.date) - 21) <= 2)
        #expect(calendar.component(.month, from: lowest.date) == 12)
        #expect(abs(calendar.component(.day, from: lowest.date) - 21) <= 2)
    }

    // MARK: - L'hiver

    @Test("Montréal connaît un hiver vitaminique du 19 novembre au 22 janvier")
    func montrealHasAWinter() throws {
        let year = outlook(on: day(2026, 8, 13))
        let winter = try #require(year.winter)
        // La borne de fin est le minuit suivant le dernier jour creux.
        let lastDay = winter.end.addingTimeInterval(-1)

        #expect(year.hasWinter)
        #expect(calendar.component(.month, from: winter.start) == 11)
        #expect(abs(calendar.component(.day, from: winter.start) - 19) <= 1)
        #expect(calendar.component(.month, from: lastDay) == 1)
        #expect(abs(calendar.component(.day, from: lastDay) - 22) <= 1)

        // Deux mois pleins, et non les quatre que la sagesse populaire annonce :
        // le seuil de 25° est franchi bien avant l'équinoxe de printemps.
        #expect(winter.duration > 55 * 86_400)
        #expect(winter.duration < 75 * 86_400)
        #expect(winter.contains(day(2026, 12, 21)))
        #expect(!winter.contains(day(2026, 9, 21)))
    }

    @Test("L'hiver reste d'un seul tenant quand on le regarde en janvier")
    func winterIsNotCutByNewYear() throws {
        // Le piège : balayer la seule année civile couperait cet hiver-là en
        // deux, et l'application annoncerait un hiver commençant le 1er janvier.
        let january = outlook(on: day(2026, 1, 15))
        let winter = try #require(january.winter)

        #expect(winter.contains(day(2026, 1, 15)))
        #expect(calendar.component(.year, from: winter.start) == 2025)
        #expect(calendar.component(.month, from: winter.start) == 11)
        #expect(january.daysUntilWinter(from: day(2026, 1, 15)) == nil)
        #expect(january.isInWinter(day(2026, 1, 15)))
    }

    @Test("Sous les tropiques, aucun hiver vitaminique")
    func tropicsHaveNoWinter() {
        // Miami, 25,8° N : au solstice d'hiver le Soleil culmine encore à 40°.
        let year = outlook(on: day(2026, 8, 13), latitude: 25.76, longitude: -80.19)

        // `allSatisfy` est `rethrows` : passé un chemin de clé directement à
        // `#expect`, la macro l'enveloppe dans un contexte où l'appel devient
        // potentiellement lançant. On évalue donc avant.
        let everyDayProduces = year.days.allSatisfy(\.producesVitaminD)

        #expect(!year.hasWinter)
        #expect(year.winter == nil)
        #expect(year.lowestElevation > UVEngine.vitaminDWinterElevation)
        #expect(everyDayProduces)
    }

    @Test("Au cercle polaire, l'hiver dure la moitié de l'année")
    func theArcticWinterIsLong() throws {
        // Tromsø, 69,65° N.
        let year = outlook(on: day(2026, 8, 13), latitude: 69.65, longitude: 18.96)
        let winter = try #require(year.winter)

        #expect(winter.duration > 150 * 86_400)
        #expect(year.optimalSeason == nil)
    }

    // MARK: - Saisons

    @Test("La saison optimale encadre le solstice d'été")
    func optimalSeasonSurroundsMidsummer() throws {
        let year = outlook(on: day(2026, 8, 13))
        let optimal = try #require(year.optimalSeason)
        let useful = try #require(year.usefulSeason)

        #expect(optimal.contains(day(2026, 6, 21)))
        // La règle de l'ombre est plus exigeante que le seuil de synthèse : sa
        // saison est nécessairement plus courte, et contenue dans l'autre.
        #expect(optimal.duration < useful.duration)
        #expect(useful.start <= optimal.start)
        #expect(useful.end >= optimal.end)
    }

    @Test("Le décompte des jours utiles diminue à mesure qu'on approche de l'hiver")
    func remainingDaysShrink() {
        let year = outlook(on: day(2026, 8, 13))
        let august = year.remainingUsefulDays(from: day(2026, 8, 13))
        let october = year.remainingUsefulDays(from: day(2026, 10, 13))

        #expect(august > october)
        #expect(october > 0)
        #expect(year.remainingOptimalDays(from: day(2026, 8, 13)) < august)
        // Une fois dans l'hiver, il ne reste rien à compter.
        #expect(year.remainingUsefulDays(from: day(2026, 12, 1)) == 0)
    }

    @Test("Le jour le plus proche d'une date se retrouve")
    func nearestDayIsFound() throws {
        let year = outlook(on: day(2026, 8, 13))
        let found = try #require(year.day(nearest: day(2026, 6, 21)))
        #expect(calendar.isDate(found.date, inSameDayAs: day(2026, 6, 21)))
    }
}

struct WinterPlannerTests {

    private let montreal = TimeZone(identifier: "America/Montreal")!

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        var components = DateComponents()
        components.year = year; components.month = month; components.day = dayOfMonth
        components.hour = 12
        return calendar.date(from: components)!
    }

    private func record(on date: Date, iu: Double) -> SessionRecord {
        SessionRecord(id: UUID(), start: date, end: date.addingTimeInterval(1_800),
                      vitaminDIU: iu, medFraction: 0.3,
                      locationName: "Montréal", exposedBodyPercentage: 30)
    }

    // MARK: - Décroissance

    @Test("Une demi-vie retire la moitié")
    func halfLifeHalves() {
        #expect(abs(WinterPlanner.remainingFraction(afterDays: 0) - 1.0) < 0.001)
        #expect(abs(WinterPlanner.remainingFraction(
            afterDays: WinterPlanner.halfLifeDays) - 0.5) < 0.001)
        #expect(abs(WinterPlanner.remainingFraction(
            afterDays: 2 * WinterPlanner.halfLifeDays) - 0.25) < 0.001)
        // Une date antérieure ne fait pas remonter la réserve.
        #expect(WinterPlanner.remainingFraction(afterDays: -10) == 1)
    }

    @Test("La réserve additionne les sorties passées, chacune amortie")
    func reserveSumsDecayedSessions() {
        let today = day(2026, 9, 1)
        let history = [
            record(on: today, iu: 1_000),
            record(on: day(2026, 8, 12), iu: 1_000),   // vingt jours plus tôt
        ]
        let reserve = WinterPlanner.reserve(on: today, history: history)

        // Mille pleins, plus cinq cents amortis d'une demi-vie.
        #expect(abs(reserve - 1_500) < 20)

        // Une sortie postérieure à la date demandée ne compte pas.
        let withFuture = history + [record(on: day(2026, 10, 1), iu: 5_000)]
        #expect(abs(WinterPlanner.reserve(on: today, history: withFuture) - reserve) < 0.001)
    }

    @Test("La réserve vide reste vide")
    func emptyHistoryGivesNothing() {
        #expect(WinterPlanner.reserve(on: day(2026, 9, 1), history: []) == 0)
    }

    @Test("L'apport quotidien équivalent correspond au régime permanent")
    func equivalentDailyIntakeMatchesSteadyState() {
        // Une même dose chaque jour depuis longtemps : la réserve tend vers
        // apport × constante de temps. On vérifie l'aller-retour.
        let daily = 800.0
        let reserve = daily * WinterPlanner.timeConstantDays
        #expect(abs(WinterPlanner.equivalentDailyIU(reserve: reserve) - daily) < 0.001)
    }

    @Test("La projection décroît sans jamais remonter")
    func projectionOnlyFalls() throws {
        let start = day(2026, 9, 1)
        let points = WinterPlanner.projection(
            from: start, reserve: 10_000, through: day(2026, 12, 21))

        #expect(points.count > 10)
        #expect(points.first?.reserve == 10_000)
        let values = points.map(\.reserve)
        #expect(values == values.sorted(by: >))
        // Cent onze jours, soit plus de cinq demi-vies : il ne reste presque rien.
        let last = try #require(values.last)
        #expect(last < 10_000 * 0.05)
    }

    // MARK: - Bilan

    @Test("Le bilan d'avant-hiver compte les jours et amortit la réserve")
    func planCountsDaysAndDecaysReserve() throws {
        let today = day(2026, 9, 1)
        let outlook = YearPlanner.outlook(containing: today,
                                          latitude: 45.5019, longitude: -73.5674,
                                          timeZone: montreal)
        let plan = try #require(WinterPlanner.plan(
            on: today, outlook: outlook, history: [record(on: today, iu: 2_000)]))

        #expect(!plan.hasStarted)
        #expect(plan.daysUntilStart > 50)
        #expect(plan.daysUntilStart < 90)
        #expect(plan.usefulDaysLeft > 0)
        #expect(plan.optimalDaysLeft <= plan.usefulDaysLeft)
        #expect(plan.reserve == 2_000)

        // Le cœur de l'hiver est à plus de trois demi-vies : l'essentiel de ce
        // qu'on emmagasine en septembre a disparu. C'est le message de la carte.
        #expect(plan.midwinterFraction < 0.15)
        #expect(plan.midwinter > plan.winter.start)
        #expect(plan.midwinter < plan.winter.end)
    }

    @Test("Aucun bilan sous les tropiques")
    func noPlanWithoutWinter() {
        let today = day(2026, 9, 1)
        let outlook = YearPlanner.outlook(containing: today,
                                          latitude: 25.76, longitude: -80.19,
                                          timeZone: montreal)
        #expect(WinterPlanner.plan(on: today, outlook: outlook, history: []) == nil)
    }
}
