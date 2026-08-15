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
/// Les constantes de ce fichier ne se valent pas, et il serait malhonnête de
/// les présenter sur un même plan. Elles se rangent en trois niveaux, indiqués
/// individuellement plus bas.
///
/// 1. **Définitions et géométrie.** L'équivalence 1 point d'indice UV =
///    25 mW/m² pondérés érythème est une convention CIE, pas une mesure. Les
///    projections d'un cylindre et les facteurs de forme du ciel sont de la
///    géométrie. Rien n'y est ajustable.
/// 2. **Valeurs mesurées et publiées.** Les doses érythémales minimales par
///    phototype, l'effet de la mélanine sur la synthèse, la transmission des
///    étoffes, la paramétrisation de l'indice UV par ciel clair. Elles portent
///    ici le nom de leur source.
/// 3. **Ajustements et constructions propres à cette application.** La
///    constante d'étalonnage de la synthèse, la table de rendement selon la
///    hauteur solaire, la demi-vie de la charge photochimique. Elles sont
///    signalées comme telles, sans exception.
///
/// Il ne faut pas s'illusionner sur la précision d'ensemble. Même en supposant
/// chaque constante juste, la réponse individuelle à une exposition identique
/// varie d'un facteur deux ou trois entre personnes de même phototype — c'est
/// l'un des rares points sur lesquels toute la littérature s'accorde. Les
/// durées calculées ici sont des ordres de grandeur utiles, pas des mesures.
/// Aucune décision médicale ne devrait en dépendre.
enum UVEngine {

    // MARK: - Constantes photobiologiques

    /// Irradiance érythémale correspondant à un point d'indice UV, en W/m².
    ///
    /// **Niveau 1 : définition.** Convention CIE, 1 UVI = 25 mW/m² pondérés par
    /// le spectre d'action de l'érythème (CIE 1987). Rien à mesurer ni à
    /// ajuster ici.
    static let wattsPerUVIndexPoint = 0.025

    /// Constante d'étalonnage de la synthèse cutanée, en
    /// UI · min⁻¹ · (point d'UVI)⁻¹ · (fraction de surface corporelle)⁻¹.
    ///
    /// **Niveau 3 : ajustement propre à cette application.** Cette valeur ne
    /// vient d'aucune publication. Elle a été choisie pour que le modèle
    /// reproduise la règle de Holick — un quart de DEM sur un quart de la
    /// surface corporelle équivaut à 1 000 UI par voie orale. C'est donc **un
    /// seul nombre ajusté sur une seule règle de pouce qui porte toute
    /// l'échelle en unités internationales de l'application**.
    ///
    /// Et cette règle est elle-même contestée. Elle a été établie sous une
    /// lampe fluorescente, dont le spectre diffère sensiblement de celui du
    /// Soleil ; Fioletov et coll. (*J Steroid Biochem Mol Biol*, 2010) estiment
    /// que l'appliquer au rayonnement solaire fausse l'équivalence d'environ un
    /// tiers. Le modèle, tel qu'il est calé, rend 641 UI là où la règle brute en
    /// annonce 1 000 — soit quinze pour cent sous la règle corrigée. C'est une
    /// coïncidence rassurante, pas une validation.
    ///
    /// Si un chiffre de cette application devait se révéler faux d'un facteur
    /// deux, ce serait celui-ci.
    static let synthesisConstant = 55.0

    /// Plafond de synthèse pour le corps entier, en UI.
    ///
    /// Au-delà d'une certaine dose, la prévitamine D3 se photo-isomérise en
    /// lumistérol et en tachystérol plutôt que de s'accumuler : prolonger
    /// l'exposition n'augmente plus le rendement, mais continue d'augmenter la
    /// dose érythémale. C'est le mécanisme qui rend impossible une intoxication
    /// à la vitamine D par le seul soleil.
    ///
    /// **Niveau 3.** Le mécanisme est solidement établi ; le chiffre l'est
    /// moins. La littérature situe la production d'une exposition du corps
    /// entier à une DEM entre 10 000 et 25 000 UI, une fourchette large. Les
    /// 20 000 UI retenus ici ne sont pas cette production mais l'asymptote de
    /// photo-équilibre, que la courbe approche sans jamais l'atteindre : le
    /// modèle rend 8 270 UI à une DEM du corps entier, soit un peu sous le bas de
    /// la fourchette publiée. L'erreur va donc dans le sens prudent.
    static let wholeBodySynthesisCeiling = 20_000.0

    // MARK: - Efficacité spectrale

    /// Rendement relatif de la bande UVB utile à la synthèse, en fonction de la
    /// hauteur du Soleil.
    ///
    /// Le spectre d'action de la production de prévitamine D3 culmine à
    /// 298 ± 2 nm (CIE 174:2006), plus court que celui de l'érythème. Comme
    /// l'absorption par l'ozone croît fortement vers les courtes longueurs
    /// d'onde, l'allongement du trajet atmosphérique quand le Soleil descend
    /// appauvrit le rayonnement en UVB bien plus vite qu'il ne réduit l'indice
    /// UV. En pratique, la synthèse s'éteint alors que l'indice UV reste
    /// mesurable : c'est l'« hiver vitaminique » des hautes latitudes, où le
    /// Soleil brille sans jamais monter assez haut.
    ///
    /// **Niveau 3 : construction propre à cette application.** Une version
    /// antérieure de ce commentaire présentait la table comme « empirique et
    /// normalisée sur les hauteurs supérieures à 65° », ce qui laissait croire
    /// à une origine expérimentale. Elle n'en a pas. Je l'ai bâtie pour
    /// reproduire trois comportements qualitatifs connus : synthèse nulle sous
    /// 10° de hauteur, hiver vitaminique aux hauteurs faibles, plein rendement
    /// au-delà de 65°. Aucune donnée derrière chaque point.
    ///
    /// La manière correcte de faire ce calcul est d'intégrer le spectre
    /// d'action CIE 174:2006 contre un spectre d'irradiance modélisé par
    /// transfert radiatif, plutôt que de multiplier un indice UV large bande
    /// par un facteur scalaire. C'est l'approche de la littérature, et c'est le
    /// remplacement qui améliorerait le plus ce moteur.
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
    /// **Niveau 2, déduit d'une mesure.** Webb, Kline et Holick (*J Clin
    /// Endocrinol Metab*, 1988) ont exposé du 7-déhydrocholestérol au soleil
    /// d'hiver à Boston (42,2° N) et à Edmonton, sans obtenir de prévitamine D3
    /// de novembre à février, et concluaient à un hiver vitaminique à toute
    /// latitude supérieure à 34°. Ce critère de latitude se traduit
    /// directement : au solstice d'hiver, à 34° de latitude, le Soleil culmine
    /// à 32,6°. D'où le seuil retenu ici.
    ///
    /// Il valait auparavant 25°, ce qui reposait sur un angle zénithal de 65°
    /// cité de mémoire plutôt que déduit d'une mesure — et déclarait donc
    /// productives des journées où Webb et coll. n'ont rien détecté.
    ///
    /// Le seuil reste flou par nature. Webb dosait de la prévitamine D3 dans des
    /// ampoules, un essai plus sensible que la peau ; à l'inverse, la synthèse
    /// ne s'arrête pas net à une hauteur donnée, elle devient seulement trop
    /// faible pour compter sur une journée.
    static let vitaminDWinterElevation = 30.0

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

    // MARK: - Géométrie du corps

    /// Part directe du rayonnement UV érythémal reçu sur une surface
    /// horizontale, par ciel clair.
    ///
    /// Elle croît avec la hauteur du Soleil : le trajet atmosphérique se
    /// raccourcit, la diffusion de Rayleigh emporte une part moindre du
    /// faisceau. Aux hauteurs utiles à la vitamine D, elle va d'un tiers à
    /// six dixièmes. La distinction compte ici parce que le faisceau direct
    /// et le ciel diffus n'atteignent pas un corps de la même façon.
    ///
    /// **Niveau 3 : ajustement propre à cette application.** La forme
    /// 0,62·√sin(h) est de moi. Elle reproduit l'ordre de grandeur admis — la
    /// part directe du rayonnement érythémal par ciel clair passe d'environ un
    /// tiers à Soleil rasant à un peu plus de la moitié à Soleil haut — mais
    /// aucun jeu de mesures ne l'a produite.
    private static func directBeamFraction(solarElevation: Double) -> Double {
        let sine = sin(solarElevation * .pi / 180)
        guard sine > 0 else { return 0 }
        return min(0.7, 0.62 * sqrt(sine))
    }

    /// Éclairement moyen sur l'ensemble de la peau d'un corps **debout**,
    /// rapporté à l'éclairement horizontal que mesure l'indice UV.
    ///
    /// **Niveau 1 pour la géométrie, niveau 3 pour la part directe** qu'elle
    /// utilise. Le corps est traité comme un cylindre vertical. Pour le faisceau direct,
    /// l'aire projetée d'un cylindre vaut cos(h)/π de son aire totale ; rapportée
    /// à l'horizontale, qui reçoit sin(h), il reste cotan(h)/π. Pour le ciel
    /// diffus, un point d'une paroi verticale ne voit qu'une demi-voûte, d'où un
    /// facteur de forme de 0,5.
    ///
    /// Le résultat va de 0,7 à Soleil rasant à moins de 0,2 au zénith : un corps
    /// debout capte mal un Soleil qui lui tombe sur la tête, et bien un Soleil
    /// qui l'éclaire de flanc.
    static func standingIrradianceRatio(solarElevation: Double) -> Double {
        guard solarElevation > 0.5 else { return 0 }
        let radians = solarElevation * .pi / 180
        let direct = directBeamFraction(solarElevation: solarElevation)
        let beam = direct * (cos(radians) / (.pi * sin(radians)))
        let sky = (1 - direct) * 0.5
        return beam + sky
    }

    /// Même grandeur pour un corps couché.
    ///
    /// La moitié tournée vers le ciel reçoit l'éclairement horizontal complet,
    /// faisceau et diffus ensemble — c'est exactement ce que mesure l'indice UV.
    /// L'autre moitié ne reçoit rien. D'où une demie, corrigée d'un cinquième
    /// pour la courbure du corps et son propre ombrage : un dormeur n'est pas
    /// une plaque plane. La valeur ne dépend pas de la hauteur du Soleil, celle-ci
    /// étant déjà contenue dans l'indice UV horizontal.
    ///
    /// La correction de 0,80 est **de niveau 3** : je l'ai choisie. Elle place
    /// le résultat à 0,40, dans la fourchette de 0,4 à 0,5 couramment rapportée
    /// pour le rapport d'exposition d'un corps allongé — mais elle n'en est pas
    /// tirée.
    static let lyingIrradianceRatio = 0.5 * 0.80

    /// Correction de posture, rapportée à la position debout.
    ///
    /// ## Pourquoi ce n'est pas « une moitié »
    ///
    /// L'application divisait auparavant la synthèse par deux dès qu'on se
    /// couchait, au motif qu'une moitié du corps seulement voit le ciel. C'était
    /// compter la géométrie deux fois. La constante d'étalonnage est calée sur
    /// un repère clinique mesuré sur des gens **debout** : elle contient déjà,
    /// sans le dire, le fait qu'un corps debout ne présente jamais au Soleil que
    /// le tiers environ de sa peau. Aucune posture n'expose la peau entière —
    /// il y faudrait des miroirs.
    ///
    /// La bonne grandeur est donc le rapport d'une posture à l'autre, et il
    /// n'est pas d'une moitié : il vaut environ 0,6 quand le Soleil est bas,
    /// franchit 1 vers 45° de hauteur, et atteint 1,6 quand le Soleil est très
    /// haut. Se coucher ne paie qu'à partir du moment où l'ombre devient plus
    /// courte que soi — la règle que l'application enseigne déjà par ailleurs,
    /// retrouvée ici par une voie entièrement indépendante.
    static func postureFactor(lyingDown: Bool, solarElevation: Double) -> Double {
        guard lyingDown else { return 1 }
        let standing = standingIrradianceRatio(solarElevation: solarElevation)
        guard standing > 0.01 else { return 1 }
        return min(3, lyingIrradianceRatio / standing)
    }

    // MARK: - Débits de dose

    /// Débits instantanés de vitamine D et de dose érythémale.
    ///
    /// - Parameter postureFactor: correction géométrique de la posture,
    ///   rapportée à la position debout qui vaut 1 et sert d'étalonnage. Voir
    ///   ``postureFactor(lyingDown:solarElevation:)``.
    ///
    ///   N'agit que sur la synthèse. La dose érythémale se mesure par unité de
    ///   peau éclairée : le ventre d'un dormeur, horizontal, reçoit exactement
    ///   l'indice UV annoncé, et l'épaule d'un marcheur à peu près autant. La
    ///   posture change la récolte, pas la vitesse à laquelle rougit le morceau
    ///   de peau le plus exposé.
    static func rates(profile: UserProfile,
                      uvIndex: Double,
                      solarElevation: Double,
                      environment: EnvironmentFactors = .standard,
                      postureFactor: Double = 1) -> DoseRates {
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
            * max(0, min(3, postureFactor))
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
