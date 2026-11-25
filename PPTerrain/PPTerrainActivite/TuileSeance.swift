import ActivityKit
import SwiftUI
import WidgetKit

@main
struct PPTerrainActiviteBundle: WidgetBundle {
    var body: some Widget {
        TuileSeance()
    }
}

struct TuileSeance: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ActiviteSeance.self) { contexte in
            EcranVerrouille(etat: contexte.state)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { contexte in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(contexte.state.ville, systemImage: contexte.state.icone)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Compte(cible: contexte.state.cible)
                        .font(.headline.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(contexte.state.titre)
                        .font(.subheadline)
                }
            } compactLeading: {
                Image(systemName: contexte.state.icone)
            } compactTrailing: {
                Compte(cible: contexte.state.cible)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
            } minimal: {
                Image(systemName: contexte.state.icone)
            }
        }
    }
}

struct EcranVerrouille: View {
    let etat: ActiviteSeance.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: etat.icone)
                .font(.title2)
                .foregroundStyle(Color(red: 0.93, green: 0.74, blue: 0.19))
            VStack(alignment: .leading, spacing: 3) {
                Text(etat.titre)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(etat.detail)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Compte(cible: etat.cible)
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
        }
    }
}

/// Le compte à rebours, que le système fait avancer seul ; passé l'heure, « maintenant ».
struct Compte: View {
    let cible: Date

    var body: some View {
        if cible > .now {
            Text(timerInterval: Date.now...cible, countsDown: true)
        } else {
            Text("maintenant")
        }
    }
}
