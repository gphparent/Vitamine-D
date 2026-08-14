import Foundation

/// Suggestion d'objectif quotidien, à partir de ce que les autorités publient.
///
/// ## D'où viennent les chiffres
///
/// L'ancrage est l'apport nutritionnel recommandé de Santé Canada, repris de
/// l'Institute of Medicine : 600 UI par jour jusqu'à 70 ans, 800 au-delà, avec
/// un apport maximal tolérable de 4 000 UI. Ce sont les seules valeurs de ce
/// fichier qui aient une autorité réglementaire.
///
/// S'y ajoute une correction de corpulence, et celle-là relève de la
/// littérature plutôt que de la réglementation. La vitamine D est liposoluble :
/// elle se répartit dans la masse grasse, où elle devient moins disponible. À
/// dose égale, la concentration sanguine monte d'environ 13 nmol/L par
/// 1 000 UI chez une personne de corpulence normale, 11,5 en surpoids et 8,6
/// en obésité. Les auteurs qui en tirent une posologie recommandent une fois
/// et demie la dose en surpoids, deux à trois fois en obésité.
///
/// ## Ce que la suggestion n'est pas
///
/// Ce n'est pas une prescription, et l'application n'a aucun moyen de savoir
/// ce que contient votre sang. L'apport recommandé est de surcroît défini pour
/// une exposition solaire minimale : l'utiliser comme cible de synthèse
/// cutanée est une simplification volontaire, et elle penche du côté prudent
/// — on ne peut pas s'intoxiquer à la vitamine D par le seul soleil, le
/// photo-équilibre s'en charge.
///
/// Un avis médical prime sur tout ce qui suit, sans exception.
enum VitaminDTarget {

    /// Apport nutritionnel recommandé, Santé Canada / IOM.
    static let referenceIntakeUnder70 = 600.0
    static let referenceIntakeOver70 = 800.0
    /// Apport maximal tolérable pour un adulte.
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

        /// Multiplicateur appliqué à l'apport de référence.
        ///
        /// Le bas de la fourchette publiée est retenu — deux fois plutôt que
        /// trois en obésité — parce qu'une suggestion trop haute pousserait à
        /// s'exposer davantage, donc à dépenser du capital cutané, pour une
        /// cible que rien ne vérifie.
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
        /// Objectif suggéré, arrondi à la centaine et borné.
        let dailyIU: Double
        /// Apport de référence avant correction.
        let referenceIU: Double
        let bodyFactor: Double
        let bmi: Double?
        let category: BodyCategory
        /// La suggestion a-t-elle été plafonnée par l'apport maximal tolérable ?
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

        let reference = age > 70 ? referenceIntakeOver70 : referenceIntakeUnder70
        let bmi = bodyMassIndex(weightKilograms: weightKilograms,
                                heightCentimetres: heightCentimetres)
        let category = BodyCategory(bmi: bmi)

        let raw = reference * category.factor
        let capped = min(raw, tolerableUpperIntake)
        // Arrondi à la centaine : un objectif à 900 UI se retient, un objectif
        // à 897 donne une fausse impression de précision.
        let rounded = (capped / 100).rounded() * 100

        return Suggestion(dailyIU: max(400, rounded),
                          referenceIU: reference,
                          bodyFactor: category.factor,
                          bmi: bmi,
                          category: category,
                          wasCapped: raw > tolerableUpperIntake)
    }

    /// Phrase qui explique la suggestion, sans jamais la présenter comme une
    /// prescription.
    static func rationale(for suggestion: Suggestion, age: Int) -> String {
        var text = "Apport de référence de Santé Canada pour "
        text += age > 70 ? "plus de 70 ans" : "un adulte"
        text += " : \(Int(suggestion.referenceIU)) UI par jour. "

        switch suggestion.category {
        case .unknown:
            text += "Indiquez votre taille et votre poids pour affiner : la vitamine D se "
            text += "répartit dans la masse grasse, et le besoin y varie du simple au double."
        case .normal:
            text += "Votre corpulence ne demande pas de correction."
        case .overweight, .obese:
            let percent = Int((suggestion.bodyFactor - 1) * 100)
            text += "La vitamine D étant liposoluble, elle se dilue dans la masse grasse : "
            text += "la littérature suggère environ \(percent) % de plus dans votre cas."
        }

        if suggestion.wasCapped {
            text += " La valeur est plafonnée à l'apport maximal tolérable de "
            text += "\(Int(tolerableUpperIntake)) UI."
        }
        return text
    }
}
