import SwiftUI

struct ListeView: View {
    @Environment(Magasin.self) private var magasin
    @State private var confirmerDeconnexion = false

    var body: some View {
        NavigationStack {
            List {
                if let erreur = magasin.erreur {
                    Label(erreur, systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if magasin.semaine != nil && magasin.rendezVous.isEmpty {
                    ContentUnavailableView("Aucune séance cette semaine", systemImage: "calendar", description: Text("Les séances des huit prochains jours apparaîtront ici."))
                }

                ForEach(Format.parJour(magasin.rendezVous)) { groupe in
                    Section(Format.jour(groupe.jour).capitalized(with: Format.langue)) {
                        ForEach(groupe.seances) { seance in
                            NavigationLink(value: seance) { LigneSeance(seance: seance) }
                        }
                    }
                }

                if let semaine = magasin.semaine {
                    Text("Mis à jour \(semaine.genereLe.formatted(.relative(presentation: .named).locale(Format.langue))).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Séances")
            .navigationDestination(for: RendezVous.self) { FicheView(seance: $0) }
            .refreshable { await magasin.synchroniser() }
            .overlay {
                if magasin.semaine == nil && magasin.enCours { ProgressView("Téléchargement de la semaine…") }
            }
            .toolbar {
                Menu {
                    Button("Déconnecter cet iPhone", role: .destructive) { confirmerDeconnexion = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .confirmationDialog("Déconnecter cet iPhone ? Tout ce qui est téléchargé sera effacé.", isPresented: $confirmerDeconnexion, titleVisibility: .visible) {
                Button("Déconnecter", role: .destructive) { Task { await magasin.deconnecter() } }
            }
        }
    }
}

struct LigneSeance: View {
    let seance: RendezVous

    @Environment(Magasin.self) private var magasin

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(seance.debut.map(Format.heure) ?? "")
                .font(.headline.monospacedDigit())
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(seance.lieu).font(.body.weight(.semibold))
                if let forfait = seance.forfait { Text(forfait).font(.subheadline).foregroundStyle(.secondary) }
                HStack(spacing: 8) {
                    if seance.enAttente { Text("À confirmer").font(.caption.bold()).foregroundStyle(.orange) }
                    if let fin = magasin.fin(de: seance) {
                        Label("Terminé \(Format.heure(fin))", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                    } else if let depart = magasin.depart(pour: seance), !seance.enAttente, magasin.arrivee(de: seance) == nil {
                        Label("Partir \(Format.heure(depart))", systemImage: "clock").font(.caption).foregroundStyle(.secondary)
                    }
                    if seance.surPlace == false { Label("Personne sur place", systemImage: "key").font(.caption).foregroundStyle(.secondary) }
                    if !seance.pieces.isEmpty { Label("\(seance.pieces.count)", systemImage: "paperclip").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
