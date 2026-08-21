import Foundation
import Testing
@testable import VitamineD

struct UVEngineTests {

    private func profile(skin: SkinType = .iii,
                         age: Int = 30,
                         tan: TanLevel = .none,
                         exposedFraction preset: ClothingPreset = .tShirtShorts,
                         spf: Int = 1,
                         goal: Double = 1000) -> UserProfile {
        var profile = UserProfile.default
        profile.skinType = skin
        profile.age = age
        profile.tanLevel = tan
        profile.exposure = BodyExposure(preset: preset, sunscreenSPF: spf)
        profile.dailyGoalIU = goal
        return profile
    }

    // MARK: - Efficacité spectrale

    @Test("La synthèse est nulle sous le seuil de hauteur")
    func noSynthesisWhenSunIsLow() {
        #expect(UVEngine.vitaminDEfficiency(solarElevation: 5) == 0)
        #expect(UVEngine.vitaminDEfficiency(solarElevation: 10) == 0)
        #expect(UVEngine.vitaminDEfficiency(solarElevation: -20) == 0)
    }

    @Test("L'efficacité croît avec la hauteur du Soleil et sature")
    func efficiencyIsMonotonic() {
        var previous = 0.0
        for elevation in stride(from: 11.0, through: 90.0, by: 1.0) {
            let value = UVEngine.vitaminDEfficiency(solarElevation: elevation)
            #expect(value >= previous - 1e-9)
            #expect(value <= 1.0)
            previous = value
        }
        #expect(UVEngine.vitaminDEfficiency(solarElevation: 65) == 1.0)
        #expect(UVEngine.vitaminDEfficiency(solarElevation: 90) == 1.0)
    }

    @Test("La règle de l'ombre correspond à une efficacité déjà élevée")
    func shadowRuleEfficiency() {
        let value = UVEngine.vitaminDEfficiency(
            solarElevation: UVEngine.optimalSynthesisElevation)
        #expect(value > 0.7 && value < 0.85)
    }

    // MARK: - Étalonnage

    @Test("Règle de Holick : un quart de DEM sur un quart du corps")
    func holicksRuleCalibration() {
        // La règle dit 1 000 UI, mais elle a été établie sous une lampe
        // fluorescente et l'appliquer au Soleil la fait surestimer d'environ un
        // tiers (Fioletov et coll. 2010). La cible honnête est donc quelque
        // 750 UI, et le modèle doit tomber sous la règle brute sans s'en
        // éloigner absurdement.
        //
        // Le reste du corps est habillé de tissu dense : le repère a été mesuré
        // sur une surface irradiée et une autre à l'abri, pas sur un cobaye en
        // t-shirt.
        var subject = profile(exposedFraction: .custom)
        subject.exposure.customRegions = [.face, .neck, .upperArms, .forearms, .hands]
        subject.exposure.fabric = .dense
        #expect(abs(subject.exposure.exposedBodyFraction - 0.25) < 0.05)

        let rates = UVEngine.rates(profile: subject, uvIndex: 7, solarElevation: 60)

        // Durée nécessaire pour consommer un quart de la DEM du phototype III.
        let quarterMED = subject.effectiveMED / 4
        let minutes = quarterMED / (rates.erythemalJoulesPerMinute)
        let produced = UVEngine.saturated(
            rawIU: rates.vitaminDIUPerMinute * minutes, profile: subject)

        #expect(produced > 500)
        #expect(produced < 1_000)
    }

    @Test("Temps de brûlure conforme aux repères des phototypes")
    func burnTimes() {
        // Sous un indice UV de 8, un phototype II non bronzé rougit en une
        // vingtaine de minutes ; un phototype VI met plusieurs fois plus.
        let light = UVEngine.rates(profile: profile(skin: .ii), uvIndex: 8, solarElevation: 60)
        let dark = UVEngine.rates(profile: profile(skin: .vi), uvIndex: 8, solarElevation: 60)

        let lightMinutes = 1 / light.medFractionPerMinute
        let darkMinutes = 1 / dark.medFractionPerMinute

        #expect(lightMinutes > 15 && lightMinutes < 30)
        #expect(darkMinutes > 60 && darkMinutes < 110)
        #expect(darkMinutes / lightMinutes > 3)
    }

    @Test("Un phototype foncé synthétise un peu moins, et brûle beaucoup plus tard")
    func darkSkinSynthesisIsSlightlySlower() {
        // Ce test affirmait un rapport de synthèse supérieur à trois entre les
        // phototypes II et VI. Il encodait l'intuition que Young et coll. 2020
        // ont démentie : le facteur mesuré est de 1,3 à 1,4. Un test qui répète
        // la constante qu'il devrait contrôler ne contrôle rien — celui-ci
        // aurait dû tomber quand la constante est devenue fausse, il tombait au
        // contraire quand elle est devenue juste.
        let light = UVEngine.rates(profile: profile(skin: .ii), uvIndex: 8, solarElevation: 60)
        let dark = UVEngine.rates(profile: profile(skin: .vi), uvIndex: 8, solarElevation: 60)

        #expect(dark.vitaminDIUPerMinute < light.vitaminDIUPerMinute)
        let synthesisRatio = light.vitaminDIUPerMinute / dark.vitaminDIUPerMinute
        #expect(synthesisRatio > 1.25 && synthesisRatio < 1.45)

        // L'écart considérable est de l'autre côté : à dose égale, la peau
        // foncée met quatre fois plus longtemps à rougir. C'est ce contraste,
        // et non le seul rapport de synthèse, que l'application doit refléter.
        let burnRatio = light.medFractionPerMinute / dark.medFractionPerMinute
        #expect(burnRatio > 3)
        #expect(burnRatio > synthesisRatio * 2)
    }

    @Test("La surface découverte agit proportionnellement sur la synthèse, pas sur la brûlure")
    func exposedAreaAffectsSynthesisOnly() {
        let covered = UVEngine.rates(profile: profile(exposedFraction: .longSleevesTrousers),
                                     uvIndex: 8, solarElevation: 60)
        let bare = UVEngine.rates(profile: profile(exposedFraction: .swimwear),
                                  uvIndex: 8, solarElevation: 60)

        #expect(bare.vitaminDIUPerMinute > covered.vitaminDIUPerMinute * 4)
        // La dose érythémale reçue par un centimètre carré de peau nue ne dépend
        // pas de la quantité de peau nue ailleurs.
        #expect(abs(bare.medFractionPerMinute - covered.medFractionPerMinute) < 1e-9)
    }

    @Test("L'acclimatation relève le seuil d'érythème sans changer la synthèse")
    func tanningRaisesThresholdOnly() {
        let pale = UVEngine.rates(profile: profile(tan: .none), uvIndex: 8, solarElevation: 60)
        let tanned = UVEngine.rates(profile: profile(tan: .wellTanned), uvIndex: 8, solarElevation: 60)

        #expect(tanned.medFractionPerMinute < pale.medFractionPerMinute)
        #expect(abs(tanned.vitaminDIUPerMinute - pale.vitaminDIUPerMinute) < 1e-9)
    }

    @Test("La crème solaire réduit les deux grandeurs à la fois")
    func sunscreenReducesBoth() {
        let bare = UVEngine.rates(profile: profile(spf: 1), uvIndex: 9, solarElevation: 60)
        let creamed = UVEngine.rates(profile: profile(spf: 30), uvIndex: 9, solarElevation: 60)

        #expect(creamed.medFractionPerMinute < bare.medFractionPerMinute)
        #expect(creamed.vitaminDIUPerMinute < bare.vitaminDIUPerMinute)

        // Sous-application prise en compte : la protection effective d'un IP 30
        // avoisine 5,5, pas 30.
        let ratio = bare.medFractionPerMinute / creamed.medFractionPerMinute
        #expect(ratio > 5 && ratio < 6)
    }

    @Test("Vieillir ne pénalise plus la synthèse avant un âge avancé")
    func ageOnlyPenalisesTheVeryOld() {
        // Borecka et coll. 2024 : chez des adultes valides, la concentration
        // cutanée en 7-déhydrocholestérol ne diffère pas entre jeunes et âgés,
        // ni la montée de vitamine D3 après exposition. La pénalité de 1 % par
        // an dès vingt ans, héritée d'une mesure de 1985 sur peau prélevée, ne
        // tient plus. Il en reste une décroissance lente aux très grands âges,
        // là où l'ancienne mesure gardait sa part de vérité.
        #expect(profile(age: 20).ageFactor == 1.0)
        #expect(profile(age: 45).ageFactor == 1.0)
        #expect(profile(age: 70).ageFactor == 1.0)
        #expect(profile(age: 85).ageFactor < 1.0)
        #expect(profile(age: 120).ageFactor >= 0.7)

        let middleAged = UVEngine.rates(profile: profile(age: 45), uvIndex: 8, solarElevation: 60)
        let veryOld = UVEngine.rates(profile: profile(age: 90), uvIndex: 8, solarElevation: 60)
        #expect(veryOld.vitaminDIUPerMinute < middleAged.vitaminDIUPerMinute)
        // Et l'âge ne touche toujours pas au risque de brûlure.
        #expect(abs(veryOld.medFractionPerMinute - middleAged.medFractionPerMinute) < 1e-9)
    }

    // MARK: - Mélanine

    @Test("La mélanine freine peu la synthèse et beaucoup l'érythème")
    func melaninBlocksErythemaFarMoreThanSynthesis() {
        // Young et coll. 2020, sur 102 volontaires exposés à la même dose
        // sub-érythémale : le facteur d'inhibition entre phototypes II et VI
        // vaut 1,3 à 1,4 seulement. L'application retenait auparavant un
        // rapport de quatre, l'intuition plutôt que la mesure.
        let ratio = SkinType.ii.vitaminDFactor / SkinType.vi.vitaminDFactor
        #expect(ratio > 1.25 && ratio < 1.45)

        // Tandis que du côté de la rougeur, l'écart reste considérable.
        let medRatio = SkinType.vi.medJoulesPerSquareMetre
            / SkinType.ii.medJoulesPerSquareMetre
        #expect(medRatio > 3)
        #expect(medRatio > ratio * 2)

        // L'ordre reste monotone : plus de mélanine, moins de synthèse.
        let factors = SkinType.allCases.map(\.vitaminDFactor)
        #expect(factors == factors.sorted(by: >))
    }

    @Test("Le rendement est meilleur quand le Soleil est haut")
    func efficiencyPeaksAtHighSun() {
        // À indice UV égal — cas artificiel mais éclairant — un Soleil haut
        // donne plus de vitamine D pour la même dose érythémale.
        let high = UVEngine.rates(profile: profile(), uvIndex: 5, solarElevation: 65)
        let low = UVEngine.rates(profile: profile(), uvIndex: 5, solarElevation: 25)
        #expect(high.efficiency > low.efficiency * 3)
    }

    // MARK: - Plafond de synthèse

    @Test("La synthèse sature au lieu de croître indéfiniment")
    func synthesisSaturates() {
        let subject = profile()
        let ceiling = UVEngine.synthesisCeiling(profile: subject)

        #expect(UVEngine.saturated(rawIU: 0, profile: subject) == 0)
        #expect(UVEngine.saturated(rawIU: ceiling * 10, profile: subject) < ceiling)
        #expect(UVEngine.saturated(rawIU: ceiling * 10, profile: subject) > ceiling * 0.99)

        // Aux faibles doses, la relation reste quasi linéaire.
        let small = UVEngine.saturated(rawIU: ceiling * 0.02, profile: subject)
        #expect(abs(small - ceiling * 0.02) / (ceiling * 0.02) < 0.02)
    }

    @Test("Le rendement marginal décroît vers zéro")
    func marginalYieldDecays() {
        let subject = profile()
        let ceiling = UVEngine.synthesisCeiling(profile: subject)
        #expect(UVEngine.marginalYield(rawIU: 0, profile: subject) == 1.0)
        #expect(UVEngine.marginalYield(rawIU: ceiling, profile: subject) < 0.4)
        #expect(UVEngine.marginalYield(rawIU: ceiling * 5, profile: subject) < 0.01)
    }

    @Test("Plus de peau découverte relève le plafond")
    func ceilingScalesWithExposedArea() {
        let covered = UVEngine.synthesisCeiling(profile: profile(exposedFraction: .longSleevesTrousers))
        let bare = UVEngine.synthesisCeiling(profile: profile(exposedFraction: .swimwear))
        #expect(bare > covered * 4)
    }

    // MARK: - Modèle d'indice UV

    @Test("L'indice UV modélisé reste dans des bornes plausibles")
    func modelledUVIsPlausible() {
        // Montréal, midi du solstice : hauteur 68°.
        let montreal = UVEngine.modelledClearSkyUVIndex(
            solarElevation: 67.9, environment: .standard)
        #expect(montreal > 7 && montreal < 11)

        // Soleil au zénith, tropiques.
        let tropics = UVEngine.modelledClearSkyUVIndex(
            solarElevation: 90, environment: .standard)
        #expect(tropics > 10 && tropics < 14)

        // Soleil couché.
        #expect(UVEngine.modelledClearSkyUVIndex(solarElevation: -5, environment: .standard) == 0)
    }

    @Test("Altitude et neige relèvent l'indice UV")
    func altitudeAndAlbedoIncreaseUV() {
        var mountain = EnvironmentFactors.standard
        mountain.altitude = 2000
        mountain.surfaceAlbedo = 0.7

        let sea = UVEngine.modelledClearSkyUVIndex(solarElevation: 50, environment: .standard)
        let alpine = UVEngine.modelledClearSkyUVIndex(solarElevation: 50, environment: mountain)
        #expect(alpine > sea * 1.3)
    }

    @Test("Une colonne d'ozone plus épaisse abaisse l'indice UV")
    func ozoneReducesUV() {
        var thin = EnvironmentFactors.standard
        thin.totalOzone = 250
        var thick = EnvironmentFactors.standard
        thick.totalOzone = 400

        #expect(UVEngine.modelledClearSkyUVIndex(solarElevation: 50, environment: thin)
                > UVEngine.modelledClearSkyUVIndex(solarElevation: 50, environment: thick))
    }

    @Test("Les nuages atténuent moins les UV que la lumière visible")
    func cloudTransmission() {
        #expect(UVEngine.cloudTransmission(cloudCoverFraction: 0) == 1.0)
        // Ciel entièrement couvert : il reste encore le quart du rayonnement.
        let overcast = UVEngine.cloudTransmission(cloudCoverFraction: 1)
        #expect(abs(overcast - 0.25) < 0.01)
        // À moitié couvert, la perte reste faible — d'où les brûlures « par temps gris ».
        #expect(UVEngine.cloudTransmission(cloudCoverFraction: 0.5) > 0.9)
    }

    // MARK: - Surfaces corporelles

    @Test("Les fractions de surface corporelle sont normalisées")
    func bodyFractionsAreNormalised() {
        let everything = Set(BodyRegion.allCases)
        #expect(abs(BodyExposure.normalisedFraction(for: everything) - 1.0) < 1e-9)
        #expect(BodyExposure.normalisedFraction(for: []) == 0)
    }

    @Test("Les tenues sont ordonnées de la plus couvrante à la plus découverte")
    func clothingPresetsAreOrdered() throws {
        let order: [ClothingPreset] = [.coat, .longSleevesTrousers, .tShirtTrousers,
                                       .tShirtShorts, .tankTopShorts, .swimwear]
        let fractions = order.map { BodyExposure(preset: $0).exposedBodyFraction }
        #expect(fractions == fractions.sorted())
        #expect(try #require(fractions.last) > 0.7)
        #expect(try #require(fractions.first) < 0.05)
    }

    @Test("Le chapeau retire le visage du compte")
    func hatRemovesFace() {
        let bareHead = BodyExposure(preset: .tShirtShorts, wearsHat: false)
        let hatted = BodyExposure(preset: .tShirtShorts, wearsHat: true)
        #expect(hatted.exposedBodyFraction < bareHead.exposedBodyFraction)
        #expect(!hatted.exposedRegions.contains(.face))
    }

    // MARK: - Étoffe

    @Test("L'étoffe se classe du plus opaque au plus transparent")
    func fabricsAreOrdered() {
        let order: [Fabric] = [.dense, .standard, .light, .sheer]
        let values = order.map(\.transmission)
        #expect(values == values.sorted())
        #expect(values.allSatisfy { $0 > 0 && $0 < 1 })
        // Un jean atteint UPF 50, le t-shirt blanc d'été reste dans les 3 à 7
        // mesurés sur des vêtements réels, un voile tombe sous 4.
        #expect(Fabric.dense.upf >= 50)
        #expect(Fabric.light.upf >= 3 && Fabric.light.upf <= 7)
        #expect(Fabric.sheer.upf < 4)
    }

    @Test("Une étoffe fine laisse produire davantage, sans avancer la rougeur")
    func fabricRaisesSynthesisButNotTheBurn() {
        // Le point que l'écran doit rendre : sous des manches longues, changer
        // de tissu déplace la vitamine D de plus du double, alors que l'heure du
        // coup de soleil ne bouge pas d'une minute — elle se joue sur le visage
        // et les mains, que rien ne recouvre.
        var dense = profile(exposedFraction: .longSleevesTrousers)
        dense.exposure.fabric = .dense
        var sheer = profile(exposedFraction: .longSleevesTrousers)
        sheer.exposure.fabric = .sheer

        let denseRates = UVEngine.rates(profile: dense, uvIndex: 8, solarElevation: 60)
        let sheerRates = UVEngine.rates(profile: sheer, uvIndex: 8, solarElevation: 60)

        #expect(sheerRates.vitaminDIUPerMinute > denseRates.vitaminDIUPerMinute * 2)
        #expect(sheerRates.medFractionPerMinute == denseRates.medFractionPerMinute)
        #expect(sheerRates.erythemalJoulesPerMinute == denseRates.erythemalJoulesPerMinute)

        // Le plafond suit la même surface équivalente : le rapport entre les
        // deux ne dépend donc pas de l'étoffe, exactement comme il ne dépend
        // pas de la tenue.
        let denseRatio = denseRates.vitaminDIUPerMinute / UVEngine.synthesisCeiling(profile: dense)
        let sheerRatio = sheerRates.vitaminDIUPerMinute / UVEngine.synthesisCeiling(profile: sheer)
        #expect(abs(denseRatio - sheerRatio) < 1e-9)
    }

    @Test("La crème solaire ne s'applique qu'à la peau nue")
    func sunscreenOnlyCoversBareSkin() {
        // Personne n'étale de crème sous ses vêtements : la peau couverte
        // continue de recevoir ce que l'étoffe laisse passer, crème ou non.
        var bare = profile(exposedFraction: .longSleevesTrousers)
        bare.exposure.fabric = .standard
        var creamed = bare
        creamed.exposure.sunscreenSPF = 50

        let bareRates = UVEngine.rates(profile: bare, uvIndex: 9, solarElevation: 60)
        let creamedRates = UVEngine.rates(profile: creamed, uvIndex: 9, solarElevation: 60)

        #expect(creamedRates.vitaminDIUPerMinute < bareRates.vitaminDIUPerMinute)
        #expect(creamedRates.medFractionPerMinute < bareRates.medFractionPerMinute)

        // La part passant par l'étoffe subsiste : la crème ne peut pas tout
        // couper, même à IP 50 sur un dixième de corps découvert.
        let throughFabric = (1 - bare.exposure.exposedBodyFraction)
            * Fabric.standard.transmission
        #expect(creamedRates.vitaminDIUPerMinute
                > bareRates.vitaminDIUPerMinute
                * throughFabric / bare.exposure.effectiveExposedFraction * 0.99)
    }

    @Test("La posture n'agit que sur la synthèse")
    func postureLeavesErythemaAlone() {
        let standing = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60)
        let lying = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60,
                                   postureFactor: 0.5)

        #expect(abs(lying.vitaminDIUPerMinute - standing.vitaminDIUPerMinute / 2) < 0.001)

        // Mais l'éclairement reçu par la peau qui est au Soleil ne change pas :
        // c'est une puissance par unité de surface, et elle ne se divise pas
        // parce qu'il y a moins de surface.
        #expect(lying.medFractionPerMinute == standing.medFractionPerMinute)
        #expect(lying.erythemalJoulesPerMinute == standing.erythemalJoulesPerMinute)
    }

    @Test("Une correction de posture absurde est ramenée dans les bornes")
    func postureFactorIsClamped() {
        let normal = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60)
        let tooMuch = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60,
                                     postureFactor: 12)
        let negative = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60,
                                      postureFactor: -1)
        #expect(abs(tooMuch.vitaminDIUPerMinute - 3 * normal.vitaminDIUPerMinute) < 0.001)
        #expect(negative.vitaminDIUPerMinute == 0)
    }

    // MARK: - Géométrie de la posture

    @Test("Un corps debout ne présente au Soleil qu'une fraction de sa peau")
    func standingBodyNeverCatchesEverything() {
        // Le point que l'utilisateur a relevé : aucune posture n'expose la peau
        // entière, il y faudrait des miroirs. Un corps debout capte bien un
        // Soleil de flanc et mal un Soleil qui lui tombe sur la tête.
        for elevation in stride(from: 10.0, through: 89.0, by: 1.0) {
            let ratio = UVEngine.standingIrradianceRatio(solarElevation: elevation)
            #expect(ratio > 0 && ratio < 1)
        }
        #expect(UVEngine.standingIrradianceRatio(solarElevation: 15)
                > UVEngine.standingIrradianceRatio(solarElevation: 75))
        #expect(UVEngine.standingIrradianceRatio(solarElevation: 0) == 0)
    }

    @Test("Se coucher ne paie qu'à Soleil haut, et bascule à la règle de l'ombre")
    func lyingDownOnlyPaysWhenTheSunIsHigh() throws {
        // La correction n'est pas d'une moitié : elle vaut moins que 1 quand le
        // Soleil est bas, plus que 1 quand il est haut. Le point de bascule
        // tombe sur la règle de l'ombre — retrouvée ici par une voie purement
        // géométrique, sans qu'aucune constante ne l'y force.
        #expect(UVEngine.postureFactor(lyingDown: true, solarElevation: 20) < 0.8)
        #expect(UVEngine.postureFactor(lyingDown: true, solarElevation: 70) > 1.3)

        var crossover: Double?
        for elevation in stride(from: 10.0, through: 89.0, by: 0.5)
        where UVEngine.postureFactor(lyingDown: true, solarElevation: elevation) >= 1 {
            crossover = elevation
            break
        }
        let found = try #require(crossover)
        #expect(abs(found - UVEngine.optimalSynthesisElevation) < 4)

        // Debout reste l'étalon, quelle que soit la hauteur du Soleil.
        #expect(UVEngine.postureFactor(lyingDown: false, solarElevation: 20) == 1)
        #expect(UVEngine.postureFactor(lyingDown: false, solarElevation: 70) == 1)
    }

    @Test("La correction de posture croît continûment avec la hauteur du Soleil")
    func postureFactorIsMonotonic() {
        var previous = 0.0
        for elevation in stride(from: 10.0, through: 89.0, by: 1.0) {
            let value = UVEngine.postureFactor(lyingDown: true, solarElevation: elevation)
            #expect(value >= previous - 1e-9)
            #expect(value > 0 && value <= 3)
            previous = value
        }
    }
}
