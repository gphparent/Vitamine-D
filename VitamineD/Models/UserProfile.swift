import Foundation

/// Profil de l'utilisateur : tout ce qui, du côté de la personne, module la
/// synthèse de vitamine D et le risque d'érythème.
struct UserProfile: Codable, Equatable, Sendable {
    var skinType: SkinType
    var age: Int
    var tanLevel: TanLevel
    var exposure: BodyExposure

    /// Ascendance déclarée, conservée pour pouvoir réafficher le questionnaire
    /// tel qu'il a été rempli. N'intervient plus dans aucun calcul une fois le
    /// phototype fixé.
    var ancestry: Ancestry?

    /// Poids en kilogrammes, facultatif.
    ///
    /// N'entre dans aucun calcul de dose : la synthèse cutanée dépend de la
    /// surface de peau et non de la masse. Le poids et la taille ne servent
    /// qu'à suggérer un objectif quotidien, parce que la vitamine D est
    /// liposoluble et se dilue dans la masse grasse.
    var weightKilograms: Double?
    /// Taille en centimètres, facultative. Même usage que le poids.
    var heightCentimetres: Double?

    /// Objectif quotidien de synthèse cutanée, en UI.
    var dailyGoalIU: Double

    /// Part de la DEM qu'on s'autorise à atteindre avant l'alerte d'arrêt.
    /// 0,6 correspond à la recommandation prudente : la synthèse de vitamine D
    /// plafonne bien avant l'érythème, il n'y a aucun bénéfice à s'en approcher.
    var burnAlertFraction: Double

    var notifyWindowOpening: Bool
    var notifyDailyPlan: Bool
    /// Heure de la notification du plan quotidien, en minutes depuis minuit.
    var dailyPlanMinuteOfDay: Int

    /// L'accueil du premier lancement a-t-il été traversé ?
    var hasCompletedOnboarding: Bool

    // MARK: - Lumière et horloge interne

    /// Suivre aussi la lumière du matin, pour le calage circadien.
    /// L'application peut-elle lire les données de santé de l'appareil ?
    ///
    /// Lecture seule, et rien n'y est jamais écrit : il n'existe aucun type
    /// HealthKit pour la synthèse cutanée, et verser ce que la peau fabrique
    /// dans la vitamine D « alimentaire » fausserait le suivi nutritionnel de
    /// l'utilisateur avec quelque chose qu'il n'a pas mangé.
    var readsHealthKit: Bool

    /// L'application enregistre-t-elle ses sorties dans Santé ?
    ///
    /// Ce qui est écrit est l'exposition mesurée — indice UV moyen et durée —
    /// qui décrit exactement ce que la sortie a été.
    var writesHealthKit: Bool

    /// Verser en plus la vitamine D synthétisée dans le champ *alimentaire*.
    ///
    /// Séparé du réglage précédent, et désactivé par défaut, parce que c'est le
    /// seul point où l'application écrirait une donnée dans un champ qui ne lui
    /// correspond pas tout à fait : HealthKit ne connaît que la vitamine D
    /// avalée. Le total devient juste, la provenance devient fausse — et
    /// l'arbitrage appartient à l'utilisateur, pas au programme.
    var writesVitaminDAsDietary: Bool

    var tracksCircadianLight: Bool
    /// Heure de lever habituelle, en minutes depuis minuit.
    var wakeMinuteOfDay: Int
    /// Heure de lever visée, si elle diffère de l'habituelle.
    var targetWakeMinuteOfDay: Int
    /// Durée de sommeil souhaitée, en heures.
    var sleepHours: Double
    var notifyMorningLight: Bool

    /// Étapes de la routine du soir pour lesquelles un rappel quotidien est
    /// programmé, par identifiant.
    ///
    /// Conservé en chaînes plutôt qu'en cas d'énumération : une version qui
    /// retirerait une étape ne doit pas rendre le profil illisible.
    var sleepReminders: Set<String>

    static let `default` = UserProfile(
        skinType: .iii,
        age: 35,
        tanLevel: .none,
        exposure: BodyExposure(),
        ancestry: nil,
        weightKilograms: nil,
        heightCentimetres: nil,
        dailyGoalIU: 1000,
        burnAlertFraction: 0.6,
        notifyWindowOpening: true,
        notifyDailyPlan: true,
        dailyPlanMinuteOfDay: 8 * 60,
        hasCompletedOnboarding: false,
        readsHealthKit: false,
        writesHealthKit: false,
        writesVitaminDAsDietary: false,
        tracksCircadianLight: true,
        wakeMinuteOfDay: 7 * 60,
        targetWakeMinuteOfDay: 7 * 60,
        sleepHours: 8,
        notifyMorningLight: false,
        sleepReminders: []
    )

    /// Rendement lié à l'âge.
    ///
    /// La concentration cutanée en 7-déhydrocholestérol décroît régulièrement
    /// après la vingtaine ; à 70 ans elle vaut environ la moitié de celle d'un
    /// jeune adulte (Holick, 1989). Le facteur est borné à 0,4 pour éviter une
    /// extrapolation absurde aux grands âges.
    var ageFactor: Double {
        let reference = 20.0
        guard Double(age) > reference else { return 1.0 }
        return max(0.4, 1.0 - 0.01 * (Double(age) - reference))
    }

    /// Dose érythémale minimale effective, acclimatation comprise, en J/m².
    var effectiveMED: Double {
        skinType.medJoulesPerSquareMetre * tanLevel.medMultiplier
    }

    // MARK: - Décodage tolérant

    /// Chaque champ est lu séparément, avec repli sur la valeur par défaut.
    ///
    /// Le décodage synthétisé échouerait dès qu'une version ajoute un champ,
    /// et l'application repartirait alors d'un profil vierge : phototype,
    /// tenue et objectif effacés sans un mot. Pour des réglages que
    /// l'utilisateur a pris la peine de saisir, c'est inacceptable.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = UserProfile.default

        skinType = (try? container.decode(SkinType.self, forKey: .skinType)) ?? fallback.skinType
        age = (try? container.decode(Int.self, forKey: .age)) ?? fallback.age
        tanLevel = (try? container.decode(TanLevel.self, forKey: .tanLevel)) ?? fallback.tanLevel
        exposure = (try? container.decode(BodyExposure.self, forKey: .exposure)) ?? fallback.exposure
        ancestry = try? container.decodeIfPresent(Ancestry.self, forKey: .ancestry)
        weightKilograms = try? container.decodeIfPresent(Double.self, forKey: .weightKilograms)
        heightCentimetres = try? container.decodeIfPresent(Double.self, forKey: .heightCentimetres)
        dailyGoalIU = (try? container.decode(Double.self, forKey: .dailyGoalIU)) ?? fallback.dailyGoalIU
        burnAlertFraction = (try? container.decode(Double.self, forKey: .burnAlertFraction))
            ?? fallback.burnAlertFraction
        notifyWindowOpening = (try? container.decode(Bool.self, forKey: .notifyWindowOpening))
            ?? fallback.notifyWindowOpening
        notifyDailyPlan = (try? container.decode(Bool.self, forKey: .notifyDailyPlan))
            ?? fallback.notifyDailyPlan
        dailyPlanMinuteOfDay = (try? container.decode(Int.self, forKey: .dailyPlanMinuteOfDay))
            ?? fallback.dailyPlanMinuteOfDay

        // Un profil enregistré par une version antérieure vient forcément de
        // quelqu'un qui s'est déjà servi de l'application : lui imposer
        // l'accueil serait absurde.
        hasCompletedOnboarding = (try? container.decode(Bool.self, forKey: .hasCompletedOnboarding)) ?? true

        tracksCircadianLight = (try? container.decode(Bool.self, forKey: .tracksCircadianLight))
            ?? fallback.tracksCircadianLight
        wakeMinuteOfDay = (try? container.decode(Int.self, forKey: .wakeMinuteOfDay))
            ?? fallback.wakeMinuteOfDay
        targetWakeMinuteOfDay = (try? container.decode(Int.self, forKey: .targetWakeMinuteOfDay))
            ?? wakeMinuteOfDay
        sleepHours = (try? container.decode(Double.self, forKey: .sleepHours)) ?? fallback.sleepHours
        readsHealthKit = (try? container.decode(Bool.self, forKey: .readsHealthKit))
            ?? fallback.readsHealthKit
        writesHealthKit = (try? container.decode(Bool.self, forKey: .writesHealthKit))
            ?? fallback.writesHealthKit
        writesVitaminDAsDietary = (try? container.decode(Bool.self, forKey: .writesVitaminDAsDietary))
            ?? fallback.writesVitaminDAsDietary
        notifyMorningLight = (try? container.decode(Bool.self, forKey: .notifyMorningLight))
            ?? fallback.notifyMorningLight
        sleepReminders = (try? container.decode(Set<String>.self, forKey: .sleepReminders))
            ?? fallback.sleepReminders
    }

    init(skinType: SkinType,
         age: Int,
         tanLevel: TanLevel,
         exposure: BodyExposure,
         ancestry: Ancestry?,
         weightKilograms: Double? = nil,
         heightCentimetres: Double? = nil,
         dailyGoalIU: Double,
         burnAlertFraction: Double,
         notifyWindowOpening: Bool,
         notifyDailyPlan: Bool,
         dailyPlanMinuteOfDay: Int,
         hasCompletedOnboarding: Bool,
         readsHealthKit: Bool = false,
         writesHealthKit: Bool = false,
         writesVitaminDAsDietary: Bool = false,
         tracksCircadianLight: Bool,
         wakeMinuteOfDay: Int,
         targetWakeMinuteOfDay: Int,
         sleepHours: Double,
         notifyMorningLight: Bool,
         sleepReminders: Set<String> = []) {
        self.skinType = skinType
        self.age = age
        self.tanLevel = tanLevel
        self.exposure = exposure
        self.ancestry = ancestry
        self.weightKilograms = weightKilograms
        self.heightCentimetres = heightCentimetres
        self.dailyGoalIU = dailyGoalIU
        self.burnAlertFraction = burnAlertFraction
        self.notifyWindowOpening = notifyWindowOpening
        self.notifyDailyPlan = notifyDailyPlan
        self.dailyPlanMinuteOfDay = dailyPlanMinuteOfDay
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.readsHealthKit = readsHealthKit
        self.writesHealthKit = writesHealthKit
        self.writesVitaminDAsDietary = writesVitaminDAsDietary
        self.tracksCircadianLight = tracksCircadianLight
        self.wakeMinuteOfDay = wakeMinuteOfDay
        self.targetWakeMinuteOfDay = targetWakeMinuteOfDay
        self.sleepHours = sleepHours
        self.notifyMorningLight = notifyMorningLight
        self.sleepReminders = sleepReminders
    }

    /// Le lever visé diffère-t-il de l'habituel ?
    var wantsPhaseShift: Bool { targetWakeMinuteOfDay != wakeMinuteOfDay }

    // MARK: - Objectif

    /// Objectif quotidien que la littérature suggère pour ce profil.
    var suggestedGoal: VitaminDTarget.Suggestion {
        VitaminDTarget.suggestion(age: age,
                                  weightKilograms: weightKilograms,
                                  heightCentimetres: heightCentimetres)
    }

    /// L'objectif retenu s'écarte-t-il nettement de la suggestion ?
    ///
    /// La tolérance vaut un cran du réglage : signaler un écart de cent unités
    /// serait du bruit, et l'utilisateur a le droit de choisir sa valeur.
    var goalDivergesFromSuggestion: Bool {
        abs(dailyGoalIU - suggestedGoal.dailyIU) > 100
    }
}
