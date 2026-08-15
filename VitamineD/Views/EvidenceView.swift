import SwiftUI

/// D'où viennent les chiffres, et jusqu'où ils engagent.
///
/// L'application affiche un objectif en unités internationales et des durées à
/// la minute : deux choses qui ressemblent à une ordonnance sans en être une.
/// Cette page dit pour chaque valeur qui la publie, et ce qu'elle vaut — une
/// recommandation réglementaire, une moyenne de population, ou une convention
/// de calcul.
struct EvidenceView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                preamble
                referenceCard
                bodyCard
                skinCard
                yourGoal
                MedicalNotice()
            }
            .padding(16)
        }
        .background(SkyBackground(
            solarElevation: model.solarPosition?.elevation ?? -90,
            cloudCover: model.currentConditions?.cloudCover ?? 0))
        .navigationTitle("Les sources")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var preamble: some View {
        Card {
            Text("""
            Trois familles de chiffres se croisent dans cette application, et \
            elles n'ont pas du tout le même poids. Les apports de référence sont \
            réglementaires. La correction de corpulence vient de la littérature, \
            qui est cohérente mais moins tranchée. Les seuils cutanés, enfin, \
            sont des moyennes de population appliquées à votre peau, que \
            personne n'a mesurée.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Apports de référence

    private var referenceCard: some View {
        Card(title: "L'apport de référence", systemImage: "text.book.closed") {
            row("Jusqu'à 70 ans",
                "\(Int(VitaminDTarget.referenceIntakeUnder70)) UI/jour",
                tint: Theme.vitaminD)
            GoldRule()
            row("Au-delà de 70 ans",
                "\(Int(VitaminDTarget.referenceIntakeOver70)) UI/jour",
                tint: Theme.vitaminD)
            GoldRule()
            row("Apport maximal tolérable",
                "\(Int(VitaminDTarget.tolerableUpperIntake)) UI/jour")

            Text("""
            Ce sont les valeurs de Santé Canada, reprises de l'Institute of \
            Medicine, et les seules de cette page à avoir une autorité \
            réglementaire. Une précision compte : elles sont définies pour un \
            apport alimentaire, chez des personnes à exposition solaire \
            minimale. Les employer comme cible de synthèse cutanée est une \
            simplification volontaire, et elle penche du côté prudent — on ne \
            s'intoxique pas à la vitamine D par le seul Soleil, le \
            photo-équilibre de la peau s'en charge.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Corpulence

    private var bodyCard: some View {
        Card(title: "Pourquoi la corpulence entre en jeu", systemImage: "figure") {
            Text("""
            La vitamine D est liposoluble : elle se répartit dans la masse \
            grasse, où elle devient moins disponible pour la circulation. À dose \
            égale, la concentration sanguine monte d'environ 13 nmol/L par \
            1 000 UI chez une personne de corpulence normale, 11,5 en surpoids \
            et 8,6 en obésité. Les auteurs qui en tirent une posologie \
            recommandent une fois et demie la dose en surpoids, et deux à trois \
            fois en obésité.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)

            GoldRule()

            row("Corpulence normale", "× 1")
            row("Surpoids (IMC 25 à 30)", "× 1,5")
            row("Obésité (IMC ≥ 30)", "× 2")

            Text("""
            Le bas de la fourchette publiée est retenu — deux fois plutôt que \
            trois — parce qu'un objectif trop haut pousserait à s'exposer \
            davantage, donc à dépenser du capital cutané, pour une cible que \
            rien ne vient vérifier. C'est un arbitrage de prudence, pas un \
            résultat d'étude.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Peau

    private var skinCard: some View {
        Card(title: "Les seuils cutanés", systemImage: "hand.raised") {
            Text("""
            La dose érythémale minimale — l'énergie ultraviolette au-delà de \
            laquelle la peau rougit — est tabulée par phototype de Fitzpatrick. \
            Ce sont des moyennes : à phototype égal, deux personnes peuvent \
            différer d'un facteur deux. L'application applique en plus le \
            spectre d'action érythémal normalisé (1 UVI = 25 mW/m²) et celui de \
            la synthèse de vitamine D, qui culmine vers 297 nm.

            Rien de tout cela n'est mesuré sur vous. C'est la raison pour \
            laquelle l'alerte se déclenche à une fraction du seuil, et non au \
            seuil lui-même.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)

            GoldRule()

            Text("""
            Le chiffre le plus incertain de l'application est la conversion \
            entre rayonnement reçu et unités produites. La référence usuelle — \
            une dose érythémale sur un corps découvert vaudrait dix mille à \
            vingt-cinq mille unités avalées — vient de Holick, et l'expérience \
            d'origine employait une lampe fluorescente dont le spectre diffère \
            du Soleil ; Webb et Engelsen ont montré que la transposition \
            surestime d'environ un tiers. L'application se calibre en dessous \
            de cette fourchette. Retenez l'ordre de grandeur, pas le chiffre.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Votre cas

    private var yourGoal: some View {
        let suggestion = model.profile.suggestedGoal

        return Card(title: "Dans votre cas", systemImage: "person.crop.circle") {
            row("Objectif retenu", Format.iu(model.profile.dailyGoalIU),
                tint: Theme.vitaminD)
            GoldRule()
            row("Suggestion", Format.iu(suggestion.dailyIU))
            row("Corpulence", suggestion.category.title)
            if let bmi = suggestion.bmi {
                row("IMC", String(format: "%.1f", bmi))
            }

            Text(VitaminDTarget.rationale(for: suggestion, age: model.profile.age))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Détails

    private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    NavigationStack { EvidenceView().environment(AppModel()) }
}
