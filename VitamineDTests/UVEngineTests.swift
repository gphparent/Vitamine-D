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

    @Test("Repère clinique : environ 1 000 UI en une douzaine de minutes")
    func clinicalCalibration() {
        // Phototype III, 25 % de peau découverte, indice UV 7, Soleil haut.
        var subject = profile(exposedFraction: .custom)
        subject.exposure.customRegions = [.face, .neck, .upperArms, .forearms, .hands]
        let fraction = subject.exposure.exposedBodyFraction
        #expect(abs(fraction - 0.25) < 0.05)

        let rates = UVEngine.rates(profile: subject, uvIndex: 7, solarElevation: 60)
        let minutesTo1000 = 1000 / rates.vitaminDIUPerMinute
        #expect(minutesTo1000 > 8 && minutesTo1000 < 18)
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

    @Test("Un phototype foncé synthétise moins pour la même dose")
    func darkSkinSynthesisIsSlower() {
        let light = UVEngine.rates(profile: profile(skin: .ii), uvIndex: 8, solarElevation: 60)
        let dark = UVEngine.rates(profile: profile(skin: .vi), uvIndex: 8, solarElevation: 60)
        #expect(dark.vitaminDIUPerMinute < light.vitaminDIUPerMinute)
        #expect(light.vitaminDIUPerMinute / dark.vitaminDIUPerMinute > 3)
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

    @Test("L'âge réduit la synthèse sans toucher au risque de brûlure")
    func ageAffectsSynthesisOnly() {
        let young = UVEngine.rates(profile: profile(age: 20), uvIndex: 8, solarElevation: 60)
        let old = UVEngine.rates(profile: profile(age: 70), uvIndex: 8, solarElevation: 60)

        #expect(old.vitaminDIUPerMinute < young.vitaminDIUPerMinute)
        #expect(abs(old.medFractionPerMinute - young.medFractionPerMinute) < 1e-9)
        #expect(abs(profile(age: 70).ageFactor - 0.5) < 0.01)
        #expect(profile(age: 15).ageFactor == 1.0)
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
        // Un jean dépasse UPF 50, un voile tombe sous 4.
        #expect(Fabric.dense.upf > 50)
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

    @Test("La part éclairée n'agit que sur la synthèse")
    func illuminatedShareLeavesErythemaAlone() {
        let whole = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60)
        let half = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60,
                                  illuminatedShare: 0.5)

        // Moitié de peau tournée vers le Soleil, moitié de vitamine D.
        #expect(abs(half.vitaminDIUPerMinute - whole.vitaminDIUPerMinute / 2) < 0.001)

        // Mais l'éclairement reçu par la peau qui est au Soleil ne change pas :
        // c'est une puissance par unité de surface, et elle ne se divise pas
        // parce qu'il y a moins de surface.
        #expect(half.medFractionPerMinute == whole.medFractionPerMinute)
        #expect(half.erythemalJoulesPerMinute == whole.erythemalJoulesPerMinute)
    }

    @Test("Une part éclairée absurde est ramenée dans les bornes")
    func illuminatedShareIsClamped() {
        let normal = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60)
        let tooMuch = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60,
                                     illuminatedShare: 4)
        let negative = UVEngine.rates(profile: .default, uvIndex: 8, solarElevation: 60,
                                      illuminatedShare: -1)
        #expect(tooMuch.vitaminDIUPerMinute == normal.vitaminDIUPerMinute)
        #expect(negative.vitaminDIUPerMinute == 0)
    }
}
