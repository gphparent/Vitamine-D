import SwiftUI

struct ProfileView: View {

    @Environment(AppModel.self) private var model
    @State private var showsClothing = false
    @State private var showsPhototypeHelp = false

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
                        Button("Refaire le questionnaire") { showsPhototypeHelp = true }
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
                    LabeledContent("Plafond par sortie",
                                   value: Format.iu(UVEngine.synthesisCeiling(profile: model.profile)))
                } header: {
                    Text("Exposition")
                } footer: {
                    Text("Le plafond correspond au point où la prévitamine D3 se dégrade aussi "
                         + "vite qu'elle se forme. C'est la raison pour laquelle on ne peut pas "
                         + "s'intoxiquer à la vitamine D par le seul soleil.")
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

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Seuil d'alerte cutanée")
                            Spacer()
                            Text(Format.percent(model.profile.burnAlertFraction))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $model.profile.burnAlertFraction, in: 0.3...0.9, step: 0.05)
                    }
                } header: {
                    Text("Objectifs")
                } footer: {
                    Text("L'alerte se déclenche à cette fraction de votre dose érythémale "
                         + "minimale. En rester bien en dessous ne coûte presque rien : la "
                         + "synthèse plafonne largement avant la rougeur.")
                }

                Section("Alertes") {
                    Toggle("Ouverture de la fenêtre UVB", isOn: $model.profile.notifyWindowOpening)
                    Toggle("Plan du matin", isOn: $model.profile.notifyDailyPlan)
                    if model.profile.notifyDailyPlan {
                        DatePicker("Heure du plan",
                                   selection: dailyPlanTime,
                                   displayedComponents: .hourAndMinute)
                    }
                    if model.notifications.authorisationStatus != .authorized {
                        Button("Autoriser les notifications") {
                            Task { await model.notifications.requestAuthorisation() }
                        }
                    }
                }

                Section("Comprendre") {
                    NavigationLink("À quoi sert la vitamine D") { VitaminDPrimerView() }
                    NavigationLink("Glossaire") { GlossaryListView() }
                }

                Section {
                    NavigationLink("Méthode et limites") { MethodologyView() }
                } footer: {
                    Text("Cette application n'est pas un dispositif médical. Les durées "
                         + "affichées sont des ordres de grandeur : la réponse cutanée varie "
                         + "d'un facteur deux à trois entre individus de même phototype.")
                }
            }
            .navigationTitle("Profil")
            .sheet(isPresented: $showsClothing) {
                ClothingView(exposure: $model.profile.exposure)
            }
            .sheet(isPresented: $showsPhototypeHelp) {
                OnboardingView()
            }
        }
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
