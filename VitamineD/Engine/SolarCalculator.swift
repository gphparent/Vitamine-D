import Foundation

/// Position du Soleil dans le repère de l'observateur.
struct SolarPosition: Equatable, Sendable {
    /// Hauteur apparente au-dessus de l'horizon, en degrés, réfraction comprise.
    /// C'est la hauteur à afficher et celle qu'attendent les formules de masse
    /// d'air.
    let elevation: Double
    /// Hauteur géométrique, sans réfraction.
    ///
    /// Le seuil conventionnel de lever et coucher (-0,833°) intègre déjà les 34'
    /// de réfraction à l'horizon et les 16' de demi-diamètre du disque : il doit
    /// donc être comparé à cette valeur-ci, sans quoi la réfraction est comptée
    /// deux fois et la journée s'allonge de quelques minutes.
    let trueElevation: Double
    /// Azimut en degrés, mesuré depuis le nord vers l'est.
    let azimuth: Double
    /// Déclinaison solaire, en degrés.
    let declination: Double
    /// Équation du temps, en minutes.
    let equationOfTime: Double

    /// Angle zénithal, complément de la hauteur.
    var zenithAngle: Double { 90 - elevation }

    /// Masse d'air relative traversée par le rayonnement direct.
    ///
    /// Formule de Kasten & Young (1989), valable jusqu'à l'horizon, là où le
    /// simple 1/cos(θ) diverge.
    var airMass: Double {
        guard elevation > -0.5 else { return .infinity }
        let h = max(elevation, 0.0)
        return 1.0 / (sin(h * .pi / 180) + 0.50572 * pow(h + 6.07995, -1.6364))
    }

    /// Longueur de l'ombre d'un objet vertical, en multiples de sa hauteur.
    ///
    /// La « règle de l'ombre » vient de là : quand l'ombre est plus courte que
    /// la personne (rapport < 1, soit une hauteur solaire > 45°), les UVB
    /// atteignent le sol en quantité utile.
    var shadowRatio: Double? {
        guard elevation > 0.5 else { return nil }
        return 1.0 / tan(elevation * .pi / 180)
    }
}

/// Position solaire d'après l'algorithme du NOAA Solar Calculator (dérivé de
/// Meeus, *Astronomical Algorithms*). Précision de l'ordre de la minute d'arc
/// pour les dates comprises entre 1900 et 2100, ce qui dépasse largement les
/// besoins d'un calcul de dose UV.
///
/// Tous les calculs se font en temps universel : aucun fuseau horaire n'entre
/// dans les formules, ce qui élimine une source classique d'erreurs.
enum SolarCalculator {

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    /// Jour julien pour une date donnée.
    static func julianDay(for date: Date) -> Double {
        // 2440587.5 est le jour julien de l'époque Unix (1970-01-01T00:00:00Z).
        date.timeIntervalSince1970 / 86400.0 + 2440587.5
    }

    /// Position du Soleil vue depuis un point de la surface terrestre.
    static func position(date: Date, latitude: Double, longitude: Double) -> SolarPosition {
        let jd = julianDay(for: date)
        let t = (jd - 2451545.0) / 36525.0  // siècles juliens depuis J2000.0

        // Longitude moyenne et anomalie moyenne du Soleil.
        var meanLongitude = 280.46646 + t * (36000.76983 + t * 0.0003032)
        meanLongitude = meanLongitude.truncatingRemainder(dividingBy: 360)
        if meanLongitude < 0 { meanLongitude += 360 }

        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)

        // Équation du centre : écart entre orbite circulaire et orbite réelle.
        let centre = sin(radians(meanAnomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * t)
            + sin(radians(3 * meanAnomaly)) * 0.000289

        let trueLongitude = meanLongitude + centre

        // Longitude apparente : correction de nutation et d'aberration.
        let apparentLongitude = trueLongitude - 0.00569
            - 0.00478 * sin(radians(125.04 - 1934.136 * t))

        // Obliquité de l'écliptique, corrigée de la nutation.
        let meanObliquity = 23.0 + (26.0 + ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813)))) / 60.0) / 60.0
        let obliquity = meanObliquity + 0.00256 * cos(radians(125.04 - 1934.136 * t))

        let declination = degrees(asin(sin(radians(obliquity)) * sin(radians(apparentLongitude))))

        // Équation du temps, en minutes.
        let y = pow(tan(radians(obliquity / 2)), 2)
        let eqTimeRadians = y * sin(2 * radians(meanLongitude))
            - 2 * eccentricity * sin(radians(meanAnomaly))
            + 4 * eccentricity * y * sin(radians(meanAnomaly)) * cos(2 * radians(meanLongitude))
            - 0.5 * y * y * sin(4 * radians(meanLongitude))
            - 1.25 * eccentricity * eccentricity * sin(2 * radians(meanAnomaly))
        let equationOfTime = 4 * degrees(eqTimeRadians)

        // Temps solaire vrai, en minutes, à partir du temps universel.
        let utcMinutes = utcMinutesOfDay(for: date)
        var trueSolarTime = utcMinutes + equationOfTime + 4 * longitude
        trueSolarTime = trueSolarTime.truncatingRemainder(dividingBy: 1440)
        if trueSolarTime < 0 { trueSolarTime += 1440 }

        var hourAngle = trueSolarTime / 4 - 180
        if hourAngle < -180 { hourAngle += 360 }

        let latRad = radians(latitude)
        let decRad = radians(declination)
        let haRad = radians(hourAngle)

        let cosZenith = min(1, max(-1,
            sin(latRad) * sin(decRad) + cos(latRad) * cos(decRad) * cos(haRad)))
        let zenith = degrees(acos(cosZenith))
        let trueElevation = 90 - zenith

        let elevation = trueElevation + atmosphericRefraction(trueElevation: trueElevation)

        // Azimut mesuré depuis le nord, sens horaire. Le dénominateur s'annule
        // aux pôles et au zénith exact, où l'azimut n'est pas défini.
        var azimuth: Double
        let divisor = cos(latRad) * sin(radians(zenith))
        if abs(divisor) > 1e-12 {
            let numerator = sin(latRad) * cos(radians(zenith)) - sin(decRad)
            let cosAz = min(1, max(-1, numerator / divisor))
            azimuth = degrees(acos(cosAz))
            azimuth = hourAngle > 0 ? (azimuth + 180).truncatingRemainder(dividingBy: 360)
                                    : (540 - azimuth).truncatingRemainder(dividingBy: 360)
        } else {
            azimuth = latitude > 0 ? 180 : 0
        }

        return SolarPosition(
            elevation: elevation,
            trueElevation: trueElevation,
            azimuth: azimuth,
            declination: declination,
            equationOfTime: equationOfTime
        )
    }

    /// Correction de réfraction atmosphérique, en degrés (Meeus, ch. 16).
    ///
    /// Près de l'horizon, l'atmosphère relève l'image du Soleil d'environ un
    /// demi-degré : c'est la raison pour laquelle il est visible alors qu'il est
    /// géométriquement déjà couché.
    private static func atmosphericRefraction(trueElevation e: Double) -> Double {
        if e > 85 { return 0 }
        let te = tan(radians(e))
        let arcSeconds: Double
        if e > 5 {
            arcSeconds = 58.1 / te - 0.07 / pow(te, 3) + 0.000086 / pow(te, 5)
        } else if e > -0.575 {
            arcSeconds = 1735 + e * (-518.2 + e * (103.4 + e * (-12.79 + e * 0.711)))
        } else {
            arcSeconds = -20.772 / te
        }
        return arcSeconds / 3600
    }

    private static func utcMinutesOfDay(for date: Date) -> Double {
        let seconds = date.timeIntervalSince1970
        let dayFraction = seconds / 86400.0
        let withinDay = dayFraction - floor(dayFraction)
        return withinDay * 1440.0
    }

    // MARK: - Événements du jour

    /// Instant du midi solaire local pour un jour donné.
    ///
    /// Le midi solaire n'est pas midi à la montre : l'équation du temps le
    /// décale de ±16 minutes selon la saison, et la position dans le fuseau
    /// horaire peut ajouter jusqu'à une heure de plus.
    static func solarNoon(on day: Date, latitude: Double, longitude: Double,
                          calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        // Deux itérations suffisent : l'équation du temps varie très lentement.
        var estimate = start.addingTimeInterval(43200)
        for _ in 0..<2 {
            let position = position(date: estimate, latitude: latitude, longitude: longitude)
            let offsetMinutes = 720 - 4 * longitude - position.equationOfTime
            let utcStart = floor(start.timeIntervalSince1970 / 86400) * 86400
            estimate = Date(timeIntervalSince1970: utcStart + offsetMinutes * 60)
        }
        return estimate
    }

    /// Instants de la journée où la hauteur du Soleil franchit un seuil.
    ///
    /// Balayage à la minute puis raffinement par dichotomie : robuste aux nuits
    /// et jours polaires, où la fonction ne croise jamais le seuil, ou le croise
    /// hors de la fenêtre attendue.
    /// - Parameter geometric: comparer la hauteur géométrique plutôt que la
    ///   hauteur apparente. À n'utiliser que pour le seuil conventionnel de
    ///   lever et coucher (-0,833°), qui inclut déjà la réfraction.
    static func crossings(of thresholdElevation: Double,
                          on day: Date,
                          latitude: Double,
                          longitude: Double,
                          calendar: Calendar,
                          geometric: Bool = false) -> [DateInterval] {
        let start = calendar.startOfDay(for: day)
        let step: TimeInterval = 60
        let count = Int(24 * 60)

        func elevation(at date: Date) -> Double {
            let p = position(date: date, latitude: latitude, longitude: longitude)
            return geometric ? p.trueElevation : p.elevation
        }

        var intervals: [DateInterval] = []
        var openedAt: Date?
        var previousDate = start
        var previousAbove = elevation(at: start) >= thresholdElevation
        if previousAbove { openedAt = start }

        for index in 1...count {
            let date = start.addingTimeInterval(Double(index) * step)
            let above = elevation(at: date) >= thresholdElevation
            if above != previousAbove {
                let crossing = refine(from: previousDate, to: date,
                                      threshold: thresholdElevation,
                                      risingIntoZone: above,
                                      elevation: elevation)
                if above {
                    openedAt = crossing
                } else if let opened = openedAt, crossing > opened {
                    intervals.append(DateInterval(start: opened, end: crossing))
                    openedAt = nil
                }
            }
            previousAbove = above
            previousDate = date
        }

        if let opened = openedAt {
            let end = start.addingTimeInterval(Double(count) * step)
            if end > opened { intervals.append(DateInterval(start: opened, end: end)) }
        }
        return intervals
    }

    private static func refine(from lower: Date, to upper: Date,
                               threshold: Double,
                               risingIntoZone: Bool,
                               elevation: (Date) -> Double) -> Date {
        var low = lower
        var high = upper
        for _ in 0..<12 {  // 60 s / 2^12 ≈ 15 ms, très au-delà du nécessaire
            let mid = Date(timeIntervalSince1970: (low.timeIntervalSince1970 + high.timeIntervalSince1970) / 2)
            let above = elevation(mid) >= threshold
            if above == risingIntoZone { high = mid } else { low = mid }
        }
        return high
    }

    /// Lever et coucher du Soleil, définis par la hauteur du centre du disque à
    /// -0,833° (rayon apparent du disque plus réfraction à l'horizon).
    static func sunriseSunset(on day: Date, latitude: Double, longitude: Double,
                              calendar: Calendar) -> (sunrise: Date?, sunset: Date?) {
        let daylight = crossings(of: -0.833, on: day, latitude: latitude,
                                 longitude: longitude, calendar: calendar,
                                 geometric: true)
        guard let widest = daylight.max(by: { $0.duration < $1.duration }) else {
            return (nil, nil)  // nuit polaire
        }
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = dayStart.addingTimeInterval(86400)
        let sunrise = widest.start <= dayStart.addingTimeInterval(1) ? nil : widest.start
        let sunset = widest.end >= dayEnd.addingTimeInterval(-1) ? nil : widest.end
        return (sunrise, sunset)
    }
}
