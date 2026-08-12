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
