import SwiftUI

/// Ce qui attend après les séances (Guillaume, 25 nov.) : les photos à envoyer et leurs étapes, les retouches
/// demandées par les clients, les tâches données par la coordination. Chaque geste part tout de suite au serveur.
struct TachesView: View {
    @Environment(Magasin.self) private var magasin

    var body: some View {
        NavigationStack {
            List {
                if let taches = magasin.taches {
                    if taches.nombre == 0 {
                        ContentUnavailableView("Rien à faire", systemImage: "checkmark.seal", description: Text("Les photos à envoyer, les retouches et les tâches de la coordination apparaîtront ici."))
                    }
                    if !taches.photos.isEmpty {
                        Section("Photos à envoyer") {
                            ForEach(taches.photos) { photos in
                                NavigationLink(value: photos) { LignePhotos(photos: photos) }
                            }
                        }
                    }
                    if !taches.retouches.isEmpty {
                        Section("Retouches demandées") {
                            ForEach(taches.retouches) { retouche in
                                NavigationLink(value: retouche) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(Self.lieu(retouche.adresse, retouche.ville)).font(.body.weight(.semibold))
                                        Text(retouche.photos.count == 1 ? "1 photo" : "\(retouche.photos.count) photos")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                    if !taches.equipe.isEmpty {
                        Section("De la coordination") {
                            ForEach(taches.equipe) { LigneEquipe(tache: $0) }
                        }
                    }
                } else if magasin.semaine != nil {
                    Text("Ouvrez l’appli avec du réseau pour recevoir vos tâches.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Tâches")
            .navigationDestination(for: Taches.PhotosAEnvoyer.self) { FichePhotos(id: $0.id) }
            .navigationDestination(for: Taches.Retouche.self) { FicheRetouche(retouche: $0) }
            .refreshable { await magasin.synchroniser() }
        }
    }

    static func lieu(_ adresse: String?, _ ville: String?) -> String {
        let morceaux = [adresse, ville].compactMap { $0 }.filter { !$0.isEmpty }
        return morceaux.isEmpty ? "Adresse inconnue" : morceaux.joined(separator: ", ")
    }
}

private struct LignePhotos: View {
    let photos: Taches.PhotosAEnvoyer

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(TachesView.lieu(photos.adresse, photos.ville)).font(.body.weight(.semibold))
            HStack(spacing: 8) {
                if let debut = photos.debut {
                    Text("Séance \(Format.jour(debut))").font(.subheadline).foregroundStyle(.secondary)
                }
                Text("\(photos.faites) sur \(photos.etapes.count)")
                    .font(.caption.bold())
                    .foregroundStyle(photos.faites == photos.etapes.count ? .green : .secondary)
            }
        }
    }
}

/// Les étapes cochées une à une, puis « Photos envoyées » : la tâche quitte la liste et la coordination facture.
private struct FichePhotos: View {
    let id: Int

    @Environment(Magasin.self) private var magasin
    @Environment(\.dismiss) private var fermer
    @State private var envoi = false
    @State private var confirmer = false
    @State private var rate = false

    private var photos: Taches.PhotosAEnvoyer? { magasin.taches?.photos.first { $0.id == id } }

    var body: some View {
        List {
            if let photos {
                Section {
                    Text(TachesView.lieu(photos.adresse, photos.ville)).font(.headline)
                    if let forfait = photos.forfait { Text(forfait).foregroundStyle(.secondary) }
                    if let debut = photos.debut { Text("Séance \(Format.jour(debut)) à \(Format.heure(debut))").foregroundStyle(.secondary) }
                }
                Section("Étapes") {
                    ForEach(photos.etapes, id: \.cle) { etape in
                        Button {
                            geste { await magasin.tache("rendez-vous/\(id)/etape", corps: ["cle": etape.cle, "faite": !etape.faite]) }
                        } label: {
                            Label(etape.nom, systemImage: etape.faite ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(etape.faite ? Color.green : Color.primary)
                        }
                        .disabled(envoi)
                    }
                }
                Section {
                    Button {
                        confirmer = true
                    } label: {
                        Label("Photos envoyées au client", systemImage: "paperplane").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(envoi)
                } footer: {
                    Text("Ne les envoie pas : marque seulement qu’elles sont parties, pour que la coordination facture.")
                }
            } else {
                ContentUnavailableView("Tâche faite", systemImage: "checkmark.seal")
            }
        }
        .navigationTitle("Photos à envoyer")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Les photos sont parties chez le client ?", isPresented: $confirmer, titleVisibility: .visible) {
            Button("Oui, marquer envoyées") {
                geste {
                    let ok = await magasin.tache("rendez-vous/\(id)/photos-envoyees")
                    if ok { fermer() }
                    return ok
                }
            }
        }
        .alert("Pas envoyé", isPresented: $rate) {} message: { Text("Il faut du réseau. Réessayez dans un instant.") }
    }

    private func geste(_ action: @escaping @MainActor () async -> Bool) {
        envoi = true
        Task {
            rate = !(await action())
            envoi = false
        }
    }
}

/// Les notes du client, photo par photo, puis « Faites » ; aviser le client lui envoie le lien de ses photos à jour.
private struct FicheRetouche: View {
    let retouche: Taches.Retouche

    @Environment(Magasin.self) private var magasin
    @Environment(\.dismiss) private var fermer
    @State private var envoi = false
    @State private var rate = false

    var body: some View {
        List {
            Section {
                Text(TachesView.lieu(retouche.adresse, retouche.ville)).font(.headline)
                if let soumise = retouche.soumiseAt { Text("Demandées \(Format.jour(soumise).lowercased())").foregroundStyle(.secondary) }
            }
            if let message = retouche.message, !message.isEmpty {
                Section("Message du client") { Text(message) }
            }
            Section("Photos") {
                ForEach(Array(retouche.photos.enumerated()), id: \.offset) { _, photo in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(photo.nom ?? "Photo").font(.subheadline.weight(.semibold))
                        if let note = photo.note { Text(note) }
                    }
                }
            }
            Section {
                Button {
                    faire(aviser: true)
                } label: {
                    Label("Faites, aviser le client", systemImage: "envelope").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Faites, sans aviser") { faire(aviser: false) }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Aviser envoie au client le lien de ses photos à jour, par courriel ou par texto.")
            }
            .disabled(envoi)
        }
        .navigationTitle("Retouches")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Pas envoyé", isPresented: $rate) {} message: { Text("Il faut du réseau. Réessayez dans un instant.") }
    }

    private func faire(aviser: Bool) {
        envoi = true
        Task {
            let ok = await magasin.tache("retouches/\(retouche.id)/faite", corps: ["aviser": aviser])
            envoi = false
            if ok { fermer() } else { rate = true }
        }
    }
}

private struct LigneEquipe: View {
    let tache: Taches.DeLaCoordination

    @Environment(Magasin.self) private var magasin
    @State private var envoi = false
    @State private var rate = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                envoi = true
                Task {
                    rate = !(await magasin.tache("taches/\(tache.id)/faite"))
                    envoi = false
                }
            } label: {
                Image(systemName: envoi ? "circle.dotted" : "circle").font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(envoi)

            VStack(alignment: .leading, spacing: 3) {
                Text(tache.titre).font(.body.weight(.semibold))
                if let jour = tache.jour {
                    Text("Pour \(Format.jour(jour).lowercased())")
                        .font(.caption)
                        .foregroundStyle(tache.enRetard() ? .red : .secondary)
                }
                if let details = tache.details, !details.isEmpty {
                    Text(details).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        .alert("Pas envoyé", isPresented: $rate) {} message: { Text("Il faut du réseau. Réessayez dans un instant.") }
    }
}
