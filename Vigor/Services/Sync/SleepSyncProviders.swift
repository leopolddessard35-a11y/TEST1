import Foundation
import HealthKit

// MARK: - Modèle d'échange

/// Une nuit de sommeil, indépendante de la source (Apple Santé, API, mock).
struct SleepRecord: Equatable, Sendable {
    /// Jour du réveil, à minuit.
    let day: Date
    let hours: Double
    let bedtime: Date?
    let wake: Date?
    let source: String
}

// MARK: - Erreurs

enum SyncError: LocalizedError, Equatable {
    case healthDataUnavailable
    case notAuthorized
    /// Données Santé chiffrées tant que l'iPhone est verrouillé.
    case protectedData
    case noSourceReady
    case noData
    case provider(String)
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .healthDataUnavailable: "Apple Santé n'est pas disponible sur cet appareil."
        case .notAuthorized: "Accès au sommeil refusé : Réglages → Santé → Accès aux données → Vigor."
        case .protectedData: "iPhone verrouillé : les données Santé seront lues au déverrouillage."
        case .noSourceReady: "Aucune source prête : autorise Apple Santé ou ajoute ta clé Intervals.icu."
        case .noData: "Aucune nuit trouvée pour l'instant."
        case .provider(let message): "Lecture impossible : \(message)"
        case .persistence(let message): "Enregistrement impossible : \(message)"
        }
    }
}

// MARK: - Sources de sommeil (protocoles pour la mockabilité)

/// Une source de nuits de sommeil.
@MainActor
protocol SleepDataProvider {
    var name: String { get }
    /// Prête à être lue sans interaction (autorisations déjà accordées, clé présente…).
    func isReady() async -> Bool
    /// Demande l'accès si besoin (uniquement au premier plan).
    func requestAccess() async throws
    func fetchNights(days: Int) async throws -> [SleepRecord]
}

extension SleepDataProvider {
    func requestAccess() async throws {}
}

/// Apple Santé : `HKCategoryTypeIdentifier.sleepAnalysis` (Garmin, Apple Watch, iPhone…).
@MainActor
struct HealthKitSleepProvider: SleepDataProvider {
    let health: HealthKitService
    private let store = HKHealthStore()

    var name: String { "Apple Santé" }

    func isReady() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        // `.unnecessary` = la demande d'autorisation a déjà été faite (iOS ne dit jamais si la LECTURE est accordée).
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: [HKCategoryType(.sleepAnalysis)])
        return status == .unnecessary
    }

    func requestAccess() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { throw SyncError.healthDataUnavailable }
        try await health.requestAuthorization()
    }

    func fetchNights(days: Int) async throws -> [SleepRecord] {
        guard HKHealthStore.isHealthDataAvailable() else { throw SyncError.healthDataUnavailable }
        do {
            let nights = try await health.sleepNights(days: days)
            return nights.map { day, night in
                SleepRecord(day: day, hours: night.hours, bedtime: night.bedtime, wake: night.wake, source: name)
            }
            .sorted { $0.day < $1.day }
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            throw SyncError.protectedData
        } catch let error as HKError where error.code == .errorAuthorizationDenied || error.code == .errorAuthorizationNotDetermined {
            throw SyncError.notAuthorized
        }
    }
}

/// API distante : Intervals.icu (données Garmin), utilisée si Apple Santé n'est pas prêt.
@MainActor
struct IntervalsSleepProvider: SleepDataProvider {
    let apiKey: () -> String
    let athleteID: () -> String

    var name: String { "Intervals.icu" }

    func isReady() async -> Bool { !apiKey().isEmpty }

    func fetchNights(days: Int) async throws -> [SleepRecord] {
        let key = apiKey()
        guard !key.isEmpty else { throw SyncError.noSourceReady }
        let client = IntervalsClient(apiKey: key, athleteID: athleteID().isEmpty ? "0" : athleteID())
        let newest = Date.now
        let oldest = Calendar.current.date(byAdding: .day, value: -days, to: newest) ?? newest
        let wellness = try await client.wellness(oldest: oldest, newest: newest)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return wellness.compactMap { item -> SleepRecord? in
            guard let seconds = item.sleepSecs, seconds > 0, let date = formatter.date(from: item.id) else { return nil }
            return SleepRecord(day: Calendar.current.startOfDay(for: date), hours: seconds / 3600,
                               bedtime: nil, wake: nil, source: name)
        }
        .sorted { $0.day < $1.day }
    }
}

/// Source factice : simulateur, aperçus SwiftUI et tests. Jamais utilisée sur l'iPhone en production.
@MainActor
struct MockSleepProvider: SleepDataProvider {
    var ready = true
    var nights: [SleepRecord]
    var error: SyncError?
    /// Simule la latence réseau.
    var delay: Duration = .milliseconds(300)

    var name: String { "Démo" }

    init(ready: Bool = true, nights: [SleepRecord]? = nil, error: SyncError? = nil) {
        self.ready = ready
        self.error = error
        self.nights = nights ?? MockSleepProvider.sampleNights()
    }

    func isReady() async -> Bool { ready }

    func fetchNights(days: Int) async throws -> [SleepRecord] {
        try await Task.sleep(for: delay)
        if let error { throw error }
        return nights
    }

    static func sampleNights(days: Int = 7, calendar: Calendar = .current) -> [SleepRecord] {
        let today = calendar.startOfDay(for: .now)
        return (0..<days).compactMap { offset -> SleepRecord? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let wake = calendar.date(bySettingHour: 7, minute: 10, second: 0, of: day) else { return nil }
            let hours = 7.0 + Double((offset * 37) % 90) / 60
            return SleepRecord(day: day, hours: hours, bedtime: wake.addingTimeInterval(-hours * 3600 - 900),
                               wake: wake, source: "Démo")
        }
    }
}

// MARK: - Cache de la dernière synchro

protocol SyncCache: AnyObject {
    var lastSyncDate: Date? { get set }
}

/// Persistance simple dans UserDefaults.
final class UserDefaultsSyncCache: SyncCache {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "sync.sleep.lastSuccess") {
        self.defaults = defaults
        self.key = key
    }

    var lastSyncDate: Date? {
        get { defaults.object(forKey: key) as? Date }
        set { defaults.set(newValue, forKey: key) }
    }
}

final class InMemorySyncCache: SyncCache {
    var lastSyncDate: Date?
    init(lastSyncDate: Date? = nil) { self.lastSyncDate = lastSyncDate }
}

// MARK: - Destination des nuits

@MainActor
protocol SleepStore {
    /// Enregistre les nuits ; renvoie le nombre de jours écrits.
    @discardableResult
    func save(_ records: [SleepRecord]) throws -> Int
}
