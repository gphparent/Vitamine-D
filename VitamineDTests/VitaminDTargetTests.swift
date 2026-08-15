import Foundation
import Testing
@testable import VitamineD

/// L'objectif suggéré est le seul chiffre de l'application qui ressemble à une
/// posologie. Il doit donc rester dans les bornes que les autorités publient,
/// quoi qu'on lui donne à manger.
struct VitaminDTargetTests {

    // MARK: - Une fourchette, pas une autorité

    @Test("La suggestion est le milieu de la fourchette publiée")
    func suggestionSitsBetweenTheTwoInstitutions() {
        let suggestion = VitaminDTarget.suggestion(
            age: 35, weightKilograms: 70, heightCentimetres: 175)

        #expect(suggestion.category == .normal)
        #expect(suggestion.lowerIU == VitaminDTarget.dietaryReferenceUnder70)
        #expect(suggestion.upperIU == VitaminDTarget.clinicalReferenceUpper)
        // Ni l'une ni l'autre des bornes : les institutions ne s'accordent pas,
        // et retenir l'une d'elles serait choisir un camp sans argument.
        #expect(suggestion.dailyIU > suggestion.lowerIU)
        #expect(suggestion.dailyIU < suggestion.upperIU)
        #expect(!suggestion.wasCapped)
    }

    @Test("Au-delà de 70 ans, la borne basse monte à 800 UI")
    func olderAdultGetsHigherLowerBound() {
        let suggestion = VitaminDTarget.suggestion(
            age: 75, weightKilograms: 70, heightCentimetres: 175)

        #expect(suggestion.lowerIU == VitaminDTarget.dietaryReferenceOver70)
        #expect(suggestion.dailyIU > VitaminDTarget.dietaryReferenceOver70)
    }

    @Test("Sans mesure, la fourchette reste celle d'un adulte non corrigé")
    func missingMeasurementsLeaveTheRangeUncorrected() {
        let suggestion = VitaminDTarget.suggestion(
            age: 35, weightKilograms: nil, heightCentimetres: nil)

        #expect(suggestion.category == .unknown)
        #expect(suggestion.bmi == nil)
        #expect(suggestion.bodyFactor == 1)
        #expect(suggestion.lowerIU == VitaminDTarget.dietaryReferenceUnder70)
        #expect(suggestion.upperIU == VitaminDTarget.clinicalReferenceUpper)
    }

    // MARK: - Corpulence

    @Test("La corpulence classe selon les seuils usuels de l'IMC")
    func bodyCategoryFollowsBodyMassIndex() {
        // 1,75 m : 76 kg donne 24,8 ; 85 kg donne 27,8 ; 95 kg donne 31,0.
        #expect(VitaminDTarget.BodyCategory(
            bmi: VitaminDTarget.bodyMassIndex(weightKilograms: 76,
                                              heightCentimetres: 175)) == .normal)
        #expect(VitaminDTarget.BodyCategory(
            bmi: VitaminDTarget.bodyMassIndex(weightKilograms: 85,
                                              heightCentimetres: 175)) == .overweight)
        #expect(VitaminDTarget.BodyCategory(
            bmi: VitaminDTarget.bodyMassIndex(weightKilograms: 95,
                                              heightCentimetres: 175)) == .obese)
    }

    @Test("Le besoin croît avec la corpulence, sans jamais décroître")
    func suggestionIsMonotonicInBodyMass() {
        let weights: [Double] = [55, 70, 85, 100, 130]
        let suggestions = weights.map {
            VitaminDTarget.suggestion(age: 40, weightKilograms: $0,
                                      heightCentimetres: 175).dailyIU
        }
        let sorted = suggestions.sorted()
        #expect(suggestions == sorted)
        #expect(suggestions.first! < suggestions.last!)
    }

    @Test("Une mesure absurde ne classe pas la corpulence")
    func nonsensicalMeasurementsAreIgnored() {
        #expect(VitaminDTarget.bodyMassIndex(weightKilograms: 5,
                                             heightCentimetres: 175) == nil)
        #expect(VitaminDTarget.bodyMassIndex(weightKilograms: 70,
                                             heightCentimetres: 12) == nil)
        // Une taille en mètres saisie par mégarde ne doit pas produire un IMC
        // de vingt-deux mille.
        #expect(VitaminDTarget.bodyMassIndex(weightKilograms: 70,
                                             heightCentimetres: 1.75) == nil)
    }

    // MARK: - Bornes

    @Test("La suggestion ne dépasse jamais l'apport maximal tolérable")
    func suggestionNeverExceedsTheUpperIntake() {
        for age in [20, 45, 80] {
            for weight in stride(from: 40.0, through: 250.0, by: 10) {
                for height in stride(from: 140.0, through: 200.0, by: 10) {
                    let suggestion = VitaminDTarget.suggestion(
                        age: age, weightKilograms: weight, heightCentimetres: height)
                    #expect(suggestion.dailyIU <= VitaminDTarget.tolerableUpperIntake)
                    #expect(suggestion.upperIU <= VitaminDTarget.tolerableUpperIntake)
                    #expect(suggestion.dailyIU >= 400)
                    #expect(suggestion.dailyIU >= suggestion.lowerIU)
                    // Un objectif à 897 UI donnerait une fausse impression de
                    // précision sur une valeur qui n'en a aucune.
                    #expect(suggestion.dailyIU.truncatingRemainder(dividingBy: 100) == 0)
                }
            }
        }
    }

    // MARK: - Explication

    @Test("L'explication nomme les deux bornes et leurs auteurs")
    func rationaleNamesBothInstitutions() {
        let unknown = VitaminDTarget.suggestion(
            age: 35, weightKilograms: nil, heightCentimetres: nil)
        let text = VitaminDTarget.rationale(for: unknown, age: 35)

        // Les deux camps sont cités, et aucun n'est présenté seul : donner un
        // chiffre unique reviendrait à trancher un débat ouvert.
        #expect(text.contains("Institute of Medicine"))
        #expect(text.contains("Endocrine Society"))
        #expect(text.contains("600"))
        #expect(text.contains("2000") || text.contains("2 000"))
        // Sans mesure, l'explication doit inviter à les fournir plutôt que de
        // laisser croire que le chiffre est personnalisé.
        #expect(text.contains("taille"))
    }

    @Test("Le profil signale un objectif éloigné de la suggestion")
    func profileFlagsADivergentGoal() {
        var profile = UserProfile.default
        profile.age = 35
        profile.weightKilograms = 70
        profile.heightCentimetres = 175

        profile.dailyGoalIU = profile.suggestedGoal.dailyIU
        #expect(!profile.goalDivergesFromSuggestion)

        profile.dailyGoalIU = 2000
        #expect(profile.goalDivergesFromSuggestion)
    }
}
