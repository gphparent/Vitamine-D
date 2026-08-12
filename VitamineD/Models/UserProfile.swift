import Foundation

/// Profil de l'utilisateur : tout ce qui, du côté de la personne, module la
/// synthèse de vitamine D et le risque d'érythème.
struct UserProfile: Codable, Equatable, Sendable {
    var skinType: SkinType
    var age: Int
    var tanLevel: TanLevel
    var exposure: BodyExposure

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

    static let `default` = UserProfile(
        skinType: .iii,
        age: 35,
        tanLevel: .none,
        exposure: BodyExposure(),
        dailyGoalIU: 1000,
        burnAlertFraction: 0.6,
        notifyWindowOpening: true,
        notifyDailyPlan: true,
        dailyPlanMinuteOfDay: 8 * 60
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
}
