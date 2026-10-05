import Foundation

/// Tout ce que le coach calcule à partir des données enregistrées.
struct CoachSnapshot {
    let load: [LoadPoint]
    let readiness: ReadinessResult?
    let plan: SeasonPlan
    let latestWellness: DailyWellness?
    let activeInjuries: [Injury]

    var today: LoadPoint? { load.last }

    static func build(profile: AthleteProfile,
                      wellness: [DailyWellness],
                      activities: [CardioActivity],
                      strength: [StrengthWorkout],
                      unavailabilities: [Unavailability],
                      injuries: [Injury],
                      now: Date = .now) -> CoachSnapshot {
        let calendar = Calendar.current
        let thresholds = profile.thresholds

        var items: [(date: Date, tss: Double)] = activities.map { activity in
            (activity.start, activity.providedTSS ?? TrainingLoad.estimateTSS(
                sport: activity.sport,
                durationSeconds: activity.durationSeconds,
                normalizedPower: activity.normalizedPower,
                averagePower: activity.averagePower,
                averageHeartRate: activity.averageHeartRate,
                thresholds: thresholds))
        }
        items += strength.map { workout in
            (workout.start, TrainingLoad.estimateTSS(sport: .strength, durationSeconds: workout.durationSeconds, thresholds: thresholds))
        }

        let daily = TrainingLoad.dailyTotals(items, calendar: calendar)
        let firstDay = daily.keys.min() ?? calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let load = TrainingLoad.series(daily: daily, from: firstDay, to: now, calendar: calendar)

        let sortedWellness = wellness.sorted { $0.day < $1.day }
        let todayStart = calendar.startOfDay(for: now)
        let lastNight = sortedWellness.last { $0.day == todayStart && $0.sleepHours != nil }

        let readiness = ReadinessCalculator.compute(
            hrv: sortedWellness.compactMap { record in record.hrvMs.map { DayValue(date: record.day, value: $0) } },
            restingHR: sortedWellness.compactMap { record in record.restingHeartRate.map { DayValue(date: record.day, value: $0) } },
            lastNightSleepHours: lastNight?.sleepHours,
            sleepNeedHours: profile.sleepNeedHours,
            form: load.last?.form,
            today: now,
            calendar: calendar)

        let activeInjuries = injuries.filter(\.isActive)
        let plan = SeasonPlanner.makePlan(PlannerInput(
            today: now,
            raceDate: profile.raceDate,
            raceName: profile.raceName,
            currentCTL: load.last?.ctl ?? 0,
            targetRaceCTL: profile.targetRaceCTL,
            weeklyHoursAvailable: profile.weeklyHoursAvailable,
            strengthSessionsPerWeek: profile.strengthSessionsPerWeek,
            unavailabilities: unavailabilities.map { UnavailabilityPeriod(start: $0.start, end: $0.end, reason: $0.reason) },
            injuries: activeInjuries.map {
                InjuryStatus(name: $0.title, muscles: $0.muscles, affectsRunning: $0.affectsRunning,
                             affectsCycling: $0.affectsCycling, severity: $0.severity)
            }))

        return CoachSnapshot(load: load, readiness: readiness, plan: plan,
                             latestWellness: sortedWellness.last, activeInjuries: activeInjuries)
    }
}

extension StrengthWorkout {
    /// Regroupe les séries par exercice pour le moteur de progression.
    var exerciseSessions: [ExerciseSession] {
        var order: [String] = []
        var grouped: [String: [LoggedSet]] = [:]
        for set in sets.sorted(by: { $0.setIndex < $1.setIndex }) {
            if grouped[set.exercise] == nil { order.append(set.exercise) }
            grouped[set.exercise, default: []].append(
                LoggedSet(weightKg: set.weightKg, reps: set.reps, rpe: set.rpe, isWarmup: set.isWarmup))
        }
        return order.map { ExerciseSession(date: start, exercise: $0, sets: grouped[$0] ?? []) }
    }
}
