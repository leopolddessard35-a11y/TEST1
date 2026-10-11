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
    /// FC de repos d'une seule source sur tout l'historique (Garmin si ≥ 14 valeurs sur 60 j, sinon Apple Santé).
    let restingHRSeries: [DayValue]
    let restingHRSource: String
    /// Durée de sommeil : nuit Apple Santé (cohérente avec coucher, réveil, stades) quand elle existe, sinon Garmin.
    let sleepSource: String
    /// Source de `respirationSeries` (même règle que la FC de repos).
    let respirationSource: String
    let macroTargets: MacroTargets?
    let todayNutrition: NutritionDay
    let plannedToday: [PlannedWorkout]
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
    /// La semaine organisée : séances du plan, jours choisis, ce qui est fait (nil sans plan de saison).
    let weekPlan: WeekPlan?
    /// La semaine suivante, pour s'organiser à l'avance.
    let nextWeekPlan: WeekPlan?
    let milestones: [Milestone]
    /// Poids en moyenne mobile 7 jours.
    let weightMA7: [DayValue]
    /// Objectif d'eau du jour et eau bue (conservés pour l'affichage ; plus d'alerte hydratation).
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
    /// Score de sommeil de la nuit dernière (durée, efficacité, stades, régularité).
    let lastSleepScore: SleepScoreResult?
    /// Dette de sommeil sur 14 jours (heures, nuits anciennes moins pondérées).
    let sleepDebt: Double
    let respiratory: RespiratorySignal?
    let respirationSeries: [DayValue]
    let weeklyReport: WeeklyReport?
    let weeklyReview: WeeklyReport.Review?

    // Qualité et contexte
    /// Score de confiance du jour (sources présentes).
    let confidence: DataConfidence
    /// Événements à annoter sur les courbes (maladie, voyage, travaux, chaussures, blessure).
    let chartEvents: [ChartEvent]
    /// Efficiency Factor des sorties d'endurance comparables (Z2, ≥ 45 min, peu de dénivelé).
    let efSeries: [DayValue]
    /// Charge sRPE (RPE × minutes) des 7 derniers jours.
    let srpeWeek: Double
    let monotony: Double?

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
                      baselines: [PlanBaseline] = [],
                      placements: [SessionPlacement] = [],
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
        var restingApple: [DayValue] = []
        var restingGarmin: [DayValue] = []
        var respirationApple: [DayValue] = []
        var respirationGarmin: [DayValue] = []
        var wellnessByDay: [Date: DailyWellness] = [:]
        // Durée de sommeil effective : nuit Apple Santé si elle existe (cohérente avec coucher, réveil et
        // stades, siestes exclues), sinon durée Garmin. Tous les calculs du coach passent par `sleepByDay`.
        var sleepByDay: [Date: Double] = [:]
        var appleNights = 0
        var garminNights = 0
        for record in sortedWellness {
            if let value = record.hrvRMSSD { rmssd.append(DayValue(date: record.day, value: value)) }
            if let value = record.hrvMs { sdnn.append(DayValue(date: record.day, value: value)) }
            if let value = record.restingHeartRate { restingApple.append(DayValue(date: record.day, value: value)) }
            if let value = record.restingHeartRateGarmin { restingGarmin.append(DayValue(date: record.day, value: value)) }
            if let value = record.respiration { respirationApple.append(DayValue(date: record.day, value: value)) }
            if let value = record.respirationGarmin { respirationGarmin.append(DayValue(date: record.day, value: value)) }
            if let hours = record.sleepHours {
                sleepByDay[record.day] = hours
                appleNights += 1
            } else if let hours = record.sleepHoursGarmin {
                sleepByDay[record.day] = hours
                garminNights += 1
            }
            wellnessByDay[record.day] = record
        }
        let recentRMSSD = Stats.lastDays(60, of: rmssd, today: now, calendar: calendar).count
        let recentSDNN = Stats.lastDays(60, of: sdnn, today: now, calendar: calendar).count
        let useGarmin = recentRMSSD >= 14
        let hrvSeries: [DayValue] = useGarmin ? rmssd : sdnn
        let hrvSource = useGarmin ? "Garmin (rMSSD nocturne)" : "Apple Santé (SDNN)"

        // FC de repos et respiration : UNE source sur tout l'historique (même règle que la VFC),
        // jamais de mélange jour par jour entre deux capteurs qui ne mesurent pas pareil.
        let useGarminRHR = Stats.lastDays(60, of: restingGarmin, today: now, calendar: calendar).count >= 14
        let restingHR: [DayValue] = useGarminRHR ? restingGarmin : restingApple
        let restingHRSource = useGarminRHR ? "Garmin" : "Apple Santé"
        var restingByDay: [Date: Double] = [:]
        for point in restingHR { restingByDay[point.date] = point.value }
        let useGarminRespiration = Stats.lastDays(60, of: respirationGarmin, today: now, calendar: calendar).count >= 14
        let respirationSeries: [DayValue] = useGarminRespiration ? respirationGarmin : respirationApple
        let respirationSource = useGarminRespiration ? "Garmin" : "Apple Santé"
        let sleepSource: String = garminNights == 0 ? "Apple Santé"
            : (appleNights == 0 ? "Garmin" : "Apple Santé (Garmin pour les nuits absentes)")

        // Score de sommeil de chaque nuit (durée, efficacité, stades, régularité).
        func sleepScore(on day: Date) -> SleepScoreResult? {
            guard let record = wellnessByDay[day], let hours = sleepByDay[day] else { return nil }
            var priorBedtimes: [Double] = []
            for offset in 1...14 {
                if let previous = calendar.date(byAdding: .day, value: -offset, to: day),
                   let bed = wellnessByDay[previous]?.bedtime {
                    priorBedtimes.append(SleepAnalytics.eveningMinutes(bed, calendar: calendar))
                }
            }
            let previousDay: Date = calendar.date(byAdding: .day, value: -1, to: day) ?? day
            let need: Double = profile.sleepNeedHours + max(0, EffortScore.score(load: daily[previousDay] ?? 0) - 10) * 4 / 60
            let usual: Double? = priorBedtimes.count >= 5 ? Robust.median(priorBedtimes) : nil
            return SleepScoreCalculator.compute(asleepHours: hours, needHours: need, bedtime: record.bedtime, wake: record.wakeTime,
                                                deepHours: record.sleepDeepHours, remHours: record.sleepREMHours,
                                                awakeHours: record.sleepAwakeHours, usualBedtimeMinutes: usual, calendar: calendar)
        }

        func readiness(on day: Date) -> ReadinessResult? {
            ReadinessCalculator.compute(
                hrv: hrvSeries, restingHR: restingHR,
                lastNightSleepHours: sleepByDay[day],
                sleepNeedHours: profile.sleepNeedHours,
                form: loadByDay[day]?.form, sleepScore: sleepScore(on: day), today: day, calendar: calendar)
        }
        let lastSleepScore: SleepScoreResult? = sleepScore(on: todayStart)
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
        // Fatigue accumulée : forme < −25 au moins 5 jours sur 7, ou VFC et FC de repos dégradées ensemble.
        let tiredDays: Int = load.suffix(7).filter { $0.form < -25 }.count
        let hrvScore: Double = todayReadiness?.components.first { $0.name == "VFC" }?.score ?? 60
        let rhrScore: Double = todayReadiness?.components.first { $0.name == "FC au repos" }?.score ?? 60
        let fatigueDetected: Bool = tiredDays >= 5 || (hrvScore < 38 && rhrScore < 45)
        let plannerInput = PlannerInput(
            today: now,
            raceDate: profile.raceDate,
            raceName: profile.raceName,
            currentCTL: currentCTL,
            targetRaceCTL: profile.targetRaceCTL,
            weeklyHoursAvailable: profile.weeklyHoursAvailable,
            strengthSessionsPerWeek: profile.strengthSessionsPerWeek,
            unavailabilities: periods,
            injuries: injuryStatuses,
            fatigueDetected: fatigueDetected)
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
            insightWellness.append(WellnessSample(date: record.day, sleepHours: sleepByDay[record.day], hrv: hrv,
                                                  restingHR: restingByDay[record.day], weightKg: record.weightKg))
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
                                                previousSleep: sleepByDay[day],
                                                previousLoad: calendar.date(byAdding: .day, value: -1, to: day).flatMap { daily[$0] }))
        }
        let symptomPatterns: [SymptomPattern] = SymptomAnalysis.patterns(symptomRecords, runsByShoe: runsByShoe, today: now)
        let legZones: Set<BodyZone> = [.foot, .ankle, .calf, .shin, .knee, .hamstring, .quad, .hip, .glute]
        var recurrentLeg: [String] = []
        for pattern in symptomPatterns where pattern.isRecurrent {
            if let zone = zoneByKey[pattern.key], legZones.contains(zone) { recurrentLeg.append(pattern.key) }
        }

        // Hydratation : ~35 ml/kg + 600 ml par heure d'entraînement prévue (affichage seulement).
        let hydrationTarget: Double = (currentWeight > 0 ? currentWeight * 35 : 2500) + trainingHours * 600
        let waterToday: Double = wellnessByDay[todayStart]?.waterMl ?? 0

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
            record.sleep = sleepByDay[day]
            record.hrv = useGarmin ? wellnessDay?.hrvRMSSD : wellnessDay?.hrvMs
            record.restingHR = restingByDay[day]
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

        // Organisation de la semaine : séances du plan, jours choisis à la main, séances faites reconnues par type.
        var doneSessions: [DoneSession] = []
        for (index, activity) in activities.enumerated() {
            let minutes = Int(activity.durationSeconds / 60)
            if activity.sport == .strength {
                doneSessions.append(DoneSession(id: "cardio-\(activity.externalID)", date: activity.start, title: activity.title,
                                                symbol: "dumbbell.fill", minutes: minutes, isStrength: true, isIntense: false))
                continue
            }
            let intense = (samples[index].intensityFactor ?? 0) >= 0.82 || (activity.rpe ?? 0) >= 7
            doneSessions.append(DoneSession(id: "cardio-\(activity.externalID)", date: activity.start, title: activity.title,
                                            symbol: activity.sport.symbol, minutes: minutes, isStrength: false, isIntense: intense))
        }
        for workout in strength {
            var lowerSets = 0
            for session in workout.exerciseSessions
            where MuscleMap.targets(for: session.exercise).primary.contains(where: { $0.region == .lowerBody }) {
                lowerSets += session.workingSets.count
            }
            doneSessions.append(DoneSession(id: "muscu-\(workout.externalID)", date: workout.start, title: workout.title,
                                            symbol: "dumbbell.fill", minutes: Int(workout.durationSeconds / 60),
                                            isStrength: true, isIntense: false, isLegs: lowerSets >= 3))
        }
        func organize(_ week: PlannedWeek) -> WeekPlan {
            let weekStart = calendar.startOfDay(for: week.start)
            var pinned: [String: Date] = [:]
            var removed = Set<String>()
            for placement in placements where calendar.isDate(placement.weekStart, inSameDayAs: weekStart) {
                if let day = placement.day { pinned[placement.slot] = day } else { removed.insert(placement.slot) }
            }
            let habits = TrainingHabits.learn(from: doneSessions, before: weekStart, calendar: calendar)
            return WeekPlanner.make(week: week, ftp: thresholds.ftp, done: doneSessions, habits: habits,
                                    pinned: pinned, removed: removed, unavailable: periods,
                                    availableMinutes: { profile.availableMinutes(weekday: $0) }, now: now, calendar: calendar)
        }
        let weekPlan: WeekPlan? = plan.currentWeek.map(organize)
        let nextWeekPlan: WeekPlan? = plan.weeks.dropFirst().first.map(organize)
        let milestones: [Milestone] = PlanTracking.milestones(plan: plan)
        // Coach du jour : croisement santé × entraînement × nutrition.
        var nights: [(daysAgo: Int, hours: Double)] = []
        for offset in 0..<14 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart),
                  let sleep = sleepByDay[day] else { continue }
            nights.append((daysAgo: offset, hours: sleep))
        }
        let nightsCounted: Int = nights.filter { $0.daysAgo < 7 }.count
        // Dette sur 14 jours, les nuits anciennes pesant moins (× 0,85 par jour).
        let sleepDebt: Double = Robust.decayedSleepDebt(need: profile.sleepNeedHours, sleeps: nights)
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
        // Fréquence respiratoire nocturne : signal précoce de maladie (série d'une seule source, voir plus haut).
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

        let yesterdayEffort: Double = EffortScore.score(load: daily[yesterdayStart] ?? 0)
        let lastNightNeed: Double = profile.sleepNeedHours + max(0, yesterdayEffort - 10) * 4 / 60
        let lastSleepPerformance: Double? = sleepByDay[todayStart].map {
            SleepCoach.performance(slept: $0, need: lastNightNeed)
        }

        // Tendance VFC 7 j vs base 60 j (médiane / MAD sur le ln).
        let hrvTrend: (deltaPercent: Double, z: Double)? = {
            let base: [Double] = Stats.lastDays(60, of: hrvSeries, today: now, calendar: calendar).filter { $0.value > 0 }.map { log($0.value) }
            let week: [Double] = Stats.lastDays(7, of: hrvSeries, today: now, calendar: calendar).filter { $0.value > 0 }.map { log($0.value) }
            guard base.count >= 14, let weekMean = Stats.mean(week), let center = Robust.median(base) else { return nil }
            let spread = max(Robust.mad(base) ?? 0, 0.05)
            return ((exp(weekMean - center) - 1) * 100, (weekMean - center) / spread)
        }()
        // Douleur déclarée aujourd'hui dans le journal.
        var painToday: String?
        for symptom in symptoms where calendar.isDate(symptom.date, inSameDayAs: now) && symptom.type == .pain && symptom.intensity >= 4 {
            painToday = "douleur \(symptom.zone.label.lowercased()) \(symptom.intensity)/10"
        }

        let coachInput = DailyCoachInput(
            today: now,
            readiness: todayReadiness,
            lastNightSleep: sleepByDay[todayStart],
            sleepNeed: profile.sleepNeedHours,
            sleepDebt7: nightsCounted >= 4 ? sleepDebt : nil,
            load: load.last,
            acuteChronicRatio: Robust.acuteChronicRatio(load.map(\.tss)),
            yesterdayNutrition: totalsByDay[yesterdayStart],
            expenditure: macroTargets?.expenditure,
            weightKg: currentWeight,
            week: plan.currentWeek,
            externalPlan: externalPlan,
            scheduledToday: weekPlan.map { plan in plan.items(on: todayStart).filter(\.isPending).map(\.session) },
            ftp: thresholds.ftp,
            injuries: injuryStatuses,
            unavailableToday: unavailableToday,
            lastLegsSession: lastLegs,
            lifeLoadYesterday: lifeByDay[yesterdayStart] ?? 0,
            stepsYesterday: wellnessByDay[yesterdayStart]?.steps,
            recurrentLegSymptoms: recurrentLeg,
            respiratory: respiratory,
            hrvDeltaPercent: hrvTrend?.deltaPercent,
            hrvZ: hrvTrend?.z,
            sleepPerformance: lastSleepPerformance,
            painToday: painToday,
            availableMinutesToday: profile.availableMinutes(weekday: calendar.component(.weekday, from: now)))
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
        // Horaires : uniquement les nuits Apple Santé, avec leur propre durée (coucher, réveil et durée de la même nuit).
        for record in sortedWellness where record.day >= twoWeeksAgo {
            if let wake = record.wakeTime, let bed = record.bedtime, let slept = record.sleepHours {
                wakeTimes.append(wake)
                bedTimes.append(bed)
                sleptHours.append(slept)
            }
        }
        let sleepNeed: SleepNeed = SleepCoach.need(base: profile.sleepNeedHours, effortToday: expectedEffort, debt7: sleepDebt,
                                                   wakeTimes: wakeTimes, bedTimes: bedTimes, sleptHours: sleptHours, calendar: calendar)

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
            reportDay.sleep = sleepByDay[day]
            reportDay.trainingSeconds = trainingByDay[day] ?? 0
            if let nutrition = totalsByDay[day], nutrition.kcal > 800 {
                reportDay.kcal = nutrition.kcal
                reportDay.protein = nutrition.protein
            }
            reportDay.weight = wellnessByDay[day]?.weightKg
            reportDays.append(reportDay)
        }
        let weeklyReport: WeeklyReport? = WeeklyReportBuilder.build(days: reportDays.sorted { $0.date < $1.date }, today: now, calendar: calendar)

        // Demain : les séances placées par l'organisateur (cette semaine ou la suivante).
        let tomorrow: Date = calendar.date(byAdding: .day, value: 1, to: todayStart) ?? todayStart
        let tomorrowWeekPlan: WeekPlan? = (weekPlan?.contains(tomorrow) ?? false) ? weekPlan : nextWeekPlan
        let tomorrowPlan: [SessionPrescription] = tomorrowWeekPlan.map { plan in
            plan.items(on: tomorrow).filter(\.isPending).map(\.session)
        } ?? []

        // Score de confiance du jour : quelles sources sont présentes ?
        var present: [String] = []
        var missing: [String] = []
        let todayWellness = wellnessByDay[todayStart]
        func check(_ name: String, _ ok: Bool) { if ok { present.append(name) } else { missing.append(name) } }
        check("Sommeil", sleepByDay[todayStart] != nil)
        check("VFC", (useGarmin ? todayWellness?.hrvRMSSD : todayWellness?.hrvMs) != nil
              || !Stats.lastDays(2, of: hrvSeries, today: now, calendar: calendar).isEmpty)
        check("FC repos", !Stats.lastDays(2, of: restingHR, today: now, calendar: calendar).isEmpty)
        check("Séances synchronisées", !activities.isEmpty || !strength.isEmpty)
        check("Repas d'hier", (totalsByDay[yesterdayStart]?.kcal ?? 0) > 800)
        let confidence = DataConfidence(present: present, missing: missing)

        // Événements pour annoter les courbes.
        var chartEvents: [ChartEvent] = []
        for item in unavailabilities {
            chartEvents.append(ChartEvent(start: item.start, end: item.end, label: item.reason.label, symbol: item.reason.symbol))
        }
        for life in lifeActivities where life.minutes >= 120 {
            chartEvents.append(ChartEvent(start: life.date, end: life.date, label: life.kind.label, symbol: life.kind.symbol))
        }
        for injury in injuries {
            chartEvents.append(ChartEvent(start: injury.start, end: injury.resolvedAt ?? injury.start, label: "Blessure : \(injury.title)", symbol: "bandage.fill"))
        }
        for shoe in shoes {
            chartEvents.append(ChartEvent(start: shoe.addedAt, end: shoe.addedAt, label: "Chaussures : \(shoe.name)", symbol: "shoeprints.fill"))
        }

        // Efficiency Factor à conditions comparables : endurance stable, ≥ 45 min, < 15 m de D+ par km.
        var efByDay: [Date: [Double]] = [:]
        for (index, activity) in activities.enumerated() {
            guard activity.durationSeconds >= 45 * 60, (samples[index].intensityFactor ?? 0.7) < 0.85 else { continue }
            if let elevation = activity.elevationGain, let meters = activity.distanceMeters, meters > 0, elevation / (meters / 1000) > 15 { continue }
            if let ef = Robust.efficiencyFactor(sport: activity.sport, normalizedPower: activity.normalizedPower,
                                                averagePower: activity.averagePower, meters: activity.distanceMeters,
                                                seconds: activity.durationSeconds, averageHeartRate: activity.averageHeartRate),
               activity.sport.isCycling {
                efByDay[calendar.startOfDay(for: activity.start), default: []].append(ef)
            }
        }
        let efSeries: [DayValue] = efByDay.keys.sorted().compactMap { day in
            Stats.mean(efByDay[day] ?? []).map { DayValue(date: day, value: $0) }
        }

        // sRPE (RPE × minutes) et monotonie de Foster sur 7 jours.
        var srpeWeek: Double = 0
        for activity in activities where activity.start >= weekAgo {
            if let rpe = activity.rpe { srpeWeek += Double(rpe) * activity.durationSeconds / 60 }
        }
        for workout in strength where workout.start >= weekAgo {
            if let rpe = workout.rpe { srpeWeek += Double(rpe) * workout.durationSeconds / 60 }
        }
        let last7Loads: [Double] = load.suffix(7).map(\.tss)
        var monotony: Double?
        if let mean = Stats.mean(last7Loads), let sd = Stats.standardDeviation(last7Loads), sd > 0 { monotony = mean / sd }

        // Alerte déficit : la tendance du poids baisse alors que la charge monte.
        let recentWeightTrend: [DayValue] = Stats.exponentialTrend(Stats.lastDays(21, of: weights, today: now, calendar: calendar))
        if let first = recentWeightTrend.first, let last = recentWeightTrend.last, recentWeightTrend.count >= 8,
           last.value - first.value <= -0.5, let ramp = TrainingLoad.rampRate(load), ramp > 2 {
            insights.insert(Insight(id: "nutrition.deficit", category: .nutrition, severity: .warning,
                                    title: "Déficit énergétique probable",
                                    evidence: [String(format: "Poids lissé : %.1f kg en 3 semaines", last.value - first.value),
                                               String(format: "Condition : %+.1f points sur 7 j", ramp)],
                                    recommendation: "Ton poids baisse pendant que ta charge monte : apports en dessous de ta dépense. Ajoute 300 à 400 kcal par jour, surtout en glucides autour des séances.",
                                    references: [Science.mountjoy2018, Science.hall2008]), at: 0)
        }

        // Journée physique probablement sous-déclarée : beaucoup de pas / d'énergie active, rien de déclaré.
        if let yesterday = wellnessByDay[yesterdayStart] {
            let activeValues: [Double] = Stats.lastDays(30, of: activeEnergy, today: now, calendar: calendar).map(\.value)
            let activeHigh: Bool = {
                guard let active = yesterday.activeEnergyKcal, let center = Robust.median(activeValues),
                      let spread = Robust.mad(activeValues), spread > 0 else { return false }
                return (active - center) / spread > 2.5
            }()
            let declared: Bool = lifeActivities.contains { calendar.isDate($0.date, inSameDayAs: yesterdayStart) }
            let trained: Double = trainingByDay[yesterdayStart] ?? 0
            if !declared, trained < 3600, (yesterday.steps ?? 0) > 18_000 || activeHigh {
                insights.insert(Insight(id: "life.undeclared", category: .data, severity: .info,
                                        title: "Journée physique non déclarée ?",
                                        evidence: [String(format: "Hier : %.0f pas, %.0f kcal actives, sans séance ni activité hors sport déclarée",
                                                          yesterday.steps ?? 0, yesterday.activeEnergyKcal ?? 0)],
                                        recommendation: "Si tu as fait des travaux ou une journée debout, ajoute-la dans Journal → Hors sport : elle compte dans ta fatigue.",
                                        references: []), at: 0)
            }
        }

        // Revue hebdomadaire : prévu vs réalisé.
        var plannedLastWeek: Double?
        if let lastWeekStart = calendar.date(byAdding: .day, value: -7, to: plan.currentWeek?.start ?? todayStart) {
            plannedLastWeek = baselines.first { calendar.isDate($0.weekStart, inSameDayAs: lastWeekStart) }?.targetHours
        }
        let doneStrength: Int = strength.filter { $0.start >= weekAgo }.count
        let missed: Int = weekPlan?.droppedCount ?? 0
        let weeklyReview: WeeklyReport.Review? = weeklyReport.map {
            WeeklyReport.review(report: $0, plannedHours: plannedLastWeek, plannedStrength: profile.strengthSessionsPerWeek,
                                doneStrength: doneStrength, acuteChronic: Robust.acuteChronicRatio(load.map(\.tss)),
                                missedSessions: missed)
        }

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
            restingHRSeries: restingHR,
            restingHRSource: restingHRSource,
            sleepSource: sleepSource,
            respirationSource: respirationSource,
            macroTargets: macroTargets,
            todayNutrition: todayNutrition,
            plannedToday: plannedToday,
            brief: brief,
            tomorrowPlan: tomorrowPlan,
            loggedMealsToday: loggedMeals,
            disciplineLoads: disciplineLoads,
            weeklyVolumes: weeklyVolumes,
            volumeAlerts: volumeAlerts,
            bedtimeRegularity: bedtimeRegularity,
            correlations: correlations,
            symptomPatterns: symptomPatterns,
            weekPlan: weekPlan,
            nextWeekPlan: nextWeekPlan,
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
            lastSleepScore: lastSleepScore,
            sleepDebt: sleepDebt,
            respiratory: respiratory,
            respirationSeries: respirationSeries,
            weeklyReport: weeklyReport,
            weeklyReview: weeklyReview,
            confidence: confidence,
            chartEvents: chartEvents.sorted { $0.start < $1.start },
            efSeries: efSeries,
            srpeWeek: srpeWeek,
            monotony: monotony)
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
