import XCTest
@testable import PPTerrain

final class PlanificationTests: XCTestCase {

    private func date(_ texte: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: texte)!
    }

    private func seance(_ id: Int, _ debut: String, _ fin: String, ville: String, statut: String = "confirmee") -> RendezVous {
        let json = """
        {"id": \(id), "statut": "\(statut)", "debut": "\(debut)", "fin": "\(fin)", "adresse": "1 rue A", "unite": null, "ville": "\(ville)",
         "latitude": null, "longitude": null, "google_event_id": null, "forfait": null, "ajouts": [], "prix": null,
         "precisions": null, "note_planification": null, "client": {"nom": null, "telephone": null, "courriel": null},
         "proprietaire": null, "sur_place": null, "qui_sur_place": null, "code_recu": false, "pieces": []}
        """
        return try! Format.decodeur.decode(RendezVous.self, from: Data(json.utf8))
    }

    func testLeDepartComprendLaMargeEtSArrondit() {
        // 9 h - 37 min de route - 10 min de marge = 8 h 13, arrondi à 8 h 10.
        let depart = Planification.depart(debut: date("2026-11-26T09:00:00-05:00"), routeMinutes: 37)
        XCTAssertEqual(Format.heure(depart), "8 h 10")
    }

    func testLesAvisDeLaJournee() {
        let premiere = seance(1, "2026-11-26T09:00:00-05:00", "2026-11-26T10:00:00-05:00", ville: "Sainte-Sophie")
        let seconde = seance(2, "2026-11-26T10:30:00-05:00", "2026-11-26T11:30:00-05:00", ville: "Sainte-Agathe-des-Monts")
        let attente = seance(3, "2026-11-26T14:00:00-05:00", "2026-11-26T15:00:00-05:00", ville: "Oka", statut: "en_attente")
        let journee = Planification.journee([seconde, attente, premiere], le: date("2026-11-26T12:00:00-05:00"))
        XCTAssertEqual(journee.map(\.id), [1, 2], "Une séance à confirmer ne compte pas.")

        let rappels = Planification.rappels(
            journee: journee,
            routes: [1: Trajet(minutes: 14, km: 10.4), 2: Trajet(minutes: 32, km: 30)],
            faites: [],
            maintenant: date("2026-11-26T06:00:00-05:00")
        )

        XCTAssertEqual(rappels.map(\.id), ["avant-1", "partir-1", "partir-2"])
        XCTAssertEqual(rappels.map { Format.heure($0.quand) }, ["8 h 05", "8 h 35", "10 h 00"])
        XCTAssertEqual(rappels[0].titre, "Départ dans 30 min")
        XCTAssertEqual(rappels[0].corps, "9 h 00 à Sainte-Sophie : 14 min de route.")
        // 10 h 30 - 32 - 10 = 9 h 48, avant la fin de la première (10 h) : l'avis attend 10 h et le dit.
        XCTAssertEqual(rappels[2].titre, "Pars pour la prochaine séance, c’est serré")
    }

    func testRienQuiEstDejaPasseNiFait() {
        let premiere = seance(1, "2026-11-26T09:00:00-05:00", "2026-11-26T10:00:00-05:00", ville: "Oka")
        let rappels = Planification.rappels(journee: [premiere], routes: [1: Trajet(minutes: 14, km: 10)], faites: [], maintenant: date("2026-11-26T08:20:00-05:00"))
        XCTAssertEqual(rappels.map(\.id), ["partir-1"])
        XCTAssertTrue(Planification.rappels(journee: [premiere], routes: [1: Trajet(minutes: 14, km: 10)], faites: [1], maintenant: date("2026-11-26T06:00:00-05:00")).isEmpty)
    }

    func testLaTuileSuitLaJournee() {
        let premiere = seance(1, "2026-11-26T09:00:00-05:00", "2026-11-26T10:00:00-05:00", ville: "Sainte-Sophie")
        let seconde = seance(2, "2026-11-26T11:00:00-05:00", "2026-11-26T12:00:00-05:00", ville: "Mirabel")
        let routes = [1: Trajet(minutes: 14, km: 10), 2: Trajet(minutes: 20, km: 18)]

        // Départ à 8 h 35 : rien avant 8 h 05.
        XCTAssertNil(Planification.etat(journee: [premiere, seconde], routes: routes, arrivees: [:], fins: [:], maintenant: date("2026-11-26T08:00:00-05:00")))

        let avant = Planification.etat(journee: [premiere, seconde], routes: routes, arrivees: [:], fins: [:], maintenant: date("2026-11-26T08:10:00-05:00"))
        XCTAssertEqual(avant?.etape, .partir)
        XCTAssertEqual(avant?.titre, "Départ à 8 h 35")
        XCTAssertEqual(avant?.detail, "Sainte-Sophie · 14 min de route · 1 autre séance ensuite")

        let surPlace = Planification.etat(journee: [premiere, seconde], routes: routes, arrivees: [1: date("2026-11-26T08:55:00-05:00")], fins: [:], maintenant: date("2026-11-26T09:10:00-05:00"))
        XCTAssertEqual(surPlace?.etape, .surPlace)
        XCTAssertEqual(surPlace?.titre, "Sur place, fin prévue 10 h 00")

        let ensuite = Planification.etat(journee: [premiere, seconde], routes: routes, arrivees: [1: date("2026-11-26T08:55:00-05:00")], fins: [1: date("2026-11-26T09:50:00-05:00")], maintenant: date("2026-11-26T10:40:00-05:00"))
        XCTAssertEqual(ensuite?.ville, "Mirabel")
        XCTAssertEqual(ensuite?.etape, .enRoute)
        XCTAssertEqual(ensuite?.ensuite, 0)

        XCTAssertNil(Planification.etat(journee: [premiere, seconde], routes: routes, arrivees: [:], fins: [1: .now, 2: .now], maintenant: date("2026-11-26T12:10:00-05:00")))
    }

    func testUnGesteSeRelit() throws {
        let geste = Geste(rendezVous: 46, sorte: .arrivee, a: date("2026-11-26T08:58:00-05:00"), km: 10.4, minutes: 14)
        let relu = try Format.decodeur.decode([Geste].self, from: Format.encodeur.encode([geste]))
        XCTAssertEqual(relu, [geste])
    }
}
