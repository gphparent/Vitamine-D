import Foundation

/// Phototype de Fitzpatrick.
///
/// Deux constantes physiologiques sont attachées à chaque phototype :
///
/// - `medJoulesPerSquareMetre` : la dose érythémale minimale (DEM), soit l'énergie
///   UV pondérée par le spectre d'action de l'érythème (CIE 1987) nécessaire pour
///   produire une rougeur perceptible 24 h après l'exposition, sur une peau non
///   acclimatée. Valeurs usuelles de la littérature photobiologique
///   (1 SED = 100 J/m²).
///
/// - `vitaminDFactor` : rendement relatif de la photoconversion du
///   7-déhydrocholestérol en prévitamine D3, à dose UV égale, normalisé sur le
///   phototype III. La mélanine absorbe les UVB en compétition avec le 7-DHC :
///   une peau foncée produit nettement moins de vitamine D pour la même dose.
enum SkinType: Int, CaseIterable, Codable, Identifiable, Sendable {
    case i = 1
    case ii = 2
    case iii = 3
    case iv = 4
    case v = 5
    case vi = 6

    var id: Int { rawValue }

    /// Dose érythémale minimale, en J/m² pondérés érythème.
    var medJoulesPerSquareMetre: Double {
        switch self {
        case .i:   return 200
        case .ii:  return 250
        case .iii: return 300
        case .iv:  return 450
        case .v:   return 600
        case .vi:  return 1000
        }
    }

    /// Rendement relatif de synthèse de la vitamine D (phototype III = 1,0).
    var vitaminDFactor: Double {
        switch self {
        case .i:   return 1.40
        case .ii:  return 1.20
        case .iii: return 1.00
        case .iv:  return 0.70
        case .v:   return 0.45
        case .vi:  return 0.30
        }
    }

    var romanNumeral: String {
        ["I", "II", "III", "IV", "V", "VI"][rawValue - 1]
    }

    var title: String {
        switch self {
        case .i:   return "Type I — très claire"
        case .ii:  return "Type II — claire"
        case .iii: return "Type III — intermédiaire"
        case .iv:  return "Type IV — mate"
        case .v:   return "Type V — foncée"
        case .vi:  return "Type VI — très foncée"
        }
    }

    /// Description clinique, formulée selon la réaction au soleil plutôt que
    /// selon la couleur perçue : c'est le critère de Fitzpatrick d'origine.
    var summary: String {
        switch self {
        case .i:   return "Brûle toujours, ne bronze jamais. Souvent roux, taches de rousseur."
        case .ii:  return "Brûle facilement, bronze peu et difficilement."
        case .iii: return "Brûle modérément, bronze progressivement."
        case .iv:  return "Brûle rarement, bronze bien et rapidement."
        case .v:   return "Brûle très rarement, bronze intensément."
        case .vi:  return "Ne brûle pratiquement jamais, pigmentation foncée."
        }
    }

    /// Teinte indicative pour la pastille de sélection (approximation Von Luschan).
    var swatch: (red: Double, green: Double, blue: Double) {
        switch self {
        case .i:   return (0.98, 0.87, 0.79)
        case .ii:  return (0.95, 0.80, 0.68)
        case .iii: return (0.87, 0.69, 0.54)
        case .iv:  return (0.72, 0.53, 0.37)
        case .v:   return (0.49, 0.34, 0.22)
        case .vi:  return (0.29, 0.20, 0.14)
        }
    }
}

/// Niveau d'acclimatation (« capital bronzage ») accumulé par les expositions
/// récentes. L'épaississement de la couche cornée et la mélanogenèse relèvent la
/// DEM d'un facteur qui plafonne autour de 1,6 pour les phototypes clairs.
enum TanLevel: Int, CaseIterable, Codable, Identifiable, Sendable {
    case none = 0
    case light = 1
    case moderate = 2
    case wellTanned = 3

    var id: Int { rawValue }

    /// Multiplicateur appliqué à la DEM.
    var medMultiplier: Double {
        switch self {
        case .none:       return 1.00
        case .light:      return 1.15
        case .moderate:   return 1.35
        case .wellTanned: return 1.60
        }
    }

    var title: String {
        switch self {
        case .none:       return "Aucune"
        case .light:      return "Légère"
        case .moderate:   return "Modérée"
        case .wellTanned: return "Bien bronzée"
        }
    }

    var detail: String {
        switch self {
        case .none:       return "Première exposition de la saison, peau « d'hiver »."
        case .light:      return "Quelques expositions dans les deux dernières semaines."
        case .moderate:   return "Exposition régulière depuis plusieurs semaines."
        case .wellTanned: return "Exposition quotidienne, bronzage installé."
        }
    }
}
