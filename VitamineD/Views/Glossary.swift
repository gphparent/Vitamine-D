import SwiftUI

/// Termes que l'application emploie et qui ne vont pas de soi.
///
/// Chaque chiffre affiché repose sur une notion précise. Les montrer sans les
/// expliquer laisse l'utilisateur deviner — et deviner mal : « capital cutané »
/// évoque une réserve qui se reconstitue, alors qu'il désigne une dose qui
/// s'accumule sur une journée.
enum GlossaryEntry: String, Identifiable, CaseIterable, Sendable {
    case skinCapital
    case minimalErythemalDose
    case synthesisCeiling
    case marginalYield
    case uvIndex
    case shadowRule
    case vitaminDWinter
    case internationalUnits
    case phototype
    case acclimatisation
    case yield
    case fabric

    var id: String { rawValue }

    var term: String {
        switch self {
        case .skinCapital:          return "Capital cutané"
        case .minimalErythemalDose: return "Dose érythémale minimale (DEM)"
        case .synthesisCeiling:     return "Plafond de synthèse"
        case .marginalYield:        return "Rendement marginal"
        case .uvIndex:              return "Indice UV"
        case .shadowRule:           return "Règle de l'ombre"
        case .vitaminDWinter:       return "Hiver vitaminique"
        case .internationalUnits:   return "Unité internationale (UI)"
        case .phototype:            return "Phototype"
        case .acclimatisation:      return "Acclimatation"
        case .yield:                return "Rendement"
        case .fabric:               return "Tissu et rayonnement"
        }
    }

    /// Une phrase, pour la vue compacte.
    var summary: String {
        switch self {
        case .skinCapital:
            return "La part de votre seuil de rougeur déjà dépensée aujourd'hui."
        case .minimalErythemalDose:
            return "L'énergie UV au-delà de laquelle votre peau rougit."
        case .synthesisCeiling:
            return "Le point où prolonger l'exposition n'ajoute plus de vitamine D."
        case .marginalYield:
            return "Ce que la prochaine minute dehors rapporte encore."
        case .uvIndex:
            return "L'intensité du rayonnement qui brûle la peau, à cet instant."
        case .shadowRule:
            return "Ombre plus courte que vous : les UVB passent."
        case .vitaminDWinter:
            return "La saison où le Soleil ne monte jamais assez haut."
        case .internationalUnits:
            return "L'unité dans laquelle se compte la vitamine D."
        case .phototype:
            return "La réaction de votre peau au soleil, de I à VI."
        case .acclimatisation:
            return "Ce que les expositions récentes ont épaissi et pigmenté."
        case .yield:
            return "La vitamine D obtenue par unité de capital cutané dépensé."
        case .fabric:
            return "Ce qu'un vêtement laisse réellement passer."
        }
    }

    var explanation: String {
        switch self {
        case .skinCapital:
            return """
            Le nom est une image, et elle a ses limites. Il ne s'agit pas d'une \
            réserve qui se viderait pour de bon, mais de la dose UV accumulée \
            aujourd'hui, rapportée au seuil où votre peau rougirait.

            À 100 %, la rougeur apparaît — mais seulement quelques heures plus \
            tard. C'est ce décalage qui rend le coup de soleil si facile à \
            attraper : au moment où vous le sentez, il est fait depuis longtemps.

            Le compteur se remet à zéro chaque jour. Ce qui ne s'efface pas, en \
            revanche, ce sont les dommages accumulés sur des années — et c'est \
            pour cela que l'application vous arrête bien avant les 100 %.
            """
        case .minimalErythemalDose:
            return """
            La DEM est la quantité d'énergie ultraviolette, pondérée par la \
            sensibilité de la peau à chaque longueur d'onde, qui produit une \
            rougeur tout juste perceptible vingt-quatre heures plus tard.

            Elle varie d'un facteur cinq selon le phototype : environ 200 J/m² \
            pour un type I, 1 000 J/m² pour un type VI. C'est le seul chiffre \
            dont dépendent toutes les durées que l'application affiche.

            Une DEM n'est pas un seuil de danger, c'est un seuil de réaction \
            visible. Les dommages à l'ADN commencent bien avant.
            """
        case .synthesisCeiling:
            return """
            Au-delà d'une certaine dose, la prévitamine D3 formée dans la peau \
            se transforme en lumistérol et en tachystérol plutôt que de \
            s'accumuler. La production sature.

            La conséquence est double. D'abord, on ne peut pas s'intoxiquer à la \
            vitamine D par le seul soleil : le mécanisme s'arrête tout seul. \
            Ensuite, et c'est ce qui compte pour vous, prolonger l'exposition \
            n'ajoute plus rien du côté vitamine D — alors que le capital cutané, \
            lui, continue de se dépenser au même rythme.

            Le plafond dépend de la surface de peau découverte. Plus vous \
            exposez, plus il est haut.

            Un mot sur sa taille, parce qu'elle surprend. C'est une asymptote : \
            la courbe s'en approche sans jamais l'atteindre, et il faudrait une \
            dose infinie pour y arriver. Un plafond calculé à dix-sept mille \
            unités ne veut donc pas dire qu'on peut en produire dix-sept mille \
            dans une journée — la peau rougirait bien avant. La barre de l'écran \
            principal est graduée sur ce que la journée permet vraiment, ce qui \
            est un tout autre chiffre.
            """
        case .marginalYield:
            return """
            Le pourcentage de ce que rapportait la première minute que rapporte \
            encore la minute suivante.

            Il décroît à mesure que la synthèse approche du plafond. Sous 35 %, \
            l'application considère que rester dehors ne se justifie plus par la \
            vitamine D — ce qui ne veut pas dire qu'il faut rentrer, seulement \
            que le motif a changé.

            Surtout, il ne repart pas de 100 % parce que vous êtes rentré. \
            L'équilibre photochimique installé dans la peau ne se défait pas en \
            franchissant une porte : il se défait à mesure que la prévitamine D3 \
            quitte l'épiderme, ce qui prend des heures. Sortir dix minutes, \
            rentrer, puis ressortir ne donne donc pas deux premières minutes à \
            plein rendement — mais coûte bien deux fois le capital cutané.

            L'application retient une demi-vie de douze heures pour ce retour à \
            zéro. C'est le chiffre le moins bien établi de tout le modèle, et il \
            a été choisi prudent : s'il se trompe, c'est en annonçant un \
            rendement plus bas qu'il n'est, jamais l'inverse.
            """
        case .uvIndex:
            return """
            Une échelle définie par l'Organisation mondiale de la santé : un \
            point vaut 25 milliwatts par mètre carré de rayonnement pondéré par \
            le spectre d'action de l'érythème.

            Elle mesure ce qui brûle, pas ce qui produit de la vitamine D. Les \
            deux ne coïncident pas : le spectre d'action de la vitamine D est \
            plus court en longueur d'onde, donc plus vulnérable à l'absorption \
            par l'ozone quand le Soleil est bas. Un indice UV de 3 en fin de \
            journée ne vaut pas un indice UV de 3 à midi.
            """
        case .shadowRule:
            return """
            Tenez-vous debout au soleil et regardez votre ombre. Si elle est \
            plus courte que vous, le Soleil dépasse 45° de hauteur, et les UVB \
            traversent l'atmosphère en quantité utile.

            C'est le seul instrument de mesure que vous ayez toujours sur vous, \
            et il ne se trompe pas. L'application ne fait que le calculer à \
            l'avance et pour la journée entière.
            """
        case .vitaminDWinter:
            return """
            Au-dessus d'environ 35° de latitude, il existe une saison où le \
            Soleil ne monte jamais au-delà de 25° au-dessus de l'horizon. Le \
            trajet du rayonnement dans l'atmosphère est alors si long que \
            l'ozone absorbe la quasi-totalité des UVB.

            À Montréal, cela va de novembre à février. Le Soleil brille, \
            l'indice UV n'est pas nul, on peut même attraper un coup de soleil \
            sur les pistes de ski — mais aucune durée d'exposition ne produira \
            de vitamine D. Seules l'alimentation et la supplémentation prennent \
            le relais.
            """
        case .internationalUnits:
            return """
            Une convention de dosage : 1 UI de vitamine D vaut 0,025 microgramme \
            de cholécalciférol.

            Les apports de référence pour un adulte se situent entre 600 et \
            800 UI par jour selon les autorités, davantage pour les personnes \
            âgées ou peu exposées. L'objectif proposé par défaut dans \
            l'application, 1 000 UI, se situe dans cette fourchette haute.

            Ce que l'application compte est ce que votre peau *produit*, pas ce \
            que votre sang *contient*. Seule une prise de sang mesure la seconde.
            """
        case .phototype:
            return """
            L'échelle de Fitzpatrick, de I à VI, classe les peaux selon leur \
            réaction au soleil : à quelle vitesse elles brûlent, à quelle \
            vitesse elles bronzent.

            Elle a été construite sur la réaction, et non sur l'apparence, \
            précisément parce que la couleur perçue prédit mal le seuil de \
            rougeur. On peut avoir les cheveux noirs et les yeux foncés tout en \
            brûlant en vingt minutes.
            """
        case .acclimatisation:
            return """
            Les expositions répétées épaississent la couche cornée et \
            déclenchent la production de mélanine. Le seuil de rougeur s'en \
            trouve relevé — jusqu'à environ 60 % pour les phototypes clairs.

            C'est une protection réelle mais modeste : un bronzage installé \
            équivaut à un indice de protection de 3 ou 4, pas davantage. Et il \
            se paie en dommages cumulés, puisqu'il est lui-même une réponse à \
            une agression.
            """
        case .yield:
            return """
            La vitamine D obtenue divisée par le capital cutané dépensé pour \
            l'obtenir.

            Dans ce rapport, l'indice UV se simplifie : il figure au numérateur \
            comme au dénominateur. Le rendement ne dépend donc que de la hauteur \
            du Soleil, et il croît avec elle jusqu'à saturer vers 65°.

            D'où une conclusion qui renverse le conseil courant : il n'existe \
            aucun créneau discret où l'on gagnerait plus pour moins de risque. \
            Le meilleur rapport est toujours le Soleil le plus haut — à \
            condition d'y rester peu. À 20° de hauteur, il faut dépenser huit \
            fois plus de capital cutané pour la même vitamine D qu'à 65°.
            """
        case .fabric:
            return """
            Un vêtement n'est pas un interrupteur. Il se mesure par un indice de \
            protection, l'UPF, qui dit quelle fraction du rayonnement il arrête.

            Un t-shirt de coton blanc se situe vers UPF 10 : il laisse passer \
            environ un dixième du rayonnement. Un tissu foncé, serré ou \
            synthétique monte à plusieurs centaines, et un jean arrête tout. \
            Trois choses font chuter la protection — l'humidité, l'étirement et \
            l'usure. Un t-shirt blanc mouillé peut tomber vers UPF 3, soit à \
            peine mieux que rien.

            L'application retient l'hypothèse simple : la peau couverte ne reçoit \
            rien, la peau découverte reçoit tout. Sous un vêtement épais c'est \
            juste. Sous un t-shirt fin, cela sous-estime la vitamine D produite — \
            et, ce qui compte davantage, cela sous-estime aussi le rayonnement \
            reçu. Les jours de forte chaleur, où les tissus sont fins et humides, \
            considérez que vous êtes un peu plus exposé que ce qui est affiché.
            """
        }
    }
}

/// Petit bouton d'information, à poser près d'un chiffre.
struct GlossaryButton: View {
    let entry: GlossaryEntry
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Qu'est-ce que « \(entry.term) » ?")
        .sheet(isPresented: $isPresented) {
            GlossarySheet(entry: entry)
                .presentationDetents([.medium, .large])
        }
    }
}

/// Le texte seul, sans habillage de navigation, pour pouvoir être aussi bien
/// présenté en feuille que poussé depuis une liste.
struct GlossaryDetail: View {
    let entry: GlossaryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(entry.summary)
                    .font(.headline)
                    .foregroundStyle(Theme.vitaminD)
                Text(entry.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .navigationTitle(entry.term)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct GlossarySheet: View {
    let entry: GlossaryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GlossaryDetail(entry: entry)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Fermer") { dismiss() }
                    }
                }
        }
    }
}

/// Le glossaire entier, accessible depuis le profil.
struct GlossaryListView: View {
    var body: some View {
        List(GlossaryEntry.allCases) { entry in
            NavigationLink {
                GlossaryDetail(entry: entry)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.term).font(.subheadline.weight(.medium))
                    Text(entry.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Glossaire")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { GlossaryListView() }
}
