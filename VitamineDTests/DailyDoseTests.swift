import Foundation
import Testing
@testable import VitamineD

/// Le capital cutané se compte par journée, jamais par sortie.
///
/// C'est le défaut le plus dangereux qu'ait connu l'application : deux sorties
/// à la moitié du seuil font une rougeur, et chacune s'affichait à 50 %.
struct DailyDoseTests {

    private let montreal = TimeZone(identifier: "America/Montreal")!

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = montreal
        return calendar
    }

    private func moment(_ hour: Int, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 21
        components.hour = hour; components.minute = minute
        return calendar.date(from: components)!
    }

    private func record(at date: Date, iu: Double, med: Double) -> SessionRecord {
        SessionRecord(id: UUID(), start: date, end: date.addingTimeInterval(1_800),
                      vitaminDIU: iu, medFraction: med,
                      locationName: "Montréal", exposedBodyPercentage: 35)
    }

    // MARK: - Cumul de la journée

    @Test("Les fractions de DEM de la journée s'additionnent")
    func medFractionsAddUpOverTheDay() {
        let history = [
            record(at: moment(9), iu: 400, med: 0.30),
            record(at: moment(13), iu: 600, med: 0.35),
            // La veille ne compte pas.
            record(at: moment(13).addingTimeInterval(-86_400), iu: 900, med: 0.50),
        ]

        let total = history.totalMEDFraction(on: moment(18), calendar: calendar)
        #expect(abs(total - 0.65) < 0.0001)
        #expect(abs(history.totalIU(on: moment(18), calendar: calendar) - 1_000) < 0.0001)
    }

    @Test("Une journée sans sortie ne consomme rien")
    func anEmptyDayCostsNothing() {
        #expect([SessionRecord]().totalMEDFraction(on: moment(12), calendar: calendar) == 0)
    }

    // MARK: - Niveau d'alerte

    @Test("Le niveau d'alerte juge la journée, pas la sortie")
    func burnLevelJudgesTheWholeDay() {
        var progress = SessionProgress(elapsed: 600, vitaminDIU: 300, rawVitaminDIU: 320,
                                       medFraction: 0.30, currentRates: .zero,
                                       marginalYield: 0.9)

        // Seule, cette sortie est anodine.
        #expect(progress.burnLevel(alertFraction: 0.6) == .safe)

        // Précédée d'une matinée à 40 %, elle franchit le seuil.
        progress.carriedMEDFraction = 0.40
        #expect(abs(progress.dayMEDFraction - 0.70) < 0.0001)
        #expect(progress.burnLevel(alertFraction: 0.6) >= .warning)
    }

    @Test("Les totaux de la journée se composent des deux parts")
    func dayTotalsCombineBothParts() {
        var progress = SessionProgress(elapsed: 600, vitaminDIU: 250, rawVitaminDIU: 260,
                                       medFraction: 0.20, currentRates: .zero,
                                       marginalYield: 0.8)
        progress.carriedMEDFraction = 0.15
        progress.carriedVitaminDIU = 400

        #expect(abs(progress.dayVitaminDIU - 650) < 0.0001)
        #expect(abs(progress.dayMEDFraction - 0.35) < 0.0001)

        // Sans rien d'hérité, les deux totaux valent la sortie seule.
        let alone = SessionProgress(elapsed: 600, vitaminDIU: 250, rawVitaminDIU: 260,
                                    medFraction: 0.20, currentRates: .zero,
                                    marginalYield: 0.8)
        #expect(alone.dayVitaminDIU == alone.vitaminDIU)
        #expect(alone.dayMEDFraction == alone.medFraction)
    }

    // MARK: - Créneaux proposés

    @Test("Un créneau proposé n'engage que le capital cutané restant")
    func recommendationsSpendOnlyWhatIsLeft() throws {
        let day = moment(12)
        let profile = UserProfile.default

        let morning = DayPlanner.makePlan(
            date: day, latitude: 45.5019, longitude: -73.5674,
            timeZone: montreal, profile: profile, carriedMED: 0, forecast: [])
        let afterALongMorning = DayPlanner.makePlan(
            date: day, latitude: 45.5019, longitude: -73.5674,
            timeZone: montreal, profile: profile,
            carriedMED: profile.burnAlertFraction * 0.75, forecast: [])

        let fresh = try #require(morning.bestRecommendation)
        let tired = try #require(afterALongMorning.bestRecommendation)

        // Il ne reste qu'un quart de l'allocation : le créneau proposé ne peut
        // pas en dépenser davantage.
        #expect(tired.medFraction <= profile.burnAlertFraction * 0.25 + 0.01)
        #expect(tired.medFraction < fresh.medFraction)
        #expect(tired.duration < fresh.duration)
    }

    @Test("Aucun créneau quand le capital du jour est épuisé")
    func noRecommendationsWhenTheDayIsSpent() {
        let day = moment(12)
        let profile = UserProfile.default

        let spent = DayPlanner.makePlan(
            date: day, latitude: 45.5019, longitude: -73.5674,
            timeZone: montreal, profile: profile,
            carriedMED: profile.burnAlertFraction, forecast: [])

        #expect(spent.recommendations.isEmpty)
    }
}
