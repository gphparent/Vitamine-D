import SwiftUI

/// Une liste de lecture approuvee : ce qui reste a voir, dans l'ordre de la
/// liste, et de quoi tout lire d'affilee.
struct ListeView: View {

    @Environment(AppModel.self) private var modele
    let liste: ListeApprouvee

    @State private var fiche: FicheListe?
    @State private var erreur: String?
    @State private var montrerVues = false

    var body: some View {
        List {
            if let fiche {
                let restantes = fiche.videos.filter { !modele.estVue($0.id) }
                Section {
                    NavigationLink {
                        LecteurView(videoID: restantes.first?.id, listeID: liste.id, titre: liste.titre)
                    } label: {
                        Label(restantes.count == fiche.videos.count ? "Tout lire" : "Reprendre",
                              systemImage: "play.fill")
                    }
                } footer: {
                    Text("\(fiche.videos.count - restantes.count) vue(s) sur \(fiche.videos.count)")
                }

                Section {
                    ForEach(montrerVues ? fiche.videos : restantes, id: \.id) { video in
                        NavigationLink {
                            LecteurView(videoID: video.id, listeID: liste.id, titre: video.titre)
                        } label: {
                            LigneVideo(titre: video.titre, chaine: fiche.chaine,
                                       miniature: URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg"),
                                       vue: modele.estVue(video.id))
                        }
                        .swipeActions { BoutonVue(id: video.id) }
                    }
                }
            } else if let erreur {
                Text(erreur).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(liste.titre)
        .toolbar {
            Toggle(isOn: $montrerVues) {
                Label("Afficher les vidéos vues", systemImage: "eye")
            }
        }
        .task {
            do { fiche = try await modele.fiche(liste: liste.id) }
            catch { erreur = "Impossible de lire cette liste pour l'instant." }
        }
    }
}
