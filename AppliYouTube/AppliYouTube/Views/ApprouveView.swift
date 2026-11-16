import SwiftUI

/// Tout ce que le juge a ouvert. On peut retirer, jamais ajouter.
struct ApprouveView: View {

    @Environment(AppModel.self) private var modele

    var body: some View {
        NavigationStack {
            List {
                Section("Vidéos") {
                    if modele.videos.isEmpty {
                        Text("Aucune vidéo approuvée à l'unité.").foregroundStyle(.secondary)
                    }
                    ForEach(modele.videos) { video in
                        NavigationLink {
                            LecteurView(videoID: video.id, titre: video.titre)
                        } label: {
                            LigneVideo(titre: video.titre, chaine: video.chaine,
                                       miniature: URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg"))
                        }
                    }
                    .onDelete { indices in
                        indices.map { modele.videos[$0] }.forEach(modele.retirer(video:))
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
        }
    }
}
