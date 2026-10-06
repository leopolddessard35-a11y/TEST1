import Foundation
import Testing
@testable import Vigor

private let base = DateComponents(calendar: .current, year: 2026, month: 10, day: 20, hour: 12).date!
private func ago(_ days: Int) -> Date { Calendar.current.date(byAdding: .day, value: -days, to: base)! }

struct AnalyticsTests {
    @Test func heartRateZonesAndDrift() {
        // 60 min : 30 min à 130 bpm puis 30 min à 140 bpm, seuil 170 → zones 1 puis 2, dérive ≈ +7 %.
        var samples: [HeartRateZones.Sample] = []
        for second in stride(from: 0, to: 3600, by: 5) {
            samples.append(HeartRateZones.Sample(time: base.addingTimeInterval(Double(second)), bpm: second < 1800 ? 130 : 140))
        }
        let bounds = HeartRateZones.bounds(thresholds: Thresholds(cyclingLTHR: 170), sport: .cycling)!
        let result = HeartRateZones.analyze(samples, bounds: bounds)
        #expect(result.zones[0] > 1700) // 130 < 0,81 × 170 = 137,7
        #expect(result.zones[1] > 1700) // 140 < 0,90 × 170 = 153
        #expect((result.drift ?? 0) > 5)
    }

    @Test func disciplineLoadsAndGlobal() {
        var items: [LoadItem] = []
        for day in 0..<28 { items.append(LoadItem(date: ago(day), tss: 50, discipline: "Vélo")) }
        for day in 0..<7 { items.append(LoadItem(date: ago(day), tss: 40, discipline: "Hors sport")) }
        let loads = LoadAnalytics.disciplineLoads(items, today: base)
        #expect(loads.first?.name == "Global")
        let bike = loads.first { $0.name == "Vélo" }
        #expect(abs((bike?.ratio ?? 0) - 1) < 0.01)
        let life = loads.first { $0.name == "Hors sport" }
        #expect((life?.ratio ?? 0) > 3)
    }

    @Test func volumeAlertAbove10Percent() {
        let calendar = SeasonPlanner.isoCalendar
        let week = calendar.dateInterval(of: .weekOfYear, for: base)!.start
        let previous = calendar.date(byAdding: .day, value: -7, to: week)!
        let before = calendar.date(byAdding: .day, value: -14, to: week)!
        let samples = [
            VolumeSample(date: before.addingTimeInterval(3600), sport: .cycling, seconds: 5 * 3600, meters: 0),
            VolumeSample(date: previous.addingTimeInterval(3600), sport: .cycling, seconds: 7 * 3600, meters: 0),
        ]
        let volumes = LoadAnalytics.weeklyVolumes(samples: samples, tonnage: [], life: [], weeks: 4, today: base)
        let alerts = LoadAnalytics.progressionAlerts(volumes)
        #expect(alerts.contains { $0.hasPrefix("Vélo") })
    }

    @Test func bedtimeRegularityAcrossMidnight() {
        let calendar = Calendar.current
        let times = [23 * 60 + 30, 0 * 60 + 30, 23 * 60 + 45, 0 * 60 + 15, 23 * 60 + 50].map { minutes in
            calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: base)!
        }
        let regularity = SleepAnalytics.bedtimeRegularity(times)
        #expect((regularity?.sd ?? 999) < 40) // 23 h 30 et 0 h 30 sont proches, pas à 23 h d'écart
    }

    @Test func correlationDetectsSleepHRVLink() {
        let records = (0..<30).map { day -> DayRecord in
            var record = DayRecord(date: ago(day))
            let sleep = 6 + Double(day % 4) * 0.7
            record.sleep = sleep
            record.hrv = 40 + sleep * 4
            return record
        }
        let results = Correlations.analyze(records)
        #expect((results.first { $0.id == "sleep-hrv" }?.r ?? 0) > 0.9)
    }

    @Test func symptomPatternFindsShoeAndRecurrence() {
        let records = (0..<6).map { index in
            SymptomRecord(date: ago(index * 2), key: "Engourdissement · pied gauche", intensity: 4,
                          onsetMinutes: index.isMultiple(of: 2) ? 22 : 35, shoe: index.isMultiple(of: 2) ? "Pegasus" : "Novablast",
                          terrain: "Route", fatigue: 3, previousSleep: 7.5)
        }
        let patterns = SymptomAnalysis.patterns(records, runsByShoe: ["Pegasus": 4, "Novablast": 8], today: base)
        #expect(patterns.count == 1)
        #expect(patterns[0].isRecurrent)
        #expect(patterns[0].findings.contains { $0.contains("Pegasus") && $0.contains("22") })
    }

    @Test func rpeDrivesLoadWithoutSensors() {
        let easy = TrainingLoad.estimateTSS(sport: .running, durationSeconds: 3600, rpe: 3, thresholds: Thresholds())
        let hard = TrainingLoad.estimateTSS(sport: .running, durationSeconds: 3600, rpe: 9, thresholds: Thresholds())
        #expect(hard > easy * 2)
        #expect(TrainingLoad.estimateTSS(sport: .strength, durationSeconds: 3600, rpe: 8, thresholds: Thresholds()) == 48)
    }

    @Test func lifeActivityLoadEquivalent() {
        let renovation = LifeActivity(date: base, kind: .renovation, minutes: 360, intensity: 2)
        #expect(renovation.loadEquivalent == 210)
    }
}
