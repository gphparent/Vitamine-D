import Foundation
import Testing
@testable import VitamineD

struct ExposureSessionTests {

    private let latitude = 45.5019
    private let longitude = -73.5674

    /// Un jour d'été, à Montréal, autour du midi solaire.
    private var noon: Date {
        var components = DateComponents()
        components.year = 2026; components.month = 6; components.day = 21
        components.hour = 16; components.minute = 56  // 12 h 56 heure locale
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    private func session(startingAt start: Date,
                         profile: UserProfile = .default) -> ExposureSession {
        ExposureSession(
            id: UUID(),
            startDate: start,
            profile: profile,
            location: ResolvedLocation(latitude: latitude, longitude: longitude,
                                       altitude: 36, name: "Montréal", isManual: true))
    }

    /// Indice UV constant : rend l'intégration vérifiable à la main.
    private func fixedUV(_ value: Double) -> (Date) -> Double { { _ in value } }

    @Test("Une séance qui vient de commencer n'a rien accumulé")
    func freshSessionIsEmpty() {
        let live = session(startingAt: noon)
        let progress = SessionIntegrator.progress(
            for: live, at: noon, environment: .standard, uvIndexAt: fixedUV(8))
        #expect(progress.vitaminDIU == 0)
        #expect(progress.medFraction == 0)
        #expect(progress.elapsed == 0)
    }

    @Test("L'intégration retrouve le produit du débit par la durée")
    func integrationMatchesRateTimesTime() {
        let live = session(startingAt: noon)
        let progress = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(20 * 60),
            environment: .standard, uvIndexAt: fixedUV(8))

        let position = SolarCalculator.position(
            date: noon.addingTimeInterval(10 * 60), latitude: latitude, longitude: longitude)
        let rates = UVEngine.rates(profile: .default, uvIndex: 8,
                                   solarElevation: position.elevation)

        // Le Soleil bouge un peu en vingt minutes : on tolère 2 %.
        #expect(abs(progress.rawVitaminDIU - rates.vitaminDIUPerMinute * 20)
                / (rates.vitaminDIUPerMinute * 20) < 0.02)
        #expect(abs(progress.medFraction - rates.medFractionPerMinute * 20)
                / (rates.medFractionPerMinute * 20) < 0.02)
        #expect(abs(progress.elapsed - 20 * 60) < 1)
    }

    @Test("La dose croît de façon monotone")
    func doseIsMonotonic() {
        let live = session(startingAt: noon)
        var previousIU = -1.0
        var previousMED = -1.0
        for minutes in stride(from: 0, through: 120, by: 5) {
            let progress = SessionIntegrator.progress(
                for: live, at: noon.addingTimeInterval(Double(minutes) * 60),
                environment: .standard, uvIndexAt: fixedUV(7))
            #expect(progress.vitaminDIU >= previousIU)
            #expect(progress.medFraction >= previousMED)
            previousIU = progress.vitaminDIU
            previousMED = progress.medFraction
        }
    }

    @Test("La synthèse plafonne alors que la dose cutanée continue de croître")
    func synthesisPlateausButBurnDoesNot() {
        let live = session(startingAt: noon)
        let ceiling = UVEngine.synthesisCeiling(profile: .default)

        let short = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(30 * 60),
            environment: .standard, uvIndexAt: fixedUV(9))
        let long = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(180 * 60),
            environment: .standard, uvIndexAt: fixedUV(9))

        #expect(long.vitaminDIU < ceiling)
        // La dose érythémale, elle, est strictement proportionnelle au temps :
        // c'est tout l'argument contre les longues expositions.
        #expect(long.medFraction > short.medFraction * 4)
        #expect(long.marginalYield < short.marginalYield)
    }

    @Test("Changer de tenue en cours de sortie modifie le débit")
    func changingClothesChangesTheRate() {
        var live = session(startingAt: noon)
        let halfway = noon.addingTimeInterval(15 * 60)
        live.segments.append(.init(start: halfway,
                                   exposure: BodyExposure(preset: .swimwear)))

        let unchanged = session(startingAt: noon)
        let withChange = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(30 * 60),
            environment: .standard, uvIndexAt: fixedUV(8))
        let without = SessionIntegrator.progress(
            for: unchanged, at: noon.addingTimeInterval(30 * 60),
            environment: .standard, uvIndexAt: fixedUV(8))

        #expect(withChange.rawVitaminDIU > without.rawVitaminDIU)
        // Se découvrir davantage n'accélère pas le coup de soleil : la dose
        // reçue par unité de surface est la même.
        #expect(abs(withChange.medFraction - without.medFraction) < 1e-9)
    }

    @Test("Appliquer de la crème en cours de sortie ralentit les deux compteurs")
    func applyingSunscreenSlowsBoth() {
        var live = session(startingAt: noon)
        live.segments.append(.init(
            start: noon.addingTimeInterval(10 * 60),
            exposure: BodyExposure(preset: .tShirtShorts, sunscreenSPF: 50)))

        let protectedRun = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(40 * 60),
            environment: .standard, uvIndexAt: fixedUV(9))
        let bareRun = SessionIntegrator.progress(
            for: session(startingAt: noon), at: noon.addingTimeInterval(40 * 60),
            environment: .standard, uvIndexAt: fixedUV(9))

        #expect(protectedRun.medFraction < bareRun.medFraction)
        #expect(protectedRun.rawVitaminDIU < bareRun.rawVitaminDIU)
    }

    @Test("Une séance terminée fige son compte")
    func endedSessionStopsAccumulating() {
        var live = session(startingAt: noon)
        live.endDate = noon.addingTimeInterval(20 * 60)

        let atEnd = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(20 * 60),
            environment: .standard, uvIndexAt: fixedUV(8))
        let muchLater = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(600 * 60),
            environment: .standard, uvIndexAt: fixedUV(8))

        #expect(abs(atEnd.vitaminDIU - muchLater.vitaminDIU) < 1e-9)
        #expect(abs(atEnd.medFraction - muchLater.medFraction) < 1e-9)
    }

    @Test("La projection situe l'instant où un seuil sera franchi")
    func projectionFindsThreshold() throws {
        let live = session(startingAt: noon)
        let goal = UserProfile.default.dailyGoalIU

        let reached = try #require(SessionIntegrator.projectedDate(
            for: live, from: noon, environment: .standard,
            uvIndexAt: fixedUV(8),
            reaching: { $0.vitaminDIU >= goal }))

        #expect(reached > noon)

        // Au seuil, l'objectif doit être atteint ; une minute plus tôt, non.
        let atThreshold = SessionIntegrator.progress(
            for: live, at: reached, environment: .standard, uvIndexAt: fixedUV(8))
        let justBefore = SessionIntegrator.progress(
            for: live, at: reached.addingTimeInterval(-90),
            environment: .standard, uvIndexAt: fixedUV(8))

        #expect(atThreshold.vitaminDIU >= goal)
        #expect(justBefore.vitaminDIU < goal)
    }

    @Test("Un seuil hors d'atteinte ne renvoie aucune date")
    func unreachableThresholdReturnsNil() {
        let live = session(startingAt: noon)
        let impossible = SessionIntegrator.projectedDate(
            for: live, from: noon, environment: .standard,
            horizon: 2 * 3600,
            uvIndexAt: fixedUV(8),
            reaching: { $0.vitaminDIU >= 1_000_000 })
        #expect(impossible == nil)
    }

    @Test("Les paliers d'alerte cutanée sont ordonnés")
    func burnLevelsAreOrdered() {
        func level(_ fraction: Double) -> SessionProgress.BurnLevel {
            SessionProgress(elapsed: 0, vitaminDIU: 0, rawVitaminDIU: 0,
                            medFraction: fraction, currentRates: .zero, marginalYield: 1)
                .burnLevel(alertFraction: 0.6)
        }
        #expect(level(0.1) == .safe)
        #expect(level(0.5) == .caution)
        #expect(level(0.7) == .warning)
        #expect(level(0.95) == .danger)
        #expect(level(0.1) < level(0.5))
        #expect(level(0.7) < level(0.95))
    }

    // MARK: - Se retourner

    /// Une sortie couchée, retournée à mi-parcours.
    private func flippingSession(startingAt start: Date,
                                 duration: TimeInterval) -> ExposureSession {
        var live = session(startingAt: start)
        live.segments = [
            .init(start: start, exposure: UserProfile.default.exposure, side: .front),
            .init(start: start.addingTimeInterval(duration / 2),
                  exposure: UserProfile.default.exposure, side: .back)
        ]
        return live
    }

    private func lyingSession(startingAt start: Date) -> ExposureSession {
        var live = session(startingAt: start)
        live.segments = [.init(start: start,
                               exposure: UserProfile.default.exposure,
                               side: .front)]
        return live
    }

    @Test("Debout, le calcul par moitiés redonne exactement l'ancien")
    func uprightMatchesTheWholeBodyFormula() {
        let live = session(startingAt: noon)
        let progress = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(40 * 60),
            environment: .standard, carried: 500, uvIndexAt: fixedUV(8))

        // Deux demi-plafonds à demi-charge valent un plafond entier à charge
        // entière : la refonte ne devait rien changer à une sortie debout.
        let expected = UVEngine.saturated(
            rawIU: progress.rawVitaminDIU, carried: 500, profile: .default)
        #expect(abs(progress.vitaminDIU - expected) < 0.5)

        let expectedYield = UVEngine.marginalYield(
            rawIU: 500 + progress.rawVitaminDIU, profile: .default)
        #expect(abs(progress.marginalYield - expectedYield) < 0.001)

        #expect(progress.currentSide == .whole)
        #expect(progress.medBySide.front == 0)
        #expect(progress.medBySide.back == 0)
    }

    @Test("Couché sous un Soleil haut, la synthèse dépasse celle d'un corps debout")
    func lyingDownBeatsStandingUnderAHighSun() {
        // Le défaut relevé par l'utilisateur : l'application divisait la
        // synthèse par deux dès qu'on se couchait, au motif qu'une moitié
        // seulement du corps voit le ciel. C'était compter la géométrie deux
        // fois — l'étalonnage est mesuré sur des gens debout, et un corps
        // debout n'a jamais présenté au Soleil que le tiers de sa peau.
        //
        // Au midi solaire du 21 juin à Montréal, le Soleil culmine vers 68° :
        // un corps debout le reçoit de haut, donc mal ; un corps couché le
        // reçoit de plein fouet. La récolte est plus grande couché, ce que
        // savent d'expérience tous ceux qui se sont fait bronzer.
        let end = noon.addingTimeInterval(30 * 60)
        let upright = SessionIntegrator.progress(
            for: session(startingAt: noon), at: end,
            environment: .standard, uvIndexAt: fixedUV(8))
        let lying = SessionIntegrator.progress(
            for: lyingSession(startingAt: noon), at: end,
            environment: .standard, uvIndexAt: fixedUV(8))

        #expect(lying.rawVitaminDIU > upright.rawVitaminDIU * 1.2)
        #expect(lying.rawVitaminDIU < upright.rawVitaminDIU * 1.7)

        // La dose érythémale, elle, ne dépend pas de la posture : le ventre
        // d'un dormeur, horizontal, reçoit exactement l'indice UV annoncé, et
        // l'épaule d'un marcheur à peu près autant.
        #expect(abs(lying.medFraction - upright.medFraction) < 0.001)
    }

    @Test("Sous un Soleil bas, se coucher fait perdre")
    func lyingDownLosesUnderALowSun() {
        // La bascule tient à la géométrie seule : un corps debout est un
        // cylindre vertical, qui offre sa plus grande surface au Soleil quand
        // celui-ci rase l'horizon. En fin d'après-midi, rester debout rapporte
        // davantage — l'inverse exact de midi.
        let evening = noon.addingTimeInterval(5.5 * 3600)
        let end = evening.addingTimeInterval(30 * 60)
        let upright = SessionIntegrator.progress(
            for: session(startingAt: evening), at: end,
            environment: .standard, uvIndexAt: fixedUV(3))
        let lying = SessionIntegrator.progress(
            for: lyingSession(startingAt: evening), at: end,
            environment: .standard, uvIndexAt: fixedUV(3))

        #expect(lying.rawVitaminDIU < upright.rawVitaminDIU)
        #expect(abs(lying.medFraction - upright.medFraction) < 0.001)
    }

    @Test("Se retourner divise en deux le capital dépensé sur chaque moitié")
    func turningOverHalvesTheWorstPatch() {
        let duration: TimeInterval = 40 * 60
        let end = noon.addingTimeInterval(duration)

        let onOneSide = SessionIntegrator.progress(
            for: lyingSession(startingAt: noon), at: end,
            environment: .standard, uvIndexAt: fixedUV(8))
        let flipped = SessionIntegrator.progress(
            for: flippingSession(startingAt: noon, duration: duration), at: end,
            environment: .standard, uvIndexAt: fixedUV(8))

        // Le fait central : à durée égale et à dose brute égale, la moitié la
        // plus exposée n'a pris que la moitié de la dose érythémale.
        #expect(abs(flipped.rawVitaminDIU - onOneSide.rawVitaminDIU) < 0.5)
        #expect(abs(flipped.medFraction - onOneSide.medFraction / 2) < 0.005)

        // Chaque moitié porte sa part, et aucune n'est oubliée.
        #expect(flipped.medBySide.front > 0)
        #expect(flipped.medBySide.back > 0)
        #expect(abs(flipped.medBySide.front - flipped.medBySide.back) < 0.01)
        #expect(flipped.currentSide == .back)
    }

    @Test("La moitié fraîche repart au plein rendement")
    func theFreshHalfStartsUnsaturated() {
        // Une exposition assez longue pour que la saturation morde.
        let duration: TimeInterval = 80 * 60
        let end = noon.addingTimeInterval(duration)

        let onOneSide = SessionIntegrator.progress(
            for: lyingSession(startingAt: noon), at: end,
            environment: .standard, uvIndexAt: fixedUV(9))
        let flipped = SessionIntegrator.progress(
            for: flippingSession(startingAt: noon, duration: duration), at: end,
            environment: .standard, uvIndexAt: fixedUV(9))

        // Même dose brute, mais répartie sur deux moitiés qui saturent chacune
        // moins vite : la vitamine D réellement produite est plus grande.
        #expect(abs(flipped.rawVitaminDIU - onOneSide.rawVitaminDIU) < 1)
        #expect(flipped.vitaminDIU > onOneSide.vitaminDIU)
        #expect(flipped.marginalYield > onOneSide.marginalYield)
    }

    @Test("La moitié quittée garde ce qu'elle a pris")
    func theAbandonedHalfKeepsItsDose() {
        let duration: TimeInterval = 40 * 60
        let live = flippingSession(startingAt: noon, duration: duration)

        let atFlip = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(duration / 2),
            environment: .standard, uvIndexAt: fixedUV(8))
        let atEnd = SessionIntegrator.progress(
            for: live, at: noon.addingTimeInterval(duration),
            environment: .standard, uvIndexAt: fixedUV(8))

        // Rien n'est remis à zéro : la première face porte encore, à la fin,
        // ce qu'elle avait au moment du retournement.
        #expect(atEnd.medBySide.front > 0)
        #expect(abs(atEnd.medBySide.front - atFlip.medBySide.front) < 0.001)
    }

    @Test("Une sortie enregistrée sans face se relit comme une sortie debout")
    func legacySegmentDecodesAsUpright() throws {
        let json = """
        {"start": 780000000, "exposure": {"preset": "tShirtShorts",
         "customRegions": [], "sunscreenSPF": 1, "wearsHat": false}}
        """.data(using: .utf8)!

        let segment = try JSONDecoder().decode(ExposureSession.Segment.self, from: json)
        #expect(segment.side == .whole)
    }

    @Test("Une sortie de nuit n'accumule rien")
    func nightSessionAccumulatesNothing() {
        let midnight = noon.addingTimeInterval(-12 * 3600)
        let live = session(startingAt: midnight)
        let progress = SessionIntegrator.progress(
            for: live, at: midnight.addingTimeInterval(60 * 60),
            environment: .standard, uvIndexAt: { _ in 0 })
        #expect(progress.vitaminDIU == 0)
        #expect(progress.medFraction == 0)
    }
}
