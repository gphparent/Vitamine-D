import XCTest
@testable import AppliYouTube

final class PartageTests: XCTestCase {

    private func date(_ texte: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: texte)!
    }

    private func chaine(_ id: String, _ le: String) -> Chaine {
        Chaine(id: id, nom: id, approuveeLe: date(le), raison: "")
    }

    func testLaFusionReunitLesDeuxAppareils() {
        let iphone = DocumentPartage(chaines: [chaine("UCa", "2026-11-01T10:00:00.000Z")])
        let ordi = DocumentPartage(chaines: [chaine("UCb", "2026-11-02T10:00:00.000Z")])
        XCTAssertEqual(DocumentPartage.fusion(iphone, ordi).chaines.map(\.id), ["UCb", "UCa"])
    }

    func testUnRetraitPosterieurFermeLaPorte() {
        let iphone = DocumentPartage(chaines: [chaine("UCa", "2026-11-01T10:00:00.000Z")])
        let ordi = DocumentPartage(retraits: [Retrait(id: "UCa", le: date("2026-11-03T10:00:00.000Z"))])
        XCTAssertTrue(DocumentPartage.fusion(iphone, ordi).chaines.isEmpty)
    }

    func testUneApprobationApresUnRetraitRouvreLaPorte() {
        let avant = DocumentPartage(retraits: [Retrait(id: "UCa", le: date("2026-11-03T10:00:00.000Z"))])
        let apres = DocumentPartage(chaines: [chaine("UCa", "2026-11-05T10:00:00.000Z")])
        XCTAssertEqual(DocumentPartage.fusion(avant, apres).chaines.count, 1)
    }

    /// Le document ecrit par l'extension (dates `toISOString()`) se relit, et
    /// se reecrit sous la meme forme.
    func testFormatCommunAvecLExtension() throws {
        let json = """
        {"version":1,"chaines":[{"id":"UCa","nom":"A","approuveeLe":"2026-11-01T10:00:00.123Z","raison":""}],
         "videos":[],"retraits":[{"id":"x","le":"2026-11-02T10:00:00Z"}]}
        """
        let doc = try DocumentPartage.decodeur.decode(DocumentPartage.self, from: Data(json.utf8))
        XCTAssertEqual(doc.chaines.first?.nom, "A")
        let texte = String(decoding: try DocumentPartage.encodeur.encode(doc), as: UTF8.self)
        XCTAssertTrue(texte.contains("\"2026-11-01T10:00:00.123Z\""))
        XCTAssertTrue(texte.contains("\"2026-11-02T10:00:00.000Z\""))
    }

    func testLesConsignesSontDansLePaquet() {
        XCTAssertTrue(Juge.consignes.contains("en français"))
    }
}
