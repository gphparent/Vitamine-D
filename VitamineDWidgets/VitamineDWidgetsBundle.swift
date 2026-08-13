import SwiftUI
import WidgetKit

/// Point d'entrée de l'extension.
///
/// Elle ne contient pour l'instant qu'une activité en direct, et aucune
/// vignette d'écran d'accueil : une vignette qui afficherait l'indice UV du
/// moment devrait le recalculer en arrière-plan, avec la position et la
/// météo — beaucoup de machinerie pour un chiffre que l'application donne déjà.
@main
struct VitamineDWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SunSessionLiveActivity()
    }
}
