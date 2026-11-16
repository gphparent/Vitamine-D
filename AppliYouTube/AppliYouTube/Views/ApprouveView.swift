import SwiftUI

/// Tout ce que le juge a ouvert. On peut retirer, jamais ajouter.
struct ApprouveView: View {

    @Environment(AppModel.self) private var modele
    @State private var montrerVues = false
    @State private var aDesabonner: String?


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

                Section {
                    let sources = modele.sources
                    if sources.isEmpty {
                        Text("Aucune chaîne.").foregroundStyle(.secondary)
                    }
                    ForEach(sources) { source in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.nom).font(.body.weight(.medium))
                            Text(source.description).font(.caption).foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Se désabonner", role: .destructive) {
                                aDesabonner = source.nom
                            }
                        }
                    }
                } header: {
                    Text("Chaînes")
                } footer: {
                    Text("Glisse vers la gauche pour te désabonner : la chaîne et ses vidéos approuvées disparaissent.")
                }
            }
            .navigationTitle("Approuvé")
            .confirmationDialog(
                "Se désabonner de « \(aDesabonner ?? "") » ?",
                isPresented: Binding(get: { aDesabonner != nil }, set: { if !$0 { aDesabonner = nil } }),
                titleVisibility: .visible
            ) {
                Button("Se désabonner", role: .destructive) {
                    if let nom = aDesabonner { modele.desabonner(chaine: nom) }
                }
            } message: {
                Text("La chaîne et toutes ses vidéos approuvées disparaissent, sur tous tes appareils.")
            }
            .toolbar {
                Toggle(isOn: $montrerVues) {
                    Label("Afficher les vidéos vues", systemImage: "eye")
                }
            }
        }
    }
}
