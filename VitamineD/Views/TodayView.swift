import SwiftUI

struct TodayView: View {

    @Environment(AppModel.self) private var model
    @State private var showsLocationPicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if model.location == nil {
                        locationPrompt
                    } else {
                        notices
                        statusCard
                        if let plan = model.plan {
                            recommendations(plan)
                            Card { DayChart(plan: plan, now: model.now) }
                            morningLightCard
                            dayFacts(plan)
                        }
                        explanation
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Aujourd'hui")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showsLocationPicker = true
                    } label: {
                        Label(model.location?.name ?? "Lieu",
                              systemImage: model.location?.isManual == true ? "mappin" : "location.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                }
            }
            .refreshable { await model.refresh() }
            .sheet(isPresented: $showsLocationPicker) { LocationPickerView() }
        }
    }

    // MARK: - Sections

    private var locationPrompt: some View {
        Card {
            VStack(spacing: 14) {
                Image(systemName: "location.circle")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.vitaminD)
                Text("Où êtes-vous ?")
                    .font(.headline)
                Text("La latitude détermine à elle seule si les UVB traversent "
                     + "l'atmosphère. Sans position, aucun calcul n'est possible.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Utiliser ma position") {
                    model.locationService.requestAuthorisation()
                    model.locationService.refresh()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.vitaminD)
                Button("Choisir un lieu") { showsLocationPicker = true }
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var notices: some View {
        if let plan = model.plan, plan.isVitaminDWinter {
            NoticeBanner(
                kind: .warning,
                title: "Hiver vitaminique",
                message: "Le Soleil culmine à \(Format.degrees(plan.peakElevation)) aujourd'hui, "
                    + "sous les \(Format.degrees(UVEngine.vitaminDWinterElevation)) nécessaires. "
                    + "Le trajet du rayonnement dans l'atmosphère est si long que l'ozone "
                    + "absorbe la quasi-totalité des UVB : aucune durée d'exposition ne "
                    + "produira de vitamine D. Seule l'alimentation ou un supplément peut "
                    + "prendre le relais.")
        }

        if let plan = model.plan, plan.goalExceedsCeiling, !plan.isVitaminDWinter {
            NoticeBanner(
                kind: .info,
                title: "Objectif hors de portée dans cette tenue",
                message: "Avec \(Int(model.profile.exposure.exposedBodyPercentage)) % de peau découverte, "
                    + "la synthèse plafonne à environ \(Format.iu(UVEngine.synthesisCeiling(profile: model.profile))) "
                    + "par sortie. Découvrez davantage de peau, ou revoyez l'objectif à la baisse.")
        }

        if model.snapshot?.isModelled == true {
            NoticeBanner(
                kind: .info,
                title: "Données modélisées",
                message: "Le service météo est injoignable. Les heures et hauteurs solaires "
                    + "restent exactes, mais l'indice UV est calculé pour un ciel dégagé : "
                    + "les valeurs réelles seront plus basses s'il y a des nuages.")
        }
    }

    private var statusCard: some View {
        Card {
            HStack(alignment: .top, spacing: 18) {
                UVGauge(uvIndex: model.currentConditions?.uvIndex ?? 0,
                        clearSkyIndex: model.currentConditions?.uvIndexClearSky ?? 0)

                VStack(alignment: .leading, spacing: 8) {
                    Text(statusHeadline)
                        .font(.headline)
                        .foregroundStyle(statusTint)

                    if let position = model.solarPosition {
                        Label(shadowSentence(position), systemImage: "figure.stand")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let conditions = model.currentConditions {
                        Label {
                            Text("\(WeatherCode.describe(conditions.weatherCode)) · "
                                 + Format.temperature(conditions.apparentTemperature))
                        } icon: {
                            Image(systemName: WeatherCode.symbolName(conditions.weatherCode))
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                        if conditions.cloudTransmission < 0.95 {
                            Text("Les nuages retirent \(Format.percent(1 - conditions.cloudTransmission)) du rayonnement UV.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                MetricTile(label: "Synthèse actuelle",
                           value: rateText,
                           detail: model.profile.exposure.summary,
                           tint: Theme.vitaminD)
                MetricTile(label: "Coup de soleil",
                           value: burnText,
                           detail: burnDetail,
                           glossary: .minimalErythemalDose)
                MetricTile(label: "Aujourd'hui",
                           value: Format.iu(model.todayTotalIU),
                           detail: "objectif \(Int(model.profile.dailyGoalIU)) UI",
                           glossary: .internationalUnits)
            }
        }
    }

    private func recommendations(_ plan: DayPlan) -> some View {
        Group {
            if plan.recommendations.isEmpty {
                Card(title: "Créneaux", systemImage: "clock") {
                    Text(plan.isVitaminDWinter
                         ? "Aucun créneau aujourd'hui : le Soleil reste trop bas."
                         : "Aucun créneau ne permet d'atteindre l'objectif aujourd'hui. "
                           + "Une sortie reste bénéfique, mais le rendement sera faible.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Quand sortir")
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 4)

                    ForEach(Array(plan.recommendations.enumerated()), id: \.element.id) { index, item in
                        RecommendationCard(recommendation: item,
                                           timeZone: plan.timeZone,
                                           isPrimary: index == 0)
                    }
                }
            }
        }
    }

    /// Renvoi vers le calage circadien.
    ///
    /// Volontairement distinct des créneaux vitamine D, et placé après eux :
    /// c'est une autre raison de sortir, à un autre moment, par un mécanisme
    /// sans rapport. Les mêler embrouillerait les deux.
    @ViewBuilder
    private var morningLightCard: some View {
        if let light = model.morningLight {
            NavigationLink {
                CircadianView()
            } label: {
                Card(title: "Lumière du matin", systemImage: "sunrise") {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Format.interval(light.window, in: model.plan?.timeZone))
                                .font(.title3.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.primary)
                            if let minutes = light.quality.recommendedMinutes {
                                Text("\(minutes.lowerBound) à \(minutes.upperBound) min dehors "
                                     + "pour caler votre horloge")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(light.quality.advice)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                    }

                    Text("Sans rapport avec la vitamine D — le Soleil est alors "
                         + "trop bas pour les UVB. C'est l'horloge interne que "
                         + "cette lumière-là règle.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func dayFacts(_ plan: DayPlan) -> some View {
        Card(title: "La journée", systemImage: "sun.horizon") {
            VStack(spacing: 10) {
                factRow("Lever", plan.sunrise.map { Format.time($0, in: plan.timeZone) } ?? "—")
                factRow("Midi solaire", Format.time(plan.solarNoon, in: plan.timeZone))
                factRow("Coucher", plan.sunset.map { Format.time($0, in: plan.timeZone) } ?? "—")
                factRow("Hauteur maximale", Format.degrees(plan.peakElevation))
                factRow("Indice UV maximal", String(format: "%.1f", plan.peakUVIndex))

                if let optimal = plan.windows.filter({ $0.quality == .optimal }).first {
                    factRow("Fenêtre optimale", Format.interval(optimal.interval, in: plan.timeZone))
                }
                if let useful = plan.windows.first, plan.windows.contains(where: { $0.quality != .optimal }) {
                    factRow("Synthèse possible dès", Format.time(useful.interval.start, in: plan.timeZone))
                }
            }
        }
    }

    private var explanation: some View {
        Card(title: "Pourquoi ces heures", systemImage: "book") {
            Text("""
            Les UVB — la seule bande qui déclenche la synthèse — sont absorbés par \
            l'ozone bien plus fortement que les UVA. Quand le Soleil descend, le trajet \
            du rayonnement dans l'atmosphère s'allonge et les UVB disparaissent les \
            premiers. Il reste alors de la lumière, de la chaleur, un indice UV non nul, \
            et pourtant plus rien pour la vitamine D.

            D'où la règle de l'ombre : tant que votre ombre est plus courte que vous, le \
            Soleil dépasse 45° de hauteur et les UVB passent. C'est aussi le moment où le \
            rapport entre vitamine D gagnée et capital cutané dépensé est le meilleur — \
            ce qui rend le milieu de journée plus sûr qu'une longue exposition de fin \
            d'après-midi, à condition d'y rester peu de temps.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Détails

    private func factRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium).monospacedDigit())
        }
    }

    private var statusHeadline: String {
        guard let position = model.solarPosition else { return "—" }
        if position.elevation < 0 { return "Le Soleil est couché" }
        if model.currentRates.vitaminDIUPerMinute < 0.5 {
            return "Soleil trop bas pour la vitamine D"
        }
        if position.elevation >= UVEngine.optimalSynthesisElevation {
            return "Fenêtre optimale ouverte"
        }
        return "Synthèse possible, rendement réduit"
    }

    private var statusTint: Color {
        guard let position = model.solarPosition, position.elevation > 0 else { return .secondary }
        if model.currentRates.vitaminDIUPerMinute < 0.5 { return .secondary }
        return position.elevation >= UVEngine.optimalSynthesisElevation ? Theme.vitaminD : .orange
    }

    private func shadowSentence(_ position: SolarPosition) -> String {
        guard let ratio = position.shadowRatio else {
            return "Soleil sous l'horizon"
        }
        let height = Format.degrees(position.elevation)
        if ratio < 1 {
            return "Soleil à \(height) — votre ombre est plus courte que vous"
        }
        return String(format: "Soleil à %@ — votre ombre fait %.1f× votre taille", height, ratio)
    }

    private var rateText: String {
        let rate = model.currentRates.vitaminDIUPerMinute
        return rate < 0.5 ? "—" : "\(Int(rate)) UI/min"
    }

    /// Temps avant rougeur si l'on restait dehors sans bouger à partir de
    /// maintenant, la course du Soleil comprise.
    private var burnText: String {
        guard model.currentRates.medFractionPerMinute > 0.0001,
              let plan = model.plan else { return "—" }
        guard let seconds = DayPlanner.timeToErythema(
            from: model.now, samples: plan.samples) else {
            // Le Soleil se couchera avant que la dose suffise.
            return "hors d'atteinte"
        }
        return Format.duration(seconds)
    }

    private var burnDetail: String {
        model.currentRates.medFractionPerMinute > 0.0001
            ? "peau nue, montée du Soleil comprise"
            : "peau nue, sans protection"
    }
}

#Preview {
    TodayView().environment(AppModel())
}
