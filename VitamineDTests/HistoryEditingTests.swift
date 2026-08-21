import Foundation
import Testing
@testable import VitamineD

/// Corriger l'historique après coup — « on oublie parfois de dire qu'on rentre
/// ou qu'on sort ».
struct HistoryEditingTests {

    private let montreal = TimeZone(identifier: "America/Montreal")!
    private let place = ResolvedLocation(latitude: 45.5019, longitude: -73.5674,
                                         altitude: 36, name: "Montréal", isManual: true)

    /// 21 juin 2026, midi solaire à Montréal.
    private var noon: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 21
        components.hour = 16; components.minute = 56
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private func clearSky() -> (Date) -> Double {
        RetroactiveEstimator.clearSkyProvider(
            latitude: place.latitude, longitude: place.longitude, environment: .standard)
    }

    private func estimate(from start: Date, minutes: Double,
                          profile: UserProfile = .default,
                          side: BodySide = .whole) -> SessionRecord {
        RetroactiveEstimator.estimate(
            start: start, end: start.addingTimeInterval(minutes * 60),
            profile: profile, side: side, location: place, uvIndexAt: clearSky())
    }

    // MARK: - Reconstitution

    @Test("Une sortie reconstituée porte de la vitamine D et du capital dépensé")
    func aReconstructedOutingHasBothCounts() throws {
        let record = estimate(from: noon, minutes: 30)

        #expect(record.vitaminDIU > 0)
        #expect(record.medFraction > 0)
        #expect(record.minutes == 30)
        #expect(record.isRetroactive)
        #expect(record.locationName == "Montréal")
        // Les coordonnées sont conservées : sans elles, une correction
        // ultérieure ne saurait plus où le Soleil se trouvait.
        #expect(record.latitude == place.latitude)
        // La dose brute est conservée, et elle domine la dose plafonnée.
        let raw = try #require(record.rawVitaminDIU)
        #expect(raw >= record.vitaminDIU)
    }

    @Test("Doubler la durée ne double pas la récolte")
    func twiceTheTimeIsNotTwiceTheVitaminD() {
        // Le point qui interdisait un simple produit durée × débit : le Soleil
        // descend pendant la sortie, et le plafond de photo-équilibre courbe le
        // total. Une heure à midi ne vaut pas deux fois trente minutes.
        let half = estimate(from: noon, minutes: 30)
        let full = estimate(from: noon, minutes: 60)

        #expect(full.vitaminDIU > half.vitaminDIU)
        #expect(full.vitaminDIU < 2 * half.vitaminDIU)

        // La dose érythémale, elle, ne connaît pas de plafond : elle continue
        // de s'accumuler tant qu'on reste dehors.
        #expect(full.medFraction > 1.7 * half.medFraction)
    }

    @Test("Une sortie de nuit ne produit rien")
    func anOutingAfterSunsetProducesNothing() {
        let midnight = noon.addingTimeInterval(11 * 3600)
        let record = estimate(from: midnight, minutes: 60)

        #expect(record.vitaminDIU == 0)
        #expect(record.medFraction == 0)
    }

    @Test("La tenue déclarée change ce que la reconstitution retient")
    func clothingDrivesTheReconstruction() {
        var covered = UserProfile.default
        covered.exposure = BodyExposure(preset: .longSleevesTrousers)
        var bare = UserProfile.default
        bare.exposure = BodyExposure(preset: .swimwear)

        let coveredRecord = estimate(from: noon, minutes: 30, profile: covered)
        let bareRecord = estimate(from: noon, minutes: 30, profile: bare)

        #expect(bareRecord.vitaminDIU > coveredRecord.vitaminDIU * 3)
        #expect(bareRecord.exposedBodyPercentage > coveredRecord.exposedBodyPercentage)
        // Se couvrir ne protège pas de rougir : la peau nue reçoit la même dose.
        #expect(abs(bareRecord.medFraction - coveredRecord.medFraction) < 0.001)
    }

    @Test("Une fin antérieure au début est ramenée à une minute")
    func aBackwardsOutingIsClamped() {
        let record = RetroactiveEstimator.estimate(
            start: noon, end: noon.addingTimeInterval(-3600),
            profile: .default, location: place, uvIndexAt: clearSky())

        #expect(record.end > record.start)
        #expect(record.minutes == 1)
    }

    @Test("La reconstitution et le chronomètre donnent le même nombre")
    func manualEntryMatchesTheStopwatch() {
        // La garantie qui compte : une saisie manuelle passe par l'intégrateur
        // des sorties chronométrées, et non par un second calcul qui aurait
        // divergé au premier changement de constante.
        let end = noon.addingTimeInterval(40 * 60)
        var live = ExposureSession(startDate: noon, profile: .default, location: place)
        live.endDate = end

        let chronometered = SessionIntegrator.progress(
            for: live, at: end, environment: .standard, uvIndexAt: clearSky())
        let reconstructed = estimate(from: noon, minutes: 40)

        #expect(abs(reconstructed.vitaminDIU - chronometered.vitaminDIU) < 0.01)
        #expect(abs(reconstructed.medFraction - chronometered.medFraction) < 0.0001)
    }

    // MARK: - Charge cutanée reconstruite

    @Test("Effacer une sortie retire sa charge de la peau")
    func deletingAnOutingReleasesTheSkin() {
        let record = estimate(from: noon, minutes: 45)
        let later = noon.addingTimeInterval(2 * 3600)

        let withOuting = Photosaturation.rebuilt(
            from: [record], asOf: later, profile: .default)
        let without = Photosaturation.rebuilt(
            from: [], asOf: later, profile: .default)

        #expect(withOuting.load(at: later) > 0)
        #expect(without.load(at: later) == 0)
        #expect(withOuting.marginalYield(at: later) < 1)
        #expect(without.marginalYield(at: later) == 1)
    }

    @Test("Deux historiques identiques donnent la même charge")
    func theRebuildIsDeterministic() {
        let records = [estimate(from: noon, minutes: 30),
                       estimate(from: noon.addingTimeInterval(3 * 3600), minutes: 20)]
        let later = noon.addingTimeInterval(6 * 3600)

        let first = Photosaturation.rebuilt(from: records, asOf: later, profile: .default)
        // Le même historique dans l'autre sens : le tri interne doit l'égaliser.
        let second = Photosaturation.rebuilt(from: records.reversed(),
                                             asOf: later, profile: .default)

        #expect(abs(first.load(at: later) - second.load(at: later)) < 1e-9)
    }

    @Test("Les sorties trop anciennes ne pèsent plus")
    func oldOutingsAreDropped() {
        let ancient = estimate(from: noon.addingTimeInterval(-10 * 86_400), minutes: 60)
        let now = noon.addingTimeInterval(3600)

        let rebuilt = Photosaturation.rebuilt(from: [ancient], asOf: now, profile: .default)
        #expect(rebuilt.load(at: now) == 0)
    }

    @Test("Une tenue équivalente est retrouvée depuis le seul pourcentage")
    func equivalentClothingIsRecovered() {
        let reference = BodyExposure(preset: .tShirtShorts, fabric: .sheer, sunscreenSPF: 30)

        for preset in ClothingPreset.allCases where preset != .custom {
            let percentage = BodyExposure.normalisedFraction(for: preset.exposedRegions) * 100
            let recovered = BodyExposure.matching(exposedPercentage: percentage,
                                                  like: reference)
            #expect(recovered.preset == preset)
            // L'étoffe et la protection déclarées survivent au passage.
            #expect(recovered.fabric == .sheer)
            #expect(recovered.sunscreenSPF == 30)
        }
    }

    // MARK: - Persistance

    @Test("Une sortie enregistrée avant ces champs se relit sans rien perdre")
    func legacyRecordSurvivesDecoding() throws {
        // Ni dose brute, ni coordonnées, ni marque de saisie manuelle : le
        // format d'avant. Un historique est la seule chose de cette application
        // qui ne se reconstitue pas.
        let legacy = Data("""
        {"id":"7B3E0F42-1C4A-4B8E-9F51-2D6A8C0E1234",
         "start":760000000,"end":760001800,
         "vitaminDIU":1234.5,"medFraction":0.42,
         "locationName":"Québec","exposedBodyPercentage":35}
        """.utf8)

        let record = try JSONDecoder().decode(SessionRecord.self, from: legacy)

        #expect(record.vitaminDIU == 1234.5)
        #expect(record.locationName == "Québec")
        #expect(record.minutes == 30)
        #expect(record.latitude == nil)
        #expect(!record.isRetroactive)
        // Faute de dose brute, on retient la dose plafonnée, qui lui est
        // toujours inférieure : la charge reconstituée est sous-estimée, pas
        // inventée.
        #expect(record.rawOrSaturatedIU == 1234.5)
    }

    @Test("Un aller-retour d'encodage conserve les nouveaux champs")
    func roundTripKeepsTheNewFields() throws {
        let original = estimate(from: noon, minutes: 25)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SessionRecord.self, from: data)

        #expect(decoded == original)
        #expect(decoded.isRetroactive)
        #expect(decoded.latitude != nil)
        #expect(decoded.rawVitaminDIU != nil)
    }
}
