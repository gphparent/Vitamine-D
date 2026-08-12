import CoreLocation
import SwiftUI

/// Choix du lieu : position réelle, ou lieu fixé à la main pour préparer un
/// déplacement. La latitude étant le premier déterminant de la synthèse, pouvoir
/// simuler une destination a un intérêt concret.
struct LocationPickerView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Suggestion] = []
    @State private var isSearching = false
    @State private var searchError: String?

    struct Suggestion: Identifiable, Equatable {
        let id = UUID()
        let name: String
        let detail: String
        let latitude: Double
        let longitude: Double
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        model.setManualLocation(nil)
                        model.locationService.requestAuthorisation()
                        dismiss()
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Ma position").foregroundStyle(.primary)
                                Text(statusDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "location.fill")
                        }
                    }
                }

                if isSearching {
                    Section { ProgressView().frame(maxWidth: .infinity) }
                }

                if let searchError {
                    Section {
                        Text(searchError)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if !results.isEmpty {
                    Section("Résultats") {
                        ForEach(results) { suggestion in
                            Button {
                                model.setManualLocation(ResolvedLocation(
                                    latitude: suggestion.latitude,
                                    longitude: suggestion.longitude,
                                    altitude: 0,
                                    name: suggestion.name,
                                    isManual: true))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(suggestion.name).foregroundStyle(.primary)
                                    Text(suggestion.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                if let location = model.location {
                    Section("Lieu actuel") {
                        LabeledContent("Nom", value: location.name)
                        LabeledContent("Latitude", value: String(format: "%.4f°", location.latitude))
                        LabeledContent("Longitude", value: String(format: "%.4f°", location.longitude))
                        LabeledContent("Altitude", value: "\(Int(location.altitude)) m")
                    }
                }
            }
            .searchable(text: $query, prompt: "Ville ou lieu")
            .onSubmit(of: .search) { Task { await search() } }
            .navigationTitle("Lieu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    private var statusDescription: String {
        switch model.locationService.status {
        case .authorised:  return "Localisation autorisée"
        case .denied:      return "Refusée — activez-la dans Réglages"
        case .restricted:  return "Restreinte par les réglages de l'appareil"
        case .requesting:  return "Autorisation en cours…"
        case .failed(let message): return message
        case .idle:        return "Toucher pour autoriser"
        }
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        isSearching = true
        searchError = nil
        defer { isSearching = false }

        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(trimmed)
            results = placemarks.compactMap { placemark in
                guard let coordinate = placemark.location?.coordinate else { return nil }
                let name = placemark.locality ?? placemark.name ?? trimmed
                let detail = [placemark.administrativeArea, placemark.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")
                return Suggestion(name: name, detail: detail,
                                  latitude: coordinate.latitude,
                                  longitude: coordinate.longitude)
            }
            if results.isEmpty { searchError = "Aucun lieu trouvé pour « \(trimmed) »." }
        } catch {
            results = []
            searchError = "Recherche impossible : \(error.localizedDescription)"
        }
    }
}

#Preview {
    LocationPickerView().environment(AppModel())
}
