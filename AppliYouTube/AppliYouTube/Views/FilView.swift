import SwiftUI

/// Les nouvelles videos des chaines approuvees, moins ce qui a deja ete vu.
struct FilView: View {

    @Environment(AppModel.self) private var modele
    @State private var montrerVues = false

    private var aVoir: [VideoDuFil] {
        montrerVues ? modele.fil : modele.fil.filter { !modele.estVue($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if modele.chaines.isEmpty {
                    ContentUnavailableView(
                        "Aucune chaîne approuvée",
                        systemImage: "checkmark.shield",
                        description: Text("Colle le lien d'une chaîne dans l'onglet Demander : si le juge l'approuve, ses nouvelles vidéos arriveront ici."))
                } else if modele.fil.isEmpty && modele.chargementFil {
                    ProgressView()
                } else if aVoir.isEmpty {
                    ContentUnavailableView(
                        "Tout est vu",
                        systemImage: "checkmark.circle",
                        description: Text("Rien de nouveau à voir pour l'instant."))
                } else {
                    List(aVoir) { video in
                        NavigationLink {
                            LecteurView(videoID: video.id, titre: video.titre)
                        } label: {
                            LigneVideo(titre: video.titre, chaine: video.chaine, miniature: video.miniature,
                                       date: video.publieeLe, vue: modele.estVue(video.id))
                        }
                        .swipeActions { BoutonVue(id: video.id) }
                    }
                    .listStyle(.plain)
                    .refreshable { await modele.rafraichirFil() }
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
