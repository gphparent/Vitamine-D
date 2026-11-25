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
                    VStack(spacing: 8) {
                        Text(contexte.state.titre)
                            .font(.subheadline)
                        BoutonGeste(etat: contexte.state)
                    }
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
        // CarPlay (iOS 26) et la montre prennent la petite version.
        .supplementalActivityFamilies([.small])
    }
}

struct EcranVerrouille: View {
    let etat: ActiviteSeance.ContentState

    @Environment(\.activityFamily) private var famille

    var body: some View {
        if famille == .small {
            Petite(etat: etat)
        } else {
            VStack(spacing: 10) {
                ligne
                BoutonGeste(etat: etat)
            }
        }
    }

    private var ligne: some View {
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

/// Dans CarPlay : de quoi lire d'un coup d'œil en conduisant, la ville, le compte à rebours et le bouton.
struct Petite: View {
    let etat: ActiviteSeance.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(etat.ville, systemImage: etat.icone)
                .font(.headline)
                .lineLimit(1)
            Compte(cible: etat.cible)
                .font(.title3.weight(.semibold).monospacedDigit())
            BoutonGeste(etat: etat)
        }
        .foregroundStyle(.white)
    }
}

/// « Arrivé » ou « Terminé », touché sans déverrouiller ni ouvrir l'appli.
struct BoutonGeste: View {
    let etat: ActiviteSeance.ContentState

    var body: some View {
        if let seance = etat.seance {
            Button(intent: GesteTuile(seance: seance, termine: etat.etape == .surPlace)) {
                Label(etat.bouton, systemImage: etat.iconeBouton)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(etat.etape == .surPlace ? Color.green : Color(red: 0.93, green: 0.74, blue: 0.19))
            .foregroundStyle(etat.etape == .surPlace ? Color.white : Color.black)
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
