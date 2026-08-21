import Foundation

/// Ce que l'atmosphère laisse passer, longueur d'onde par longueur d'onde.
///
/// ## Pourquoi un second calcul, et en quoi il ne double pas le premier
///
/// ``UVEngine`` estime une **dose** : combien d'unités internationales par
/// minute pour une peau donnée. Il le fait à partir de l'indice UV large bande,
/// multiplié par une table de rendement — approximation dont le commentaire de
/// cette table dit franchement les limites.
///
/// Ce fichier-ci ne calcule aucune dose. Il calcule une **transmission**, bande
/// par bande, en intégrant sur la longueur d'onde. Il ne sert qu'à montrer le
/// mécanisme : pourquoi les UVB disparaissent quand le Soleil descend alors que
/// les UVA restent. Aucune décision, aucune durée d'exposition n'en dépend.
///
/// La séparation est délibérée. Brancher ce calcul sur le moteur de dose
/// demanderait de réétalonner la constante de synthèse, qui est calée sur un
/// repère clinique et non sur un spectre. Ce serait un autre travail, et il vaut
/// mieux deux calculs dont on dit lequel sert à quoi que deux calculs qu'on
/// croit interchangeables.
///
/// ## Ce que le calcul comprend
///
/// L'absorption par l'ozone, suivant Beer-Lambert sur le trajet oblique : c'est
/// elle qui fait toute la différence entre les deux bandes, puisque sa section
/// efficace varie d'un facteur mille entre 300 et 350 nm quand la diffusion de
/// Rayleigh, elle, ne varie que d'un facteur deux.
///
/// La diffusion de Rayleigh est traitée à part, et sans la compter comme une
/// perte : un photon diffusé n'est pas absorbé, il change de direction, et une
/// bonne moitié finit tout de même au sol. C'est pourquoi on bronze à l'ombre.
/// L'approximation retenue — la moyenne entre le faisceau direct survivant et
/// l'unité — est grossière mais va dans le bon sens ; l'ignorer aurait annoncé
/// un effondrement des UVB dix fois trop brutal.
///
/// ## Contrôle contre le réel
///
/// Deux repères indépendants du modèle. Au sol et Soleil haut, il donne un
/// rapport UVA sur UVB de 28 à 32 ; les mesures publiées se tiennent entre 20
/// et 30. Et l'indice UV érythémal qu'il en déduit atteint 12 au zénith sous
/// 300 unités Dobson, contre 12,5 pour la paramétrisation de Fioletov que le
/// moteur utilise par ailleurs. Deux voies séparées qui tombent au même endroit.
enum AtmosphericSpectrum {

    // MARK: - Constantes de milieu

    /// Molécules par centimètre carré dans une unité Dobson.
    static let moleculesPerDobson = 2.687e16

    /// Colonne d'ozone de référence, en unités Dobson.
    static let referenceOzone = 300.0

    /// Frontière conventionnelle entre UVB et UVA, en nanomètres.
    static let uvbUpperBound = 315.0

    // MARK: - Section efficace de l'ozone

    /// Section efficace d'absorption de l'ozone, en cm² par molécule, vers 295 K.
    ///
    /// **Niveau 2, avec une réserve.** La bande de Huggins est tabulée depuis
    /// Bass & Paur (1985) et Molina & Molina (1986), qui s'accordent à quelques
    /// pour cent entre 310 et 340 nm. La table ci-dessous est une version
    /// lissée de ces valeurs, ancrée sur le seul point que j'aie pu vérifier
    /// directement : σ(325,126 nm) = 1,647·10⁻²⁰ cm², la référence
    /// photométrique du BIPM.
    ///
    /// Deux choses qu'elle ne rend pas. Le spectre réel porte une structure
    /// vibrationnelle marquée, que le lissage efface. Et la section efficace
    /// décroît quand la température baisse, ce qui compte pour une couche
    /// d'ozone stratosphérique à 220 K plutôt qu'à 295 K.
    private static let ozoneCrossSections: [(nanometres: Double, sigma: Double)] = [
        (290, 1.35e-18), (295, 6.50e-19), (300, 3.40e-19), (305, 1.70e-19),
        (310, 9.50e-20), (315, 5.50e-20), (320, 3.00e-20), (325, 1.647e-20),
        (330, 8.50e-21), (335, 4.50e-21), (340, 2.40e-21), (345, 1.20e-21),
        (350, 6.00e-22), (360, 1.50e-22), (370, 4.00e-23), (400, 1.00e-23)
    ]

    /// Interpolation logarithmique : la section efficace chute de trois ordres
    /// de grandeur sur cinquante nanomètres, une interpolation linéaire y serait
    /// absurde.
    static func ozoneCrossSection(nanometres lambda: Double) -> Double {
        guard let first = ozoneCrossSections.first,
              let last = ozoneCrossSections.last else { return 0 }
        if lambda <= first.nanometres { return first.sigma }
        if lambda >= last.nanometres { return last.sigma }

        for index in 1..<ozoneCrossSections.count {
            let upper = ozoneCrossSections[index]
            guard lambda <= upper.nanometres else { continue }
            let lower = ozoneCrossSections[index - 1]
            let span = upper.nanometres - lower.nanometres
            let t = span > 0 ? (lambda - lower.nanometres) / span : 0
            let logSigma = log10(lower.sigma) * (1 - t) + log10(upper.sigma) * t
            return pow(10, logSigma)
        }
        return last.sigma
    }

    // MARK: - Diffusion moléculaire

    /// Épaisseur optique de Rayleigh à l'incidence verticale.
    ///
    /// **Niveau 1.** Forme de Hansen & Travis (1974), qui suit la dépendance en
    /// λ⁻⁴ de Rayleigh avec ses termes correctifs. C'est cette dépendance qui
    /// fait le ciel bleu, et qui explique qu'une part notable des UVB atteigne
    /// le sol sans jamais venir en ligne droite du Soleil.
    static func rayleighOpticalDepth(nanometres lambda: Double) -> Double {
        let micron = lambda / 1000
        let inverseFourth = pow(micron, -4)
        return 0.008569 * inverseFourth
            * (1 + 0.0113 * pow(micron, -2) + 0.00013 * inverseFourth)
    }

    // MARK: - Spectres

    /// Irradiance solaire hors atmosphère, en W/m²/nm.
    ///
    /// **Niveau 3.** Valeurs approchées d'un spectre de référence, échantillonnées
    /// tous les dix nanomètres et interpolées linéairement. La forme suffit
    /// largement ici : le résultat n'est présenté qu'en pourcentage d'une
    /// référence calculée avec le même spectre, si bien qu'une erreur d'échelle
    /// s'annule des deux côtés.
    private static let solarIrradiance: [(nanometres: Double, watts: Double)] = [
        (290, 0.55), (300, 0.51), (310, 0.68), (320, 0.78), (330, 1.05),
        (340, 1.05), (350, 1.00), (360, 1.05), (370, 1.15), (380, 1.12),
        (390, 1.05), (400, 1.50)
    ]

    static func extraterrestrialIrradiance(nanometres lambda: Double) -> Double {
        guard let first = solarIrradiance.first,
              let last = solarIrradiance.last else { return 0 }
        if lambda <= first.nanometres { return first.watts }
        if lambda >= last.nanometres { return last.watts }

        for index in 1..<solarIrradiance.count {
            let upper = solarIrradiance[index]
            guard lambda <= upper.nanometres else { continue }
            let lower = solarIrradiance[index - 1]
            let span = upper.nanometres - lower.nanometres
            let t = span > 0 ? (lambda - lower.nanometres) / span : 0
            return lower.watts * (1 - t) + upper.watts * t
        }
        return last.watts
    }

    /// Spectre d'action de la production de prévitamine D3.
    ///
    /// **Niveau 3, approchant du niveau 2.** Approximation lisse de CIE
    /// 174:2006 : plateau jusqu'à 298 nm — le pic — puis décroissance
    /// logarithmique d'une décade tous les dix nanomètres et demi. Elle rend
    /// les valeurs publiées à quelques centièmes près sur la plage qui compte,
    /// et s'annule au-delà de 330 nm, où plus rien ne se produit.
    static func vitaminDAction(nanometres lambda: Double) -> Double {
        guard lambda >= 255, lambda <= 330 else { return 0 }
        guard lambda > 298 else { return 1 }
        return pow(10, -(lambda - 298) / 10.5)
    }

    /// Spectre d'action de l'érythème.
    ///
    /// **Niveau 1.** Définition CIE 1987, reprise telle quelle par l'ISO 17166 :
    /// unité jusqu'à 298 nm, deux segments logarithmiques ensuite. C'est ce
    /// spectre qui définit l'indice UV, et il n'y a rien à y ajuster.
    static func erythemalAction(nanometres lambda: Double) -> Double {
        guard lambda >= 250, lambda <= 400 else { return 0 }
        if lambda <= 298 { return 1 }
        if lambda <= 328 { return pow(10, 0.094 * (298 - lambda)) }
        return pow(10, 0.015 * (139 - lambda))
    }

    // MARK: - Ce qui arrive au sol

    /// Rayonnement parvenu au sol, par bande.
    ///
    /// Les trois premières grandeurs sont des irradiances relatives, sans unité
    /// physique utile : seules comptent leurs proportions et leur évolution.
    struct Arrival: Equatable, Sendable {
        /// Irradiance UVB, 280 à 315 nm.
        var uvb: Double
        /// Irradiance UVA, 315 à 400 nm.
        var uva: Double
        /// Irradiance pondérée par le spectre d'action de la vitamine D.
        var vitaminD: Double
        /// Irradiance pondérée par le spectre d'action de l'érythème.
        var erythemal: Double

        static let zero = Arrival(uvb: 0, uva: 0, vitaminD: 0, erythemal: 0)

        /// Combien d'UVA pour un UVB. Vaut une trentaine sous un Soleil haut,
        /// et plusieurs centaines quand il rase l'horizon — c'est le seul
        /// chiffre à retenir de tout ce fichier.
        var uvaPerUVB: Double? {
            guard uvb > 1e-9 else { return nil }
            return uva / uvb
        }

        /// Indice UV correspondant, au sens de la définition CIE.
        var uvIndex: Double { erythemal / UVEngine.wattsPerUVIndexPoint }
    }

    /// Masse d'air relative traversée par le rayonnement.
    ///
    /// Formule de Kasten & Young (1989), la même que celle du calculateur
    /// solaire : à l'horizon, un simple 1/sin(h) divergerait.
    static func airMass(solarElevation: Double) -> Double? {
        guard solarElevation > 0 else { return nil }
        let denominator = sin(solarElevation * .pi / 180)
            + 0.50572 * pow(solarElevation + 6.07995, -1.6364)
        guard denominator > 0 else { return nil }
        return 1 / denominator
    }

    /// Intègre le spectre reçu au sol, nanomètre par nanomètre.
    static func arrival(solarElevation: Double,
                        ozoneDobson: Double = referenceOzone) -> Arrival {
        guard solarElevation > 0, let mass = airMass(solarElevation: solarElevation) else {
            return .zero
        }
        let column = max(1, ozoneDobson) * moleculesPerDobson
        // Le rayonnement est reçu sur une surface horizontale : l'inclinaison
        // du faisceau compte autant que ce que l'atmosphère en laisse.
        let projection = sin(solarElevation * .pi / 180)

        var result = Arrival.zero
        for step in 280..<400 {
            let lambda = Double(step) + 0.5

            let absorbed = exp(-ozoneCrossSection(nanometres: lambda) * column * mass)
            // La diffusion n'est pas une perte sèche : ce qui est dévié
            // redescend pour bonne part. On retient la moyenne entre le
            // faisceau direct survivant et la totalité.
            let scattered = (1 + exp(-rayleighOpticalDepth(nanometres: lambda) * mass)) / 2

            let energy = extraterrestrialIrradiance(nanometres: lambda)
                * absorbed * scattered * projection

            if lambda < uvbUpperBound {
                result.uvb += energy
            } else {
                result.uva += energy
            }
            result.vitaminD += energy * vitaminDAction(nanometres: lambda)
            result.erythemal += energy * erythemalAction(nanometres: lambda)
        }
        return result
    }

    /// Référence : le Soleil au zénith, colonne d'ozone standard.
    ///
    /// Sert à exprimer tout le reste en pourcentage. Un maximum absolu, jamais
    /// atteint hors des tropiques.
    static let zenithReference = arrival(solarElevation: 90)

    /// Part de chaque bande encore présente, rapportée au Soleil au zénith.
    ///
    /// C'est la grandeur que l'écran affiche, et elle porte à elle seule tout
    /// le propos : à 10° de hauteur il reste 11 % des UVA et 0,6 % des UVB ; à
    /// 30°, 41 % et 19 % ; à 60°, 84 % et 73 %. Les deux bandes ne se vident
    /// pas du tout au même rythme, et c'est pourquoi une fin d'après-midi
    /// lumineuse et chaude ne produit plus rien.
    static func relativeToZenith(solarElevation: Double,
                                 ozoneDobson: Double = referenceOzone) -> Arrival {
        let here = arrival(solarElevation: solarElevation, ozoneDobson: ozoneDobson)
        let top = zenithReference
        return Arrival(
            uvb: top.uvb > 0 ? here.uvb / top.uvb : 0,
            uva: top.uva > 0 ? here.uva / top.uva : 0,
            vitaminD: top.vitaminD > 0 ? here.vitaminD / top.vitaminD : 0,
            erythemal: top.erythemal > 0 ? here.erythemal / top.erythemal : 0)
    }
}
