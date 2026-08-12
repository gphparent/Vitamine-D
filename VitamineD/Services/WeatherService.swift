import Foundation

/// Instantané météo et UV pour un lieu, sur plusieurs jours.
struct WeatherSnapshot: Equatable, Sendable {
    let fetchedAt: Date
    let latitude: Double
    let longitude: Double
    /// Altitude du terrain telle que renvoyée par le modèle, en mètres.
    let altitude: Double
    let timeZone: TimeZone
    /// Série horaire, triée par date croissante.
    let hourly: [UVConditions]
    /// Vrai lorsque les données proviennent du modèle interne, faute de réseau.
    let isModelled: Bool

    func conditions(at date: Date) -> UVConditions? {
        hourly.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    func hourly(on day: Date, calendar: Calendar) -> [UVConditions] {
        let start = calendar.startOfDay(for: day)
        let end = start.addingTimeInterval(86_400)
        return hourly.filter { $0.date >= start && $0.date < end }
    }
}

enum WeatherServiceError: LocalizedError {
    case badResponse(Int)
    case malformedPayload
    case seriesMismatch

    var errorDescription: String? {
        switch self {
        case .badResponse(let code):
            return "Le service météo a répondu avec le code \(code)."
        case .malformedPayload:
            return "La réponse du service météo est illisible."
        case .seriesMismatch:
            return "Les séries météo et UV ne concordent pas."
        }
    }
}

/// Accès aux prévisions Open-Meteo.
///
/// Deux points d'entrée sont nécessaires : l'indice UV vit dans l'API qualité de
/// l'air, la météo de surface dans l'API prévision. Les deux sont interrogées en
/// parallèle, puis fusionnées sur l'horodatage.
///
/// Open-Meteo ne demande pas de clé d'API. Son usage gratuit est réservé aux
/// projets non commerciaux ; une distribution sur l'App Store demanderait soit
/// un abonnement, soit un basculement vers WeatherKit.
protocol WeatherProviding: Sendable {
    func snapshot(latitude: Double, longitude: Double, days: Int) async throws -> WeatherSnapshot
}

struct OpenMeteoService: WeatherProviding {

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func snapshot(latitude: Double, longitude: Double, days: Int = 3) async throws -> WeatherSnapshot {
        async let weather = fetchWeather(latitude: latitude, longitude: longitude, days: days)
        async let air = fetchAirQuality(latitude: latitude, longitude: longitude, days: days)
        let (weatherPayload, airPayload) = try await (weather, air)

        // Les séries d'Open-Meteo admettent des trous : chaque élément est un
        // Double optionnel. On les aplatit ici une bonne fois pour toutes.
        func value(_ series: [Double?], _ index: Int, fallback: Double = 0) -> Double {
            guard series.indices.contains(index), let value = series[index] else { return fallback }
            return value
        }

        let airHours = airPayload.hourly
        var uvByTime: [Int: (uv: Double, clearSky: Double)] = [:]
        uvByTime.reserveCapacity(airHours.time.count)
        for (index, timestamp) in airHours.time.enumerated() {
            uvByTime[timestamp] = (value(airHours.uv_index, index),
                                   value(airHours.uv_index_clear_sky, index))
        }

        let hours = weatherPayload.hourly
        var series: [UVConditions] = []
        series.reserveCapacity(hours.time.count)

        for (index, timestamp) in hours.time.enumerated() {
            let uv = uvByTime[timestamp] ?? (0, 0)
            series.append(UVConditions(
                date: Date(timeIntervalSince1970: TimeInterval(timestamp)),
                uvIndex: uv.uv,
                uvIndexClearSky: uv.clearSky,
                cloudCover: value(hours.cloud_cover, index) / 100,
                temperature: value(hours.temperature_2m, index, fallback: .nan),
                apparentTemperature: value(hours.apparent_temperature, index, fallback: .nan),
                precipitationProbability: value(hours.precipitation_probability, index) / 100,
                windSpeed: value(hours.wind_speed_10m, index),
                weatherCode: Int(value(hours.weather_code, index))
            ))
        }

        guard !series.isEmpty else { throw WeatherServiceError.malformedPayload }

        return WeatherSnapshot(
            fetchedAt: Date(),
            latitude: weatherPayload.latitude,
            longitude: weatherPayload.longitude,
            altitude: weatherPayload.elevation ?? 0,
            timeZone: TimeZone(identifier: weatherPayload.timezone) ?? .current,
            hourly: series.sorted { $0.date < $1.date },
            isModelled: false
        )
    }

    // MARK: - Requêtes

    private func fetchWeather(latitude: Double, longitude: Double, days: Int) async throws -> WeatherPayload {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "hourly", value: "temperature_2m,apparent_temperature,cloud_cover,precipitation_probability,wind_speed_10m,weather_code"),
            .init(name: "forecast_days", value: String(days)),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "timezone", value: "auto")
        ]
        return try await get(components.url!, as: WeatherPayload.self)
    }

    private func fetchAirQuality(latitude: Double, longitude: Double, days: Int) async throws -> AirQualityPayload {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "hourly", value: "uv_index,uv_index_clear_sky"),
            .init(name: "forecast_days", value: String(days)),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "timezone", value: "auto")
        ]
        return try await get(components.url!, as: AirQualityPayload.self)
    }

    private func get<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadRevalidatingCacheData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WeatherServiceError.malformedPayload
        }
        guard (200..<300).contains(http.statusCode) else {
            throw WeatherServiceError.badResponse(http.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw WeatherServiceError.malformedPayload
        }
    }

    // MARK: - Décodage

    private struct WeatherPayload: Decodable {
        let latitude: Double
        let longitude: Double
        let elevation: Double?
        let timezone: String
        let hourly: Hourly

        struct Hourly: Decodable {
            let time: [Int]
            let temperature_2m: [Double?]
            let apparent_temperature: [Double?]
            let cloud_cover: [Double?]
            let precipitation_probability: [Double?]
            let wind_speed_10m: [Double?]
            let weather_code: [Double?]
        }
    }

    private struct AirQualityPayload: Decodable {
        let hourly: Hourly

        struct Hourly: Decodable {
            let time: [Int]
            let uv_index: [Double?]
            let uv_index_clear_sky: [Double?]
        }
    }
}

/// Repli hors ligne : série horaire reconstruite à partir de la seule géométrie
/// solaire, sans nuages. Permet à l'application de rester utilisable en montagne
/// ou hors couverture réseau, avec un avertissement explicite.
struct ModelledWeatherService: WeatherProviding {

    let environment: EnvironmentFactors

    init(environment: EnvironmentFactors = .standard) {
        self.environment = environment
    }

    func snapshot(latitude: Double, longitude: Double, days: Int = 3) async throws -> WeatherSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: Date())
        var series: [UVConditions] = []

        for hour in 0..<(days * 24) {
            let date = start.addingTimeInterval(TimeInterval(hour) * 3600)
            let position = SolarCalculator.position(
                date: date, latitude: latitude, longitude: longitude)
            let uvi = UVEngine.modelledClearSkyUVIndex(
                solarElevation: position.elevation, environment: environment)
            series.append(UVConditions(
                date: date, uvIndex: uvi, uvIndexClearSky: uvi,
                cloudCover: 0, temperature: .nan, apparentTemperature: .nan,
                precipitationProbability: 0, windSpeed: 0, weatherCode: 0))
        }

        return WeatherSnapshot(
            fetchedAt: Date(),
            latitude: latitude,
            longitude: longitude,
            altitude: environment.altitude,
            timeZone: .current,
            hourly: series,
            isModelled: true
        )
    }
}

/// Traduction des codes météo WMO utilisés par Open-Meteo.
enum WeatherCode {
    static func describe(_ code: Int) -> String {
        switch code {
        case 0:        return "Ciel dégagé"
        case 1:        return "Généralement dégagé"
        case 2:        return "Partiellement nuageux"
        case 3:        return "Couvert"
        case 45, 48:   return "Brouillard"
        case 51, 53, 55: return "Bruine"
        case 56, 57:   return "Bruine verglaçante"
        case 61, 63, 65: return "Pluie"
        case 66, 67:   return "Pluie verglaçante"
        case 71, 73, 75: return "Neige"
        case 77:       return "Grains de neige"
        case 80, 81, 82: return "Averses"
        case 85, 86:   return "Averses de neige"
        case 95:       return "Orage"
        case 96, 99:   return "Orage avec grêle"
        default:       return "Conditions variables"
        }
    }

    static func symbolName(_ code: Int, isDaytime: Bool = true) -> String {
        switch code {
        case 0:        return isDaytime ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2:     return isDaytime ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:        return "cloud.fill"
        case 45, 48:   return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default:       return "cloud.sun.fill"
        }
    }

    /// Neige au sol : l'albédo grimpe, et avec lui la dose reçue au visage.
    static func impliesSnowCover(_ code: Int) -> Bool {
        [71, 73, 75, 77, 85, 86].contains(code)
    }
}
