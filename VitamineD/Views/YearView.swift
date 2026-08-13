import Charts
import SwiftUI

/// L'année entière au lieu courant.
///
/// La vue quotidienne ne peut pas dire ceci : qu'à Montréal, quatre mois de
/// l'année ne produisent rien, quelle que soit l'heure et quelle que soit la
/// durée passée dehors. C'est pourtant le fait le plus lourd de conséquences
/// pour qui vit au nord du 45e parallèle, et il n'apparaît qu'à cette échelle.
struct YearView: View {

    @Environment(AppModel.self) private var model
    @State private var selected: Date?
    @State private var showsLocationPicker = false

    private var outlook: YearOutlook? { model.yearOutlook }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let outlook {
                    header(outlook)
                    Card { chart(outlook) }
                    seasons(outlook)
                    verdict(outlook)
                } else {
                    Card {
                        Text("L'année ne peut être calculée sans position.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .background(SkyBackground(
                solarElevation: model.solarPosition?.elevation ?? -90,
                cloudCover: model.currentConditions?.cloudCover ?? 0))
        .navigationTitle(model.location?.name ?? "L'année")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Changer de lieu") { showsLocationPicker = true }
                    .font(.subheadline)
            }
        }
        .sheet(isPresented: $showsLocationPicker) { LocationPickerView() }
    }

    // MARK: - En-tête

    private func header(_ outlook: YearOutlook) -> some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "globe.americas")
                    .font(.title2)
                    .foregroundStyle(Theme.vitaminD)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.location?.name ?? "Position")
                        .font(.title3.weight(.semibold))
                    Text(coordinates(outlook))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(latitudeSentence(outlook))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func coordinates(_ outlook: YearOutlook) -> String {
        let lat = String(format: "%.2f", abs(outlook.latitude))
        let lon = String(format: "%.2f", abs(outlook.longitude))
        let ns = outlook.latitude >= 0 ? "N" : "S"
        let ew = outlook.longitude >= 0 ? "E" : "O"
        return "\(lat)° \(ns) · \(lon)° \(ew)"
    }

    private func latitudeSentence(_ outlook: YearOutlook) -> String {
        let high = Format.degrees(outlook.highestElevation)
        let low = Format.degrees(outlook.lowestElevation)
        return "Le Soleil culmine à \(high) au solstice d'été et à \(low) à celui "
            + "d'hiver. C'est cet écart, et lui seul, qui crée l'hiver vitaminique."
    }

    // MARK: - Courbe

    private func chart(_ outlook: YearOutlook) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            chartHeader(outlook)

            Chart {
                ForEach(outlook.winterPeriods, id: \.start) { period in
                    RectangleMark(
                        xStart: .value("Début", period.start),
                        xEnd: .value("Fin", period.end),
                        yStart: .value("Bas", 0.0),
                        yEnd: .value("Haut", 90.0)
                    )
                    .foregroundStyle(Color.blue.opacity(0.10))
                }

                ForEach(outlook.days) { day in
                    AreaMark(
                        x: .value("Date", day.date),
                        y: .value("Hauteur", day.peakElevation)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [Theme.vitaminD.opacity(0.45), Theme.vitaminD.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom))
                }

                RuleMark(y: .value("Règle de l'ombre", UVEngine.optimalSynthesisElevation))
                    .foregroundStyle(Theme.vitaminD.opacity(0.7))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 1) {
                        Text("45° · rendement optimal")
                            .font(.caption2)
                            .foregroundStyle(Theme.vitaminD)
                    }

                RuleMark(y: .value("Seuil", UVEngine.vitaminDWinterElevation))
                    .foregroundStyle(.blue.opacity(0.7))
                    .lineStyle(.init(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .bottom, alignment: .leading, spacing: 1) {
                        Text("25° · plus rien en dessous")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }

                RuleMark(x: .value("Aujourd'hui", model.now))
                    .foregroundStyle(.primary.opacity(0.6))
                    .lineStyle(.init(lineWidth: 1.5))

                if let day = selectedDay(outlook) {
                    PointMark(
                        x: .value("Date", day.date),
                        y: .value("Hauteur", day.peakElevation)
                    )
                    .foregroundStyle(Theme.yieldColour(day.band))
                }
            }
            // Bornes et graduations en Double : les marques le sont, et un
            // littéral entier ferait inférer une échelle d'un autre type que
            // celui des données.
            .chartYScale(domain: 0.0...90.0)
            .chartXSelection(value: $selected)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 25.0, 45.0, 65.0, 90.0]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let degrees = value.as(Double.self) {
                            Text("\(Int(degrees))°")
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month, count: 2)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(Format.monthAbbreviation(date, in: outlook.timeZone))
                        }
                    }
                }
            }
            .frame(height: 210)

            Text("Hauteur du Soleil à son midi, jour après jour. La zone bleue est "
                 + "l'hiver vitaminique : le Soleil y reste sous 25°, l'ozone absorbe "
                 + "les UVB, et aucune durée d'exposition ne produit quoi que ce soit.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chartHeader(_ outlook: YearOutlook) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if let day = selectedDay(outlook) {
                Text(Format.longDate(day.date, in: outlook.timeZone))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Format.degrees(day.peakElevation)) · \(day.band.shortTitle)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.yieldColour(day.band))
            } else {
                Text("L'année \(String(outlook.year))")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("Touchez la courbe")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func selectedDay(_ outlook: YearOutlook) -> YearDay? {
        guard let selected else { return nil }
        return outlook.day(nearest: selected)
    }

    // MARK: - Saisons

    private func seasons(_ outlook: YearOutlook) -> some View {
        Card(title: "Les saisons de la vitamine D", systemImage: "calendar") {
            VStack(spacing: 10) {
                row("Rendement optimal",
                    outlook.optimalSeason.map { Format.dateRange($0, in: outlook.timeZone) } ?? "jamais",
                    tint: Theme.vitaminD)
                row("Synthèse possible",
                    outlook.usefulSeason.map { Format.dateRange($0, in: outlook.timeZone) } ?? "jamais")
                row("Hiver vitaminique",
                    outlook.winter.map { Format.dateRange($0, in: outlook.timeZone) } ?? "aucun",
                    tint: .blue)
            }
        }
    }

    private func row(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Ce qu'il faut en conclure

    @ViewBuilder
    private func verdict(_ outlook: YearOutlook) -> some View {
        Card(title: "Ce que cela implique", systemImage: "text.book.closed") {
            if outlook.hasWinter {
                Text("""
                À cette latitude, une partie de l'année ne produit rien. Ce n'est \
                pas une question de temps passé dehors ni de tenue : le rayonnement \
                utile n'atteint tout simplement pas le sol.

                Deux conséquences pratiques. D'abord, les sorties de la belle saison \
                comptent double, puisqu'elles sont les seules possibles. Ensuite, la \
                période creuse se prépare — l'onglet Historique en tient le compte — \
                mais elle ne se comble pas : le 25(OH)D circulant perd la moitié de \
                sa valeur toutes les trois semaines environ. Passé un certain point, \
                l'alimentation et la supplémentation prennent nécessairement le relais.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                Text("""
                À cette latitude, le Soleil monte assez haut toute l'année : il n'y \
                a pas d'hiver vitaminique. La synthèse reste possible en toute \
                saison, ce qui déplace la question — il ne s'agit plus de savoir \
                quand c'est possible, mais de ne pas dépenser son capital cutané \
                plus vite que nécessaire.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack { YearView().environment(AppModel()) }
}
