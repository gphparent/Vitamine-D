import QuickLook
import SwiftUI

struct FicheView: View {
    let seance: RendezVous

    @Environment(Magasin.self) private var magasin
    @Environment(\.openURL) private var ouvrir
    @State private var apercu: URL?

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
                if let lien = seance.lienPlans {
                    Button { ouvrir(lien) } label: { Label("Itinéraire dans Plans", systemImage: "car.fill") }
                }
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
