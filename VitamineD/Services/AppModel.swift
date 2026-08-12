import Foundation
import Observation
import SwiftUI

/// État central de l'application : profil, lieu, météo, plan du jour et séance
/// en cours. Tout le reste de l'interface lit d'ici.
@MainActor
@Observable
final class AppModel {

    // MARK: - État publié

    var profile: UserProfile {
        didSet {
            guard profile != oldValue else { return }
            store.save(profile, for: .profile)
            rebuildPlan()
            refreshDailyNotification()
        }
    }

    private(set) var location: ResolvedLocation?
    private(set) var snapshot: WeatherSnapshot?
    private(set) var plan: DayPlan?
    private(set) var activeSession: ExposureSession?
    private(set) var progress: SessionProgress = .zero
    private(set) var history: [SessionRecord] = []
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    /// Instant de référence pour les vues. Réévalué chaque seconde pendant une
    /// séance, chaque minute autrement.
    private(set) var now = Date()

    let locationService = LocationService()
    let notifications = NotificationService()

    // MARK: - Dépendances

    private let store: Store
    private let weatherService: any WeatherProviding
    private let fallbackService = ModelledWeatherService()
    private var tickTask: Task<Void, Never>?

    /// Décalage appliqué à l'horloge, en secondes. Toujours nul en usage
    /// normal ; seules les captures d'écran automatisées s'en servent.
    private let clockOffset: TimeInterval

    private var currentDate: Date { Date().addingTimeInterval(clockOffset) }

    init(store: Store = Store(),
         weatherService: any WeatherProviding = OpenMeteoService()) {
        self.store = store
        self.weatherService = weatherService
        self.profile = store.load(UserProfile.self, for: .profile) ?? .default
        self.history = store.load([SessionRecord].self, for: .history) ?? []
        self.activeSession = store.load(ExposureSession.self, for: .activeSession)

        // Une position imposée sur la ligne de commande prime sur tout le
        // reste : c'est ce qui permet à l'intégration continue de produire des
        // captures d'écran sans dépendre du GPS du simulateur.
        if let forced = LaunchOptions.forcedLocation {
            self.location = forced
            locationService.setManual(latitude: forced.latitude,
                                      longitude: forced.longitude,
                                      name: forced.name,
                                      altitude: forced.altitude)
        } else if let manual = store.load(ResolvedLocation.self, for: .manualLocation) {
            self.location = manual
            locationService.setManual(latitude: manual.latitude,
                                      longitude: manual.longitude,
                                      name: manual.name,
                                      altitude: manual.altitude)
        }

        if LaunchOptions.wantsSolarNoon, let place = self.location {
            let noon = SolarCalculator.solarNoon(
                on: Date(), latitude: place.latitude, longitude: place.longitude,
                calendar: Calendar(identifier: .gregorian))
            self.clockOffset = noon.timeIntervalSince(Date())
        } else {
            self.clockOffset = 0
        }
        self.now = currentDate
    }

    // MARK: - Environnement

    /// Paramètres d'environnement déduits du lieu et de la météo.
    var environment: EnvironmentFactors {
        var factors = EnvironmentFactors.standard
        factors.altitude = max(location?.altitude ?? 0, snapshot?.altitude ?? 0)

        // Un manteau neigeux relève fortement l'albédo : le rayonnement réfléchi
        // atteint le visage et le dessous du menton, régions habituellement
        // épargnées. C'est ce qui explique les coups de soleil de ski.
        if let code = snapshot?.conditions(at: now)?.weatherCode,
           WeatherCode.impliesSnowCover(code) {
            factors.surfaceAlbedo = 0.6
        }
        return factors
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot?.timeZone ?? .current
        return calendar
    }

    var solarPosition: SolarPosition? {
        guard let location else { return nil }
        return SolarCalculator.position(date: now,
                                        latitude: location.latitude,
                                        longitude: location.longitude)
    }

    var currentConditions: UVConditions? {
        plan?.sample(nearest: now).map { sample in
            UVConditions(date: sample.date,
                         uvIndex: sample.uvIndex,
                         uvIndexClearSky: sample.uvIndexClearSky,
                         cloudCover: sample.cloudCover,
                         temperature: sample.apparentTemperature,
                         apparentTemperature: sample.apparentTemperature,
                         precipitationProbability: sample.precipitationProbability,
                         windSpeed: 0,
                         weatherCode: snapshot?.conditions(at: sample.date)?.weatherCode ?? 0)
        }
    }

    /// Débits instantanés dans la tenue actuellement déclarée.
    var currentRates: DoseRates {
        guard let position = solarPosition,
              let sample = plan?.sample(nearest: now) else { return .zero }
        return UVEngine.rates(profile: profile,
                              uvIndex: sample.uvIndex,
                              solarElevation: position.elevation,
                              environment: environment)
    }

    var todayTotalIU: Double {
        history.totalIU(on: now, calendar: calendar)
            + (activeSession != nil ? progress.vitaminDIU : 0)
    }

    // MARK: - Cycle de vie

    func start() async {
        startTicking()
        locationService.refresh()
        await notifications.refreshAuthorisationStatus()
        await refresh()
    }

    func onLocationChanged() {
        guard let resolved = locationService.location else { return }
        let moved = location.map { existing in
            abs(existing.latitude - resolved.latitude) > 0.05
                || abs(existing.longitude - resolved.longitude) > 0.05
        } ?? true

        location = resolved
        if moved || snapshot == nil {
            Task { await refresh() }
        } else {
            rebuildPlan()
        }
    }

    /// Fixe une position manuelle, ou revient au GPS si `nil`.
    func setManualLocation(_ manual: ResolvedLocation?) {
        if let manual {
            store.save(manual, for: .manualLocation)
            location = manual
            locationService.setManual(latitude: manual.latitude,
                                      longitude: manual.longitude,
                                      name: manual.name,
                                      altitude: manual.altitude)
        } else {
            store.remove(.manualLocation)
            location = nil
            locationService.refresh()
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard let location else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            snapshot = try await weatherService.snapshot(
                latitude: location.latitude, longitude: location.longitude, days: 3)
            lastError = nil
        } catch {
            // Sans réseau, le modèle de ciel clair prend le relais : les heures
            // restent justes, seule la couverture nuageuse manque. Mieux vaut
            // cela qu'un écran vide.
            snapshot = try? await fallbackService.snapshot(
                latitude: location.latitude, longitude: location.longitude, days: 3)
            lastError = error.localizedDescription
        }

        rebuildPlan()
        refreshDailyNotification()
        scheduleWindowNotification()
        updateProgress()
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval: UInt64 = self.activeSession != nil ? 1 : 30
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self.now = self.currentDate
                self.updateProgress()

                // Le plan est reconstruit au changement de jour, sinon les
                // fenêtres afficheraient encore celles de la veille.
                if let plan = self.plan,
                   !self.calendar.isDate(plan.date, inSameDayAs: self.now) {
                    self.rebuildPlan()
                }
            }
        }
    }

    // MARK: - Plan

    private func rebuildPlan() {
        guard let location else { plan = nil; return }
        let forecast = snapshot?.hourly ?? []
        plan = DayPlanner.makePlan(
            date: now,
            latitude: location.latitude,
            longitude: location.longitude,
            timeZone: snapshot?.timeZone ?? .current,
            profile: profile,
            environment: environment,
            forecast: forecast)
    }

    /// Plan d'un jour quelconque, pour la vue des prochains jours.
    func plan(for day: Date) -> DayPlan? {
        guard let location else { return nil }
        return DayPlanner.makePlan(
            date: day,
            latitude: location.latitude,
            longitude: location.longitude,
            timeZone: snapshot?.timeZone ?? .current,
            profile: profile,
            environment: environment,
            forecast: snapshot?.hourly ?? [])
    }

    // MARK: - Séance

    var isSessionActive: Bool { activeSession != nil }

    func startSession() {
        guard let location else { return }
        let session = ExposureSession(profile: profile, location: location)
        activeSession = session
        store.save(session, for: .activeSession)
        updateProgress()
        startTicking()

        Task {
            await notifications.scheduleSessionAlerts(
                session: session,
                environment: environment,
                uvIndexAt: uvIndexProvider())
        }
    }

    /// Enregistre un changement de tenue en cours de sortie.
    func updateSessionExposure(_ exposure: BodyExposure) {
        profile.exposure = exposure
        guard var session = activeSession else { return }
        session.segments.append(.init(start: Date(), exposure: exposure))
        activeSession = session
        store.save(session, for: .activeSession)
        updateProgress()

        // Les alertes déjà déposées reposaient sur l'ancienne tenue : elles ne
        // valent plus rien. On les remplace.
        Task {
            await notifications.scheduleSessionAlerts(
                session: session,
                environment: environment,
                uvIndexAt: uvIndexProvider())
        }
    }

    @discardableResult
    func endSession() -> SessionRecord? {
        guard var session = activeSession else { return nil }
        session.endDate = Date()
        updateProgress()

        let record = SessionRecord(
            id: session.id,
            start: session.startDate,
            end: session.endDate ?? Date(),
            vitaminDIU: progress.vitaminDIU,
            medFraction: progress.medFraction,
            locationName: session.locationName,
            exposedBodyPercentage: session.exposure(at: session.endDate ?? Date())
                .exposedBodyPercentage)

        history.insert(record, at: 0)
        // Trois mois d'historique suffisent largement à voir une tendance.
        history = Array(history.prefix(200))
        store.save(history, for: .history)

        activeSession = nil
        store.remove(.activeSession)
        progress = .zero
        notifications.cancelSessionAlerts()
        startTicking()
        return record
    }

    private func updateProgress() {
        guard let session = activeSession else { progress = .zero; return }
        progress = SessionIntegrator.progress(
            for: session, at: now, environment: environment,
            uvIndexAt: uvIndexProvider())
    }

    /// Fournisseur d'indice UV interpolé, partagé par l'intégrateur et les
    /// projections de notification.
    private func uvIndexProvider() -> @Sendable (Date) -> Double {
        let samples = plan?.samples ?? []
        let factors = self.environment
        let coordinates = self.location
        return { date in
            if let nearest = samples.min(by: {
                abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
            }), abs(nearest.date.timeIntervalSince(date)) < 15 * 60 {
                return nearest.uvIndex
            }
            // Hors de la plage échantillonnée — séance à cheval sur minuit, ou
            // prévision épuisée — on retombe sur le modèle de ciel clair.
            guard let coordinates else { return 0 }
            let position = SolarCalculator.position(date: date,
                                                    latitude: coordinates.latitude,
                                                    longitude: coordinates.longitude)
            return UVEngine.modelledClearSkyUVIndex(
                solarElevation: position.elevation, environment: factors)
        }
    }

    // MARK: - Notifications

    private func refreshDailyNotification() {
        guard profile.notifyDailyPlan else {
            notifications.scheduleDailyPlan(minuteOfDay: profile.dailyPlanMinuteOfDay, plan: nil)
            return
        }
        notifications.scheduleDailyPlan(minuteOfDay: profile.dailyPlanMinuteOfDay, plan: plan)
    }

    private func scheduleWindowNotification() {
        guard profile.notifyWindowOpening, let plan else { return }
        guard let opening = plan.windows.first(where: {
            $0.quality == .optimal && $0.interval.start > now
        }) else { return }

        let sample = plan.sample(nearest: opening.interval.start)
        notifications.scheduleWindowOpening(
            at: opening.interval.start,
            elevation: sample?.solarElevation ?? UVEngine.optimalSynthesisElevation,
            uvIndex: sample?.uvIndex ?? opening.peakUVIndex)
    }
}
