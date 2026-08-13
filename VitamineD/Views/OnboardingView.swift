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

    /// Trois pages d'explication, l'âge, l'ascendance, les cinq questions,
    /// puis le résultat.
    private var stepCount: Int { PhototypeQuestionnaire.questions.count + 6 }

    /// Rang de la première question du questionnaire.
    private static let firstQuestionStep = 5

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
        case 0:      purpose
        case 1:      uvbWindow
        case 2:      fabricPrimer
        case 3:      welcome
        case 4:      ancestryStep
        case stepCount - 1: result
        default:     question(PhototypeQuestionnaire.questions[step - Self.firstQuestionStep])
        }
    }

    // MARK: - Pages d'explication

    private func page(_ symbol: String, _ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 52))
                .foregroundStyle(Theme.vitaminD)

            Text(title)
                .font(.largeTitle.weight(.semibold))

            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }

    private var purpose: some View {
        page("sun.max.trianglebadge.exclamationmark", "À quoi sert cette application", """
        Le Soleil fabrique votre vitamine D et abîme votre peau par le même \
        rayonnement, dans les mêmes minutes. Il n'existe aucune exposition qui \
        donne l'un sans l'autre : toute la question est le rapport entre les deux.

        L'application tient donc deux comptes en parallèle — ce que vous \
        produisez, et ce que vous dépensez — puis vous dit quand sortir, \
        combien de temps, et quand rentrer.

        Elle n'est pas un dispositif médical, et ne mesure rien dans votre sang. \
        Elle calcule des ordres de grandeur à partir de la position du Soleil, \
        de la météo, de votre peau et de votre tenue.
        """)
    }

    private var uvbWindow: some View {
        page("angle", "Pourquoi la hauteur du Soleil décide de tout", """
        Seuls les UVB déclenchent la synthèse, et l'ozone les absorbe bien plus \
        fortement que le reste du rayonnement. Quand le Soleil descend, le trajet \
        dans l'atmosphère s'allonge et les UVB disparaissent les premiers.

        Il reste alors de la lumière, de la chaleur, un indice UV non nul — et \
        pourtant plus rien pour la vitamine D. Un soleil de fin d'après-midi peut \
        vous brûler sans rien produire du tout.

        D'où la règle de l'ombre, qui ne demande aucun instrument : tant que votre \
        ombre est plus courte que vous, le Soleil dépasse 45° et les UVB passent. \
        C'est aussi pourquoi il existe, sous nos latitudes, une saison entière où \
        aucune durée d'exposition ne produit quoi que ce soit.
        """)
    }

    private var fabricPrimer: some View {
        page("tshirt", "Ce que les vêtements laissent passer", """
        La surface de peau découverte entre directement dans le calcul : doubler \
        la surface exposée divise par deux le temps nécessaire. C'est le réglage \
        le plus utile à tenir à jour, et il est en première page.

        Le tissu n'est pas un mur pour autant. Un t-shirt de coton blanc arrête \
        environ 90 % du rayonnement, un tissu foncé et serré presque tout, un \
        jean la totalité. Mais un tissu mouillé ou distendu en laisse passer \
        bien davantage — un t-shirt blanc trempé ne protège presque plus.

        L'application fait l'hypothèse simple que la peau couverte ne reçoit \
        rien. Sous un vêtement épais c'est exact ; sous un t-shirt fin et clair, \
        cela sous-estime un peu la vitamine D produite, mais aussi le risque de \
        rougeur. Retenez-le les jours de forte chaleur.
        """)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "person.crop.circle")
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
        guard step >= Self.firstQuestionStep, step < stepCount - 1 else { return true }
        let question = PhototypeQuestionnaire.questions[step - Self.firstQuestionStep]
        return questionnaire.answers[question.id] != nil
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
