import Foundation
import Testing
@testable import VitamineD

/// Les lampes d'hiver, et surtout ce qu'elles ne font pas.
struct LightTherapyTests {

    @Test("Aucune modalité ne prétend produire de la vitamine D")
    func noModalityClaimsVitaminD() {
        // Le malentendu qui justifie l'écran : on achète une lampe rouge en
        // croyant compenser le Soleil qui manque. Chaque carte doit donc porter
        // le démenti, et pas seulement le bandeau du haut — une carte se lit
        // souvent seule.
        for modality in LightTherapy.Modality.allCases {
            #expect(modality.caveat.contains("vitamine D"))
            #expect(!modality.purpose.contains("itamine D"))
        }
    }

    @Test("Seule la luminothérapie porte une preuve solide")
    func onlyBrightLightIsSolid() {
        #expect(LightTherapy.Modality.brightLight.evidence == .solid)
        #expect(LightTherapy.Modality.photobiomodulation.evidence == .thin)
        #expect(LightTherapy.Modality.eveningRed.evidence == .moderate)

        // L'écran classe de la preuve la plus forte à la plus faible. Un
        // catalogue rangé autrement laisserait croire que les trois se valent.
        let ordered = LightTherapy.Modality.allCases.sorted { $0.evidence < $1.evidence }
        #expect(ordered.first == .brightLight)
        #expect(ordered.last == .photobiomodulation)
    }

    @Test("La photobiomodulation avertit que davantage n'est pas mieux")
    func photobiomodulationWarnsAboutTheBiphasicCurve() {
        // Huang, Sharma, Carroll et Hamblin : la réponse est biphasique, et les
        // valeurs où se produisent les transitions ne font pas l'objet d'un
        // accord. Une application qui donnerait une posologie ferme mentirait.
        let text = LightTherapy.Modality.photobiomodulation.rationale
        #expect(text.contains("biphasique"))
        #expect(LightTherapy.Modality.photobiomodulation.caveat.contains("pas mieux"))
    }

    @Test("Les durées conseillées suivent les protocoles publiés")
    func durationsFollowPublishedProtocols() {
        // Trente minutes à 10 000 lux : le protocole devenu standard dans les
        // essais sur le trouble affectif saisonnier.
        #expect(LightTherapy.Modality.brightLight.duration == 30 * 60)
        #expect(LightTherapy.brightLightLux == 10_000)

        for modality in LightTherapy.Modality.allCases {
            #expect(modality.duration > 0)
            #expect(modality.duration <= 2 * 3600)
        }
    }

    @Test("La luminothérapie se prend le matin, le rouge le soir")
    func timingFollowsTheClock() {
        let wake = 7 * 60, bed = 23 * 60

        let morning = LightTherapy.Modality.brightLight
            .suggestedStart(wakeMinute: wake, bedMinute: bed)
        let evening = LightTherapy.Modality.eveningRed
            .suggestedStart(wakeMinute: wake, bedMinute: bed)

        #expect(morning < 12 * 60)
        #expect(evening > 12 * 60)
        #expect(evening < bed)
        // Prise le soir, la lumière vive retarde l'endormissement au lieu de
        // l'avancer : l'écart entre les deux doit rester franc.
        #expect(evening - morning > 8 * 60)
    }

    @Test("Une lampe ne dépasse jamais un ciel dégagé")
    func aLampNeverBeatsClearDaylight() {
        // Le chiffre qui remet la lampe à sa place : elle fait jeu égal avec un
        // ciel couvert, et se fait dépasser de cinq fois par un ciel dégagé.
        #expect(LightTherapy.brightLightLux == LightTherapy.overcastDaylightLux)
        #expect(LightTherapy.clearDaylightLux > LightTherapy.brightLightLux * 4)
        #expect(LightTherapy.indoorRatio > 30)
    }
}
