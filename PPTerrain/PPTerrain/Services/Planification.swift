import Foundation

/// Un avis de départ, programmé sur le iPhone : il sonne même sans réseau.
struct Rappel: Hashable {
    let id: String
    let quand: Date
    let titre: String
    let corps: String
}

/// Quand partir, et quoi dire à l'écran verrouillé (Guillaume, 25 nov.). Sans réseau ni Plans : de quoi tester.
enum Planification {
    /// Minutes pour se stationner et sortir l'équipement, comme le résumé du matin de l'appli web.
    static let marge = 10

    /// La tuile apparaît à partir de 30 minutes avant le départ.
    static let avance: TimeInterval = 30 * 60

    /// La route, plus la marge, arrondie aux 5 minutes d'avant : on part un peu tôt plutôt qu'un peu tard.
    static func depart(debut: Date, routeMinutes: Int) -> Date {
        let brut = debut.addingTimeInterval(-Double((routeMinutes + marge) * 60))
        return Date(timeIntervalSince1970: (brut.timeIntervalSince1970 / 300).rounded(.down) * 300)
    }

    /// Les séances confirmées d'une journée, dans l'ordre.
    static func journee(_ seances: [RendezVous], le jour: Date) -> [RendezVous] {
        seances
            .filter { !$0.enAttente && $0.debut != nil && Format.calendrier.isDate($0.debut!, inSameDayAs: jour) }
            .sorted { $0.debut! < $1.debut! }
    }

    static func fin(_ seance: RendezVous) -> Date {
        seance.fin ?? seance.debut!.addingTimeInterval(3600)
    }

    /// Pour la première séance de la journée : 30 minutes avant de partir, puis à l'heure de partir.
    /// Pour les suivantes : à l'heure de partir, ou à la fin de la précédente quand l'horaire est serré.
    static func rappels(journee: [RendezVous], routes: [Int: Trajet], faites: Set<Int>, maintenant: Date) -> [Rappel] {
        var rappels: [Rappel] = []

        for (rang, seance) in journee.enumerated() where !faites.contains(seance.id) {
            guard let debut = seance.debut, let route = routes[seance.id] else { continue }
            let partir = depart(debut: debut, routeMinutes: route.minutes)
            let ville = seance.ville ?? "la séance"
            let corps = "\(Format.heure(debut)) à \(ville) : \(route.minutes) min de route."

            if rang == 0 {
                rappels.append(Rappel(id: "avant-\(seance.id)", quand: partir.addingTimeInterval(-avance), titre: "Départ dans 30 min", corps: corps))
                rappels.append(Rappel(id: "partir-\(seance.id)", quand: partir, titre: "C’est l’heure de partir", corps: corps))
            } else {
                let precedente = fin(journee[rang - 1])
                let serre = partir < precedente
                rappels.append(Rappel(
                    id: "partir-\(seance.id)",
                    quand: max(partir, precedente),
                    titre: serre ? "Pars pour la prochaine séance, c’est serré" : "Pars pour la prochaine séance",
                    corps: corps
                ))
            }
        }

        return rappels.filter { $0.quand > maintenant }
    }

    /// Ce que montre la tuile en ce moment ; nil avant 30 minutes du premier départ, ou quand la journée est finie.
    static func etat(
        journee: [RendezVous],
        routes: [Int: Trajet],
        arrivees: [Int: Date],
        fins: [Int: Date],
        maintenant: Date
    ) -> ActiviteSeance.ContentState? {
        guard let premiere = journee.first, let debut = premiere.debut else { return nil }

        let premierDepart = routes[premiere.id].map { depart(debut: debut, routeMinutes: $0.minutes) } ?? debut.addingTimeInterval(-3600)
        guard maintenant >= premierDepart.addingTimeInterval(-avance) else { return nil }

        let restantes = journee.filter { fins[$0.id] == nil }
        guard let courante = restantes.first, let heure = courante.debut else { return nil }
        let route = routes[courante.id]

        if arrivees[courante.id] != nil {
            return ActiviteSeance.ContentState(etape: .surPlace, ville: courante.ville ?? "", heureSeance: heure, depart: nil, finPrevue: fin(courante), routeMinutes: nil, ensuite: restantes.count - 1)
        }

        let partir = route.map { depart(debut: heure, routeMinutes: $0.minutes) }
        return ActiviteSeance.ContentState(
            etape: (partir.map { maintenant < $0 } ?? false) ? .partir : .enRoute,
            ville: courante.ville ?? "",
            heureSeance: heure,
            depart: partir,
            finPrevue: fin(courante),
            routeMinutes: route?.minutes,
            ensuite: restantes.count - 1
        )
    }
}
