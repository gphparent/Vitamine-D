import Foundation

/// Force de la preuve derrière une recommandation.
///
/// Vit ici, avec les recommandations qu'elle qualifie, et non dans la vue qui
/// l'affiche : c'est une propriété de l'affirmation, pas de son étiquette.
enum EvidenceStrength: Int, Comparable, Sendable {
    case solid, moderate, thin

    static func < (lhs: EvidenceStrength, rhs: EvidenceStrength) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var title: String {
        switch self {
        case .solid:    return "Preuve solide"
        case .moderate: return "Preuve modérée"
        case .thin:     return "Preuve mince"
        }
    }
}

/// La soirée et le matin, heure par heure, à partir de l'heure de lever visée.
///
/// ## Pourquoi une routine plutôt qu'un catalogue
///
/// Ce qui décide de la qualité d'une nuit se joue en grande partie **avant**
/// elle, et à des heures précises que personne ne retient. Savoir que la
/// caféine a une demi-vie de cinq à six heures ne sert à rien ; recevoir une
/// alerte à quinze heures parce qu'on se couche à vingt-trois heures, si.
///
/// Chaque étape porte donc une heure calculée, une raison, et une force de
/// preuve. Aucune n'est imposée : ce sont des rappels quotidiens qu'on active
/// un par un.
///
/// ## Ce qui n'est pas ici
///
/// Rien de tout ceci ne traite un trouble du sommeil. L'insomnie chronique se
/// soigne, et son traitement de première intention est une thérapie
/// cognitivo-comportementale, pas une liste de bonnes habitudes.
enum SleepRoutineStep: String, CaseIterable, Identifiable, Codable, Sendable {
    case caffeineCutoff
    case lastMeal
    case exerciseCutoff
    case dimLights
    case warmBath
    case screensOff
    case bedtime
    case wake
    case morningLight

    var id: String { rawValue }

    /// Point de référence de l'étape.
    enum Anchor: Sendable {
        case bedtime
        case wake
    }

    var anchor: Anchor {
        switch self {
        case .wake, .morningLight: return .wake
        default:                   return .bedtime
        }
    }

    /// Décalage en minutes par rapport au point de référence. Négatif = avant.
    var offsetMinutes: Int {
        switch self {
        case .caffeineCutoff: return -480
        case .lastMeal:       return -180
        case .exerciseCutoff: return -90
        case .dimLights:      return -Int(CircadianPlanner.eveningDimLead / 60)
        case .warmBath:       return -90
        case .screensOff:     return -60
        case .bedtime:        return 0
        case .wake:           return 0
        case .morningLight:   return 15
        }
    }

    var title: String {
        switch self {
        case .caffeineCutoff: return "Dernier café"
        case .lastMeal:       return "Dernier repas copieux"
        case .exerciseCutoff: return "Fin de l'effort intense"
        case .dimLights:      return "Baisser les lumières"
        case .warmBath:       return "Bain ou douche chaude"
        case .screensOff:     return "Écrans de côté"
        case .bedtime:        return "Au lit"
        case .wake:           return "Lever"
        case .morningLight:   return "Lumière du matin"
        }
    }

    var symbolName: String {
        switch self {
        case .caffeineCutoff: return "cup.and.saucer"
        case .lastMeal:       return "fork.knife"
        case .exerciseCutoff: return "figure.run"
        case .dimLights:      return "lightbulb.slash"
        case .warmBath:       return "shower"
        case .screensOff:     return "iphone.slash"
        case .bedtime:        return "bed.double"
        case .wake:           return "alarm"
        case .morningLight:   return "sun.horizon"
        }
    }

    /// Ce que dit la recherche, et jusqu'où elle va.
    var rationale: String {
        switch self {
        case .caffeineCutoff:
            return """
            La caféine a une demi-vie de cinq à six heures : la moitié de votre \
            espresso de seize heures circule encore à vingt-deux. Un essai de \
            référence a donné 400 mg — deux grandes tasses — six heures avant le \
            coucher : le temps de sommeil mesuré a chuté de plus d'une heure, \
            sans que les participants s'en rendent compte. Six heures est donc \
            un plancher, pas une marge ; huit sont plus sûres.
            """
        case .lastMeal:
            return """
            La digestion élève la température centrale, or l'endormissement \
            demande qu'elle baisse. Un repas copieux tardif retarde \
            l'endormissement et fragmente la première moitié de la nuit. Trois \
            heures suffisent dans la plupart des cas ; une collation légère ne \
            pose pas de problème.
            """
        case .exerciseCutoff:
            return """
            Contrairement à ce qu'on répète, l'exercice du soir ne nuit pas au \
            sommeil : une méta-analyse de vingt-trois essais lui trouve même \
            plus de sommeil lent profond. La réserve porte sur l'intensité — un \
            effort vigoureux qui se termine dans l'heure précédant le coucher \
            retarde l'endormissement, le cœur et la température n'ayant pas eu \
            le temps de redescendre.
            """
        case .dimLights:
            return """
            La mélatonine ne se libère qu'en pénombre, et la lumière du soir \
            retarde l'horloge interne — exactement l'inverse de celle du matin. \
            Deux à trois heures de lumière basse avant le coucher visé laissent \
            à la sécrétion le temps de démarrer. C'est la même heure que celle \
            qu'affiche la carte du soir.
            """
        case .warmBath:
            return """
            Le geste le mieux documenté de cette liste, et le moins connu. Une \
            méta-analyse de treize essais : dix minutes dans une eau à 40-42 °C, \
            une à deux heures avant le coucher, raccourcissent le délai \
            d'endormissement d'environ un tiers. Le mécanisme est \
            contre-intuitif — se réchauffer dilate les vaisseaux des mains et \
            des pieds, ce qui évacue la chaleur et fait *baisser* la température \
            centrale, signal d'endormissement.
            """
        case .screensOff:
            return """
            L'écran agit par deux voies qu'il faut distinguer. Sa lumière \
            retarde l'horloge, mais un téléphone à bout de bras éclaire bien \
            moins qu'une lampe de plafond : à ce compte, baisser les lumières \
            de la pièce compte davantage. Ce qui coûte vraiment, c'est le \
            contenu — une application conçue pour retenir l'attention retient \
            aussi l'éveil. D'où l'intérêt d'un blocage automatique plutôt que \
            d'une résolution.
            """
        case .bedtime:
            return """
            La régularité pèse plus lourd que la durée. Sur près de \
            61 000 personnes suivies à l'accéléromètre, l'irrégularité des \
            heures de sommeil prédit la mortalité toutes causes mieux que le \
            nombre d'heures dormies — de vingt à quarante-huit pour cent de \
            risque en moins pour les plus réguliers. Se coucher à la même heure \
            sept jours sur sept vaut mieux que dormir plus longtemps le samedi.
            """
        case .wake:
            return """
            L'heure de lever est le point d'ancrage de toute l'horloge, et c'est \
            elle qu'il faut tenir en premier — y compris la fin de semaine. Un \
            lever décalé de deux heures le samedi produit l'équivalent d'un \
            décalage horaire de deux fuseaux, à refaire chaque lundi.
            """
        case .morningLight:
            return """
            La lumière reçue dans l'heure qui suit le lever avance l'horloge et \
            fixe, environ seize heures plus tard, le moment où la mélatonine \
            reviendra. C'est le seul levier de cette liste qui agisse sur le \
            soir en n'étant employé que le matin — et l'onglet Sommeil calcule \
            déjà votre fenêtre.
            """
        }
    }

    /// Résumé d'une ligne, pour la liste.
    var summary: String {
        switch self {
        case .caffeineCutoff: return "8 h avant le coucher"
        case .lastMeal:       return "3 h avant"
        case .exerciseCutoff: return "effort vigoureux seulement"
        case .dimLights:      return "2 h 30 avant"
        case .warmBath:       return "10 min, 1 à 2 h avant"
        case .screensOff:     return "1 h avant"
        case .bedtime:        return "la même heure chaque jour"
        case .wake:           return "y compris la fin de semaine"
        case .morningLight:   return "dans l'heure qui suit"
        }
    }

    var evidence: EvidenceStrength {
        switch self {
        case .caffeineCutoff, .warmBath, .bedtime, .wake, .morningLight, .dimLights:
            return .solid
        case .lastMeal, .exerciseCutoff:
            return .moderate
        case .screensOff:
            return .thin
        }
    }

    /// Texte de la notification.
    var notificationBody: String {
        switch self {
        case .caffeineCutoff: return "Dernier café si vous voulez dormir ce soir."
        case .lastMeal:       return "Dernier repas copieux : après, une collation légère."
        case .exerciseCutoff: return "Terminez l'effort vigoureux maintenant."
        case .dimLights:      return "Baissez les lumières : la mélatonine attend la pénombre."
        case .warmBath:       return "C'est le moment du bain chaud — dix minutes suffisent."
        case .screensOff:     return "Écrans de côté pour la dernière heure."
        case .bedtime:        return "Au lit. La régularité compte plus que la durée."
        case .wake:           return "Debout — même heure que d'habitude."
        case .morningLight:   return "Dehors quelques minutes : c'est le signal du matin."
        }
    }
}

/// La routine calculée pour un profil donné.
struct SleepRoutine: Equatable, Sendable {

    /// Une étape, avec son heure.
    struct Entry: Identifiable, Equatable, Sendable {
        let step: SleepRoutineStep
        /// Minute du jour, de 0 à 1439.
        let minuteOfDay: Int
        var id: String { step.rawValue }
    }

    let bedtimeMinuteOfDay: Int
    let wakeMinuteOfDay: Int
    /// Toutes les étapes, dans l'ordre où elles surviennent en soirée puis au
    /// matin.
    let entries: [Entry]

    func minute(of step: SleepRoutineStep) -> Int? {
        entries.first { $0.step == step }?.minuteOfDay
    }

    /// Construit la routine à partir du lever visé et de la durée souhaitée.
    ///
    /// Les heures sont ramenées dans la journée par modulo : une routine dont
    /// le dernier café tombe « la veille » reste parfaitement valable, c'est
    /// une heure d'horloge comme une autre.
    static func make(profile: UserProfile) -> SleepRoutine {
        let wake = wrap(profile.targetWakeMinuteOfDay)
        let bedtime = wrap(profile.targetWakeMinuteOfDay
                           - Int((profile.sleepHours * 60).rounded()))

        let entries = SleepRoutineStep.allCases.map { step -> Entry in
            let base = step.anchor == .bedtime ? bedtime : wake
            return Entry(step: step, minuteOfDay: wrap(base + step.offsetMinutes))
        }

        // Ordonnées à partir du premier rappel de la soirée : présentées par
        // minute croissante, la liste commencerait au milieu de la nuit et se
        // lirait à l'envers.
        let first = entries.first { $0.step == .caffeineCutoff }?.minuteOfDay ?? 0
        let sorted = entries.sorted {
            wrap($0.minuteOfDay - first) < wrap($1.minuteOfDay - first)
        }

        return SleepRoutine(bedtimeMinuteOfDay: bedtime,
                            wakeMinuteOfDay: wake,
                            entries: sorted)
    }

    private static func wrap(_ minute: Int) -> Int {
        ((minute % 1440) + 1440) % 1440
    }
}
