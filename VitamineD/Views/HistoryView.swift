import Charts
import SwiftUI

struct HistoryView: View {

    @Environment(AppModel.self) private var model
    @State private var editing: SessionRecord?
    @State private var isAddingForgotten = false

    private var lastFourteenDays: [(day: Date, total: Double)] {
        let calendar = model.calendar
        let today = calendar.startOfDay(for: model.now)
        return (0..<14).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return (day, model.history.totalIU(on: day, calendar: calendar))
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summary
                    chart
                    reserveCard
                    list
                }
                .padding(16)
            }
            .background(SkyBackground(
                solarElevation: model.solarPosition?.elevation ?? -90,
                cloudCover: model.currentConditions?.cloudCover ?? 0))
            .navigationTitle("Historique")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingForgotten = true
                    } label: {
                        Label("Sortie oubliée", systemImage: "plus")
                    }
                    .disabled(model.location == nil)
                }
            }
            .sheet(item: $editing) { record in
                SessionEditorView(existing: record,
                                  defaultExposure: model.profile.exposure,
                                  defaultStart: record.start)
            }
            .sheet(isPresented: $isAddingForgotten) {
                SessionEditorView(defaultExposure: model.profile.exposure,
                                  defaultStart: defaultForgottenStart)
            }
        }
    }

    /// Point de départ proposé pour une sortie oubliée : une demi-heure avant
    /// maintenant, arrondie au quart d'heure. Personne ne se souvient d'être
    /// sorti à 14 h 07, et une molette qu'on ne touche pas doit déjà proposer
    /// quelque chose de plausible.
    private var defaultForgottenStart: Date {
        let half = model.now.addingTimeInterval(-30 * 60)
        let quarter = 15.0 * 60
        return Date(timeIntervalSince1970:
                        (half.timeIntervalSince1970 / quarter).rounded() * quarter)
    }

    private var summary: some View {
        Card {
            HStack(spacing: 12) {
                MetricTile(label: "Aujourd'hui",
                           value: Format.iu(model.todayTotalWithDietIU),
                           detail: model.todayTotalWithDietIU > model.todayTotalIU
                               ? "peau et alimentation"
                               : "objectif \(Int(model.profile.dailyGoalIU)) UI",
                           tint: Theme.vitaminD)
                MetricTile(label: "7 derniers jours",
                           value: Format.iu(model.history.totalIU(lastDays: 7, from: model.now)))
                MetricTile(label: "Moyenne / jour",
                           value: Format.iu(model.history.totalIU(lastDays: 7, from: model.now) / 7))
            }
        }
    }

    private var chart: some View {
        Card(title: "Deux dernières semaines", systemImage: "chart.bar") {
            Chart {
                ForEach(lastFourteenDays, id: \.day) { entry in
                    BarMark(
                        x: .value("Jour", entry.day, unit: .day),
                        y: .value("UI", entry.total)
                    )
                    .foregroundStyle(entry.total >= model.profile.dailyGoalIU
                                     ? Theme.vitaminD
                                     : Theme.vitaminD.opacity(0.35))
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Objectif", model.profile.dailyGoalIU))
                    .foregroundStyle(.secondary)
                    .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("objectif")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 3)) { value in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .frame(height: 160)
        }
    }

    // MARK: - Réserves et hiver

    /// Ce qui reste en circulation de tout ce qui a été synthétisé, et ce
    /// qu'il en adviendra d'ici l'hiver.
    ///
    /// Un total hebdomadaire ne dit rien d'utile, parce qu'une réserve ne
    /// s'additionne pas : elle fuit. Le 25-hydroxyvitamine D circulant perd la
    /// moitié de sa valeur en une quinzaine de jours, ce qui change tout — deux
    /// sorties identiques à trois semaines d'écart ne valent pas le double
    /// d'une seule, et c'est la régularité, non l'intensité, qui tient un
    /// plateau.
    ///
    /// Le chiffre est présenté en **apport quotidien équivalent** plutôt qu'en
    /// réservoir : c'est la seule forme qui se compare à quelque chose de
    /// connu, à savoir la fourchette des apports recommandés.
    ///
    /// Deux cartes se partageaient autrefois ce sujet — « Vos réserves » et
    /// « Avant l'hiver » — avec chacune sa réserve, son graphique et sa mise
    /// en garde sur la demi-vie, répétée presque mot pour mot. Une seule
    /// courbe dit tout : le passé, la projection au rythme actuel, et la zone
    /// d'hiver où l'apport tombe à zéro.
    private var reserveCard: some View {
        let now = model.now
        let reserve = WinterPlanner.reserve(on: now, history: model.history)
        let daily = WinterPlanner.equivalentDailyIU(reserve: reserve)
        let cadence = WinterPlanner.recentDailyIU(on: now, history: model.history)
        let plan = model.winterPlan
        let hasStarted = plan?.hasStarted == true

        return Card(title: hasStarted ? "Hiver vitaminique" : "Réserves et hiver",
                    systemImage: hasStarted ? "snowflake" : "drop.halffull") {
            HStack(spacing: 12) {
                MetricTile(label: "Apport équivalent",
                           value: reserve > 1 ? "\(Int(daily.rounded())) UI/j" : "—",
                           detail: "en circulation",
                           tint: Theme.vitaminD)
                if let plan {
                    if plan.hasStarted {
                        MetricTile(label: "Fin de l'hiver",
                                   value: Format.shortDate(plan.winter.end,
                                                           in: model.calendar.timeZone),
                                   detail: "retour de la synthèse",
                                   tint: .blue)
                        MetricTile(label: "Au cœur de l'hiver",
                                   value: reserve > 1 ? Format.percent(plan.midwinterFraction) : "—",
                                   detail: "de la réserve actuelle")
                    } else {
                        MetricTile(label: "Jours utiles",
                                   value: "\(plan.usefulDaysLeft)",
                                   detail: "avant l'hiver, le "
                                       + Format.shortDate(plan.winter.start,
                                                          in: model.calendar.timeZone),
                                   tint: .blue)
                        MetricTile(label: "À l'entrée de l'hiver",
                                   value: "\(equivalentAtWinter(plan, cadence: cadence)) UI/j",
                                   detail: "au rythme actuel")
                    }
                } else {
                    MetricTile(label: "Recommandé",
                               value: "\(Int(VitaminDTarget.dietaryReferenceUnder70))"
                                   + " à \(Int(VitaminDTarget.clinicalReferenceUpper))",
                               detail: "UI/j selon la source")
                    MetricTile(label: "Rythme récent",
                               value: "\(Int(cadence.rounded())) UI/j",
                               detail: "sur deux semaines")
                }
            }

            if reserve > 1 || plan != nil {
                reserveChart(reserve: reserve, cadence: cadence, plan: plan)
            }

            if reserve > 1 {
                Text(reserveVerdict(daily: daily))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Aucune sortie enregistrée pour l'instant. La réserve se "
                     + "calcule à partir des sorties terminées dans l'application.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let plan {
                GoldRule()
                Text(plan.hasStarted ? winterSentence(plan) : closureSentence(plan))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(cadenceAdvice(plan, daily: cadence))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if reserve > 1 {
                    Text(decaySentence(plan))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if model.profile.readsHealthKit, model.health.dietaryVitaminDIU > 0 {
                GoldRule()
                Text("Santé rapporte en plus "
                     + Format.iu(model.health.dietaryVitaminDIU)
                     + " d'apport alimentaire aujourd'hui. Les deux voies aboutissent "
                     + "à la même molécule, et c'est celle-là qui prendra le relais "
                     + "quand la courbe ci-dessus touchera le fond.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GoldRule()

            Text("""
            Ce n'est pas une concentration sanguine, et l'application n'a aucun \
            moyen de la connaître : c'est un modèle qui applique la décroissance \
            publiée — la moitié en une quinzaine de jours — à ce que vous avez \
            synthétisé. Il sert à se comparer à soi-même d'une semaine à l'autre, \
            pas à remplacer une prise de sang.
            """)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Apport équivalent à l'entrée de l'hiver, si le rythme actuel se maintient.
    private func equivalentAtWinter(_ plan: WinterPlanner.Plan, cadence: Double) -> Int {
        let atWinter = WinterPlanner.reserve(
            after: Double(plan.daysUntilStart), starting: plan.reserve, dailyIU: cadence)
        return Int(WinterPlanner.equivalentDailyIU(reserve: atWinter).rounded())
    }

    /// Quatre-vingt-dix jours derrière ; devant, jusqu'à la fin de l'hiver
    /// s'il y en a un, trente jours sinon.
    ///
    /// La projection suit le rythme des deux dernières semaines jusqu'à
    /// l'entrée de l'hiver, puis ne fait plus que descendre : c'est la forme
    /// qui répond à la vraie question, non pas « combien emmagasiner » mais
    /// « à quelle hauteur entrer dans la saison creuse ».
    private func reserveChart(reserve: Double,
                              cadence: Double,
                              plan: WinterPlanner.Plan?) -> some View {
        let now = model.now
        let step = 2 * 86_400.0
        let past = WinterPlanner.series(from: now.addingTimeInterval(-90 * 86_400),
                                        to: now,
                                        history: model.history,
                                        step: step)
        let ahead: [(date: Date, reserve: Double)]
        if let plan {
            ahead = WinterPlanner.forecast(
                from: now,
                reserve: reserve,
                dailyIU: cadence,
                winterStart: plan.hasStarted ? now : plan.winter.start,
                through: plan.winter.end,
                step: step)
        } else {
            ahead = WinterPlanner.projection(from: now,
                                             reserve: reserve,
                                             through: now.addingTimeInterval(30 * 86_400),
                                             step: step)
        }

        let low = VitaminDTarget.dietaryReferenceUnder70
        let high = VitaminDTarget.clinicalReferenceUpper
        let peak = (past + ahead)
            .map { WinterPlanner.equivalentDailyIU(reserve: $0.reserve) }
            .max() ?? 0
        let ceiling = max(high * 1.15, peak * 1.2)

        return Chart {
            if let plan {
                RectangleMark(
                    xStart: .value("Début", plan.hasStarted ? now : plan.winter.start),
                    xEnd: .value("Fin", plan.winter.end),
                    yStart: .value("Bas", 0.0),
                    yEnd: .value("Haut", ceiling)
                )
                .foregroundStyle(Color.blue.opacity(0.10))
                .annotation(position: .overlay, alignment: .topTrailing, spacing: 4) {
                    Text("hiver")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(past, id: \.date) { point in
                AreaMark(x: .value("Date", point.date),
                         y: .value("Apport équivalent",
                                   WinterPlanner.equivalentDailyIU(reserve: point.reserve)))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Theme.vitaminD.opacity(0.45), Theme.vitaminD.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom))
            }

            ForEach(ahead, id: \.date) { point in
                LineMark(x: .value("Date", point.date),
                         y: .value("Apport équivalent",
                                   WinterPlanner.equivalentDailyIU(reserve: point.reserve)),
                         series: .value("Série", "projection"))
                    .foregroundStyle(Theme.vitaminD.opacity(0.6))
                    .lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.monotone)
            }

            // Une bande, et non un trait : les institutions ne s'accordent pas
            // sur la cible, et afficher l'une des deux comme « la » référence
            // donnerait à un chiffre contesté une autorité qu'il n'a pas.
            RectangleMark(
                yStart: .value("Bas", low),
                yEnd: .value("Haut", high))
                .foregroundStyle(.primary.opacity(0.10))
                .annotation(position: .top, alignment: .leading, spacing: 1) {
                    Text("fourchette des apports recommandés")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            RuleMark(x: .value("Aujourd'hui", now))
                .foregroundStyle(.primary.opacity(0.5))
                .lineStyle(.init(lineWidth: 1))
        }
        .chartYScale(domain: 0.0...ceiling)
        .chartXAxis {
            AxisMarks(values: .stride(by: .month)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(Format.monthAbbreviation(date, in: model.calendar.timeZone))
                    }
                }
            }
        }
        .frame(height: 160)
    }

    private func reserveVerdict(daily: Double) -> String {
        let low = VitaminDTarget.dietaryReferenceUnder70
        let high = VitaminDTarget.clinicalReferenceUpper
        let value = Int(daily.rounded())

        if daily >= high {
            return "Vos sorties soutiennent l'équivalent de \(value) UI par jour, "
                + "au-dessus de la fourchette entière des apports recommandés. Le "
                + "trait pointillé montre la suite au rythme actuel."
        }
        if daily >= low {
            return "Vos sorties soutiennent l'équivalent de \(value) UI par jour, "
                + "dans la fourchette des apports recommandés — plus près de sa borne "
                + "basse ou haute selon l'institution qu'on retient. Le trait pointillé "
                + "montre la suite au rythme actuel."
        }
        let share = Format.percent(daily / low)
        return "Vos sorties soutiennent l'équivalent de \(value) UI par jour, "
            + "soit \(share) de la borne la plus basse. Le reste doit venir de "
            + "l'assiette ou d'un supplément — et le trait pointillé montre la "
            + "suite au rythme actuel."
    }

    /// Ce qu'il faudrait faire, dit en sorties plutôt qu'en unités.
    ///
    /// Le régime permanent du réservoir vaut apport quotidien × constante de
    /// temps. Viser l'objectif quotidien revient donc à viser une réserve de
    /// `objectif × 29 jours` — et l'écart entre le rythme actuel et celui-là se
    /// traduit en un nombre de sorties par semaine, seule forme sous laquelle
    /// un conseil de ce genre est utilisable.
    private func cadenceAdvice(_ plan: WinterPlanner.Plan, daily: Double) -> String {
        guard !plan.hasStarted else {
            return "L'apport est nul jusqu'au printemps : la courbe ne fait plus que "
                + "descendre. C'est la période où l'alimentation et la supplémentation "
                + "prennent le relais."
        }

        let goal = model.profile.dailyGoalIU
        guard goal > 0 else { return "Fixez un objectif quotidien pour obtenir un rythme." }

        let sessionsPerWeek = min(7.0, max(0, (goal - daily) / max(goal, 1)) * 7)
        let equivalent = equivalentAtWinter(plan, cadence: daily)

        var advice = "À ce rythme, vous entreriez dans l'hiver avec l'équivalent de "
        advice += "\(equivalent) UI par jour. "
        if sessionsPerWeek < 0.5 {
            advice += "C'est déjà le niveau de votre objectif : tenez-le jusqu'au "
            advice += "\(Format.shortDate(plan.winter.start, in: model.calendar.timeZone))."
        } else {
            let rounded = Int(sessionsPerWeek.rounded())
            advice += "Environ \(max(1, rounded)) sortie\(rounded > 1 ? "s" : "") de plus par "
            advice += "semaine d'ici là vous amènerait au niveau de votre objectif. "
            advice += "La régularité compte davantage que l'intensité : le réservoir "
            advice += "tend vers l'apport moyen, et une sortie héroïque ne survit pas "
            advice += "à six semaines."
        }
        return advice
    }

    /// Assemblée par affectations : les longues concaténations mêlant littéraux
    /// et appels de fonction font capituler l'inférence de type de Swift.
    private func closureSentence(_ plan: WinterPlanner.Plan) -> String {
        let zone = model.calendar.timeZone
        let start = Format.shortDate(plan.winter.start, in: zone)
        let last = Format.shortDate(plan.winter.end.addingTimeInterval(-1), in: zone)
        var sentence = "Passé le \(start), le Soleil ne monte plus assez haut : "
        sentence += "aucune durée d'exposition ne produira de vitamine D "
        sentence += "avant le \(last)."
        return sentence
    }

    private func winterSentence(_ plan: WinterPlanner.Plan) -> String {
        let last = Format.shortDate(plan.winter.end.addingTimeInterval(-1),
                                    in: model.calendar.timeZone)
        var sentence = "Le Soleil reste sous "
            + "\(Format.degrees(UVEngine.vitaminDWinterElevation)) jusqu'au \(last). "
            + "Sortir garde tout "
        sentence += "son intérêt pour l'humeur, le sommeil et l'horloge interne — "
        sentence += "mais pas pour la vitamine D, qu'il faut chercher dans l'assiette "
        sentence += "ou dans un supplément."
        return sentence
    }

    private func decaySentence(_ plan: WinterPlanner.Plan) -> String {
        guard plan.reserve > 1 else {
            return "Aucune sortie enregistrée pour l'instant : la réserve se calcule "
                + "à partir des sorties terminées dans l'application."
        }
        let remaining = Format.percent(plan.midwinterFraction)
        let date = Format.shortDate(plan.midwinter, in: model.calendar.timeZone)
        return "Sans nouvelle exposition, il en restera environ \(remaining) au \(date), "
            + "au cœur de l'hiver."
    }

    @ViewBuilder
    private var list: some View {
        if model.history.isEmpty {
            Card {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Aucune sortie enregistrée")
                        .font(.headline)
                    Text("Les sorties apparaîtront ici une fois terminées. "
                         + "Vous pouvez aussi en saisir une que vous avez "
                         + "oublié de chronométrer.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Ajouter une sortie oubliée") { isAddingForgotten = true }
                        .font(.footnote.weight(.medium))
                        .disabled(model.location == nil)
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            Card(title: "Sorties", systemImage: "list.bullet") {
                VStack(spacing: 0) {
                    ForEach(model.history.prefix(30)) { record in
                        row(record)
                        if record.id != model.history.prefix(30).last?.id {
                            GoldRule().padding(.vertical, 8)
                        }
                    }
                }
            }
        }
    }

    private func row(_ record: SessionRecord) -> some View {
        Button {
            editing = record
        } label: {
            rowContent(record)
        }
        .buttonStyle(.plain)
    }

    private func rowContent(_ record: SessionRecord) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.start.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                    .font(.subheadline.weight(.medium))
                Text("\(record.minutes) min · \(record.locationName) · "
                     + "\(Int(record.exposedBodyPercentage)) % de peau")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Une sortie reconstituée repose sur un indice UV modélisé et
                // sur une tenue déclarée de mémoire. Elle vaut moins qu'une
                // mesure, et la liste ne doit pas les confondre.
                if record.isRetroactive {
                    Label("saisie à la main", systemImage: "pencil")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Format.iu(record.vitaminDIU))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.vitaminD)
                Text(Format.percent(record.medFraction) + " DEM")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(record.medFraction > 0.8 ? .red : .secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)
        }
        .contentShape(.rect)
    }
}

#Preview {
    HistoryView().environment(AppModel())
}
