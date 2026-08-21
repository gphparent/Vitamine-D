import Foundation

/// Ce que la peau garde d'une exposition, et qui empêche la suivante de
/// repartir de zéro.
///
/// ## Ce que fait la peau
///
/// Les UVB convertissent le 7-déhydrocholestérol de l'épiderme en
/// prévitamine D3. Mais le même rayonnement transforme aussi la prévitamine D3
/// en lumistérol et en tachystérol : au bout de dix à vingt minutes de plein
/// Soleil d'été, un équilibre photostationnaire s'installe, et la quantité de
/// prévitamine D3 présente à un instant donné cesse d'augmenter. C'est le
/// plafond que l'application appelle plafond de synthèse.
///
/// Cet équilibre ne se défait pas parce qu'on rentre. Il se défait à mesure
/// que la prévitamine D3 quitte la peau — par isomérisation thermique en
/// vitamine D3, puis captation par la protéine de transport. Cette étape-là se
/// compte en heures et en jours, pas en minutes.
///
/// ## Ce que faisait l'application
///
/// Le rendement était calculé sur la dose accumulée depuis le début de la
/// *sortie*. Terminer une sortie et en démarrer une autre dans la foulée
/// remettait donc le compteur à 100 %, ce qui revenait à promettre une récolte
/// que la peau ne peut pas fournir — et à faire dépenser du capital cutané
/// pour rien. L'erreur allait dans le sens qui flatte, le pire des deux.
///
/// ## La constante de temps
///
/// C'est le chiffre le moins bien étayé de tout le modèle, et il vaut mieux le
/// dire. Les demi-vies rapportées pour la conversion thermique de la
/// prévitamine D3 s'étalent largement selon les auteurs et les conditions ;
/// la cinétique d'une seconde exposition le même jour n'est, elle, presque pas
/// documentée.
///
/// Douze heures est un compromis délibérément prudent : une pause de dix
/// minutes ne rend presque rien, une nuit rend la moitié, une journée entière
/// les trois quarts. En cas d'erreur, elle va dans le sens qui protège —
/// l'application annonce un rendement plus bas qu'il ne l'est peut-être, donc
/// ne pousse jamais à sortir pour une vitamine D qui ne viendrait pas.
struct Photosaturation: Codable, Equatable, Sendable {

    /// Demi-vie de la charge photochimique, en heures.
    static let halfLifeHours = 12.0

    /// Charge **sans dimension** : la dose déposée rapportée au plafond de la
    /// peau qui l'a reçue.
    ///
    /// Le choix de l'unité n'est pas un détail d'implémentation, c'est une
    /// correction de bogue. La charge était auparavant conservée en UI brutes,
    /// pour tout le corps, et le rendement se calculait en la divisant par le
    /// plafond de la tenue *du moment*. Or ce plafond dépend de la surface
    /// découverte : enfiler un manteau le faisait chuter, et le rendement
    /// affiché s'effondrait sans que rien n'ait changé dans la peau.
    ///
    /// Le photo-équilibre s'installe dans un morceau de peau, et il ne sait
    /// rien de ce qu'on porte par-dessus. La grandeur conservée est donc la
    /// saturation de ce morceau — une proportion, invariante par changement de
    /// tenue. La conversion en UI brutes, dont le moteur a besoin, se fait au
    /// moment de l'emploi avec le plafond en vigueur.
    private(set) var saturation: Double
    private(set) var updatedAt: Date

    static let empty = Photosaturation(saturation: 0, updatedAt: .distantPast)

    init(saturation: Double = 0, updatedAt: Date = .distantPast) {
        self.saturation = max(0, saturation)
        self.updatedAt = updatedAt
    }

    /// Saturation restante à un instant donné, de 0 à l'infini.
    func load(at date: Date) -> Double {
        let hours = date.timeIntervalSince(updatedAt) / 3600
        guard hours > 0 else { return saturation }
        // Au-delà de quelques jours, la décroissance a tout emporté et le
        // calcul flotte inutilement près de zéro.
        guard hours < 30 * 24 else { return 0 }
        return saturation * pow(0.5, hours / Self.halfLifeHours)
    }

    /// Charge exprimée en UI brutes pour un profil donné, telle que le moteur
    /// l'attend.
    func rawLoad(at date: Date, profile: UserProfile) -> Double {
        load(at: date) * UVEngine.synthesisCeiling(profile: profile)
    }

    /// Verse la dose brute d'une sortie qui vient de s'achever.
    ///
    /// La normalisation se fait ici, avec la tenue portée pendant la sortie :
    /// c'est elle qui a déterminé quelle peau a reçu quoi.
    ///
    /// La dose est déposée d'un coup à la fin, alors qu'elle s'est accumulée
    /// tout au long de la sortie. L'écart est négligeable : une sortie dure au
    /// plus une heure ou deux, contre douze heures de demi-vie.
    mutating func deposit(rawIU: Double, at date: Date, profile: UserProfile) {
        guard rawIU > 0 else { return }
        let ceiling = UVEngine.synthesisCeiling(profile: profile)
        saturation = load(at: date) + rawIU / max(1, ceiling)
        updatedAt = date
    }

    /// Fraction du rendement encore disponible, de 0 à 1.
    ///
    /// Ne dépend d'aucun profil, et c'est tout l'intérêt : la peau chargée
    /// l'est autant sous un manteau que sous un maillot de bain.
    func marginalYield(at date: Date) -> Double {
        exp(-load(at: date))
    }

    // MARK: - Reconstruction depuis l'historique

    /// Nombre de jours d'historique qui pèsent encore.
    ///
    /// À douze heures de demi-vie, trois jours laissent moins d'un pour cent.
    /// Remonter plus loin coûterait du calcul pour un chiffre invisible.
    static let rebuildWindowDays = 3.0

    /// Reconstitue la charge à partir du seul historique.
    ///
    /// La charge était un accumulateur autonome : chaque sortie terminée y
    /// versait sa dose, et rien ne l'en retirait jamais. C'était tenable tant
    /// qu'une sortie, une fois close, ne bougeait plus. Dès lors qu'on peut la
    /// corriger ou l'effacer, l'accumulateur pointe sur un passé qui n'existe
    /// plus — une sortie supprimée continuerait de peser sur le rendement
    /// annoncé, sans que rien à l'écran ne l'explique.
    ///
    /// Elle devient donc un état dérivé, recalculable à tout moment. C'est
    /// aussi ce qui la rend vérifiable : deux historiques identiques donnent la
    /// même charge, ce qu'un accumulateur ne garantissait pas.
    static func rebuilt(from records: [SessionRecord],
                        asOf date: Date,
                        profile: UserProfile) -> Photosaturation {
        var rebuilt = Photosaturation.empty
        let horizon = date.addingTimeInterval(-rebuildWindowDays * 86_400)

        for record in records.filter({ $0.end > horizon }).sorted(by: { $0.end < $1.end }) {
            var recordProfile = profile
            recordProfile.exposure = BodyExposure.matching(
                exposedPercentage: record.exposedBodyPercentage,
                like: profile.exposure)
            rebuilt.deposit(rawIU: record.rawOrSaturatedIU,
                            at: record.end,
                            profile: recordProfile)
        }
        return rebuilt
    }

    // MARK: - Décodage

    /// Une charge enregistrée par une version antérieure était exprimée en UI
    /// brutes, dans une unité que celle-ci ne sait plus interpréter. On repart
    /// de zéro plutôt que de lire un chiffre pour un autre : la charge se
    /// dissipe de moitié en douze heures, l'oubli ne coûte donc qu'une journée.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        saturation = (try? container.decode(Double.self, forKey: .saturation)) ?? 0
        updatedAt = (try? container.decode(Date.self, forKey: .updatedAt)) ?? .distantPast
    }
}
