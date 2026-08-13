import Foundation

/// Ce que devient la vitamine D synthétisée, une fois l'été fini.
///
/// L'idée d'« emmagasiner » du soleil avant l'hiver est juste dans son
/// principe et trompeuse dans son ampleur. Le 25-hydroxyvitamine D circulant
/// a une demi-vie de deux à trois semaines : une réserve constituée en
/// septembre est réduite de moitié à la mi-octobre, du trois quarts au début
/// de novembre, et ne pèse plus grand-chose en janvier.
///
/// Le calcul ci-dessous sert donc autant à encourager les sorties de fin d'été
/// qu'à dire honnêtement ce qu'elles ne peuvent pas faire. Au-dessus du 45e
/// parallèle, aucune stratégie d'exposition ne couvre un hiver entier.
enum WinterPlanner {

    /// Demi-vie du 25(OH)D circulant, en jours.
    ///
    /// Les études donnent de 15 à 25 jours selon la population et le statut de
    /// départ. Vingt est une valeur centrale défendable ; les conclusions
    /// qualitatives ne changent pas aux bornes de cette fourchette.
    static let halfLifeDays = 20.0

    /// Constante de temps de la décroissance exponentielle.
    static var timeConstantDays: Double { halfLifeDays / log(2) }

    /// Part d'une dose encore présente après un certain nombre de jours.
    static func remainingFraction(afterDays days: Double) -> Double {
        guard days > 0 else { return 1 }
        return pow(0.5, days / halfLifeDays)
    }

    /// Réserve relative à une date donnée : chaque synthèse passée, amortie par
    /// sa propre décroissance.
    ///
    /// L'unité est une UI-équivalent en circulation, non une concentration
    /// sanguine. Seule une prise de sang mesure la seconde ; ce chiffre-ci ne
    /// vaut que pour se comparer à soi-même d'une semaine à l'autre.
    static func reserve(on date: Date, history: [SessionRecord]) -> Double {
        history.reduce(0.0) { total, record in
            let elapsed = date.timeIntervalSince(record.start) / 86_400
            guard elapsed >= 0 else { return total }
            return total + record.vitaminDIU * remainingFraction(afterDays: elapsed)
        }
    }

    /// Apport quotidien constant qui, à l'équilibre, soutiendrait cette réserve.
    ///
    /// Traduction du réservoir en un chiffre comparable aux apports de
    /// référence : à l'équilibre, réserve = apport × constante de temps.
    static func equivalentDailyIU(reserve: Double) -> Double {
        reserve / timeConstantDays
    }

    /// Décroissance de la réserve actuelle si plus aucune exposition n'avait
    /// lieu, échantillonnée jusqu'à une date donnée.
    static func projection(from date: Date,
                           reserve: Double,
                           through end: Date,
                           step: TimeInterval = 7 * 86_400) -> [(date: Date, reserve: Double)] {
        guard end > date, step > 0 else { return [(date, reserve)] }

        var result: [(date: Date, reserve: Double)] = []
        var cursor = date
        while cursor <= end {
            let elapsed = cursor.timeIntervalSince(date) / 86_400
            result.append((cursor, reserve * remainingFraction(afterDays: elapsed)))
            cursor = cursor.addingTimeInterval(step)
        }
        if let last = result.last, last.date < end {
            let elapsed = end.timeIntervalSince(date) / 86_400
            result.append((end, reserve * remainingFraction(afterDays: elapsed)))
        }
        return result
    }

    /// Bilan d'avant-hiver.
    struct Plan: Equatable, Sendable {
        /// Hiver vitaminique visé.
        let winter: DateInterval
        /// Y sommes-nous déjà ?
        let hasStarted: Bool
        let daysUntilStart: Int
        let usefulDaysLeft: Int
        let optimalDaysLeft: Int
        /// Réserve relative actuelle, en UI-équivalent.
        let reserve: Double
        /// Ce qu'il en restera au cœur de l'hiver, sans nouvelle exposition.
        let reserveAtMidwinter: Double
        let midwinter: Date

        var midwinterFraction: Double {
            reserve > 0 ? reserveAtMidwinter / reserve : 0
        }
    }

    static func plan(on date: Date, outlook: YearOutlook, history: [SessionRecord]) -> Plan? {
        guard let winter = outlook.winter else { return nil }

        let midwinter = Date(timeIntervalSince1970:
            (winter.start.timeIntervalSince1970 + winter.end.timeIntervalSince1970) / 2)
        let current = reserve(on: date, history: history)
        let elapsedToMidwinter = max(0, midwinter.timeIntervalSince(date) / 86_400)

        return Plan(
            winter: winter,
            hasStarted: winter.contains(date),
            daysUntilStart: outlook.daysUntilWinter(from: date) ?? 0,
            usefulDaysLeft: outlook.remainingUsefulDays(from: date),
            optimalDaysLeft: outlook.remainingOptimalDays(from: date),
            reserve: current,
            reserveAtMidwinter: current * remainingFraction(afterDays: elapsedToMidwinter),
            midwinter: midwinter
        )
    }
}
