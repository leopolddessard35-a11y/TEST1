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
    /// Le plan du jour adapté (santé × entraînement × nutrition).
    let brief: DailyBrief
    /// Séances prévues demain (pour la notification du matin).
    let tomorrowPlan: [SessionPrescription]
    /// Repas déjà renseignés aujourd'hui (pas de rappel pour ceux-là).
    let loggedMealsToday: Set<Meal>

    // Suivi avancé
    let disciplineLoads: [DisciplineLoad]
    let weeklyVolumes: [WeeklyVolume]
    let volumeAlerts: [String]
    let bedtimeRegularity: (sd: Double, average: String)?
    let correlations: [Correlation]
    let symptomPatterns: [SymptomPattern]
    let weekStatus: [DayStatus]
    let milestones: [Milestone]
    /// Poids en moyenne mobile 7 jours.
    let weightMA7: [DayValue]
    let hydrationTarget: Double
    let waterToday: Double
    let shoeKm: [(name: String, km: Double)]
    let lifeLoad7: Double
    /// Apports par jour (jours renseignés).
    let nutritionDays: [NutritionDay]

    // Scores quotidiens
    /// Score d'effort du jour (0–21).
    let effortToday: Double
    /// Effort des 30 derniers jours.
    let effortHistory: [DayValue]
    let effortTarget: ClosedRange<Double>
    /// Besoin de sommeil de la nuit à venir.
    let sleepNeed: SleepNeed
    /// Performance de la nuit dernière (sommeil / besoin).
    let lastSleepPerformance: Double?
    let respiratory: RespiratorySignal?
    let respirationSeries: [DayValue]
    let weeklyReport: WeeklyReport?

    var today: LoadPoint? { load.last }

    static func build(profile: AthleteProfile,
                      wellness: [DailyWellness],
                      activities: [CardioActivity],
                      strength: [StrengthWorkout],
                      unavailabilities: [Unavailability],
                      injuries: [Injury],
                      foods: [FoodEntry],
                      planned: [PlannedWorkout],
                      lifeActivities: [LifeActivity] = [],
                      symptoms: [Symptom] = [],
                      shoes: [Shoe] = [],
                      now: Date = .now) -> CoachSnapshot {
        let calendar = Calendar.current
        let thresholds = profile.thresholds
        let todayStart = calendar.startOfDay(for: now)

        // Séances et charge.
        let samples: [ActivitySample] = activities.map { activity in
            let tss = activity.providedTSS ?? TrainingLoad.estimateTSS(
                sport: activity.sport, durationSeconds: activity.durationSeconds,
                normalizedPower: activity.normalizedPower, averagePower: activity.averagePower,
                averageHeartRate: activity.averageHeartRate, rpe: activity.rpe, thresholds: thresholds)
            let intensity = activity.providedIntensity ?? TrainingLoad.intensityFactor(
                sport: activity.sport, normalizedPower: activity.normalizedPower, averagePower: activity.averagePower,
                averageHeartRate: activity.averageHeartRate, thresholds: thresholds)
            return ActivitySample(date: activity.start, sport: activity.sport, durationSeconds: activity.durationSeconds,
                                  tss: tss, intensityFactor: intensity, averagePower: activity.averagePower)
        }
        var items: [(date: Date, tss: Double)] = []
        for sample in samples { items.append((date: sample.date, tss: sample.tss)) }
        for workout in strength {
            let tss: Double = TrainingLoad.estimateTSS(sport: .strength, durationSeconds: workout.durationSeconds, rpe: workout.rpe, thresholds: thresholds)
            items.append((date: workout.start, tss: tss))
        }
        // Charge hors sport : activités physiques déclarées + pas au-delà de 12 000.
        for life in lifeActivities {
            items.append((date: life.date, tss: life.loadEquivalent))
        }
        for record in wellness {
            if let steps = record.steps, steps > 12_000 {
                items.append((date: record.day, tss: (steps - 12_000) / 1000 * 2))
            }
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
        let history: [DayValue] = (0..<60).reversed().compactMap { offset in
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
        var insights: [Insight] = InsightEngine.analyze(insightInput, calendar: calendar)

        // Suivi avancé : discipline, volume, hors sport, sommeil, symptômes, chaussures, hydratation.
        var loadItems: [LoadItem] = []
        for sample in samples {
            let name: String = sample.sport.isCycling ? "Vélo" : (sample.sport == .running ? "Course" : "Autre")
            loadItems.append(LoadItem(date: sample.date, tss: sample.tss, discipline: name))
        }
        var tonnage: [(date: Date, kg: Double)] = []
        for workout in strength {
            let tss: Double = TrainingLoad.estimateTSS(sport: .strength, durationSeconds: workout.durationSeconds, rpe: workout.rpe, thresholds: thresholds)
            loadItems.append(LoadItem(date: workout.start, tss: tss, discipline: "Muscu"))
            var kg: Double = 0
            for set in workout.sets where !set.isWarmup {
                kg += (set.weightKg ?? 0) * Double(set.reps ?? 0)
            }
            tonnage.append((date: workout.start, kg: kg))
        }
        var lifeMinutes: [(date: Date, minutes: Double)] = []
        let weekAgo: Date = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        var lifeLoad7: Double = 0
        var lifeHours7: Double = 0
        var lifeByDay: [Date: Double] = [:]
        for life in lifeActivities {
            loadItems.append(LoadItem(date: life.date, tss: life.loadEquivalent, discipline: "Hors sport"))
            lifeMinutes.append((date: life.date, minutes: Double(life.minutes)))
            lifeByDay[calendar.startOfDay(for: life.date), default: 0] += life.loadEquivalent
            if life.date >= weekAgo {
                lifeLoad7 += life.loadEquivalent
                lifeHours7 += Double(life.minutes) / 60
            }
        }
        let disciplineLoads: [DisciplineLoad] = LoadAnalytics.disciplineLoads(loadItems, today: now, calendar: calendar)

        var volumeSamples: [VolumeSample] = []
        var endurance: [EnduranceQuality] = []
        var rated: [RatedSession] = []
        for (index, activity) in activities.enumerated() {
            volumeSamples.append(VolumeSample(date: activity.start, sport: activity.sport,
                                              seconds: activity.durationSeconds, meters: activity.distanceMeters ?? 0))
            endurance.append(EnduranceQuality(date: activity.start, durationSeconds: activity.durationSeconds,
                                              zoneSeconds: activity.zoneSeconds, decoupling: activity.decouplingPercent))
            if let rpe = activity.rpe {
                rated.append(RatedSession(date: activity.start, rpe: rpe, intensityFactor: samples[index].intensityFactor))
            }
        }
        let weeklyVolumes: [WeeklyVolume] = LoadAnalytics.weeklyVolumes(samples: volumeSamples, tonnage: tonnage,
                                                                         life: lifeMinutes, weeks: 8, today: now)
        let volumeAlerts: [String] = LoadAnalytics.progressionAlerts(weeklyVolumes)

        let twoWeeksAgo: Date = calendar.date(byAdding: .day, value: -14, to: todayStart) ?? todayStart
        var bedtimes: [Date] = []
        for record in sortedWellness where record.day >= twoWeeksAgo {
            if let bedtime = record.bedtime { bedtimes.append(bedtime) }
        }
        let bedtimeRegularity = SleepAnalytics.bedtimeRegularity(bedtimes, calendar: calendar)

        // Chaussures (kilométrage des sorties course).
        var shoeNames: [String: String] = [:]
        var shoeKmByID: [String: Double] = [:]
        for shoe in shoes {
            shoeNames[shoe.shoeID] = shoe.name
            shoeKmByID[shoe.shoeID] = shoe.initialKm
        }
        let defaultShoeID: String? = shoes.first { $0.isDefault && !$0.retired }?.shoeID
        var runsByShoe: [String: Int] = [:]
        for activity in activities where activity.sport == .running {
            guard let id = activity.shoeID ?? defaultShoeID else { continue }
            shoeKmByID[id, default: 0] += (activity.distanceMeters ?? 0) / 1000
            if let name = shoeNames[id] { runsByShoe[name, default: 0] += 1 }
        }
        var shoeKm: [(name: String, km: Double)] = []
        for shoe in shoes where !shoe.retired {
            shoeKm.append((name: shoe.name, km: shoeKmByID[shoe.shoeID] ?? 0))
        }

        // Journal de symptômes.
        var symptomRecords: [SymptomRecord] = []
        var zoneByKey: [String: BodyZone] = [:]
        for symptom in symptoms {
            let day = calendar.startOfDay(for: symptom.date)
            let shoeName: String? = symptom.shoeID.flatMap { shoeNames[$0] }
            zoneByKey[symptom.key] = symptom.zone
            symptomRecords.append(SymptomRecord(date: symptom.date, key: symptom.key, intensity: symptom.intensity,
                                                onsetMinutes: symptom.onsetMinutes, shoe: shoeName,
                                                terrain: symptom.terrain?.label, fatigue: symptom.fatigue,
                                                previousSleep: wellnessByDay[day]?.sleepHours))
        }
        let symptomPatterns: [SymptomPattern] = SymptomAnalysis.patterns(symptomRecords, runsByShoe: runsByShoe, today: now)
        let legZones: Set<BodyZone> = [.foot, .ankle, .calf, .shin, .knee, .hamstring, .quad, .hip, .glute]
        var recurrentLeg: [String] = []
        for pattern in symptomPatterns where pattern.isRecurrent {
            if let zone = zoneByKey[pattern.key], legZones.contains(zone) { recurrentLeg.append(pattern.key) }
        }

        // Hydratation : ~35 ml/kg + 600 ml par heure d'entraînement prévue.
        let hydrationTarget: Double = (currentWeight > 0 ? currentWeight * 35 : 2500) + trainingHours * 600
        let waterToday: Double = wellnessByDay[todayStart]?.waterMl ?? 0
        var waterRatios: [Double] = []
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart),
                  let water = wellnessByDay[day]?.waterMl, water > 0 else { continue }
            waterRatios.append(water / max(hydrationTarget, 1))
        }

        let advanced: [Insight] = AdvancedInsights.analyze(
            disciplineLoads: disciplineLoads,
            volumeAlerts: volumeAlerts,
            lifeLoad7: lifeLoad7,
            lifeHours7: lifeHours7,
            rated: rated,
            bedtimeSD: bedtimeRegularity?.sd,
            averageBedtime: bedtimeRegularity?.average,
            endurance: endurance,
            symptoms: symptomPatterns,
            shoeKm: shoeKm,
            waterRatio7: waterRatios.count >= 3 ? Stats.mean(waterRatios) : nil,
            today: now)
        insights.append(contentsOf: advanced)
        insights.sort { $0.severity > $1.severity }

        // Croisements jour par jour (120 jours).
        var readinessByDay: [Date: Double] = [:]
        for point in history { readinessByDay[point.date] = point.value }
        var rpeByDay: [Date: [Double]] = [:]
        for session in rated { rpeByDay[calendar.startOfDay(for: session.date), default: []].append(Double(session.rpe)) }
        var dayRecords: [DayRecord] = []
        for offset in 0..<120 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            var record = DayRecord(date: day)
            let wellnessDay = wellnessByDay[day]
            record.sleep = wellnessDay?.sleepHours
            record.hrv = useGarmin ? wellnessDay?.hrvRMSSD : wellnessDay?.hrvMs
            record.restingHR = wellnessDay?.restingHeartRate
            record.load = daily[day] ?? 0
            record.lifeLoad = lifeByDay[day] ?? 0
            let nutrition = totalsByDay[day]
            if let nutrition, nutrition.kcal > 800 {
                record.kcal = nutrition.kcal
                record.protein = nutrition.protein
                record.carbs = nutrition.carbs
            }
            record.readiness = readinessByDay[day]
            record.rpe = rpeByDay[day].flatMap { Stats.mean($0) }
            dayRecords.append(record)
        }
        let correlations: [Correlation] = Correlations.analyze(dayRecords)

        // Poids : moyenne mobile 7 jours.
        var weightMA7: [DayValue] = []
        for point in weights {
            let windowStart = point.date.addingTimeInterval(-6 * 86_400)
            let window: [Double] = weights.filter { $0.date >= windowStart && $0.date <= point.date }.map(\.value)
            if let mean = Stats.mean(window) { weightMA7.append(DayValue(date: point.date, value: mean)) }
        }

        // Prévu vs réalisé (semaine en cours) et jalons.
        var bikeDays = Set<Date>()
        var strengthDays = Set<Date>()
        var doneLabels: [Date: [String]] = [:]
        for activity in activities {
            let day = calendar.startOfDay(for: activity.start)
            bikeDays.insert(day)
            doneLabels[day, default: []].append("\(activity.sport.label) \((activity.durationSeconds / 3600).hoursText)")
        }
        for workout in strength {
            let day = calendar.startOfDay(for: workout.start)
            strengthDays.insert(day)
            doneLabels[day, default: []].append(workout.title)
        }
        let weekStatus: [DayStatus] = plan.currentWeek.map {
            PlanTracking.weekStatus(week: $0, bikeDays: bikeDays, strengthDays: strengthDays, doneLabels: doneLabels,
                                    today: now, ftp: thresholds.ftp, calendar: calendar)
        } ?? []
        let milestones: [Milestone] = PlanTracking.milestones(plan: plan)
        // Coach du jour : croisement santé × entraînement × nutrition.
        var sleepDebt: Double = 0
        var nightsCounted = 0
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart),
                  let sleep = wellnessByDay[day]?.sleepHours else { continue }
            sleepDebt += max(0, profile.sleepNeedHours - sleep)
            nightsCounted += 1
        }
        let acuteLoad: Double = load.suffix(7).reduce(0) { $0 + $1.tss } / 7
        let chronicLoad: Double = load.suffix(28).reduce(0) { $0 + $1.tss } / 28
        let yesterdayStart: Date = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        var externalPlan: [PlannedSessionInput] = []
        for workout in plannedToday {
            let minutes: Int = Int((workout.plannedSeconds ?? 3600) / 60)
            externalPlan.append(PlannedSessionInput(name: workout.name, sport: workout.sport, minutes: minutes, tss: workout.plannedTSS))
        }
        var unavailableToday: UnavailabilityReason?
        for item in unavailabilities where calendar.startOfDay(for: item.start) <= todayStart && calendar.startOfDay(for: item.end) >= todayStart {
            unavailableToday = item.reason
        }
        var lastLegs: Date?
        for workout in strength where workout.start <= now {
            var lowerSets = 0
            for session in workout.exerciseSessions {
                let lower = MuscleMap.targets(for: session.exercise).primary.contains { $0.region == .lowerBody }
                if lower { lowerSets += session.workingSets.count }
            }
            if lowerSets >= 3, lastLegs.map({ workout.start > $0 }) ?? true { lastLegs = workout.start }
        }
        // Fréquence respiratoire nocturne : signal précoce de maladie.
        var respirationSeries: [DayValue] = []
        for record in sortedWellness {
            if let value = record.respiration { respirationSeries.append(DayValue(date: record.day, value: value)) }
        }
        let respiratory: RespiratorySignal? = RespiratoryMonitor.signal(respiration: respirationSeries, restingHR: restingHR,
                                                                        today: now, calendar: calendar)
        if let respiratory, respiratory.isWarning {
            var evidence = [String(format: "Respiration nocturne : %.1f resp/min (ta normale : %.1f, %+.1f)", respiratory.latest, respiratory.baseline, respiratory.delta)]
            if respiratory.restingHRUp { evidence.append("FC de repos également au-dessus de ta moyenne") }
            insights.insert(Insight(id: "illness.respiration", category: .recovery,
                                    severity: respiratory.restingHRUp ? .warning : .watch,
                                    title: "Possible début de maladie",
                                    evidence: evidence,
                                    recommendation: "La fréquence respiratoire de nuit est très stable chez toi : une hausse d'1 respiration/min ou plus précède souvent une infection, parfois avant les symptômes. Pas d'intensité, hydrate-toi, dors plus. Repos complet si fièvre ou symptômes sous le cou.",
                                    references: [Science.buchheit2014]), at: 0)
        }

        let coachInput = DailyCoachInput(
            today: now,
            readiness: todayReadiness,
            lastNightSleep: wellnessByDay[todayStart]?.sleepHours,
            sleepNeed: profile.sleepNeedHours,
            sleepDebt7: nightsCounted >= 4 ? sleepDebt : nil,
            load: load.last,
            acuteChronicRatio: chronicLoad > 10 ? acuteLoad / chronicLoad : nil,
            yesterdayNutrition: totalsByDay[yesterdayStart],
            expenditure: macroTargets?.expenditure,
            weightKg: currentWeight,
            week: plan.currentWeek,
            externalPlan: externalPlan,
            ftp: thresholds.ftp,
            injuries: injuryStatuses,
            unavailableToday: unavailableToday,
            lastLegsSession: lastLegs,
            lifeLoadYesterday: lifeByDay[yesterdayStart] ?? 0,
            stepsYesterday: wellnessByDay[yesterdayStart]?.steps,
            recurrentLegSymptoms: recurrentLeg,
            respiratory: respiratory)
        let brief: DailyBrief = DailyCoach.brief(coachInput, calendar: calendar)

        // Score d'effort (0–21) : tout ce qui fatigue, séances + hors sport + pas.
        let effortToday: Double = EffortScore.score(load: daily[todayStart] ?? 0)
        var effortHistory: [DayValue] = []
        for offset in (0..<30).reversed() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            effortHistory.append(DayValue(date: day, value: EffortScore.score(load: daily[day] ?? 0)))
        }
        let effortTarget: ClosedRange<Double> = EffortScore.target(for: todayReadiness?.level, verdict: brief.verdict)

        // Besoin de sommeil de la nuit à venir : effort du jour (fait ou prévu) + dette.
        var plannedLoad: Double = 0
        if doneToday == 0 {
            for session in brief.adapted {
                let hours: Double = Double(session.minutes) / 60
                if session.kind.isStrength { plannedLoad += hours * 45 }
                else if session.kind.isBike { plannedLoad += hours * (session.kind.isIntense ? 70 : 50) }
            }
        }
        let expectedEffort: Double = EffortScore.score(load: (daily[todayStart] ?? 0) + plannedLoad)
        var wakeTimes: [Date] = []
        var bedTimes: [Date] = []
        var sleptHours: [Double] = []
        for record in sortedWellness where record.day >= twoWeeksAgo {
            if let wake = record.wakeTime, let bed = record.bedtime, let slept = record.sleepHours {
                wakeTimes.append(wake)
                bedTimes.append(bed)
                sleptHours.append(slept)
            }
        }
        let sleepNeed: SleepNeed = SleepCoach.need(base: profile.sleepNeedHours, effortToday: expectedEffort, debt7: sleepDebt,
                                                   wakeTimes: wakeTimes, bedTimes: bedTimes, sleptHours: sleptHours, calendar: calendar)
        let yesterdayEffort: Double = EffortScore.score(load: daily[yesterdayStart] ?? 0)
        let lastNightNeed: Double = profile.sleepNeedHours + max(0, yesterdayEffort - 10) * 4 / 60
        let lastSleepPerformance: Double? = wellnessByDay[todayStart]?.sleepHours.map {
            SleepCoach.performance(slept: $0, need: lastNightNeed)
        }

        // Bilan hebdomadaire : 7 derniers jours vs 7 précédents.
        var trainingByDay: [Date: Double] = [:]
        for activity in activities { trainingByDay[calendar.startOfDay(for: activity.start), default: 0] += activity.durationSeconds }
        for workout in strength { trainingByDay[calendar.startOfDay(for: workout.start), default: 0] += workout.durationSeconds }
        var reportDays: [WeeklyReportBuilder.Day] = []
        for offset in 1...14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart) else { continue }
            let previousDay: Date = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let previousEffort: Double = EffortScore.score(load: daily[previousDay] ?? 0)
            var reportDay = WeeklyReportBuilder.Day(date: day, sleepNeed: profile.sleepNeedHours + max(0, previousEffort - 10) * 4 / 60)
            reportDay.recovery = readinessByDay[day]
            reportDay.load = daily[day] ?? 0
            reportDay.effort = EffortScore.score(load: reportDay.load)
            reportDay.sleep = wellnessByDay[day]?.sleepHours
            reportDay.trainingSeconds = trainingByDay[day] ?? 0
            if let nutrition = totalsByDay[day], nutrition.kcal > 800 {
                reportDay.kcal = nutrition.kcal
                reportDay.protein = nutrition.protein
            }
            reportDay.weight = wellnessByDay[day]?.weightKg
            reportDays.append(reportDay)
        }
        let weeklyReport: WeeklyReport? = WeeklyReportBuilder.build(days: reportDays.sorted { $0.date < $1.date }, today: now, calendar: calendar)

        let tomorrow: Date = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        var tomorrowWeek: PlannedWeek? = plan.currentWeek
        for week in plan.weeks where week.start <= tomorrow {
            tomorrowWeek = week
        }
        let tomorrowPlan: [SessionPrescription] = tomorrowWeek.map {
            DailyCoach.template(for: $0, weekday: calendar.component(.weekday, from: tomorrow), ftp: thresholds.ftp)
        } ?? []

        var loggedMeals = Set<Meal>()
        for entry in foods where calendar.isDate(entry.date, inSameDayAs: now) {
            loggedMeals.insert(entry.meal)
        }

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
            todayAdvice: brief.headline,
            brief: brief,
            tomorrowPlan: tomorrowPlan,
            loggedMealsToday: loggedMeals,
            disciplineLoads: disciplineLoads,
            weeklyVolumes: weeklyVolumes,
            volumeAlerts: volumeAlerts,
            bedtimeRegularity: bedtimeRegularity,
            correlations: correlations,
            symptomPatterns: symptomPatterns,
            weekStatus: weekStatus,
            milestones: milestones,
            weightMA7: weightMA7,
            hydrationTarget: hydrationTarget,
            waterToday: waterToday,
            shoeKm: shoeKm,
            lifeLoad7: lifeLoad7,
            nutritionDays: nutritionDays,
            effortToday: effortToday,
            effortHistory: effortHistory,
            effortTarget: effortTarget,
            sleepNeed: sleepNeed,
            lastSleepPerformance: lastSleepPerformance,
            respiratory: respiratory,
            respirationSeries: respirationSeries,
            weeklyReport: weeklyReport)
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
