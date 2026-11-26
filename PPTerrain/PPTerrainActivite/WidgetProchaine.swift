import SwiftUI
import WidgetKit

/// Le petit widget « Prochaine séance ». CarPlay (iOS 26) l'affiche à gauche du tableau de bord une fois choisi dans
/// Réglages, Général, CarPlay ; il ne fait que montrer, rien à toucher en conduisant.
struct WidgetProchaine: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Prochaines.genre, provider: Fournisseur()) { entree in
            VueProchaine(entree: entree)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Prochaine séance")
        .description("L’heure, la ville et l’heure de départ de la prochaine séance. Aussi dans CarPlay.")
        .supportedFamilies([.systemSmall])
    }
}

struct EntreeProchaine: TimelineEntry {
    let date: Date
    let seance: ProchaineSeance?
    /// Faux tant que le iPhone n'a pas été déverrouillé depuis son allumage, ou que l'appli n'a rien déposé.
    let lisible: Bool
}

struct Fournisseur: TimelineProvider {
    func placeholder(in context: Context) -> EntreeProchaine {
        EntreeProchaine(date: .now, seance: ProchaineSeance(ville: "Saint-Jérôme", debut: .now.addingTimeInterval(5400), fin: .now.addingTimeInterval(9000), depart: .now.addingTimeInterval(3600)), lisible: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (EntreeProchaine) -> Void) {
        let seances = Prochaines.lire()
        completion(context.isPreview && seances == nil
            ? placeholder(in: context)
            : EntreeProchaine(date: .now, seance: seances.flatMap { Prochaines.aMontrer($0, a: .now) }, lisible: seances != nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<EntreeProchaine>) -> Void) {
        let maintenant = Date.now
        guard let seances = Prochaines.lire() else {
            // Rien de lisible : on réessaie bientôt, l'appli redemande aussi un dessin à chaque ouverture.
            completion(Timeline(entries: [EntreeProchaine(date: maintenant, seance: nil, lisible: false)], policy: .after(maintenant.addingTimeInterval(900))))
            return
        }
        let entrees = Prochaines.moments(seances, depuis: maintenant).prefix(60).map {
            EntreeProchaine(date: $0, seance: Prochaines.aMontrer(seances, a: $0), lisible: true)
        }
        completion(Timeline(entries: Array(entrees), policy: .after(maintenant.addingTimeInterval(6 * 3600))))
    }
}

struct VueProchaine: View {
    let entree: EntreeProchaine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label("Prochaine séance", systemImage: "camera.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color(red: 0.93, green: 0.74, blue: 0.19))
                .lineLimit(1)

            if let seance = entree.seance {
                Text(Self.jour(seance.debut, vu: entree.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(HeureTexte.texte(seance.debut))
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text(seance.ville)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Group {
                    if seance.debut <= entree.date {
                        Text("En cours, fin \(HeureTexte.texte(seance.fin))")
                    } else if let depart = seance.depart {
                        Text("Partir à \(HeureTexte.texte(depart))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Spacer(minLength: 0)
                Text(entree.lisible ? "Aucune séance prévue" : "Ouvrez PP Terrain")
                    .font(.headline)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// « Aujourd'hui », « Demain », puis « jeu. 27 ».
    static func jour(_ date: Date, vu maintenant: Date) -> String {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = HeureTexte.fuseau
        if calendrier.isDate(date, inSameDayAs: maintenant) { return "Aujourd’hui" }
        if let demain = calendrier.date(byAdding: .day, value: 1, to: maintenant), calendrier.isDate(date, inSameDayAs: demain) { return "Demain" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_CA")
        f.timeZone = HeureTexte.fuseau
        f.dateFormat = "EEE d"
        return f.string(from: date)
    }
}
