import SwiftUI

/// Le Soleil, l'ozone, et ce qui passe vraiment.
///
/// Toute l'application repose sur un fait que les chiffres énoncent sans le
/// montrer : quand le Soleil descend, les UVB s'éteignent bien plus vite que
/// les UVA. On garde de la lumière, de la chaleur, un indice UV non nul, et
/// plus rien pour la vitamine D. C'est contre-intuitif, et une phrase ne
/// suffit pas à le faire admettre.
///
/// D'où deux molettes et un dessin. On promène l'heure et la saison, on voit
/// les rayons bleus continuer de passer pendant que les violets s'arrêtent dans
/// la couche d'ozone, et le fait devient évident sans qu'on ait à l'expliquer.
///
/// Les rayons ne sont pas décoratifs : leur nombre suit la transmission
/// calculée, et leur point d'arrêt marque là où l'ozone les prend.
struct SunRayView: View {

    @Environment(AppModel.self) private var model

    /// Minute du jour, de 0 à 1440.
    @State private var minuteOfDay: Double = 12 * 60
    /// Quantième de l'année, de 1 à 365.
    @State private var dayOfYear: Double = 172   // solstice d'été

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ScreenTitle(title: "Ce qui passe", subtitle: subtitle)

                Card { sky }

                Card(title: "Quand", systemImage: "slider.horizontal.3") {
                    slider(title: "Heure",
                           value: $minuteOfDay, range: 0...1439,
                           label: Format.minuteOfDay(Int(minuteOfDay)))
                    slider(title: "Jour de l'année",
                           value: $dayOfYear, range: 1...365,
                           label: Format.shortDate(date, in: timeZone))
                }

                Card(title: "Ce qui atteint le sol", systemImage: "chart.bar") {
                    bars
                }

                if let ratio = arrival.uvaPerUVB, elevation > 0 {
                    Card {
                        Text(ratioSentence(ratio))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                explanation
            }
            .padding(16)
        }
        .background(SkyBackground(solarElevation: elevation, cloudCover: 0))
        .navigationTitle("Rayons")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Position du Soleil

    private var timeZone: TimeZone { model.calendar.timeZone }

    /// Date correspondant aux deux molettes, dans l'année en cours.
    private var date: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let year = calendar.component(.year, from: model.now)
        var components = DateComponents()
        components.year = year
        components.day = Int(dayOfYear)
        components.month = 1
        let dayStart = calendar.date(from: components) ?? model.now
        return dayStart.addingTimeInterval(minuteOfDay * 60)
    }

    private var place: ResolvedLocation { model.location ?? .montreal }

    private var elevation: Double {
        SolarCalculator.position(date: date,
                                 latitude: place.latitude,
                                 longitude: place.longitude).elevation
    }

    private var arrival: AtmosphericSpectrum.Arrival {
        AtmosphericSpectrum.arrival(solarElevation: elevation)
    }

    private var relative: AtmosphericSpectrum.Arrival {
        AtmosphericSpectrum.relativeToZenith(solarElevation: elevation)
    }

    private var subtitle: String {
        "\(place.name.uppercased()) · \(Format.degrees(max(0, elevation))) DE HAUTEUR"
    }

    // MARK: - Le ciel et les rayons

    private var sky: some View {
        VStack(spacing: 10) {
            Canvas { context, size in
                draw(in: context, size: size)
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 14) {
                legendDot(Theme.uvaColour, "UVA")
                legendDot(Theme.uvbColour, "UVB")
                Spacer()
                Text(elevation > 0 ? "Soleil à \(Format.degrees(elevation))" : "Soleil couché")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func legendDot(_ colour: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }

    /// Nombre de rayons dessinés par bande. Douze suffisent à lire une
    /// proportion d'un coup d'œil, et restent dessinables sur un téléphone.
    private static let rayCount = 12

    private func draw(in context: GraphicsContext, size: CGSize) {
        let ground = size.height * 0.86
        let ozoneTop = size.height * 0.26
        let ozoneBottom = size.height * 0.40

        // Le sol.
        context.fill(Path(CGRect(x: 0, y: ground, width: size.width,
                                 height: size.height - ground)),
                     with: .color(Color(red: 0.24, green: 0.32, blue: 0.24)))

        // La couche d'ozone, d'autant plus épaisse à traverser que le Soleil
        // est bas — c'est tout le propos, et le dessin doit le montrer.
        context.fill(Path(CGRect(x: 0, y: ozoneTop, width: size.width,
                                 height: ozoneBottom - ozoneTop)),
                     with: .color(Color(red: 0.45, green: 0.55, blue: 0.85).opacity(0.30)))
        context.draw(Text("couche d'ozone").font(.system(size: 9))
            .foregroundStyle(.white.opacity(0.75)),
                     at: CGPoint(x: 52, y: (ozoneTop + ozoneBottom) / 2))

        guard elevation > 0 else {
            context.draw(Text("Le Soleil est sous l'horizon")
                .font(.footnote).foregroundStyle(.white.opacity(0.8)),
                         at: CGPoint(x: size.width / 2, y: size.height / 2))
            return
        }

        // Le Soleil : plus le rayonnement vient de haut, plus il est haut sur
        // le dessin. L'abscisse suit l'heure, du levant au couchant.
        let fraction = min(1, max(0, elevation / 90))
        let sunY = size.height * 0.06 + (ozoneTop - size.height * 0.06) * (1 - fraction)
        let sunX = size.width * (0.16 + 0.68 * min(1, max(0, minuteOfDay / 1440)))
        let sun = CGPoint(x: sunX, y: sunY)

        context.fill(Path(ellipseIn: CGRect(x: sun.x - 15, y: sun.y - 15,
                                            width: 30, height: 30)),
                     with: .color(Theme.vitaminD))

        // La cible au sol : une silhouette, pour que les rayons aient une fin.
        let target = CGPoint(x: size.width * 0.5, y: ground)
        context.fill(Path(ellipseIn: CGRect(x: target.x - 4, y: ground - 26,
                                            width: 8, height: 8)),
                     with: .color(.white.opacity(0.85)))
        context.fill(Path(CGRect(x: target.x - 3, y: ground - 17, width: 6, height: 17)),
                     with: .color(.white.opacity(0.85)))

        drawRays(context, from: sun, to: target, ozoneBottom: ozoneBottom,
                 share: relative.uva, colour: Theme.uvaColour, offset: -14)
        drawRays(context, from: sun, to: target, ozoneBottom: ozoneBottom,
                 share: relative.uvb, colour: Theme.uvbColour, offset: 14)
    }

    /// Trace une famille de rayons, dont la part qui traverse suit la
    /// transmission calculée.
    ///
    /// Les rayons arrêtés s'interrompent dans la couche d'ozone, avec un point
    /// à l'endroit où ils sont absorbés. C'est là que se lit la différence : à
    /// Soleil bas, la colonne violette s'arrête presque entière dans la bande
    /// bleue, la colonne bleue la traverse sans dommage.
    private func drawRays(_ context: GraphicsContext,
                          from sun: CGPoint,
                          to target: CGPoint,
                          ozoneBottom: CGFloat,
                          share: Double,
                          colour: Color,
                          offset: CGFloat) {
        let total = Self.rayCount
        // Au moins un rayon dès qu'il reste quelque chose : annoncer zéro quand
        // il reste un demi pour cent serait aussi faux que d'en dessiner douze.
        let passing = share <= 0 ? 0 : max(1, Int((Double(total) * share).rounded()))

        for index in 0..<total {
            let spread = CGFloat(index - total / 2) * 2.6 + offset
            let start = CGPoint(x: sun.x + spread * 0.5, y: sun.y + 12)
            let end = CGPoint(x: target.x + spread, y: target.y)

            let passes = index < passing
            // Les rayons arrêtés s'échelonnent dans l'épaisseur de la couche
            // plutôt que de finir tous sur la même ligne. L'échelonnement est
            // déterministe : un tirage au hasard ferait frémir le dessin à
            // chaque redessin, c'est-à-dire à chaque frémissement de molette.
            let depth = CGFloat(index % 4) * 3.5
            let stopY = passes ? end.y : ozoneBottom - depth
            let ratio = (stopY - start.y) / max(1, end.y - start.y)
            let stop = CGPoint(x: start.x + (end.x - start.x) * ratio, y: stopY)

            var path = Path()
            path.move(to: start)
            path.addLine(to: passes ? end : stop)
            context.stroke(path, with: .color(colour.opacity(passes ? 0.9 : 0.35)),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

            if !passes {
                context.fill(Path(ellipseIn: CGRect(x: stop.x - 2.5, y: stop.y - 2.5,
                                                    width: 5, height: 5)),
                             with: .color(colour.opacity(0.55)))
            }
        }
    }

    // MARK: - Chiffres

    private var bars: some View {
        VStack(spacing: 12) {
            bar("UVA", relative.uva, Theme.uvaColour,
                "bronzage, vieillissement de la peau")
            bar("UVB", relative.uvb, Theme.uvbColour,
                "vitamine D, coup de soleil")
            bar("Efficacité vitamine D", relative.vitaminD, Theme.vitaminD,
                "UVB pondérés par le spectre d'action")
        }
    }

    private func bar(_ title: String, _ value: Double,
                     _ colour: Color, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Text(percentText(value))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(colour)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(colour)
                        .frame(width: geometry.size.width * min(1, max(0, value)))
                }
            }
            .frame(height: 8)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    /// En deçà d'un pour cent, un arrondi à l'entier afficherait « 0 % » là où
    /// il reste quelque chose. La différence entre peu et rien est justement
    /// ce que cet écran doit faire voir.
    private func percentText(_ value: Double) -> String {
        if value <= 0 { return "0 %" }
        if value < 0.01 { return String(format: "%.2f %%", value * 100) }
        if value < 0.1 { return String(format: "%.1f %%", value * 100) }
        return Format.percent(value)
    }

    private func ratioSentence(_ ratio: Double) -> String {
        let rounded = Int(ratio.rounded())
        var text = "Pour un seul UVB qui arrive, il en arrive \(rounded) d'UVA. "
        if ratio > 100 {
            text += "Le Soleil est si bas que les UVB ont pratiquement disparu, "
            text += "alors que la lumière et la chaleur, elles, sont toujours là. "
            text += "C'est exactement la situation où l'on croit encore faire sa "
            text += "vitamine D sans plus rien produire."
        } else if ratio > 45 {
            text += "Les UVB commencent à manquer : la synthèse tourne au ralenti "
            text += "alors que la peau, elle, continue de vieillir sous les UVA."
        } else {
            text += "C'est le meilleur rapport que l'atmosphère permette. "
            text += "Il ne descend jamais sous une trentaine, même Soleil au zénith."
        }
        return text
    }

    private var explanation: some View {
        Card(title: "Pourquoi cette différence", systemImage: "book") {
            Text("""
            Les deux bandes traversent la même atmosphère, mais l'ozone ne les \
            voit pas de la même façon. Il absorbe mille fois plus fortement à \
            300 nanomètres qu'à 350. Tant que le Soleil est haut, le trajet est \
            court et les deux passent. Quand il descend, le trajet s'allonge — \
            au ras de l'horizon, le rayonnement traverse dix fois plus \
            d'atmosphère qu'au zénith — et cette absorption mille fois plus \
            forte se paie mille fois plus cher.

            Les UVB s'éteignent donc les premiers, et de très loin. C'est aussi \
            pourquoi l'hiver vitaminique existe : à Montréal de novembre à \
            février, le Soleil ne monte jamais assez haut pour que les UVB \
            franchissent la couche.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)

            GoldRule()

            Text("""
            Ce dessin montre un mécanisme, pas une dose. Il suppose un ciel \
            parfaitement dégagé et une colonne d'ozone standard de 300 unités \
            Dobson ; le calcul des durées d'exposition, lui, se fait ailleurs \
            et à partir de l'indice UV réellement prévu.
            """)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func slider(title: String, value: Binding<Double>,
                        range: ClosedRange<Double>, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text(label).font(.subheadline.weight(.medium).monospacedDigit())
            }
            Slider(value: value, in: range)
                .tint(Theme.vitaminD)
        }
    }
}

#Preview {
    NavigationStack { SunRayView().environment(AppModel()) }
}
