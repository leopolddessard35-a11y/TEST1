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
        var items: [(date: Date, tss: Double)] = []
        for sample in samples { items.append((date: sample.date, tss: sample.tss)) }
        for workout in strength {
            let tss: Double = TrainingLoad.estimateTSS(sport: .strength, durationSeconds: workout.durationSeconds, thresholds: thresholds)
            items.append((date: workout.start, tss: tss))
        }
        let daily: [Date: Double] = TrainingLoad.dailyTotals(items, calendar: calendar)
        let fallbackStart: Date = calendar.date(byAdding: .day, value: -60, to: now) ?? now
        let firstDay: Date = daily.keys.min() ?? fallbackStart
        let load: [LoadPoint] = TrainingLoad.series(daily: daily, from: firstDay, to: now, calendar: calendar)
        var loadByDay: [Date: LoadPoint] = [:]
        for point in load { loadByDay[point.date] = point }

        // VFC : une seule source, jamais de mélange SDNN / rMSSD.
        let sortedWellness: [DailyWellness] = wellness.sorted { $0.day < $1.day }
        var rmssd: [DayValue] = []
        var sdnn: [DayValue] = []
        var restingHR: [DayValue] = []
        var wellnessByDay: [Date: DailyWellness] = [:]
        for record in sortedWellness {
            if let value = record.hrvRMSSD { rmssd.append(DayValue(date: record.day, value: value)) }
            if let value = record.hrvMs { sdnn.append(DayValue(date: record.day, value: value)) }
            if let value = record.restingHeartRate { restingHR.append(DayValue(date: record.day, value: value)) }
            wellnessByDay[record.day] = record
        }
        let recentRMSSD = Stats.lastDays(60, of: rmssd, today: now, calendar: calendar).count
        let recentSDNN = Stats.lastDays(60, of: sdnn, today: now, calendar: calendar).count
        let useGarmin = recentRMSSD >= 14
        let hrvSeries: [DayValue] = useGarmin ? rmssd : sdnn
        let hrvSource = useGarmin ? "Garmin (rMSSD nocturne)" : "Apple Santé (SDNN)"

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
        let activeInjuries: [Injury] = injuries.filter(\.isActive)
        var periods: [UnavailabilityPeriod] = []
        for item in unavailabilities {
            periods.append(UnavailabilityPeriod(start: item.start, end: item.end, reason: item.reason))
        }
        var injuryStatuses: [InjuryStatus] = []
        for injury in activeInjuries {
            injuryStatuses.append(InjuryStatus(name: injury.title, muscles: injury.muscles, affectsRunning: injury.affectsRunning,
                                               affectsCycling: injury.affectsCycling, severity: injury.severity))
        }
        let currentCTL: Double = load.last?.ctl ?? 0
        let plannerInput = PlannerInput(
            today: now,
            raceDate: profile.raceDate,
            raceName: profile.raceName,
            currentCTL: currentCTL,
            targetRaceCTL: profile.targetRaceCTL,
            weeklyHoursAvailable: profile.weeklyHoursAvailable,
            strengthSessionsPerWeek: profile.strengthSessionsPerWeek,
            unavailabilities: periods,
            injuries: injuryStatuses)
        let plan: SeasonPlan = SeasonPlanner.makePlan(plannerInput)

        // Nutrition (boucles explicites : plus rapides à compiler).
        var totalsByDay: [Date: NutritionDay] = [:]
        for entry in foods {
            let day = calendar.startOfDay(for: entry.date)
            let current = totalsByDay[day] ?? NutritionDay(date: day, kcal: 0, protein: 0, carbs: 0, fat: 0)
            totalsByDay[day] = NutritionDay(date: day,
                                            kcal: current.kcal + entry.kcal,
                                            protein: current.protein + entry.protein,
                                            carbs: current.carbs + entry.carbs,
                                            fat: current.fat + entry.fat)
        }
        let nutritionDays: [NutritionDay] = totalsByDay.values.sorted { $0.date < $1.date }
        let emptyToday = NutritionDay(date: todayStart, kcal: 0, protein: 0, carbs: 0, fat: 0)
        let todayNutrition: NutritionDay = totalsByDay[todayStart] ?? emptyToday

        var weights: [DayValue] = []
        var activeEnergy: [DayValue] = []
        for record in sortedWellness {
            if let weight = record.weightKg { weights.append(DayValue(date: record.day, value: weight)) }
            if let active = record.activeEnergyKcal { activeEnergy.append(DayValue(date: record.day, value: active)) }
        }
        let recentWeights: [DayValue] = Stats.lastDays(14, of: weights, today: now, calendar: calendar)
        let trendWeight: Double? = Stats.exponentialTrend(recentWeights).last?.value
        let profileWeight: Double = profile.weightKg > 0 ? profile.weightKg : 0
        let currentWeight: Double = trendWeight ?? profileWeight

        let plannedToday: [PlannedWorkout] = planned.filter { calendar.isDate($0.date, inSameDayAs: now) }
        var doneToday: Double = 0
        for sample in samples where calendar.isDate(sample.date, inSameDayAs: now) {
            doneToday += sample.durationSeconds
        }
        var plannedSeconds: Double = 0
        for workout in plannedToday {
            plannedSeconds += workout.plannedSeconds ?? 0
        }
        let yesterday: Date = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        let lastWeekActive: [Double] = Stats.lastDays(7, of: activeEnergy, today: yesterday, calendar: calendar).map(\.value)
        let averageActive: Double? = Stats.mean(lastWeekActive)
        let adaptive: Double? = NutritionPlanner.adaptiveExpenditure(nutrition: nutritionDays, weights: weights,
                                                                     today: now, calendar: calendar)

        let trainingHours: Double = max(doneToday, plannedSeconds) / 3600
        let macroTargets: MacroTargets? = NutritionPlanner.targets(
            weightKg: currentWeight,
            heightCm: profile.heightCm,
            age: profile.age,
            sex: profile.sex,
            activeKcal: averageActive,
            trainingHours: trainingHours,
            phase: plan.currentWeek?.phase,
            adaptiveExpenditure: adaptive)

        // Analyse critique.
        let strengthSessions: [ExerciseSession] = strength.flatMap(\.exerciseSessions)
        var insightWellness: [WellnessSample] = []
        for record in sortedWellness {
            let hrv: Double? = useGarmin ? record.hrvRMSSD : record.hrvMs
            insightWellness.append(WellnessSample(date: record.day, sleepHours: record.sleepHours, hrv: hrv,
                                                  restingHR: record.restingHeartRate, weightKg: record.weightKg))
        }
        let insightInput = InsightInput(
            today: now,
            wellness: insightWellness,
            hrvSourcesMixed: recentRMSSD > 0 && recentSDNN > 0,
            load: load,
            activities: samples,
            strength: strengthSessions,
            nutrition: nutritionDays,
            weightKg: currentWeight,
            ftp: thresholds.ftp,
            sleepNeedHours: profile.sleepNeedHours,
            phase: plan.currentWeek?.phase,
            readiness: todayReadiness)
        let insights: [Insight] = InsightEngine.analyze(insightInput, calendar: calendar)
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
