import Foundation

/// Lecture de YouTube sans cle Google : la page publique d'une video, la page
/// d'une chaine et le flux RSS que YouTube publie pour chaque chaine. Pas de
/// recherche, volontairement : c'est la recherche qui ouvre la spirale.
struct YouTubeService {

    enum Erreur: LocalizedError {
        case introuvable
        var errorDescription: String? { "Impossible de lire cette page YouTube." }
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Video

    func fiche(video id: String) async throws -> FicheVideo {
        let page = try await telecharger("https://www.youtube.com/watch?v=\(id)&hl=fr")
        if let fiche = AnalyseYouTube.ficheVideo(depuisPage: page, id: id) {
            return fiche
        }
        // Repli : oEmbed ne donne que le titre et la chaine, mais ne casse pas
        // quand YouTube remanie sa page.
        let donnees = try await telecharger(
            "https://www.youtube.com/oembed?format=json&url=https://www.youtube.com/watch?v=\(id)")
        guard let json = try JSONSerialization.jsonObject(with: Data(donnees.utf8)) as? [String: Any],
              let titre = json["title"] as? String else { throw Erreur.introuvable }
        return FicheVideo(id: id, titre: titre, chaine: json["author_name"] as? String ?? "")
    }

    // MARK: Chaine

    func fiche(chaine adresse: String) async throws -> FicheChaine {
        let page = try await telecharger(adresse)
        guard let id = AnalyseYouTube.identifiantChaine(depuisPage: page) else {
            throw Erreur.introuvable
        }
        let videos = (try? await flux(chaine: id)) ?? []
        return FicheChaine(
            id: id,
            nom: AnalyseYouTube.meta("og:title", dans: page) ?? id,
            description: AnalyseYouTube.meta("og:description", dans: page),
            dernieresVideos: videos.prefix(15).map(\.titre))
    }

    func flux(chaine id: String) async throws -> [VideoDuFil] {
        let xml = try await telecharger("https://www.youtube.com/feeds/videos.xml?channel_id=\(id)")
        return AnalyseYouTube.videos(depuisFlux: Data(xml.utf8))
    }

    // MARK: Reseau

    private func telecharger(_ adresse: String) async throws -> String {
        guard let url = URL(string: adresse) else { throw Erreur.introuvable }
        var requete = URLRequest(url: url)
        // Une page de bureau, en francais : c'est la forme dont l'analyse
        // ci-dessous depend.
        requete.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent")
        requete.setValue("fr-CA,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        let (donnees, reponse) = try await session.data(for: requete)
        guard (reponse as? HTTPURLResponse)?.statusCode == 200 else { throw Erreur.introuvable }
        return String(decoding: donnees, as: UTF8.self)
    }
}

/// Analyse pure, sans reseau, pour pouvoir l'eprouver dans les tests.
enum AnalyseYouTube {

    /// Identifiants de video presents dans un texte libre, dans l'ordre.
    static func identifiantsVideo(dans texte: String) -> [String] {
        let motif = #"(?:youtu\.be/|youtube\.com/(?:watch\?(?:[^\s]*&)?v=|shorts/|live/|embed/))([A-Za-z0-9_-]{11})"#
        return correspondances(motif, dans: texte)
    }

    /// Adresses de chaine presentes dans un texte libre.
    static func adressesChaine(dans texte: String) -> [String] {
        let motif = #"(https?://(?:www\.|m\.)?youtube\.com/(?:@[\w.\-]+|channel/UC[\w-]{22}|c/[\w.\-]+|user/[\w.\-]+))"#
        return correspondances(motif, dans: texte).map {
            $0.replacingOccurrences(of: "://m.", with: "://www.")
        }
    }

    static func ficheVideo(depuisPage page: String, id: String) -> FicheVideo? {
        guard let json = objetJSON(apres: "ytInitialPlayerResponse = ", dans: page),
              let details = json["videoDetails"] as? [String: Any],
              let titre = details["title"] as? String else { return nil }
        let micro = (json["microformat"] as? [String: Any])?["playerMicroformatRenderer"] as? [String: Any]
        return FicheVideo(
            id: id,
            titre: titre,
            chaine: details["author"] as? String ?? "",
            chaineID: details["channelId"] as? String,
            description: (details["shortDescription"] as? String).map { String($0.prefix(2000)) },
            dureeSecondes: (details["lengthSeconds"] as? String).flatMap(Int.init),
            categorie: micro?["category"] as? String,
            motsCles: (details["keywords"] as? [String]).map { Array($0.prefix(20)) })
    }

    static func identifiantChaine(depuisPage page: String) -> String? {
        for motif in [#""externalId":"(UC[\w-]{22})""#,
                      #"itemprop="identifier" content="(UC[\w-]{22})""#,
                      #"youtube\.com/channel/(UC[\w-]{22})""#] {
            if let id = correspondances(motif, dans: page).first { return id }
        }
        return nil
    }

    static func meta(_ propriete: String, dans page: String) -> String? {
        let motif = #"<meta property=""# + NSRegularExpression.escapedPattern(for: propriete) + #"" content="([^"]*)""#
        return correspondances(motif, dans: page).first.map(decoderEntites)
    }

    static func videos(depuisFlux donnees: Data) -> [VideoDuFil] {
        let lecteur = LecteurFlux()
        let analyseur = XMLParser(data: donnees)
        analyseur.delegate = lecteur
        analyseur.parse()
        return lecteur.videos
    }

    // MARK: Outils

    /// Extrait l'objet JSON qui suit `marqueur`, en comptant les accolades hors
    /// des chaines. YouTube l'enchaine a d'autres scripts sur la meme ligne,
    /// d'ou l'impossibilite de couper au premier `;`.
    static func objetJSON(apres marqueur: String, dans page: String) -> [String: Any]? {
        guard let debutMarqueur = page.range(of: marqueur) else { return nil }
        let octets = Array(page.utf8[debutMarqueur.upperBound...])
        guard octets.first == UInt8(ascii: "{") else { return nil }
        var profondeur = 0, dansChaine = false, echappe = false
        for (i, o) in octets.enumerated() {
            if dansChaine {
                if echappe { echappe = false }
                else if o == UInt8(ascii: "\\") { echappe = true }
                else if o == UInt8(ascii: "\"") { dansChaine = false }
                continue
            }
            switch o {
            case UInt8(ascii: "\""): dansChaine = true
            case UInt8(ascii: "{"): profondeur += 1
            case UInt8(ascii: "}"):
                profondeur -= 1
                if profondeur == 0 {
                    let tranche = Data(octets[...i])
                    return try? JSONSerialization.jsonObject(with: tranche) as? [String: Any]
                }
            default: break
            }
        }
        return nil
    }

    private static func correspondances(_ motif: String, dans texte: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: motif) else { return [] }
        let plage = NSRange(texte.startIndex..., in: texte)
        var vus = Set<String>(), resultat: [String] = []
        for m in regex.matches(in: texte, range: plage) {
            guard let r = Range(m.range(at: 1), in: texte) else { continue }
            let valeur = String(texte[r])
            if vus.insert(valeur).inserted { resultat.append(valeur) }
        }
        return resultat
    }

    private static func decoderEntites(_ texte: String) -> String {
        [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">")]
            .reduce(texte) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

/// Lit le flux Atom d'une chaine : une `entry` par video.
private final class LecteurFlux: NSObject, XMLParserDelegate {

    var videos: [VideoDuFil] = []

    private var dansEntree = false, dansAuteur = false
    private var texte = ""
    private var id = "", titre = "", chaine = "", publiee = ""
    private let dates = ISO8601DateFormatter()

    func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        texte = ""
        switch element {
        case "entry": dansEntree = true; id = ""; titre = ""; chaine = ""; publiee = ""
        // L'auteur de la chaine figure aussi en tete du flux, hors de toute
        // entree : il ne doit pas armer le drapeau.
        case "author" where dansEntree: dansAuteur = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        texte += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?,
                qualifiedName: String?) {
        guard dansEntree else { return }
        let valeur = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        switch element {
        case "yt:videoId": id = valeur
        case "title" where !dansAuteur: titre = valeur
        case "name" where dansAuteur: chaine = valeur
        case "published": publiee = valeur
        case "author": dansAuteur = false
        case "entry":
            dansEntree = false
            if !id.isEmpty {
                videos.append(VideoDuFil(id: id, titre: titre, chaine: chaine,
                                         publieeLe: dates.date(from: publiee)))
            }
        default: break
        }
    }
}
