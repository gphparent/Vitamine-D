import SwiftUI

/// Saisie ou correction d'une sortie.
///
/// La feuille sert deux cas que rien ne distingue au fond : on a oublié de dire
/// qu'on sortait, ou oublié de dire qu'on rentrait. Dans les deux, il s'agit de
/// déclarer après coup deux heures et une tenue, et de laisser le moteur en
/// tirer le reste.
///
/// Le parti pris est de recalculer en direct. Le total de vitamine D et la part
/// de capital cutané se rafraîchissent pendant qu'on tourne la molette des
/// heures : on voit donc ce qu'on est en train d'inscrire avant de l'inscrire,
/// au lieu de valider à l'aveugle et de découvrir le chiffre dans la liste.
struct SessionEditorView: View {

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// Sortie à corriger. `nil` pour une sortie oubliée qu'on ajoute.
    let existing: SessionRecord?

    @State private var start: Date
    @State private var end: Date
    @State private var exposure: BodyExposure
    @State private var side: BodySide
    @State private var showsDeleteConfirmation = false

    init(existing: SessionRecord? = nil,
         defaultExposure: BodyExposure,
         defaultStart: Date) {
        self.existing = existing
        let begin = existing?.start ?? defaultStart
        _start = State(initialValue: begin)
        _end = State(initialValue: existing?.end ?? begin.addingTimeInterval(20 * 60))
        _exposure = State(initialValue: defaultExposure)
        _side = State(initialValue: .whole)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Heures") {
                    DatePicker("Sortie", selection: $start)
                    DatePicker("Retour", selection: $end, in: start...)
                    LabeledContent("Durée", value: Format.duration(max(0, end.timeIntervalSince(start))))
                }

                Section("Tenue") {
                    Picker("Vêtements", selection: $exposure.preset) {
                        ForEach(ClothingPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    Picker("Étoffe", selection: $exposure.fabric) {
                        ForEach(Fabric.allCases) { fabric in
                            Text(fabric.title).tag(fabric)
                        }
                    }
                    Toggle("Chapeau", isOn: $exposure.wearsHat)
                    Picker("Position", selection: $side) {
                        ForEach(BodySide.allCases) { option in
                            Text(option.shortTitle).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    if let preview {
                        LabeledContent("Vitamine D") {
                            Text(Format.iu(preview.vitaminDIU))
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(Theme.vitaminD)
                        }
                        LabeledContent("Capital cutané") {
                            Text(Format.percent(preview.medFraction) + " de la DEM")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(preview.medFraction > 0.8 ? .red : .secondary)
                        }
                        if let uv = preview.averageUVIndex {
                            LabeledContent("Indice UV moyen",
                                           value: String(format: "%.1f", uv))
                        }
                    } else {
                        Text("Choisissez un lieu pour que le calcul soit possible.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Ce que cela représente")
                } footer: {
                    Text(estimateCaveat)
                }

                if existing != nil {
                    Section {
                        Button("Supprimer cette sortie", role: .destructive) {
                            showsDeleteConfirmation = true
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(existing == nil ? "Sortie oubliée" : "Corriger la sortie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(preview == nil || end <= start)
                }
            }
            .confirmationDialog("Supprimer cette sortie ?",
                                isPresented: $showsDeleteConfirmation,
                                titleVisibility: .visible) {
                Button("Supprimer", role: .destructive) {
                    if let existing { model.deleteRecord(existing) }
                    dismiss()
                }
            } message: {
                Text("La vitamine D et le capital cutané de cette journée seront "
                     + "recalculés sans elle. Santé la retirera aussi.")
            }
            // La molette de fin ne peut pas descendre sous celle de début.
            // Reculer le début sans corriger la fin donnerait sinon une sortie
            // de durée négative, que le moteur refuserait en silence.
            .onChange(of: start) { _, newValue in
                if end <= newValue { end = newValue.addingTimeInterval(20 * 60) }
            }
        }
    }

    /// Recalcul complet à chaque frappe. Le coût est celui d'une intégration sur
    /// quelques dizaines de minutes, imperceptible, et il évite d'avoir à
    /// invalider un cache dont personne ne se souviendrait.
    private var preview: SessionRecord? {
        guard end > start, let place = model.place(for: existing) else { return nil }
        return model.estimateRecord(id: existing?.id ?? UUID(),
                                    start: start, end: end,
                                    exposure: exposure, side: side, at: place)
    }

    /// Ce que la reconstitution ne peut pas savoir, dit là où on le lit.
    private var estimateCaveat: String {
        var text = "Le calcul suit la vraie course du Soleil pendant la sortie, "
        text += "et non une simple multiplication : une heure à midi ne vaut pas "
        text += "deux fois trente minutes."

        if model.calendar.isDate(start, inSameDayAs: model.now) {
            text += "\n\nLa sortie étant d'aujourd'hui, l'indice UV est celui "
            text += "des prévisions, nuages compris."
        } else {
            text += "\n\nLe service météo ne rend pas le passé : pour une "
            text += "journée écoulée, l'indice UV est celui d'un ciel dégagé. "
            text += "S'il faisait couvert, le chiffre est surestimé."
        }

        text += "\n\nLa sortie est comptée sur une peau reposée. Si vous en "
        text += "reconstituez deux dans la même journée, la seconde sera un peu "
        text += "généreuse."
        return text
    }

    private func save() {
        guard let preview else { return }
        model.saveRecord(preview)
        dismiss()
    }
}

#Preview {
    SessionEditorView(defaultExposure: BodyExposure(), defaultStart: Date())
        .environment(AppModel())
}
