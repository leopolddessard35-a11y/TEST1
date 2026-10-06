import Foundation
import Testing
@testable import Vigor

@MainActor
private final class RecordingStore: SleepStore {
    var saved: [SleepRecord] = []
    func save(_ records: [SleepRecord]) throws -> Int {
        saved.append(contentsOf: records)
        return records.count
    }
}

@MainActor
struct SyncServiceTests {
    private let night = SleepRecord(day: Calendar.current.startOfDay(for: .now), hours: 7.5, bedtime: nil, wake: nil, source: "Test")

    @Test func syncsAndStoresTimestamp() async throws {
        let store = RecordingStore()
        let cache = InMemorySyncCache()
        let service = SyncService(primary: MockSleepProvider(nights: [night]), store: store, cache: cache)
        try await service.syncSleepData()
        #expect(store.saved == [night])
        #expect(cache.lastSyncDate != nil)
        #expect(service.hasSyncedToday)
        #expect(service.syncError == nil)
    }

    @Test func skipsWhenAlreadySyncedToday() async throws {
        let store = RecordingStore()
        let service = SyncService(primary: MockSleepProvider(nights: [night]), store: store,
                                  cache: InMemorySyncCache(lastSyncDate: .now))
        try await service.syncSleepData()
        #expect(store.saved.isEmpty)
        try await service.syncSleepData(force: true)
        #expect(store.saved.count == 1)
    }

    @Test func resyncsOnANewDay() async throws {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now)!
        let store = RecordingStore()
        let service = SyncService(primary: MockSleepProvider(nights: [night]), store: store,
                                  cache: InMemorySyncCache(lastSyncDate: yesterday))
        #expect(!service.hasSyncedToday)
        try await service.syncSleepData()
        #expect(store.saved.count == 1)
    }

    @Test func fallsBackWhenPrimaryNotReady() async throws {
        let store = RecordingStore()
        let service = SyncService(primary: MockSleepProvider(ready: false),
                                  fallback: MockSleepProvider(nights: [night]),
                                  store: store, cache: InMemorySyncCache())
        try await service.syncSleepData(allowPrompt: false)
        #expect(store.saved == [night])
    }

    @Test func exposesErrorAndKeepsCacheEmpty() async {
        let cache = InMemorySyncCache()
        let service = SyncService(primary: MockSleepProvider(error: .notAuthorized), store: RecordingStore(), cache: cache)
        await #expect(throws: SyncError.notAuthorized) { try await service.syncSleepData() }
        #expect(service.syncError == .notAuthorized)
        #expect(cache.lastSyncDate == nil)
        #expect(!service.isSyncing)
    }

    @Test func noSourceReadyIsReported() async {
        let service = SyncService(primary: MockSleepProvider(ready: false), store: RecordingStore(), cache: InMemorySyncCache())
        await #expect(throws: SyncError.noSourceReady) { try await service.syncSleepData(allowPrompt: false) }
    }
}
