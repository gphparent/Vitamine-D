import SwiftUI
import UIKit

struct ProfileView: View {

    @Environment(AppModel.self) private var model
    @State private var showsClothing = false
    /// Poids et taille sont saisis en texte plutôt que liés au profil : lier
    /// directement écrirait « 7 kg » le temps de taper « 70 ».
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var hasSeededMorphology = false
    /// Les deux entrées — « revoir la présentation » et « refaire le
    /// questionnaire » — ouvrent le même écran, qui commence par les pages
    /// d'explication et finit par le phototype.
    @State private var showsOnboarding = false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            Form {
                Section {
                    ForEach(SkinType.allCases) { type in
                        skinTypeRow(type, binding: $model.profile.skinType)
                    }
                } header: {
                    HStack {
                        Text("Phototype")
                        Spacer()
                        Button("Refaire le questionnaire") { showsOnboarding = true }
                            .font(.caption)
                            .textCase(nil)
                    }
                } footer: {
                    Text("Le phototype fixe la dose érythémale minimale — l'énergie UV "
                         + "au-delà de laquelle la peau rougit — et le rendement de la "
                         + "synthèse. C'est le réglage qui pèse le plus lourd.")
                }

                Section("Vous") {
                    Stepper(value: $model.profile.age, in: 5...100) {
                        HStack {
                            Text("Âge")
                            Spacer()
                            Text("\(model.profile.age) ans")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    Picker("Acclimatation", selection: $model.profile.tanLevel) {
                        ForEach(TanLevel.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }

                    LabeledContent("Rendement lié à l'âge",
                                   value: Format.percent(model.profile.ageFactor))
                    LabeledContent("Seuil d'érythème",
                                   value: String(format: "%.0f J/m²", model.profile.effectiveMED))
                    NavigationLink("Que veulent dire ces chiffres ?") {
                        GlossaryListView()
                    }
                    .font(.footnote)
                }

                Section {
                    Button {
                        showsClothing = true
                    } label: {
                        HStack {
                            Text("Tenue habituelle").foregroundStyle(.primary)
                            Spacer()
                            Text(model.profile.exposure.preset.title)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    LabeledContent("Peau exposée",
                                   value: String(format: "%.0f %%",
                                                 model.profile.exposure.exposedBodyPercentage))
                    if let plan = model.plan {
                        LabeledContent("Maximum aujourd'hui",
                                       value: Format.iu(plan.attainableIU))
                    }
                    LabeledContent("Plafond théorique",
                                   value: Format.iu(UVEngine.synthesisCeiling(profile: model.profile)))
                } header: {
                    Text("Exposition")
                } footer: {
                    Text("""
                    Le maximum du jour est ce que vous obtiendriez en restant dehors au \
                    meilleur moment jusqu'à la rougeur. C'est le chiffre utile.

                    Le plafond théorique est le point où la prévitamine D3 se dégraderait \
                    aussi vite qu'elle se forme — la raison pour laquelle on ne peut pas \
                    s'intoxiquer à la vitamine D par le seul soleil. C'est une asymptote : \
                    la courbe s'en approche sans jamais l'atteindre, et la peau rougit bien \
                    avant. Il ne se lit pas comme une quantité obtenable.
                    """)
                }

                Section {
                    morphologyField("Poids", unit: "kg", text: $weightText)
                    morphologyField("Taille", unit: "cm", text: $heightText)

                    if let bmi = VitaminDTarget.bodyMassIndex(
                        weightKilograms: model.profile.weightKilograms,
                        heightCentimetres: model.profile.heightCentimetres) {
                        LabeledContent("Indice de masse corporelle",
                                       value: String(format: "%.1f", bmi))
                    }
                } header: {
                    Text("Morphologie")
                } footer: {
                    Text("""
                    Facultatif, et sans effet sur les durées d'exposition : la synthèse \
                    dépend de la surface de peau découverte, pas de la masse. Ces deux \
                    mesures ne servent qu'à suggérer un objectif quotidien, parce que la \
                    vitamine D est liposoluble et se dilue dans la masse grasse.
                    """)
                }

                Section {
                    Stepper(value: $model.profile.dailyGoalIU, in: 400...4000, step: 100) {
                        HStack {
                            Text("Objectif quotidien")
                            Spacer()
                            Text(Format.iu(model.profile.dailyGoalIU))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    suggestionRow

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Seuil d'alerte cutanée")
                            Spacer()
                            Text(Format.percent(model.profile.burnAlertFraction))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $model.profile.burnAlertFraction, in: 0.3...0.9, step: 0.05)
                        Text(burnThresholdSentence)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Objectifs")
                } footer: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("""
                        L'objectif est une cible de synthèse cutanée, exprimée dans la même \
                        unité que les apports alimentaires de référence pour pouvoir s'y \
                        comparer. Le seuil d'alerte, lui, est la fraction de votre dose \
                        érythémale minimale à laquelle l'application vous demande de \
                        rentrer : en rester bien en dessous ne coûte presque rien, puisque \
                        la synthèse plafonne largement avant la rougeur.
                        """)
                        MedicalNotice(isCompact: true)
                    }
                }

                Section("Alertes") {
                    Toggle("Ouverture de la fenêtre UVB", isOn: $model.profile.notifyWindowOpening)
                    Toggle("Plan du matin", isOn: $model.profile.notifyDailyPlan)
                    if model.profile.notifyDailyPlan {
                        DatePicker("Heure du plan",
                                   selection: dailyPlanTime,
                                   displayedComponents: .hourAndMinute)
                    }
                    if model.notifications.authorisationStatus == .denied {
                        // Une fois refusées, les notifications ne se
                        // redemandent pas non plus : le système ne repose la
                        // question qu'une seule fois, ici comme pour Santé.
                        Button("Ouvrir les réglages de l'application") { openAppSettings() }
                    } else if model.notifications.authorisationStatus != .authorized {
                        Button("Autoriser les notifications") {
                            Task { await model.notifications.requestAuthorisation() }
                        }
                    }
                }

                Section {
                    // Basculer *est* la demande d'autorisation. Séparer les
                    // deux laissait des gens avec un interrupteur allumé et
                    // aucun accès : l'application lisait le vide et n'affichait
                    // rien, ce qui ressemblait exactement à une panne.
                    Toggle("Lire les données de santé", isOn: $model.profile.readsHealthKit)
                        .disabled(!model.health.isAvailable)
                    Toggle("Enregistrer mes sorties dans Santé",
                           isOn: $model.profile.writesHealthKit)
                        .disabled(!model.health.isAvailable)

                    if model.profile.readsHealthKit || model.profile.writesHealthKit {
                        healthStatusRow
                    }

                    if model.profile.readsHealthKit {
                        LabeledContent("Vitamine D alimentaire aujourd'hui",
                                       value: model.health.hasDietarySamples
                                           ? Format.iu(model.health.dietaryVitaminDIU)
                                           : "aucune donnée")
                        LabeledContent("Plein jour mesuré",
                                       value: model.health.hasDaylightSamples
                                           ? "\(Int(model.health.daylightMinutes.rounded())) min"
                                           : "aucune donnée")
                    }

                    if let error = model.health.lastWriteError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    Button("Ouvrir l'application Santé") { openHealthApp() }
                        .font(.footnote)
                } header: {
                    Text("Santé")
                } footer: {
                    Text("""
                    En lecture : votre apport alimentaire en vitamine D, pour savoir si \
                    les suppléments prennent le relais quand le Soleil ne peut plus \
                    rien, et vos minutes de plein jour, pour repérer les expositions \
                    que l'application n'a pas comptées.

                    En écriture : l'exposition ultraviolette de chaque sortie — un \
                    indice UV moyen sur une durée, ce qui décrit exactement ce qu'elle \
                    a été. Le temps passé au grand jour n'est jamais écrit : votre \
                    montre l'enregistre déjà, et Santé additionne les sources.

                    « Aucune donnée » veut dire qu'aucune application n'en a jamais \
                    enregistré, pas que la lecture a échoué. Les minutes de plein jour \
                    viennent de l'Apple Watch et n'existent pas sans elle ; la vitamine \
                    D alimentaire suppose que vous notiez vos repas ou vos suppléments \
                    quelque part.
                    """)
                }

                if model.profile.writesHealthKit {
                    Section {
                        Toggle("Compter la synthèse comme apport alimentaire",
                               isOn: $model.profile.writesVitaminDAsDietary)
                    } footer: {
                        Text("""
                        À vous de trancher, et voici l'enjeu. Santé ne connaît qu'une \
                        vitamine D : celle qu'on avale. Y verser celle que votre peau \
                        fabrique rend le total juste — c'est la même molécule, et vous \
                        verriez enfin votre apport réel — mais la provenance fausse : \
                        le graphique nutritionnel comptera comme un repas ce qui vient \
                        du Soleil, et toute autre application lisant ce champ fera de \
                        même.

                        Désactivé, vos sorties restent enregistrées comme exposition \
                        ultraviolette, sans toucher à la nutrition.
                        """)
                    }

                    Section {
                        Button("Retirer mes données de Santé", role: .destructive) {
                            Task { await model.health.deleteWrittenSamples(since: .distantPast) }
                        }
                    } footer: {
                        Text("Efface de Santé les échantillons écrits par cette "
                             + "application, et eux seuls. Ce que d'autres sources y ont "
                             + "déposé n'est pas touché.")
                    }
                }

                Section("Comprendre") {
                    Button("Revoir la présentation") { showsOnboarding = true }
                    NavigationLink("À quoi sert la vitamine D") { VitaminDPrimerView() }
                    NavigationLink("Glossaire") { GlossaryListView() }
                }

                Section {
                    NavigationLink("Méthode et limites") { MethodologyView() }
                    NavigationLink("Sur quoi reposent ces chiffres") { EvidenceView() }
                } footer: {
                    Text("""
                    Cette application n'est pas un dispositif médical et ne pose aucun \
                    diagnostic. Elle applique à un modèle des données publiées — apports \
                    recommandés, photobiologie cutanée, position du Soleil — et ne mesure \
                    rien dans votre sang. Ces apports ne font d'ailleurs pas consensus, et \
                    l'application expose le désaccord plutôt que de trancher.

                    Les durées affichées sont des ordres de grandeur : la réponse cutanée \
                    varie d'un facteur deux à trois entre individus de même phototype. \
                    L'avis de votre médecin prime sur tout ce qui est affiché ici, sans \
                    exception — et il est nécessaire si vous prenez un traitement \
                    photosensibilisant, souffrez d'une maladie de peau ou avez un \
                    antécédent de cancer cutané.
                    """)
                }
            }
            .navigationTitle("Profil")
            .task {
                guard !hasSeededMorphology else { return }
                hasSeededMorphology = true
                weightText = MeasurementField.text(from: model.profile.weightKilograms)
                heightText = MeasurementField.text(from: model.profile.heightCentimetres)
            }
            .onChange(of: weightText) { _, new in
                model.profile.weightKilograms = MeasurementField.value(from: new)
            }
            .onChange(of: heightText) { _, new in
                model.profile.heightCentimetres = MeasurementField.value(from: new)
            }
            // Allumer l'interrupteur, c'est demander l'accès. Le système ne
            // présentera sa feuille qu'une fois — ensuite tout se passe dans
            // Réglages ▸ Santé, et le bouton ci-dessous y mène.
            .onChange(of: model.profile.readsHealthKit) { _, on in
                if on { requestHealthAccess() }
            }
            .onChange(of: model.profile.writesHealthKit) { _, on in
                if on { requestHealthAccess() }
            }
            .onChange(of: model.profile.writesVitaminDAsDietary) { _, on in
                if on { requestHealthAccess() }
            }
            .task {
                await model.health.refreshRequestStatus(
                    writing: model.profile.writesHealthKit,
                    dietary: model.profile.writesVitaminDAsDietary)
            }
            .sheet(isPresented: $showsClothing) {
                ClothingView(exposure: $model.profile.exposure)
            }
            .sheet(isPresented: $showsOnboarding) {
                OnboardingView(isReview: true)
            }
        }
    }

    // MARK: - Santé

    /// Ce que l'application sait honnêtement de son propre accès.
    ///
    /// Elle en sait moins qu'on ne croit, et le taire serait pire que de
    /// l'admettre. Apple ne révèle jamais si une autorisation de *lecture* a
    /// été accordée : c'est délibéré, pour qu'un refus ne puisse pas trahir
    /// l'existence d'une donnée. L'écriture, elle, est vérifiable.
    @ViewBuilder
    private var healthStatusRow: some View {
        if model.health.connection == .unavailable {
            Label("Santé n'est pas disponible sur cet appareil",
                  systemImage: "xmark.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else {
            // Le bouton reste offert quel que soit l'état. Le masquer une fois
            // la question posée laissait sans recours ceux à qui le système
            // n'affiche plus rien — c'est-à-dire tout le monde, dès la seconde
            // fois.
            Button {
                requestHealthAccess()
            } label: {
                Label(model.health.connection == .notRequested
                          ? "Demander l'accès à Santé"
                          : "Revérifier l'accès",
                      systemImage: "heart.text.square")
            }

            if let outcome = model.health.lastOutcome {
                outcomeRow(outcome)
            }

            if model.profile.writesHealthKit {
                Text(writeStatusSentence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Ce qui a été accordé en lecture n'est pas consultable : Apple "
                 + "l'interdit, pour qu'un refus ne puisse pas révéler l'existence "
                 + "d'une donnée. Seule l'application Santé le montre.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Ce que le système a répondu au dernier appui.
    @ViewBuilder
    private func outcomeRow(_ outcome: HealthKitService.RequestOutcome) -> some View {
        switch outcome {
        case .presented:
            Label("Le système a présenté sa demande.", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(Color(red: 0.30, green: 0.66, blue: 0.42))

        case .alreadyAsked:
            VStack(alignment: .leading, spacing: 6) {
                Label("iOS ne repose jamais la question", systemImage: "info.circle")
                    .font(.caption.weight(.medium))
                Text("""
                Rien ne s'affiche parce que la feuille d'autorisation a déjà été \
                présentée une fois — au moment où vous avez activé l'interrupteur. \
                iOS ne la montre plus jamais ensuite, même après une \
                réinstallation. Tout se règle désormais dans l'application Santé.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                Button("Ouvrir Santé") { openHealthApp() }
                    .font(.caption.weight(.medium))
                Text("Puis : votre portrait en haut à droite ▸ Apps et services ▸ "
                     + "Vitamine D.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Refus de HealthKit", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .unavailable:
            Text("Aucun type de donnée à demander sur cet appareil.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var writeStatusSentence: String {
        switch model.health.ultravioletWriteStatus {
        case .sharingAuthorized:
            return "Écriture de l'exposition ultraviolette : autorisée."
        case .sharingDenied:
            return "Écriture de l'exposition ultraviolette : refusée. "
                + "Vos sorties ne sont donc pas enregistrées dans Santé."
        default:
            return "Écriture de l'exposition ultraviolette : jamais demandée."
        }
    }

    private func requestHealthAccess() {
        Task {
            await model.health.requestAuthorisation(
                writing: model.profile.writesHealthKit,
                dietary: model.profile.writesVitaminDAsDietary)
            await model.health.refresh(on: model.now, calendar: model.calendar)
        }
    }

    /// Ouvre la fiche de l'application dans Réglages.
    ///
    /// À ne pas confondre avec la destination utile pour Santé : les
    /// autorisations HealthKit ne figurent pas sur cette page-là. Elle sert aux
    /// notifications et à la position.
    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Ouvre l'application Santé, seul endroit où les autorisations HealthKit
    /// se consultent et se modifient une fois la question posée.
    private func openHealthApp() {
        guard let url = URL(string: "x-apple-health://") else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Morphologie et objectif

    private func morphologyField(_ label: String,
                                 unit: String,
                                 text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 90)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    /// Ce que la littérature suggère, et pourquoi.
    ///
    /// Affiché en permanence plutôt qu'imposé : l'objectif reste celui de
    /// l'utilisateur, mais il ne devrait pas avoir à deviner d'où sortent les
    /// mille unités par défaut.
    private var suggestionRow: some View {
        let suggestion = model.profile.suggestedGoal

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Suggestion", systemImage: "text.book.closed")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(Format.iu(suggestion.dailyIU))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.vitaminD)
            }

            Text(VitaminDTarget.rationale(for: suggestion, age: model.profile.age))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.profile.goalDivergesFromSuggestion {
                Button("Adopter \(Format.iu(suggestion.dailyIU))") {
                    model.profile.dailyGoalIU = suggestion.dailyIU
                }
                .font(.caption.weight(.medium))
            }
        }
    }

    private var burnThresholdSentence: String {
        let percent = Format.percent(model.profile.burnAlertFraction)
        return "L'alerte tombe à \(percent) de la dose qui rougirait votre peau. "
            + "La synthèse, elle, plafonne bien avant : au-delà, on dépense du "
            + "capital cutané sans plus rien produire."
    }

    private var dailyPlanTime: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = model.profile.dailyPlanMinuteOfDay / 60
                components.minute = model.profile.dailyPlanMinuteOfDay % 60
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.profile.dailyPlanMinuteOfDay = (components.hour ?? 8) * 60 + (components.minute ?? 0)
            }
        )
    }

    private func skinTypeRow(_ type: SkinType, binding: Binding<SkinType>) -> some View {
        Button {
            binding.wrappedValue = type
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color(red: type.swatch.red, green: type.swatch.green, blue: type.swatch.blue))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 0.5))

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(type.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if binding.wrappedValue == type {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.vitaminD)
                }
            }
        }
    }
}

#Preview {
    ProfileView().environment(AppModel())
}
