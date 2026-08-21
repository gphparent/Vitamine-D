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

    // MARK: - Ce que l'application sait de son propre accès

    /// Y a-t-il seulement des échantillons à lire ?
    ///
    /// Zéro et « rien » ne veulent pas dire la même chose, et c'est toute la
    /// différence entre une application qui fonctionne et une application qui
    /// paraît cassée. Une somme nulle peut signifier trois choses : personne
    /// n'a jamais rien enregistré, l'autorisation a été refusée, ou la valeur
    /// est réellement nulle. HealthKit ne dira jamais laquelle — Apple
    /// l'interdit pour la lecture, afin qu'un refus ne puisse pas trahir
    /// l'existence d'une donnée. On distingue au moins le premier cas.
    private(set) var hasDietarySamples = false
    private(set) var hasDaylightSamples = false

    /// Dernière relecture réussie.
    private(set) var lastRefresh: Date?

    /// Dernière erreur d'écriture, telle que HealthKit l'a formulée.
    ///
    /// Elle était auparavant avalée par un `try?`. Une écriture refusée ne
    /// laissait alors aucune trace nulle part : ni dans Santé, ni à l'écran.
    private(set) var lastWriteError: String?

    /// Le système a-t-il déjà posé la question à l'utilisateur ?
    ///
    /// `shouldRequest` signifie qu'au moins un type n'a jamais été soumis :
    /// c'est le seul cas où présenter la feuille sert à quelque chose.
    /// `unnecessary` signifie que tout a été demandé — sans rien dire de ce qui
    /// a été accordé.
    private(set) var requestStatus: HKAuthorizationRequestStatus = .unknown

    /// Écriture autorisée pour l'exposition ultraviolette ?
    ///
    /// Contrairement à la lecture, le statut d'écriture est lisible : il n'y a
    /// aucun secret à protéger dans le fait qu'une application ait le droit
    /// d'ajouter une donnée.
    var ultravioletWriteStatus: HKAuthorizationStatus {
        guard let type = HKQuantityType.quantityType(forIdentifier: .uvExposure) else {
            return .notDetermined
        }
        return store.authorizationStatus(for: type)
    }

    var dietaryWriteStatus: HKAuthorizationStatus {
        guard let type = HKQuantityType.quantityType(forIdentifier: .dietaryVitaminD) else {
            return .notDetermined
        }
        return store.authorizationStatus(for: type)
    }

    /// État global, tel qu'on peut honnêtement le présenter.
    enum Connection: Equatable, Sendable {
        /// Pas de HealthKit sur cet appareil.
        case unavailable
        /// La question n'a jamais été posée.
        case notRequested
        /// La question a été posée. Ce qui a été accordé en lecture reste,
        /// par construction, invérifiable.
        case requested
    }

    /// Seul `unnecessary` prouve que la question a été posée. Dans le doute on
    /// propose de la poser : appuyer sur le bouton une fois de trop ne coûte
    /// rien, alors qu'annoncer à tort un accès obtenu laisse quelqu'un devant
    /// un écran vide sans savoir quoi faire.
    var connection: Connection {
        guard isAvailable else { return .unavailable }
        return requestStatus == .unnecessary ? .requested : .notRequested
    }

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

    /// Ce qu'une demande d'autorisation a réellement produit.
    ///
    /// Le bouton précédent « ne marchait pas », et il était impossible de dire
    /// en quoi : la demande ne laissait aucune trace, ni feuille affichée, ni
    /// erreur, ni explication. Le cas le plus fréquent n'est pourtant pas une
    /// panne — c'est qu'iOS ne repose jamais la question. Une fois la feuille
    /// présentée, elle ne revient plus, et tout appui ultérieur est
    /// silencieusement sans effet.
    enum RequestOutcome: Equatable, Sendable {
        /// La feuille du système a été présentée.
        case presented
        /// Rien ne s'est affiché : la question avait déjà été posée. La suite
        /// se règle dans l'application Santé, pas ici.
        case alreadyAsked
        /// HealthKit a refusé la demande, avec son propre message.
        case failed(String)
        case unavailable
    }

    private(set) var lastOutcome: RequestOutcome?

    @discardableResult
    func requestAuthorisation(writing: Bool = false,
                              dietary: Bool = false) async -> RequestOutcome {
        guard isAvailable else {
            lastOutcome = .unavailable
            return .unavailable
        }
        let share = writing ? writeTypes(includingDietary: dietary) : []
        let read = readTypes
        guard !read.isEmpty || !share.isEmpty else {
            lastOutcome = .unavailable
            return .unavailable
        }

        // L'état d'avant décide de ce que le système fera : s'il ne compte pas
        // demander, aucune feuille n'apparaîtra. Le savoir permet de le dire,
        // au lieu de laisser quelqu'un devant un bouton inerte.
        let before = (try? await store.statusForAuthorizationRequest(
            toShare: share, read: read)) ?? .unknown

        var outcome: RequestOutcome
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            isAuthorised = true
            lastAuthorisationError = nil
            outcome = before == .shouldRequest ? .presented : .alreadyAsked
        } catch {
            isAuthorised = false
            lastAuthorisationError = error.localizedDescription
            outcome = .failed(error.localizedDescription)
        }

        await refreshRequestStatus(writing: writing, dietary: dietary)
        lastOutcome = outcome
        return outcome
    }

    /// Dernier refus opposé par HealthKit à une demande d'autorisation.
    private(set) var lastAuthorisationError: String?

    /// Relit l'état de la demande auprès du système.
    ///
    /// À appeler à l'ouverture de l'écran de réglages : l'utilisateur a pu
    /// changer d'avis dans Réglages ▸ Santé entre deux lancements, et
    /// l'application ne l'apprendra pas autrement.
    func refreshRequestStatus(writing: Bool = false, dietary: Bool = false) async {
        guard isAvailable else {
            requestStatus = .unknown
            return
        }
        let share = writing ? writeTypes(includingDietary: dietary) : []
        requestStatus = (try? await store.statusForAuthorizationRequest(
            toShare: share, read: readTypes)) ?? .unknown
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
        do {
            try await store.save(samples)
            lastWriteError = nil
        } catch {
            // Une écriture refusée ne laissait aucune trace : ni dans Santé,
            // ni à l'écran. L'utilisateur en concluait, à raison, que rien ne
            // marchait — sans jamais savoir quoi.
            lastWriteError = error.localizedDescription
        }
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

    /// Retire de Santé les échantillons d'une sortie précise.
    ///
    /// Supprimer une sortie de l'historique sans la retirer de Santé laisserait
    /// derrière elle une donnée que plus rien dans l'application ne justifie, et
    /// que l'utilisateur devrait aller chasser à la main. Le filtre porte sur
    /// l'identifiant de synchronisation, celui-là même qui rend l'écriture
    /// idempotente.
    func deleteSamples(forRecord id: UUID) async {
        guard isAvailable else { return }
        let identifiers = ["\(id.uuidString)-uv", "\(id.uuidString)-vitamined"]
        let predicate = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeySyncIdentifier,
            allowedValues: identifiers)
        for type in writeTypes(includingDietary: true) {
            _ = try? await store.deleteObjects(of: type, predicate: predicate)
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

        // Une somme absente et une somme nulle sont deux choses différentes :
        // la première dit qu'il n'existe aucun échantillon, la seconde qu'il en
        // existe et qu'ils valent zéro. L'écran doit pouvoir le dire.
        let micrograms = await sum(identifier: .dietaryVitaminD,
                                   unit: .gramUnit(with: .micro),
                                   from: start, to: end)
        hasDietarySamples = micrograms != nil
        dietaryVitaminDIU = (micrograms ?? 0) / Self.microgrammesPerIU

        let minutes = await sum(identifier: .timeInDaylight,
                                unit: .minute(),
                                from: start, to: end)
        hasDaylightSamples = minutes != nil
        daylightMinutes = minutes ?? 0

        lastRefresh = Date()
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
