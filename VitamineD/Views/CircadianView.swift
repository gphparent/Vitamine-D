import SwiftUI

/// Lumière du matin et horloge interne.
struct CircadianView: View {

    @Environment(AppModel.self) private var model
    @State private var showsSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                preamble
                todayCard
                if model.profile.wantsPhaseShift { shiftCard }
                eveningCard
                routineLink
                lampsCard
                caveat
            }
            .padding(16)
        }
        .background(SkyBackground(
                solarElevation: model.solarPosition?.elevation ?? -90,
                cloudCover: model.currentConditions?.cloudCover ?? 0))
        .navigationTitle("Sommeil")
        .toolbar {
            // Lever habituel, lever visé, durée de sommeil : ces réglages
            // conditionnent tout l'écran. Ils étaient au bas d'une page de
            // lecture, où personne ne les cherchait ; l'engrenage est
            // l'endroit où l'on cherche un réglage.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsSettings = true
                } label: {
                    Label("Réglages du sommeil", systemImage: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showsSettings) { CircadianSettingsView() }
    }

    // MARK: - Sections

    /// Les lampes et les outils, en une carte et deux lignes.
    ///
    /// L'hiver pousse à chercher des lampes, et le commerce en vend beaucoup en
    /// laissant croire qu'elles remplacent le Soleil. La carte est dans cet
    /// onglet-ci parce qu'il s'agit d'horloge interne et d'humeur, pas de
    /// vitamine D. Deux cartes se partageaient ce sujet et se recouvraient :
    /// la luminothérapie figurait dans les deux.
    private var lampsCard: some View {
        Card(title: "Lampes et outils", systemImage: "lamp.desk") {
            Text("Aucune lampe ne produit de vitamine D. Mais contre l'hiver, "
                 + "l'une d'elles a de vraies preuves, et d'autres outils "
                 + "aident à caler l'horloge.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GoldRule()

            linkRow("Luminothérapie, rouge, infrarouge",
                    detail: "Ce que fait chacune, avec un minuteur",
                    systemImage: "timer") {
                LightTherapyView()
            }

            linkRow("Lampes, simulateurs d'aube, verres filtrants",
                    detail: "Ce que vaut chacun, et ce que la preuve dit vraiment",
                    systemImage: "lightbulb.max") {
                SleepToolsView()
            }
        }
    }

    /// Une ligne cliquable dans une carte : intitulé, détail, chevron.
    private func linkRow<Destination: View>(
        _ title: String,
        detail: String,
        systemImage: String,
        @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(Theme.vitaminD)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }


    private var preamble: some View {
        Card {
            Text("""
            Ceci n'a rien à voir avec la vitamine D, et c'est même son exact \
            contraire. Le Soleil rasant du matin ne produit aucun UVB utile — \
            mais c'est le meilleur signal horaire de la journée pour votre \
            horloge interne.

            Deux raisons de sortir, à deux moments différents, par deux \
            mécanismes sans rapport.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var todayCard: some View {
        if let light = model.morningLight {
            Card(title: "Aujourd'hui", systemImage: "sunrise") {
                HStack(alignment: .firstTextBaseline) {
                    Text(Format.interval(light.window, in: model.plan?.timeZone))
                        .font(.title2.weight(.semibold).monospacedDigit())
                    Spacer()
                    Text(light.quality.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(qualityColour(light.quality))
                }

                if let minutes = light.quality.recommendedMinutes {
                    Text("\(minutes.lowerBound) à \(minutes.upperBound) minutes dehors")
                        .font(.headline)
                        .foregroundStyle(Theme.vitaminD)
                }

                Text(light.quality.advice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                GoldRule()

                HStack(spacing: 12) {
                    MetricTile(label: "Dehors",
                               value: illuminanceText(light.illuminance),
                               detail: "au meilleur moment")
                    MetricTile(label: "Pièce éclairée",
                               value: "300 lux",
                               detail: "pour comparaison")
                    MetricTile(label: "Meilleur moment",
                               value: Format.time(light.best, in: model.plan?.timeZone))
                }

                Text(comparisonSentence(light.illuminance))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if light.sunRisesAfterWaking {
                    NoticeBanner(
                        kind: .info,
                        title: "Vous vous levez avant le Soleil",
                        message: "La fenêtre commence au lever, pas à votre réveil : "
                            + "avant, il n'y a rien à capter. En hiver, une lampe de "
                            + "luminothérapie prend le relais — comptez 10 000 lux "
                            + "à trente centimètres.")
                }
            }
        } else if !model.profile.tracksCircadianLight {
            Card {
                Text("Le suivi de la lumière matinale est désactivé.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Activer dans les réglages") { showsSettings = true }
                    .font(.footnote.weight(.medium))
            }
        } else {
            Card {
                Text("Aucune fenêtre calculable aujourd'hui — le Soleil ne se lève "
                     + "pas, ou la prévision manque.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var shiftCard: some View {
        let plan = model.phaseShift
        let earlier = plan.shiftMinutes < 0

        return Card(title: "Déplacer votre lever", systemImage: "arrow.left.arrow.right") {
            Text(earlier
                 ? "Vous visez \(Format.minuteOfDay(model.profile.targetWakeMinuteOfDay)), "
                   + "soit \(abs(plan.shiftMinutes)) minutes plus tôt que votre habitude."
                 : "Vous visez \(Format.minuteOfDay(model.profile.targetWakeMinuteOfDay)), "
                   + "soit \(abs(plan.shiftMinutes)) minutes plus tard que votre habitude.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                MetricTile(label: "Demain, visez",
                           value: Format.minuteOfDay(plan.nextWakeMinuteOfDay),
                           tint: Theme.vitaminD)
                MetricTile(label: "Arrivée estimée",
                           value: plan.days <= 1 ? "demain" : "en \(plan.days) jours")
                MetricTile(label: "Pas quotidien",
                           value: "\(CircadianPlanner.maximumDailyShift) min",
                           detail: "au maximum")
            }

            Text("""
            L'horloge se déplace d'elle-même de moins d'une heure par jour sous \
            l'effet de la lumière. Aller plus vite ne fait que creuser un écart \
            entre l'heure du réveil et celle du corps — précisément ce qu'on \
            cherche à supprimer.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(earlier
                 ? "Pour avancer : lumière dès le lever, pénombre le soir."
                 : "Pour retarder : lumière le soir, et évitez-la trop tôt le matin.")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var eveningCard: some View {
        Card(title: "Le soir", systemImage: "moon") {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.minuteOfDay(model.phaseShift.dimLightMinuteOfDay))
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("baissez les lumières")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("""
            La lumière du soir agit à l'inverse de celle du matin : elle retarde \
            l'horloge. Deux à trois heures de pénombre avant le coucher visé lui \
            laissent le temps de libérer la mélatonine.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)

            Text("Coucher visé : \(Format.minuteOfDay(bedtimeMinute)), pour "
                 + String(format: "%.1f", model.profile.sleepHours) + " heures de sommeil.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Renvoi vers la routine programmable.
    ///
    /// Placé avant le catalogue d'outils, et c'est délibéré : ce qui change une
    /// nuit se joue à des heures précises, pas dans le choix d'une lampe.
    private var routineLink: some View {
        NavigationLink {
            SleepRoutineView()
        } label: {
            Card(title: "Votre routine", systemImage: "list.bullet.clipboard") {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Neuf heures calculées, neuf rappels au choix")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(reminderSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var reminderSummary: String {
        let count = model.profile.sleepReminders.count
        switch count {
        case 0:  return "Dernier café, bain chaud, pénombre, coucher — aucun rappel actif"
        case 1:  return "Un rappel actif"
        default: return "\(count) rappels actifs"
        }
    }

    private var caveat: some View {
        Card(title: "Ce que valent ces durées", systemImage: "questionmark.circle") {
            Text("""
            Que la lumière soit le principal synchroniseur de l'horloge interne \
            ne fait aucun doute, et que celle du matin avance la phase tandis \
            que celle du soir la retarde est également bien établi.

            Les durées précises proposées ici viennent en revanche de la \
            vulgarisation — celles que popularise notamment Andrew Huberman — \
            et non d'un protocole clinique. Elles sont raisonnables et sans \
            risque, mais ce ne sont pas des posologies.

            Une précision de sécurité : ne fixez jamais le Soleil. Le bénéfice \
            vient de la lumière ambiante qui atteint la rétine, pas du fait de \
            le regarder.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Détails

    private var bedtimeMinute: Int {
        let raw = Double(model.profile.targetWakeMinuteOfDay) - model.profile.sleepHours * 60
        return ((Int(raw.rounded()) % 1440) + 1440) % 1440
    }

    private func illuminanceText(_ lux: Double) -> String {
        lux >= 10_000
            ? "\(Int((lux / 1000).rounded())) k lux"
            : "\(Int(lux.rounded())) lux"
    }

    private func comparisonSentence(_ lux: Double) -> String {
        let ratio = max(1, lux / 300)
        return "Soit environ \(Int(ratio.rounded())) fois l'éclairement d'une pièce "
            + "bien éclairée. Une fenêtre ne suffit pas : le verre et la distance "
            + "font perdre l'essentiel."
    }

    private func qualityColour(_ quality: CircadianPlanner.LightQuality) -> Color {
        switch quality {
        case .excellent, .good: return Color(red: 0.30, green: 0.66, blue: 0.42)
        case .moderate:         return Color(red: 0.95, green: 0.72, blue: 0.20)
        case .weak:             return .orange
        case .insufficient:     return .secondary
        }
    }

}

/// Les réglages de l'horloge, en feuille.
///
/// Lever habituel, lever visé et durée de sommeil déplacent d'un coup la
/// fenêtre du matin, l'heure de pénombre et les neuf rappels de la routine.
/// Ils vivaient au bas de l'onglet, après huit cartes de lecture ; la routine
/// renvoyait même « aux réglages de l'onglet Sommeil », sans dire où.
struct CircadianSettingsView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section {
                    Toggle("Suivre la lumière du matin", isOn: $model.profile.tracksCircadianLight)
                } footer: {
                    Text("Calcule chaque jour la fenêtre de lumière du matin et "
                         + "l'heure à laquelle baisser les lumières le soir.")
                }

                if model.profile.tracksCircadianLight {
                    Section {
                        timePicker("Lever habituel", minute: $model.profile.wakeMinuteOfDay)
                        timePicker("Lever visé", minute: $model.profile.targetWakeMinuteOfDay)
                    } header: {
                        Text("Lever")
                    } footer: {
                        Text("Un lever visé différent du lever habituel déclenche un "
                             + "plan de déplacement progressif, d'au plus une heure "
                             + "par jour.")
                    }

                    Section {
                        HStack {
                            Text("Sommeil souhaité")
                            Spacer()
                            Text(String(format: "%.1f h", model.profile.sleepHours))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $model.profile.sleepHours, in: 5...10, step: 0.5)
                    } header: {
                        Text("Nuit")
                    } footer: {
                        Text("L'heure de coucher visée et les rappels de la routine "
                             + "se déduisent du lever visé et de cette durée.")
                    }
                }
            }
            .navigationTitle("Sommeil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    private func timePicker(_ label: String, minute: Binding<Int>) -> some View {
        DatePicker(label,
                   selection: Binding(
                    get: {
                        var components = DateComponents()
                        components.hour = minute.wrappedValue / 60
                        components.minute = minute.wrappedValue % 60
                        return Calendar.current.date(from: components) ?? Date()
                    },
                    set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        minute.wrappedValue = (parts.hour ?? 7) * 60 + (parts.minute ?? 0)
                    }),
                   displayedComponents: .hourAndMinute)
    }
}

#Preview {
    NavigationStack { CircadianView().environment(AppModel()) }
}
