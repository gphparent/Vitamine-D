import Foundation

/// Suggestion d'objectif quotidien, et l'état réel du débat qui l'entoure.
///
/// ## Il n'y a pas de chiffre officiel unique
///
/// C'est le point de départ, et il est souvent escamoté. Deux recommandations
/// coexistent chez des institutions également sérieuses, et elles diffèrent
/// d'un facteur trois.
///
/// L'**Institute of Medicine** (2011), dont les valeurs sont reprises par Santé
/// Canada et la FDA, fixe l'apport de référence à 600 UI par jour jusqu'à
/// 70 ans, 800 au-delà. La cible est une concentration sanguine de 50 nmol/L,
/// jugée suffisante pour la santé osseuse.
///
/// L'**Endocrine Society** (2011) vise 75 nmol/L et en déduit 1 500 à 2 000 UI
/// par jour pour un adulte. Le désaccord ne porte pas sur l'arithmétique mais
/// sur le seuil de suffisance : ce sont deux définitions différentes de « ne
/// pas manquer ».
///
/// ## Et l'arithmétique du chiffre bas est contestée
///
/// Veugelers et Ekwaru ont montré en 2014 que l'IOM avait commis une erreur
/// statistique dans le calcul de son apport recommandé : en reprenant ses
/// propres données, l'apport garantissant 50 nmol/L chez 97,5 % des gens — la
/// définition même d'un apport recommandé — ressort à près de 8 900 UI par
/// jour, non à 600. Des statisticiens indépendants ont confirmé le calcul.
///
/// Cela ne veut pas dire qu'il faut prendre 8 900 UI : cette valeur extrapole
/// au-delà des données disponibles, qui ne comportaient personne au-dessus de
/// 2 400 UI par jour, et l'IOM en conteste la portée. Mais cela veut dire que
/// **600 UI ne peut pas être présenté comme un chiffre solide**. C'est la borne
/// basse d'une fourchette, et la plus fragile des deux.
///
/// ## Ce que l'application en fait
///
/// Elle affiche la fourchette et suggère son milieu, plutôt que de nommer une
/// autorité. Un objectif ne détermine d'ailleurs jamais l'exposition : la
/// limite cutanée passe toujours devant, et un objectif hors de portée est
/// signalé comme tel au lieu de pousser à rester dehors.
///
/// Un avis médical prime sur tout ce qui précède, et une prise de sang tranche
/// ce qu'aucun modèle ne peut deviner.
enum VitaminDTarget {

    /// Borne basse : apport nutritionnel de référence de l'Institute of
    /// Medicine (2011), repris par Santé Canada. Vise 50 nmol/L.
    static let dietaryReferenceUnder70 = 600.0
    static let dietaryReferenceOver70 = 800.0

    /// Borne haute : recommandation de l'Endocrine Society pour un adulte,
    /// qui vise 75 nmol/L.
    static let clinicalReferenceLower = 1_500.0
    static let clinicalReferenceUpper = 2_000.0

    /// Apport maximal tolérable pour un adulte, valeur sur laquelle les deux
    /// camps s'accordent.
    static let tolerableUpperIntake = 4_000.0

    /// Corpulence, au sens où elle change le besoin.
    enum BodyCategory: String, Sendable {
        case unknown
        case normal
        case overweight
        case obese

        var title: String {
            switch self {
            case .unknown:    return "Corpulence inconnue"
            case .normal:     return "Corpulence normale"
            case .overweight: return "Surpoids"
            case .obese:      return "Obésité"
            }
        }

        /// Multiplicateur appliqué à la fourchette.
        ///
        /// La vitamine D est liposoluble : elle se répartit dans la masse
        /// grasse, où elle devient moins disponible. À dose égale, la
        /// concentration sanguine monte d'environ 13 nmol/L par 1 000 UI chez
        /// une personne de corpulence normale, 11,5 en surpoids et 8,6 en
        /// obésité. Les auteurs qui en tirent une posologie recommandent une
        /// fois et demie la dose en surpoids, deux à trois fois en obésité ; le
        /// bas de cette fourchette-là est retenu.
        var factor: Double {
            switch self {
            case .unknown, .normal: return 1.0
            case .overweight:       return 1.5
            case .obese:            return 2.0
            }
        }

        init(bmi: Double?) {
            guard let bmi, bmi > 10, bmi < 80 else { self = .unknown; return }
            switch bmi {
            case ..<25: self = .normal
            case ..<30: self = .overweight
            default:    self = .obese
            }
        }
    }

    struct Suggestion: Equatable, Sendable {
        /// Objectif suggéré : le milieu de la fourchette, arrondi et borné.
        let dailyIU: Double
        /// Borne basse, dérivée de l'apport de référence de l'IOM.
        let lowerIU: Double
        /// Borne haute, dérivée de la recommandation de l'Endocrine Society.
        let upperIU: Double
        let bodyFactor: Double
        let bmi: Double?
        let category: BodyCategory
        /// La borne haute a-t-elle été ramenée à l'apport maximal tolérable ?
        let wasCapped: Bool
    }

    /// Indice de masse corporelle, si les deux mesures sont connues.
    static func bodyMassIndex(weightKilograms: Double?, heightCentimetres: Double?) -> Double? {
        guard let weight = weightKilograms, let height = heightCentimetres,
              weight > 20, weight < 400, height > 90, height < 260 else { return nil }
        let metres = height / 100
        return weight / (metres * metres)
    }

    static func suggestion(age: Int,
                           weightKilograms: Double?,
                           heightCentimetres: Double?) -> Suggestion {

        let low = age > 70 ? dietaryReferenceOver70 : dietaryReferenceUnder70
        let bmi = bodyMassIndex(weightKilograms: weightKilograms,
                                heightCentimetres: heightCentimetres)
        let category = BodyCategory(bmi: bmi)

        let lower = low * category.factor
        let rawUpper = clinicalReferenceUpper * category.factor
        let upper = min(rawUpper, tolerableUpperIntake)

        // Le milieu de la fourchette, faute d'argument décisif pour l'une ou
        // l'autre de ses bornes. Arrondi à la centaine : un objectif à 1 297 UI
        // donnerait une fausse impression de précision sur une valeur que la
        // littérature ne connaît qu'à un facteur trois près.
        let middle = ((lower + upper) / 2 / 100).rounded() * 100

        return Suggestion(dailyIU: max(400, min(middle, tolerableUpperIntake)),
                          lowerIU: lower,
                          upperIU: upper,
                          bodyFactor: category.factor,
                          bmi: bmi,
                          category: category,
                          wasCapped: rawUpper > tolerableUpperIntake)
    }

    /// Phrase qui explique la suggestion, sans jamais la présenter comme une
    /// prescription ni s'abriter derrière une autorité.
    static func rationale(for suggestion: Suggestion, age: Int) -> String {
        var text = "Les recommandations vont de \(Int(suggestion.lowerIU)) UI "
        text += "— apport de référence de l'Institute of Medicine, repris par "
        text += "Santé Canada — à \(Int(suggestion.upperIU)) UI, recommandation "
        text += "de l'Endocrine Society. Elles ne visent pas la même "
        text += "concentration sanguine, d'où l'écart. "

        switch suggestion.category {
        case .unknown:
            text += "Indiquez votre taille et votre poids pour affiner : la vitamine D se "
            text += "répartit dans la masse grasse, et le besoin y varie du simple au double."
        case .normal:
            text += "Votre corpulence ne demande pas de correction."
        case .overweight, .obese:
            let percent = Int((suggestion.bodyFactor - 1) * 100)
            text += "La vitamine D étant liposoluble, elle se dilue dans la masse grasse : "
            text += "la fourchette est relevée d'environ \(percent) % dans votre cas."
        }

        if suggestion.wasCapped {
            text += " La borne haute est ramenée à l'apport maximal tolérable de "
            text += "\(Int(tolerableUpperIntake)) UI."
        }

        text += " La valeur proposée en est le milieu."
        return text
    }
}
