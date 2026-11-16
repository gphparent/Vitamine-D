import SwiftUI

struct FilView: View {

    @Environment(AppModel.self) private var modele

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
                } else {
                    List(modele.fil) { video in
                        NavigationLink {
                            LecteurView(videoID: video.id, titre: video.titre)
                        } label: {
                            LigneVideo(titre: video.titre, chaine: video.chaine,
                                       miniature: video.miniature, date: video.publieeLe)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await modele.rafraichirFil() }
                }
            }
            .navigationTitle("Fil")
        }
    }
}

struct LigneVideo: View {

    let titre: String
    let chaine: String
    let miniature: URL?
    var date: Date? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: miniature) { image in
                image.resizable().aspectRatio(16 / 9, contentMode: .fill)
            } placeholder: {
                Rectangle().fill(.quaternary)
            }
            .frame(width: 128, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))

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
