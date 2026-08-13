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
    /// La course du Soleil sur l'année entière au lieu courant. Sert à situer
    /// la journée dans sa saison, et à préparer l'hiver vitaminique.
    private(set) var yearOutlook: YearOutlook?
    private(set) var activeSession: ExposureSession?
    private(set) var progress: SessionProgress = .zero
    private(set) var history: [SessionRecord] = []
    /// Ce que la peau garde de ses expositions précédentes. Une sortie qui suit
    /// de peu la précédente ne repart pas du bas de la courbe de saturation.
    private(set) var photosaturation: Photosaturation = .empty
    private(set) var lastError: String?
    private(set) var isRefreshing = false

    /// Instant de référence pour les vues. Réévalué chaque seconde pendant une
    /// séance, chaque minute autrement.
    private(set) var now = Date()

    let locationService = LocationService()
    let notifications = NotificationService()
    let liveActivity = LiveActivityService()
    let health = HealthKitService()

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
         weatherService: any WeatherProviding = AppleWeatherService()) {
        self.store = store
        self.weatherService = weatherService
        self.profile = store.load(UserProfile.self, for: .profile) ?? .default
        self.history = store.load([SessionRecord].self, for: .history) ?? []
        self.activeSession = store.load(ExposureSession.self, for: .activeSession)
        self.photosaturation = store.load(Photosaturation.self, for: .photosaturation) ?? .empty

        // Une position imposée sur la ligne de commande prime sur tout le
        // reste : c'est ce qui permet à l'intégration continue de produire des
        // captures d'écran sans dépendre du GPS du simulateur.
        let resolved = LaunchOptions.forcedLocation
            ?? store.load(ResolvedLocation.self, for: .manualLocation)
        self.location = resolved

        if LaunchOptions.wantsSolarNoon, let place = resolved {
            let noon = SolarCalculator.solarNoon(
                on: Date(), latitude: place.latitude, longitude: place.longitude,
                calendar: Calendar(identifier: .gregorian))
            self.clockOffset = noon.timeIntervalSince(Date())
        } else {
            self.clockOffset = 0
        }
        self.now = Date().addingTimeInterval(self.clockOffset)

        // Toutes les propriétés stockées sont désormais remplies : c'est
        // seulement à partir d'ici que Swift autorise à appeler une méthode.
        if let resolved {
            locationService.setManual(latitude: resolved.latitude,
                                      longitude: resolved.longitude,
                                      name: resolved.name,
                                      altitude: resolved.altitude)
        }
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

    // MARK: - Lumière et horloge interne

    /// Fenêtre de lumière matinale pour aujourd'hui.
    ///
    /// Sans rapport avec la vitamine D : le Soleil rasant du matin ne produit
    /// aucun UVB utile, mais c'est le meilleur signal horaire de la journée.
    var morningLight: CircadianPlanner.MorningLight? {
        guard profile.tracksCircadianLight, let plan else { return nil }
        let dayStart = calendar.startOfDay(for: now)
        let wake = dayStart.addingTimeInterval(TimeInterval(profile.wakeMinuteOfDay) * 60)
        return CircadianPlanner.morningLight(wakeTime: wake,
                                             samples: plan.samples,
                                             sunrise: plan.sunrise)
    }

    var phaseShift: CircadianPlanner.PhaseShiftPlan {
        CircadianPlanner.phaseShift(current: profile.wakeMinuteOfDay,
                                    target: profile.targetWakeMinuteOfDay,
                                    sleepDuration: profile.sleepHours)
    }

    /// La fenêtre de lumière matinale est-elle encore devant nous ?
    var morningLightIsAhead: Bool {
        guard let light = morningLight else { return false }
        return light.window.end > now
    }

    /// Charge photochimique restante à l'instant présent.
    var carriedLoad: Double { photosaturation.load(at: now) }

    /// Charge que la peau portait au moment où la sortie en cours a commencé.
    ///
    /// C'est cette valeur-là, et non celle de l'instant présent, qu'attend
    /// l'intégrateur : la dose de la sortie en cours n'a pas encore été versée
    /// dans la charge — elle ne l'est qu'à la fin — et l'intégrateur l'ajoute
    /// lui-même en repartant du début. Lui donner la charge d'aujourd'hui
    /// compterait la sortie deux fois.
    private var carriedAtSessionStart: Double {
        guard let session = activeSession else { return carriedLoad }
        return photosaturation.load(at: session.startDate)
    }

    /// Rendement que rapporterait la première minute d'une nouvelle sortie.
    ///
    /// Vaut 1 sur une peau reposée, et d'autant moins que la dernière sortie
    /// est récente et généreuse.
    var restingMarginalYield: Double {
        photosaturation.marginalYield(at: now, profile: profile)
    }

    // MARK: - Hiver

    /// Bilan d'avant-hiver : ce qui reste de saison utile, et ce que devient la
    /// réserve constituée jusqu'ici.
    var winterPlan: WinterPlanner.Plan? {
        guard let yearOutlook else { return nil }
        return WinterPlanner.plan(on: now, outlook: yearOutlook, history: history)
    }

    /// Ce que la journée a consommé et produit avant la sortie en cours.
    ///
    /// L'érythème s'accumule sur la journée entière : une sortie ne redémarre
    /// pas de zéro, elle reprend là où la précédente s'est arrêtée.
    var carriedMEDToday: Double {
        history.totalMEDFraction(on: now, calendar: calendar)
    }

    var carriedIUToday: Double {
        history.totalIU(on: now, calendar: calendar)
    }

    var todayTotalIU: Double {
        carriedIUToday + (activeSession != nil ? progress.vitaminDIU : 0)
    }

    /// Vitamine D du jour, celle de l'assiette comprise quand elle est connue.
    ///
    /// Les deux voies aboutissent à la même molécule : les additionner est
    /// légitime, et c'est même la seule façon de juger d'une journée d'hiver,
    /// où la peau ne produit rien du tout.
    var todayTotalWithDietIU: Double {
        todayTotalIU + (profile.readsHealthKit ? health.dietaryVitaminDIU : 0)
    }

    /// Minutes de plein jour mesurées par l'appareil que l'application n'a pas
    /// vues passer.
    ///
    /// L'écart n'est pas anodin : c'est du capital cutané dépensé hors de ses
    /// comptes. On ne le convertit pas en dose — l'appareil ne dit ni la tenue
    /// ni l'ombre — mais on le signale.
    var untrackedDaylightMinutes: Double {
        guard profile.readsHealthKit else { return 0 }
        let recorded = history
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .reduce(0.0) { $0 + $1.duration / 60 }
            + (activeSession != nil ? progress.elapsed / 60 : 0)
        return max(0, health.daylightMinutes - recorded)
    }

    /// Capital cutané dépensé aujourd'hui, sortie en cours comprise.
    var todayTotalMEDFraction: Double {
        carriedMEDToday + (activeSession != nil ? progress.medFraction : 0)
    }

    /// Niveau d'alerte cutanée pour la journée, sortie en cours ou non.
    ///
    /// Les seuils sont ceux d'une sortie, appliqués au total du jour : c'est
    /// la même peau et le même seuil de rougeur, que la dose ait été prise en
    /// une fois ou en trois.
    var todayBurnLevel: SessionProgress.BurnLevel {
        var probe = SessionProgress.zero
        probe.carriedMEDFraction = todayTotalMEDFraction
        return probe.burnLevel(alertFraction: profile.burnAlertFraction)
    }

    // MARK: - Cycle de vie

    func start() async {
        if profile.readsHealthKit {
            await health.refresh(on: now, calendar: calendar)
        }
        // Une activité peut avoir survécu à la fermeture de l'application :
        // on la reprend si la sortie court toujours, on la congédie sinon.
        liveActivity.adopt(sessionIsActive: isSessionActive)
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

        if profile.readsHealthKit {
            await health.refresh(on: now, calendar: calendar)
        }

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
        guard let location else { plan = nil; yearOutlook = nil; return }
        let forecast = snapshot?.hourly ?? []
        let zone = snapshot?.timeZone ?? .current
        plan = DayPlanner.makePlan(
            date: now,
            latitude: location.latitude,
            longitude: location.longitude,
            timeZone: zone,
            profile: profile,
            environment: environment,
            carried: carriedLoad,
            carriedMED: carriedMEDToday,
            forecast: forecast)

        // L'année ne dépend ni de la météo ni du profil : on ne la recalcule que
        // si le lieu ou l'année civile ont changé.
        let year = calendar.component(.year, from: now)
        if yearOutlook?.latitude != location.latitude
            || yearOutlook?.longitude != location.longitude
            || yearOutlook?.year != year {
            yearOutlook = YearPlanner.outlook(containing: now,
                                              latitude: location.latitude,
                                              longitude: location.longitude,
                                              timeZone: zone)
        }
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
            carried: carriedLoad,
            carriedMED: carriedMEDToday,
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

        liveActivity.start(locationName: session.locationName,
                           exposedBodyPercentage: profile.exposure.exposedBodyPercentage,
                           startedAt: session.startDate,
                           state: liveActivityState(for: session))

        // Valeurs saisies avant de franchir la frontière de la tâche : elles
        // décrivent l'état de la journée à cet instant précis.
        let carried = carriedAtSessionStart
        let carriedMED = carriedMEDToday
        let carriedIU = carriedIUToday
        Task {
            await notifications.scheduleSessionAlerts(
                session: session,
                environment: environment,
                carried: carried,
                carriedMED: carriedMED,
                carriedIU: carriedIU,
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

        // Changement voulu par l'utilisateur : il doit se voir tout de suite
        // sur l'écran verrouillé, sans attendre le prochain créneau.
        liveActivity.update(liveActivityState(for: session), force: true)

        // Les alertes déjà déposées reposaient sur l'ancienne tenue : elles ne
        // valent plus rien. On les remplace.
        // Valeurs saisies avant de franchir la frontière de la tâche : elles
        // décrivent l'état de la journée à cet instant précis.
        let carried = carriedAtSessionStart
        let carriedMED = carriedMEDToday
        let carriedIU = carriedIUToday
        Task {
            await notifications.scheduleSessionAlerts(
                session: session,
                environment: environment,
                carried: carried,
                carriedMED: carriedMED,
                carriedIU: carriedIU,
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

        // La dose brute de la sortie rejoint la charge de la peau : la
        // prochaine sortie démarrera donc plus haut sur la courbe de
        // saturation, et non à 100 % de rendement comme si rien ne s'était
        // passé.
        photosaturation.deposit(rawIU: progress.rawVitaminDIU,
                                at: session.endDate ?? now)
        store.save(photosaturation, for: .photosaturation)

        activeSession = nil
        store.remove(.activeSession)
        progress = .zero
        rebuildPlan()
        notifications.cancelSessionAlerts()
        liveActivity.end()
        startTicking()
        return record
    }

    private func updateProgress() {
        guard let session = activeSession else { progress = .zero; return }
        progress = SessionIntegrator.progress(
            for: session, at: now, environment: environment,
            carried: carriedAtSessionStart,
            carriedMED: carriedMEDToday,
            carriedIU: carriedIUToday,
            uvIndexAt: uvIndexProvider())

        // Le garde évite de resimuler la sortie à chaque battement d'horloge
        // pour un état qui serait aussitôt jeté.
        if liveActivity.isDue {
            liveActivity.update(liveActivityState(for: session))
        }
    }

    /// État à afficher sur l'écran verrouillé et dans l'île dynamique.
    ///
    /// L'heure d'arrêt est projetée en poursuivant la sortie dans les
    /// conditions prévues — course du Soleil comprise — et l'on retient celle
    /// des deux échéances qui vient en premier. C'est elle que le système
    /// décomptera tout seul, sans que l'application soit réveillée.
    private func liveActivityState(for session: ExposureSession)
    -> SunSessionAttributes.ContentState {

        let provider = uvIndexProvider()
        let burnLimit = profile.burnAlertFraction
        let goal = profile.dailyGoalIU

        let carried = carriedAtSessionStart
        let carriedMED = carriedMEDToday
        let carriedIU = carriedIUToday

        // Les deux échéances se jugent sur la journée, pas sur la sortie : le
        // seuil que l'utilisateur s'est fixé vaut pour sa peau, qui ne
        // distingue pas les sorties.
        let burnAt = SessionIntegrator.projectedDate(
            for: session, from: now, environment: environment,
            carried: carried, carriedMED: carriedMED, carriedIU: carriedIU,
            uvIndexAt: provider,
            reaching: { $0.dayMEDFraction >= burnLimit })
        let goalAt = SessionIntegrator.projectedDate(
            for: session, from: now, environment: environment,
            carried: carried, carriedMED: carriedMED, carriedIU: carriedIU,
            uvIndexAt: provider,
            reaching: { $0.dayVitaminDIU >= goal })

        var stopAt: Date?
        var limit = SunSessionAttributes.ContentState.Limit.none
        switch (burnAt, goalAt) {
        case let (burn?, goalDate?):
            stopAt = min(burn, goalDate)
            limit = burn <= goalDate ? .burn : .goal
        case let (burn?, nil):
            stopAt = burn
            limit = .burn
        case let (nil, goalDate?):
            stopAt = goalDate
            limit = .goal
        case (nil, nil):
            break
        }

        return SunSessionAttributes.ContentState(
            vitaminDIU: progress.dayVitaminDIU,
            goalIU: goal,
            medFraction: progress.dayMEDFraction,
            burnLimit: burnLimit,
            uvIndex: currentConditions?.uvIndex ?? 0,
            stopAt: stopAt,
            limit: limit)
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
