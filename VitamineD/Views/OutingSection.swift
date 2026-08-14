import SwiftUI

/// Le bloc « sortir », sur l'écran principal.
///
/// Il occupait auparavant un onglet à lui seul, qui répétait la moitié de
/// l'écran d'accueil : mêmes barres, même tenue, même météo, à deux endroits
/// qui pouvaient se contredire le temps d'un battement d'horloge. Tout est
/// désormais ici, sous les deux seules formes qu'il prend — on n'est pas
/// dehors, ou on y est.
struct OutingSection: View {

    @Environment(AppModel.self) private var model
    @State private var lastRecord: SessionRecord?
    @State private var showsSummary = false

    var body: some View {
        Group {
            if model.isSessionActive {
                active
            } else {
                idle
            }
        }
        .alert("Sortie terminée", isPresented: $showsSummary, presenting: lastRecord) { _ in
            Button("Parfait") { }
        } message: { record in
            Text("\(record.minutes) min · \(Format.iu(record.vitaminDIU)) · "
                 + "\(Format.percent(record.medFraction)) de votre seuil d'érythème.")
        }
    }

    // MARK: - Au repos

    /// Les deux options, dans l'ordre du temps.
    ///
    /// « Maintenant » vient toujours en premier quand elle existe, même si elle
    /// n'est pas la meilleure : c'est la question qu'on se pose en premier, et
    /// masquer la réponse pour cause de créneau supérieur cet après-midi serait
    /// répondre à côté. C'est la mise en avant, et non l'ordre, qui conseille.
    @ViewBuilder
    private var idle: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sortir")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(Theme.onSky)
                .padding(.horizontal, 4)

            let options = model.outingOptions

            if let immediate = options.immediate, let plan = model.plan {
                OutingOptionRow(kind: .now,
                                recommendation: immediate,
                                goalIU: model.profile.dailyGoalIU,
                                timeZone: plan.timeZone,
                                isPreferred: !options.laterIsBetter,
                                start: startSession)
            } else {
                unavailableNow
            }

            if let later = options.later, let plan = model.plan {
                OutingOptionRow(kind: .later,
                                recommendation: later,
                                goalIU: model.profile.dailyGoalIU,
                                timeZone: plan.timeZone,
                                isPreferred: options.laterIsBetter)
            }

            if options.laterIsBetter, options.immediate != nil {
                Text("Attendre vaut mieux : le Soleil sera plus haut, donc plus "
                     + "de vitamine D pour moins de capital cutané.")
                    .font(.caption)
                    .foregroundStyle(Theme.onSky.opacity(0.85))
                    .padding(.horizontal, 4)
            }

            if model.notifications.authorisationStatus == .denied {
                NoticeBanner(
                    kind: .warning,
                    title: "Alertes désactivées",
                    message: "Sans autorisation de notification, l'application ne pourra pas "
                        + "vous prévenir qu'il est temps de rentrer. Réglages › Notifications.")
            }
        }
    }

    /// Pourquoi sortir maintenant ne donnerait rien.
    private var unavailableNow: some View {
        Card(title: "Pas maintenant", systemImage: "sun.horizon") {
            Text(unavailableMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.outingOptions.later == nil, model.location != nil {
                Text(nothingLaterMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Sortir reste possible : ce n'est pas parce que le calcul ne
            // recommande rien qu'il faut empêcher quelqu'un de compter sa
            // sortie. Le bouton reste, en retrait.
            if model.location != nil {
                Button(action: startSession) {
                    Label("Je sors quand même", systemImage: "figure.walk.departure")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(Theme.vitaminD)
            }
        }
    }

    private var unavailableMessage: String {
        guard model.location != nil else {
            return "Indiquez d'abord votre position : sans latitude, rien ne se calcule."
        }
        if let plan = model.plan, plan.isVitaminDWinter {
            return "Le Soleil ne monte pas assez haut aujourd'hui — "
                + "\(Format.degrees(plan.peakElevation)) au plus haut, contre les "
                + "\(Format.degrees(UVEngine.vitaminDWinterElevation)) nécessaires. "
                + "Une sortie reste bonne pour le moral et pour l'horloge interne, "
                + "mais elle ne produira pas de vitamine D."
        }
        if model.todayTotalMEDFraction >= model.profile.burnAlertFraction - 0.01 {
            return "Votre capital cutané du jour est dépensé : vous êtes à "
                + "\(Format.percent(model.todayTotalMEDFraction)) de votre seuil "
                + "d'érythème. La peau, elle, ne distingue pas les sorties — "
                + "attendez demain."
        }
        if let position = model.solarPosition, position.elevation <= 0 {
            return "Le Soleil est couché."
        }
        return "Le Soleil est trop bas pour produire quoi que ce soit d'utile "
            + "en ce moment."
    }

    private var nothingLaterMessage: String {
        if let plan = model.plan, plan.isVitaminDWinter {
            return "Plus tard non plus : c'est vrai de la journée entière. "
                + "L'alimentation et les suppléments sont les seules voies qui restent, "
                + "et l'onglet Historique tient le compte de la réserve."
        }
        return "Il ne reste aucun créneau utile aujourd'hui non plus — rendez-vous demain."
    }

    private func startSession() {
        Task {
            if model.notifications.authorisationStatus == .notDetermined {
                await model.notifications.requestAuthorisation()
            }
            model.startSession()
        }
    }

    // MARK: - Dehors

    private var active: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Vous êtes dehors")
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(Theme.onSky)
                .padding(.horizontal, 4)

            Card {
                VStack(spacing: 18) {
                    Text(Format.stopwatch(model.progress.elapsed))
                        .font(.system(size: 54, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    HStack(spacing: 12) {
                        MetricTile(label: "Débit",
                                   value: "\(Int(model.progress.currentRates.vitaminDIUPerMinute)) UI/min")
                        MetricTile(label: "Rendement",
                                   value: Format.percent(model.progress.marginalYield),
                                   detail: "restant",
                                   glossary: .marginalYield)
                        MetricTile(label: "Aujourd'hui",
                                   value: Format.iu(model.progress.dayVitaminDIU),
                                   detail: "sur \(Int(model.profile.dailyGoalIU)) UI",
                                   tint: Theme.vitaminD)
                    }

                    Button(role: .destructive) {
                        lastRecord = model.endSession()
                        showsSummary = lastRecord != nil
                    } label: {
                        Label("Je rentre", systemImage: "figure.walk.arrival")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.burnColour(burnLevel))
                }
            }

            postureCard
            statusBanner
            alertsCard
        }
    }

    // MARK: - Debout, couché, retourné

    /// La position, et le bouton qui vaut le plus cher de tout l'écran.
    ///
    /// Se retourner ne remet rien à zéro : cela ouvre un second compte. La
    /// moitié qu'on quitte garde ce qu'elle a pris — et la reprendra si l'on
    /// se retourne encore — pendant que la moitié qui arrive part avec son
    /// capital cutané intact.
    private var postureCard: some View {
        let side = model.currentSide
        let med = model.progress.medBySide

        return Card(title: "Position", systemImage: side.symbolName) {
            Picker("Position", selection: Binding(
                get: { side },
                set: { model.setSessionSide($0) })) {
                ForEach(BodySide.allCases) { option in
                    Text(option.shortTitle).tag(option)
                }
            }
            .pickerStyle(.segmented)

            if side.isLyingDown {
                Button {
                    model.turnOver()
                } label: {
                    Label("Je me retourne", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.vitaminD)

                GoldRule()

                HStack(spacing: 12) {
                    MetricTile(label: BodySide.front.title,
                               value: Format.percent(med.erythemal(of: .front)),
                               detail: side == .front ? "au Soleil" : "à l'abri",
                               tint: side == .front ? Theme.burnColour(burnLevel) : .secondary)
                    MetricTile(label: BodySide.back.title,
                               value: Format.percent(med.erythemal(of: .back)),
                               detail: side == .back ? "au Soleil" : "à l'abri",
                               tint: side == .back ? Theme.burnColour(burnLevel) : .secondary)
                }

                Text("""
                Couché, la moitié du corps qui regarde le ciel prend toute la \
                dose, et l'autre n'en prend aucune. La synthèse tourne donc à \
                la moitié du débit d'une position debout — mais le coup de \
                soleil, lui, se prépare aussi vite.

                Se retourner à mi-parcours donne la même vitamine D pour la \
                moitié du capital cutané sur chaque moitié. C'est le seul geste \
                gratuit de toute l'application.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Debout ou en marche, le corps pivote : toute la peau "
                     + "découverte compte comme une seule pièce. Passez à "
                     + "« Ventre » ou « Dos » si vous vous allongez — les deux "
                     + "moitiés se comptent alors séparément.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var burnLevel: SessionProgress.BurnLevel {
        model.progress.burnLevel(alertFraction: model.profile.burnAlertFraction)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch burnLevel {
        case .safe:
            if model.progress.marginalYield < DayPlanner.diminishingReturnsThreshold {
                NoticeBanner(
                    kind: .info,
                    title: "La synthèse plafonne",
                    message: "La prévitamine D3 formée se dégrade maintenant aussi vite qu'elle "
                        + "se forme. Rester dehors n'ajoute plus grand-chose, mais continue "
                        + "d'accumuler de la dose érythémale.")
            }
        case .caution:
            NoticeBanner(
                kind: .warning,
                title: "Surveillez",
                message: "Vous approchez du seuil que vous vous êtes fixé "
                    + "(\(Format.percent(model.profile.burnAlertFraction)) de la DEM).")
        case .warning:
            NoticeBanner(
                kind: .warning,
                title: "Couvrez-vous",
                message: "Cherchez l'ombre, remettez un vêtement ou appliquez de la crème. "
                    + "La rougeur n'apparaîtra que dans quelques heures : ne vous fiez pas "
                    + "à ce que vous voyez maintenant.")
        case .danger:
            NoticeBanner(
                kind: .critical,
                title: "Rentrez",
                message: "Le seuil de coup de soleil est atteint ou dépassé. "
                    + "Aucune vitamine D supplémentaire n'est à gagner ici.")
        }
    }

    private var alertsCard: some View {
        Card(title: "Prochaines alertes", systemImage: "bell") {
            Text("""
            Les alertes sont déjà programmées auprès du système. Vous pouvez ranger \
            le téléphone : elles se déclencheront même si l'application est fermée. \
            Si vous changez de tenue ou appliquez de la crème, mettez-le à jour \
            juste en dessous — les alertes seront recalculées.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)

            GoldRule()

            if model.liveActivity.isRunning {
                Label("Le décompte est aussi sur l'écran verrouillé",
                      systemImage: "lock.iphone")
                    .font(.footnote)
                    .foregroundStyle(Theme.vitaminD)
                Text("Inutile de déverrouiller : l'heure à laquelle rentrer y "
                     + "défile toute seule, et se retrouve dans l'île dynamique "
                     + "quand vous êtes dans une autre application.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !model.liveActivity.isAvailable {
                Label("Activités en direct désactivées", systemImage: "lock.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Le décompte pourrait rester affiché sur l'écran verrouillé. "
                     + "Réglages ▸ Vitamine D ▸ Activités en direct.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ScrollView { OutingSection().padding(16) }
        .background(SkyBackground(solarElevation: 40))
        .environment(AppModel())
}
