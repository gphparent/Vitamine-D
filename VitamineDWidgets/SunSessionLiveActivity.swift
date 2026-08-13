import ActivityKit
import SwiftUI
import WidgetKit

/// Or de la vitamine D, repris de l'application.
///
/// L'extension est un programme distinct : elle ne voit ni `Theme` ni quoi que
/// ce soit d'autre de l'application. Cette poignée de constantes est donc
/// redéfinie ici, et c'est la seule duplication acceptée.
private enum Palette {
    static let vitaminD = Color(red: 0.95, green: 0.72, blue: 0.20)
    static let burn = Color(red: 0.90, green: 0.35, blue: 0.25)

    static func burnTint(_ fraction: Double) -> Color {
        switch fraction {
        case ..<0.5:  return Color(red: 0.30, green: 0.66, blue: 0.42)
        case ..<0.75: return Color(red: 0.95, green: 0.72, blue: 0.20)
        case ..<1:    return .orange
        default:      return burn
        }
    }
}

struct SunSessionLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SunSessionAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(Palette.vitaminD)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Gauge(value: context.state.goalFraction) {
                        Image(systemName: "sun.max.fill")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(Palette.vitaminD)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Gauge(value: context.state.burnFraction) {
                        Image(systemName: "flame")
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .tint(Palette.burnTint(context.state.burnFraction))
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text("\(Int(context.state.vitaminDIU.rounded())) UI")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(Palette.vitaminD)
                        Text(context.attributes.locationName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    CountdownLine(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "sun.max.fill")
                    .foregroundStyle(Palette.vitaminD)
            } compactTrailing: {
                CompactCountdown(state: context.state)
            } minimal: {
                Image(systemName: context.state.isPressing ? "flame.fill" : "sun.max.fill")
                    .foregroundStyle(context.state.isPressing
                                     ? Palette.burnTint(context.state.burnFraction)
                                     : Palette.vitaminD)
            }
            .keylineTint(Palette.vitaminD)
        }
    }
}

// MARK: - Écran verrouillé

private struct LockScreenView: View {
    let attributes: SunSessionAttributes
    let state: SunSessionAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Label("Au soleil", systemImage: "sun.max.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.vitaminD)
                Spacer()
                Text(attributes.locationName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            CountdownLine(state: state)

            bar(label: "Vitamine D",
                detail: "\(Int(state.vitaminDIU.rounded())) sur \(Int(state.goalIU.rounded())) UI",
                fraction: state.goalFraction,
                tint: Palette.vitaminD)

            bar(label: "Capital cutané",
                detail: "\(Int((state.medFraction * 100).rounded())) % de la DEM",
                fraction: state.burnFraction,
                tint: Palette.burnTint(state.burnFraction))
        }
        .padding(16)
    }

    private func bar(label: String, detail: String, fraction: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.18))
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Décompte

/// Le décompte s'anime tout seul.
///
/// `Text(timerInterval:)` est rendu par le système, qui fait défiler les
/// chiffres sans que l'application soit réveillée. C'est ce qui permet à
/// l'affichage de rester juste à la seconde près pendant une heure de soleil
/// sans consommer la moindre mise à jour du budget d'ActivityKit.
private struct CountdownLine: View {
    let state: SunSessionAttributes.ContentState

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let countdown = state.countdown {
                Text(timerInterval: countdown, countsDown: true)
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Palette.burnTint(state.burnFraction))
                    .frame(maxWidth: 90, alignment: .leading)
                Text(reasonText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(state.headline)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Palette.burnTint(state.burnFraction))
                Text(fallbackText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var reasonText: String {
        switch state.limit {
        case .goal:   return "avant d'avoir votre compte"
        case .burn:   return "avant la limite que vous avez fixée"
        case .sunset: return "avant que le Soleil ne descende"
        case .none:   return "restantes"
        }
    }

    private var fallbackText: String {
        if state.burnFraction >= 1 { return "la limite cutanée est atteinte" }
        if state.goalFraction >= 1 { return "vous pouvez rentrer" }
        return "rien ne presse : indice UV \(String(format: "%.1f", state.uvIndex))"
    }
}

/// Version d'un pouce de large, pour l'île dynamique repliée.
private struct CompactCountdown: View {
    let state: SunSessionAttributes.ContentState

    var body: some View {
        if let countdown = state.countdown {
            Text(timerInterval: countdown, countsDown: true)
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.burnTint(state.burnFraction))
                .frame(maxWidth: 52)
        } else {
            Text("\(Int(state.vitaminDIU.rounded()))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(Palette.vitaminD)
        }
    }
}
