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
                    Text("""
                    La surface de peau découverte entre directement dans le calcul : \
                    doubler la surface exposée divise par deux le temps nécessaire.
                    """)
                }

                Section {
                    ForEach(Fabric.allCases) { fabric in
                        fabricRow(fabric)
                    }
                } header: {
                    Text("Étoffe")
                } footer: {
                    Text("""
                    La peau couverte ne reçoit pas rien, et les vêtements protègent \
                    bien moins qu'on ne le croit. Un jean ou une laine serrée arrêtent \
                    presque tout. Mais le t-shirt de coton blanc que tout le monde \
                    porte l'été est mesuré entre UPF 3 et UPF 7 : il laisse passer \
                    entre un septième et un tiers du rayonnement, très loin de l'UPF 30 \
                    que recommande l'OMS. Mouillé ou distendu, il ne protège \
                    pratiquement plus.

                    Comme la peau couverte représente presque tout le corps, ce filet \
                    compte : sous des manches longues, un coton d'été apporte les deux \
                    tiers de ce que donnent le visage, le cou et les mains réunis, et \
                    un t-shirt blanc en apporte près du double. C'est pourquoi changer \
                    d'étoffe déplace la durée conseillée sans qu'un seul centimètre de \
                    peau n'ait été découvert.

                    L'étoffe n'agit que sur la vitamine D. L'heure du coup de soleil \
                    reste calculée sur la peau nue, qui rougira la première quoi \
                    qu'on porte ailleurs.
                    """)
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
                                        .foregroundStyle(.secondary)
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
                    HStack {
                        Text("Surface équivalente")
                        Spacer()
                        Text(Format.percent(exposure.effectiveExposedFraction))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if exposure.sunscreenSPF > 1 {
                        HStack {
                            Text("UV atteignant la peau nue")
                            Spacer()
                            Text(Format.percent(exposure.sunscreenTransmission))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                } footer: {
                    Text("""
                    La surface équivalente est celle qui entre dans le calcul de la \
                    vitamine D : la peau nue, plus la peau couverte comptée à hauteur \
                    de ce que l'étoffe laisse passer.
                    """)
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
            // L'étoffe suit la tenue : passer au manteau sans repasser au tissu
            // dense laisserait le calcul tourner sur un coton d'été.
            exposure.fabric = preset.suggestedFabric
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
                    .foregroundStyle(.secondary)
                if exposure.preset == preset {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Theme.vitaminD)
                }
            }
        }
    }

    private func fabricRow(_ fabric: Fabric) -> some View {
        Button {
            exposure.fabric = fabric
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(fabric.title)
                        .foregroundStyle(.primary)
                    Text(fabric.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("UPF \(fabric.upf)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if exposure.fabric == fabric {
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
