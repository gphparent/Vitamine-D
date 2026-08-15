import SwiftUI

/// La soirée et le matin, heure par heure, avec un rappel activable par étape.
///
/// C'est la partie de l'onglet Sommeil qui *fait* quelque chose. Le reste
/// explique ; ici, on programme. Les heures se déduisent du lever visé et de la
/// durée de sommeil souhaitée : changer l'un déplace les neuf rappels d'un
/// coup.
struct SleepRoutineView: View {

    @Environment(AppModel.self) private var model
    @State private var expanded: SleepRoutineStep?

    private var routine: SleepRoutine { model.sleepRoutine }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                anchors
                notificationNotice
                steps
                alarmNotice
                caveat
            }
            .padding(16)
        }
        .background(SkyBackground(
            solarElevation: model.solarPosition?.elevation ?? -90,
            cloudCover: model.currentConditions?.cloudCover ?? 0))
        .navigationTitle("Votre routine")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Les deux points d'ancrage

    private var anchors: some View {
        Card(title: "D'où tout se calcule", systemImage: "clock.arrow.circlepath") {
            HStack(spacing: 12) {
                MetricTile(label: "Coucher",
                           value: Format.minuteOfDay(routine.bedtimeMinuteOfDay),
                           detail: "déduit du lever")
                MetricTile(label: "Lever visé",
                           value: Format.minuteOfDay(routine.wakeMinuteOfDay),
                           tint: Theme.vitaminD)
                MetricTile(label: "Sommeil",
                           value: String(format: "%.1f h", model.profile.sleepHours))
            }

            GoldRule()

            Text("Les neuf heures ci-dessous se déduisent de ces deux-là. "
                 + "Modifiez le lever visé ou la durée dans les réglages de "
                 + "l'onglet Sommeil, et tout se replace.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var notificationNotice: some View {
        if model.notifications.authorisationStatus == .denied {
            NoticeBanner(
                kind: .warning,
                title: "Notifications refusées",
                message: "Les rappels ne peuvent pas être déposés. "
                    + "Réglages ▸ Vitamine D ▸ Notifications.")
        } else if model.notifications.authorisationStatus == .notDetermined,
                  !model.profile.sleepReminders.isEmpty {
            NoticeBanner(
                kind: .info,
                title: "Autorisation à donner",
                message: "Activez un rappel et acceptez la demande : sans elle, "
                    + "rien ne sera programmé.")
        }
    }

    // MARK: - Les étapes

    private var steps: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("La journée à rebours")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(Theme.onSky)
                .padding(.horizontal, 4)

            ForEach(routine.entries) { entry in
                stepCard(entry)
            }
        }
    }

    private func stepCard(_ entry: SleepRoutine.Entry) -> some View {
        let step = entry.step
        let isOpen = expanded == step

        return Card {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: step.symbolName)
                    .font(.title3)
                    .foregroundStyle(Theme.vitaminD)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.subheadline.weight(.semibold))
                    Text(step.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(Format.minuteOfDay(entry.minuteOfDay))
                    .font(.title3.weight(.semibold).monospacedDigit())

                Toggle("", isOn: reminder(for: step))
                    .labelsHidden()
                    .tint(Theme.vitaminD)
            }

            Button {
                withAnimation(.snappy) { expanded = isOpen ? nil : step }
            } label: {
                HStack(spacing: 6) {
                    EvidenceBadge(strength: step.evidence)
                    Text(isOpen ? "Masquer" : "Pourquoi")
                        .font(.caption.weight(.medium))
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                    Spacer()
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if isOpen {
                Text(step.rationale)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Rappel activé pour une étape.
    private func reminder(for step: SleepRoutineStep) -> Binding<Bool> {
        Binding(
            get: { model.profile.sleepReminders.contains(step.rawValue) },
            set: { isOn in
                if isOn {
                    model.profile.sleepReminders.insert(step.rawValue)
                    // Le premier rappel activé est le bon moment pour demander
                    // l'autorisation : la demande arrive alors qu'on vient
                    // d'exprimer ce qu'on en attend.
                    if model.notifications.authorisationStatus == .notDetermined {
                        Task {
                            await model.notifications.requestAuthorisation()
                            model.refreshSleepReminders()
                        }
                    }
                } else {
                    model.profile.sleepReminders.remove(step.rawValue)
                }
            })
    }

    // MARK: - Ce qu'un rappel n'est pas

    private var alarmNotice: some View {
        Card(title: "Rappels, et non alarmes", systemImage: "alarm.waves.left.and.right") {
            Text("""
            iOS réserve les alarmes à l'application Horloge : elle seule sonne \
            malgré le mode silencieux et les modes de concentration. Ce que \
            l'application dépose ici, ce sont des notifications — parfaites \
            pour se rappeler de baisser les lumières, insuffisantes pour se \
            réveiller.

            Réglez donc votre réveil dans Horloge, à \
            \(Format.minuteOfDay(routine.wakeMinuteOfDay)). Le rappel de lever \
            ci-dessus ne sert qu'à constater si vous avez tenu l'heure.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var caveat: some View {
        Card(title: "Ce que valent ces heures", systemImage: "questionmark.circle") {
            Text("""
            Chaque étape porte son étiquette de preuve, et elles ne se valent \
            pas. Le bain chaud, la caféine et la régularité reposent sur des \
            essais contrôlés ou de grandes cohortes ; le couvre-feu des écrans \
            repose surtout sur du bon sens et des études contradictoires.

            Ces heures sont des points de départ, pas des prescriptions. \
            Décalez-les si votre expérience dit autre chose : c'est votre nuit \
            qui a le dernier mot, pas une moyenne de population.

            Une insomnie qui dure ne se corrige pas avec une liste d'habitudes. \
            Son traitement de première intention est une thérapie \
            cognitivo-comportementale, et elle se demande à un médecin.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack { SleepRoutineView().environment(AppModel()) }
}
