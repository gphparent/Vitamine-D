import Charts
import SwiftUI

/// Courbe de la journée : indice UV en aire colorée, hauteur du Soleil en trait,
/// et surtout des bandes de fond qui disent d'un coup d'œil ce que vaut chaque
/// heure.
///
/// Superposer indice UV et hauteur solaire est le point de la vue : les deux ne
/// culminent pas tout à fait ensemble par temps variable, et c'est justement
/// l'écart qui explique qu'un après-midi lumineux puisse ne rien valoir pour la
/// vitamine D.
struct DayChart: View {

    let plan: DayPlan
    let now: Date
    /// Instant au-delà duquel une exposition ininterrompue commencée maintenant
    /// aurait franchi la dose érythémale minimale.
    let burnHorizon: Date?

    @State private var selected: Date?

    init(plan: DayPlan, now: Date) {
        self.plan = plan
        self.now = now
        self.burnHorizon = DayPlanner.timeToErythema(from: now, samples: plan.samples)
            .map { now.addingTimeInterval($0) }
    }

    private var visibleSamples: [TimelineSample] {
        plan.samples.filter { $0.solarElevation > -4 }
    }

    private var selectedSample: TimelineSample? {
        guard let selected else { return nil }
        return plan.samples.min {
            abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected))
        }
    }

    private var bands: [(interval: DateInterval, band: DayPlanner.YieldBand)] {
        DayPlanner.yieldBands(from: plan.samples)
    }

    private var maxUV: Double { max(2, (plan.peakUVIndex * 1.25).rounded(.up)) }

    private var dayEnd: Date? { plan.samples.last?.date }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Chart {
                // Fond : ce que vaut chaque heure. Le rendement ne dépendant que
                // de la hauteur du Soleil, ces bandes sont les mêmes quel que
                // soit le temps qu'il fait.
                ForEach(Array(bands.enumerated()), id: \.offset) { _, entry in
                    RectangleMark(
                        xStart: .value("Début", entry.interval.start),
                        xEnd: .value("Fin", entry.interval.end),
                        yStart: .value("Bas", 0.0),
                        yEnd: .value("Haut", maxUV)
                    )
                    .foregroundStyle(Theme.yieldColour(entry.band).opacity(entry.band == .negligible ? 0.07 : 0.16))
                }

                // Zone de risque : après cet instant, être resté dehors sans
                // interruption depuis maintenant suffit à brûler.
                if let burnHorizon, let dayEnd, burnHorizon < dayEnd {
                    RectangleMark(
                        xStart: .value("Début", burnHorizon),
                        xEnd: .value("Fin", dayEnd),
                        yStart: .value("Bas", 0.0),
                        yEnd: .value("Haut", maxUV)
                    )
                    .foregroundStyle(.red.opacity(0.10))

                    RuleMark(x: .value("Seuil de brûlure", burnHorizon))
                        .foregroundStyle(.red.opacity(0.65))
                        .lineStyle(.init(lineWidth: 1.5, dash: [5, 3]))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("brûlure")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.red)
                        }
                }

                ForEach(visibleSamples) { sample in
                    AreaMark(
                        x: .value("Heure", sample.date),
                        y: .value("Indice UV", sample.uvIndex)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Theme.uvColour(plan.peakUVIndex).opacity(0.45),
                                     Theme.uvColour(plan.peakUVIndex).opacity(0.04)],
                            startPoint: .top, endPoint: .bottom)
                    )
                    .interpolationMethod(.catmullRom)
                }

                ForEach(visibleSamples) { sample in
                    LineMark(
                        x: .value("Heure", sample.date),
                        y: .value("Hauteur", sample.solarElevation / 90 * maxUV)
                    )
                    .foregroundStyle(.secondary)
                    .lineStyle(.init(lineWidth: 1.5, dash: [4, 3]))
                    .interpolationMethod(.catmullRom)
                }

                RuleMark(x: .value("Maintenant", now))
                    .foregroundStyle(Theme.vitaminD)
                    .lineStyle(.init(lineWidth: 1.5))

                if let selectedSample {
                    RuleMark(x: .value("Sélection", selectedSample.date))
                        .foregroundStyle(.primary.opacity(0.35))
                    PointMark(
                        x: .value("Heure", selectedSample.date),
                        y: .value("Indice UV", selectedSample.uvIndex)
                    )
                    .foregroundStyle(Theme.uvColour(selectedSample.uvIndex))
                }
            }
            .chartYScale(domain: 0...maxUV)
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let uv = value.as(Double.self) {
                            Text(String(format: "%.0f", uv))
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Format.time(date, in: plan.timeZone))
                        }
                    }
                }
            }
            .frame(height: 200)

            legend
            footnote
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let sample = selectedSample {
                Text(Format.time(sample.date, in: plan.timeZone))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text("UV \(String(format: "%.1f", sample.uvIndex)) · Soleil \(Format.degrees(sample.solarElevation))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(DayPlanner.YieldBand(solarElevation: sample.solarElevation).shortTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.yieldColour(
                        DayPlanner.YieldBand(solarElevation: sample.solarElevation)))
            } else {
                Text("Courbe du jour")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Touchez la courbe")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Légende

    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 14) {
                legendItem(colour: Theme.uvColour(plan.peakUVIndex), label: "Indice UV", filled: true)
                legendItem(colour: .secondary, label: "Hauteur du Soleil", filled: false)
                if burnHorizon != nil {
                    legendItem(colour: .red, label: "Zone de brûlure", filled: true)
                }
            }
            HStack(spacing: 14) {
                ForEach([DayPlanner.YieldBand.negligible, .partial, .optimal], id: \.self) { band in
                    legendItem(colour: Theme.yieldColour(band), label: band.shortTitle, filled: true)
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(colour: Color, label: String, filled: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(filled ? colour.opacity(0.5) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(colour, style: .init(lineWidth: 1, dash: filled ? [] : [2, 2]))
                )
                .frame(width: 14, height: 8)
            Text(label)
        }
    }

    private var footnote: some View {
        Text(burnHorizon == nil
             ? "Les bandes de fond donnent le rendement — vitamine D gagnée par unité "
               + "de capital cutané —, qui ne dépend que de la hauteur du Soleil. "
               + "Aujourd'hui, rester dehors sans interruption à partir de maintenant "
               + "ne suffirait pas à brûler avant le coucher."
             : "Les bandes de fond donnent le rendement — vitamine D gagnée par unité "
               + "de capital cutané —, qui ne dépend que de la hauteur du Soleil. "
               + "La zone rouge marque l'instant où, resté dehors sans interruption "
               + "depuis maintenant, vous auriez atteint le seuil de rougeur.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
