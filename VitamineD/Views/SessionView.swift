import SwiftUI

/// Écran de sortie : démarrage, suivi en direct, arrêt.
struct SessionView: View {

    @Environment(AppModel.self) private var model
    @State private var showsClothing = false
    @State private var lastRecord: SessionRecord?
    @State private var showsSummary = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if model.isSessionActive {
                        activeSession
                    } else {
                        idle
                    }
                }
                .padding(16)
            }
            .background(SkyBackground(
                solarElevation: model.solarPosition?.elevation ?? -90,
                cloudCover: model.currentConditions?.cloudCover ?? 0))
            .navigationTitle("Sortie")
            .sheet(isPresented: $showsClothing) {
                ClothingView(exposure: Binding(
                    get: { model.profile.exposure },
                    set: { newValue in
                        if model.isSessionActive {
                            model.updateSessionExposure(newValue)
                        } else {
                            model.profile.exposure = newValue
                        }
                    }
                ))
            }
            .alert("Sortie terminée", isPresented: $showsSummary, presenting: lastRecord) { _ in
                Button("Parfait") { }
            } message: { record in
                Text("\(record.minutes) min · \(Format.iu(record.vitaminDIU)) · "
                     + "\(Format.percent(record.medFraction)) de votre seuil d'érythème.")
            }
        }
    }

    // MARK: - Au repos

    private var idle: some View {
        VStack(spacing: 16) {
            Card {
                VStack(spacing: 16) {
                    Image(systemName: "sun.max.trianglebadge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(canStart ? Theme.vitaminD : .secondary)

                    Text(canStart ? "Prêt à sortir" : "Conditions défavorables")
                        .font(.headline)

                    Text(idleMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        Task {
                            if model.notifications.authorisationStatus == .notDetermined {
                                await model.notifications.requestAuthorisation()
                            }
                            model.startSession()
                        }
                    } label: {
                        Label("Je sors maintenant", systemImage: "figure.walk.departure")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.vitaminD)
                    .disabled(model.location == nil)
                }
                .frame(maxWidth: .infinity)
            }

            clothingCard

            if model.notifications.authorisationStatus == .denied {
                NoticeBanner(
                    kind: .warning,
                    title: "Alertes désactivées",
                    message: "Sans autorisation de notification, l'application ne pourra pas "
                        + "vous prévenir qu'il est temps de rentrer. Réglages › Notifications.")
            }

            projectionCard
        }
    }

    private var canStart: Bool {
        model.currentRates.vitaminDIUPerMinute > 0.5
    }

    private var idleMessage: String {
        guard model.location != nil else {
            return "Indiquez d'abord votre position dans l'onglet Aujourd'hui."
        }
        if let plan = model.plan, plan.isVitaminDWinter {
            return "Le Soleil ne monte pas assez haut aujourd'hui. Une sortie reste bonne "
                + "pour le moral, mais elle ne produira pas de vitamine D."
        }
        if !canStart {
            if let next = model.plan?.windows.first(where: { $0.interval.start > model.now }) {
                return "Le Soleil est trop bas pour l'instant. Prochaine fenêtre à "
                    + "\(Format.time(next.interval.start, in: model.plan?.timeZone ?? .current))."
            }
            return "Le Soleil est trop bas pour produire de la vitamine D."
        }
        let rate = Int(model.currentRates.vitaminDIUPerMinute)
        return "Dans votre tenue actuelle, environ \(rate) UI par minute. "
            + "L'application vous préviendra quand arrêter."
    }

    @ViewBuilder
    private var projectionCard: some View {
        if canStart, let plan = model.plan,
           let index = plan.samples.firstIndex(where: { $0.date >= model.now }),
           let projection = DayPlanner.simulateSession(
            startingAt: index, samples: plan.samples, profile: model.profile,
            carried: model.carriedLoad, carriedMED: model.carriedMEDToday) {
            Card(title: "Si vous sortiez maintenant", systemImage: "hourglass") {
                HStack(spacing: 12) {
                    MetricTile(label: "Durée conseillée",
                               value: "\(projection.minutes) min")
                    MetricTile(label: "Vitamine D",
                               value: Format.iu(projection.expectedIU),
                               tint: Theme.vitaminD)
                    MetricTile(label: "Capital cutané",
                               value: Format.percent(projection.medFraction),
                               detail: model.carriedMEDToday > 0.02 ? "en plus d'aujourd'hui" : nil)
                }
                Text(projection.limitingFactor.explanation)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - En cours

    private var activeSession: some View {
        VStack(spacing: 16) {
            Card {
                VStack(spacing: 18) {
                    Text(Format.stopwatch(model.progress.elapsed))
                        .font(.system(size: 54, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    // Les deux barres comptent la journée, pas la sortie : la
                    // peau ne remet pas ses compteurs à zéro parce qu'on est
                    // rentré déposer un manteau.
                    DualProgressBar(
                        vitaminDFraction: model.progress.vitaminDPercentOfGoal,
                        medFraction: model.progress.dayMEDFraction,
                        burnLevel: burnLevel)

                    HStack(spacing: 12) {
                        MetricTile(label: "Vitamine D",
                                   value: Format.iu(model.progress.dayVitaminDIU),
                                   detail: "sur \(Int(model.profile.dailyGoalIU)) UI aujourd'hui",
                                   tint: Theme.vitaminD)
                        MetricTile(label: "Débit",
                                   value: "\(Int(model.progress.currentRates.vitaminDIUPerMinute)) UI/min")
                        MetricTile(label: "Rendement",
                                   value: Format.percent(model.progress.marginalYield),
                                   detail: "restant",
                                   glossary: .marginalYield)
                    }
                }
            }

            statusBanner

            Button(role: .destructive) {
                lastRecord = model.endSession()
                showsSummary = lastRecord != nil
            } label: {
                Label("Je rentre", systemImage: "figure.walk.arrival")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.burnColour(burnLevel))

            clothingCard

            Card(title: "Prochaines alertes", systemImage: "bell") {
                Text("""
                Les alertes sont déjà programmées auprès du système. Vous pouvez ranger \
                le téléphone : elles se déclencheront même si l'application est fermée. \
                Si vous changez de tenue ou appliquez de la crème, mettez-le à jour \
                ci-dessus — les alertes seront recalculées.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)

                GoldRule()

                if model.liveActivity.isRunning {
                    Label("Le décompte est aussi sur l'écran verrouillé",
                          systemImage: "lock.iphone")
                        .font(.footnote)
                        .foregroundStyle(Theme.vitaminD)
                    Text("Inutile de déverrouiller : l'heure à laquelle rentrer y "
                         + "défile toute seule, et se retrouve dans l'île dynamique "
                         + "quand vous êtes dans une autre application.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if !model.liveActivity.isAvailable {
                    Label("Activités en direct désactivées", systemImage: "lock.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Le décompte pourrait rester affiché sur l'écran verrouillé. "
                         + "Réglages ▸ Vitamine D ▸ Activités en direct.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var burnLevel: SessionProgress.BurnLevel {
        model.progress.burnLevel(alertFraction: model.profile.burnAlertFraction)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch burnLevel {
        case .safe:
            if model.progress.marginalYield < DayPlanner.diminishingReturnsThreshold {
                NoticeBanner(
                    kind: .info,
                    title: "La synthèse plafonne",
                    message: "La prévitamine D3 formée se dégrade maintenant aussi vite qu'elle "
                        + "se forme. Rester dehors n'ajoute plus grand-chose, mais continue "
                        + "d'accumuler de la dose érythémale.")
            } else {
                NoticeBanner(
                    kind: .info,
                    title: "Tout va bien",
                    message: "Vous êtes à \(Format.percent(model.progress.dayMEDFraction)) de votre "
                        + "seuil d'érythème.")
            }
        case .caution:
            NoticeBanner(
                kind: .warning,
                title: "Surveillez",
                message: "Vous approchez du seuil que vous vous êtes fixé "
                    + "(\(Format.percent(model.profile.burnAlertFraction)) de la DEM).")
        case .warning:
            NoticeBanner(
                kind: .warning,
                title: "Couvrez-vous",
                message: "Cherchez l'ombre, remettez un vêtement ou appliquez de la crème. "
                    + "La rougeur n'apparaîtra que dans quelques heures : ne vous fiez pas "
                    + "à ce que vous voyez maintenant.")
        case .danger:
            NoticeBanner(
                kind: .critical,
                title: "Rentrez",
                message: "Le seuil de coup de soleil est atteint ou dépassé. "
                    + "Aucune vitamine D supplémentaire n'est à gagner ici.")
        }
    }

    private var clothingCard: some View {
        Card(title: "Tenue actuelle", systemImage: "tshirt") {
            Button {
                showsClothing = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.profile.exposure.preset.title)
                            .font(.body.weight(.medium))
                        Text(model.profile.exposure.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    SessionView().environment(AppModel())
}
