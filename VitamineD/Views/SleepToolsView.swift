import SwiftUI

/// Les outils qu'on emploie pour caler son sommeil sur la lumière, et ce que
/// vaut chacun.
///
/// Le marché de ces objets est bruyant, et la publicité y tient lieu de preuve.
/// Cette page range les outils par force de preuve plutôt que par prix, et dit
/// franchement où celle-ci s'arrête. Un seul d'entre eux est gratuit et bat
/// tous les autres.
struct SleepToolsView: View {

    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                mechanism
                scale
                ForEach(SleepTool.allCases) { tool in
                    card(for: tool)
                }
                evening
                caveat
            }
            .padding(16)
        }
        .background(SkyBackground(
            solarElevation: model.solarPosition?.elevation ?? -90,
            cloudCover: model.currentConditions?.cloudCover ?? 0))
        .navigationTitle("Outils")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Le mécanisme

    private var mechanism: some View {
        Card(title: "Par où la lumière entre", systemImage: "eye") {
            Text("""
            La rétine ne sert pas qu'à voir. Elle contient des cellules \
            ganglionnaires à mélanopsine qui ne participent pas à l'image et \
            n'envoient qu'un seul message, directement au noyau \
            suprachiasmatique de l'hypothalamus : il fait jour.

            Ce noyau règle ensuite l'heure de tout le reste — libération de \
            mélatonine, pic de cortisol, température corporelle, envie de \
            dormir. La lumière du matin avance cette horloge, celle du soir la \
            retarde. Tout ce qui suit n'est qu'une façon de fournir ce signal \
            quand le Soleil ne le fournit pas.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - L'échelle

    /// L'ordre de grandeur est l'argument central, et il est contre-intuitif.
    private var scale: some View {
        Card(title: "Ce que l'œil reçoit vraiment", systemImage: "sun.max") {
            VStack(spacing: 8) {
                ForEach(Illuminance.reference) { entry in
                    HStack(alignment: .firstTextBaseline) {
                        Text(entry.place)
                            .font(.subheadline)
                        Spacer(minLength: 12)
                        Text(entry.value)
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(entry.isEffective ? Theme.vitaminD : .secondary)
                    }
                    if entry.id != Illuminance.reference.last?.id { GoldRule() }
                }
            }

            Text("""
            Une pièce bien éclairée plafonne vers 300 à 500 lux. Le seuil à \
            partir duquel l'horloge se déplace mesurablement se situe vers \
            1 000 lux, et le protocole étudié en clinique en emploie 10 000. \
            L'écart entre le dedans et le dehors n'est pas d'un facteur deux, \
            il est d'un facteur cent — et l'œil ne le sent pas, parce qu'il \
            s'adapte.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Les outils

    private func card(for tool: SleepTool) -> some View {
        Card(title: tool.title, systemImage: tool.symbolName) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(tool.dose)
                    .font(.headline)
                    .foregroundStyle(Theme.vitaminD)
                Spacer(minLength: 8)
                EvidenceBadge(strength: tool.evidence)
            }

            Text(tool.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            GoldRule()

            Label(tool.limit, systemImage: "exclamationmark.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Le soir

    private var evening: some View {
        Card(title: "Le soir, l'outil est le contraire d'une lampe",
             systemImage: "moon.stars") {
            Text("""
            Toutes les solutions du soir reviennent à retirer de la lumière, \
            non à en ajouter. Baisser les lampes deux à trois heures avant le \
            coucher ne coûte rien et agit sur le même mécanisme que tout ce qui \
            précède, dans l'autre sens.

            Votre pénombre est fixée à \(Format.minuteOfDay(model.phaseShift.dimLightMinuteOfDay)) \
            d'après votre lever visé.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var caveat: some View {
        Card(title: "Ce que ces chiffres valent", systemImage: "questionmark.circle") {
            Text("""
            Que la lumière soit le principal synchroniseur de l'horloge interne \
            ne fait aucun doute, et le sens de l'effet — le matin avance, le \
            soir retarde — est solidement établi.

            La force de la preuve varie en revanche beaucoup d'un outil à \
            l'autre, et c'est ce que dit l'étiquette de chaque carte. La \
            luminothérapie à 10 000 lux repose sur trois décennies d'essais \
            cliniques, essentiellement dans la dépression saisonnière. Les \
            simulateurs d'aube et les lunettes filtrantes ont des bases plus \
            minces, et parfois contradictoires : les lunettes du soir avancent \
            la phase de sommeil dans plusieurs essais sans qu'on retrouve \
            l'effet attendu sur la mélatonine salivaire, ce qui devrait rendre \
            prudent sur le mécanisme invoqué pour les vendre.

            Rien de tout cela n'est un traitement. Un trouble du sommeil qui \
            dure se porte chez un médecin, pas chez un marchand de lampes.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Force de la preuve

/// Étiquette de force de preuve.
///
/// Elle n'est pas décorative : elle est la seule chose qui distingue un outil
/// étudié depuis trente ans d'un objet vendu sur la foi d'un mécanisme
/// plausible.
struct EvidenceBadge: View {
    enum Strength: Int, Comparable, Sendable {
        case solid, moderate, thin

        static func < (lhs: Strength, rhs: Strength) -> Bool { lhs.rawValue < rhs.rawValue }

        var title: String {
            switch self {
            case .solid:    return "Preuve solide"
            case .moderate: return "Preuve modérée"
            case .thin:     return "Preuve mince"
            }
        }

        var tint: Color {
            switch self {
            case .solid:    return Color(red: 0.30, green: 0.66, blue: 0.42)
            case .moderate: return Color(red: 0.95, green: 0.72, blue: 0.20)
            case .thin:     return .secondary
            }
        }
    }

    let strength: Strength

    var body: some View {
        Text(strength.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(strength.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(strength.tint.opacity(0.14), in: Capsule())
    }
}

// MARK: - Catalogue

/// Repères d'éclairement, pour rendre l'ordre de grandeur palpable.
struct Illuminance: Identifiable, Sendable {
    let place: String
    let value: String
    /// L'éclairement suffit-il à déplacer l'horloge ?
    let isEffective: Bool

    var id: String { place }

    static let reference: [Illuminance] = [
        .init(place: "Chambre au réveil", value: "10 lux", isEffective: false),
        .init(place: "Salon éclairé", value: "300 lux", isEffective: false),
        .init(place: "Bureau bien éclairé", value: "500 lux", isEffective: false),
        .init(place: "Seuil d'effet mesurable", value: "1 000 lux", isEffective: true),
        .init(place: "Lampe de luminothérapie", value: "10 000 lux", isEffective: true),
        .init(place: "Dehors, ciel couvert", value: "10 000 lux", isEffective: true),
        .init(place: "Dehors, plein Soleil", value: "100 000 lux", isEffective: true),
    ]
}

/// Les outils, dans l'ordre où il vaut la peine de les essayer.
enum SleepTool: String, CaseIterable, Identifiable, Sendable {
    case daylight
    case lightBox
    case dawnSimulator
    case blueBlockers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daylight:      return "Le Soleil"
        case .lightBox:      return "Lampe de luminothérapie"
        case .dawnSimulator: return "Simulateur d'aube"
        case .blueBlockers:  return "Lunettes filtrantes du soir"
        }
    }

    var symbolName: String {
        switch self {
        case .daylight:      return "sun.horizon"
        case .lightBox:      return "lamp.desk"
        case .dawnSimulator: return "sunrise"
        case .blueBlockers:  return "eyeglasses"
        }
    }

    var dose: String {
        switch self {
        case .daylight:      return "10 à 30 min, dès le lever"
        case .lightBox:      return "10 000 lux, 20 à 30 min"
        case .dawnSimulator: return "crescendo de 30 à 90 min"
        case .blueBlockers:  return "2 à 3 h avant le coucher"
        }
    }

    var evidence: EvidenceBadge.Strength {
        switch self {
        case .daylight:      return .solid
        case .lightBox:      return .solid
        case .dawnSimulator: return .moderate
        case .blueBlockers:  return .thin
        }
    }

    var summary: String {
        switch self {
        case .daylight:
            return """
            Gratuit, et plus puissant que tout ce qui se vend : dix mille lux \
            sous un ciel couvert, cent mille en plein Soleil. Aucune lampe \
            n'approche cela. C'est le seul outil de cette liste que \
            l'application planifie elle-même, dans la carte du matin.
            """
        case .lightBox:
            return """
            Le protocole étudié est stable depuis trente ans : dix mille lux \
            pendant vingt à trente minutes, dans l'heure qui suit le réveil. \
            La lampe se place de côté et un peu au-dessus des yeux, sans qu'on \
            la fixe, pendant qu'on déjeune ou qu'on lit. C'est le recours quand \
            le Soleil ne se lève pas assez tôt — de novembre à février sous nos \
            latitudes.
            """
        case .dawnSimulator:
            return """
            Une lumière qui monte en intensité avant l'heure du réveil, pour \
            sortir du sommeil par la lumière plutôt que par la sonnerie. Elle \
            plafonne vers deux à trois cents lux : très en deçà d'une lampe de \
            luminothérapie, et en deçà du seuil d'effet franc. Utile pour la \
            difficulté à émerger et l'humeur des matins d'hiver, insuffisant \
            pour déplacer une horloge nettement décalée.
            """
        case .blueBlockers:
            return """
            Des verres qui retirent le bleu des écrans et des lampes du soir. \
            Plusieurs essais y trouvent une avance de la phase de sommeil et un \
            réveil plus facile. Mais l'effet sur la mélatonine salivaire, qui \
            est le mécanisme invoqué pour les vendre, ne se retrouve pas \
            toujours — ce qui invite à la prudence sur les promesses.
            """
        }
    }

    var limit: String {
        switch self {
        case .daylight:
            return "Ne fonctionne que si le Soleil est levé quand vous l'êtes."
        case .lightBox:
            return "Contre-indiquée en cas de trouble bipolaire ou de maladie rétinienne "
                + "sans avis médical : elle peut déclencher un virage maniaque."
        case .dawnSimulator:
            return "Trop faible pour un décalage important. À compléter par du vrai jour."
        case .blueBlockers:
            return "Ne remplace pas le fait de baisser les lumières : filtrer un écran "
                + "brillant laisse passer beaucoup plus qu'éteindre la pièce."
        }
    }
}

#Preview {
    NavigationStack { SleepToolsView().environment(AppModel()) }
}
