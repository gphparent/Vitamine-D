import ActivityKit
import Foundation

/// Ce que l'application transmet au système pendant une sortie, et ce que
/// l'extension dessine sur l'écran verrouillé et dans l'île dynamique.
///
/// Ce fichier appartient aux deux cibles à la fois. C'est une exigence
/// d'ActivityKit et non une commodité : le système apparie l'activité à sa
/// présentation par le type des attributs, qui doit donc être littéralement le
/// même des deux côtés.
///
/// Rien de ce qui est ici ne doit dépendre du reste de l'application — ni du
/// modèle, ni du moteur de calcul. L'extension est un autre programme, chargé
/// par le système, qui ne connaît que ce fichier.
struct SunSessionAttributes: ActivityAttributes {

    /// Ce qui évolue au fil de la sortie.
    struct ContentState: Codable, Hashable {
        /// Vitamine D synthétisée depuis le début, plafond compris.
        var vitaminDIU: Double
        var goalIU: Double
        /// Part de la dose érythémale minimale déjà consommée, de 0 à 1.
        var medFraction: Double
        /// Seuil que l'utilisateur s'est fixé, en fraction de la DEM.
        var burnLimit: Double
        var uvIndex: Double
        /// Instant où il faudra rentrer. `nil` quand rien n'y oblige avant le
        /// coucher du Soleil.
        var stopAt: Date?
        var limit: Limit

        /// Ce qui mettra fin à la sortie.
        enum Limit: String, Codable, Hashable {
            case goal
            case burn
            case sunset
            case none

            var title: String {
                switch self {
                case .goal:   return "objectif atteint"
                case .burn:   return "limite cutanée"
                case .sunset: return "Soleil couchant"
                case .none:   return "sans échéance"
                }
            }
        }

        var goalFraction: Double {
            guard goalIU > 0 else { return 0 }
            return min(1, vitaminDIU / goalIU)
        }

        /// Progression vers le seuil que l'utilisateur s'est fixé, et non vers
        /// la rougeur elle-même : c'est ce seuil-là qui commande l'alerte.
        var burnFraction: Double {
            guard burnLimit > 0 else { return 0 }
            return min(1, medFraction / burnLimit)
        }

        /// Le capital cutané est-il en train de devenir le facteur limitant ?
        var isPressing: Bool { burnFraction >= 0.75 }

        /// Intervalle à décompter, ou `nil` si l'échéance est passée ou absente.
        ///
        /// Construit ici plutôt que dans la vue, et en un seul point : un
        /// `ClosedRange` dont la borne basse dépasse la haute fait planter le
        /// programme, et l'échéance passe forcément derrière nous pendant que
        /// l'activité reste affichée.
        var countdown: ClosedRange<Date>? {
            guard let stopAt else { return nil }
            let now = Date()
            guard stopAt > now else { return nil }
            return now...stopAt
        }

        /// Une seule phrase, pour les présentations les plus étroites.
        var headline: String {
            if burnFraction >= 1 { return "Rentrez" }
            if goalFraction >= 1 { return "Objectif atteint" }
            return "\(Int(vitaminDIU.rounded())) UI"
        }
    }

    /// Ce qui ne bouge pas de toute la sortie.
    var startedAt: Date
    var locationName: String
    var exposedBodyPercentage: Double
}
