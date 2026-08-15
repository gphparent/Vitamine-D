import Foundation
import Testing
@testable import VitamineD

struct PhotosaturationTests {

    private let noon = Date(timeIntervalSince1970: 1_786_000_000)

    private func hours(_ count: Double, after date: Date) -> Date {
        date.addingTimeInterval(count * 3600)
    }

    private func profile(_ preset: ClothingPreset) -> UserProfile {
        var profile = UserProfile.default
        profile.exposure = BodyExposure(preset: preset)
        return profile
    }

    // MARK: - Décroissance

    @Test("Une demi-vie retire la moitié de la charge")
    func halfLifeHalvesTheLoad() {
        let profile = UserProfile.default
        var skin = Photosaturation()
        skin.deposit(rawIU: 4_000, at: noon, profile: profile)

        #expect(abs(skin.rawLoad(at: noon, profile: profile) - 4_000) < 1)
        #expect(abs(skin.rawLoad(at: hours(12, after: noon), profile: profile) - 2_000) < 1)
        #expect(abs(skin.rawLoad(at: hours(24, after: noon), profile: profile) - 1_000) < 1)
        #expect(skin.rawLoad(at: hours(24 * 30, after: noon), profile: profile) == 0)
    }

    @Test("Rentrer dix minutes ne remet rien à zéro")
    func aShortBreakChangesAlmostNothing() {
        let profile = UserProfile.default
        var skin = Photosaturation()
        skin.deposit(rawIU: 6_000, at: noon, profile: profile)

        let after = skin.rawLoad(at: noon.addingTimeInterval(10 * 60), profile: profile)
        // Moins de un pour cent rendu : c'est tout l'objet de la correction.
        #expect(after > 6_000 * 0.99)
    }

    @Test("Une charge antérieure à la dernière mise à jour ne remonte pas")
    func loadNeverGrowsBackwards() {
        let profile = UserProfile.default
        var skin = Photosaturation()
        skin.deposit(rawIU: 1_000, at: noon, profile: profile)
        #expect(abs(skin.rawLoad(at: hours(-5, after: noon), profile: profile) - 1_000) < 1)
    }

    @Test("Les dépôts successifs s'ajoutent à ce qui reste")
    func depositsAccumulateOnTopOfTheRemainder() {
        let profile = UserProfile.default
        var skin = Photosaturation()
        skin.deposit(rawIU: 4_000, at: noon, profile: profile)
        skin.deposit(rawIU: 4_000, at: hours(12, after: noon), profile: profile)

        // Deux mille restants, plus quatre mille frais.
        #expect(abs(skin.rawLoad(at: hours(12, after: noon), profile: profile) - 6_000) < 1)

        // Un dépôt nul ne doit rien changer, ni à la charge ni à l'horodatage.
        let before = skin
        skin.deposit(rawIU: 0, at: hours(20, after: noon), profile: profile)
        #expect(skin == before)
    }

    @Test("Une charge vide laisse le rendement intact")
    func anEmptySkinYieldsEverything() {
        #expect(Photosaturation.empty.marginalYield(at: noon) == 1)
        #expect(Photosaturation.empty.load(at: noon) == 0)
    }

    // MARK: - Ce que la charge doit ignorer

    @Test("Changer de vêtements ne change pas le rendement d'une peau chargée")
    func clothingDoesNotMoveTheYield() {
        // Le défaut signalé par l'utilisateur : le pourcentage de « peau encore
        // chargée » sautait dès qu'il changeait de tenue. La charge était
        // conservée en UI pour le corps entier, puis rapportée au plafond de la
        // tenue du moment — enfiler un manteau divisait ce plafond et faisait
        // s'effondrer le rendement affiché, sans que rien n'ait bougé dans la
        // peau. Le photo-équilibre s'installe dans un morceau de peau, et il ne
        // sait rien de ce qu'on porte par-dessus.
        let worn = profile(.tShirtShorts)
        var skin = Photosaturation()
        skin.deposit(rawIU: UVEngine.synthesisCeiling(profile: worn) * 0.7,
                     at: noon, profile: worn)

        let reference = skin.marginalYield(at: noon)
        #expect(abs(reference - exp(-0.7)) < 0.01)

        // La même peau, sous n'importe quelle tenue, rend la même chose.
        #expect(skin.marginalYield(at: noon) == reference)
        #expect(skin.marginalYield(at: hours(12, after: noon)) > reference)

        // Et la conversion en UI, elle, suit bien le plafond : une charge égale
        // à 70 % du plafond en vaut toujours 70 %, quelle que soit la tenue.
        for preset in [ClothingPreset.coat, .longSleevesTrousers, .swimwear] {
            let other = profile(preset)
            let ratio = skin.rawLoad(at: noon, profile: other)
                / UVEngine.synthesisCeiling(profile: other)
            #expect(abs(ratio - 0.7) < 0.001)
        }
    }

    @Test("Une charge enregistrée sans son champ se relit sans tout perdre")
    func decodingToleratesAMissingField() throws {
        // Le champ a changé d'unité : une charge écrite par une version
        // antérieure repart de zéro plutôt que d'être lue pour une autre.
        let legacy = Data(#"{"load":4200,"updatedAt":760000000}"#.utf8)
        let decoded = try JSONDecoder().decode(Photosaturation.self, from: legacy)
        #expect(decoded.load(at: noon) == 0)
        #expect(decoded.marginalYield(at: noon) == 1)
    }

    // MARK: - Effet sur la synthèse

    @Test("Le rendement d'une peau chargée est inférieur à celui d'une peau reposée")
    func aLoadedSkinYieldsLess() {
        let profile = UserProfile.default
        var skin = Photosaturation()
        skin.deposit(rawIU: UVEngine.synthesisCeiling(profile: profile),
                     at: noon, profile: profile)

        // Une charge égale au plafond laisse exp(-1), soit 37 %.
        let yield = skin.marginalYield(at: noon)
        #expect(abs(yield - exp(-1)) < 0.01)

        // Et douze heures plus tard, la moitié de la charge : exp(-0,5).
        let later = skin.marginalYield(at: hours(12, after: noon))
        #expect(abs(later - exp(-0.5)) < 0.01)
        #expect(later > yield)
    }

    @Test("La même dose brute produit moins sur une peau déjà chargée")
    func theSameDoseProducesLessOnLoadedSkin() {
        let profile = UserProfile.default
        let ceiling = UVEngine.synthesisCeiling(profile: profile)
        let dose = ceiling / 4

        let fresh = UVEngine.saturated(rawIU: dose, carried: 0, profile: profile)
        let loaded = UVEngine.saturated(rawIU: dose, carried: ceiling, profile: profile)

        #expect(fresh > loaded)
        // Sur une peau reposée, la même dose rapporte près de trois fois plus.
        #expect(fresh > 2.5 * loaded)

        // Sans charge, la formule doit rendre exactement l'ancienne.
        #expect(abs(fresh - UVEngine.saturated(rawIU: dose, profile: profile)) < 0.001)
    }

    @Test("La capacité restante décroît avec la charge et ne devient jamais négative")
    func remainingCapacityShrinks() {
        let profile = UserProfile.default
        let ceiling = UVEngine.synthesisCeiling(profile: profile)

        #expect(abs(UVEngine.remainingCapacity(carried: 0, profile: profile) - ceiling) < 0.001)
        #expect(UVEngine.remainingCapacity(carried: ceiling, profile: profile) < ceiling * 0.4)
        #expect(UVEngine.remainingCapacity(carried: 10 * ceiling, profile: profile) > 0)
    }

    @Test("La dose cumulée nécessaire est celle qui produit bien la cible")
    func cumulativeDoseIsConsistent() throws {
        let profile = UserProfile.default
        let ceiling = UVEngine.synthesisCeiling(profile: profile)
        let carried = ceiling / 3
        let target = ceiling / 5

        let needed = try #require(UVEngine.cumulativeDose(
            toProduce: target, carried: carried, profile: profile))

        #expect(needed > carried)
        let produced = UVEngine.saturated(rawIU: needed - carried, carried: carried, profile: profile)
        #expect(abs(produced - target) < 0.01)
    }

    @Test("Aucune dose n'atteint une cible au-delà de la capacité restante")
    func anUnreachableTargetHasNoDose() {
        let profile = UserProfile.default
        let ceiling = UVEngine.synthesisCeiling(profile: profile)
        let carried = ceiling * 2
        let capacity = UVEngine.remainingCapacity(carried: carried, profile: profile)

        #expect(UVEngine.cumulativeDose(
            toProduce: capacity * 1.1, carried: carried, profile: profile) == nil)
        #expect(UVEngine.cumulativeDose(
            toProduce: capacity * 0.5, carried: carried, profile: profile) != nil)
    }

    // MARK: - Ce que voyait l'utilisateur

    @Test("Deux sorties enchaînées ne repartent pas à plein rendement")
    func backToBackSessionsDoNotReset() throws {
        // Le défaut signalé : arrêter une sortie et en démarrer une autre dans
        // la foulée redonnait 100 % de rendement, donc promettait une récolte
        // que la peau ne peut pas fournir.
        let profile = UserProfile.default
        let ceiling = UVEngine.synthesisCeiling(profile: profile)

        var skin = Photosaturation()
        skin.deposit(rawIU: ceiling * 0.8, at: noon, profile: profile)

        let justAfter = noon.addingTimeInterval(5 * 60)
        #expect(skin.marginalYield(at: justAfter) < 0.5)
        // Il faut une nuit pour revenir dans les trois quarts.
        #expect(skin.marginalYield(at: hours(24, after: noon)) > 0.7)
    }

    @Test("Un créneau proposé tient compte de la charge héritée")
    func recommendationsAccountForTheLoad() throws {
        var calendar = Calendar(identifier: .gregorian)
        let montreal = TimeZone(identifier: "America/Montreal")!
        calendar.timeZone = montreal
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 21
        components.hour = 12
        let day = calendar.date(from: components)!

        let profile = UserProfile.default
        let ceiling = UVEngine.synthesisCeiling(profile: profile)

        let fresh = DayPlanner.makePlan(
            date: day, latitude: 45.5019, longitude: -73.5674,
            timeZone: montreal, profile: profile, carried: 0, forecast: [])
        let loaded = DayPlanner.makePlan(
            date: day, latitude: 45.5019, longitude: -73.5674,
            timeZone: montreal, profile: profile, carried: ceiling, forecast: [])

        let freshBest = try #require(fresh.bestRecommendation)
        let loadedBest = try #require(loaded.bestRecommendation)

        // La bonne grandeur à comparer n'est pas la récolte mais son prix.
        // Selon le Soleil du jour, une peau chargée peut encore atteindre
        // l'objectif — en y passant beaucoup plus de temps et en dépensant
        // beaucoup plus de capital cutané. C'est le rapport des deux qui se
        // dégrade toujours, et jamais l'inverse.
        let freshYield = freshBest.expectedIU / max(freshBest.medFraction, 0.0001)
        let loadedYield = loadedBest.expectedIU / max(loadedBest.medFraction, 0.0001)
        #expect(loadedYield < freshYield)

        // Et la récolte ne dépasse jamais la capacité restante, soit exp(-1)
        // du plafond quand la charge égale ce plafond.
        #expect(loadedBest.expectedIU <= ceiling * exp(-1.0) + 0.01)
        #expect(loadedBest.expectedIU <= freshBest.expectedIU + 0.01)
    }
}
