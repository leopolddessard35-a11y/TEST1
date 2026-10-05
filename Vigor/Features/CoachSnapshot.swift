import Foundation

/// Tout ce que le coach calcule à partir des données enregistrées.
struct CoachSnapshot {
    let load: [LoadPoint]
    let readiness: ReadinessResult?
    /// Score de récupération des 30 derniers jours.
    let readinessHistory: [DayValue]
    let plan: SeasonPlan
    let latestWellness: DailyWellness?
    /// Toutes les journées, triées par date.
    let wellness: [DailyWellness]
    let activeInjuries: [Injury]
    let insights: [Insight]
    /// VFC d'une seule source (Garmin rMSSD en priorité, sinon Apple SDNN).
    let hrvSeries: [DayValue]
    let hrvSource: String
    let macroTargets: MacroTargets?
    let todayNutrition: NutritionDay
    let plannedToday: [PlannedWorkout]
    let todayAdvice: String

    var today: LoadPoint? { load.last }

    static func build(profile: AthleteProfile,
                      wellness: [DailyWellness],
                      activities: [CardioActivity],
                      strength: [StrengthWorkout],
                      unavailabilities: [Unavailability],
                      injuries: [Injury],
                      foods: [FoodEntry],
                      planned: [PlannedWorkout],
                      now: Date = .now) -> CoachSnapshot {
        let calendar = Calendar.current
        let thresholds = profile.thresholds
        let todayStart = calendar.startOfDay(for: now)

        // Séances et charge.
        let samples: [ActivitySample] = activities.map { activity in
            let tss = activity.providedTSS ?? TrainingLoad.estimateTSS(
                sport: activity.sport, durationSeconds: activity.durationSeconds,
                normalizedPower: activity.normalizedPower, averagePower: activity.averagePower,
                averageHeartRate: activity.averageHeartRate, thresholds: thresholds)
            let intensity = activity.providedIntensity ?? TrainingLoad.intensityFactor(
                sport: activity.sport, normalizedPower: activity.normalizedPower, averagePower: activity.averagePower,
                averageHeartRate: activity.averageHeartRate, thresholds: thresholds)
            return ActivitySample(date: activity.start, sport: activity.sport, durationSeconds: activity.durationSeconds,
                                  tss: tss, intensityFactor: intensity, averagePower: activity.averagePower)
        }
        var items: [(date: Date, tss: Double)] = samples.map { ($0.date, $0.tss) }
        items += strength.map { workout in
            (workout.start, TrainingLoad.estimateTSS(sport: .strength, durationSeconds: workout.durationSeconds, thresholds: thresholds))
        }
        let daily = TrainingLoad.dailyTotals(items, calendar: calendar)
        let firstDay = daily.keys.min() ?? calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let load = TrainingLoad.series(daily: daily, from: firstDay, to: now, calendar: calendar)
        let loadByDay = Dictionary(load.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })

        // VFC : une seule source, jamais de mélange SDNN / rMSSD.
        let sortedWellness = wellness.sorted { $0.day < $1.day }
        let rmssd = sortedWellness.compactMap { record in record.hrvRMSSD.map { DayValue(date: record.day, value: $0) } }
        let sdnn = sortedWellness.compactMap { record in record.hrvMs.map { DayValue(date: record.day, value: $0) } }
        let recentRMSSD = Stats.lastDays(60, of: rmssd, today: now, calendar: calendar).count
        let recentSDNN = Stats.lastDays(60, of: sdnn, today: now, calendar: calendar).count
        let useGarmin = recentRMSSD >= 14
        let hrvSeries = useGarmin ? rmssd : sdnn
        let hrvSource = useGarmin ? "Garmin (rMSSD nocturne)" : "Apple Santé (SDNN)"
        let restingHR = sortedWellness.compactMap { record in record.restingHeartRate.map { DayValue(date: record.day, value: $0) } }
        let wellnessByDay = Dictionary(sortedWellness.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })

        func readiness(on day: Date) -> ReadinessResult? {
            ReadinessCalculator.compute(
                hrv: hrvSeries, restingHR: restingHR,
                lastNightSleepHours: wellnessByDay[day]?.sleepHours,
                sleepNeedHours: profile.sleepNeedHours,
                form: loadByDay[day]?.form, today: day, calendar: calendar)
        }
        let todayReadiness = readiness(on: todayStart)
        let history: [DayValue] = (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart),
                  let result = readiness(on: day) else { return nil }
            return DayValue(date: day, value: Double(result.score))
        }

        // Plan saisonnier.
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

        // Nutrition.
        let nutritionDays = Dictionary(grouping: foods, by: { calendar.startOfDay(for: $0.date) }).map { day, entries in
            NutritionDay(date: day,
                         kcal: entries.reduce(0) { $0 + $1.kcal },
                         protein: entries.reduce(0) { $0 + $1.protein },
                         carbs: entries.reduce(0) { $0 + $1.carbs },
                         fat: entries.reduce(0) { $0 + $1.fat })
        }.sorted { $0.date < $1.date }
        let todayNutrition = nutritionDays.first { $0.date == todayStart }
            ?? NutritionDay(date: todayStart, kcal: 0, protein: 0, carbs: 0, fat: 0)
        let weights = sortedWellness.compactMap { record in record.weightKg.map { DayValue(date: record.day, value: $0) } }
        let currentWeight = Stats.exponentialTrend(Stats.lastDays(14, of: weights, today: now, calendar: calendar)).last?.value
            ?? (profile.weightKg > 0 ? profile.weightKg : 0)

        let plannedToday = planned.filter { calendar.isDate($0.date, inSameDayAs: now) }
        let doneToday = samples.filter { calendar.isDate($0.date, inSameDayAs: now) }.reduce(0) { $0 + $1.durationSeconds }
        let plannedSeconds = plannedToday.reduce(0) { $0 + ($1.plannedSeconds ?? 0) }
        let averageActive = Stats.mean(Stats.lastDays(7, of: sortedWellness.compactMap { record in
            record.activeEnergyKcal.map { DayValue(date: record.day, value: $0) }
        }, today: calendar.date(byAdding: .day, value: -1, to: now) ?? now, calendar: calendar).map(\.value))

        let macroTargets = NutritionPlanner.targets(
            weightKg: currentWeight,
            heightCm: profile.heightCm,
            age: profile.age,
            sex: profile.sex,
            activeKcal: averageActive,
            trainingHours: max(doneToday, plannedSeconds) / 3600,
            phase: plan.currentWeek?.phase,
            adaptiveExpenditure: NutritionPlanner.adaptiveExpenditure(nutrition: nutritionDays, weights: weights, today: now, calendar: calendar))

        // Analyse critique.
        let strengthSessions = strength.flatMap(\.exerciseSessions)
        let insights = InsightEngine.analyze(InsightInput(
            today: now,
            wellness: sortedWellness.map { record in
                WellnessSample(date: record.day, sleepHours: record.sleepHours,
                               hrv: useGarmin ? record.hrvRMSSD : record.hrvMs,
                               restingHR: record.restingHeartRate, weightKg: record.weightKg)
            },
            hrvSourcesMixed: recentRMSSD > 0 && recentSDNN > 0,
            load: load,
            activities: samples,
            strength: strengthSessions,
            nutrition: nutritionDays,
            weightKg: currentWeight,
            ftp: thresholds.ftp,
            sleepNeedHours: profile.sleepNeedHours,
            phase: plan.currentWeek?.phase,
            readiness: todayReadiness), calendar: calendar)

        return CoachSnapshot(
            load: load,
            readiness: todayReadiness,
            readinessHistory: history,
            plan: plan,
            latestWellness: sortedWellness.last,
            wellness: sortedWellness,
            activeInjuries: activeInjuries,
            insights: insights,
            hrvSeries: hrvSeries,
            hrvSource: hrvSource,
            macroTargets: macroTargets,
            todayNutrition: todayNutrition,
            plannedToday: plannedToday,
            todayAdvice: advice(readiness: todayReadiness, planned: plannedToday, week: plan.currentWeek))
    }

    /// Conseil du jour : croise la récupération avec la séance prévue.
    static func advice(readiness: ReadinessResult?, planned: [PlannedWorkout], week: PlannedWeek?) -> String {
        let hardPlanned = planned.contains { ($0.plannedTSS ?? 0) >= 70 }
        switch (readiness?.level, hardPlanned) {
        case (.low?, true):
            return "Séance prévue exigeante mais récupération basse : remplace-la par 45–60 min en zone 2 et décale l'intensité de 48 h."
        case (.low?, false):
            return "Récupération basse : journée facile (endurance très douce, mobilité ou repos)."
        case (.moderate?, true):
            return "Séance prévue OK, mais réduis le nombre de répétitions intenses d'environ 20 % si les sensations ne suivent pas."
        case (.ready?, true):
            return "Feu vert pour la séance clé du jour."
        case (.ready?, false):
            return "Bonne récupération : c'est un bon jour pour une séance de qualité ou ta séance Legs."
        default:
            if let week { return "Semaine \(week.kind.label.lowercased()) · \(week.phase.label) : \(week.targetHours.hoursText) prévues." }
            return "Synchronise tes données pour obtenir le conseil du jour."
        }
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

/// Évite de tout recalculer à chaque affichage : le calcul n'est refait que si les données changent.
final class SnapshotCache {
    private var key: Int?
    private var value: CoachSnapshot?

    func snapshot(for key: Int, build: () -> CoachSnapshot) -> CoachSnapshot {
        if let value, self.key == key { return value }
        let fresh = build()
        self.key = key
        value = fresh
        return fresh
    }
}
