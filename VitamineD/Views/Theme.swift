import SwiftUI

/// Palette et formatage partagés.
enum Theme {

    /// Couleur conventionnelle de l'indice UV, telle que définie par l'OMS.
    static func uvColour(_ index: Double) -> Color {
        switch index {
        case ..<3:   return Color(red: 0.22, green: 0.66, blue: 0.36)   // vert, faible
        case ..<6:   return Color(red: 0.95, green: 0.77, blue: 0.06)   // jaune, modéré
        case ..<8:   return Color(red: 0.93, green: 0.49, blue: 0.13)   // orange, élevé
        case ..<11:  return Color(red: 0.85, green: 0.22, blue: 0.20)   // rouge, très élevé
        default:     return Color(red: 0.60, green: 0.31, blue: 0.71)   // violet, extrême
        }
    }

    static func uvLabel(_ index: Double) -> String {
        switch index {
        case ..<3:  return "Faible"
        case ..<6:  return "Modéré"
        case ..<8:  return "Élevé"
        case ..<11: return "Très élevé"
        default:    return "Extrême"
        }
    }

    static func burnColour(_ level: SessionProgress.BurnLevel) -> Color {
        switch level {
        case .safe:    return Color(red: 0.22, green: 0.66, blue: 0.36)
        case .caution: return Color(red: 0.95, green: 0.77, blue: 0.06)
        case .warning: return Color(red: 0.93, green: 0.49, blue: 0.13)
        case .danger:  return Color(red: 0.85, green: 0.16, blue: 0.16)
        }
    }

    static func windowColour(_ quality: ExposureWindow.Quality) -> Color {
        switch quality {
        case .marginal: return .secondary
        case .good:     return Color(red: 0.95, green: 0.72, blue: 0.20)
        case .optimal:  return Color(red: 0.94, green: 0.53, blue: 0.10)
        }
    }

    /// Couleur d'une bande de rendement. Le vert n'est pas décoratif : il dit
    /// que la règle de l'ombre est satisfaite, donc que chaque minute passée
    /// dehors rapporte le maximum pour ce qu'elle coûte à la peau.
    static func yieldColour(_ band: DayPlanner.YieldBand) -> Color {
        switch band {
        case .negligible: return Color(red: 0.55, green: 0.57, blue: 0.60)
        case .partial:    return Color(red: 0.95, green: 0.72, blue: 0.20)
        case .optimal:    return Color(red: 0.30, green: 0.66, blue: 0.42)
        }
    }

    static let vitaminD = Color(red: 0.98, green: 0.68, blue: 0.13)

    /// Les deux bandes ultraviolettes, pour le schéma des rayons.
    ///
    /// Le choix n'est pas arbitraire : les UVA, plus proches du visible,
    /// prennent le bleu ; les UVB, plus courts, le violet vers lequel l'œil
    /// s'arrête. Personne ne voit ces longueurs d'onde, mais l'ordre du spectre
    /// se lit d'instinct et vaut mieux qu'une paire de couleurs quelconques.
    static let uvaColour = Color(red: 0.36, green: 0.62, blue: 0.96)
    static let uvbColour = Color(red: 0.64, green: 0.36, blue: 0.92)

    // MARK: - Registre héraldique

    /// Pigments de l'icône, repris tels quels de `Tools/fabriquer-icone.py`.
    ///
    /// Ils ne servent qu'au décor — titres, filets, contours de carte. Les
    /// échelles de données gardent leurs couleurs conventionnelles : un indice
    /// UV rouge doit rester rouge, quelle que soit la charte.
    static let gold = Color(red: 226/255, green: 178/255, blue: 74/255)
    static let goldLight = Color(red: 244/255, green: 214/255, blue: 136/255)
    static let goldDark = Color(red: 135/255, green: 96/255, blue: 30/255)

    /// Or des inscriptions, qui suit l'apparence du système.
    ///
    /// L'or foncé ne tient pas sur une carte sombre — 2,7:1, sous le seuil
    /// lisible. En apparence sombre c'est donc l'or clair qui porte les
    /// capitales et les filets. Une couleur figée aurait rendu les têtes de
    /// carte pratiquement invisibles la nuit.
    static let capsGold = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark ? UIColor(gold) : UIColor(goldDark)
    })

    /// Contour de carte : filet d'or à 28 %, 30 % de l'or clair la nuit.
    static let cardEdge = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(gold).withAlphaComponent(0.30)
            : UIColor(goldDark).withAlphaComponent(0.28)
    })

    /// Filet d'or, en remplacement du séparateur gris à l'intérieur des cartes.
    static var goldRule: LinearGradient {
        LinearGradient(colors: [capsGold.opacity(0.45), .clear],
                       startPoint: .leading, endPoint: .trailing)
    }

    /// Encre posée à nu sur le ciel.
    ///
    /// Jamais la couleur de texte ordinaire : le noir tombe à 3,2:1 sur l'azur
    /// de plein jour, sous le seuil de lisibilité.
    static let onSky = Color.white
    static let onSkyDim = Color(red: 241/255, green: 244/255, blue: 252/255).opacity(0.78)

    /// Cartes posées sur le ciel : translucides, jamais opaques.
    ///
    /// `systemBackground` plutôt qu'un blanc fixe, pour que le texte ordinaire
    /// garde son contraste dans les deux apparences du système.
    ///
    /// À 86 % — la valeur du système de design, pensée pour le web — le ciel
    /// remonte assez pour éteindre l'encre tertiaire, qui n'a déjà que 30 %
    /// d'alpha. La carte se compose alors à moins de 4,5:1 sur ses mentions
    /// secondaires. 96 % garde la transparence perceptible sans manger le
    /// texte : c'est la lisibilité qui tranche, pas la maquette.
    static let cardBackground = Color(uiColor: .systemBackground).opacity(0.96)

    // MARK: - Ciel

    /// Les trois arrêts du fond d'écran, choisis par la hauteur du Soleil.
    ///
    /// La phase ne dépend jamais de l'heure, toujours de la hauteur : c'est la
    /// même grandeur qui décide du rendement UVB, et les deux dernières bornes
    /// — celles de l'hiver vitaminique et de la règle de l'ombre — sont
    /// exactement celles des bandes de rendement. Le fond dit donc quelque
    /// chose de vrai, et non une ambiance.
    static func skyStops(solarElevation: Double) -> [Color] {
        switch solarElevation {
        case ..<(-12):
            return [hex(0x060C22), hex(0x0C183C), hex(0x152551)]
        case ..<0:
            return [hex(0x101C46), hex(0x2A3E78), hex(0x7A5F7E)]
        case ..<8:
            return [hex(0x1E3F80), hex(0x7D6A9A), hex(0xE2B24A)]
        case ..<UVEngine.vitaminDWinterElevation:
            return [hex(0x20488F), hex(0x4A76B6), hex(0xC9B48C)]
        case ..<UVEngine.optimalSynthesisElevation:
            return [hex(0x1D4795), hex(0x3F74BD), hex(0x9FC0E2)]
        default:
            return [hex(0x173F92), hex(0x2E5CA8), hex(0x8FB6DE)]
        }
    }

    /// Voile nuageux superposé au ciel, sans en changer la phase.
    static func skyVeil(cloudCover: Double) -> Color {
        switch cloudCover {
        case ..<0.20: return .clear
        case ..<0.45: return Color(red: 241/255, green: 244/255, blue: 252/255).opacity(0.14)
        case ..<0.75: return Color(red: 241/255, green: 244/255, blue: 252/255).opacity(0.30)
        default:      return Color(red: 160/255, green: 170/255, blue: 190/255).opacity(0.62)
        }
    }

    private static func hex(_ value: Int) -> Color {
        Color(red: Double((value >> 16) & 0xFF) / 255,
              green: Double((value >> 8) & 0xFF) / 255,
              blue: Double(value & 0xFF) / 255)
    }
}

/// Formatage cohérent des heures et durées dans toute l'application.
enum Format {

    static func time(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func interval(_ interval: DateInterval, in timeZone: TimeZone? = nil) -> String {
        "\(time(interval.start, in: timeZone)) – \(time(interval.end, in: timeZone))"
    }

    /// « 12 août ».
    static func shortDate(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "d MMMM"
        return formatter.string(from: date)
    }

    /// « jeudi 12 août ».
    static func longDate(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "EEEE d MMMM"
        return formatter.string(from: date)
    }

    /// « août », pour un axe de graphique.
    static func monthAbbreviation(_ date: Date, in timeZone: TimeZone? = nil) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_CA")
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "MMM"
        return formatter.string(from: date)
    }

    /// « 6 novembre – 5 février ». La borne de fin d'un intervalle de jours
    /// pleins tombe à minuit le lendemain : on affiche la veille.
    static func dateRange(_ interval: DateInterval, in timeZone: TimeZone? = nil) -> String {
        let last = interval.end.addingTimeInterval(-1)
        return "\(shortDate(interval.start, in: timeZone)) – \(shortDate(last, in: timeZone))"
    }

    /// Heure exprimée en minutes depuis minuit : « 6 h 45 ».
    static func minuteOfDay(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%d h %02d", wrapped / 60, wrapped % 60)
    }

    /// Durée en écriture courte : « 8 min », « 1 h 25 ».
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours) h \(String(format: "%02d", minutes))" }
        return "\(minutes) min"
    }

    /// Chronomètre d'une séance en cours.
    static func stopwatch(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func iu(_ value: Double) -> String {
        "\(Int(value.rounded())) UI"
    }

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded())) %"
    }

    /// Rapport d'une grandeur à une autre : « 1,4 fois », « 0,7 fois ».
    ///
    /// La locale est passée explicitement : sans elle, `String(format:)` s'en
    /// tient à POSIX et écrirait « 1.4 fois » au milieu d'une phrase française.
    /// C'est la même locale que les dates de ce fichier, et pour la même raison.
    static func multiplier(_ value: Double) -> String {
        String(format: "%.1f fois", locale: Locale(identifier: "fr_CA"), value)
    }

    static func temperature(_ celsius: Double) -> String {
        celsius.isNaN ? "—" : "\(Int(celsius.rounded())) °C"
    }

    static func degrees(_ value: Double) -> String {
        String(format: "%.0f°", value)
    }
}
