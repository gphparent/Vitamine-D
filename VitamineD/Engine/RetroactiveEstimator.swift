import Foundation

/// Reconstitution d'une sortie qu'on a oublié de chronométrer.
///
/// ## Pourquoi cela ne peut pas être un simple calcul de coin de table
///
/// Il aurait été facile de multiplier une durée par un débit. Ç'aurait été
/// faux : la hauteur du Soleil change pendant la sortie, le rendement UVB avec
/// elle, et le plafond de photo-équilibre courbe le total. Une sortie de
/// quarante minutes à midi ne vaut pas deux fois une sortie de vingt.
///
/// Le calcul passe donc par le même intégrateur que les sorties chronométrées.
/// Une saisie manuelle et un chronométrage produisent le même nombre pour les
/// mêmes conditions, et c'est la seule garantie qui vaille : deux calculs
/// parallèles auraient divergé au premier changement de constante.
///
/// ## Ce que la reconstitution ne peut pas savoir
///
/// Deux choses, et elles sont dites à l'écran plutôt que cachées ici.
///
/// L'indice UV d'abord. Le service météo ne conserve pas les valeurs passées à
/// la minute ; au-delà de la journée en cours, l'estimation retombe sur le
/// modèle de ciel clair. Une sortie reconstituée un jour couvert est donc
/// surestimée — les nuages retirent jusqu'à trois quarts du rayonnement.
///
/// La charge photochimique ensuite. La sortie est calculée sur une peau
/// reposée. Qui reconstitue deux sorties dans la même journée verra donc la
/// seconde comptée un peu généreusement, puisque la première avait déjà entamé
/// le rendement.
enum RetroactiveEstimator {

    /// Reconstruit une sortie à partir de ce que l'utilisateur en déclare.
    ///
    /// - Parameter uvIndexAt: source d'indice UV. L'appelant y met les
    ///   échantillons du jour s'il en a, le modèle de ciel clair sinon.
    static func estimate(id: UUID = UUID(),
                         start: Date,
                         end: Date,
                         profile: UserProfile,
                         side: BodySide = .whole,
                         location: ResolvedLocation,
                         environment: EnvironmentFactors = .standard,
                         carried: Double = 0,
                         uvIndexAt: (Date) -> Double) -> SessionRecord {

        let end = max(end, start.addingTimeInterval(60))

        var session = ExposureSession(id: id, startDate: start,
                                      profile: profile, location: location)
        session.endDate = end
        session.segments = [.init(start: start, exposure: profile.exposure, side: side)]

        let progress = SessionIntegrator.progress(
            for: session, at: end, environment: environment,
            carried: carried, uvIndexAt: uvIndexAt)

        return SessionRecord(
            id: id,
            start: start,
            end: end,
            vitaminDIU: progress.vitaminDIU,
            medFraction: progress.medFraction,
            locationName: location.name,
            exposedBodyPercentage: profile.exposure.exposedBodyPercentage,
            averageUVIndex: averageUVIndex(from: start, to: end, uvIndexAt: uvIndexAt),
            rawVitaminDIU: progress.rawVitaminDIU,
            latitude: location.latitude,
            longitude: location.longitude,
            isRetroactive: true)
    }

    /// Indice UV moyen sur la durée, échantillonné toutes les cinq minutes.
    ///
    /// La moyenne porte sur toute la sortie, nuit comprise si la saisie
    /// déborde : une sortie déclarée de 18 h à 22 h a bien un indice UV moyen
    /// faible, et l'annoncer nul serait aussi faux que l'annoncer élevé.
    static func averageUVIndex(from start: Date,
                               to end: Date,
                               uvIndexAt: (Date) -> Double) -> Double? {
        guard end > start else { return nil }
        let step: TimeInterval = 300
        var total = 0.0
        var count = 0
        var cursor = start
        while cursor <= end {
            total += uvIndexAt(cursor)
            count += 1
            cursor = cursor.addingTimeInterval(step)
        }
        guard count > 0 else { return nil }
        return total / Double(count)
    }

    /// Source d'indice UV pour une date passée, faute de mesure conservée.
    ///
    /// Le modèle de ciel clair est optimiste par construction. C'est le sens
    /// prudent pour cette application-ci : il attribue à la sortie plus de dose
    /// érythémale qu'elle n'en a probablement pris, donc conseille de sortir
    /// moins, jamais plus.
    static func clearSkyProvider(latitude: Double,
                                 longitude: Double,
                                 environment: EnvironmentFactors) -> (Date) -> Double {
        { date in
            let position = SolarCalculator.position(date: date,
                                                    latitude: latitude,
                                                    longitude: longitude)
            return UVEngine.modelledClearSkyUVIndex(solarElevation: position.elevation,
                                                    environment: environment)
        }
    }
}
