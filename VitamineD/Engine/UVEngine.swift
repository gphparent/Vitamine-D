import Foundation

/// Conditions UV et météorologiques à un instant donné.
struct UVConditions: Codable, Equatable, Sendable {
    let date: Date
    /// Indice UV réel, nuages compris.
    let uvIndex: Double
    /// Indice UV qu'on aurait par ciel parfaitement dégagé.
    let uvIndexClearSky: Double
    /// Couverture nuageuse, de 0 à 1.
    let cloudCover: Double
    let temperature: Double
    let apparentTemperature: Double
    /// Probabilité de précipitations, de 0 à 1.
    let precipitationProbability: Double
    let windSpeed: Double
    /// Code météo WMO, tel que fourni par Open-Meteo.
    let weatherCode: Int

    /// Part du rayonnement UV que les nuages laissent passer.
    var cloudTransmission: Double {
        guard uvIndexClearSky > 0.05 else { return 1 }
        return min(1, uvIndex / uvIndexClearSky)
    }
}

/// Débits de dose instantanés, pour un profil et des conditions donnés.
struct DoseRates: Equatable, Sendable {
    /// Unités internationales de vitamine D synthétisées par minute, avant
    /// application du plafond de photo-équilibre.
    let vitaminDIUPerMinute: Double
    /// Dose érythémale reçue par minute, en J/m² pondérés érythème.
    let erythemalJoulesPerMinute: Double
    /// Part de la DEM accumulée par minute, de 0 à 1.
    let medFractionPerMinute: Double

    static let zero = DoseRates(vitaminDIUPerMinute: 0,
                                erythemalJoulesPerMinute: 0,
                                medFractionPerMinute: 0)

    /// Rendement de la fenêtre : UI de vitamine D obtenues par pourcent de DEM
    /// consommé. Plus ce rapport est élevé, plus l'exposition est « rentable ».
    ///
    /// Il croît avec la hauteur du Soleil : c'est la raison contre-intuitive
    /// pour laquelle le milieu de journée est le moment le *moins* risqué pour
    /// faire sa vitamine D, à condition d'y rester peu de temps.
    var efficiency: Double {
        guard medFractionPerMinute > 0 else { return 0 }
        return vitaminDIUPerMinute / (medFractionPerMinute * 100)
    }
}

/// Paramètres d'environnement qui modulent le rayonnement UVB reçu au sol.
struct EnvironmentFactors: Codable, Equatable, Sendable {
    /// Altitude du lieu, en mètres.
    var altitude: Double
    /// Colonne totale d'ozone, en unités Dobson.
    var totalOzone: Double
    /// Albédo du sol : 0,03 pour l'herbe, jusqu'à 0,85 pour la neige fraîche.
    var surfaceAlbedo: Double
    /// Fraction du ciel visible depuis la position de l'utilisateur.
    /// En ville, entre immeubles, une bonne part du rayonnement diffus est
    /// masquée ; en terrain dégagé, la valeur est 1.
    var skyViewFactor: Double

    static let standard = EnvironmentFactors(altitude: 0,
                                             totalOzone: 300,
                                             surfaceAlbedo: 0.05,
                                             skyViewFactor: 1.0)
}

/// Moteur photobiologique : conversion du rayonnement UV en synthèse de
/// vitamine D d'une part, en risque d'érythème d'autre part.
///
/// ## Sur la validité du modèle
///
/// Les constantes viennent de la littérature photobiologique publiée, mais la
/// synthèse cutanée réelle varie d'un facteur deux ou trois entre individus de
/// même phototype. Les durées calculées ici sont des ordres de grandeur utiles,
/// pas des mesures. Aucune décision médicale ne devrait en dépendre.
enum UVEngine {

    // MARK: - Constantes photobiologiques

    /// Irradiance érythémale correspondant à un point d'indice UV, en W/m².
    /// Définition de la CIE : 1 UVI = 25 mW/m² pondérés érythème.
    static let wattsPerUVIndexPoint = 0.025

    /// Constante d'étalonnage de la synthèse cutanée, en
    /// UI · min⁻¹ · (point d'UVI)⁻¹ · (fraction de surface corporelle)⁻¹.
    ///
    /// Calée sur le repère clinique classique : un adulte de phototype III,
    /// 25 % de peau découverte, sous un indice UV de 7 et un Soleil haut,
    /// atteint environ 1 000 UI en une douzaine de minutes.
    static let synthesisConstant = 55.0

    /// Plafond de synthèse pour le corps entier, en UI.
    ///
    /// Au-delà d'une certaine dose, la prévitamine D3 se photo-isomérise en
    /// lumistérol et en tachystérol plutôt que de s'accumuler : prolonger
    /// l'exposition n'augmente plus le rendement, mais continue d'augmenter la
    /// dose érythémale. C'est le mécanisme qui rend impossible une intoxication
    /// à la vitamine D par le seul soleil.
    static let wholeBodySynthesisCeiling = 20_000.0

    // MARK: - Efficacité spectrale

    /// Rendement relatif de la bande UVB utile à la synthèse, en fonction de la
    /// hauteur du Soleil.
    ///
    /// Le spectre d'action de la vitamine D culmine vers 297 nm, plus court que
    /// celui de l'érythème. Comme l'absorption par l'ozone croît fortement vers
    /// les courtes longueurs d'onde, l'allongement du trajet atmosphérique
    /// quand le Soleil descend appauvrit le rayonnement en UVB bien plus vite
    /// qu'il ne réduit l'indice UV. En pratique, la synthèse s'éteint alors que
    /// l'indice UV reste mesurable : c'est l'« hiver vitaminique » des hautes
    /// latitudes, où le Soleil brille sans jamais monter assez haut.
    ///
    /// Table empirique normalisée sur les hauteurs supérieures à 65°.
    private static let efficiencyTable: [(elevation: Double, efficiency: Double)] = [
        (10, 0.00), (15, 0.05), (20, 0.12), (25, 0.24), (30, 0.38),
        (35, 0.52), (40, 0.66), (45, 0.78), (50, 0.87), (55, 0.93),
        (60, 0.97), (65, 1.00), (90, 1.00)
    ]

    /// Hauteur solaire en deçà de laquelle la synthèse est tenue pour nulle.
    static let minimumSynthesisElevation = 10.0

    /// Hauteur solaire maximale du jour en deçà de laquelle on parle d'« hiver
    /// vitaminique ».
    ///
    /// Correspond à un angle zénithal de 65°, seuil usuellement retenu comme
    /// celui où le flux UVB devient négligeable. C'est ce qui décrit la
    /// situation de Montréal ou de Boston de novembre à février : le Soleil
    /// brille, l'indice UV n'est pas nul, et pourtant la synthèse cutanée est
    /// pratiquement arrêtée.
    static let vitaminDWinterElevation = 25.0

    /// Hauteur solaire à partir de laquelle la synthèse devient efficace.
    /// Correspond à la règle de l'ombre : ombre plus courte que la personne.
    static let optimalSynthesisElevation = 45.0

    static func vitaminDEfficiency(solarElevation: Double) -> Double {
        guard solarElevation > minimumSynthesisElevation else { return 0 }
        guard solarElevation < 65 else { return 1 }
        for index in 1..<efficiencyTable.count {
            let upper = efficiencyTable[index]
            guard solarElevation <= upper.elevation else { continue }
            let lower = efficiencyTable[index - 1]
            let span = upper.elevation - lower.elevation
            let ratio = span > 0 ? (solarElevation - lower.elevation) / span : 0
            return lower.efficiency + ratio * (upper.efficiency - lower.efficiency)
        }
        return 1
    }

    // MARK: - Indice UV modélisé (repli hors ligne)

    /// Indice UV par ciel clair, estimé à partir de la seule géométrie solaire.
    ///
    /// Paramétrisation de Fioletov et coll. : UVI ≈ 12,5 · μ^2,42 · (Ω/300)^−1,23,
    /// où μ est le cosinus de l'angle zénithal et Ω la colonne d'ozone en unités
    /// Dobson. Sert de repli quand le réseau n'est pas joignable, et de garde-fou
    /// contre une valeur aberrante renvoyée par le service météo.
    static func modelledClearSkyUVIndex(solarElevation: Double,
                                        environment: EnvironmentFactors) -> Double {
        guard solarElevation > 0 else { return 0 }
        let mu = cos((90 - solarElevation) * .pi / 180)
        guard mu > 0 else { return 0 }

        var uvi = 12.5 * pow(mu, 2.42) * pow(environment.totalOzone / 300, -1.23)

        // Atténuation par les aérosols, valeur moyenne en air continental.
        uvi *= 0.92
        // L'air se raréfie avec l'altitude : environ +6 % d'UV par kilomètre.
        uvi *= 1 + 0.06 * (environment.altitude / 1000)
        // Le sol renvoie une partie du rayonnement vers l'observateur.
        uvi *= 1 + 0.5 * max(0, environment.surfaceAlbedo - 0.05)

        return max(0, uvi)
    }

    /// Transmission UV sous couverture nuageuse.
    ///
    /// Les nuages atténuent bien moins les UV que la lumière visible : sous un
    /// ciel entièrement couvert il reste couramment 30 à 40 % du rayonnement UV,
    /// alors que la sensation lumineuse s'effondre. D'où les coups de soleil
    /// « par temps gris ». Relation empirique de Josefsson & Landelius.
    static func cloudTransmission(cloudCoverFraction: Double) -> Double {
        let cf = min(1, max(0, cloudCoverFraction))
        return 1 - 0.75 * pow(cf, 3.4)
    }

    // MARK: - Débits de dose

    /// Débits instantanés de vitamine D et de dose érythémale.
    ///
    /// - Parameter illuminatedShare: part de la peau découverte réellement
    ///   tournée vers le Soleil. Vaut 1 debout, une demie couché. N'agit que
    ///   sur la synthèse : la dose érythémale se mesure par unité de peau
    ///   éclairée, et ne dépend donc pas de la quantité qui l'est.
    static func rates(profile: UserProfile,
                      uvIndex: Double,
                      solarElevation: Double,
                      environment: EnvironmentFactors = .standard,
                      illuminatedShare: Double = 1) -> DoseRates {
        guard uvIndex > 0, solarElevation > 0 else { return .zero }

        let exposure = profile.exposure
        let transmission = exposure.sunscreenTransmission * environment.skyViewFactor

        // Côté brûlure : la dose érythémale ne dépend pas de la surface exposée,
        // seulement de l'irradiance reçue par la peau la moins protégée.
        let erythemalPerMinute = uvIndex * wattsPerUVIndexPoint * 60 * transmission
        let medFraction = erythemalPerMinute / profile.effectiveMED

        // Côté synthèse : la surface compte directement, et deux filtres
        // différents s'appliquent à deux surfaces différentes. La crème solaire
        // ne couvre que la peau nue — personne n'en met sous ses vêtements — et
        // l'étoffe ne filtre que la peau couverte.
        let bare = exposure.exposedBodyFraction
        let effectiveArea = bare * exposure.sunscreenTransmission
            + (1 - bare) * exposure.fabric.transmission

        let efficiency = vitaminDEfficiency(solarElevation: solarElevation)
        let vitaminD = synthesisConstant
            * uvIndex
            * efficiency
            * effectiveArea
            * max(0, min(1, illuminatedShare))
            * profile.skinType.vitaminDFactor
            * profile.ageFactor
            * environment.skyViewFactor

        return DoseRates(vitaminDIUPerMinute: vitaminD,
                         erythemalJoulesPerMinute: erythemalPerMinute,
                         medFractionPerMinute: medFraction)
    }

    /// Plafond de synthèse pour ce profil, en UI.
    ///
    /// La surface retenue est la surface équivalente, étoffe comprise : la peau
    /// sous un vêtement fin finit elle aussi par atteindre son photo-équilibre,
    /// simplement plus tard. La crème solaire, elle, n'entre pas dans le
    /// plafond — elle ralentit la montée sans abaisser le palier.
    static func synthesisCeiling(profile: UserProfile) -> Double {
        max(1, wholeBodySynthesisCeiling
            * profile.exposure.effectiveExposedFraction
            * profile.skinType.vitaminDFactor
            * profile.ageFactor)
    }

    /// Applique le plafond de photo-équilibre à une dose brute cumulée.
    ///
    /// La saturation exponentielle reproduit le comportement observé : rendement
    /// quasi linéaire au début de l'exposition, puis aplatissement progressif.
    static func saturated(rawIU: Double, ceiling: Double) -> Double {
        let ceiling = max(1, ceiling)
        return ceiling * (1 - exp(-rawIU / ceiling))
    }

    static func saturated(rawIU: Double, profile: UserProfile) -> Double {
        saturated(rawIU: rawIU, ceiling: synthesisCeiling(profile: profile))
    }

    /// Part du rendement encore disponible à ce niveau de dose cumulée, de 0 à 1.
    static func marginalYield(rawIU: Double, ceiling: Double) -> Double {
        exp(-rawIU / max(1, ceiling))
    }

    static func marginalYield(rawIU: Double, profile: UserProfile) -> Double {
        marginalYield(rawIU: rawIU, ceiling: synthesisCeiling(profile: profile))
    }

    // MARK: - Exposition sur une peau déjà chargée

    /// Vitamine D produite par une dose brute supplémentaire, à partir d'un
    /// état de saturation déjà installé.
    ///
    /// La courbe de saturation ne repart pas de son origine à chaque sortie :
    /// on en prend la portion comprise entre la charge déjà présente et le
    /// nouveau total. D'où une production qui décroît à mesure que la peau se
    /// charge, alors que le capital cutané, lui, se dépense au même rythme.
    static func saturated(rawIU: Double, carried: Double, profile: UserProfile) -> Double {
        let start = max(0, carried)
        return saturated(rawIU: start + max(0, rawIU), profile: profile)
            - saturated(rawIU: start, profile: profile)
    }

    /// Ce que la peau peut encore produire avant d'atteindre le plafond, compte
    /// tenu de ce qu'elle porte déjà.
    static func remainingCapacity(carried: Double, profile: UserProfile) -> Double {
        let ceiling = synthesisCeiling(profile: profile)
        return ceiling * exp(-max(0, carried) / ceiling)
    }

    /// Dose brute **cumulée** — charge comprise — à laquelle `target` UI
    /// supplémentaires auront été produites.
    ///
    /// `nil` quand le plafond l'interdit : au-delà de la capacité restante,
    /// aucune durée d'exposition n'y suffit.
    static func cumulativeDose(toProduce target: Double,
                               carried: Double,
                               profile: UserProfile) -> Double? {
        guard target > 0 else { return max(0, carried) }
        let ceiling = synthesisCeiling(profile: profile)
        let start = max(0, carried)
        let remainder = exp(-start / ceiling) - target / ceiling
        guard remainder > 0 else { return nil }
        return -ceiling * log(remainder)
    }
}
