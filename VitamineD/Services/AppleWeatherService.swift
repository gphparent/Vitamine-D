import CoreLocation
import Foundation
import WeatherKit

/// Prévisions par WeatherKit, avec repli sur Open-Meteo.
///
/// Le changement est d'abord juridique : l'usage gratuit d'Open-Meteo est
/// réservé aux projets non commerciaux, ce qu'une application distribuée sur
/// l'App Store n'est plus. WeatherKit est inclus dans le compte développeur et
/// n'impose qu'une contrainte d'attribution, honorée dans « Méthode et limites ».
///
/// Il impose en revanche une contrainte technique qu'il faut regarder en face :
/// **l'indice UV y est un entier**. Le prendre tel quel donnerait une courbe en
/// escalier, et surtout une intégration fausse — le temps avant rougeur se
/// calcule en cumulant le débit minute par minute, et un palier de 3 là où la
/// valeur réelle vaut 3,4 se paie en erreur de plus de dix pour cent sur toute
/// la durée annoncée.
///
/// La parade est de combiner les deux sources d'information. La couverture
/// nuageuse de WeatherKit, elle, est continue et bien mesurée : appliquée au
/// modèle de ciel clair, elle donne une courbe lisse. On la contraint ensuite à
/// rester dans la demi-unité de l'entier fourni par Apple, qui reste
/// l'autorité. On obtient une valeur continue qui ne contredit jamais la source.
struct AppleWeatherService: WeatherProviding {

    private let fallback: any WeatherProviding
    private let environment: EnvironmentFactors

    init(fallback: any WeatherProviding = OpenMeteoService(),
         environment: EnvironmentFactors = .standard) {
        self.fallback = fallback
        self.environment = environment
    }

    func snapshot(latitude: Double, longitude: Double, days: Int = 3) async throws -> WeatherSnapshot {
        do {
            return try await appleSnapshot(latitude: latitude, longitude: longitude, days: days)
        } catch {
            // WeatherKit peut échouer pour des raisons qui n'ont rien à voir
            // avec le réseau — droit d'application absent, quota, région non
            // couverte. Le repli garde l'application utilisable dans tous ces
            // cas, au lieu de la laisser sans données.
            return try await fallback.snapshot(latitude: latitude, longitude: longitude, days: days)
        }
    }

    // MARK: - WeatherKit

    private func appleSnapshot(latitude: Double,
                               longitude: Double,
                               days: Int) async throws -> WeatherSnapshot {

        let location = CLLocation(latitude: latitude, longitude: longitude)
        let start = Calendar.current.startOfDay(for: Date())
        let end = start.addingTimeInterval(TimeInterval(days) * 86_400)

        let forecast = try await WeatherKit.WeatherService.shared.weather(
            for: location, including: .hourly(startDate: start, endDate: end))

        let series = forecast.forecast.map { hour -> UVConditions in
            let position = SolarCalculator.position(
                date: hour.date, latitude: latitude, longitude: longitude)
            let clearSky = UVEngine.modelledClearSkyUVIndex(
                solarElevation: position.elevation, environment: environment)

            return UVConditions(
                date: hour.date,
                uvIndex: reconciledUVIndex(reported: hour.uvIndex.value,
                                           clearSky: clearSky,
                                           cloudCover: hour.cloudCover),
                uvIndexClearSky: clearSky,
                cloudCover: hour.cloudCover,
                temperature: hour.temperature.converted(to: .celsius).value,
                apparentTemperature: hour.apparentTemperature.converted(to: .celsius).value,
                precipitationProbability: hour.precipitationChance,
                windSpeed: hour.wind.speed.converted(to: .kilometersPerHour).value,
                weatherCode: WeatherCode.wmoCode(for: hour.condition)
            )
        }

        guard !series.isEmpty else { throw WeatherServiceError.malformedPayload }

        return WeatherSnapshot(
            fetchedAt: Date(),
            latitude: latitude,
            longitude: longitude,
            // WeatherKit ne renvoie pas l'altitude du terrain. Celle du GPS,
            // que le modèle utilise déjà, prend le relais.
            altitude: 0,
            timeZone: await timeZone(for: location),
            hourly: series.sorted { $0.date < $1.date },
            isModelled: false
        )
    }

    /// Concilie l'entier d'Apple et la courbe continue déduite des nuages.
    ///
    /// L'entier reste l'autorité : la valeur retenue ne s'en écarte jamais de
    /// plus d'une demi-unité, ce qui est exactement l'incertitude introduite
    /// par l'arrondi. À l'intérieur de cette marge, c'est la physique qui
    /// décide, et la courbe redevient lisse.
    private func reconciledUVIndex(reported: Int,
                                   clearSky: Double,
                                   cloudCover: Double) -> Double {
        let modelled = clearSky * UVEngine.cloudTransmission(cloudCoverFraction: cloudCover)
        let floor = max(0, Double(reported) - 0.5)
        let ceiling = Double(reported) + 0.5
        return min(max(modelled, floor), ceiling)
    }

    /// Fuseau horaire du lieu.
    ///
    /// Indispensable, et absent de WeatherKit : sans lui, un lieu choisi à la
    /// main afficherait ses créneaux à l'heure du téléphone. Le géocodeur
    /// inverse le donne ; à défaut, on retombe sur le fuseau courant.
    private func timeZone(for location: CLLocation) async -> TimeZone {
        let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks?.first?.timeZone ?? .current
    }
}

extension WeatherCode {

    /// Traduit une condition WeatherKit vers le code WMO que le reste de
    /// l'application manipule.
    ///
    /// La correspondance n'est pas bijective — les deux nomenclatures ne
    /// découpent pas le temps de la même façon — mais elle n'a besoin d'être
    /// juste que sur ce dont l'application se sert : la description affichée,
    /// le symbole, et surtout la présence de neige au sol, qui double l'albédo
    /// et explique les coups de soleil de ski.
    static func wmoCode(for condition: WeatherCondition) -> Int {
        switch condition {
        case .clear, .hot:                      return 0
        case .mostlyClear:                      return 1
        case .partlyCloudy:                     return 2
        case .cloudy, .mostlyCloudy, .smoky, .haze, .blowingDust, .breezy, .windy:
            return 3
        case .foggy:                            return 45
        case .drizzle:                          return 51
        case .rain:                             return 61
        case .heavyRain:                        return 65
        case .freezingDrizzle, .freezingRain:   return 66
        case .sleet, .wintryMix:                return 68
        case .flurries, .snow:                  return 71
        case .heavySnow, .blizzard, .blowingSnow:
            return 75
        case .hail:                             return 77
        case .sunShowers:                       return 80
        case .thunderstorms, .strongStorms, .isolatedThunderstorms, .scatteredThunderstorms:
            return 95
        case .sunFlurries, .frigid:             return 73
        case .hurricane, .tropicalStorm:        return 82
        @unknown default:                       return 3
        }
    }
}
