import XCTest
@testable import AppliYouTube

final class AnalyseYouTubeTests: XCTestCase {

    func testIdentifiantsVideoDansToutesLesFormes() {
        let texte = """
        regarde https://www.youtube.com/watch?v=dQw4w9WgXcQ et aussi
        https://youtu.be/abcdefghijk?t=30, https://m.youtube.com/watch?feature=share&v=ABCDEFGHIJK
        https://www.youtube.com/shorts/12345678901 puis encore youtu.be/abcdefghijk
        """
        XCTAssertEqual(AnalyseYouTube.identifiantsVideo(dans: texte),
                       ["dQw4w9WgXcQ", "abcdefghijk", "ABCDEFGHIJK", "12345678901"])
    }

    func testAdressesChaine() {
        let texte = "https://m.youtube.com/@ChaineTest et https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv"
        XCTAssertEqual(AnalyseYouTube.adressesChaine(dans: texte),
                       ["https://www.youtube.com/@ChaineTest",
                        "https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv"])
    }

    func testUnLienDeVideoNEstPasUneChaine() {
        XCTAssertTrue(AnalyseYouTube.adressesChaine(dans: "https://www.youtube.com/watch?v=dQw4w9WgXcQ").isEmpty)
    }

    func testFicheDepuisPage() {
        let page = #"""
        <script>var ytInitialPlayerResponse = {"videoDetails":{"videoId":"dQw4w9WgXcQ","title":"Cours { 1 }","lengthSeconds":"600","channelId":"UCabcdefghijklmnopqrstuv","shortDescription":"Une \"vraie\" description","author":"Chaîne"},"microformat":{"playerMicroformatRenderer":{"category":"Education"}}};var meta = {};</script>
        """#
        let fiche = AnalyseYouTube.ficheVideo(depuisPage: page, id: "dQw4w9WgXcQ")
        XCTAssertEqual(fiche?.titre, "Cours { 1 }")
        XCTAssertEqual(fiche?.chaine, "Chaîne")
        XCTAssertEqual(fiche?.chaineID, "UCabcdefghijklmnopqrstuv")
        XCTAssertEqual(fiche?.dureeSecondes, 600)
        XCTAssertEqual(fiche?.categorie, "Education")
        XCTAssertEqual(fiche?.description, #"Une "vraie" description"#)
    }

    func testIdentifiantEtNomDeChaine() {
        let page = #"<meta property="og:title" content="Théo &amp; Cie"><script>{"externalId":"UCabcdefghijklmnopqrstuv"}</script>"#
        XCTAssertEqual(AnalyseYouTube.identifiantChaine(depuisPage: page), "UCabcdefghijklmnopqrstuv")
        XCTAssertEqual(AnalyseYouTube.meta("og:title", dans: page), "Théo & Cie")
    }

    func testFluxRSS() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns="http://www.w3.org/2005/Atom">
          <title>Chaîne</title>
          <author><name>Chaîne</name></author>
          <entry>
            <yt:videoId>dQw4w9WgXcQ</yt:videoId>
            <title>Première vidéo</title>
            <author><name>Chaîne</name></author>
            <published>2026-11-01T12:00:00+00:00</published>
          </entry>
        </feed>
        """
        let videos = AnalyseYouTube.videos(depuisFlux: Data(xml.utf8))
        XCTAssertEqual(videos.count, 1)
        XCTAssertEqual(videos.first?.id, "dQw4w9WgXcQ")
        XCTAssertEqual(videos.first?.titre, "Première vidéo")
        XCTAssertEqual(videos.first?.chaine, "Chaîne")
        XCTAssertNotNil(videos.first?.publieeLe)
    }
}
