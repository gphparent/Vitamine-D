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
                disputeCard
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
            aucune n'est solide au même degré. Les apports recommandés sont \
            l'objet d'un désaccord ouvert entre institutions, et le plus bas \
            d'entre eux est contesté jusque dans son calcul. La correction de \
            corpulence vient de la littérature, cohérente mais moins tranchée. \
            Les seuils cutanés, enfin, sont des moyennes de population \
            appliquées à votre peau, que personne n'a mesurée.

            Rien de tout cela n'est présenté ici comme une vérité \
            administrative. Ce sont des repères publiés, avec leurs auteurs et \
            leurs limites, et vous restez libre de fixer votre objectif où bon \
            vous semble.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Apports de référence

    private var referenceCard: some View {
        Card(title: "Il n'y a pas de chiffre officiel", systemImage: "text.book.closed") {
            row("Institute of Medicine, repris par Santé Canada",
                "\(Int(VitaminDTarget.dietaryReferenceUnder70)) UI/jour")
            GoldRule()
            row("Endocrine Society",
                "\(Int(VitaminDTarget.clinicalReferenceLower)) à "
                    + "\(Int(VitaminDTarget.clinicalReferenceUpper)) UI/jour")
            GoldRule()
            row("Apport maximal tolérable",
                "\(Int(VitaminDTarget.tolerableUpperIntake)) UI/jour")

            Text("""
            Deux institutions également sérieuses, un écart d'un facteur trois. \
            Le désaccord ne porte pas sur l'arithmétique mais sur le seuil de \
            suffisance : l'Institute of Medicine vise 50 nmol/L dans le sang, \
            l'Endocrine Society 75. Ce sont deux définitions différentes de \
            « ne pas manquer », et aucune des deux n'est la bonne réponse \
            évidente.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    /// Le chiffre bas est en outre contesté dans son calcul même.
    ///
    /// Ce n'est pas un détail d'école : c'est la raison pour laquelle
    /// l'application ne présente aucune de ces valeurs comme une autorité.
    private var disputeCard: some View {
        Card(title: "Et le chiffre bas est contesté", systemImage: "exclamationmark.bubble") {
            Text("""
            Veugelers et Ekwaru ont montré en 2014 que l'Institute of Medicine \
            avait commis une erreur statistique dans le calcul de son apport \
            recommandé. En reprenant ses propres données, l'apport qui \
            garantirait 50 nmol/L chez 97,5 % des gens — la définition même d'un \
            apport recommandé — ressort à près de 8 900 UI par jour, et non à \
            600. Des statisticiens indépendants ont refait le calcul et l'ont \
            confirmé.

            Cela ne veut pas dire qu'il faille prendre 8 900 UI. Cette valeur \
            extrapole bien au-delà des données disponibles, qui ne comportaient \
            personne au-dessus de 2 400 UI par jour, et l'institution en \
            conteste la portée. Mais cela veut dire qu'un apport de 600 UI ne \
            peut pas être présenté comme un chiffre solide : c'est la borne \
            basse d'une fourchette, et la plus fragile des deux.

            D'où le parti pris de cette application : afficher la fourchette et \
            en proposer le milieu, plutôt que de nommer une autorité. Un \
            objectif ne commande d'ailleurs jamais l'exposition — la limite \
            cutanée passe toujours devant.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)

            GoldRule()

            Text("""
            Une précision qui vaut pour toutes ces valeurs : elles sont définies \
            pour un apport *alimentaire*, chez des personnes à exposition \
            solaire minimale. Les employer comme cible de synthèse cutanée est \
            une simplification volontaire, et elle penche du côté prudent — on \
            ne s'intoxique pas à la vitamine D par le seul Soleil, le \
            photo-équilibre de la peau s'en charge.
            """)
            .font(.caption)
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
            row("Fourchette publiée",
                "\(Int(suggestion.lowerIU)) à \(Int(suggestion.upperIU)) UI")
            row("Milieu, proposé par défaut", Format.iu(suggestion.dailyIU))
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
