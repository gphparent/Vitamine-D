import SwiftUI

struct TodayView: View {

    @Environment(AppModel.self) private var model
    @State private var showsLocationPicker = false
    @State private var showsClothing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if model.location == nil {
                        locationPrompt
                    } else {
                        notices
                        statusCard
                        clothingCard
                        if let plan = model.plan {
                            recommendations(plan)
                            Card { DayChart(plan: plan, now: model.now) }
                            dayFacts(plan)
                        }
                        explanation
                    }
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Vitamine D")
            .toolbar {
                // Le lieu reste une pastille flottante dans la barre, et mène
                // à l'année entière : c'est là que se voit l'hiver vitaminique,
                // qu'aucune vue quotidienne ne peut montrer.
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        YearView()
                    } label: {
                        Label(model.location?.name ?? "Lieu",
                              systemImage: model.location?.isManual == true ? "mappin" : "location.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
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
            .sheet(isPresented: $showsClothing) {
                ClothingView(exposure: Binding(
                    get: { model.profile.exposure },
                    set: { model.updateSessionExposure($0) }))
            }
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

        // Sans cette explication, un rendement à 60 % sur une peau qui n'a rien
        // fait depuis une heure passe pour un défaut d'affichage.
        if model.restingMarginalYield < 0.85, model.plan?.isVitaminDWinter != true {
            NoticeBanner(
                kind: .info,
                title: "Peau encore chargée",
                message: "Votre dernière sortie a laissé la synthèse à "
                    + "\(Format.percent(model.restingMarginalYield)) de son rendement. "
                    + "Ce n'est pas un compteur qui se remet à zéro en rentrant : la "
                    + "prévitamine D3 formée dans la peau met des heures à en repartir. "
                    + "Une nouvelle sortie coûterait autant de capital cutané pour "
                    + "nettement moins de vitamine D.")
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
            // Le décompte d'abord : c'est lui qui décide d'une sortie. La jauge
            // et les tuiles qui suivent disent l'instant présent.
            if let plan = model.plan {
                OptimalWindowCountdown(plan: plan, now: model.now)
                Divider()
            }

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
                MetricTile(label: "Vitamine D",
                           value: Format.iu(model.todayTotalIU),
                           detail: "objectif \(Int(model.profile.dailyGoalIU)) UI",
                           tint: Theme.vitaminD,
                           glossary: .internationalUnits)
                MetricTile(label: "Coup de soleil",
                           value: burnText,
                           detail: burnDetail,
                           glossary: .minimalErythemalDose)
            }

            // Les deux comptes de la journée, et non ceux d'une sortie : la
            // peau additionne le matin et l'après-midi, et deux demi-doses
            // font une rougeur.
            DualProgressBar(
                vitaminDFraction: model.profile.dailyGoalIU > 0
                    ? model.todayTotalIU / model.profile.dailyGoalIU : 0,
                medFraction: model.todayTotalMEDFraction,
                burnLevel: model.todayBurnLevel)
        }
    }

    /// Choix de la tenue, à même l'écran principal.
    ///
    /// La surface de peau découverte pèse aussi lourd que la hauteur du Soleil
    /// dans tout ce qui s'affiche au-dessus : la reléguer dans un réglage
    /// revenait à laisser tourner le calcul sur une hypothèse invisible. Un
    /// manteau et un t-shirt donnent des durées dans un rapport de un à six.
    private var clothingCard: some View {
        Card(title: "Tenue", systemImage: "tshirt") {
            HStack(alignment: .firstTextBaseline) {
                Text(model.profile.exposure.preset.title)
                    .font(.headline)
                Spacer()
                Text(String(format: "%.0f %%", model.profile.exposure.exposedBodyPercentage))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(Theme.vitaminD)
                Text("de peau")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(quickPresets) { preset in
                        presetChip(preset)
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 10) {
                if model.profile.exposure.sunscreenSPF > 1 {
                    Label("IP \(model.profile.exposure.sunscreenSPF)", systemImage: "drop.fill")
                }
                if model.profile.exposure.wearsHat {
                    Text("Chapeau")
                }
                Spacer()
                Button("Détails et protection") { showsClothing = true }
                    .font(.caption.weight(.medium))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Les tenues courantes, dans l'ordre du plus couvert au moins couvert. La
    /// tenue personnalisée reste dans la feuille de détail.
    private var quickPresets: [ClothingPreset] {
        [.coat, .longSleevesTrousers, .tShirtTrousers, .tShirtShorts, .tankTopShorts, .swimwear]
    }

    private func presetChip(_ preset: ClothingPreset) -> some View {
        let isSelected = model.profile.exposure.preset == preset

        return Button {
            var exposure = model.profile.exposure
            exposure.preset = preset
            // Passe par le modèle plutôt que par le profil : si une sortie est
            // en cours, le changement de tenue doit ouvrir un nouveau segment,
            // sinon la dose déjà accumulée serait recalculée à tort.
            model.updateSessionExposure(exposure)
        } label: {
            VStack(spacing: 5) {
                Image(systemName: preset.symbolName)
                    .font(.body)
                    .frame(height: 20)
                // Deux lignes toujours, quitte à ce que la seconde soit vide :
                // sans cela « Manteau » ferait une boîte plus courte que
                // « Manches longues », et la rangée serait bancale.
                Text(preset.shortTitle)
                    .font(.caption2)
                    .lineLimit(2, reservesSpace: true)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 84)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Theme.vitaminD : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected
                          ? Theme.vitaminD.opacity(0.14)
                          : Color.secondary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
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

                    // Dans l'ordre de la journée, non par mérite : c'est ainsi
                    // qu'on décide entre ce matin et après le dîner. Le meilleur
                    // créneau reste signalé par sa teinte et son étiquette.
                    ForEach(plan.chronologicalRecommendations) { item in
                        RecommendationCard(recommendation: item,
                                           timeZone: plan.timeZone,
                                           isPrimary: item.id == plan.bestRecommendation?.id)
                    }
                }
            }
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

                // La même définition que le décompte en haut de l'écran : deux
                // chiffres qui se contrediraient seraient pires qu'un seul.
                if let optimal = plan.optimalBand {
                    factRow("Fenêtre optimale", Format.interval(optimal, in: plan.timeZone))
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
        // Le décompte en tête de l'écran annonce déjà la fenêtre ; inutile de le
        // répéter ici. On dit plutôt ce que vaut l'instant présent.
        if position.elevation >= UVEngine.optimalSynthesisElevation {
            return "Rendement optimal"
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
        // Ce qui reste de la dose du jour, et non une dose entière : le seuil
        // de rougeur se franchit avec la somme de la journée.
        let remaining = max(0, 1 - model.todayTotalMEDFraction)
        guard remaining > 0.01 else { return "seuil atteint" }
        guard let seconds = DayPlanner.timeToErythema(
            from: model.now, samples: plan.samples, fraction: remaining) else {
            // Le Soleil se couchera avant que la dose suffise.
            return "hors d'atteinte"
        }
        return Format.duration(seconds)
    }

    private var burnDetail: String {
        guard model.currentRates.medFractionPerMinute > 0.0001 else {
            return "peau nue, sans protection"
        }
        return model.todayTotalMEDFraction > 0.02
            ? "en comptant ce qui est déjà dépensé"
            : "peau nue, montée du Soleil comprise"
    }
}

#Preview {
    TodayView().environment(AppModel())
}
