import SwiftUI

/// Les factures envoyées ce mois-ci et leur total (Guillaume, 27 nov.). L'onglet n'existe que pour qui voit l'argent.
struct FinancesView: View {
    @Environment(Magasin.self) private var magasin

    var body: some View {
        NavigationStack {
            List {
                if let finances = magasin.semaine?.finances {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.mois(finances.mois)).font(.subheadline).foregroundStyle(.secondary)
                            Text(Self.argent(finances.total)).font(.largeTitle.bold())
                            Text((finances.nombre > 1 ? "\(finances.nombre) factures envoyées" : "\(finances.nombre) facture envoyée") + " · avant taxes")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }

                    if finances.factures.isEmpty {
                        Text("Aucune facture envoyée ce mois-ci.").foregroundStyle(.secondary)
                    } else {
                        Section("Factures") {
                            ForEach(finances.factures) { LigneFacture(facture: $0) }
                        }
                    }

                    Section {
                        Text("Aperçu tiré de l’étape « Facturé » de chaque rendez-vous. Il sera revu quand QuickBooks fera les factures.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Finances")
            .refreshable { await magasin.synchroniser() }
        }
    }

    static func argent(_ montant: Int) -> String {
        montant.formatted(.number.locale(Locale(identifier: "fr_CA"))) + " $"
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
                Text("Facturée le " + facture.factureLe.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "fr_CA"))))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(FinancesView.argent(facture.montant)).font(.body.weight(.semibold))
                Text(facture.payee ? "Payée" : "À encaisser")
                    .font(.footnote)
                    .foregroundStyle(facture.payee ? .green : .orange)
            }
        }
    }
}
