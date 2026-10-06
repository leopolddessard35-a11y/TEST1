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
        for day in 0..<90 { items.append(LoadItem(date: ago(day), tss: 50, discipline: "Vélo")) }
        for day in 0..<7 { items.append(LoadItem(date: ago(day), tss: 40, discipline: "Hors sport")) }
        let loads = LoadAnalytics.disciplineLoads(items, today: base)
        #expect(loads.first?.name == "Global")
        let bike = loads.first { $0.name == "Vélo" }
        #expect(abs((bike?.ratio ?? 0) - 1) < 0.01)
        let life = loads.first { $0.name == "Hors sport" }
        #expect((life?.ratio ?? 0) > 2)
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

struct DailyScoresTests {
    @Test func effortScaleIsLogarithmic() {
        #expect(abs(EffortScore.score(load: 100) - 14) < 0.01)
        #expect(EffortScore.score(load: 200) > 18 && EffortScore.score(load: 200) < 19)
        #expect(EffortScore.score(load: 0) == 0)
        #expect(EffortScore.score(load: 1000) < 21)
        #expect(abs(EffortScore.load(for: 14) - 100) < 0.5)
    }

    @Test func sleepNeedGrowsWithEffortAndDebt() {
        let rested = SleepCoach.need(base: 8, effortToday: 8, debt7: 0, wakeTimes: [], bedTimes: [], sleptHours: [])
        let tired = SleepCoach.need(base: 8, effortToday: 18, debt7: 6, wakeTimes: [], bedTimes: [], sleptHours: [])
        #expect(rested.total == 8)
        #expect(abs(tired.total - (8 + 32.0 / 60 + 1)) < 0.01) // +32 min d'effort, +1 h de dette (plafond)
        #expect(tired.bedtimeMinutes < rested.bedtimeMinutes) // coucher plus tôt
    }

    @Test func respiratoryRiseIsFlagged() {
        var respiration: [DayValue] = []
        var rhr: [DayValue] = []
        for day in 0..<30 {
            respiration.append(DayValue(date: ago(day), value: day < 2 ? 16.4 : 14.6 + Double(day % 3) * 0.1))
            rhr.append(DayValue(date: ago(day), value: day < 2 ? 55 : 48))
        }
        let signal = RespiratoryMonitor.signal(respiration: respiration, restingHR: rhr, today: base)
        #expect(signal?.isWarning == true)
        #expect(signal?.restingHRUp == true)
    }

    @Test func weeklyReportComparesWeeks() {
        var days: [WeeklyReportBuilder.Day] = []
        for offset in 1...14 {
            var day = WeeklyReportBuilder.Day(date: Calendar.current.startOfDay(for: ago(offset)), sleepNeed: 8)
            day.recovery = offset <= 7 ? 75 : 55
            day.load = 60
            day.sleep = 7.5
            days.append(day)
        }
        let report = WeeklyReportBuilder.build(days: days, today: base)
        #expect(report?.current.recovery == 75)
        #expect(report?.previous.recovery == 55)
        #expect(report?.highlights.first?.contains("hausse") == true)
    }
}

struct RobustAndDecisionTests {
    @Test func medianAndMAD() {
        #expect(Robust.median([1, 3, 2, 100]) == 2.5)
        #expect(abs((Robust.mad([1, 2, 3, 4, 100]) ?? 0) - 1.4826) < 0.001)
    }

    @Test func spearmanHandlesMonotonicNonLinear() {
        let xs: [Double] = Array(1...20).map(Double.init)
        let ys: [Double] = xs.map { $0 * $0 * $0 }
        #expect(abs((Robust.spearman(xs, ys) ?? 0) - 1) < 0.0001)
        let ci = Robust.confidenceInterval(r: 0.5, n: 30)
        #expect(ci != nil && ci!.contains(0.5) && !ci!.contains(0))
    }

    @Test func regressionDetectsTrend() {
        let points = (0..<8).map { DayValue(date: ago(56 - $0 * 7), value: 100 + Double($0) * 2) }
        let fit = Robust.regression(points)
        #expect(abs((fit?.slopePerDay ?? 0) * 7 - 2) < 0.01)
    }

    @Test func decayedDebtWeightsRecentNights() {
        let recent = Robust.decayedSleepDebt(need: 8, sleeps: [(daysAgo: 0, hours: 6)])
        let old = Robust.decayedSleepDebt(need: 8, sleeps: [(daysAgo: 10, hours: 6)])
        #expect(recent == 2)
        #expect(old < 0.5)
    }

    @Test func twoRedSignalsAdaptAndThreeRest() {
        let week = PlannedWeek(id: 0, start: base, phase: .build, kind: .load, targetTSS: 450, targetHours: 8,
                               longRideHours: 3, intensitySessions: 2, strengthSessions: 3, runningAllowed: true,
                               availableDays: 7, projectedCTL: 45, notes: [])
        var input = DailyCoachInput(today: DateComponents(calendar: .current, year: 2026, month: 10, day: 13, hour: 8).date!,
                                    readiness: ReadinessResult(score: 75, level: .ready, components: []),
                                    lastNightSleep: 5.5, sleepNeed: 8, sleepDebt7: nil, load: nil, acuteChronicRatio: 1.6,
                                    yesterdayNutrition: nil, expenditure: nil, weightKg: 72, week: week, ftp: 206)
        let adapted = DailyCoach.brief(input)
        #expect(adapted.redSignals.count == 2)
        #expect(adapted.verdict == .easy)
        input.hrvZ = -1.5
        input.hrvDeltaPercent = -14
        let rest = DailyCoach.brief(input)
        #expect(rest.verdict == .rest)
        #expect(rest.headline.contains("VFC -14 %") || rest.headline.contains("VFC −14 %") || rest.headline.contains("-14"))
    }

    @Test func experimentEffect() {
        var series: [DayValue] = []
        for day in 0..<28 { series.append(DayValue(date: ago(27 - day), value: day < 14 ? 50 + Double(day % 3) : 60 + Double(day % 3))) }
        let result = ExperimentAnalysis.analyze(series: series, start: ago(13), end: nil, today: base)
        #expect((result.changePercent ?? 0) > 15)
        #expect(result.verdict == "Effet net.")
    }
}

struct StrictParsingTests {
    @Test func parsesDurationsMissingAndCommas() {
        #expect(HevyImporter.number("1:23:45") == 5025)
        #expect(HevyImporter.number("23:45") == 1425)
        #expect(HevyImporter.number("--") == nil)
        #expect(HevyImporter.number("72,5") == 72.5)
        #expect(HevyImporter.number("") == nil)
    }
}
