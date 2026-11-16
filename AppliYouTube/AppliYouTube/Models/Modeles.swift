import Foundation

/// Une chaine que le juge a approuvee en entier : toutes ses nouvelles videos
/// arrivent dans le fil sans nouvelle demande.
struct Chaine: Codable, Identifiable, Hashable {
    let id: String              // UC..., l'identifiant stable de YouTube
    var nom: String
    var approuveeLe: Date
    var raison: String
}

/// Une video approuvee a l'unite, hors de toute chaine approuvee.
struct VideoApprouvee: Codable, Identifiable, Hashable {
    let id: String              // les onze caracteres apres `v=`
    var titre: String
    var chaine: String
    var approuveeLe: Date
    var raison: String
}

/// Une entree du fil, tiree du flux RSS d'une chaine approuvee.
struct VideoDuFil: Identifiable, Hashable {
    let id: String
    let titre: String
    let chaine: String
    let publieeLe: Date?

    var miniature: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg") }
}

/// Une bulle de la conversation avec le juge, telle qu'affichee.
struct Echange: Codable, Identifiable, Hashable {
    enum Auteur: String, Codable { case moi, juge, systeme }

    var id = UUID()
    let auteur: Auteur
    let texte: String
    var verdict: Verdict? = nil
    var date = Date()
}

enum Verdict: String, Codable {
    case approuveVideo = "approuve_video"
    case approuveChaine = "approuve_chaine"
    case refuse = "refuse"
    case discussion = "discussion"
}

/// Ce que l'appli a pu lire d'une video avant de la soumettre au juge. Le juge
/// ne voit rien d'autre : il ne peut approuver que ce que l'appli a consulte.
struct FicheVideo: Codable, Hashable {
    let id: String
    var titre: String
    var chaine: String
    var chaineID: String?
    var description: String?
    var dureeSecondes: Int?
    var categorie: String?
    var motsCles: [String]?
}

/// Meme principe pour une chaine : son nom, sa description et les titres de
/// ses dernieres videos, qui disent mieux que tout le reste ce qu'elle publie.
struct FicheChaine: Codable, Hashable {
    let id: String
    var nom: String
    var description: String?
    var dernieresVideos: [String]
}
