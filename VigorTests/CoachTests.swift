import Foundation
import Testing
@testable import Vigor

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    DateComponents(calendar: Calendar.current, year: year, month: month, day: day, hour: 12).date!
}

struct TrainingLoadTests {
    @Test func oneHourAtFTPIsHundredTSS() {
        let tss = TrainingLoad.estimateTSS(sport: .cycling, durationSeconds: 3600, normalizedPower: 206,
                                           thresholds: Thresholds(ftp: 206))
        #expect(abs(tss - 100) < 0.001)
    }

    @Test func heartRateFallbackWithoutPower() {
        let tss = TrainingLoad.estimateTSS(sport: .running, durationSeconds: 3600, averageHeartRate: 150,
                                           thresholds: Thresholds(runningLTHR: 170))
        #expect(tss > 70 && tss < 85)
    }

    @Test func constantLoadConvergesTowardsDailyTSS() {
        let calendar = Calendar.current
        let start = day(2026, 1, 1)
        var daily: [Date: Double] = [:]
        for offset in 0..<200 {
            daily[calendar.startOfDay(for: calendar.date(byAdding: .day, value: offset, to: start)!)] = 50
        }
        let series = TrainingLoad.series(daily: daily, from: start, to: calendar.date(byAdding: .day, value: 199, to: start)!)
        #expect(series.count == 200)
        #expect(abs(series.last!.ctl - 50) < 1)
        #expect(abs(series.last!.form) < 1)
    }
}

struct ReadinessTests {
    @Test func lowHRVAndShortSleepGiveLowReadiness() {
        let today = day(2026, 10, 5)
        let calendar = Calendar.current
        var hrv: [DayValue] = []
        var rhr: [DayValue] = []
        for offset in 1...40 {
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            hrv.append(DayValue(date: date, value: 60 + Double(offset % 5)))
            rhr.append(DayValue(date: date, value: 50 + Double(offset % 3)))
        }
        hrv.append(DayValue(date: today, value: 35))
        rhr.append(DayValue(date: today, value: 60))

        let result = ReadinessCalculator.compute(hrv: hrv, restingHR: rhr, lastNightSleepHours: 5,
                                                 sleepNeedHours: 8, form: nil, today: today)
        #expect(result?.level == .low)
    }

    @Test func normalValuesGiveGoodReadiness() {
        let today = day(2026, 10, 5)
        let calendar = Calendar.current
        var hrv: [DayValue] = []
        for offset in 0...40 {
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!
            hrv.append(DayValue(date: date, value: 60 + Double(offset % 5)))
        }
        let result = ReadinessCalculator.compute(hrv: hrv, restingHR: [], lastNightSleepHours: 8,
                                                 sleepNeedHours: 8, form: 0, today: today)
        #expect(result?.level == .ready)
    }
}

struct StrengthProgressionTests {
    private func session(_ date: Date, weight: Double, reps: [Int]) -> ExerciseSession {
        ExerciseSession(date: date, exercise: "Bench Press (Barbell)",
                        sets: [LoggedSet(weightKg: 40, reps: 10, isWarmup: true)] + reps.map { LoggedSet(weightKg: weight, reps: $0) })
    }

    @Test func topOfRangeIncreasesLoad() {
        let advice = StrengthProgression.advise(exercise: "Bench Press (Barbell)",
                                                sessions: [session(day(2026, 10, 1), weight: 70, reps: [10, 10, 10])])
        #expect(advice?.action == .increase)
        #expect(advice?.suggestedWeightKg == 72.5)
    }

    @Test func lowReadinessHoldsTheIncrease() {
        let advice = StrengthProgression.advise(exercise: "Bench Press (Barbell)",
                                                sessions: [session(day(2026, 10, 1), weight: 70, reps: [10, 10, 10])],
                                                readiness: .low)
        #expect(advice?.action == .keep)
    }

    @Test func twoStalledSessionsDecreaseLoad() {
        let sessions = [
            session(day(2026, 9, 24), weight: 80, reps: [5, 5, 4]),
            session(day(2026, 10, 1), weight: 80, reps: [5, 4, 4]),
        ]
        let advice = StrengthProgression.advise(exercise: "Bench Press (Barbell)", sessions: sessions)
        #expect(advice?.action == .decrease)
        #expect(advice?.suggestedWeightKg == 72)
    }

    @Test func injuredMuscleIsAvoided() {
        let rdl = ExerciseSession(date: day(2026, 10, 1), exercise: "Romanian Deadlift (Barbell)",
                                  sets: [LoggedSet(weightKg: 80, reps: 8)])
        let advice = StrengthProgression.advise(exercise: rdl.exercise, sessions: [rdl], injuredMuscles: [.hamstrings])
        #expect(advice?.action == .avoid)
    }

    @Test func muscleMapRecognisesCommonHevyExercises() {
        #expect(MuscleMap.targets(for: "Seated Leg Curl (Machine)").primary == [.hamstrings])
        #expect(MuscleMap.targets(for: "Bicep Curl (Dumbbell)").primary == [.biceps])
        #expect(MuscleMap.targets(for: "Lat Pulldown (Cable)").primary == [.lats])
        #expect(MuscleMap.targets(for: "Squat (Barbell)").primary.contains(.quads))
        #expect(MuscleMap.increment(for: "Squat (Barbell)") == 5)
    }
}

struct SeasonPlannerTests {
    private func input(ctl: Double = 30,
                       unavailabilities: [UnavailabilityPeriod] = [],
                       injuries: [InjuryStatus] = []) -> PlannerInput {
        PlannerInput(today: day(2026, 10, 5), raceDate: day(2027, 4, 25), currentCTL: ctl, targetRaceCTL: 60,
                     weeklyHoursAvailable: 10, strengthSessionsPerWeek: 3,
                     unavailabilities: unavailabilities, injuries: injuries)
    }

    @Test func planRunsUntilRaceWeek() {
        let plan = SeasonPlanner.makePlan(input())
        #expect(plan.weeks.count == 29)
        #expect(plan.weeks.last?.phase == .race)
        #expect(plan.weeks[plan.weeks.count - 2].phase == .taper)
    }

    @Test func progressionIsGradual() {
        let plan = SeasonPlanner.makePlan(input())
        for (previous, next) in zip(plan.weeks, plan.weeks.dropFirst()) {
            #expect(next.projectedCTL - previous.projectedCTL <= 6.01)
        }
        #expect(plan.projectedPeakCTL >= 59)
        #expect(plan.weeks.contains { $0.kind == .recovery })
    }

    @Test func taperReducesLoad() {
        let plan = SeasonPlanner.makePlan(input())
        let peak = plan.weeks.filter { $0.phase == .specific }.map(\.targetTSS).max() ?? 0
        let taper = plan.weeks.first { $0.phase == .taper }!
        #expect(taper.targetTSS < peak * 0.8)
    }

    @Test func illnessReducesWeekAndFollowingWeek() {
        let normal = SeasonPlanner.makePlan(input())
        let sick = SeasonPlanner.makePlan(input(unavailabilities: [
            UnavailabilityPeriod(start: day(2026, 10, 19), end: day(2026, 10, 23), reason: .illness),
        ]))
        #expect(sick.weeks[2].targetTSS < normal.weeks[2].targetTSS)
        #expect(sick.weeks[2].availableDays == 2)
        #expect(sick.weeks[3].notes.contains { $0.contains("Retour après maladie") })
    }

    @Test func hamstringInjuryBlocksRunningAndIntensity() {
        let injury = InjuryStatus(name: "Ischio gauche", muscles: [.hamstrings], affectsRunning: true,
                                  affectsCycling: false, severity: 2)
        let plan = SeasonPlanner.makePlan(input(injuries: [injury]))
        #expect(plan.weeks.first?.phase == .reprise)
        #expect(plan.weeks.allSatisfy { !$0.runningAllowed })
        #expect(plan.weeks.allSatisfy { $0.intensitySessions == 0 })
    }
}

struct ImportTests {
    @Test func parsesHevyExport() throws {
        let csv = """
        "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_kg","reps","distance_km","duration_seconds","rpe"
        "Push","5 Oct 2026, 18:30","5 Oct 2026, 19:35","Bonne séance","Bench Press (Barbell)",,"prise large",0,"warmup",40,10,,,
        "Push","5 Oct 2026, 18:30","5 Oct 2026, 19:35","Bonne séance","Bench Press (Barbell)",,"prise large",1,"normal",72.5,8,,,8.5
        "Push","5 Oct 2026, 18:30","5 Oct 2026, 19:35","Bonne séance","Plank",,"",0,"normal",,,,60,
        "Pull","7 Oct 2026, 18:00","7 Oct 2026, 19:00","","Lat Pulldown (Cable)",,"",0,"normal",55,12,,,
        """
        let workouts = try HevyImporter.parse(csv)
        #expect(workouts.count == 2)
        let push = workouts[0]
        #expect(push.title == "Push")
        #expect(push.description == "Bonne séance")
        #expect(push.sets.count == 3)
        #expect(push.sets[0].setType == "warmup")
        #expect(push.sets[1].weightKg == 72.5)
        #expect(push.sets[1].rpe == 8.5)
        #expect(push.sets[1].exerciseNotes == "prise large")
        #expect(push.sets[2].durationSeconds == 60)
        #expect(push.end != nil)
    }

    @Test func csvHandlesQuotedCommasAndNewlines() {
        let rows = CSVParser.parse("a,b\n\"x, y\",\"ligne1\nligne2\"\n")
        #expect(rows == [["a", "b"], ["x, y", "ligne1\nligne2"]])
    }

    @Test func detectsDuplicateRides() {
        let start = day(2026, 10, 5)
        #expect(ActivityDeduplicator.isSameSession(sportA: .indoorCycling, startA: start, durationA: 3600,
                                                   sportB: .cycling, startB: start.addingTimeInterval(120), durationB: 3500))
        #expect(!ActivityDeduplicator.isSameSession(sportA: .running, startA: start, durationA: 3600,
                                                    sportB: .cycling, startB: start, durationB: 3600))
    }
}
