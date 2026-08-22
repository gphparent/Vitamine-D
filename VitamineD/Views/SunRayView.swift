import SwiftUI

/// La course du Soleil, colorée par ce qui traverse.
///
/// Toute l'application repose sur un fait que ses chiffres énoncent sans le
/// montrer : quand le Soleil descend, les UVB s'éteignent bien plus vite que
/// les UVA. Il reste de la lumière, de la chaleur, un indice UV non nul, et
/// plus rien pour la vitamine D.
///
/// ## Pourquoi une coupole plutôt qu'une coupe
///
/// La première version montrait une coupe de l'atmosphère : correcte, et
/// illisible. Elle donnait un instant isolé, sans dire où il tombait dans la
/// journée. La coupole donne l'arc entier d'un coup, et l'on s'y repère comme
/// on se repère dans le ciel.
///
/// Deux rubans suivent cet arc : les UVA à l'extérieur, les UVB à l'intérieur,
/// chaque segment porté à l'opacité de sa transmission. Confondus près du
/// zénith, ils s'écartent en descendant. C'est la thèse de l'application,
/// dessinée plutôt qu'affirmée.
///
/// ## Pourquoi de biais
///
/// Vu dans l'axe du méridien, l'arc se referme sur lui-même et sa hauteur
/// devient impossible à estimer : le point le plus haut se confond avec le bord
/// lointain de l'horizon. La caméra est donc placée à quarante degrés de côté,
/// et un rapporteur se dresse dans le plan du midi — le seul endroit de la
/// coupole où un angle soit mesurable à l'œil.
struct SunRayView: View {

    @Environment(AppModel.self) private var model

    @State private var minuteOfDay: Double = 12 * 60
    @State private var dayOfYear: Double = 172

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card { dome }
                readout
                verdict
                explanation
                MedicalNotice()
            }
            .padding(16)
        }
        .background(SkyBackground(solarElevation: elevation, cloudCover: 0))
        // Les molettes restent au bas de l'écran quoi qu'on fasse défiler.
        // Elles sont l'instrument : les laisser remonter avec le contenu
        // obligeait à revenir les chercher après chaque lecture, et cassait
        // le va-et-vient entre le geste et son effet.
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle("Les rayons")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Position

    private var place: ResolvedLocation { model.location ?? .montreal }

    private var date: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.calendar.timeZone
        let year = calendar.component(.year, from: model.now)
        var components = DateComponents()
        components.year = year; components.month = 1; components.day = Int(dayOfYear)
        let start = calendar.date(from: components) ?? model.now
        return start.addingTimeInterval(minuteOfDay * 60)
    }

    private var declination: Double {
        SolarCalculator.position(date: date,
                                 latitude: place.latitude,
                                 longitude: place.longitude).declination
    }

    /// Hauteur du Soleil à une minute donnée, en heure solaire vraie.
    ///
    /// L'heure solaire plutôt que l'heure légale : la molette porte alors sur
    /// la géométrie et non sur un fuseau, et midi tombe toujours à la
    /// culmination. C'est ce qu'on veut d'un instrument.
    private func elevation(atMinute minute: Double) -> Double {
        let vector = SolarGeometry.vector(declination: declination,
                                          hourAngle: minute / 4 - 180,
                                          latitude: place.latitude)
        return asin(max(-1, min(1, vector.up))) / .pi * 180
    }

    private var elevation: Double { elevation(atMinute: minuteOfDay) }

    private var arrival: AtmosphericSpectrum.Arrival {
        AtmosphericSpectrum.relativeToZenith(solarElevation: max(0, elevation))
    }

    // MARK: - Coupole

    private var dome: some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                SkyDome(latitude: place.latitude,
                        declination: declination,
                        minuteOfDay: minuteOfDay)
                    .draw(in: context, size: size)
            }
            .frame(height: 300)

            HStack(spacing: 14) {
                bandKey(Theme.uvaColour, "UVA")
                bandKey(Theme.uvbColour, "UVB")
                Spacer()
                Text(elevation > 0
                     ? "Soleil à \(Format.degrees(elevation))"
                     : "Soleil couché")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
    }

    private func bandKey(_ colour: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(colour).frame(width: 16, height: 4)
            Text(text).foregroundStyle(.secondary)
        }
    }

    // MARK: - Chiffres

    private var readout: some View {
        HStack(spacing: 12) {
            MetricTile(label: "UVA", value: percent(arrival.uva),
                       detail: "bronzage, vieillissement", tint: Theme.uvaColour)
            MetricTile(label: "UVB", value: percent(arrival.uvb),
                       detail: "vitamine D, coup de soleil", tint: Theme.uvbColour)
            MetricTile(label: "Vitamine D", value: percent(arrival.vitaminD),
                       detail: "UVB pondérés", tint: Theme.vitaminD)
        }
    }

    /// Sous un pour cent, un arrondi à l'entier afficherait « 0 % » là où il
    /// reste quelque chose. La différence entre peu et rien est exactement ce
    /// que cet écran doit faire voir.
    private func percent(_ value: Double) -> String {
        guard elevation > 0, value > 0 else { return "—" }
        if value < 0.001 { return String(format: "%.2f %%", value * 100) }
        if value < 0.01 { return String(format: "%.1f %%", value * 100) }
        return Format.percent(value)
    }

    @ViewBuilder
    private var verdict: some View {
        if elevation > 0,
           let ratio = AtmosphericSpectrum
            .arrival(solarElevation: elevation).uvaPerUVB {
            Card {
                Text(sentence(ratio))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sentence(_ ratio: Double) -> String {
        var text = "Pour un seul UVB qui arrive, il en arrive "
            + "\(Int(ratio.rounded())) d'UVA. "
        if ratio > 150 {
            text += "Les UVB ont pratiquement disparu, alors que la lumière et "
                + "la chaleur sont toujours là. C'est exactement la situation où "
                + "l'on croit encore faire sa vitamine D."
        } else if ratio > 45 {
            text += "Les UVB commencent à manquer : la synthèse tourne au ralenti "
                + "pendant que la peau continue de vieillir sous les UVA."
        } else {
            text += "C'est le meilleur rapport que l'atmosphère permette — il ne "
                + "descend jamais sous une trentaine, même Soleil au zénith."
        }
        return text
    }

    private var explanation: some View {
        Card(title: "Pourquoi les deux traits se séparent", systemImage: "book") {
            Text("""
            Les deux bandes traversent la même atmosphère, mais l'ozone ne les \
            voit pas de la même façon : il absorbe cinq cents fois plus \
            fortement à 300 nanomètres qu'à 350. Tant que le Soleil est haut, le \
            trajet est court et les deux passent. Quand il descend, le trajet \
            s'allonge — au ras de l'horizon, le rayonnement traverse dix fois \
            plus d'atmosphère qu'au zénith — et cette absorption cinq cents fois \
            plus forte se paie cinq cents fois plus cher.

            Le trait d'or à 45° est la règle de l'ombre. Une journée dont la \
            culmination reste loin dessous ne produira pas grand-chose, et c'est \
            précisément ce qu'est un hiver vitaminique.
            """)
            .font(.footnote)
            .foregroundStyle(.secondary)

            GoldRule()

            Text("""
            Ce dessin montre un mécanisme, pas une dose. Il suppose un ciel \
            parfaitement dégagé et une colonne d'ozone standard ; les durées \
            d'exposition, elles, se calculent à partir de l'indice UV réellement \
            prévu.
            """)
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Molettes

    private var controls: some View {
        VStack(spacing: 10) {
            slider("Heure solaire", $minuteOfDay, 0...1439,
                   Format.minuteOfDay(Int(minuteOfDay)))
            slider("Jour de l'année", $dayOfYear, 1...365,
                   Format.shortDate(date, in: model.calendar.timeZone))
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func slider(_ title: String, _ value: Binding<Double>,
                        _ range: ClosedRange<Double>, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(label)
                    .font(.caption.weight(.medium).monospacedDigit())
            }
            Slider(value: value, in: range)
                .tint(Theme.vitaminD)
        }
    }
}

#Preview {
    NavigationStack { SunRayView().environment(AppModel()) }
}
