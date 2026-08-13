import SwiftUI

/// Accueil du premier lancement.
///
/// Le phototype est le réglage qui pèse le plus lourd dans tout ce que
/// l'application calcule : il fixe la dose au-delà de laquelle la peau rougit,
/// et le rendement de la synthèse. Le laisser à une valeur par défaut, comme le
/// faisait la première version, revient à donner des durées fausses à qui ne
/// pense pas à ouvrir les réglages.
struct OnboardingView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    @State private var questionnaire = PhototypeQuestionnaire()
    @State private var chosenType: SkinType?
    @State private var age = 35

    /// Bienvenue, ascendance, les cinq questions, puis le résultat.
    private var stepCount: Int { PhototypeQuestionnaire.questions.count + 3 }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ProgressView(value: Double(step + 1), total: Double(stepCount))
                    .tint(Theme.vitaminD)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        content
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                footer
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if step > 0 && step < stepCount - 1 {
                        Button("Passer") { step = stepCount - 1 }
                            .font(.subheadline)
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - Contenu

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:      welcome
        case 1:      ancestryStep
        case stepCount - 1: result
        default:     question(PhototypeQuestionnaire.questions[step - 2])
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.vitaminD)

            Text("Votre peau d'abord")
                .font(.largeTitle.weight(.semibold))

            Text("""
            Tout ce que cette application calcule dépend d'un seul réglage : \
            la dose de rayonnement au-delà de laquelle votre peau rougit. Elle \
            varie d'un facteur cinq entre les personnes.

            Cinq questions, une minute. Vous pourrez tout corriger ensuite.
            """)
            .font(.body)
            .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Âge")
                    .font(.subheadline.weight(.medium))
                Text("La peau produit moins de vitamine D en vieillissant : "
                     + "environ 1 % de moins par an après vingt ans.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Stepper(value: $age, in: 5...100) {
                    Text("\(age) ans").monospacedDigit()
                }
            }
        }
    }

    private var ancestryStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Votre ascendance")
                .font(.title2.weight(.semibold))

            Text("""
            Facultatif, et seulement un point de départ. L'ascendance est \
            corrélée à la pigmentation, mais l'écart entre deux personnes d'une \
            même région dépasse souvent l'écart entre régions — c'est votre \
            réaction au soleil, aux questions suivantes, qui aura le dernier mot.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)

            ForEach(Ancestry.grouped, id: \.title) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                    ForEach(group.options) { option in
                        choiceRow(option.title,
                                  selected: questionnaire.ancestry == option) {
                            questionnaire.ancestry = option
                        }
                    }
                }
            }
        }
    }

    private func question(_ question: PhototypeQuestionnaire.Question) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(question.prompt)
                .font(.title2.weight(.semibold))

            if let detail = question.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(question.answers.enumerated()), id: \.offset) { index, answer in
                choiceRow(answer,
                          selected: questionnaire.answers[question.id] == index) {
                    questionnaire.answers[question.id] = index
                }
            }
        }
    }

    private var result: some View {
        let suggested = questionnaire.suggestion
        let selected = chosenType ?? suggested

        return VStack(alignment: .leading, spacing: 18) {
            Text("Votre phototype")
                .font(.title2.weight(.semibold))

            HStack(spacing: 14) {
                Circle()
                    .fill(Color(red: selected.swatch.red,
                                green: selected.swatch.green,
                                blue: selected.swatch.blue))
                    .frame(width: 52, height: 52)
                    .overlay(Circle().stroke(.secondary.opacity(0.3), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected.title).font(.headline)
                    Text(selected.summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let explanation = questionnaire.explanation {
                Text(explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.vitaminD.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Ce que cela donne")
                    .font(.subheadline.weight(.medium))
                Text(thresholdSentence(for: selected))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Ajuster")
                .font(.subheadline.weight(.medium))
            ForEach(SkinType.allCases) { type in
                choiceRow("\(type.romanNumeral) — \(type.summary)",
                          selected: selected == type) {
                    chosenType = type
                }
            }
        }
    }

    /// Construite en plusieurs affectations plutôt qu'en une chaîne de `+` :
    /// l'inférence de type de Swift s'étrangle sur les concaténations longues
    /// mêlant littéraux et `String(format:)`.
    private func thresholdSentence(for type: SkinType) -> String {
        let mine = String(format: "%.0f", type.medJoulesPerSquareMetre)
        let lightest = String(format: "%.0f", SkinType.i.medJoulesPerSquareMetre)
        let darkest = String(format: "%.0f", SkinType.vi.medJoulesPerSquareMetre)
        var sentence = "Votre peau rougit à partir de \(mine) J/m², contre "
        sentence += "\(lightest) pour le type I et \(darkest) pour le type VI. "
        sentence += "C'est ce seuil qui fixe toutes les durées que l'application "
        sentence += "vous donnera."
        return sentence
    }

    // MARK: - Navigation

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button("Précédent") { step -= 1 }
                    .buttonStyle(.bordered)
            }
            Button(step == stepCount - 1 ? "Commencer" : "Suivant") {
                if step == stepCount - 1 { finish() } else { step += 1 }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.vitaminD)
            .frame(maxWidth: .infinity)
            .disabled(!canAdvance)
        }
        .padding(20)
        .background(.bar)
    }

    /// On n'exige une réponse que pour les questions ; l'ascendance reste
    /// facultative, et l'écran de résultat propose toujours une valeur.
    private var canAdvance: Bool {
        guard step >= 2, step < stepCount - 1 else { return true }
        return questionnaire.answers[PhototypeQuestionnaire.questions[step - 2].id] != nil
    }

    private func finish() {
        var profile = model.profile
        profile.skinType = chosenType ?? questionnaire.suggestion
        profile.age = age
        profile.ancestry = questionnaire.ancestry
        profile.hasCompletedOnboarding = true
        model.profile = profile
        dismiss()
    }

    private func choiceRow(_ label: String,
                           selected: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.vitaminD : Color.secondary.opacity(0.45))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected ? Theme.vitaminD.opacity(0.5) : .clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView().environment(AppModel())
}
