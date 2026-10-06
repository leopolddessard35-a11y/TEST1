import Foundation
import Testing
@testable import Vigor

struct DailyCoachTests {
    /// Mardi 13 octobre 2026, 8 h.
    private let tuesday = DateComponents(calendar: .current, year: 2026, month: 10, day: 13, hour: 8).date!

    private func buildWeek() -> PlannedWeek {
        PlannedWeek(id: 0, start: tuesday, phase: .build, kind: .load, targetTSS: 450, targetHours: 8,
                    longRideHours: 3, intensitySessions: 2, strengthSessions: 3, runningAllowed: true,
                    availableDays: 7, projectedCTL: 45, notes: [])
    }

    private func readiness(_ level: ReadinessLevel, _ score: Int) -> ReadinessResult {
        ReadinessResult(score: score, level: level, components: [])
    }

    private func input(readiness: ReadinessResult?, sleep: Double?) -> DailyCoachInput {
        DailyCoachInput(today: tuesday, readiness: readiness, lastNightSleep: sleep, sleepNeed: 8, sleepDebt7: nil,
                        load: nil, acuteChronicRatio: nil, yesterdayNutrition: nil, expenditure: nil, weightKg: 72,
                        week: buildWeek(), ftp: 206)
    }

    @Test func tuesdayOfBuildWeekIsThreshold() {
        let sessions = DailyCoach.template(for: buildWeek(), weekday: 3, ftp: 206)
        #expect(sessions.contains { $0.kind == .threshold })
        #expect(sessions.first { $0.kind == .threshold }?.detail.contains("195") == true) // 95 % de 206 W, arrondi
    }

    @Test func weekTemplatePlacesPPLAndLongRide() {
        #expect(DailyCoach.template(for: buildWeek(), weekday: 2, ftp: 206).contains { $0.kind == .push })
        #expect(DailyCoach.template(for: buildWeek(), weekday: 6, ftp: 206).contains { $0.kind == .legs })
        #expect(DailyCoach.template(for: buildWeek(), weekday: 7, ftp: 206).contains { $0.kind == .longRide })
    }

    @Test func greatRecoveryKeepsIntensity() {
        let brief = DailyCoach.brief(input(readiness: readiness(.ready, 85), sleep: 8.2))
        #expect(brief.verdict == .push)
        #expect(brief.adapted.contains { $0.kind == .threshold })
    }

    @Test func shortNightRemovesIntensity() {
        let brief = DailyCoach.brief(input(readiness: readiness(.ready, 75), sleep: 5.2))
        #expect(!brief.adapted.contains { $0.kind.isIntense })
        #expect(brief.adapted.contains { $0.kind == .endurance })
        #expect(!brief.changes.isEmpty)
    }

    @Test func lowRecoveryGivesEasyDay() {
        let brief = DailyCoach.brief(input(readiness: readiness(.low, 35), sleep: 6.5))
        #expect(brief.verdict == .easy || brief.verdict == .rest)
        #expect(!brief.adapted.contains { $0.kind.isIntense })
    }

    @Test func lowCarbsYesterdayAddsFuelingPriority() {
        var coachInput = input(readiness: readiness(.ready, 80), sleep: 8)
        coachInput.yesterdayNutrition = NutritionDay(date: tuesday, kcal: 2000, protein: 140, carbs: 220, fat: 70)
        let brief = DailyCoach.brief(coachInput)
        #expect(brief.factors.contains { $0.name == "Glucides bas hier" })
        #expect(brief.fueling.first?.contains("Glucides bas hier") == true)
    }

    @Test func hamstringInjuryAdaptsLegsDay() {
        var coachInput = input(readiness: readiness(.ready, 80), sleep: 8)
        coachInput.today = DateComponents(calendar: .current, year: 2026, month: 10, day: 16, hour: 8).date! // vendredi
        coachInput.injuries = [InjuryStatus(name: "Ischio", muscles: [.hamstrings], affectsRunning: true, affectsCycling: false, severity: 1)]
        let brief = DailyCoach.brief(coachInput)
        #expect(brief.adapted.first { $0.kind == .legs }?.detail.contains("ischio") == true)
    }
}

struct MealReminderTests {
    @Test func lunchBeforeIntensityRecommendsCarbs() {
        let sessions = [DailyCoach.bike(.threshold, minutes: 75, ftp: 206, phase: .build)]
        let tip = NotificationScheduler.mealTip(.lunch, sessions: sessions, tomorrowSessions: [], forTomorrow: false)
        #expect(tip?.contains("glucides") == true)
    }

    @Test func dinnerBeforeLongRideTomorrow() {
        let tomorrow = [DailyCoach.bike(.longRide, minutes: 180, ftp: 206, phase: .base)]
        let tip = NotificationScheduler.mealTip(.dinner, sessions: [], tomorrowSessions: tomorrow, forTomorrow: false)
        #expect(tip?.contains("demain") == true)
    }

    @Test func mealSharesCoverTheDay() {
        let total = NotificationScheduler.remindedMeals.reduce(0.0) { $0 + NotificationScheduler.share(of: $1) }
        #expect(abs(total - 1) < 0.001)
    }
}
