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

struct SleepTimeTests {
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        DateComponents(calendar: .current, year: 2026, month: 10, day: day, hour: hour, minute: minute).date!
    }

    @Test func segmentsBeforeMidnightBelongToTheNextMorning() {
        let calendar = Calendar.current
        // Endormi le 10 à 23 h 10 : le segment qui finit à 23 h 55 appartient à la nuit du 11.
        #expect(HealthKitService.nightDay(forSegmentEnding: date(10, 23, 55)) == calendar.startOfDay(for: date(11, 7)))
        #expect(HealthKitService.nightDay(forSegmentEnding: date(11, 7, 10)) == calendar.startOfDay(for: date(11, 7)))
        // Sieste de l'après-midi : rattachée au jour même.
        #expect(HealthKitService.nightDay(forSegmentEnding: date(11, 15)) == calendar.startOfDay(for: date(11, 7)))
    }

    @Test func bedtimeAdviceIsAnEveningTime() {
        let wakes = (1...7).map { date($0, 7, 15) }
        let beds = (1...7).map { date($0, 6, 45).addingTimeInterval(-8 * 3600) }
        let need = SleepCoach.need(base: 8, effortToday: 8, debt7: 0, wakeTimes: wakes, bedTimes: beds,
                                   sleptHours: Array(repeating: 7.5, count: 7))
        #expect(need.usualWakeMinutes == 7 * 60 + 15)
        #expect((21 * 60...23 * 60 + 59).contains(need.bedtimeMinutes))
    }
}

struct TrainingCalendarTests {
    @Test func monthGridStartsOnTheFirstWeekday() {
        let reference = DateComponents(calendar: .current, year: 2026, month: 10, day: 15).date!
        let days = TrainingCalendar.month(containing: reference, activities: [], workouts: [], unavailabilities: [],
                                          planned: [], weekStatus: [])
        #expect(days.compactMap { $0 }.count == 31)
        // Octobre 2026 commence un jeudi : 3 cases vides avec une semaine qui commence le lundi.
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let mondayFirst = TrainingCalendar.month(containing: reference, activities: [], workouts: [], unavailabilities: [],
                                                 planned: [], weekStatus: [], calendar: calendar)
        #expect(mondayFirst.prefix(while: { $0 == nil }).count == 3)
    }
}
