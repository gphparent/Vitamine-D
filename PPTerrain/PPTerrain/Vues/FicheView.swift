import QuickLook
import SwiftUI

struct FicheView: View {
    let seance: RendezVous

    @Environment(Magasin.self) private var magasin
    @Environment(\.openURL) private var ouvrir
    @State private var apercu: URL?

    /// La séance telle que la dernière synchronisation l'a ramenée (« Arrivé » et « Terminé » compris).
    private var actuelle: RendezVous { magasin.rendezVous.first { $0.id == seance.id } ?? seance }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    if let debut = seance.debut {
                        Text("\(Format.jour(debut).capitalized(with: Format.langue)), \(Format.heure(debut))\(seance.fin.map { " à \(Format.heure($0))" } ?? "")")
                            .font(.headline)
                    }
                    Text(seance.lieu).font(.title3.weight(.semibold))
                    if seance.enAttente {
                        Text("Heure à confirmer").font(.subheadline.bold()).foregroundStyle(.orange)
                    }
                }
                if let route = magasin.routes[seance.id], let depart = magasin.depart(pour: seance), magasin.arrivee(de: actuelle) == nil {
                    Label("Partir à \(Format.heure(depart)) : \(route.minutes) min de route, \(Int(route.km.rounded())) km", systemImage: "clock")
                        .font(.subheadline)
                }
                if let lien = seance.lienPlans {
                    Button { ouvrir(lien) } label: { Label("Itinéraire dans Google Maps", systemImage: "car.fill") }
                }
            }

            if !seance.enAttente, let debut = seance.debut, Format.calendrier.isDateInToday(debut) {
                SurPlace(seance: actuelle)
            }

            Section("Accès") {
                if seance.surPlace == false {
                    Label("Personne sur place", systemImage: "key.fill")
                    Label(seance.codeRecu ? "Code reçu : dans l’agenda de ce iPhone" : "Code pas encore reçu", systemImage: seance.codeRecu ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(seance.codeRecu ? Color.primary : Color.orange)
                } else if let qui = seance.quiSurPlace, !qui.isEmpty {
                    Label("Sur place : \(qui)", systemImage: "person.fill")
                } else {
                    Label("Quelqu’un sera sur place", systemImage: "person.fill")
                }
            }

            Section("Contacts") {
                CartePersonne(titre: seance.client.nom ?? "Client", telephone: seance.client.telephone, courriel: seance.client.courriel)
                if let proprio = seance.proprietaire {
                    CartePersonne(titre: "\(proprio.nom ?? "Propriétaire") (propriétaire)", telephone: proprio.contact, courriel: nil)
                }
            }

            Section("Commande") {
                if let forfait = seance.forfait { Text(forfait).font(.body.weight(.semibold)) }
                ForEach(seance.ajouts, id: \.self) { Label($0, systemImage: "plus.circle") }
                if let prix = seance.prix { Text("\(Int(prix)) $ avant taxes").foregroundStyle(.secondary) }
            }

            if let precisions = seance.precisions, !precisions.isEmpty {
                Section("Précisions") { Text(precisions) }
            }
            if let note = seance.notePlanification, !note.isEmpty {
                Section("Note de planification") { Text(note) }
            }

            Section("Fichiers et notes") {
                if seance.pieces.isEmpty {
                    Text("Aucun fichier pour cette séance.").foregroundStyle(.secondary)
                }
                ForEach(seance.pieces) { piece in
                    LignePiece(piece: piece, local: magasin.local(piece)) { apercu = $0 }
                }
            }
        }
        .navigationTitle(seance.debut.map(Format.heure) ?? "Séance")
        .navigationBarTitleDisplayMode(.inline)
        .quickLookPreview($apercu)
        .refreshable { await magasin.synchroniser() }
    }
}

private struct CartePersonne: View {
    let titre: String
    let telephone: String?
    let courriel: String?

    @Environment(\.openURL) private var ouvrir

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(titre).font(.body.weight(.semibold))
            HStack(spacing: 16) {
                if let numero = chiffres(telephone) {
                    Button { ouvrir(URL(string: "tel:\(numero)")!) } label: { Label("Appeler", systemImage: "phone.fill") }
                    Button { ouvrir(URL(string: "sms:\(numero)")!) } label: { Label("Texto", systemImage: "message.fill") }
                } else if let telephone, !telephone.isEmpty {
                    Text(telephone).foregroundStyle(.secondary)
                }
                if let courriel, !courriel.isEmpty, let url = URL(string: "mailto:\(courriel)") {
                    Button { ouvrir(url) } label: { Label("Courriel", systemImage: "envelope.fill") }
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
    }

    /// Un numéro composable, ou rien si le champ contient autre chose (un courriel, un nom).
    private func chiffres(_ texte: String?) -> String? {
        guard let texte else { return nil }
        let garde = texte.filter { $0.isNumber || $0 == "+" }
        return garde.filter(\.isNumber).count >= 10 ? garde : nil
    }
}

private struct LignePiece: View {
    let piece: Piece
    let local: URL?
    let apercevoir: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if piece.fichier {
                Button {
                    if let local { apercevoir(local) }
                } label: {
                    HStack {
                        Image(systemName: icone)
                        VStack(alignment: .leading) {
                            Text(piece.nom ?? "Fichier").foregroundStyle(.primary)
                            Text(local == nil ? "Pas encore téléchargé" : (Format.taille(piece.taille) ?? "Sur ce iPhone"))
                                .font(.caption)
                                .foregroundStyle(local == nil ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
                        }
                    }
                }
                .disabled(local == nil)
            }
            if let note = piece.note, !note.isEmpty {
                Text(note).font(piece.fichier ? .footnote : .body).foregroundStyle(piece.fichier ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            }
        }
    }

    private var icone: String {
        let nom = (piece.nom ?? "").lowercased()
        if nom.hasSuffix(".pdf") { return "doc.richtext" }
        if [".jpg", ".jpeg", ".png", ".heic", ".webp"].contains(where: nom.hasSuffix) { return "photo" }
        return "doc"
    }
}

/// « Arrivé » puis « Terminé » (Guillaume, 25 nov.) : la coordination voit où en est la journée sans appeler,
/// la durée réelle de la séance est notée, et le trajet s'inscrit au carnet de kilométrage. Sans réseau, le geste
/// attend sur le iPhone et part à la prochaine synchronisation.
private struct SurPlace: View {
    let seance: RendezVous

    @Environment(Magasin.self) private var magasin
    @State private var envoi = false

    var body: some View {
        Section("Sur place") {
            if let fin = magasin.fin(de: seance) {
                Label("Terminé à \(Format.heure(fin))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let arrivee = magasin.arrivee(de: seance) {
                    Text("Arrivé à \(Format.heure(arrivee)), \(Int(fin.timeIntervalSince(arrivee) / 60)) min sur place.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if let arrivee = magasin.arrivee(de: seance) {
                Label("Arrivé à \(Format.heure(arrivee))", systemImage: "mappin.circle.fill")
                Button {
                    geste { await magasin.marquerFin(seance) }
                } label: {
                    Label("Terminé", systemImage: "checkmark.circle").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(envoi)
            } else {
                Button {
                    geste { await magasin.marquerArrivee(seance) }
                } label: {
                    Label("Arrivé", systemImage: "mappin.and.ellipse").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(envoi)
                if let route = magasin.routes[seance.id] {
                    Text("\(Int(route.km.rounded())) km iront au carnet de kilométrage.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if magasin.gestes.contains(where: { $0.rendezVous == seance.id }) {
                Label("En attente de réseau : sera envoyé plus tard.", systemImage: "wifi.slash")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func geste(_ action: @escaping () async -> Void) {
        envoi = true
        Task {
            await action()
            envoi = false
        }
    }
}
