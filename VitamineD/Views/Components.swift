import SwiftUI

/// Filet d'or, en remplacement du séparateur gris à l'intérieur d'une carte.
///
/// L'or s'éteint vers la droite plutôt que de traverser toute la largeur : un
/// trait plein ferait règle de tableau, un filet qui s'efface fait réglure de
/// manuscrit.
struct GoldRule: View {
    var body: some View {
        Rectangle()
            .fill(Theme.goldRule)
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}

/// Carte générique, fond et coins arrondis cohérents.
///
/// La tête de carte est en capitales incisées d'or sur filet, et non en gris
/// semi-gras. C'est l'un des quatre gestes du registre héraldique : l'or porte
/// l'inscription, jamais la donnée — laquelle garde ses couleurs
/// conventionnelles juste en dessous.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    /// Variante sobre, pour les feuilles denses où le registre héraldique
    /// tomberait mal.
    var isPlain: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title)
                        .font(isPlain ? .subheadline.weight(.semibold) : .caption)
                        .tracking(isPlain ? 0 : 1.6)
                        .textCase(isPlain ? nil : .uppercase)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .labelStyle(.titleAndIcon)
                .foregroundStyle(isPlain ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.goldDark))

                if !isPlain { GoldRule() }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.cardEdge, lineWidth: 1)
        )
    }
}

/// Fond de ciel, choisi par la hauteur du Soleil.
///
/// Ce n'est pas une ambiance : la phase suit la grandeur qui décide du
/// rendement UVB, et deux de ses bornes sont celles des bandes de rendement.
/// Quand le fond vire au bleu profond, c'est que la synthèse est finie.
struct SkyBackground: View {
    let solarElevation: Double
    var cloudCover: Double = 0

    var body: some View {
        LinearGradient(colors: Theme.skyStops(solarElevation: solarElevation),
                       startPoint: .top, endPoint: .bottom)
            .overlay(Theme.skyVeil(cloudCover: cloudCover))
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.6), value: solarElevation)
    }
}

/// Titre d'écran : nom en capitales incisées, lieu et date en dessous.
///
/// La police d'affichage n'entre que là. Le système en fournit une taillée pour
/// l'écran — le serif d'Apple — ce qui évite d'embarquer une fonte et conserve
/// la mise à l'échelle dynamique, que toute police livrée avec l'application
/// perdrait pour les tailles d'accessibilité.
struct ScreenTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 30, weight: .regular, design: .serif))
                .foregroundStyle(Theme.onSky)
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .tracking(2.2)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.goldLight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// Petite tuile chiffrée.
struct MetricTile: View {
    let label: String
    let value: String
    var detail: String?
    var tint: Color = .primary
    /// Terme à expliquer, si l'intitulé ne se suffit pas à lui-même.
    var glossary: GlossaryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let glossary { GlossaryButton(entry: glossary) }
            }
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Jauge circulaire d'indice UV.
struct UVGauge: View {
    let uvIndex: Double
    let clearSkyIndex: Double
    /// Anneau d'or autour du cadran, comme le nimbe d'une icône. Un seul par
    /// écran, jamais sur un cadran secondaire.
    var hasNimbus: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 10)

            // Trait fin : ce que l'indice vaudrait sans nuages. L'écart entre les
            // deux arcs rend visible ce que les nuages retirent réellement, qui
            // est bien moins que ce que l'œil suppose.
            Circle()
                .trim(from: 0, to: min(1, clearSkyIndex / 12))
                .stroke(Color.secondary.opacity(0.35), style: .init(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .trim(from: 0, to: min(1, uvIndex / 12))
                .stroke(Theme.uvColour(uvIndex), style: .init(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: uvIndex)

            VStack(spacing: 0) {
                Text(String(format: "%.1f", uvIndex))
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text("UV")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 108, height: 108)
        .padding(hasNimbus ? 5 : 0)
        .overlay {
            if hasNimbus {
                Circle().strokeBorder(Theme.gold, lineWidth: 1)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Indice UV")
        .accessibilityValue(String(format: "%.1f, %@", uvIndex, Theme.uvLabel(uvIndex)))
    }
}

/// Barre de progression à deux têtes : vitamine D gagnée d'un côté, capital
/// cutané consommé de l'autre. Les voir ensemble est tout l'intérêt : la
/// question n'est jamais « combien de soleil », mais « combien de vitamine D
/// pour combien de peau ».
struct DualProgressBar: View {
    let vitaminDFraction: Double
    let medFraction: Double
    let burnLevel: SessionProgress.BurnLevel

    var body: some View {
        VStack(spacing: 10) {
            bar(label: "Vitamine D",
                value: vitaminDFraction,
                tint: Theme.vitaminD,
                trailing: Format.percent(min(1, vitaminDFraction)))

            bar(label: "Capital cutané",
                value: medFraction,
                tint: Theme.burnColour(burnLevel),
                trailing: Format.percent(min(1, medFraction)) + " de la DEM",
                glossary: .skinCapital)
        }
    }

    private func bar(label: String, value: Double, tint: Color, trailing: String,
                     glossary: GlossaryEntry? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 3) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                if let glossary { GlossaryButton(entry: glossary) }
                Spacer()
                Text(trailing).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: 8)
        }
    }
}

/// Bandeau d'avertissement.
struct NoticeBanner: View {
    enum Kind { case info, warning, critical }

    let kind: Kind
    let title: String
    let message: String

    private var tint: Color {
        switch kind {
        case .info:     return .blue
        case .warning:  return .orange
        case .critical: return .red
        }
    }

    private var symbol: String {
        switch kind {
        case .info:     return "info.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // Fond de carte, et non une simple teinte : posé sur un ciel de nuit,
        // un aplat à 10 % laisserait le texte illisible.
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.45), lineWidth: 1)
        )
    }
}

/// Décompte avant la plage de meilleur rendement, et barre du jour.
///
/// C'est le seul chiffre qui décide d'une sortie : tout le reste de l'écran
/// explique, celui-ci commande. D'où sa place en haut et sa taille.
///
/// La plage est définie sur la seule hauteur du Soleil — au-delà de 45°, votre
/// ombre est plus courte que vous. Elle ne dépend donc pas de la météo, et le
/// décompte ne change pas d'une prévision à l'autre.
struct OptimalWindowCountdown: View {

    let plan: DayPlan
    let now: Date

    private enum Phase {
        case ahead(DateInterval, TimeInterval)
        case open(DateInterval, TimeInterval)
        case past(DateInterval)
        case absent
    }

    private var phase: Phase {
        guard let band = plan.optimalBand else { return .absent }
        if now < band.start { return .ahead(band, band.start.timeIntervalSince(now)) }
        if now < band.end { return .open(band, band.end.timeIntervalSince(now)) }
        return .past(band)
    }

    private struct Copy {
        let label: String
        let value: String
        let detail: String
        let tint: Color
        let symbol: String
    }

    private var copy: Copy {
        let zone = plan.timeZone
        switch phase {
        case let .ahead(band, delay):
            return Copy(label: "Fenêtre optimale",
                        value: "dans " + Format.duration(delay),
                        detail: Format.interval(band, in: zone)
                            + " · le Soleil passe alors au-dessus de 45°",
                        tint: Theme.vitaminD,
                        symbol: "hourglass")
        case let .open(band, left):
            return Copy(label: "Fenêtre optimale ouverte",
                        value: "encore " + Format.duration(left),
                        detail: "Jusqu'à " + Format.time(band.end, in: zone)
                            + " · votre ombre est plus courte que vous",
                        tint: Theme.vitaminD,
                        symbol: "sun.max.fill")
        case let .past(band):
            return Copy(label: "Fenêtre optimale passée",
                        value: Format.interval(band, in: zone),
                        detail: "Le Soleil est redescendu sous 45°. Il y repassera "
                            + "demain à peu près à la même heure.",
                        tint: .secondary,
                        symbol: "sunset")
        case .absent:
            return Copy(label: "Pas de fenêtre optimale aujourd'hui",
                        value: "Soleil à " + Format.degrees(plan.peakElevation) + " au plus haut",
                        detail: "Il faut 45° pour que le rendement soit à son meilleur. "
                            + "Une sortie reste utile si le Soleil dépasse "
                            + Format.degrees(UVEngine.vitaminDWinterElevation) + ".",
                        tint: .secondary,
                        symbol: "sun.horizon")
        }
    }

    /// Rendu sans habillage de carte : le décompte se place à l'intérieur de la
    /// carte d'état, au-dessus de la jauge, plutôt que d'occuper une carte à
    /// lui seul. Les deux disent la même chose à deux échelles — ce qu'il en
    /// est maintenant, et ce qui vient — et se lisent mieux ensemble.
    var body: some View {
        let copy = self.copy

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: copy.symbol)
                    .font(.title2)
                    .foregroundStyle(copy.tint)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(copy.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(copy.value)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(copy.tint)
                        .contentTransition(.numericText())
                    Text(copy.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            dayBar
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(copy.label)
        .accessibilityValue(copy.value)
    }

    /// La journée d'un lever à l'autre, avec la plage optimale en or et
    /// l'instant présent en repère.
    @ViewBuilder
    private var dayBar: some View {
        if let daylight {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))

                    if let band = plan.optimalBand {
                        Capsule()
                            .fill(Theme.vitaminD.opacity(0.55))
                            .frame(width: bandWidth(band, across: geometry.size.width))
                            .offset(x: offset(of: band.start, across: geometry.size.width))
                    }

                    Capsule()
                        .fill(Color.primary)
                        .frame(width: 2)
                        .offset(x: offset(of: now, across: geometry.size.width) - 1)
                }
            }
            .frame(height: 8)

            HStack {
                Text(Format.time(daylight.start, in: plan.timeZone))
                Spacer()
                Text(Format.time(daylight.end, in: plan.timeZone))
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.tertiary)
        }
    }

    /// Du lever au coucher, quand les deux existent.
    private var daylight: DateInterval? {
        guard let sunrise = plan.sunrise,
              let sunset = plan.sunset,
              sunset > sunrise else { return nil }
        return DateInterval(start: sunrise, end: sunset)
    }

    /// Position horizontale d'un instant sur la barre du jour.
    private func offset(of date: Date, across width: CGFloat) -> CGFloat {
        guard let daylight, daylight.duration > 0 else { return 0 }
        let ratio = date.timeIntervalSince(daylight.start) / daylight.duration
        return width * CGFloat(min(1, max(0, ratio)))
    }

    private func bandWidth(_ band: DateInterval, across width: CGFloat) -> CGFloat {
        let start = offset(of: band.start, across: width)
        let end = offset(of: band.end, across: width)
        return max(2, end - start)
    }
}

/// Carte d'un créneau recommandé.
struct RecommendationCard: View {
    let recommendation: SessionRecommendation
    let timeZone: TimeZone
    var isPrimary: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Les créneaux sont présentés dans l'ordre de la journée : le meilleur
            // n'est plus forcément le premier, il lui faut donc une marque.
            if isPrimary {
                Text("Meilleur créneau")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Theme.vitaminD)
                    .textCase(.uppercase)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(Format.time(recommendation.start, in: timeZone))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text("pendant \(recommendation.minutes) min")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if recommendation.reachesGoal {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.vitaminD)
                }
            }

            HStack(spacing: 16) {
                MetricTile(label: "Vitamine D",
                           value: Format.iu(recommendation.expectedIU),
                           tint: Theme.vitaminD)
                MetricTile(label: "Capital cutané",
                           value: Format.percent(recommendation.medFraction),
                           detail: "de la DEM",
                           glossary: .skinCapital)
                MetricTile(label: "UV moyen",
                           value: String(format: "%.1f", recommendation.averageUVIndex),
                           tint: Theme.uvColour(recommendation.averageUVIndex))
            }

            Text(recommendation.limitingFactor.explanation)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isPrimary ? Theme.vitaminD.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isPrimary ? Theme.vitaminD.opacity(0.4) : .clear, lineWidth: 1)
        )
    }
}
