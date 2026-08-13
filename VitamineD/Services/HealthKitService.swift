import Foundation
import HealthKit
import Observation

/// Lecture des données de santé de l'appareil.
///
/// ## Pourquoi rien n'est jamais écrit
///
/// HealthKit ne possède aucun type pour la vitamine D synthétisée par la peau.
/// Le seul type disponible, `dietaryVitaminD`, désigne l'apport **alimentaire**
/// — ce qu'on avale. Y verser ce que la peau fabrique salirait le suivi
/// nutritionnel de l'utilisateur avec quelque chose qu'il n'a pas mangé, et
/// fausserait toute autre application lisant ce champ. Beaucoup d'applications
/// le font ; celle-ci s'en abstient.
///
/// ## Ce que la lecture apporte
///
/// Deux choses que l'application ne peut pas savoir seule.
///
/// L'apport alimentaire d'abord. En hiver vitaminique, l'application annonce
/// que le Soleil ne peut plus rien et qu'il faut se tourner vers l'assiette ou
/// un supplément — sans savoir si c'est fait. Le lire referme la boucle.
///
/// Le temps passé au grand jour ensuite. Le comptage quotidien ne connaît que
/// les sorties déclarées dans l'application ; l'Apple Watch, elle, mesure la
/// lumière du jour sans qu'on lui demande rien. L'écart entre les deux est
/// précisément la part d'exposition que l'application ignorait — donc du
/// capital cutané dépensé hors de ses comptes.
@MainActor
@Observable
final class HealthKitService {

    /// Une unité internationale de vitamine D vaut 0,025 microgramme de
    /// cholécalciférol. La conversion est une convention, non une mesure.
    static let microgrammesPerIU = 0.025

    private let store = HKHealthStore()

    private(set) var isAuthorised = false
    /// Vitamine D alimentaire du jour, convertie en unités internationales.
    private(set) var dietaryVitaminDIU: Double = 0
    /// Minutes de plein jour mesurées par l'appareil, ce jour-ci.
    private(set) var daylightMinutes: Double = 0

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        if let vitaminD = HKQuantityType.quantityType(forIdentifier: .dietaryVitaminD) {
            types.insert(vitaminD)
        }
        if let daylight = HKQuantityType.quantityType(forIdentifier: .timeInDaylight) {
            types.insert(daylight)
        }
        return types
    }

    // MARK: - Autorisation

    func requestAuthorisation() async {
        guard isAvailable, !readTypes.isEmpty else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            isAuthorised = true
        } catch {
            isAuthorised = false
        }
    }

    // MARK: - Lecture

    /// Relit les deux grandeurs pour la journée contenant `date`.
    ///
    /// HealthKit ne dit jamais si l'autorisation de *lecture* a été refusée —
    /// c'est délibéré de la part d'Apple, pour qu'une application ne puisse pas
    /// déduire d'un refus qu'une donnée existe. Une somme nulle est donc
    /// indiscernable d'un refus, et l'interface ne doit rien affirmer sur cette
    /// base.
    func refresh(on date: Date, calendar: Calendar) async {
        guard isAvailable else { return }
        let start = calendar.startOfDay(for: date)
        let end = start.addingTimeInterval(86_400)

        if let micrograms = await sum(identifier: .dietaryVitaminD,
                                      unit: .gramUnit(with: .micro),
                                      from: start, to: end) {
            dietaryVitaminDIU = micrograms / Self.microgrammesPerIU
        }

        if let minutes = await sum(identifier: .timeInDaylight,
                                   unit: .minute(),
                                   from: start, to: end) {
            daylightMinutes = minutes
        }
    }

    private func sum(identifier: HKQuantityTypeIdentifier,
                     unit: HKUnit,
                     from start: Date,
                     to end: Date) async -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum)

        let statistics = try? await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit)
    }
}
