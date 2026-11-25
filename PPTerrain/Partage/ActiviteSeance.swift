import ActivityKit
import Foundation

/// La tuile de l'écran verrouillé et de l'île dynamique (Guillaume, 25 nov.) : la prochaine séance de la journée,
/// l'heure où partir et le compte à rebours. Compilée dans l'appli et dans l'extension qui la dessine.
/// L'écran verrouillé se lit par-dessus l'épaule : la ville et l'heure seulement, jamais l'adresse ni le client.
struct ActiviteSeance: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Etape: String, Codable, Hashable {
            /// Pas encore l'heure de partir : le compte à rebours va jusqu'au départ.
            case partir
            /// Parti, ou l'heure est passée : le compte à rebours va jusqu'à la séance.
            case enRoute
            /// « Arrivé » touché : le compte à rebours va jusqu'à la fin prévue.
            case surPlace
        }

        var etape: Etape
        var ville: String
        var heureSeance: Date
        var depart: Date?
        var finPrevue: Date?
        var routeMinutes: Int?
        /// Les séances qui suivent celle-ci aujourd'hui.
        var ensuite: Int

        /// Le moment vers lequel compte la tuile.
        var cible: Date {
            switch etape {
            case .partir: return depart ?? heureSeance
            case .enRoute: return heureSeance
            case .surPlace: return finPrevue ?? heureSeance.addingTimeInterval(3600)
            }
        }

        var titre: String {
            switch etape {
            case .partir: return "Départ à \(HeureTexte.texte(depart ?? heureSeance))"
            case .enRoute: return "Séance à \(HeureTexte.texte(heureSeance))"
            case .surPlace: return "Sur place, fin prévue \(HeureTexte.texte(finPrevue ?? heureSeance))"
            }
        }

        var detail: String {
            var morceaux = [ville]
            if etape != .surPlace, let routeMinutes { morceaux.append("\(routeMinutes) min de route") }
            if ensuite > 0 { morceaux.append(ensuite == 1 ? "1 autre séance ensuite" : "\(ensuite) autres séances ensuite") }
            return morceaux.joined(separator: " · ")
        }

        var icone: String {
            switch etape {
            case .partir: return "clock"
            case .enRoute: return "car.fill"
            case .surPlace: return "camera.fill"
            }
        }
    }

    var jour: Date
}

enum HeureTexte {
    static let fuseau = TimeZone(identifier: "America/Toronto")!

    /// « 10 h 30 »
    static func texte(_ date: Date) -> String {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = fuseau
        let c = calendrier.dateComponents([.hour, .minute], from: date)
        return String(format: "%d h %02d", c.hour ?? 0, c.minute ?? 0)
    }
}
