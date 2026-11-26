import XCTest
@testable import PPTerrain

final class ProchainesTests: XCTestCase {

    private func date(_ texte: String) -> Date {
        ISO8601DateFormatter().date(from: texte)!
    }

    private var seances: [ProchaineSeance] {
        [
            ProchaineSeance(ville: "Morin-Heights", debut: date("2026-11-26T10:30:00-05:00"), fin: date("2026-11-26T11:30:00-05:00"), depart: date("2026-11-26T09:50:00-05:00")),
            ProchaineSeance(ville: "Sainte-Sophie", debut: date("2026-11-27T09:00:00-05:00"), fin: date("2026-11-27T10:00:00-05:00"), depart: nil),
        ]
    }

    func testLeWidgetMontreLaSeanceEnCoursPuisLaSuivante() {
        XCTAssertEqual(Prochaines.aMontrer(seances, a: date("2026-11-26T08:00:00-05:00"))?.ville, "Morin-Heights")
        XCTAssertEqual(Prochaines.aMontrer(seances, a: date("2026-11-26T11:00:00-05:00"))?.ville, "Morin-Heights", "En cours, elle reste jusqu'à sa fin.")
        XCTAssertEqual(Prochaines.aMontrer(seances, a: date("2026-11-26T11:30:00-05:00"))?.ville, "Sainte-Sophie")
        XCTAssertNil(Prochaines.aMontrer(seances, a: date("2026-11-27T10:00:00-05:00")))
    }

    func testLeWidgetChangeAuDebutEtALaFinDeChaqueSeance() {
        let depuis = date("2026-11-26T11:00:00-05:00")
        XCTAssertEqual(Prochaines.moments(seances, depuis: depuis), [
            depuis,
            date("2026-11-26T11:30:00-05:00"),
            date("2026-11-27T09:00:00-05:00"),
            date("2026-11-27T10:00:00-05:00"),
        ])
    }
}
