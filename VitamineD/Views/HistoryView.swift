import Charts
import SwiftUI

struct HistoryView: View {

    @Environment(AppModel.self) private var model

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
                    winterCard
                    list
                }
                .padding(16)
            }
            .background(SkyBackground(
                solarElevation: model.solarPosition?.elevation ?? -90,
                cloudCover: model.currentConditions?.cloudCover ?? 0))
            .navigationTitle("Historique")
        }
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

    // MARK: - Avant l'hiver

    /// Plan d'avant-hiver.
    ///
    /// Le compteur quotidien ne dit rien de la saison, et c'est précisément ce
    /// qui manque au Québec : on peut suivre chaque créneau de mai à septembre
    /// et se retrouver à plat en janvier. Cette carte rend visibles les deux
    /// choses qui décident vraiment — le nombre de jours utiles qui restent, et
    /// la vitesse à laquelle ce qu'on a déjà fabriqué disparaît.
    @ViewBuilder
    // MARK: - Réserves

    /// Ce qui reste en circulation de tout ce qui a été synthétisé.
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
    /// connu, à savoir l'apport de référence de Santé Canada.
    private var reserveCard: some View {
        let now = model.now
        let reserve = WinterPlanner.reserve(on: now, history: model.history)
        let daily = WinterPlanner.equivalentDailyIU(reserve: reserve)
        let recent = WinterPlanner.recentDailyIU(on: now, history: model.history)

        return Card(title: "Vos réserves", systemImage: "drop.halffull") {
            HStack(spacing: 12) {
                MetricTile(label: "Apport équivalent",
                           value: reserve > 1 ? "\(Int(daily.rounded())) UI/j" : "—",
                           detail: "en circulation",
                           tint: Theme.vitaminD)
                MetricTile(label: "Référence",
                           value: "\(Int(VitaminDTarget.referenceIntakeUnder70)) UI/j",
                           detail: "Santé Canada")
                MetricTile(label: "Demi-vie",
                           value: "\(Int(WinterPlanner.halfLifeDays)) jours",
                           detail: "du 25(OH)D")
            }

            if reserve > 1 {
                reserveChart(reserve: reserve, dailyIU: recent)
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

            GoldRule()

            Text("""
            Ce n'est pas une concentration sanguine, et l'application n'a aucun \
            moyen de la connaître : c'est un modèle qui applique la décroissance \
            publiée à ce que vous avez synthétisé. Il sert à se comparer à \
            soi-même d'une semaine à l'autre, pas à remplacer une prise de sang.
            """)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Quatre-vingt-dix jours derrière, trente devant.
    private func reserveChart(reserve: Double, dailyIU: Double) -> some View {
        let now = model.now
        let past = WinterPlanner.series(from: now.addingTimeInterval(-90 * 86_400),
                                        to: now,
                                        history: model.history,
                                        step: 2 * 86_400)
        let ahead = WinterPlanner.projection(from: now,
                                             reserve: reserve,
                                             through: now.addingTimeInterval(30 * 86_400),
                                             step: 2 * 86_400)

        return Chart {
            ForEach(past, id: \.date) { point in
                AreaMark(x: .value("Date", point.date),
                         y: .value("Apport équivalent",
                                   WinterPlanner.equivalentDailyIU(reserve: point.reserve)))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Theme.vitaminD.opacity(0.45), Theme.vitaminD.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom))
            }

            // La projection suppose l'arrêt de toute exposition : c'est la
            // pente qu'on subit, pas celle qu'on suivra.
            ForEach(ahead, id: \.date) { point in
                LineMark(x: .value("Date", point.date),
                         y: .value("Apport équivalent",
                                   WinterPlanner.equivalentDailyIU(reserve: point.reserve)),
                         series: .value("Série", "projection"))
                    .foregroundStyle(Theme.vitaminD.opacity(0.6))
                    .lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
            }

            RuleMark(y: .value("Référence", VitaminDTarget.referenceIntakeUnder70))
                .foregroundStyle(.primary.opacity(0.45))
                .lineStyle(.init(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 1) {
                    Text("apport de référence")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

            RuleMark(x: .value("Aujourd'hui", now))
                .foregroundStyle(.primary.opacity(0.5))
                .lineStyle(.init(lineWidth: 1))
        }
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
        .frame(height: 150)
    }

    private func reserveVerdict(daily: Double) -> String {
        let reference = VitaminDTarget.referenceIntakeUnder70
        let value = Int(daily.rounded())
        if daily >= reference {
            return "Vos sorties soutiennent l'équivalent de \(value) UI par jour, "
                + "soit au moins l'apport de référence. Le trait pointillé montre "
                + "ce qu'il en resterait si vous cessiez de sortir dès aujourd'hui."
        }
        let share = Format.percent(daily / reference)
        return "Vos sorties soutiennent l'équivalent de \(value) UI par jour, "
            + "soit \(share) de l'apport de référence. Le reste doit venir de "
            + "l'assiette ou d'un supplément — et le trait pointillé montre la "
            + "pente si vous cessiez de sortir dès aujourd'hui."
    }

    private var winterCard: some View {
        if let plan = model.winterPlan {
            Card(title: plan.hasStarted ? "Hiver vitaminique" : "Avant l'hiver",
                 systemImage: "snowflake") {

                if plan.hasStarted {
                    startedContent(plan)
                } else {
                    aheadContent(plan)
                }

                GoldRule()
                reserveContent(plan)
                GoldRule()
                forecastContent(plan)
            }
        }
    }

    // MARK: - Réserves à venir

    /// Ce que devient la réserve d'ici l'hiver, au rythme actuel.
    ///
    /// La courbe a une forme caractéristique — un plateau, puis une chute à
    /// l'entrée de l'hiver — et c'est elle qui répond à la vraie question. Il
    /// ne s'agit pas de savoir combien emmagasiner, mais à quelle hauteur
    /// entrer dans la saison creuse : passé le seuil, l'apport tombe à zéro et
    /// seule la décroissance continue.
    @ViewBuilder
    private func forecastContent(_ plan: WinterPlanner.Plan) -> some View {
        let daily = WinterPlanner.recentDailyIU(on: model.now, history: model.history)
        let points = WinterPlanner.forecast(
            from: model.now,
            reserve: plan.reserve,
            dailyIU: daily,
            winterStart: plan.hasStarted ? model.now : plan.winter.start,
            through: plan.winter.end)

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Réserves à venir")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("rythme actuel : \(Int(daily.rounded())) UI/jour")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Chart {
                if !plan.hasStarted {
                    RectangleMark(
                        xStart: .value("Début", plan.winter.start),
                        xEnd: .value("Fin", plan.winter.end),
                        yStart: .value("Bas", 0.0),
                        yEnd: .value("Haut", forecastCeiling(points))
                    )
                    .foregroundStyle(Color.blue.opacity(0.10))
                }

                ForEach(points, id: \.date) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Réserve", point.reserve)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Theme.vitaminD.opacity(0.40), Theme.vitaminD.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                }
            }
            .chartYScale(domain: 0.0...forecastCeiling(points))
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 1)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Format.monthAbbreviation(date, in: model.calendar.timeZone))
                        }
                    }
                }
            }
            .frame(height: 120)

            Text(cadenceAdvice(plan, daily: daily))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
        }
    }

    private func forecastCeiling(_ points: [(date: Date, reserve: Double)]) -> Double {
        let peak = points.map(\.reserve).max() ?? 0
        return max(1_000, peak * 1.2)
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
        let atWinter = WinterPlanner.reserve(
            after: Double(plan.daysUntilStart), starting: plan.reserve, dailyIU: daily)
        let equivalent = Int(WinterPlanner.equivalentDailyIU(reserve: atWinter).rounded())

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

    private func aheadContent(_ plan: WinterPlanner.Plan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                MetricTile(label: "L'hiver commence",
                           value: "\(plan.daysUntilStart) j",
                           detail: Format.shortDate(plan.winter.start, in: model.calendar.timeZone),
                           tint: .blue)
                MetricTile(label: "Jours utiles",
                           value: "\(plan.usefulDaysLeft)",
                           detail: "où la synthèse est possible")
                MetricTile(label: "Dont optimaux",
                           value: "\(plan.optimalDaysLeft)",
                           detail: "Soleil au-dessus de 45°",
                           tint: Theme.vitaminD)
            }

            Text(closureSentence(plan))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
        var sentence = "Le Soleil reste sous 25° jusqu'au \(last). Sortir garde tout "
        sentence += "son intérêt pour l'humeur, le sommeil et l'horloge interne — "
        sentence += "mais pas pour la vitamine D, qu'il faut chercher dans l'assiette "
        sentence += "ou dans un supplément."
        return sentence
    }

    private func startedContent(_ plan: WinterPlanner.Plan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nous y sommes")
                .font(.headline)
                .foregroundStyle(.blue)
            Text(winterSentence(plan))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Ce que devient ce qui a déjà été fabriqué.
    private func reserveContent(_ plan: WinterPlanner.Plan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Réserve estimée")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(reserveText(plan))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.vitaminD)
            }

            Text(decaySentence(plan))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("""
            Le 25-hydroxyvitamine D circulant perd la moitié de sa valeur en une \
            quinzaine de jours. Emmagasiner du soleil fonctionne donc à l'échelle \
            de quelques semaines, pas d'une saison : aucune stratégie d'exposition \
            ne couvre un hiver québécois entier. Ce chiffre est un indice relatif, \
            utile pour se comparer à soi-même d'une semaine à l'autre — seule une \
            prise de sang mesure un taux.
            """)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reserveText(_ plan: WinterPlanner.Plan) -> String {
        guard plan.reserve > 1 else { return "—" }
        let daily = WinterPlanner.equivalentDailyIU(reserve: plan.reserve)
        return "≈ \(Int(daily.rounded())) UI/jour"
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
                    Text("Les sorties apparaîtront ici une fois terminées.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(record.start.formatted(.dateTime.weekday(.abbreviated).day().month().hour().minute()))
                    .font(.subheadline.weight(.medium))
                Text("\(record.minutes) min · \(record.locationName) · "
                     + "\(Int(record.exposedBodyPercentage)) % de peau")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
    }
}

#Preview {
    HistoryView().environment(AppModel())
}
