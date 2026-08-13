import SwiftUI

/// À quoi sert la vitamine D, et ce que la preuve soutient réellement.
///
/// Les affirmations sur la vitamine D circulent avec une confiance que les
/// données ne justifient pas toujours. Cette page distingue explicitement ce qui
/// est établi de ce qui reste une association — et sépare surtout deux choses
/// qu'on confond sans cesse : les effets de la *vitamine D*, et ceux de la
/// *lumière*, qui n'empruntent pas du tout le même chemin biologique.
struct VitaminDPrimerView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                intro

                section(
                    strength: .established,
                    title: "L'os et le muscle",
                    body: """
                    C'est le rôle pour lequel la vitamine D a été découverte, et \
                    le seul qui ne prête à aucune discussion. Elle commande \
                    l'absorption intestinale du calcium et du phosphate. Sans \
                    elle, le calcium alimentaire traverse sans être absorbé — \
                    d'où le rachitisme chez l'enfant, l'ostéomalacie chez \
                    l'adulte.

                    La faiblesse musculaire proximale et l'augmentation du risque \
                    de chute chez les personnes âgées carencées relèvent du même \
                    mécanisme, et se corrigent par la supplémentation.
                    """)

                section(
                    strength: .plausible,
                    title: "L'immunité",
                    body: """
                    Les cellules immunitaires portent des récepteurs à la \
                    vitamine D, et celle-ci commande la production de \
                    cathélicidine, un peptide antimicrobien. Le mécanisme est \
                    réel et bien décrit.

                    Ce que les essais montrent est plus modeste que le mécanisme \
                    ne le laisserait espérer. Les méta-analyses de \
                    supplémentation trouvent une réduction faible des infections \
                    respiratoires, concentrée chez les personnes réellement \
                    carencées au départ. Chez quelqu'un dont le statut est déjà \
                    correct, en ajouter n'apporte à peu près rien.

                    Autrement dit : corriger une carence aide. Se supplémenter \
                    au-delà n'est pas un bouclier.
                    """)

                section(
                    strength: .uncertain,
                    title: "Le sommeil",
                    body: """
                    Les études d'observation associent régulièrement un statut \
                    bas en vitamine D à un sommeil de moins bonne qualité et plus \
                    court. Mais l'association est fragile à interpréter : les \
                    gens qui dorment mal sortent moins, et sortir moins abaisse \
                    le statut en vitamine D. La flèche causale pourrait pointer \
                    dans l'autre sens, ou les deux.

                    Les essais de supplémentation donnent des résultats \
                    inconstants. Il serait malhonnête de vous promettre un \
                    meilleur sommeil en vous exposant davantage.
                    """)

                section(
                    strength: .established,
                    title: "La lumière et l'horloge interne",
                    body: """
                    Voilà, en revanche, un effet du soleil sur le sommeil qui ne \
                    fait aucun doute — et il n'a rien à voir avec la vitamine D.

                    La lumière est le principal synchroniseur de l'horloge \
                    circadienne. Des cellules rétiniennes spécialisées, sensibles \
                    au bleu, informent directement le noyau suprachiasmatique de \
                    l'heure qu'il fait dehors. C'est ce signal qui cale l'heure \
                    d'endormissement, la sécrétion de mélatonine et la \
                    température corporelle.

                    Et le contraste est écrasant : même sous un ciel couvert, \
                    l'extérieur dépasse 10 000 lux, contre 100 à 500 lux dans une \
                    pièce éclairée. Une fenêtre ne suffit pas.

                    C'est aussi l'exact inverse de la fenêtre vitamine D : le \
                    Soleil bas du matin ne produit aucun UVB utile, mais c'est le \
                    meilleur moment pour caler l'horloge.
                    """)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Ce que l'application ne mesure pas")
                        .font(.headline)
                    Text("""
                    Elle calcule ce que votre peau *produit*, pas ce que votre \
                    sang *contient*. Les deux ne se recoupent qu'en partie : \
                    l'alimentation, les suppléments, la masse grasse — la \
                    vitamine D y est stockée — et la génétique pèsent tout \
                    autant.

                    Seul un dosage sanguin de 25-hydroxyvitamine D dit où vous en \
                    êtes réellement. Si la question vous importe, c'est par là \
                    qu'il faut commencer, pas par une application.
                    """)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
        .navigationTitle("À quoi ça sert")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        Text("""
        Les affirmations sur la vitamine D circulent avec plus d'assurance que \
        les données n'en autorisent. Chaque section ci-dessous indique donc la \
        force de la preuve, et non seulement le mécanisme.
        """)
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private enum Strength {
        case established, plausible, uncertain

        var label: String {
            switch self {
            case .established: return "Établi"
            case .plausible:   return "Effet réel mais modeste"
            case .uncertain:   return "Association, causalité incertaine"
            }
        }

        var colour: Color {
            switch self {
            case .established: return Color(red: 0.30, green: 0.66, blue: 0.42)
            case .plausible:   return Color(red: 0.95, green: 0.72, blue: 0.20)
            case .uncertain:   return .secondary
            }
        }
    }

    private func section(strength: Strength, title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(strength.label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(strength.colour)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(strength.colour.opacity(0.14), in: Capsule())

            Text(title).font(.headline)

            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack { VitaminDPrimerView() }
}
