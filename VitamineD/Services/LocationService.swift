import CoreLocation
import Foundation
import Observation

/// Lieu où l'utilisateur se trouve, ou qu'il a choisi manuellement.
struct ResolvedLocation: Codable, Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var name: String
    var isManual: Bool

    static let montreal = ResolvedLocation(
        latitude: 45.5019, longitude: -73.5674, altitude: 36,
        name: "Montréal", isManual: true)
}

/// Suivi de la position, avec autorisation et repli manuel.
///
/// La précision demandée est délibérément grossière : à l'échelle du calcul
/// solaire, un kilomètre d'écart déplace le midi solaire de quelques secondes.
/// Rien ne justifie de consommer la batterie pour mieux.
@MainActor
@Observable
final class LocationService: NSObject {

    enum Status: Equatable {
        case idle
        case requesting
        case authorised
        case denied
        case restricted
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var location: ResolvedLocation?

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.distanceFilter = 2000
    }

    var authorisationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestAuthorisation() {
        guard manager.authorizationStatus == .notDetermined else {
            syncStatus()
            return
        }
        status = .requesting
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        switch manager.authorizationStatus {
        case .notDetermined:
            requestAuthorisation()
        case .authorizedAlways, .authorizedWhenInUse:
            status = .authorised
            manager.requestLocation()
        case .denied:
            status = .denied
        case .restricted:
            status = .restricted
        @unknown default:
            status = .idle
        }
    }

    /// Fixe une position manuelle, par exemple pour préparer un voyage.
    func setManual(latitude: Double, longitude: Double, name: String, altitude: Double = 0) {
        location = ResolvedLocation(latitude: latitude, longitude: longitude,
                                    altitude: altitude, name: name, isManual: true)
    }

    private func syncStatus() {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: status = .authorised
        case .denied: status = .denied
        case .restricted: status = .restricted
        case .notDetermined: status = .idle
        @unknown default: status = .idle
        }
    }

    private func reverseGeocode(_ clLocation: CLLocation) {
        geocoder.reverseGeocodeLocation(clLocation) { [weak self] placemarks, _ in
            guard let self, let placemark = placemarks?.first else { return }
            let name = placemark.locality
                ?? placemark.subAdministrativeArea
                ?? placemark.administrativeArea
                ?? placemark.country
                ?? "Position actuelle"
            Task { @MainActor in
                self.location?.name = name
            }
        }
    }
}

/// Les rappels de CoreLocation arrivent hors de l'acteur principal. Chacun
/// extrait immédiatement des valeurs simples — coordonnées, altitude, texte —
/// avant de sauter sur l'acteur principal : ni `CLLocationManager` ni
/// `CLLocation` ne traversent la frontière, ce qui évite de faire voyager des
/// objets non transférables.
extension LocationService: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.syncStatus()
            if case .authorised = self.status { self.manager.requestLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let coordinate = latest.coordinate
        let altitude = max(0, latest.altitude)

        Task { @MainActor in
            // Une position fixée à la main n'est pas écrasée par le GPS :
            // l'utilisateur qui prépare un voyage veut garder sa destination.
            if self.location?.isManual == true { return }
            self.location = ResolvedLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                altitude: altitude,
                name: self.location?.name ?? "Position actuelle",
                isManual: false)
            self.reverseGeocode(CLLocation(latitude: coordinate.latitude,
                                           longitude: coordinate.longitude))
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            // Une erreur ponctuelle ne doit pas effacer une position déjà connue.
            if self.location == nil {
                self.status = .failed(message)
            }
        }
    }
}
