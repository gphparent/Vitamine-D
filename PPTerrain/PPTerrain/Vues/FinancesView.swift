import SwiftUI

/// Ses séances faites ce mois-ci, facturées ou non, et la part qui lui revient (Guillaume, 27 nov.). L'onglet n'existe que pour qui voit l'argent.
struct FinancesView: View {
    @Environment(Magasin.self) private var magasin

    var body: some View {
        NavigationStack {
            List {
                if let finances = magasin.semaine?.finances {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Ma part · " + Self.mois(finances.mois)).font(.headline)
                            Text(Self.argent(finances.total)).font(.largeTitle.bold())
                            Text((finances.nombre > 1 ? "\(finances.nombre) séances" : "\(finances.nombre) séance") + " · avant taxes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let aRegler = finances.aRegler, aRegler > 0 {
                                Text(aRegler > 1 ? "\(aRegler) séances sans part connue, hors du total" : "1 séance sans part connue, hors du total")
                                    .font(.footnote)
                                    .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 6)
                    }

                    if finances.factures.isEmpty {
                        Text("Aucune séance faite ce mois-ci.").foregroundStyle(.secondary)
                    } else {
                        Section("Ma part par séance") {
                            ForEach(finances.factures) { LigneFacture(facture: $0) }
                        }
                    }

                    Section {
                        Text("Toutes les séances faites dans le mois, facturées ou non. Aperçu, revu quand QuickBooks fera les factures.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Finances")
            .refreshable { await magasin.synchroniser() }
        }
    }

    static func argent(_ montant: Double) -> String {
        montant.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "fr_CA"))) + " $"
    }

    /// « 2026-11 » devient « Novembre 2026 ».
    static func mois(_ texte: String) -> String {
        let lecture = DateFormatter()
        lecture.dateFormat = "yyyy-MM"
        lecture.locale = Locale(identifier: "en_US_POSIX")
        guard let date = lecture.date(from: texte) else { return texte }
        let ecriture = DateFormatter()
        ecriture.locale = Locale(identifier: "fr_CA")
        ecriture.dateFormat = "LLLL yyyy"
        return ecriture.string(from: date).prefix(1).uppercased() + ecriture.string(from: date).dropFirst()
    }
}

private struct LigneFacture: View {
    let facture: Finances.Facture

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(facture.client ?? "Client inconnu").font(.body.weight(.semibold))
                Text(TachesView.lieu(facture.adresse, facture.ville)).font(.subheadline).foregroundStyle(.secondary)
                Text(facture.le.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "fr_CA"))))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(facture.montant.map(FinancesView.argent) ?? "Part à régler").font(.body.weight(.semibold))
                Text(facture.etat)
                    .font(.footnote)
                    .foregroundStyle(facture.etat == "Payée" ? .green : .orange)
            }
        }
    }
}
