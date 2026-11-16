import SwiftUI

/// Tout ce que le juge a ouvert. On peut retirer, jamais ajouter.
struct ApprouveView: View {

    @Environment(AppModel.self) private var modele
    @State private var montrerVues = false

    var body: some View {
        NavigationStack {
            List {
                Section("Listes de lecture") {
                    if modele.listes.isEmpty {
                        Text("Aucune liste approuvée.").foregroundStyle(.secondary)
                    }
                    ForEach(modele.listes) { liste in
                        NavigationLink {
                            ListeView(liste: liste)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(liste.titre).font(.body.weight(.medium))
                                Text(liste.chaine).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { indices in
                        indices.map { modele.listes[$0] }.forEach(modele.retirer(liste:))
                    }
                }

                Section("Vidéos") {
                    let videos = montrerVues ? modele.videos : modele.videos.filter { !modele.estVue($0.id) }
                    if videos.isEmpty {
                        Text(modele.videos.isEmpty ? "Aucune vidéo approuvée à l'unité." : "Toutes les vidéos approuvées sont vues.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(videos) { video in
                        NavigationLink {
                            LecteurView(videoID: video.id, titre: video.titre)
                        } label: {
                            LigneVideo(titre: video.titre, chaine: video.chaine,
                                       miniature: URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg"),
                                       vue: modele.estVue(video.id))
                        }
                        .swipeActions(edge: .leading) { BoutonVue(id: video.id) }
                    }
                    .onDelete { indices in
                        indices.map { videos[$0] }.forEach(modele.retirer(video:))
                    }
                }

                Section("Chaînes") {
                    if modele.chaines.isEmpty {
                        Text("Aucune chaîne approuvée.").foregroundStyle(.secondary)
                    }
                    ForEach(modele.chaines) { chaine in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(chaine.nom).font(.body.weight(.medium))
                            Text(chaine.raison).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    .onDelete { indices in
                        indices.map { modele.chaines[$0] }.forEach(modele.retirer(chaine:))
                    }
                }
            }
            .navigationTitle("Approuvé")
            .toolbar {
                Toggle(isOn: $montrerVues) {
                    Label("Afficher les vidéos vues", systemImage: "eye")
                }
            }
        }
    }
}
