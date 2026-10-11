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
    /// Aujourd'hui 9 h : les tests ne dépendent pas de l'heure à laquelle ils tournent (règle des 4 h).
    private static let morning = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now)!

    @Test func syncsAndStoresTimestamp() async throws {
        let store = RecordingStore()
        let cache = InMemorySyncCache()
        let service = SyncService(primary: MockSleepProvider(nights: [night]), store: store, cache: cache,
                                  now: { Self.morning })
        try await service.syncSleepData()
        #expect(store.saved == [night])
        #expect(cache.lastSyncDate != nil)
        #expect(service.hasSyncedToday)
        #expect(service.syncError == nil)
    }

    @Test func skipsWhenAlreadySyncedToday() async throws {
        let store = RecordingStore()
        let service = SyncService(primary: MockSleepProvider(nights: [night]), store: store,
                                  cache: InMemorySyncCache(lastSyncDate: Self.morning), now: { Self.morning })
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

    @Test func openingAfterMidnightDoesNotCountForTheMorning() {
        let calendar = Calendar.current
        let halfPastMidnight = calendar.date(bySettingHour: 0, minute: 30, second: 0, of: Self.morning)!
        let atNight = SyncService(primary: MockSleepProvider(nights: [night]), store: RecordingStore(),
                                  cache: InMemorySyncCache(lastSyncDate: halfPastMidnight),
                                  now: { calendar.date(byAdding: .minute, value: 30, to: halfPastMidnight)! })
        #expect(atNight.hasSyncedToday)
        let atWake = SyncService(primary: MockSleepProvider(nights: [night]), store: RecordingStore(),
                                 cache: InMemorySyncCache(lastSyncDate: halfPastMidnight), now: { Self.morning })
        #expect(!atWake.hasSyncedToday)
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

    @Test func napDoesNotChangeTheNight() {
        let calendar = Calendar.current
        let samples = [
            RawSleepSample(start: date(10, 23), end: date(11, 3), kind: .core, source: "watch"),
            RawSleepSample(start: date(11, 3), end: date(11, 3, 20), kind: .awake, source: "watch"),
            RawSleepSample(start: date(11, 3, 20), end: date(11, 7), kind: .deep, source: "watch"),
            // Sieste de 14 h à 15 h : session séparée (écart > 90 min), exclue de la nuit.
            RawSleepSample(start: date(11, 14), end: date(11, 15), kind: .core, source: "watch"),
        ]
        let nights = HealthKitService.nights(from: samples, calendar: calendar)
        let night = nights[calendar.startOfDay(for: date(11, 7))]
        #expect(nights.count == 1)
        #expect(abs((night?.hours ?? 0) - (4 + 3 + 2.0 / 3)) < 0.001)
        #expect(night?.bedtime == date(10, 23))
        #expect(night?.wake == date(11, 7))
        #expect(abs((night?.awake ?? 0) - 1.0 / 3) < 0.001)
    }

    @Test func longestMorningSessionWinsOverALongerAfternoonOne() {
        let calendar = Calendar.current
        let samples = [
            RawSleepSample(start: date(11, 1), end: date(11, 5), kind: .unspecified, source: "phone"),
            RawSleepSample(start: date(11, 9), end: date(11, 15), kind: .unspecified, source: "phone"),
        ]
        let night = HealthKitService.nights(from: samples, calendar: calendar)[calendar.startOfDay(for: date(11, 5))]
        #expect(night?.hours == 4)
        #expect(night?.wake == date(11, 5))
        #expect(night?.deep == nil)
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
                                          planned: [], plans: [])
        #expect(days.compactMap { $0 }.count == 31)
        // Octobre 2026 commence un jeudi : 3 cases vides avec une semaine qui commence le lundi.
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let mondayFirst = TrainingCalendar.month(containing: reference, activities: [], workouts: [], unavailabilities: [],
                                                 planned: [], plans: [], calendar: calendar)
        #expect(mondayFirst.prefix(while: { $0 == nil }).count == 3)
    }
}

struct SleepScoreTests {
    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        DateComponents(calendar: .current, year: 2026, month: 10, day: day, hour: hour, minute: minute).date!
    }

    @Test func fullGoodNightScoresHigh() {
        let result = SleepScoreCalculator.compute(asleepHours: 8, needHours: 8, bedtime: at(10, 22, 45), wake: at(11, 7, 15),
                                                  deepHours: 1.4, remHours: 1.8, awakeHours: 0.4,
                                                  usualBedtimeMinutes: SleepAnalytics.eveningMinutes(at(10, 22, 40)))
        #expect((result?.score ?? 0) >= 90)
        #expect(result?.components.count == 4)
    }

    @Test func shortFragmentedNightScoresLow() {
        let result = SleepScoreCalculator.compute(asleepHours: 5, needHours: 8, bedtime: at(11, 1, 30), wake: at(11, 8, 0),
                                                  deepHours: 0.4, remHours: 0.6, awakeHours: 1.4,
                                                  usualBedtimeMinutes: SleepAnalytics.eveningMinutes(at(10, 22, 45)))
        #expect((result?.score ?? 100) < 50)
    }

    @Test func missingStagesAreIgnoredNotPenalised() {
        let result = SleepScoreCalculator.compute(asleepHours: 8, needHours: 8, bedtime: nil, wake: nil,
                                                  deepHours: nil, remHours: nil, awakeHours: nil, usualBedtimeMinutes: nil)
        #expect(result?.score == 100)
        #expect(result?.components.count == 1)
    }
}
