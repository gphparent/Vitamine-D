import XCTest
@testable import PPTerrain

final class ModelesTests: XCTestCase {

    /// La forme exacte que renvoie /api/terrain/rendez-vous (TerrainController).
    private let reponse = """
    {
      "genere_le": "2026-11-24T08:00:00-05:00",
      "photographe": "Guillaume",
      "rendez_vous": [
        {
          "id": 46, "statut": "confirmee",
          "debut": "2026-11-25T13:00:00-05:00", "fin": "2026-11-25T14:00:00-05:00",
          "adresse": "461 ch. du lac Quenouille", "unite": null, "ville": "Lac-Supérieur",
          "latitude": 46.1, "longitude": -74.4, "google_event_id": "abc",
          "forfait": "L'essentiel", "ajouts": ["Vidéo verticale de 1 min 30"], "prix": null,
          "precisions": null, "note_planification": "Chien sur place",
          "client": {"nom": "Louise", "telephone": "+15145552368", "courriel": null},
          "proprietaire": null, "sur_place": false, "qui_sur_place": null, "code_recu": true,
          "pieces": [{"id": 7, "nom": "plan/terrain.pdf", "taille": 2048, "note": "Entrer par le lac", "fichier": true, "ajoute_le": "2026-11-24T07:59:00-05:00"}]
        },
        {
          "id": 47, "statut": "en_attente",
          "debut": "2026-11-25T09:00:00-05:00", "fin": null,
          "adresse": "1 rue A, Oka", "unite": "3", "ville": "Oka",
          "latitude": null, "longitude": null, "google_event_id": null,
          "forfait": null, "ajouts": [], "prix": 300,
          "precisions": null, "note_planification": null,
          "client": {"nom": null, "telephone": null, "courriel": null},
          "proprietaire": {"nom": "Marc", "contact": "514 555-0000"}, "sur_place": null, "qui_sur_place": null, "code_recu": false,
          "pieces": []
        }
      ]
    }
    """

    func testLaReponseDuServeurSeLit() throws {
        let semaine = try Format.decodeur.decode(Semaine.self, from: Data(reponse.utf8))

        XCTAssertEqual(semaine.rendezVous.count, 2)
        let premier = semaine.rendezVous[0]
        XCTAssertTrue(premier.codeRecu)
        XCTAssertEqual(premier.surPlace, false)
        XCTAssertEqual(premier.ajouts, ["Vidéo verticale de 1 min 30"])
        XCTAssertNil(premier.prix)
        XCTAssertEqual(semaine.rendezVous[1].prix, 300)
        XCTAssertEqual(premier.pieces.first?.nomLocal, "7-plan-terrain.pdf")
    }

    func testLaCopieLocaleSeRelit() throws {
        let semaine = try Format.decodeur.decode(Semaine.self, from: Data(reponse.utf8))
        let copie = try Format.encodeur.encode(semaine)
        let relue = try Format.decodeur.decode(Semaine.self, from: copie)

        XCTAssertEqual(relue.rendezVous, semaine.rendezVous)
    }

    func testLesSeancesSeRangentParJourEtParHeure() throws {
        let semaine = try Format.decodeur.decode(Semaine.self, from: Data(reponse.utf8))
        let jours = Format.parJour(semaine.rendezVous)

        XCTAssertEqual(jours.count, 1)
        XCTAssertEqual(jours[0].seances.map(\.id), [47, 46])
        XCTAssertEqual(Format.heure(jours[0].seances[0].debut!), "9 h 00")
    }

    func testLeLieuNeRepetePasLaVille() throws {
        let semaine = try Format.decodeur.decode(Semaine.self, from: Data(reponse.utf8))

        XCTAssertEqual(semaine.rendezVous[0].lieu, "461 ch. du lac Quenouille, Lac-Supérieur")
        XCTAssertEqual(semaine.rendezVous[1].lieu, "1 rue A, Oka, app. 3")
    }

    func testDemainEtAujourdhui() {
        let maintenant = ISO8601DateFormatter().date(from: "2026-11-24T08:00:00-05:00")!
        XCTAssertEqual(Format.jour(maintenant.addingTimeInterval(3600), maintenant: maintenant), "Aujourd’hui")
        XCTAssertEqual(Format.jour(maintenant.addingTimeInterval(86_400), maintenant: maintenant), "Demain")
    }
}
