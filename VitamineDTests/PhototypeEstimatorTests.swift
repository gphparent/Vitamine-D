import Foundation
import Testing
@testable import VitamineD

struct PhototypeEstimatorTests {

    /// Répond à toutes les questions par le même indice, de 0 à 4.
    private func uniform(_ answer: Int, ancestry: Ancestry? = nil) -> PhototypeQuestionnaire {
        var questionnaire = PhototypeQuestionnaire(ancestry: ancestry)
        for question in PhototypeQuestionnaire.questions {
            questionnaire.answers[question.id] = answer
        }
        return questionnaire
    }

    @Test("Les extrêmes du questionnaire donnent les phototypes extrêmes")
    func extremesMapToExtremes() {
        #expect(uniform(0).suggestion == .i)
        #expect(uniform(4).suggestion == .vi)
    }

    @Test("L'estimation croît avec les réponses")
    func estimateIsMonotonic() throws {
        var previous = 0.0
        for answer in 0...4 {
            let estimate = try #require(uniform(answer).questionnaireEstimate)
            #expect(estimate > previous)
            previous = estimate
        }
    }

    @Test("Un questionnaire vide ne prétend rien")
    func emptyQuestionnaireHasNoEstimate() {
        let empty = PhototypeQuestionnaire()
        #expect(empty.questionnaireEstimate == nil)
        #expect(!empty.isComplete)
        // Faute de tout signal, on se place au milieu plutôt que de refuser.
        #expect(empty.suggestion == .iii)
    }

    @Test("La réaction au soleil pèse plus lourd que les caractères constitutionnels")
    func reactionOutweighsAppearance() throws {
        // Cheveux noirs, yeux foncés, aucune tache — mais brûle toujours,
        // ne bronze jamais. C'est le cas qu'un simple coup d'œil rate.
        var questionnaire = PhototypeQuestionnaire()
        questionnaire.answers = ["eyes": 4, "hair": 4, "freckles": 4, "burn": 0, "tan": 0]
        let mixed = try #require(questionnaire.questionnaireEstimate)

        var appearanceOnly = PhototypeQuestionnaire()
        appearanceOnly.answers = ["eyes": 4, "hair": 4, "freckles": 4, "burn": 2, "tan": 2]
        let neutral = try #require(appearanceOnly.questionnaireEstimate)

        #expect(mixed < neutral)
        // La réaction tire l'estimation nettement vers le clair malgré
        // l'apparence foncée.
        #expect(questionnaire.suggestion.rawValue <= SkinType.iii.rawValue)
    }

    // MARK: - Ascendance

    @Test("L'ascendance déplace l'estimation sans la dicter")
    func ancestryNudgesWithoutDeciding() throws {
        let neutral = uniform(2)
        let withNorth = uniform(2, ancestry: .northernEurope)
        let withAfrica = uniform(2, ancestry: .subSaharanAfrica)

        let base = try #require(neutral.questionnaireEstimate)
        #expect(neutral.suggestion.rawValue == Int(base.rounded()))

        // Les deux ascendances tirent dans des sens opposés…
        #expect(withNorth.suggestion.rawValue <= neutral.suggestion.rawValue)
        #expect(withAfrica.suggestion.rawValue >= neutral.suggestion.rawValue)

        // …mais sans jamais amener au phototype que l'ascendance seule
        // suggérerait : le questionnaire garde les trois quarts du poids.
        #expect(withAfrica.suggestion != .vi)
    }

    @Test("Une réaction claire résiste à une ascendance contraire")
    func strongReactionResistsAncestry() {
        // Brûle toujours, ne bronze jamais, mais ascendance subsaharienne.
        var questionnaire = PhototypeQuestionnaire(ancestry: .subSaharanAfrica)
        questionnaire.answers = ["eyes": 0, "hair": 0, "freckles": 0, "burn": 0, "tan": 0]
        // L'ascendance déplace d'un cran au plus, elle ne renverse pas.
        #expect(questionnaire.suggestion.rawValue <= SkinType.ii.rawValue)
        #expect(questionnaire.signalsDisagree)
        #expect(questionnaire.explanation != nil)
    }

    @Test("Une ascendance sans indice utile laisse le questionnaire seul")
    func neutralAncestryChangesNothing() throws {
        let plain = uniform(3)
        for ancestry in [Ancestry.mixed, .undisclosed] {
            let withAncestry = uniform(3, ancestry: ancestry)
            #expect(withAncestry.ancestryEstimate == nil)
            #expect(withAncestry.suggestion == plain.suggestion)
            #expect(!withAncestry.signalsDisagree)
        }
    }

    @Test("Le désaccord n'est signalé que s'il est réel")
    func disagreementIsOnlyFlaggedWhenSubstantial() {
        // Questionnaire au centre, ascendance au centre : rien à expliquer.
        var aligned = PhototypeQuestionnaire(ancestry: .southernEurope)
        aligned.answers = ["eyes": 2, "hair": 2, "freckles": 2, "burn": 2, "tan": 2]
        #expect(!aligned.signalsDisagree)

        var opposed = PhototypeQuestionnaire(ancestry: .subSaharanAfrica)
        opposed.answers = ["eyes": 0, "hair": 0, "freckles": 0, "burn": 0, "tan": 0]
        #expect(opposed.signalsDisagree)
    }

    @Test("Toutes les ascendances proposées sont classées dans un groupe")
    func everyAncestryIsListed() {
        let listed = Set(Ancestry.grouped.flatMap(\.options))
        #expect(listed == Set(Ancestry.allCases))
    }

    // MARK: - Persistance du profil

    @Test("Un profil enregistré par une version antérieure survit à la mise à jour")
    func legacyProfileSurvivesDecoding() throws {
        // Ni `ancestry` ni `hasCompletedOnboarding` : le format d'avant.
        let legacy = """
        {
          "skinType": 5,
          "age": 42,
          "tanLevel": 2,
          "exposure": {"preset":"swimwear","customRegions":[],"sunscreenSPF":30,"wearsHat":true},
          "dailyGoalIU": 2500,
          "burnAlertFraction": 0.45,
          "notifyWindowOpening": false,
          "notifyDailyPlan": true,
          "dailyPlanMinuteOfDay": 400
        }
        """.data(using: .utf8)!

        let profile = try JSONDecoder().decode(UserProfile.self, from: legacy)

        #expect(profile.skinType == .v)
        #expect(profile.age == 42)
        #expect(profile.dailyGoalIU == 2500)
        #expect(profile.exposure.sunscreenSPF == 30)
        // L'étoffe n'existait pas dans ce format : la tenue enregistrée en
        // suggère une plutôt que de faire échouer la relecture du profil entier.
        #expect(profile.exposure.fabric == ClothingPreset.swimwear.suggestedFabric)
        #expect(profile.burnAlertFraction == 0.45)
        // Quelqu'un qui a déjà un profil enregistré n'a pas à repasser
        // par l'accueil.
        #expect(profile.hasCompletedOnboarding)
        #expect(profile.ancestry == nil)
    }

    @Test("Un profil vide ne fait pas tout perdre")
    func emptyPayloadFallsBackToDefaults() throws {
        let profile = try JSONDecoder().decode(
            UserProfile.self, from: "{}".data(using: .utf8)!)
        #expect(profile.skinType == UserProfile.default.skinType)
        #expect(profile.dailyGoalIU == UserProfile.default.dailyGoalIU)
    }

    @Test("Un aller-retour d'encodage conserve tout")
    func roundTripPreservesEverything() throws {
        var profile = UserProfile.default
        profile.skinType = .iv
        profile.ancestry = .southAsia
        profile.hasCompletedOnboarding = true
        profile.age = 58

        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        #expect(decoded == profile)
    }
}
