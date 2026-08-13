import SwiftUI

/// Ce que l'application calcule, comment, et où sont ses limites.
struct MethodologyView: View {

    /// Attribution exigée par la licence de WeatherKit.
    ///
    /// Apple impose d'afficher la marque « Weather » et un lien vers la page
    /// légale partout où ses données apparaissent. Ce n'est pas facultatif :
    /// une application qui l'omet est refusée en revue.
    private var attribution: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Météo par  Weather", systemImage: "cloud.sun")
                .font(.subheadline.weight(.medium))
            Link("Sources et mentions légales",
                 destination: URL(string: "https://weatherkit.apple.com/legal-attribution.html")!)
                .font(.footnote)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.cardBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                attribution

                section(
                    title: "Position du Soleil",
                    body: """
                    Calculée par l'algorithme du NOAA Solar Calculator, dérivé des \
                    *Astronomical Algorithms* de Meeus. La précision est de l'ordre de la \
                    minute d'arc — largement au-delà du nécessaire ici. Tout se calcule \
                    hors ligne, à partir de la date, de la latitude et de la longitude.
                    """)

                section(
                    title: "Indice UV",
                    body: """
                    Prévisions d'Apple Weather, complétées par Open-Meteo lorsque les \
                    premières sont indisponibles. En l'absence de tout réseau, \
                    l'application retombe sur la paramétrisation de Fioletov : \
                    UVI ≈ 12,5 · μ^2,42 · (Ω/300)^−1,23, où μ est le cosinus de l'angle \
                    zénithal et Ω la colonne d'ozone. L'altitude ajoute environ 6 % par \
                    kilomètre, la neige au sol jusqu'à 30 % par réflexion.

                    Apple Weather ne publie l'indice UV qu'en nombre entier. Le prendre \
                    tel quel donnerait une courbe en escalier et fausserait le temps \
                    avant rougeur, qui s'obtient en cumulant le débit minute par minute — \
                    un palier à 3 là où la valeur vaut 3,4 se paie en plus de dix pour \
                    cent d'erreur. L'application reconstitue donc une courbe continue à \
                    partir de la couverture nuageuse, en la contraignant à ne jamais \
                    s'écarter de plus d'une demi-unité de la valeur publiée — soit \
                    exactement l'incertitude de l'arrondi.
                    """)

                section(
                    title: "Nuages",
                    body: """
                    Un ciel entièrement couvert ne retire qu'environ 25 % du rayonnement UV, \
                    alors qu'il supprime l'essentiel de la sensation de chaleur et de \
                    luminosité. C'est ce décalage qui produit les coups de soleil « par \
                    temps gris ». Quand la prévision est disponible, l'atténuation vient \
                    directement du modèle ; sinon elle suit la relation empirique de \
                    Josefsson et Landelius.
                    """)

                section(
                    title: "Érythème",
                    body: """
                    Un point d'indice UV vaut 25 mW/m² pondérés par le spectre d'action de \
                    l'érythème (CIE). La dose érythémale minimale retenue va de 200 J/m² \
                    pour un phototype I à 1 000 J/m² pour un phototype VI. L'acclimatation \
                    relève ce seuil jusqu'à 60 %. La crème solaire est comptée à la racine \
                    carrée de son indice nominal, pour tenir compte de la sous-application \
                    quasi universelle.
                    """)

                section(
                    title: "Synthèse de vitamine D",
                    body: """
                    Le débit est proportionnel à l'indice UV, à la surface de peau \
                    découverte, à un rendement propre au phototype et à un facteur d'âge \
                    — la concentration cutanée en 7-déhydrocholestérol diminue d'environ \
                    1 % par an après vingt ans. S'y ajoute une efficacité spectrale \
                    dépendant de la hauteur du Soleil : le spectre d'action de la vitamine D \
                    culmine vers 297 nm, plus court que celui de l'érythème, donc plus \
                    vulnérable à l'absorption par l'ozone quand le trajet atmosphérique \
                    s'allonge.

                    La constante d'étalonnage est calée sur le repère clinique classique : \
                    un adulte de phototype III, un quart du corps découvert, sous un indice \
                    UV de 7 et un Soleil haut, atteint environ 1 000 UI en une douzaine de \
                    minutes.
                    """)

                section(
                    title: "Le plafond",
                    body: """
                    Au-delà d'une certaine dose, la prévitamine D3 formée se photo-isomérise \
                    en lumistérol et en tachystérol au lieu de s'accumuler. La synthèse \
                    sature donc, alors que la dose érythémale, elle, continue de croître \
                    linéairement. C'est le mécanisme qui rend impossible une intoxication à \
                    la vitamine D par le seul soleil — et qui rend inutile toute exposition \
                    prolongée.
                    """)

                section(
                    title: "Ce que l'application ignore",
                    body: """
                    L'orientation du corps par rapport au Soleil, l'ombre des bâtiments et \
                    des arbres, la réflexion par l'eau ou le sable, les vitres — qui \
                    bloquent la totalité des UVB —, l'état des réserves hépatiques de \
                    25-hydroxyvitamine D, les médicaments photosensibilisants, et la \
                    variabilité individuelle, qui atteint couramment un facteur deux ou \
                    trois entre personnes de même phototype.
                    """)

                Divider()

                Text("""
                Cette application n'est pas un dispositif médical et ne remplace ni un \
                dosage sanguin, ni l'avis d'un professionnel de la santé. Toute lésion \
                cutanée qui change d'aspect justifie une consultation, quelle que soit \
                l'exposition mesurée ici.
                """)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .navigationTitle("Méthode et limites")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(title: String, body text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(.init(text))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack { MethodologyView() }
}
