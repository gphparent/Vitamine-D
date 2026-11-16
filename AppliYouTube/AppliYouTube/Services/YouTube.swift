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

    // MARK: Liste de lecture

    func fiche(liste id: String) async throws -> FicheListe {
        let page = try await telecharger("https://www.youtube.com/playlist?list=\(id)&hl=fr")
        guard let fiche = AnalyseYouTube.ficheListe(depuisPage: page, id: id) else {
            throw Erreur.introuvable
        }
        return fiche
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

    /// Identifiants de liste de lecture presents dans un texte libre. Les
    /// « Mix » (`RD...`) sont ecartes d'office : ce sont des suites de
    /// recommandations sans fin, la spirale meme que l'appli doit eviter. Les
    /// listes personnelles (a regarder plus tard, j'aime) n'ont pas de page
    /// publique.
    static func identifiantsListe(dans texte: String) -> [String] {
        correspondances(#"youtube\.com/[^\s]*[?&]list=([A-Za-z0-9_-]{10,})"#, dans: texte)
            .filter { !$0.hasPrefix("RD") }
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

    /// Les videos d'une liste, dans l'une ou l'autre des deux formes que
    /// YouTube a employees : `lockupViewModel` (2025 et apres) ou
    /// `playlistVideoRenderer`.
    static func ficheListe(depuisPage page: String, id: String) -> FicheListe? {
        guard let donnees = objetJSON(apres: "var ytInitialData = ", dans: page) else { return nil }
        var videos: [FicheListe.Element] = []
        parcourir(donnees) { cle, objet in
            switch cle {
            case "lockupViewModel":
                guard objet["contentType"] as? String == "LOCKUP_CONTENT_TYPE_VIDEO",
                      let vid = objet["contentId"] as? String,
                      let titre = (((objet["metadata"] as? [String: Any])?["lockupMetadataViewModel"]
                                    as? [String: Any])?["title"] as? [String: Any])?["content"] as? String
                else { return }
                videos.append(.init(id: vid, titre: titre))
            case "playlistVideoRenderer":
                guard let vid = objet["videoId"] as? String,
                      let titre = (((objet["title"] as? [String: Any])?["runs"] as? [[String: Any]])?
                                    .first?["text"]) as? String
                else { return }
                videos.append(.init(id: vid, titre: titre))
            default: break
            }
        }
        guard let titre = meta("og:title", dans: page), !videos.isEmpty else { return nil }
        var chaine = correspondances(#""avatarStack".{0,600}?"text":\{"content":"([^"]+)""#, dans: page).first ?? ""
        for prefixe in ["de ", "by "] where chaine.hasPrefix(prefixe) {
            chaine.removeFirst(prefixe.count)
        }
        return FicheListe(id: id, titre: titre, chaine: chaine, videos: Array(videos.prefix(100)))
    }

    private static func parcourir(_ valeur: Any, _ visite: (String, [String: Any]) -> Void) {
        if let dico = valeur as? [String: Any] {
            for (cle, sous) in dico {
                if let objet = sous as? [String: Any] { visite(cle, objet) }
                parcourir(sous, visite)
            }
        } else if let liste = valeur as? [Any] {
            for sous in liste { parcourir(sous, visite) }
        }
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
