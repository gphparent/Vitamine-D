import Foundation
import HealthKit
import Observation

/// Échanges avec les données de santé de l'appareil.
///
/// ## Ce qui s'écrit, et ce qui ne s'écrit pas
///
/// HealthKit ne possède aucun type pour la vitamine D synthétisée par la peau.
/// Trois décisions en découlent, et elles ne se valent pas.
///
/// L'**exposition ultraviolette** décrit exactement ce qu'une sortie a été :
/// un indice UV moyen sur une durée. Elle s'écrit sans réserve dès que
/// l'utilisateur accepte l'enregistrement.
///
/// La **vitamine D** ne dispose que d'un champ *alimentaire* — ce qu'on avale.
/// Y verser ce que la peau fabrique rend le total juste et la provenance
/// fausse : le graphique de Santé mélangerait synthèse cutanée et suppléments,
/// et toute autre application lisant ce champ y verrait un repas. L'arbitrage
/// appartient à l'utilisateur, pas au programme : c'est un réglage distinct,
/// désactivé par défaut.
///
/// Le **temps passé au grand jour** ne s'écrit jamais. L'Apple Watch
/// l'alimente déjà, et HealthKit additionne les échantillons de toutes les
/// sources : y ajouter les nôtres doublerait le compte de quiconque porte une
/// montre. Cette grandeur-là se lit.
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

    /// Types que l'application peut écrire.
    ///
    /// `timeInDaylight` en est délibérément absent. L'Apple Watch l'alimente
    /// déjà toute seule, et HealthKit additionne les échantillons de toutes les
    /// sources : y ajouter les nôtres doublerait le compte de quiconque porte
    /// une montre. Cette grandeur-là, l'application la lit, elle ne l'écrit pas.
    private func writeTypes(includingDietary dietary: Bool) -> Set<HKSampleType> {
        var types: Set<HKSampleType> = []
        if let uv = HKQuantityType.quantityType(forIdentifier: .uvExposure) {
            types.insert(uv)
        }
        if dietary, let vitaminD = HKQuantityType.quantityType(forIdentifier: .dietaryVitaminD) {
            types.insert(vitaminD)
        }
        return types
    }

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

    func requestAuthorisation(writing: Bool = false, dietary: Bool = false) async {
        guard isAvailable else { return }
        let share = writing ? writeTypes(includingDietary: dietary) : []
        guard !readTypes.isEmpty || !share.isEmpty else { return }
        do {
            try await store.requestAuthorization(toShare: share, read: readTypes)
            isAuthorised = true
        } catch {
            isAuthorised = false
        }
    }

    // MARK: - Écriture

    /// Enregistre une sortie terminée dans Santé.
    ///
    /// Deux précautions font tout l'intérêt de cette méthode.
    ///
    /// La première est l'identifiant de synchronisation. Sans lui, réécrire la
    /// même sortie — après une réinstallation, une restauration de sauvegarde,
    /// ou simplement deux appels — créerait des doublons qu'aucun utilisateur
    /// ne saurait démêler. HealthKit prévoit exactement ce cas : deux
    /// échantillons portant le même `HKMetadataKeySyncIdentifier` se
    /// remplacent au lieu de s'ajouter, celui dont la version est la plus haute
    /// l'emportant.
    ///
    /// La seconde est la séparation des deux écritures. L'exposition
    /// ultraviolette décrit exactement ce que la sortie a été, et s'écrit dès
    /// que l'utilisateur accepte l'enregistrement. La vitamine D, elle, ne
    /// dispose que d'un champ *alimentaire* : elle demande un accord distinct,
    /// parce qu'y verser ce que la peau fabrique rend le total juste et la
    /// provenance fausse.
    func write(_ record: SessionRecord, includingDietary dietary: Bool) async {
        guard isAvailable, record.end > record.start else { return }

        var samples: [HKSample] = []

        if let type = HKQuantityType.quantityType(forIdentifier: .uvExposure),
           let uvIndex = record.averageUVIndex, uvIndex > 0 {
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .count(), doubleValue: uvIndex),
                start: record.start,
                end: record.end,
                metadata: metadata(for: record, suffix: "uv")))
        }

        if dietary, record.vitaminDIU > 0,
           let type = HKQuantityType.quantityType(forIdentifier: .dietaryVitaminD) {
            let micrograms = record.vitaminDIU * Self.microgrammesPerIU
            samples.append(HKQuantitySample(
                type: type,
                quantity: HKQuantity(unit: .gramUnit(with: .micro), doubleValue: micrograms),
                start: record.start,
                end: record.end,
                metadata: metadata(for: record, suffix: "vitamined")))
        }

        guard !samples.isEmpty else { return }
        try? await store.save(samples)
    }

    /// Retire de Santé les échantillons d'une sortie.
    ///
    /// Utile lorsque l'utilisateur désactive l'écriture : ce qu'il a laissé
    /// écrire lui appartient, et il doit pouvoir le reprendre sans aller
    /// fouiller l'application Santé échantillon par échantillon.
    func deleteWrittenSamples(since date: Date) async {
        guard isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(from: HKSource.default())
        for type in writeTypes(includingDietary: true) {
            let byDate = HKQuery.predicateForSamples(withStart: date, end: nil, options: [])
            let both = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, byDate])
            _ = try? await store.deleteObjects(of: type, predicate: both)
        }
    }

    /// Métadonnées d'un échantillon.
    ///
    /// L'identifiant dérive de celui de la sortie, ce qui rend l'écriture
    /// idempotente : la même sortie écrite deux fois occupe un seul
    /// échantillon. Le suffixe distingue les deux grandeurs d'une même sortie,
    /// qui ne doivent évidemment pas se remplacer l'une l'autre.
    private func metadata(for record: SessionRecord, suffix: String) -> [String: Any] {
        [
            HKMetadataKeySyncIdentifier: "\(record.id.uuidString)-\(suffix)",
            HKMetadataKeySyncVersion: 1,
            HKMetadataKeyWasUserEntered: false,
        ]
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
