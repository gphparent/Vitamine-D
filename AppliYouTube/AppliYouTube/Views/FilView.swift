import SwiftUI

/// Ce qui reste a voir : les nouvelles videos des chaines approuvees, puis les
/// videos approuvees a l'unite, moins ce qui a deja ete vu.
struct FilView: View {

    @Environment(AppModel.self) private var modele
    @State private var montrerVues = false

    private var nouveautes: [VideoDuFil] {
        montrerVues ? modele.fil : modele.fil.filter { !modele.estVue($0.id) }
    }

    /// Les videos approuvees a l'unite, sans celles deja dans les nouveautes.
    private var approuvees: [VideoApprouvee] {
        let dansLeFil = Set(modele.fil.map(\.id))
        return modele.videos
            .filter { !dansLeFil.contains($0.id) && (montrerVues || !modele.estVue($0.id)) }
            .sorted { ($0.approuveeLe, $1.titre) > ($1.approuveeLe, $0.titre) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if modele.chaines.isEmpty && modele.videos.isEmpty {
                    ContentUnavailableView(
                        "Rien d'approuvé pour l'instant",
                        systemImage: "checkmark.shield",
                        description: Text("Dans l'onglet Demander, colle un lien ou demande au juge de chercher : ce qu'il approuve arrivera ici."))
                } else if modele.fil.isEmpty && modele.chargementFil && approuvees.isEmpty {
                    ProgressView()
                } else if nouveautes.isEmpty && approuvees.isEmpty {
                    ContentUnavailableView(
                        "Tout est vu",
                        systemImage: "checkmark.circle",
                        description: Text("Rien de nouveau à voir pour l'instant."))
                } else {
                    List {
                        if !nouveautes.isEmpty {
                            Section("Nouveautés des chaînes") {
                                ForEach(nouveautes) { video in
                                    ligne(id: video.id, titre: video.titre, chaine: video.chaine,
                                          miniature: video.miniature, date: video.publieeLe)
                                }
                            }
                        }
                        if !approuvees.isEmpty {
                            Section("Vidéos approuvées (\(approuvees.count))") {
                                ForEach(approuvees) { video in
                                    ligne(id: video.id, titre: video.titre, chaine: video.chaine,
                                          miniature: URL(string: "https://i.ytimg.com/vi/\(video.id)/mqdefault.jpg"))
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable {
                        await modele.synchroniser()
                        await modele.rafraichirFil()
                    }
                }
            }
            .navigationTitle("À voir")
            .toolbar {
                Toggle(isOn: $montrerVues) {
                    Label("Afficher les vidéos vues", systemImage: "eye")
                }
            }
        }
    }

    private func ligne(id: String, titre: String, chaine: String, miniature: URL?, date: Date? = nil) -> some View {
        NavigationLink {
            LecteurView(videoID: id, titre: titre)
        } label: {
            LigneVideo(titre: titre, chaine: chaine, miniature: miniature, date: date, vue: modele.estVue(id))
        }
        .swipeActions { BoutonVue(id: id) }
    }
}

/// Bascule vue / a voir, pour un glissement sur une ligne.
struct BoutonVue: View {

    @Environment(AppModel.self) private var modele
    let id: String

    var body: some View {
        let vue = modele.estVue(id)
        Button {
            modele.marquer(id, vue: !vue)
        } label: {
            Label(vue ? "À voir" : "Vue", systemImage: vue ? "arrow.uturn.backward" : "checkmark")
        }
        .tint(vue ? Color.orange : Color.green)
    }
}

struct LigneVideo: View {

    let titre: String
    let chaine: String
    let miniature: URL?
    var date: Date? = nil
    var vue = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: miniature) { image in
                image.resizable().aspectRatio(16 / 9, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .bottomTrailing) {
                if vue {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .green)
                        .padding(4)
                }
            }
            .opacity(vue ? 0.6 : 1)

            VStack(alignment: .leading, spacing: 4) {
                Text(titre).font(.subheadline.weight(.medium)).lineLimit(3)
                Text(chaine).font(.caption).foregroundStyle(.secondary)
                if let date {
                    Text(date, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
