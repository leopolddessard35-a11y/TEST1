import Foundation
import Observation
import SwiftData

/// Écrit les nuits dans `DailyWellness` (SwiftData), sans écraser une source plus complète.
@MainActor
struct SwiftDataSleepStore: SleepStore {
    let context: ModelContext

    @discardableResult
    func save(_ records: [SleepRecord]) throws -> Int {
        guard !records.isEmpty else { return 0 }
        let oldest = records.map(\.day).min() ?? .now
        let descriptor = FetchDescriptor<DailyWellness>(predicate: #Predicate { $0.day >= oldest })
        let existing = try context.fetch(descriptor)
        var byDay: [Date: DailyWellness] = [:]
        for record in existing { byDay[record.day] = record }

        var written = 0
        for night in records {
            let record: DailyWellness
            if let found = byDay[night.day] {
                record = found
            } else {
                record = DailyWellness(day: night.day)
                context.insert(record)
                byDay[night.day] = record
            }
            // Une source sans heures de coucher (API) ne remplace pas une nuit Apple Santé détaillée.
            if night.bedtime == nil, record.bedtime != nil { continue }
            record.sleepHours = night.hours
            if let bedtime = night.bedtime { record.bedtime = bedtime }
            if let wake = night.wake { record.wakeTime = wake }
            written += 1
        }
        do {
            try context.save()
        } catch {
            throw SyncError.persistence(error.localizedDescription)
        }
        return written
    }
}

/// Synchronisation du sommeil : une fois par jour suffit (la nuit ne change plus une fois réveillé).
/// État observable pour l'interface : `isSyncing`, `syncError`, `lastSyncDate`.
@MainActor
@Observable
final class SyncService {
    private(set) var isSyncing = false
    private(set) var syncError: SyncError?
    private(set) var lastSyncDate: Date?
    /// Dernière nuit lue (pour la confirmation dans Raccourcis et l'indicateur).
    private(set) var lastNight: SleepRecord?
    private(set) var lastSource: String?

    @ObservationIgnored private let primary: any SleepDataProvider
    @ObservationIgnored private let fallback: (any SleepDataProvider)?
    @ObservationIgnored private let store: any SleepStore
    @ObservationIgnored private let cache: any SyncCache
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let lookbackDays: Int

    init(primary: any SleepDataProvider,
         fallback: (any SleepDataProvider)? = nil,
         store: any SleepStore,
         cache: any SyncCache = UserDefaultsSyncCache(),
         calendar: Calendar = .current,
         lookbackDays: Int = 7,
         now: @escaping () -> Date = { .now }) {
        self.primary = primary
        self.fallback = fallback
        self.store = store
        self.cache = cache
        self.calendar = calendar
        self.lookbackDays = lookbackDays
        self.now = now
        self.lastSyncDate = cache.lastSyncDate
    }

    /// Une synchro a-t-elle déjà réussi aujourd'hui ?
    var hasSyncedToday: Bool {
        guard let lastSyncDate else { return false }
        return calendar.isDate(lastSyncDate, inSameDayAs: now())
    }

    /// Récupère les dernières nuits et les enregistre.
    /// - Parameters:
    ///   - force: ignore le cache du jour (bouton « Réessayer », tirer pour rafraîchir).
    ///   - allowPrompt: autorise la demande d'accès Apple Santé (premier plan uniquement, jamais depuis Raccourcis).
    func syncSleepData(force: Bool = false, allowPrompt: Bool = true) async throws {
        guard !isSyncing else { return }
        guard force || !hasSyncedToday else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            let (records, source) = try await fetchFromBestSource(allowPrompt: allowPrompt)
            guard !records.isEmpty else { throw SyncError.noData }
            try store.save(records)
            let date = now()
            cache.lastSyncDate = date
            lastSyncDate = date
            lastNight = records.max { $0.day < $1.day }
            lastSource = source
            syncError = nil
        } catch let error as SyncError {
            syncError = error
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let wrapped = SyncError.provider(error.localizedDescription)
            syncError = wrapped
            throw wrapped
        }
    }

    /// Variante sans erreur pour l'interface : l'erreur reste lisible dans `syncError`.
    func syncIfNeeded() async {
        try? await syncSleepData()
    }

    private func fetchFromBestSource(allowPrompt: Bool) async throws -> ([SleepRecord], String) {
        var primaryReady = await primary.isReady()
        if !primaryReady && allowPrompt {
            try? await primary.requestAccess()
            primaryReady = await primary.isReady()
        }
        if primaryReady {
            do {
                let records = try await primary.fetchNights(days: lookbackDays)
                if !records.isEmpty { return (records, primary.name) }
            } catch let error as SyncError where error == .protectedData {
                // Données verrouillées : la source distante peut quand même répondre.
                if let fallback, await fallback.isReady() {
                    return (try await fallback.fetchNights(days: lookbackDays), fallback.name)
                }
                throw error
            }
        }
        if let fallback, await fallback.isReady() {
            return (try await fallback.fetchNights(days: lookbackDays), fallback.name)
        }
        throw primaryReady ? SyncError.noData : SyncError.noSourceReady
    }
}

extension SyncService {
    /// Instance unique, partagée par l'interface et l'intent Raccourcis.
    static let shared: SyncService = {
        #if targetEnvironment(simulator)
        let primary: any SleepDataProvider = MockSleepProvider()
        #else
        let primary: any SleepDataProvider = HealthKitSleepProvider(health: HealthKitService())
        #endif
        let fallback = IntervalsSleepProvider(
            apiKey: { Keychain.get(IntervalsClient.apiKeyAccount) ?? "" },
            athleteID: {
                let context = SharedStore.container.mainContext
                return (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first?.intervalsAthleteID ?? "0"
            })
        return SyncService(primary: primary, fallback: fallback,
                           store: SwiftDataSleepStore(context: SharedStore.container.mainContext))
    }()

    /// Aperçus SwiftUI : aucune dépendance réelle.
    static func preview(error: SyncError? = nil) -> SyncService {
        final class NoopStore: SleepStore {
            func save(_ records: [SleepRecord]) throws -> Int { records.count }
        }
        return SyncService(primary: MockSleepProvider(error: error), store: NoopStore(), cache: InMemorySyncCache())
    }
}
