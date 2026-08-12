import SwiftUI

/// Choix de la tenue et de la protection solaire.
struct ClothingView: View {

    @Binding var exposure: BodyExposure
    @Environment(\.dismiss) private var dismiss

    private let spfOptions = [1, 15, 30, 50]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ClothingPreset.allCases.filter { $0 != .custom }) { preset in
                        presetRow(preset)
                    }
                    presetRow(.custom)
                } header: {
                    Text("Tenue")
                } footer: {
                    Text("La surface de peau découverte entre directement dans le calcul : "
                         + "doubler la surface exposée divise par deux le temps nécessaire.")
                }

                if exposure.preset == .custom {
                    Section("Régions découvertes") {
                        ForEach(BodyRegion.ordered) { region in
                            Toggle(isOn: binding(for: region)) {
                                HStack {
                                    Text(region.title)
                                    Spacer()
                                    Text(String(format: "%.1f %%",
                                                region.rawPercentage / BodyExposure.totalRawPercentage * 100))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }

                Section {
                    Toggle("Chapeau ou casquette", isOn: $exposure.wearsHat)

                    Picker("Crème solaire", selection: $exposure.sunscreenSPF) {
                        ForEach(spfOptions, id: \.self) { spf in
                            Text(spf == 1 ? "Aucune" : "IP \(spf)").tag(spf)
                        }
                    }
                } header: {
                    Text("Protection")
                } footer: {
                    Text("""
                    L'indice affiché sur le tube est mesuré à 2 mg/cm², une épaisseur que \
                    presque personne n'applique. L'application retient donc une protection \
                    effective proche de la racine carrée de l'indice nominal — un IP 30 mal \
                    étalé protège comme un IP 5. Mieux vaut sous-estimer sa protection que \
                    l'inverse.
                    """)
                }

                Section {
                    HStack {
                        Text("Peau exposée")
                        Spacer()
                        Text(String(format: "%.0f %%", exposure.exposedBodyPercentage))
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.vitaminD)
                    }
                    if exposure.sunscreenSPF > 1 {
                        HStack {
                            Text("UV atteignant la peau")
                            Spacer()
                            Text(Format.percent(exposure.sunscreenTransmission))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Tenue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                }
            }
        }
    }

    private func presetRow(_ preset: ClothingPreset) -> some View {
        Button {
            // Passer en mode personnalisé part de la tenue courante plutôt que
            // d'une sélection vide : on ajuste presque toujours à la marge.
            if preset == .custom {
                exposure.customRegions = exposure.preset == .custom
                    ? exposure.customRegions
                    : exposure.preset.exposedRegions
            }
            exposure.preset = preset
        } label: {
            HStack {
                Image(systemName: preset.symbolName)
                    .frame(width: 26)
                    .foregroundStyle(exposure.preset == preset ? Theme.vitaminD : .secondary)
                Text(preset.title)
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "%.0f %%",
                            BodyExposure.normalisedFraction(
                                for: preset == .custom ? exposure.customRegions : preset.exposedRegions) * 100))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
                if exposure.preset == preset {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.vitaminD)
                }
            }
        }
    }

    private func binding(for region: BodyRegion) -> Binding<Bool> {
        Binding(
            get: { exposure.customRegions.contains(region) },
            set: { isOn in
                if isOn { exposure.customRegions.insert(region) }
                else { exposure.customRegions.remove(region) }
            }
        )
    }
}

#Preview {
    ClothingView(exposure: .constant(BodyExposure()))
}
