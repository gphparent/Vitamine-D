import Charts
import SwiftUI

/// Courbe de la journée : indice UV en aire colorée, hauteur du Soleil en trait,
/// fenêtres de synthèse en bandes, instant courant en repère.
///
/// Superposer les deux grandeurs est le point de la vue : elles ne culminent pas
/// tout à fait ensemble par temps variable, et c'est justement l'écart qui
/// explique pourquoi un après-midi lumineux peut ne rien valoir pour la
/// vitamine D.
struct DayChart: View {

    let plan: DayPlan
    let now: Date
    @State private var selected: Date?

    private var visibleSamples: [TimelineSample] {
        plan.samples.filter { $0.solarElevation > -4 }
    }

    private var selectedSample: TimelineSample? {
        guard let selected else { return nil }
        return plan.samples.min {
            abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected))
        }
    }

    private var maxUV: Double { max(2, (plan.peakUVIndex * 1.25).rounded(.up)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Chart {
                ForEach(plan.windows) { window in
                    RectangleMark(
                        xStart: .value("Début", window.interval.start),
                        xEnd: .value("Fin", window.interval.end),
                        yStart: .value("Bas", 0.0),
                        yEnd: .value("Haut", maxUV)
                    )
                    .foregroundStyle(Theme.windowColour(window.quality).opacity(0.12))
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

                // Seuil de la règle de l'ombre.
                RuleMark(y: .value("Seuil", UVEngine.optimalSynthesisElevation / 90 * maxUV))
                    .foregroundStyle(.tertiary)
                    .lineStyle(.init(lineWidth: 0.5, dash: [2, 4]))

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
            .frame(height: 190)

            legend
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            if let sample = selectedSample {
                Text(Format.time(sample.date, in: plan.timeZone))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text("UV \(String(format: "%.1f", sample.uvIndex)) · Soleil \(Format.degrees(sample.solarElevation))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(sample.rates.vitaminDIUPerMinute > 0.5
                     ? "\(Int(sample.rates.vitaminDIUPerMinute)) UI/min"
                     : "aucune synthèse")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(sample.rates.vitaminDIUPerMinute > 0.5 ? Theme.vitaminD : .secondary)
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

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(colour: Theme.uvColour(plan.peakUVIndex), label: "Indice UV", filled: true)
            legendItem(colour: .secondary, label: "Hauteur du Soleil", filled: false)
            legendItem(colour: Theme.windowColour(.optimal), label: "Fenêtre utile", filled: true)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem(colour: Color, label: String, filled: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(filled ? colour.opacity(0.6) : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(colour, style: .init(lineWidth: 1, dash: filled ? [] : [2, 2]))
                )
                .frame(width: 14, height: 8)
            Text(label)
        }
    }
}
