import Foundation

/// Questionnaire d'estimation du phototype.
///
/// Cinq questions notées de 0 à 4, dans l'esprit du questionnaire
/// auto-administré de Fitzpatrick : trois portent sur des caractères
/// constitutionnels — yeux, cheveux, taches de rousseur —, deux sur la réaction
/// au soleil. S'y ajoute l'ascendance, en simple indice de départ.
///
/// Le total est converti linéairement en phototype continu, puis moyenné avec
/// l'indice d'ascendance. Cette linéarité est une simplification assumée : le
/// questionnaire original emploie des seuils par paliers, mais l'écart tient
/// dans la marge d'incertitude de l'exercice, et une échelle continue permet
/// d'afficher honnêtement les cas limites.
struct PhototypeQuestionnaire: Equatable, Sendable {

    /// Une question et ses réponses, de la peau la plus claire à la plus foncée.
    struct Question: Identifiable, Sendable {
        let id: String
        let prompt: String
        let detail: String?
        /// Réponses ordonnées ; l'indice vaut la note, de 0 à 4.
        let answers: [String]
        /// Les caractères constitutionnels sont moins fiables que la réaction
        /// au soleil : quelqu'un peut avoir les cheveux foncés et brûler quand
        /// même. On les pèse donc un peu moins.
        let weight: Double
    }

    static let questions: [Question] = [
        Question(
            id: "eyes",
            prompt: "Couleur de vos yeux",
            detail: nil,
            answers: ["Bleu très clair, gris, vert clair",
                      "Bleu, gris, vert",
                      "Noisette, brun clair",
                      "Brun foncé",
                      "Brun très foncé, presque noir"],
            weight: 0.8),
        Question(
            id: "hair",
            prompt: "Couleur naturelle de vos cheveux",
            detail: "Celle de l'enfance, avant teinture ou décoloration au soleil.",
            answers: ["Roux, blond très clair",
                      "Blond",
                      "Châtain clair",
                      "Châtain foncé",
                      "Noir"],
            weight: 0.8),
        Question(
            id: "freckles",
            prompt: "Taches de rousseur sur les zones jamais exposées",
            detail: "Le ventre, l'intérieur des bras.",
            answers: ["Nombreuses", "Quelques-unes", "Peu", "Très peu", "Aucune"],
            weight: 0.8),
        Question(
            id: "burn",
            prompt: "Après 30 minutes de soleil de midi en juin, sans crème",
            detail: "La première exposition de la saison, pas au mois d'août.",
            answers: ["Je brûle toujours, douloureusement",
                      "Je brûle facilement",
                      "Je brûle modérément",
                      "Je brûle rarement",
                      "Je ne brûle jamais"],
            weight: 1.6),
        Question(
            id: "tan",
            prompt: "Quelques jours après cette exposition",
            detail: nil,
            answers: ["Je ne bronze pas du tout",
                      "Je bronze un peu",
                      "Je bronze progressivement",
                      "Je bronze bien et vite",
                      "Je bronze intensément"],
            weight: 1.6),
    ]

    /// Réponses, indexées par identifiant de question. Une question sans réponse
    /// est simplement ignorée dans le calcul.
    var answers: [String: Int] = [:]
    var ancestry: Ancestry?

    /// Poids de l'ascendance dans l'estimation finale.
    ///
    /// Un quart : assez pour départager deux profils par ailleurs identiques,
    /// trop peu pour contredire une réaction cutanée clairement décrite.
    static let ancestryWeight = 0.25

    var isComplete: Bool {
        Self.questions.allSatisfy { answers[$0.id] != nil }
    }

    /// Phototype suggéré par les seules réponses au questionnaire, sur l'échelle
    /// continue de 1 à 6. `nil` tant qu'aucune question n'a de réponse.
    var questionnaireEstimate: Double? {
        var weighted = 0.0
        var totalWeight = 0.0
        for question in Self.questions {
            guard let answer = answers[question.id] else { continue }
            let clamped = min(4, max(0, answer))
            weighted += Double(clamped) * question.weight
            totalWeight += 4 * question.weight
        }
        guard totalWeight > 0 else { return nil }
        return 1 + 5 * (weighted / totalWeight)
    }

    /// Phototype suggéré par la seule ascendance.
    var ancestryEstimate: Double? { ancestry?.phototypeCentre }

    /// Estimation combinée, arrondie au phototype le plus proche.
    var suggestion: SkinType {
        let combined: Double
        switch (questionnaireEstimate, ancestryEstimate) {
        case let (questionnaire?, ancestry?):
            combined = questionnaire * (1 - Self.ancestryWeight)
                + ancestry * Self.ancestryWeight
        case let (questionnaire?, nil):
            combined = questionnaire
        case let (nil, ancestry?):
            combined = ancestry
        case (nil, nil):
            combined = 3
        }
        let rounded = Int(combined.rounded())
        return SkinType(rawValue: min(6, max(1, rounded))) ?? .iii
    }

    /// Les deux indices divergent-ils assez pour mériter une explication ?
    var signalsDisagree: Bool {
        guard let questionnaire = questionnaireEstimate,
              let ancestry = ancestryEstimate else { return false }
        return abs(questionnaire - ancestry) >= 1.0
    }

    /// Phrase expliquant ce qui a emporté la décision.
    ///
    /// Montrer le désaccord plutôt que le masquer : c'est ce qui apprend à
    /// l'utilisateur que sa réaction au soleil compte davantage que son
    /// ascendance, et l'invite à corriger si l'estimation le surprend.
    var explanation: String? {
        guard let questionnaire = questionnaireEstimate else { return nil }
        guard let ancestry = ancestryEstimate, signalsDisagree else {
            return "Estimation fondée sur vos réponses. Corrigez-la si elle "
                + "ne correspond pas à ce que vous observez."
        }
        let reaction = SkinType(rawValue: min(6, max(1, Int(questionnaire.rounded()))))?.romanNumeral ?? "III"
        let origin = SkinType(rawValue: min(6, max(1, Int(ancestry.rounded()))))?.romanNumeral ?? "III"
        return "Vos réponses indiquent un type \(reaction), votre ascendance "
            + "plutôt un type \(origin). C'est la réaction de votre peau qui "
            + "pèse le plus : elle mesure directement la dose au-delà de "
            + "laquelle vous rougissez, là où l'ascendance ne donne qu'une "
            + "moyenne de population."
    }
}
