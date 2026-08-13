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
                    winterCard
                    list
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Historique")
        }
    }

    private var summary: some View {
        Card {
            HStack(spacing: 12) {
                MetricTile(label: "Aujourd'hui",
                           value: Format.iu(model.todayTotalIU),
                           detail: "objectif \(Int(model.profile.dailyGoalIU)) UI",
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
    private var winterCard: some View {
        if let plan = model.winterPlan {
            Card(title: plan.hasStarted ? "Hiver vitaminique" : "Avant l'hiver",
                 systemImage: "snowflake") {

                if plan.hasStarted {
                    startedContent(plan)
                } else {
                    aheadContent(plan)
                }

                Divider()
                reserveContent(plan)
            }
        }
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
            vingtaine de jours. Emmagasiner du soleil fonctionne donc à l'échelle \
            de quelques semaines, pas d'une saison : aucune stratégie d'exposition \
            ne couvre un hiver québécois entier. Ce chiffre est un indice relatif, \
            utile pour se comparer à soi-même d'une semaine à l'autre — seule une \
            prise de sang mesure un taux.
            """)
            .font(.caption2)
            .foregroundStyle(.tertiary)
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
                            Divider().padding(.vertical, 8)
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
