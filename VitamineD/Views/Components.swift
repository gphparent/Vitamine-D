import SwiftUI

/// Carte générique, fond et coins arrondis cohérents.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Petite tuile chiffrée.
struct MetricTile: View {
    let label: String
    let value: String
    var detail: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Jauge circulaire d'indice UV.
struct UVGauge: View {
    let uvIndex: Double
    let clearSkyIndex: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 10)

            // Trait fin : ce que l'indice vaudrait sans nuages. L'écart entre les
            // deux arcs rend visible ce que les nuages retirent réellement, qui
            // est bien moins que ce que l'œil suppose.
            Circle()
                .trim(from: 0, to: min(1, clearSkyIndex / 12))
                .stroke(Color.secondary.opacity(0.35), style: .init(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0, to: min(1, uvIndex / 12))
                .stroke(Theme.uvColour(uvIndex), style: .init(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: uvIndex)

            VStack(spacing: 0) {
                Text(String(format: "%.1f", uvIndex))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("UV")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 108, height: 108)
        .accessibilityElement()
        .accessibilityLabel("Indice UV")
        .accessibilityValue(String(format: "%.1f, %@", uvIndex, Theme.uvLabel(uvIndex)))
    }
}

/// Barre de progression à deux têtes : vitamine D gagnée d'un côté, capital
/// cutané consommé de l'autre. Les voir ensemble est tout l'intérêt : la
/// question n'est jamais « combien de soleil », mais « combien de vitamine D
/// pour combien de peau ».
struct DualProgressBar: View {
    let vitaminDFraction: Double
    let medFraction: Double
    let burnLevel: SessionProgress.BurnLevel

    var body: some View {
        VStack(spacing: 10) {
            bar(label: "Vitamine D",
                value: vitaminDFraction,
                tint: Theme.vitaminD,
                trailing: Format.percent(min(1, vitaminDFraction)))

            bar(label: "Capital cutané",
                value: medFraction,
                tint: Theme.burnColour(burnLevel),
                trailing: Format.percent(min(1, medFraction)) + " de la DEM")
        }
    }

    private func bar(label: String, value: Double, tint: Color, trailing: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: 8)
        }
    }
}

/// Bandeau d'avertissement.
struct NoticeBanner: View {
    enum Kind { case info, warning, critical }

    let kind: Kind
    let title: String
    let message: String

    private var tint: Color {
        switch kind {
        case .info:     return .blue
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    private var symbol: String {
        switch kind {
        case .info:     return "info.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Carte d'un créneau recommandé.
struct RecommendationCard: View {
    let recommendation: SessionRecommendation
    let timeZone: TimeZone
    var isPrimary: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.time(recommendation.start, in: timeZone))
                    .font(isPrimary ? .largeTitle.weight(.semibold) : .title3.weight(.semibold))
                    .monospacedDigit()
                Text("pendant \(recommendation.minutes) min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if recommendation.reachesGoal {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.vitaminD)
                }
            }

            HStack(spacing: 16) {
                MetricTile(label: "Vitamine D",
                           value: Format.iu(recommendation.expectedIU),
                           tint: Theme.vitaminD)
                MetricTile(label: "Capital cutané",
                           value: Format.percent(recommendation.medFraction),
                           detail: "de la DEM")
                MetricTile(label: "UV moyen",
                           value: String(format: "%.1f", recommendation.averageUVIndex),
                           tint: Theme.uvColour(recommendation.averageUVIndex))
            }

            Text(recommendation.limitingFactor.explanation)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isPrimary ? Theme.vitaminD.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPrimary ? Theme.vitaminD.opacity(0.4) : .clear, lineWidth: 1)
        )
    }
}
