import SwiftUI

/// La semaine en grille, du lundi au dimanche (Guillaume, 25 nov.) : cette semaine et la suivante, gardées hors ligne
/// comme la liste. Toucher une séance ouvre sa fiche.
struct CalendrierView: View {
    @Environment(Magasin.self) private var magasin
    /// 0 : cette semaine ; 1 : la suivante, la dernière que le serveur envoie.
    @State private var decalage = 0

    private let hauteurHeure: CGFloat = 48
    private let largeurHeures: CGFloat = 34

    private var lundi: Date {
        Format.calendrier.date(byAdding: .day, value: 7 * decalage, to: Format.lundi(de: .now))!
    }

    private var jours: [Date] {
        (0..<7).map { Format.calendrier.date(byAdding: .day, value: $0, to: lundi)! }
    }

    private var seances: [RendezVous] {
        let fin = Format.calendrier.date(byAdding: .day, value: 7, to: lundi)!
        return magasin.rendezVous.filter { guard let debut = $0.debut else { return false }; return debut >= lundi && debut < fin }
    }

    /// De 7 h à 20 h, élargi au besoin pour une séance tôt ou tard.
    private var heures: ClosedRange<Int> {
        let cal = Format.calendrier
        let debuts = seances.compactMap(\.debut).map { cal.component(.hour, from: $0) }
        let fins = seances.map { cal.component(.hour, from: Planification.fin($0)) + 1 }
        return min(7, debuts.min() ?? 7)...max(20, fins.max() ?? 20)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                entete
                Divider()
                ScrollView {
                    grille
                        .padding(.bottom, 12)
                }
            }
            .navigationTitle(titre)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: RendezVous.self) { FicheView(seance: $0) }
            .refreshable { await magasin.synchroniser() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { decalage = 0 } label: { Image(systemName: "chevron.left") }
                        .disabled(decalage == 0)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { decalage = 1 } label: { Image(systemName: "chevron.right") }
                        .disabled(decalage == 1)
                }
            }
        }
    }

    private var titre: String {
        let f = DateFormatter()
        f.locale = Format.langue
        f.timeZone = Format.fuseau
        f.dateFormat = "d MMMM"
        return decalage == 0 ? "Cette semaine" : "Semaine du \(f.string(from: lundi))"
    }

    private var entete: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: largeurHeures)
            ForEach(jours, id: \.self) { jour in
                let aujourdhui = Format.calendrier.isDateInToday(jour)
                VStack(spacing: 2) {
                    Text(Self.initiale(jour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(Format.calendrier.component(.day, from: jour))")
                        .font(.subheadline.weight(aujourdhui ? .bold : .regular))
                        .foregroundStyle(aujourdhui ? Color.black : Color.primary)
                        .frame(width: 28, height: 28)
                        .background(aujourdhui ? Color(red: 0.93, green: 0.74, blue: 0.19) : .clear, in: Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 6)
    }

    private var grille: some View {
        GeometryReader { geo in
            let colonne = (geo.size.width - largeurHeures) / 7
            ZStack(alignment: .topLeading) {
                ForEach(Array(heures), id: \.self) { heure in
                    let y = CGFloat(heure - heures.lowerBound) * hauteurHeure
                    Text("\(heure) h")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: largeurHeures - 4, alignment: .trailing)
                        .offset(y: y - 6)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: geo.size.width - largeurHeures, height: 0.5)
                        .offset(x: largeurHeures, y: y)
                }

                if decalage == 0, let y = position(.now) {
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geo.size.width - largeurHeures, height: 1.5)
                        .offset(x: largeurHeures, y: y)
                }

                ForEach(seances) { seance in
                    if let debut = seance.debut, let jour = jours.firstIndex(where: { Format.calendrier.isDate($0, inSameDayAs: debut) }),
                       let haut = position(debut), let bas = position(Planification.fin(seance)) {
                        NavigationLink(value: seance) {
                            Bloc(seance: seance, termine: magasin.fin(de: seance) != nil)
                        }
                        .buttonStyle(.plain)
                        .frame(width: colonne - 2, height: max(bas - haut, 22))
                        .offset(x: largeurHeures + CGFloat(jour) * colonne + 1, y: haut)
                    }
                }
            }
        }
        .frame(height: CGFloat(heures.count) * hauteurHeure)
        .padding(.top, 8)
    }

    /// La hauteur d'un moment de la journée dans la grille.
    private func position(_ date: Date) -> CGFloat? {
        let c = Format.calendrier.dateComponents([.hour, .minute], from: date)
        guard let heure = c.hour, let minute = c.minute else { return nil }
        return (CGFloat(heure - heures.lowerBound) + CGFloat(minute) / 60) * hauteurHeure
    }

    /// « L », « M », « M », « J »…
    private static func initiale(_ jour: Date) -> String {
        let f = DateFormatter()
        f.locale = Format.langue
        f.timeZone = Format.fuseau
        f.dateFormat = "EEE"
        return f.string(from: jour).prefix(3).capitalized(with: Format.langue)
    }
}

private struct Bloc: View {
    let seance: RendezVous
    let termine: Bool

    private var couleur: Color {
        if seance.enAttente { return .orange }
        if termine { return .gray }
        return Color(red: 0.93, green: 0.74, blue: 0.19)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(seance.debut.map(Format.heure) ?? "")
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
            Text(seance.ville ?? seance.lieu)
                .font(.system(size: 9))
                .lineLimit(3)
        }
        .foregroundStyle(.black)
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(couleur.opacity(termine ? 0.45 : 0.9), in: RoundedRectangle(cornerRadius: 5))
    }
}
