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
