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

    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
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

    static func temperature(_ celsius: Double) -> String {
        celsius.isNaN ? "—" : "\(Int(celsius.rounded())) °C"
    }

    static func degrees(_ value: Double) -> String {
        String(format: "%.0f°", value)
    }
}
