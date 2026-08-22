import Foundation

/// Les lumières artificielles qu'on oppose à l'hiver, et ce qu'elles font
/// réellement.
///
/// ## Trois choses que le commerce confond
///
/// « Lumière rouge », « luminothérapie » et « photobiomodulation » se vendent
/// souvent ensemble, comme si c'était une seule chose déclinée. Ce sont trois
/// interventions distinctes, de longueurs d'onde différentes, aux preuves très
/// inégales, et qui ne traitent pas le même problème. Les séparer est la
/// première chose utile que cette application puisse faire ici.
///
/// ## Ce qu'aucune ne fait
///
/// **Aucune ne produit de vitamine D.** Pas une seule. La synthèse cutanée
/// demande des UVB autour de 298 nm ; le rouge est à 660 nm et le proche
/// infrarouge à 850. Il y a plus de deux cents nanomètres d'écart, et le
/// 7-déhydrocholestérol n'absorbe rien dans le rouge. Une lampe rouge ne
/// remplace donc ni le Soleil de juin, ni un supplément en janvier — c'est
/// exactement le malentendu qui justifie que cette section existe.
///
/// Ce qui compense un hiver vitaminique tient en deux lignes : l'alimentation
/// et la supplémentation. Le reste de cet écran traite d'autre chose — l'humeur,
/// l'horloge interne, la peau — qui sont de vraies questions d'hiver, mais qui
/// ne sont pas la vitamine D.
enum LightTherapy {

    /// Une modalité de lumière artificielle.
    enum Modality: String, CaseIterable, Codable, Identifiable, Sendable {
        /// Lumière blanche vive, le matin. La seule dont l'effet hivernal soit
        /// solidement établi.
        case brightLight
        /// Rouge et proche infrarouge appliqués à la peau.
        case photobiomodulation
        /// Éclairage rouge tamisé le soir, pour ne pas repousser l'endormissement.
        case eveningRed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .brightLight:        return "Luminothérapie"
            case .photobiomodulation: return "Rouge et proche infrarouge"
            case .eveningRed:         return "Rouge du soir"
            }
        }

        var subtitle: String {
            switch self {
            case .brightLight:        return "Lumière blanche vive, au réveil"
            case .photobiomodulation: return "660 et 850 nm, sur la peau"
            case .eveningRed:         return "Éclairage tamisé après le souper"
            }
        }

        var symbolName: String {
            switch self {
            case .brightLight:        return "sun.max.fill"
            case .photobiomodulation: return "waveform.path"
            case .eveningRed:         return "moon.stars.fill"
            }
        }

        /// Durée conseillée d'une séance.
        var duration: TimeInterval {
            switch self {
            case .brightLight:        return 30 * 60
            case .photobiomodulation: return 10 * 60
            case .eveningRed:         return 90 * 60
            }
        }

        /// Ce que la modalité vise. Jamais la vitamine D — voir la note du type.
        var purpose: String {
            switch self {
            case .brightLight:
                return "Humeur d'hiver et horloge interne"
            case .photobiomodulation:
                return "Peau, courbatures, récupération"
            case .eveningRed:
                return "Endormissement"
            }
        }

        var evidence: EvidenceStrength {
            switch self {
            case .brightLight:        return .solid
            case .photobiomodulation: return .thin
            case .eveningRed:         return .moderate
            }
        }

        /// Ce qu'on sait, et d'où on le sait.
        var rationale: String {
            switch self {
            case .brightLight:
                return "C'est la seule des trois dont l'effet hivernal soit "
                    + "solidement établi. Les méta-analyses sur le trouble "
                    + "affectif saisonnier donnent une taille d'effet autour de "
                    + "0,8 pour un protocole devenu standard : 10 000 lux, une "
                    + "trentaine de minutes, le matin. Le mécanisme est celui de "
                    + "l'horloge interne, pas celui de la peau — la lumière entre "
                    + "par l'œil.\n\n"
                    + "Le repère qui remet les choses en place : une journée "
                    + "d'hiver couverte donne déjà 1 000 à 10 000 lux dehors, et "
                    + "une journée ensoleillée dépasse 50 000. Une lampe à "
                    + "10 000 lux ne fait donc que remplacer une sortie qu'on "
                    + "n'a pas faite."
            case .photobiomodulation:
                return "Le rouge et le proche infrarouge sont absorbés par la "
                    + "cytochrome c oxydase des mitochondries, ce qui est établi. "
                    + "Ce qui l'est beaucoup moins, c'est la dose. La réponse est "
                    + "biphasique — une courbe d'Arndt-Schulz : trop peu ne fait "
                    + "rien, trop fait moins que la bonne dose. Huang, Sharma, "
                    + "Carroll et Hamblin, qui ont établi ce comportement, "
                    + "écrivent que les valeurs de fluence et d'irradiance où se "
                    + "produisent ces transitions ne font pas l'objet d'un accord, "
                    + "et que la forme biphasique a été observée sur cellules et "
                    + "chez l'animal, mais pas dans les essais cliniques.\n\n"
                    + "Autrement dit : le mécanisme existe, la posologie non. "
                    + "Suivez le mode d'emploi de votre appareil plutôt que ce "
                    + "minuteur, qui ne connaît ni sa puissance ni votre distance."
            case .eveningRed:
                return "Ce n'est pas un traitement, c'est un retrait. La "
                    + "mélanopsine des cellules ganglionnaires rétiniennes, qui "
                    + "renseigne l'horloge interne, culmine vers 480 nm — dans le "
                    + "bleu. Le rouge profond y est presque invisible. Éclairer "
                    + "en rouge le soir revient donc à laisser la mélatonine "
                    + "monter à l'heure, sans se priver de lumière.\n\n"
                    + "L'effet vient de ce qu'on retire, pas de ce qu'on ajoute. "
                    + "Une pièce sombre ferait aussi bien."
            }
        }

        /// Ce qu'il ne faut pas en attendre. Chaque modalité en a une.
        var caveat: String {
            switch self {
            case .brightLight:
                return "Ne produit aucune vitamine D : la lumière entre par "
                    + "l'œil, et il n'y a pas d'UVB dans une lampe de "
                    + "luminothérapie. À prendre le matin — le soir, elle "
                    + "retarde l'endormissement au lieu de l'avancer."
            case .photobiomodulation:
                return "Ne produit aucune vitamine D — plus de deux cents "
                    + "nanomètres séparent le rouge des UVB, et le "
                    + "7-déhydrocholestérol n'absorbe rien dans le rouge. "
                    + "Davantage n'est pas mieux : la réponse est biphasique."
            case .eveningRed:
                return "Ne produit aucune vitamine D, et ne remplace pas la "
                    + "lumière du matin. C'est l'inverse d'une séance : moins de "
                    + "lumière bleue, pas plus de lumière rouge."
            }
        }

        /// Heure conseillée, en minutes depuis minuit, relative au réveil ou au
        /// coucher selon la modalité.
        func suggestedStart(wakeMinute: Int, bedMinute: Int) -> Int {
            switch self {
            case .brightLight:        return wakeMinute + 15
            case .photobiomodulation: return wakeMinute + 60
            case .eveningRed:         return max(0, bedMinute - 120)
            }
        }
    }

    /// Ce qu'une séance de luminothérapie vaut, comparée à une vraie sortie.
    ///
    /// Le rapport est le seul chiffre honnête à afficher : il rappelle qu'une
    /// lampe à 10 000 lux ne fait pas mieux qu'un ciel couvert, et bien moins
    /// qu'un ciel dégagé.
    static let brightLightLux = 10_000.0
    static let overcastDaylightLux = 10_000.0
    static let clearDaylightLux = 50_000.0
    static let indoorLux = 300.0

    /// Nombre de fois où l'éclairage intérieur ordinaire est dépassé.
    static var indoorRatio: Double { brightLightLux / indoorLux }
}
