import Foundation
import Testing
@testable import VitamineD

/// Le modèle spectral qui montre pourquoi les UVB s'éteignent avant les UVA.
struct AtmosphericSpectrumTests {

    // MARK: - Sections efficaces

    @Test("La section efficace de l'ozone s'effondre vers les grandes longueurs d'onde")
    func ozoneCrossSectionCollapsesWithWavelength() {
        var previous = Double.infinity
        for nanometres in stride(from: 290.0, through: 400.0, by: 1.0) {
            let sigma = AtmosphericSpectrum.ozoneCrossSection(nanometres: nanometres)
            #expect(sigma > 0)
            #expect(sigma <= previous + 1e-30)
            previous = sigma
        }

        // Le fait qui porte tout le reste : mille fois plus absorbé à 300 nm
        // qu'à 350. La diffusion de Rayleigh, elle, ne varie que d'un facteur
        // deux sur le même intervalle — l'ozone fait donc seul la différence
        // entre les deux bandes.
        let ozoneRatio = AtmosphericSpectrum.ozoneCrossSection(nanometres: 300)
            / AtmosphericSpectrum.ozoneCrossSection(nanometres: 350)
        #expect(ozoneRatio > 400)

        let rayleighRatio = AtmosphericSpectrum.rayleighOpticalDepth(nanometres: 300)
            / AtmosphericSpectrum.rayleighOpticalDepth(nanometres: 350)
        #expect(rayleighRatio > 1.5 && rayleighRatio < 2.5)
    }

    @Test("La valeur mesurée de référence est respectée")
    func theMeasuredAnchorHolds() {
        // σ(325,126 nm) = 1,647·10⁻²⁰ cm², référence photométrique du BIPM.
        // C'est le seul point de la table que j'aie pu vérifier directement,
        // et la table doit le rendre exactement.
        let sigma = AtmosphericSpectrum.ozoneCrossSection(nanometres: 325)
        #expect(abs(sigma - 1.647e-20) < 1e-22)
    }

    // MARK: - Spectres d'action

    @Test("Le spectre d'action de la vitamine D culmine vers 298 nm et meurt vite")
    func vitaminDActionPeaksAndFallsAway() {
        #expect(AtmosphericSpectrum.vitaminDAction(nanometres: 298) == 1)
        #expect(AtmosphericSpectrum.vitaminDAction(nanometres: 340) == 0)

        // Décroissance d'une décade tous les dix nanomètres et demi.
        let at305 = AtmosphericSpectrum.vitaminDAction(nanometres: 305)
        let at315 = AtmosphericSpectrum.vitaminDAction(nanometres: 315)
        #expect(at305 > 0.15 && at305 < 0.30)
        #expect(at315 > 0.01 && at315 < 0.05)
        #expect(at305 > at315)
    }

    @Test("Le spectre d'action de l'érythème s'étend plus loin que celui de la vitamine D")
    func erythemaReachesFurtherThanVitaminD() {
        // La différence de portée est la raison pour laquelle on peut brûler
        // sans faire un gramme de vitamine D.
        #expect(AtmosphericSpectrum.erythemalAction(nanometres: 340) > 0)
        #expect(AtmosphericSpectrum.vitaminDAction(nanometres: 340) == 0)
        #expect(AtmosphericSpectrum.erythemalAction(nanometres: 298) == 1)
    }

    // MARK: - Masse d'air

    @Test("La masse d'air vaut un au zénith et une dizaine à l'horizon")
    func airMassGrowsTowardsTheHorizon() throws {
        let zenith = try #require(AtmosphericSpectrum.airMass(solarElevation: 90))
        let low = try #require(AtmosphericSpectrum.airMass(solarElevation: 5))

        #expect(abs(zenith - 1) < 0.01)
        #expect(low > 9 && low < 12)
        #expect(AtmosphericSpectrum.airMass(solarElevation: 0) == nil)
        #expect(AtmosphericSpectrum.airMass(solarElevation: -10) == nil)
    }

    // MARK: - Ce qui arrive au sol

    @Test("Les UVB s'éteignent bien plus vite que les UVA")
    func uvbFadesFasterThanUVA() {
        // Le fait que l'écran doit rendre évident. À dix degrés de hauteur, il
        // reste un dixième des UVA et moins d'un centième des UVB.
        let low = AtmosphericSpectrum.relativeToZenith(solarElevation: 10)
        let high = AtmosphericSpectrum.relativeToZenith(solarElevation: 60)

        #expect(low.uva > 0.05 && low.uva < 0.20)
        #expect(low.uvb > 0 && low.uvb < 0.02)
        #expect(low.uva > low.uvb * 10)

        #expect(high.uva > 0.75 && high.uva < 0.95)
        #expect(high.uvb > 0.6 && high.uvb < 0.85)
        // Soleil haut, les deux bandes se rapprochent : c'est la même
        // atmosphère, simplement moins épaisse à traverser.
        #expect(high.uva / high.uvb < 1.5)
    }

    @Test("Le rapport UVA sur UVB au sol reste dans les bornes mesurées")
    func theGroundRatioMatchesPublishedMeasurements() throws {
        // Contrôle externe : les mesures publiées donnent 20 à 30 UVA pour un
        // UVB au sol, Soleil haut. Un modèle qui sortirait de cette fourchette
        // serait faux quelque part, et rien d'autre dans ce fichier ne le
        // dirait.
        let high = AtmosphericSpectrum.arrival(solarElevation: 70)
        let ratio = try #require(high.uvaPerUVB)
        #expect(ratio > 20 && ratio < 40)

        // Et il enfle quand le Soleil descend.
        let low = AtmosphericSpectrum.arrival(solarElevation: 15)
        let lowRatio = try #require(low.uvaPerUVB)
        #expect(lowRatio > ratio * 3)
    }

    @Test("L'indice UV déduit s'accorde avec la paramétrisation du moteur")
    func theDerivedUVIndexAgreesWithTheEngine() {
        // Deux voies indépendantes vers la même grandeur : l'intégration
        // spectrale d'un côté, la paramétrisation de Fioletov de l'autre. Elles
        // ne partagent aucune constante. Qu'elles tombent au même endroit est
        // le meilleur contrôle dont ce fichier dispose.
        for elevation in [40.0, 60.0, 80.0] {
            let spectral = AtmosphericSpectrum.arrival(solarElevation: elevation).uvIndex
            let engine = UVEngine.modelledClearSkyUVIndex(
                solarElevation: elevation, environment: .standard)
            #expect(abs(spectral - engine) / max(engine, 0.1) < 0.35)
        }
    }

    @Test("Une couche d'ozone plus épaisse coupe les UVB sans toucher aux UVA")
    func moreOzoneOnlyCostsUVB() {
        let thin = AtmosphericSpectrum.arrival(solarElevation: 45, ozoneDobson: 250)
        let thick = AtmosphericSpectrum.arrival(solarElevation: 45, ozoneDobson: 350)

        #expect(thick.uvb < thin.uvb * 0.75)
        #expect(thick.vitaminD < thin.vitaminD * 0.75)
        // Les UVA ne voient pratiquement pas l'ozone : c'est pourquoi le trou
        // d'ozone a changé le risque de cancer sans rien changer au bronzage.
        #expect(thick.uva > thin.uva * 0.97)
    }

    @Test("Sous l'horizon, plus rien n'arrive")
    func nothingArrivesBelowTheHorizon() {
        #expect(AtmosphericSpectrum.arrival(solarElevation: 0) == .zero)
        #expect(AtmosphericSpectrum.arrival(solarElevation: -20) == .zero)
        #expect(AtmosphericSpectrum.relativeToZenith(solarElevation: -5).uvb == 0)
        #expect(AtmosphericSpectrum.arrival(solarElevation: -5).uvaPerUVB == nil)
    }

    @Test("Tout croît continûment avec la hauteur du Soleil")
    func everythingRisesWithTheSun() {
        var previous = AtmosphericSpectrum.Arrival.zero
        for elevation in stride(from: 1.0, through: 90.0, by: 1.0) {
            let here = AtmosphericSpectrum.arrival(solarElevation: elevation)
            #expect(here.uva >= previous.uva - 1e-12)
            #expect(here.uvb >= previous.uvb - 1e-12)
            #expect(here.vitaminD >= previous.vitaminD - 1e-12)
            previous = here
        }
        // Le zénith est le maximum, et la référence vaut donc bien 100 %.
        let top = AtmosphericSpectrum.relativeToZenith(solarElevation: 90)
        #expect(abs(top.uva - 1) < 1e-9)
        #expect(abs(top.uvb - 1) < 1e-9)
        #expect(abs(top.vitaminD - 1) < 1e-9)
    }
}
