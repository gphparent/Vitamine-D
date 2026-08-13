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

    /// Dose brute encore en place, dans la même unité que `rawVitaminDIU` :
    /// des UI d'avant plafonnement.
    private(set) var rawLoad: Double
    private(set) var updatedAt: Date

    static let empty = Photosaturation(rawLoad: 0, updatedAt: .distantPast)

    init(rawLoad: Double = 0, updatedAt: Date = .distantPast) {
        self.rawLoad = max(0, rawLoad)
        self.updatedAt = updatedAt
    }

    /// Charge restante à un instant donné.
    func load(at date: Date) -> Double {
        let hours = date.timeIntervalSince(updatedAt) / 3600
        guard hours > 0 else { return rawLoad }
        // Au-delà de quelques jours, la décroissance a tout emporté et le
        // calcul flotte inutilement près de zéro.
        guard hours < 30 * 24 else { return 0 }
        return rawLoad * pow(0.5, hours / Self.halfLifeHours)
    }

    /// Verse la dose brute d'une sortie qui vient de s'achever.
    ///
    /// La dose est déposée d'un coup à la fin, alors qu'elle s'est accumulée
    /// tout au long de la sortie. L'écart est négligeable : une sortie dure au
    /// plus une heure ou deux, contre douze heures de demi-vie.
    mutating func deposit(rawIU: Double, at date: Date) {
        guard rawIU > 0 else { return }
        rawLoad = load(at: date) + rawIU
        updatedAt = date
    }

    /// Fraction du rendement encore disponible, de 0 à 1, pour un profil donné.
    func marginalYield(at date: Date, profile: UserProfile) -> Double {
        UVEngine.marginalYield(rawIU: load(at: date), profile: profile)
    }
}
