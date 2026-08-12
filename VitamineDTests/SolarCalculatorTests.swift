import Foundation
import Testing
@testable import VitamineD

/// Les valeurs de référence proviennent du NOAA Solar Calculator et de
/// timeanddate.com. La tolérance retenue — 0,3° sur les hauteurs, 2 minutes sur
/// les instants — est bien inférieure à ce que la variabilité biologique rend
/// significatif.
struct SolarCalculatorTests {

    private func utc(_ year: Int, _ month: Int, _ day: Int,
                     _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private var montrealCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Montreal")!
        return calendar
    }

    private let montrealLat = 45.5019
    private let montrealLon = -73.5674

    @Test("Le jour julien de l'époque Unix est exact")
    func julianDayEpoch() {
        let epoch = Date(timeIntervalSince1970: 0)
        #expect(abs(SolarCalculator.julianDay(for: epoch) - 2440587.5) < 1e-6)
    }

    @Test("Déclinaison au solstice d'été")
    func summerSolsticeDeclination() {
        let position = SolarCalculator.position(
            date: utc(2026, 6, 21, 16, 56), latitude: montrealLat, longitude: montrealLon)
        #expect(abs(position.declination - 23.44) < 0.1)
    }

    @Test("Déclinaison quasi nulle à l'équinoxe")
    func equinoxDeclination() {
        let position = SolarCalculator.position(
            date: utc(2026, 3, 20, 12, 0), latitude: 0, longitude: 0)
        #expect(abs(position.declination) < 0.5)
    }

    @Test("Hauteur maximale à Montréal au solstice d'été")
    func summerPeakElevation() {
        // 90° − latitude + déclinaison = 90 − 45,50 + 23,44 ≈ 67,94°
        let position = SolarCalculator.position(
            date: utc(2026, 6, 21, 16, 56), latitude: montrealLat, longitude: montrealLon)
        #expect(abs(position.elevation - 67.94) < 0.3)
    }

    @Test("Hauteur maximale à Montréal au solstice d'hiver")
    func winterPeakElevation() {
        let noon = SolarCalculator.solarNoon(
            on: utc(2026, 12, 21, 12, 0), latitude: montrealLat, longitude: montrealLon,
            calendar: montrealCalendar)
        let position = SolarCalculator.position(
            date: noon, latitude: montrealLat, longitude: montrealLon)
        #expect(abs(position.elevation - 21.1) < 0.3)
    }

    @Test("Le midi solaire tombe à l'heure attendue")
    func solarNoonTiming() {
        let noon = SolarCalculator.solarNoon(
            on: utc(2026, 6, 21, 12, 0), latitude: montrealLat, longitude: montrealLon,
            calendar: montrealCalendar)
        let components = montrealCalendar.dateComponents([.hour, .minute], from: noon)
        // Midi solaire à Montréal fin juin : 12 h 56 heure avancée de l'Est.
        #expect(components.hour == 12)
        #expect(abs((components.minute ?? 0) - 56) <= 2)
    }

    @Test("Le midi solaire est bien le maximum de la journée")
    func solarNoonIsMaximum() {
        let noon = SolarCalculator.solarNoon(
            on: utc(2026, 9, 15, 12, 0), latitude: montrealLat, longitude: montrealLon,
            calendar: montrealCalendar)
        let atNoon = SolarCalculator.position(
            date: noon, latitude: montrealLat, longitude: montrealLon).elevation

        for offset in stride(from: -180.0, through: 180.0, by: 15) where offset != 0 {
            let other = SolarCalculator.position(
                date: noon.addingTimeInterval(offset * 60),
                latitude: montrealLat, longitude: montrealLon).elevation
            #expect(other <= atNoon + 1e-6)
        }
    }

    @Test("Lever et coucher à Montréal au solstice d'été")
    func summerSunriseSunset() throws {
        let (sunrise, sunset) = SolarCalculator.sunriseSunset(
            on: utc(2026, 6, 21, 12, 0), latitude: montrealLat, longitude: montrealLon,
            calendar: montrealCalendar)

        let riseComponents = montrealCalendar.dateComponents([.hour, .minute], from: try #require(sunrise))
        let setComponents = montrealCalendar.dateComponents([.hour, .minute], from: try #require(sunset))

        // Références : 05 h 06 et 20 h 47, heure avancée de l'Est.
        #expect(riseComponents.hour == 5)
        #expect(abs((riseComponents.minute ?? 0) - 6) <= 2)
        #expect(setComponents.hour == 20)
        #expect(abs((setComponents.minute ?? 0) - 47) <= 2)
    }

    @Test("La réfraction n'est pas comptée deux fois au lever")
    func refractionNotDoubleCounted() throws {
        // Au seuil conventionnel de -0,833°, la hauteur géométrique doit valoir
        // exactement ce seuil : si l'on comparait la hauteur apparente, le Soleil
        // se lèverait environ deux minutes trop tôt.
        let (sunrise, _) = SolarCalculator.sunriseSunset(
            on: utc(2026, 6, 21, 12, 0), latitude: montrealLat, longitude: montrealLon,
            calendar: montrealCalendar)
        let position = SolarCalculator.position(
            date: try #require(sunrise), latitude: montrealLat, longitude: montrealLon)
        #expect(abs(position.trueElevation - (-0.833)) < 0.05)
        #expect(position.elevation > position.trueElevation)
    }

    @Test("Nuit polaire à Tromsø")
    func polarNight() {
        let (sunrise, sunset) = SolarCalculator.sunriseSunset(
            on: utc(2026, 12, 21, 12, 0), latitude: 69.65, longitude: 18.96,
            calendar: Calendar(identifier: .gregorian))
        #expect(sunrise == nil)
        #expect(sunset == nil)
    }

    @Test("Jour polaire à Tromsø")
    func midnightSun() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Oslo")!
        let crossings = SolarCalculator.crossings(
            of: -0.833, on: utc(2026, 6, 21, 12, 0), latitude: 69.65, longitude: 18.96,
            calendar: calendar, geometric: true)
        // Le Soleil ne descend jamais sous l'horizon : un seul intervalle,
        // couvrant toute la journée.
        #expect(crossings.count == 1)
        #expect(try #require(crossings.first).duration > 23 * 3600)
    }

    @Test("Hémisphère sud : hauteur maximale à Sydney en décembre")
    func southernHemisphere() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Australia/Sydney")!
        let noon = SolarCalculator.solarNoon(
            on: utc(2026, 12, 21, 0, 0), latitude: -33.87, longitude: 151.21, calendar: calendar)
        let position = SolarCalculator.position(
            date: noon, latitude: -33.87, longitude: 151.21)
        #expect(abs(position.elevation - 79.57) < 0.5)
    }

    @Test("La règle de l'ombre coïncide avec 45° de hauteur")
    func shadowRule() throws {
        let high = SolarPosition(elevation: 45, trueElevation: 45, azimuth: 180,
                                 declination: 0, equationOfTime: 0)
        #expect(abs(try #require(high.shadowRatio) - 1.0) < 0.01)

        let higher = SolarPosition(elevation: 60, trueElevation: 60, azimuth: 180,
                                   declination: 0, equationOfTime: 0)
        #expect(try #require(higher.shadowRatio) < 1.0)

        let below = SolarPosition(elevation: 0.2, trueElevation: 0.2, azimuth: 90,
                                  declination: 0, equationOfTime: 0)
        #expect(below.shadowRatio == nil)
    }

    @Test("La masse d'air vaut 1 au zénith et croît à l'horizon")
    func airMass() {
        let zenith = SolarPosition(elevation: 90, trueElevation: 90, azimuth: 180,
                                   declination: 0, equationOfTime: 0)
        #expect(abs(zenith.airMass - 1.0) < 0.01)

        let low = SolarPosition(elevation: 10, trueElevation: 10, azimuth: 180,
                                declination: 0, equationOfTime: 0)
        #expect(low.airMass > 5 && low.airMass < 6)
    }

    @Test("Les croisements d'un seuil sont ordonnés et cohérents")
    func thresholdCrossings() throws {
        let intervals = SolarCalculator.crossings(
            of: UVEngine.optimalSynthesisElevation,
            on: utc(2026, 6, 21, 12, 0),
            latitude: montrealLat, longitude: montrealLon,
            calendar: montrealCalendar)

        #expect(intervals.count == 1)
        let window = try #require(intervals.first)
        #expect(window.duration > 5 * 3600)

        // Aux bornes, la hauteur doit valoir le seuil ; au milieu, le dépasser.
        for boundary in [window.start, window.end] {
            let elevation = SolarCalculator.position(
                date: boundary, latitude: montrealLat, longitude: montrealLon).elevation
            #expect(abs(elevation - UVEngine.optimalSynthesisElevation) < 0.1)
        }
        let middle = Date(timeIntervalSince1970:
            (window.start.timeIntervalSince1970 + window.end.timeIntervalSince1970) / 2)
        #expect(SolarCalculator.position(date: middle, latitude: montrealLat,
                                         longitude: montrealLon).elevation > 45)
    }

    @Test("Aucune fenêtre à 45° en décembre à Montréal")
    func noOptimalWindowInWinter() {
        let intervals = SolarCalculator.crossings(
            of: UVEngine.optimalSynthesisElevation,
            on: utc(2026, 12, 21, 12, 0),
            latitude: montrealLat, longitude: montrealLon,
            calendar: montrealCalendar)
        #expect(intervals.isEmpty)
    }
}
