import CoreLocation
import MapKit

/// Une route calculée par le iPhone : le temps prévu avec la circulation, et la distance pour le carnet de kilométrage.
struct Trajet: Codable, Hashable {
    let minutes: Int
    let km: Double
}

/// La vraie route d'un point à l'autre, par Apple Plans (Guillaume, 25 nov.) : le serveur, lui, ne fait qu'estimer
/// d'un centre de ville à l'autre. Aucune permission de localisation : on part du point de départ inscrit dans
/// Réglages ou de la séance d'avant, jamais d'où se trouve le téléphone.
@MainActor
final class Itineraires {
    private var lieux: [Int: CLLocationCoordinate2D] = [:]
    private var routes: [String: Trajet] = [:]

    /// Par l'adresse d'abord, qui trouve le numéro civique ; sinon les coordonnées du serveur (souvent le milieu de la rue).
    func coordonnees(de seance: RendezVous) async -> CLLocationCoordinate2D? {
        if let connu = lieux[seance.id] { return connu }

        var trouve: CLLocationCoordinate2D?
        if let adresse = seance.adresse, !adresse.isEmpty {
            let texte = [adresse, seance.ville, "QC", "Canada"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            if let marque = try? await CLGeocoder().geocodeAddressString(texte).first {
                trouve = marque.location?.coordinate
            }
        }
        if trouve == nil, let latitude = seance.latitude, let longitude = seance.longitude {
            trouve = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        if let trouve { lieux[seance.id] = trouve }
        return trouve
    }

    /// Avec l'heure de départ, Plans tient compte de la circulation prévue.
    func trajet(de depart: CLLocationCoordinate2D, vers arrivee: CLLocationCoordinate2D, partant: Date? = nil) async -> Trajet? {
        let cle = String(format: "%.4f,%.4f>%.4f,%.4f@%.0f", depart.latitude, depart.longitude, arrivee.latitude, arrivee.longitude, (partant?.timeIntervalSince1970 ?? 0) / 900)
        if let connu = routes[cle] { return connu }

        let requete = MKDirections.Request()
        requete.source = MKMapItem(placemark: MKPlacemark(coordinate: depart))
        requete.destination = MKMapItem(placemark: MKPlacemark(coordinate: arrivee))
        requete.transportType = .automobile
        if let partant, partant > .now { requete.departureDate = partant }

        guard let eta = try? await MKDirections(request: requete).calculateETA() else { return nil }
        let trajet = Trajet(minutes: Int((eta.expectedTravelTime / 60).rounded(.up)), km: eta.distance / 1000)
        routes[cle] = trajet
        return trajet
    }
}
