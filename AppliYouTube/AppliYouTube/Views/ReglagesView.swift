import SwiftUI

/// Les cles seulement. Les criteres du juge ne se reglent pas ici : ils sont
/// dans le depot (`Resources/consignes.txt`).
struct ReglagesView: View {

    @Environment(AppModel.self) private var modele

    var body: some View {
        NavigationStack {
            Form {
                ChampCle(
                    compte: .anthropic,
                    titre: "Clé d'API Anthropic",
                    exemple: "sk-ant-…",
                    explication: "Crée-la sur console.anthropic.com. Elle reste dans le trousseau de l'appareil et ne sert qu'à interroger le juge (\(Juge.modele)).")

                ChampCle(
                    compte: .github,
                    titre: "Partage avec les ordis",
                    exemple: "github_pat_…",
                    explication: "Jeton GitHub avec l'accès en lecture et écriture aux Gists. Les approbations sont partagées avec l'extension Brave dans un Gist secret de ton compte.",
                    etat: modele.etatPartage
                ) {
                    Task { await modele.jetonGitHubChange() }
                }

                Section {
                    Text("Les critères du juge sont écrits dans le dépôt de l'appli. Pour les changer, il faut un commit et une nouvelle version TestFlight — c'est voulu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Critères")
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

private struct ChampCle: View {

    let compte: Trousseau.Compte
    let titre: String
    let exemple: String
    let explication: String
    var etat: String? = nil
    var apresChangement: () -> Void = {}

    @State private var saisie = ""
    @State private var enregistree = false

    var body: some View {
        Section {
            if enregistree {
                Label("Enregistré sur cet appareil", systemImage: "key.fill")
                if let etat {
                    Text(etat).font(.footnote).foregroundStyle(.secondary)
                }
                Button("Effacer", role: .destructive) {
                    Trousseau.effacer(compte)
                    enregistree = false
                    apresChangement()
                }
            } else {
                SecureField(exemple, text: $saisie)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Enregistrer") {
                    Trousseau.ecrire(saisie.trimmingCharacters(in: .whitespacesAndNewlines), compte)
                    saisie = ""
                    enregistree = true
                    apresChangement()
                }
                .disabled(saisie.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text(titre)
        } footer: {
            Text(explication)
        }
        .onAppear { enregistree = Trousseau.lire(compte) != nil }
    }
}
