import Foundation

/// Ascendance déclarée, utilisée comme indice de départ pour estimer le
/// phototype.
///
/// ## Ce que cette donnée vaut, et ce qu'elle ne vaut pas
///
/// La corrélation entre ascendance géographique et pigmentation est réelle et
/// bien documentée : elle reflète l'adaptation à des latitudes différentes, et
/// c'est cette même adaptation qui rend le sujet de cette application
/// intéressant. Elle est donc légitime comme point de départ.
///
/// Mais la dispersion à l'intérieur d'un groupe dépasse largement l'écart entre
/// groupes. Deux personnes d'une même région d'origine peuvent être séparées de
/// deux phototypes entiers. C'est précisément pourquoi Fitzpatrick a construit
/// son échelle sur la *réaction au soleil* plutôt que sur l'apparence ou
/// l'origine : la réaction mesure ce qui compte, la dose au-delà de laquelle la
/// peau rougit.
///
/// L'ascendance pèse donc un quart dans l'estimation, contre trois quarts pour
/// les réponses sur la réaction et les caractères constitutionnels. Et
/// l'utilisateur garde toujours le dernier mot.
enum Ancestry: String, CaseIterable, Codable, Identifiable, Sendable {
    case northernEurope
    case easternEurope
    case southernEurope
    case middleEastNorthAfrica
    case subSaharanAfrica
    case southAsia
    case eastAsia
    case southeastAsia
    case indigenousAmericas
    case latinAmericaCaribbean
    case oceania
    case mixed
    case undisclosed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .northernEurope:        return "Europe du Nord, îles Britanniques"
        case .easternEurope:         return "Europe centrale et de l'Est"
        case .southernEurope:        return "Europe du Sud, Méditerranée"
        case .middleEastNorthAfrica: return "Moyen-Orient, Afrique du Nord"
        case .subSaharanAfrica:      return "Afrique subsaharienne"
        case .southAsia:             return "Asie du Sud"
        case .eastAsia:              return "Asie de l'Est"
        case .southeastAsia:         return "Asie du Sud-Est"
        case .indigenousAmericas:    return "Peuples autochtones des Amériques"
        case .latinAmericaCaribbean: return "Amérique latine, Caraïbes"
        case .oceania:               return "Océanie, Pacifique"
        case .mixed:                 return "Ascendance mixte"
        case .undisclosed:           return "Je préfère ne pas répondre"
        }
    }

    /// Phototype moyen observé dans la population correspondante, sur l'échelle
    /// continue de 1 à 6.
    ///
    /// Ces valeurs sont des centres de distributions larges, pas des
    /// affectations. `nil` lorsqu'aucun indice utile ne s'en dégage : une
    /// ascendance mixte couvre par construction tout l'éventail, et l'estimation
    /// repose alors entièrement sur les autres réponses.
    var phototypeCentre: Double? {
        switch self {
        case .northernEurope:        return 1.8
        case .easternEurope:         return 2.4
        case .southernEurope:        return 3.2
        case .middleEastNorthAfrica: return 3.6
        case .subSaharanAfrica:      return 5.5
        case .southAsia:             return 4.3
        case .eastAsia:              return 3.3
        case .southeastAsia:         return 3.6
        case .indigenousAmericas:    return 3.6
        case .latinAmericaCaribbean: return 4.0
        case .oceania:               return 4.2
        case .mixed, .undisclosed:   return nil
        }
    }

    /// Regroupement pour l'affichage, afin que la liste reste lisible.
    static let grouped: [(title: String, options: [Ancestry])] = [
        ("Europe", [.northernEurope, .easternEurope, .southernEurope]),
        ("Afrique et Moyen-Orient", [.middleEastNorthAfrica, .subSaharanAfrica]),
        ("Asie", [.southAsia, .eastAsia, .southeastAsia]),
        ("Amériques et Pacifique", [.indigenousAmericas, .latinAmericaCaribbean, .oceania]),
        ("Autre", [.mixed, .undisclosed])
    ]
}
