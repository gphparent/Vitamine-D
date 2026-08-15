import Foundation

/// Un jour de l'année, réduit à son midi solaire.
///
/// Toute la question de l'hiver vitaminique se joue sur un seul chiffre par
/// jour : la hauteur du Soleil à son point le plus haut. Si ce maximum reste
/// sous le seuil d'hiver vitaminique, aucune heure de cette journée-là ne produira de vitamine D, et il
/// est inutile d'en échantillonner davantage.
struct YearDay: Identifiable, Equatable, Sendable {
    /// Midi solaire de ce jour.
    let date: Date
    let peakElevation: Double
    /// Indice UV au midi solaire, ciel parfaitement clair.
    let peakUVIndex: Double

    var id: Date { date }

    var band: DayPlanner.YieldBand { DayPlanner.YieldBand(solarElevation: peakElevation) }

    /// La journée permet-elle la moindre synthèse ?
    var producesVitaminD: Bool { peakElevation >= UVEngine.vitaminDWinterElevation }

    /// La règle de l'ombre est-elle satisfaite au moins un instant ?
    var reachesOptimal: Bool { peakElevation >= UVEngine.optimalSynthesisElevation }
}

/// Ce que le Soleil fera dans l'année, à une latitude donnée.
///
/// C'est la vue qui manque le plus au Québec. Un habitant de Montréal peut
/// suivre scrupuleusement les créneaux quotidiens de mai à septembre et
/// découvrir en janvier que son taux sanguin est au plancher : à cette
/// latitude, le Soleil passe quatre mois sous le seuil, et aucune durée
/// d'exposition n'y change quoi que ce soit.
struct YearOutlook: Equatable, Sendable {

    let latitude: Double
    let longitude: Double
    let timeZone: TimeZone
    /// Année civile représentée par `days`, du 1er janvier au 31 décembre.
    let year: Int
    /// Un point par jour de l'année civile — la courbe à afficher.
    let days: [YearDay]
    /// Hiver vitaminique en cours ou à venir, éventuellement à cheval sur deux
    /// années civiles.
    let winter: DateInterval?
    /// Les creux d'hiver tels qu'ils tombent dans l'année civile — deux
    /// morceaux sous nos latitudes, un de chaque côté du calendrier. Ne sert
    /// qu'à ombrer la courbe.
    let winterPeriods: [DateInterval]
    /// Période où la règle de l'ombre est satisfaite au midi solaire.
    let optimalSeason: DateInterval?
    /// Période où la synthèse est possible, ne serait-ce qu'un peu.
    let usefulSeason: DateInterval?
    let highestElevation: Double
    let lowestElevation: Double

    /// Sous cette latitude, le Soleil ne descend jamais sous le seuil : il n'y a
    /// pas d'hiver vitaminique, et rien à planifier.
    var hasWinter: Bool { winter != nil }

    func isInWinter(_ date: Date) -> Bool {
        guard let winter else { return false }
        return winter.contains(date)
    }

    /// Jours restants avant l'entrée dans l'hiver vitaminique. `nil` si l'on y
    /// est déjà, ou s'il n'y en a pas à cette latitude.
    func daysUntilWinter(from date: Date) -> Int? {
        guard let winter, date < winter.start else { return nil }
        return Int((winter.start.timeIntervalSince(date) / 86_400).rounded(.up))
    }

    /// Jours restants avant l'hiver où la synthèse est possible.
    func remainingUsefulDays(from date: Date) -> Int {
        countDays(from: date) { $0.producesVitaminD }
    }

    /// Jours restants avant l'hiver où le Soleil dépasse 45° — les seuls où le
    /// rendement est à son meilleur.
    func remainingOptimalDays(from date: Date) -> Int {
        countDays(from: date) { $0.reachesOptimal }
    }

    private func countDays(from date: Date, where predicate: (YearDay) -> Bool) -> Int {
        guard let winter, date < winter.start else { return 0 }
        return days.filter { $0.date >= date && $0.date < winter.start && predicate($0) }.count
    }

    func day(nearest date: Date) -> YearDay? {
        days.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

enum YearPlanner {

    /// Trois années pleines, à cheval de part et d'autre de celle qu'on affiche.
    ///
    /// L'hiver vitaminique traverse le 1er janvier sous nos latitudes. Balayer
    /// la seule année civile le couperait en deux morceaux : en janvier,
    /// l'application annoncerait un hiver commençant le 1er du mois, et en
    /// novembre un hiver s'achevant le 31 décembre. Déborder d'un an de chaque
    /// côté rend chaque hiver d'un seul tenant, quel que soit le jour où l'on
    /// regarde.
    private static let scanDays = 1_100

    static func outlook(containing date: Date,
                        latitude: Double,
                        longitude: Double,
                        timeZone: TimeZone) -> YearOutlook {

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let year = calendar.component(.year, from: date)
        var components = DateComponents()
        components.year = year - 1
        components.month = 1
        components.day = 1
        components.hour = 12
        let january = calendar.date(from: components) ?? calendar.startOfDay(for: date)

        let scanned = days(from: january, count: scanDays,
                           latitude: latitude, longitude: longitude, calendar: calendar)

        // La courbe affichée reste l'année civile ; le balayage plus long ne
        // sert qu'à recoller l'hiver qui la traverse.
        let calendarYear = scanned.filter { calendar.component(.year, from: $0.date) == year }

        let winters = runs(in: scanned, calendar: calendar) { !$0.producesVitaminD }
        let winter = winters.first { $0.end > date } ?? winters.first

        let optimalRuns = runs(in: calendarYear, calendar: calendar) { $0.reachesOptimal }
        let usefulRuns = runs(in: calendarYear, calendar: calendar) { $0.producesVitaminD }

        return YearOutlook(
            latitude: latitude,
            longitude: longitude,
            timeZone: timeZone,
            year: year,
            days: calendarYear,
            winter: winter,
            winterPeriods: runs(in: calendarYear, calendar: calendar) { !$0.producesVitaminD },
            optimalSeason: optimalRuns.max { $0.duration < $1.duration },
            usefulSeason: usefulRuns.max { $0.duration < $1.duration },
            highestElevation: calendarYear.map(\.peakElevation).max() ?? 0,
            lowestElevation: calendarYear.map(\.peakElevation).min() ?? 0
        )
    }

    static func days(from start: Date,
                     count: Int,
                     latitude: Double,
                     longitude: Double,
                     calendar: Calendar) -> [YearDay] {

        var result: [YearDay] = []
        result.reserveCapacity(count)

        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            let noon = SolarCalculator.solarNoon(
                on: day, latitude: latitude, longitude: longitude, calendar: calendar)
            let position = SolarCalculator.position(
                date: noon, latitude: latitude, longitude: longitude)
            let uv = UVEngine.modelledClearSkyUVIndex(
                solarElevation: position.elevation, environment: .standard)

            result.append(YearDay(date: noon,
                                  peakElevation: position.elevation,
                                  peakUVIndex: uv))
        }
        return result
    }

    /// Plages contiguës de jours satisfaisant un critère.
    ///
    /// Les bornes couvrent les journées entières, et non les seuls midis
    /// solaires : un hiver vitaminique qui commence le 6 novembre commence à
    /// l'aube de ce jour-là, pas à midi.
    private static func runs(in days: [YearDay],
                             calendar: Calendar,
                             where predicate: (YearDay) -> Bool) -> [DateInterval] {

        var result: [DateInterval] = []
        var runStart: Date?
        var runEnd: Date?

        func close() {
            if let start = runStart, let end = runEnd, end > start {
                result.append(DateInterval(start: start, end: end))
            }
            runStart = nil
            runEnd = nil
        }

        for day in days {
            let dayStart = calendar.startOfDay(for: day.date)
            if predicate(day) {
                if runStart == nil { runStart = dayStart }
                runEnd = dayStart.addingTimeInterval(86_400)
            } else {
                close()
            }
        }
        close()
        return result
    }
}
