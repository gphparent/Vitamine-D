import SwiftUI

/// Les lampes qu'on allume contre l'hiver.
///
/// L'écran existe à cause d'un malentendu répandu : beaucoup de gens achètent
/// une lampe rouge en croyant compenser le Soleil qui manque, donc la vitamine
/// D. Le refuser sèchement n'aiderait personne — la question derrière est
/// bonne, l'hiver est réel. Ce qu'il faut, c'est démêler.
///
/// D'où l'ordre des cartes, qui n'est pas alphabétique mais celui de la force
/// des preuves : la luminothérapie d'abord, dont l'effet hivernal est établi ;
/// le rouge du soir ensuite, dont le raisonnement tient ; la
/// photobiomodulation en dernier, dont le mécanisme existe mais pas la
/// posologie. Et l'avertissement en tête, avant tout minuteur : aucune de ces
/// lampes ne fait de vitamine D.
struct LightTherapyView: View {

    @Environment(AppModel.self) private var model
    @State private var running: LightTherapy.Modality?
    @State private var startedAt: Date?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenTitle(title: "Lumière artificielle",
                            subtitle: "CE QUE LES LAMPES FONT, ET CE QU'ELLES NE FONT PAS")

                notice

                ForEach(ordered) { modality in
                    card(modality)
                }

                comparison
                MedicalNotice()
            }
            .padding(16)
        }
        .background(SkyBackground(
            solarElevation: model.solarPosition?.elevation ?? -90,
            cloudCover: model.currentConditions?.cloudCover ?? 0))
        .navigationTitle("Lumière")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// De la preuve la plus solide à la plus mince. Un catalogue rangé
    /// autrement laisserait croire que les trois se valent.
    private var ordered: [LightTherapy.Modality] {
        LightTherapy.Modality.allCases.sorted { $0.evidence < $1.evidence }
    }

    private var notice: some View {
        NoticeBanner(
            kind: .warning,
            title: "Aucune de ces lampes ne fait de vitamine D",
            message: "La synthèse cutanée demande des UVB autour de 298 nm. Le "
                + "rouge est à 660 nm, le proche infrarouge à 850 : plus de deux "
                + "cents nanomètres d'écart, et le 7-déhydrocholestérol n'absorbe "
                + "rien dans le rouge. Contre un hiver vitaminique il reste "
                + "l'alimentation et la supplémentation. Ce qui suit traite "
                + "d'autre chose — l'humeur, l'horloge interne, la peau — qui "
                + "sont de vraies questions d'hiver.")
    }

    // MARK: - Une modalité

    private func card(_ modality: LightTherapy.Modality) -> some View {
        Card(title: modality.title, systemImage: modality.symbolName) {
            HStack(alignment: .firstTextBaseline) {
                Text(modality.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                EvidenceTag(strength: modality.evidence)
            }

            HStack(spacing: 10) {
                Label(modality.purpose, systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(Theme.vitaminD)
                Spacer()
            }

            GoldRule()

            timer(modality)

            GoldRule()

            Text(modality.rationale)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Label(modality.caveat, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Minuteur

    /// Le minuteur est calculé, jamais décrémenté.
    ///
    /// Un compteur qui tourne en mémoire s'arrête dès que l'application passe
    /// en arrière-plan — c'est-à-dire précisément ce qu'on fait pendant une
    /// séance de trente minutes. On garde donc l'instant de départ et on lit
    /// l'écart, exactement comme les sorties au Soleil.
    private func timer(_ modality: LightTherapy.Modality) -> some View {
        let isRunning = running == modality
        let elapsed = isRunning ? model.now.timeIntervalSince(startedAt ?? model.now) : 0
        let remaining = max(0, modality.duration - elapsed)
        let done = isRunning && remaining <= 0

        return VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(done ? "Séance terminée"
                          : (isRunning ? Format.stopwatch(remaining) : Format.duration(modality.duration)))
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(done ? Theme.vitaminD : .primary)
                    .contentTransition(.numericText())
                Spacer()
                Text(suggestedTime(modality))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }

            if isRunning {
                ProgressView(value: min(1, elapsed / modality.duration))
                    .tint(Theme.vitaminD)
            }

            Button {
                if isRunning {
                    running = nil; startedAt = nil
                } else {
                    running = modality; startedAt = model.now
                }
            } label: {
                Label(isRunning ? "Arrêter" : "Démarrer la séance",
                      systemImage: isRunning ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRunning ? .secondary : Theme.vitaminD)
        }
    }

    /// Heure conseillée, calée sur le réveil et le coucher déclarés au profil.
    private func suggestedTime(_ modality: LightTherapy.Modality) -> String {
        let bed = (model.profile.wakeMinuteOfDay
            - Int(model.profile.sleepHours * 60) + 1440) % 1440
        let minute = modality.suggestedStart(wakeMinute: model.profile.wakeMinuteOfDay,
                                             bedMinute: bed) % 1440
        return "conseillé vers\n" + Format.minuteOfDay(minute)
    }

    // MARK: - Ce que vaut une lampe

    private var comparison: some View {
        Card(title: "Ce que vaut une lampe", systemImage: "ruler") {
            VStack(spacing: 8) {
                luxRow("Intérieur ordinaire", LightTherapy.indoorLux, .secondary)
                luxRow("Lampe de luminothérapie", LightTherapy.brightLightLux, Theme.vitaminD)
                luxRow("Dehors, ciel couvert", LightTherapy.overcastDaylightLux, Theme.vitaminD)
                luxRow("Dehors, ciel dégagé", LightTherapy.clearDaylightLux, Theme.gold)
            }

            GoldRule()

            Text("Une lampe de luminothérapie dépasse d'environ "
                 + "\(Int(LightTherapy.indoorRatio)) fois l'éclairage d'un salon, "
                 + "et fait jeu égal avec un ciel d'hiver couvert. Un ciel dégagé "
                 + "la dépasse de cinq fois. La lampe remplace donc une sortie "
                 + "qu'on n'a pas faite — elle ne la surpasse jamais.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Barre logarithmique : de 300 à 50 000 lux, une échelle linéaire écraserait
    /// les trois premières valeurs contre zéro et ne montrerait plus rien.
    private func luxRow(_ label: String, _ lux: Double, _ tint: Color) -> some View {
        let fraction = log10(lux / 100) / log10(LightTherapy.clearDaylightLux / 100)

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.caption)
                Spacer()
                Text("\(Int(lux)) lux")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(tint)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * min(1, max(0.02, fraction)))
                }
            }
            .frame(height: 7)
        }
    }
}

/// Pastille de force de preuve, reprise du même vocabulaire que la routine de
/// sommeil : deux échelles différentes dans une même application seraient une
/// invitation à ne croire ni l'une ni l'autre.
struct EvidenceTag: View {
    let strength: EvidenceStrength

    var body: some View {
        Text(strength.title)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(tint.opacity(0.16)))
            .foregroundStyle(tint)
    }

    private var tint: Color {
        switch strength {
        case .solid:    return Color(red: 0.30, green: 0.66, blue: 0.42)
        case .moderate: return Color(red: 0.95, green: 0.72, blue: 0.20)
        case .thin:     return .secondary
        }
    }
}

#Preview {
    NavigationStack { LightTherapyView().environment(AppModel()) }
}
