import SwiftUI

struct RacineView: View {
    @Environment(Magasin.self) private var magasin

    var body: some View {
        if magasin.connecte {
            ListeView()
        } else {
            ConnexionView()
        }
    }
}

/// Pas de mot de passe ici : la double authentification se fait dans l'admin,
/// qui ouvre ensuite l'appli avec un code à usage unique.
struct ConnexionView: View {
    @Environment(Magasin.self) private var magasin
    @Environment(\.openURL) private var ouvrir

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("PP Terrain")
                .font(.largeTitle.bold())
            Text("Vos séances de la semaine, leurs plans et leurs fichiers, même sans réseau.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Label("Ouvrez l’admin dans Safari, sur ce iPhone.", systemImage: "1.circle")
                Label("Réglages, puis « Appli iPhone ».", systemImage: "2.circle")
                Label("Touchez « Ouvrir PP Terrain ».", systemImage: "3.circle")
            }
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            Button {
                ouvrir(Magasin.serveur.appendingPathComponent("admin/appli-iphone"))
            } label: {
                Text("Ouvrir l’admin").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            if let erreur = magasin.erreur {
                Text(erreur).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(24)
    }
}
