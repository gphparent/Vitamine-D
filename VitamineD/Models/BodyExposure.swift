import Foundation

/// Région corporelle, avec sa part de surface corporelle totale.
///
/// Les pourcentages dérivent de la table de Lund-Browder (adulte), regroupée par
/// segments utiles au choix vestimentaire. Les paires (bras, jambes, mains…)
/// comptent les deux côtés. Le total brut n'est pas exactement 100 % ; il est
/// normalisé à l'usage par ``BodyExposure/normalisedFraction(for:)``.
enum BodyRegion: String, CaseIterable, Codable, Identifiable, Sendable {
    case scalp
    case face
    case neck
    case chest
    case back
    case upperArms
    case forearms
    case hands
    case thighs
    case lowerLegs
    case feet

    var id: String { rawValue }

    /// Part brute de la surface corporelle, en pourcentage.
    var rawPercentage: Double {
        switch self {
        case .scalp:      return 3.5
        case .face:       return 3.5
        case .neck:       return 2.0
        case .chest:      return 18.0
        case .back:       return 18.0
        case .upperArms:  return 8.0
        case .forearms:   return 6.0
        case .hands:      return 5.0
        case .thighs:     return 18.0
        case .lowerLegs:  return 13.0
        case .feet:       return 6.5
        }
    }

    var title: String {
        switch self {
        case .scalp:      return "Cuir chevelu"
        case .face:       return "Visage"
        case .neck:       return "Cou"
        case .chest:      return "Torse"
        case .back:       return "Dos"
        case .upperArms:  return "Bras"
        case .forearms:   return "Avant-bras"
        case .hands:      return "Mains"
        case .thighs:     return "Cuisses"
        case .lowerLegs:  return "Jambes"
        case .feet:       return "Pieds"
        }
    }

    var symbolName: String {
        switch self {
        case .scalp, .face, .neck: return "person.crop.circle"
        case .chest, .back:        return "tshirt"
        case .upperArms, .forearms, .hands: return "hand.raised"
        case .thighs, .lowerLegs, .feet:    return "figure.walk"
        }
    }

    /// Ordre d'affichage, de la tête aux pieds.
    static let ordered: [BodyRegion] = [
        .scalp, .face, .neck, .chest, .back,
        .upperArms, .forearms, .hands,
        .thighs, .lowerLegs, .feet
    ]
}

/// Tenue vestimentaire prédéfinie, exprimée comme l'ensemble des régions
/// laissées à découvert.
enum ClothingPreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case swimwear
    case tankTopShorts
    case tShirtShorts
    case tShirtTrousers
    case longSleevesTrousers
    case coat
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .swimwear:            return "Maillot de bain"
        case .tankTopShorts:       return "Camisole + short"
        case .tShirtShorts:        return "T-shirt + short"
        case .tShirtTrousers:      return "T-shirt + pantalon"
        case .longSleevesTrousers: return "Manches longues + pantalon"
        case .coat:                return "Manteau"
        case .custom:              return "Personnalisée"
        }
    }

    /// Intitulé court, pour les pastilles de l'écran principal, où six tenues
    /// doivent tenir côte à côte sans que la boîte change de taille.
    var shortTitle: String {
        switch self {
        case .swimwear:            return "Maillot"
        case .tankTopShorts:       return "Camisole"
        case .tShirtShorts:        return "T-shirt\net short"
        case .tShirtTrousers:      return "T-shirt\net pantalon"
        case .longSleevesTrousers: return "Manches\nlongues"
        case .coat:                return "Manteau"
        case .custom:              return "Sur mesure"
        }
    }

    var symbolName: String {
        switch self {
        case .swimwear:            return "figure.pool.swim"
        case .tankTopShorts:       return "figure.run"
        case .tShirtShorts:        return "tshirt.fill"
        case .tShirtTrousers:      return "tshirt"
        case .longSleevesTrousers: return "figure.stand"
        case .coat:                return "snowflake"
        case .custom:              return "slider.horizontal.3"
        }
    }

    /// Étoffe à supposer sur la peau couverte, quand l'utilisateur ne dit rien.
    ///
    /// Un manteau d'hiver n'est pas un t-shirt : le proposer d'emblée évite
    /// d'annoncer, sous une doudoune, la synthèse d'une chemise de lin.
    var suggestedFabric: Fabric {
        switch self {
        case .coat:     return .dense
        case .swimwear: return .light
        default:        return .standard
        }
    }

    /// Régions découvertes.
    ///
    /// Deux conventions valent d'être explicitées. Le cuir chevelu n'est jamais
    /// compté : la chevelure bloque la quasi-totalité des UVB. Et un short est
    /// supposé descendre au genou, donc laisser les cuisses couvertes — un
    /// short plus court se déclare en mode personnalisé, où les cuisses
    /// s'ajoutent à la main.
    var exposedRegions: Set<BodyRegion> {
        switch self {
        case .swimwear:
            return [.face, .neck, .chest, .back, .upperArms, .forearms, .hands, .thighs, .lowerLegs, .feet]
        case .tankTopShorts:
            return [.face, .neck, .upperArms, .forearms, .hands, .lowerLegs, .feet]
        case .tShirtShorts:
            return [.face, .neck, .forearms, .hands, .lowerLegs, .feet]
        case .tShirtTrousers:
            return [.face, .neck, .forearms, .hands]
        case .longSleevesTrousers:
            return [.face, .neck, .hands]
        case .coat:
            return [.face]
        case .custom:
            return [.face, .neck, .forearms, .hands]
        }
    }
}

/// Étoffe portée sur la peau couverte, classée par ce qu'elle laisse passer.
///
/// Un vêtement n'est pas un écran. Les valeurs correspondent aux facteurs de
/// protection vestimentaire (UPF) mesurés en laboratoire : un jean ou une laine
/// serrée dépassent UPF 50, un coton d'été ordinaire tourne autour de 20, un
/// tissu clair à maille lâche descend vers 7, et un voile ou un vêtement mouillé
/// tombe sous 4 — un t-shirt blanc trempé ne protège pratiquement plus.
///
/// L'étoffe n'intervient que du côté de la synthèse. Le calcul de la rougeur
/// reste conduit sur la peau nue, qui rougit la première : c'est elle qui fixe
/// le moment où il faut rentrer, et aucune étoffe ne l'avance.
enum Fabric: String, CaseIterable, Codable, Identifiable, Sendable {
    /// Denim, laine serrée, tissu foncé, double épaisseur.
    case dense
    /// Coton d'été ordinaire, la valeur par défaut.
    case standard
    /// Lin clair, maille lâche, blanc fin.
    case light
    /// Voile, mousseline, tissu mouillé ou distendu.
    case sheer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dense:    return "Dense ou foncé"
        case .standard: return "Coton ordinaire"
        case .light:    return "Léger ou clair"
        case .sheer:    return "Voile ou mouillé"
        }
    }

    var detail: String {
        switch self {
        case .dense:    return "Denim, laine, tissu foncé serré"
        case .standard: return "Coton d'été, jersey moyen"
        case .light:    return "Lin clair, maille lâche, blanc fin"
        case .sheer:    return "Mousseline, tissu mouillé ou distendu"
        }
    }

    /// Part du rayonnement UV que l'étoffe laisse atteindre la peau.
    var transmission: Double {
        switch self {
        case .dense:    return 0.01
        case .standard: return 0.05
        case .light:    return 0.15
        case .sheer:    return 0.30
        }
    }

    /// Indice de protection vestimentaire correspondant, tel qu'il figure sur
    /// les étiquettes.
    var upf: Int { Int((1 / transmission).rounded()) }
}

/// État d'exposition du corps : quelles régions sont découvertes, ce qui
/// recouvre les autres, et quelle protection solaire s'y ajoute.
struct BodyExposure: Codable, Equatable, Sendable {
    var preset: ClothingPreset
    var customRegions: Set<BodyRegion>
    /// Étoffe supposée sur toute la peau couverte.
    var fabric: Fabric
    /// Indice de protection du produit solaire appliqué (1 = aucun).
    var sunscreenSPF: Int
    /// Le chapeau ou la casquette soustrait le visage et une partie du cou au
    /// rayonnement direct.
    var wearsHat: Bool

    init(preset: ClothingPreset = .tShirtShorts,
         customRegions: Set<BodyRegion>? = nil,
         fabric: Fabric? = nil,
         sunscreenSPF: Int = 1,
         wearsHat: Bool = false) {
        self.preset = preset
        self.customRegions = customRegions ?? preset.exposedRegions
        self.fabric = fabric ?? preset.suggestedFabric
        self.sunscreenSPF = sunscreenSPF
        self.wearsHat = wearsHat
    }

    /// Une tenue enregistrée avant l'arrivée de l'étoffe n'en porte pas trace :
    /// on retient alors celle que la tenue suggère, plutôt que d'échouer à
    /// relire tout un profil pour un champ absent.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let preset = try container.decode(ClothingPreset.self, forKey: .preset)
        self.preset = preset
        self.customRegions = (try? container.decode(Set<BodyRegion>.self,
                                                    forKey: .customRegions))
            ?? preset.exposedRegions
        self.fabric = (try? container.decode(Fabric.self, forKey: .fabric))
            ?? preset.suggestedFabric
        self.sunscreenSPF = (try? container.decode(Int.self, forKey: .sunscreenSPF)) ?? 1
        self.wearsHat = (try? container.decode(Bool.self, forKey: .wearsHat)) ?? false
    }

    /// Somme des pourcentages bruts de toutes les régions du corps.
    static let totalRawPercentage: Double =
        BodyRegion.allCases.reduce(0) { $0 + $1.rawPercentage }

    static func normalisedFraction(for regions: Set<BodyRegion>) -> Double {
        let raw = regions.reduce(0.0) { $0 + $1.rawPercentage }
        return raw / totalRawPercentage
    }

    var exposedRegions: Set<BodyRegion> {
        var regions = preset == .custom ? customRegions : preset.exposedRegions
        if wearsHat {
            regions.remove(.face)
            regions.remove(.scalp)
        }
        return regions
    }

    /// Fraction de la surface corporelle réellement exposée, de 0 à 1.
    var exposedBodyFraction: Double {
        Self.normalisedFraction(for: exposedRegions)
    }

    var exposedBodyPercentage: Double { exposedBodyFraction * 100 }

    /// Surface équivalente pour la synthèse : la peau nue, plus la peau couverte
    /// comptée à hauteur de ce que l'étoffe laisse passer.
    ///
    /// La peau couverte représente presque toujours l'essentiel du corps. Même à
    /// 5 % de transmission, les 90 % de peau sous un vêtement d'été pèsent
    /// autant qu'un dixième de corps nu — c'est pourquoi une femme entièrement
    /// vêtue produit moins de vitamine D, mais pas zéro.
    ///
    /// Cette grandeur ne sert qu'à la vitamine D. La dose érythémale se mesure
    /// sur la peau la plus découverte, celle qui rougira la première.
    var effectiveExposedFraction: Double {
        let bare = exposedBodyFraction
        return bare + (1 - bare) * fabric.transmission
    }

    /// Facteur de transmission du produit solaire.
    ///
    /// L'IP est mesuré en laboratoire à 2 mg/cm², une quantité que presque
    /// personne n'applique. À l'épaisseur réellement observée (0,5 à 1 mg/cm²),
    /// la protection effective est de l'ordre de la racine de l'IP nominal.
    /// C'est l'hypothèse conservatrice retenue ici : elle évite d'annoncer des
    /// durées d'exposition dangereusement longues.
    var sunscreenTransmission: Double {
        guard sunscreenSPF > 1 else { return 1.0 }
        let effectiveSPF = sqrt(Double(sunscreenSPF))
        return 1.0 / effectiveSPF
    }

    var summary: String {
        let percent = Int(exposedBodyPercentage.rounded())
        var parts = ["\(percent) % de peau exposée"]
        if fabric != .standard { parts.append(fabric.title.lowercased()) }
        if sunscreenSPF > 1 { parts.append("IP \(sunscreenSPF)") }
        if wearsHat { parts.append("chapeau") }
        return parts.joined(separator: " · ")
    }
}
