import Foundation
import Observation

/// Etat de l'appli : ce qui est approuve, le fil, et la conversation avec le
/// juge. Rien n'entre dans les listes approuvees autrement que par un verdict
/// du juge — l'appli n'offre aucun bouton pour le faire a la main.
@MainActor
@Observable
final class AppModel {

    private(set) var chaines: [Chaine] = []
    private(set) var videos: [VideoApprouvee] = []
    private(set) var listes: [ListeApprouvee] = []
    /// Ce qui a ete vu, par identifiant de video. Le fil et les listes s'en
    /// servent pour ne montrer que ce qui reste a voir.
    private(set) var vus: [String: Visionnement] = [:]
    private(set) var fil: [VideoDuFil] = []
    private(set) var echanges: [Echange] = []
    private(set) var enAttente = false
    private(set) var chargementFil = false
    private(set) var etatPartage: String?

    /// Au-dela, la conversation repart a zero : l'historique est renvoye en
    /// entier a chaque tour, et on ne peut pas l'ecourter sans le reecrire.
    static let tourMaximum = 30

    private var messagesAPI: [Any] = []
    private var retraits: [Retrait] = []
    private var gistID: String?
    private let store = Store()
    private let youtube = YouTubeService()
    private let juge = Juge()

    init() {
        chaines = store.charger([Chaine].self, pour: .chaines) ?? []
        videos = store.charger([VideoApprouvee].self, pour: .videos) ?? []
        echanges = store.charger([Echange].self, pour: .echanges) ?? []
        retraits = store.charger([Retrait].self, pour: .retraits) ?? []
        listes = store.charger([ListeApprouvee].self, pour: .listes) ?? []
        for v in store.charger([Visionnement].self, pour: .vus) ?? [] { vus[v.id] = v }
        gistID = store.charger(String.self, pour: .gistID)
        if let brut = store.chargerBrut(.messagesAPI),
           let liste = try? JSONSerialization.jsonObject(with: brut) as? [Any] {
            messagesAPI = liste
        }
    }

    func demarrer() async {
        await synchroniser()
        await rafraichirFil()
    }

    // MARK: Partage

    /// Fusionne les approbations locales avec celles du Gist, puis les deux
    /// cotes repartent du meme document. Sans jeton GitHub, rien ne se passe.
    func synchroniser() async {
        guard let jeton = Trousseau.lire(.github), !jeton.isEmpty else {
            etatPartage = nil
            return
        }
        let local = DocumentPartage(chaines: chaines, videos: videos, listes: listes,
                                    retraits: retraits, vus: Array(vus.values))
        do {
            let (fusionne, id) = try await PartageGist(jeton: jeton).synchroniser(local, gistID: gistID)
            chaines = fusionne.chaines
            videos = fusionne.videos
            listes = fusionne.listes
            retraits = fusionne.retraits
            vus = Dictionary(fusionne.vus.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            gistID = id
            etatPartage = "Synchronisé à \(Date.now.formatted(date: .omitted, time: .shortened))."
            enregistrer()
        } catch {
            etatPartage = error.localizedDescription
        }
    }

    /// Apres un changement de jeton : le Gist sera recherche a nouveau.
    func jetonGitHubChange() async {
        gistID = nil
        store.retirer(.gistID)
        await synchroniser()
        await rafraichirFil()
    }

    // MARK: Fil

    func rafraichirFil() async {
        chargementFil = true
        defer { chargementFil = false }
        var tout: [VideoDuFil] = []
        await withTaskGroup(of: [VideoDuFil].self) { groupe in
            for chaine in chaines {
                groupe.addTask { [youtube] in (try? await youtube.flux(chaine: chaine.id)) ?? [] }
            }
            for await lot in groupe { tout += lot }
        }
        fil = tout.sorted { ($0.publieeLe ?? .distantPast) > ($1.publieeLe ?? .distantPast) }
    }

    // MARK: Visionnements

    func estVue(_ id: String) -> Bool {
        vus[id]?.vu ?? false
    }

    /// Appele par le lecteur (fin ou 90 % atteints) ou par le bouton manuel.
    func marquer(_ id: String, vue: Bool) {
        guard estVue(id) != vue else { return }
        vus[id] = Visionnement(id: id, le: .now, vu: vue)
        enregistrer()
        Task { await synchroniser() }
    }

    func fiche(liste id: String) async throws -> FicheListe {
        try await youtube.fiche(liste: id)
    }

    // MARK: Juge

    func demander(_ texte: String) async {
        let texte = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texte.isEmpty, !enAttente else { return }
        enAttente = true
        defer { enAttente = false }

        if messagesAPI.count >= Self.tourMaximum * 2 {
            nouvelleConversation(note: "Conversation recommencée : elle était devenue trop longue.")
        }
        ajouter(Echange(auteur: .moi, texte: texte))

        // L'appli lit elle-meme ce que pointent les liens, pour que le juge ne
        // tranche que sur des faits et jamais sur la seule parole de
        // l'utilisateur.
        var fichesVideo: [FicheVideo] = []
        var fichesChaine: [FicheChaine] = []
        var fichesListe: [FicheListe] = []
        for id in AnalyseYouTube.identifiantsVideo(dans: texte).prefix(3) {
            if let fiche = try? await youtube.fiche(video: id) { fichesVideo.append(fiche) }
        }
        for adresse in AnalyseYouTube.adressesChaine(dans: texte).prefix(2) {
            if let fiche = try? await youtube.fiche(chaine: adresse) { fichesChaine.append(fiche) }
        }
        for id in AnalyseYouTube.identifiantsListe(dans: texte).prefix(2) {
            if let fiche = try? await youtube.fiche(liste: id) { fichesListe.append(fiche) }
        }

        let nouveau: [String: Any] = [
            "role": "user",
            "content": composer(texte, fichesVideo: fichesVideo, fichesChaine: fichesChaine,
                                fichesListe: fichesListe),
        ]

        do {
            let decision = try await juge.juger(historique: messagesAPI, nouveau: nouveau)
            messagesAPI.append(nouveau)
            messagesAPI.append(["role": "assistant", "content": decision.contenuBrut] as [String: Any])
            appliquer(decision, fichesVideo: fichesVideo, fichesChaine: fichesChaine,
                      fichesListe: fichesListe)
            // Seuls les liens que l'appli sait lire sont proposes a l'examen.
            let propositions = decision.propositions.filter { Self.contientUnLien($0.url) }
            ajouter(Echange(auteur: .juge, texte: decision.reponse, verdict: decision.verdict,
                            propositions: propositions.isEmpty ? nil : Array(propositions.prefix(5))))
        } catch {
            // Rien n'est ajoute a l'historique de l'API : le tour echoue
            // disparait, et la conversation reste valide pour le suivant.
            ajouter(Echange(auteur: .systeme, texte: error.localizedDescription))
        }
        enregistrer()
    }

    func nouvelleConversation(note: String? = nil) {
        messagesAPI = []
        echanges = note.map { [Echange(auteur: .systeme, texte: $0)] } ?? []
        enregistrer()
    }

    /// Un lien de video, de liste ou de chaine que l'appli sait lire.
    private static func contientUnLien(_ texte: String) -> Bool {
        if !AnalyseYouTube.identifiantsVideo(dans: texte).isEmpty { return true }
        if !AnalyseYouTube.identifiantsListe(dans: texte).isEmpty { return true }
        return !AnalyseYouTube.adressesChaine(dans: texte).isEmpty
    }

    private func composer(_ texte: String, fichesVideo: [FicheVideo], fichesChaine: [FicheChaine],
                          fichesListe: [FicheListe]) -> String {
        let encodeur = JSONEncoder()
        encodeur.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        func json<T: Encodable>(_ v: T) -> String {
            (try? encodeur.encode(v)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
        }

        var parties = [texte]
        for fiche in fichesVideo { parties.append("<fiche_video>\(json(fiche))</fiche_video>") }
        for fiche in fichesChaine { parties.append("<fiche_chaine>\(json(fiche))</fiche_chaine>") }
        for fiche in fichesListe { parties.append("<fiche_liste>\(json(fiche))</fiche_liste>") }
        let aucuneFiche = fichesVideo.isEmpty && fichesChaine.isEmpty && fichesListe.isEmpty
        if aucuneFiche && Self.contientUnLien(texte) {
            parties.append("<note>L'appli n'a pas pu lire le lien fourni.</note>")
        }
        let nomsChaines = chaines.isEmpty ? "aucune" : chaines.map(\.nom).joined(separator: ", ")
        let nomsListes = listes.isEmpty ? "aucune" : listes.map(\.titre).joined(separator: ", ")
        let etat = "Chaînes approuvées : \(nomsChaines). Listes approuvées : \(nomsListes). "
            + "Vidéos approuvées à l'unité : \(videos.count)."
        parties.append("<etat>\(etat)</etat>")
        return parties.joined(separator: "\n\n")
    }

    private func appliquer(_ decision: Juge.Decision, fichesVideo: [FicheVideo], fichesChaine: [FicheChaine],
                           fichesListe: [FicheListe]) {
        switch decision.verdict {
        case .approuveVideo:
            // L'identifiant doit sortir d'une fiche lue par l'appli a ce tour-ci.
            guard let fiche = fichesVideo.first(where: { $0.id == decision.videoID }),
                  !videos.contains(where: { $0.id == fiche.id }) else { return }
            videos.insert(VideoApprouvee(id: fiche.id, titre: fiche.titre, chaine: fiche.chaine,
                                         approuveeLe: .now, raison: decision.reponse), at: 0)
            Task { await synchroniser() }
        case .approuveChaine:
            let depuisVideo = fichesVideo.first { $0.chaineID == decision.chaineID }
            let depuisChaine = fichesChaine.first { $0.id == decision.chaineID }
            guard let nom = depuisChaine?.nom ?? depuisVideo?.chaine,
                  !chaines.contains(where: { $0.id == decision.chaineID }) else { return }
            chaines.append(Chaine(id: decision.chaineID, nom: nom, approuveeLe: .now,
                                  raison: decision.reponse))
            Task { await synchroniser(); await rafraichirFil() }
        case .approuveListe:
            guard let fiche = fichesListe.first(where: { $0.id == decision.listeID }),
                  !listes.contains(where: { $0.id == fiche.id }) else { return }
            listes.insert(ListeApprouvee(id: fiche.id, titre: fiche.titre, chaine: fiche.chaine,
                                         approuveeLe: .now, raison: decision.reponse), at: 0)
            Task { await synchroniser() }
        case .refuse, .discussion:
            break
        }
    }

    // MARK: Retraits — toujours permis : fermer une porte ne demande personne.

    func retirer(chaine: Chaine) {
        chaines.removeAll { $0.id == chaine.id }
        fil.removeAll { $0.chaine == chaine.nom }
        retraits.append(Retrait(id: chaine.id, le: .now))
        enregistrer()
        Task { await synchroniser() }
    }

    func retirer(video: VideoApprouvee) {
        videos.removeAll { $0.id == video.id }
        retraits.append(Retrait(id: video.id, le: .now))
        enregistrer()
        Task { await synchroniser() }
    }

    /// Les chaines d'ou viennent les videos approuvees, qu'elles soient
    /// approuvees en entier ou non, avec le nombre de videos de chacune.
    var sources: [SourceChaine] {
        var compte: [String: Int] = [:]
        for video in videos { compte[video.chaine, default: 0] += 1 }
        var noms = Set(compte.keys)
        noms.formUnion(chaines.map(\.nom))
        let tries = noms.sorted { $0.localizedCompare($1) == .orderedAscending }
        return tries.map { nom in
            SourceChaine(nom: nom, approuvee: chaines.contains { $0.nom == nom }, videos: compte[nom] ?? 0)
        }
    }

    /// Se desabonner : la chaine n'est plus approuvee, et ses videos approuvees
    /// a l'unite partent avec elle.
    func desabonner(chaine nom: String) {
        var ids = chaines.filter { $0.nom == nom }.map(\.id)
        ids += videos.filter { $0.chaine == nom }.map(\.id)
        chaines.removeAll { $0.nom == nom }
        videos.removeAll { $0.chaine == nom }
        fil.removeAll { $0.chaine == nom }
        retraits += ids.map { Retrait(id: $0, le: .now) }
        enregistrer()
        Task { await synchroniser() }
    }

    func retirer(liste: ListeApprouvee) {
        listes.removeAll { $0.id == liste.id }
        retraits.append(Retrait(id: liste.id, le: .now))
        enregistrer()
        Task { await synchroniser() }
    }

    // MARK: Persistance

    private func ajouter(_ echange: Echange) {
        echanges.append(echange)
    }

    private func enregistrer() {
        store.enregistrer(chaines, pour: .chaines)
        store.enregistrer(videos, pour: .videos)
        store.enregistrer(echanges, pour: .echanges)
        store.enregistrer(retraits, pour: .retraits)
        store.enregistrer(listes, pour: .listes)
        store.enregistrer(Array(vus.values), pour: .vus)
        if let gistID { store.enregistrer(gistID, pour: .gistID) }
        if let brut = try? JSONSerialization.data(withJSONObject: messagesAPI) {
            store.enregistrerBrut(brut, pour: .messagesAPI)
        }
    }
}
