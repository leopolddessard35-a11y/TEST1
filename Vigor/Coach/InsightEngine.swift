import Foundation

/// Une observation du coach : ce que disent tes données, pourquoi c'est important, quoi faire.
struct Insight: Identifiable, Equatable {
    enum Severity: Int, Comparable {
        case positive = 0, info = 1, watch = 2, warning = 3

        static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

        var label: String {
            switch self {
            case .positive: "Bon signal"
            case .info: "À savoir"
            case .watch: "À surveiller"
            case .warning: "Alerte"
            }
        }

        var symbol: String {
            switch self {
            case .positive: "checkmark.seal.fill"
            case .info: "info.circle.fill"
            case .watch: "eye.fill"
            case .warning: "exclamationmark.triangle.fill"
            }
        }
    }

    enum Category: String, CaseIterable {
        case recovery, sleep, load, strength, nutrition, data

        var label: String {
            switch self {
            case .recovery: "Récupération"
            case .sleep: "Sommeil"
            case .load: "Charge"
            case .strength: "Musculation"
            case .nutrition: "Nutrition"
            case .data: "Qualité des données"
            }
        }
    }

    let id: String
    let category: Category
    let severity: Severity
    let title: String
    /// Les chiffres qui justifient l'observation.
    let evidence: [String]
    let recommendation: String
    let references: [Reference]
}

struct WellnessSample: Equatable {
    let date: Date
    var sleepHours: Double?
    var hrv: Double?
    var restingHR: Double?
    var weightKg: Double?
}

struct ActivitySample: Equatable {
    let date: Date
    let sport: Sport
    let durationSeconds: Double
    let tss: Double
    /// Intensité relative au seuil (puissance/FTP ou FC/FC seuil).
    let intensityFactor: Double?
    let averagePower: Double?
}

struct NutritionDay: Equatable {
    let date: Date
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

struct InsightInput {
    var today: Date
    var wellness: [WellnessSample]
    var hrvSourcesMixed = false
    var load: [LoadPoint]
    var activities: [ActivitySample]
    var strength: [ExerciseSession]
    var nutrition: [NutritionDay]
    var weightKg: Double
    var ftp: Double?
    var sleepNeedHours: Double
    var phase: TrainingPhase?
    var readiness: ReadinessResult?
}

/// Le « cerveau critique » : passe tes données au crible de règles issues de la littérature scientifique.
/// Chaque règle est indépendante, explicable et testée.
enum InsightEngine {
    static func analyze(_ input: InsightInput, calendar: Calendar = .current) -> [Insight] {
        var insights: [Insight] = []
        insights += recovery(input, calendar: calendar)
        insights += sleep(input, calendar: calendar)
        insights += load(input, calendar: calendar)
        insights += intensityDistribution(input, calendar: calendar)
        insights += strength(input, calendar: calendar)
        insights += nutrition(input, calendar: calendar)
        insights += dataQuality(input, calendar: calendar)
        return insights.sorted { $0.severity > $1.severity }
    }

    // MARK: Récupération (VFC + FC repos)

    static func recovery(_ input: InsightInput, calendar: Calendar) -> [Insight] {
        let hrv = input.wellness.compactMap { sample in sample.hrv.map { DayValue(date: sample.date, value: log($0)) } }
        let rhr = input.wellness.compactMap { sample in sample.restingHR.map { DayValue(date: sample.date, value: $0) } }
        let baseline = Stats.lastDays(60, of: hrv, today: input.today, calendar: calendar).map(\.value)
        let week = Stats.lastDays(7, of: hrv, today: input.today, calendar: calendar).map(\.value)
        guard baseline.count >= 21, week.count >= 4,
              let mean = Stats.mean(baseline), let sd = Stats.standardDeviation(baseline),
              let weekMean = Stats.mean(week) else { return [] }

        // Plus petit changement significatif = 0,5 écart-type (Buchheit 2014).
        let swc = 0.5 * sd
        let delta = weekMean - mean
        let rhrBaseline = Stats.lastDays(60, of: rhr, today: input.today, calendar: calendar).map(\.value)
        let rhrWeek = Stats.lastDays(7, of: rhr, today: input.today, calendar: calendar).map(\.value)
        let rhrDelta = (Stats.mean(rhrWeek) ?? 0) - (Stats.mean(rhrBaseline) ?? 0)
        let rhrSD = Stats.standardDeviation(rhrBaseline) ?? 2

        var evidence = [
            String(format: "VFC moyenne 7 j : %.0f ms (normale : %.0f–%.0f ms)", exp(weekMean), exp(mean - swc), exp(mean + swc)),
            String(format: "Écart : %+.1f %% par rapport à ta moyenne de 60 j", (exp(delta) - 1) * 100),
        ]
        if !rhrWeek.isEmpty {
            evidence.append(String(format: "FC repos 7 j : %+.1f bpm par rapport à ta moyenne", rhrDelta))
        }
        let references = [Science.plews2013, Science.buchheit2014, Science.kiviniemi2007]

        if delta < -swc && rhrDelta > rhrSD {
            return [Insight(id: "recovery.overreaching", category: .recovery, severity: .warning,
                            title: "Signes de fatigue accumulée",
                            evidence: evidence,
                            recommendation: "VFC en baisse ET FC de repos en hausse sur une semaine : c'est le schéma typique du surmenage. Allège 3 à 5 jours (endurance très facile, pas d'intensité), soigne le sommeil, vérifie l'absence de maladie.",
                            references: references)]
        }
        if delta < -swc {
            return [Insight(id: "recovery.low", category: .recovery, severity: .watch,
                            title: "VFC sous ta zone normale",
                            evidence: evidence,
                            recommendation: "VFC sous ta zone normale : séance clé seulement si les sensations suivent, sinon intensité décalée de 48 h.",
                            references: references)]
        }
        if delta > swc {
            return [Insight(id: "recovery.high", category: .recovery, severity: .positive,
                            title: "VFC au-dessus de ta normale",
                            evidence: evidence,
                            recommendation: "Bonne adaptation : c'est le bon moment pour placer les séances les plus exigeantes de la semaine.",
                            references: references)]
        }
        return []
    }

    // MARK: Sommeil

    static func sleep(_ input: InsightInput, calendar: Calendar) -> [Insight] {
        let sleep = input.wellness.compactMap { sample in sample.sleepHours.map { DayValue(date: sample.date, value: $0) } }
        let week = Stats.lastDays(7, of: sleep, today: input.today, calendar: calendar).map(\.value)
        guard week.count >= 4, let average = Stats.mean(week) else { return [] }

        var insights: [Insight] = []
        let debt = week.reduce(0) { $0 + max(0, input.sleepNeedHours - $1) }
        let evidence = [
            String(format: "Moyenne 7 nuits : %.1f h (besoin : %.1f h)", average, input.sleepNeedHours),
            String(format: "Dette de sommeil sur 7 j : %.1f h", debt),
        ]
        if debt >= 5 || average < 7 {
            insights.append(Insight(id: "sleep.debt", category: .sleep, severity: debt >= 7 ? .warning : .watch,
                                    title: "Dette de sommeil",
                                    evidence: evidence,
                                    recommendation: "Le sommeil est ton premier levier de récupération et de prise de muscle. Vise +30 à 60 min par nuit cette semaine (coucher plus tôt, sieste de 20 min après une grosse séance).",
                                    references: [Science.hirshkowitz2015, Science.milewski2014, Science.mah2011]))
        } else if average >= input.sleepNeedHours {
            insights.append(Insight(id: "sleep.good", category: .sleep, severity: .positive,
                                    title: "Sommeil suffisant",
                                    evidence: evidence,
                                    recommendation: "Continue : tu couvres ton besoin de sommeil.",
                                    references: [Science.hirshkowitz2015]))
        }

        if let sd = Stats.standardDeviation(week), sd > 1 {
            insights.append(Insight(id: "sleep.irregular", category: .sleep, severity: .watch,
                                    title: "Durée de sommeil irrégulière",
                                    evidence: [String(format: "Écart-type sur 7 nuits : %.1f h", sd)],
                                    recommendation: "Des nuits très variables perturbent l'horloge biologique même si la moyenne est bonne. Essaie de garder des horaires de coucher et de lever stables (±30 min).",
                                    references: [Science.phillips2017]))
        }
        return insights
    }

    // MARK: Charge d'entraînement

    static func load(_ input: InsightInput, calendar: Calendar) -> [Insight] {
        var insights: [Insight] = []
        let points = input.load
        guard points.count >= 28, let today = points.last else { return [] }

        if let ramp = TrainingLoad.rampRate(points), ramp > 5 {
            insights.append(Insight(id: "load.ramp", category: .load, severity: ramp > 8 ? .warning : .watch,
                                    title: "Charge qui monte vite",
                                    evidence: [String(format: "Condition : %+.1f points en 7 j (repère : ≤ 5)", ramp),
                                               String(format: "Condition actuelle : %.0f", today.ctl)],
                                    recommendation: "Une progression trop rapide est le premier facteur de blessure. Garde la semaine prochaine au même niveau ou prévois une semaine de récupération.",
                                    references: [Science.gabbett2016, Science.allenCoggan]))
        }

        let last7 = points.suffix(7).map(\.tss)
        if let ratio = Robust.acuteChronicRatio(points.map(\.tss)) {
            let acute = Robust.ewma(points.map(\.tss), days: 7)
            let chronic = Robust.ewma(points.map(\.tss), days: 28)
            let evidence = [String(format: "Charge 7 j : %.0f TSS/j · charge 28 j : %.0f TSS/j (moyennes exponentielles)", acute, chronic),
                            String(format: "Ratio aigu / chronique : %.2f (zone sûre : 0,8–1,3)", ratio)]
            if ratio > 1.5 {
                insights.append(Insight(id: "load.acwr", category: .load, severity: .warning,
                                        title: "Pic de charge inhabituel",
                                        evidence: evidence,
                                        recommendation: "Charge nettement au-dessus de ton habitude des 4 dernières semaines : semaine à venir −30 % conseillée.",
                                        references: [Science.gabbett2016]))
            } else if ratio < 0.7 {
                insights.append(Insight(id: "load.detraining", category: .load, severity: .info,
                                        title: "Charge en baisse",
                                        evidence: evidence,
                                        recommendation: "Normal en semaine de récupération ou blessé. Au-delà de 2 semaines, la condition commence à baisser : reprends progressivement.",
                                        references: [Science.gabbett2016, Science.banister1975]))
            }
        }

        // Monotonie de Foster : moyenne / écart-type de la charge quotidienne sur 7 jours.
        if let mean = Stats.mean(last7), let sd = Stats.standardDeviation(last7), sd > 0, mean > 20 {
            let monotony = mean / sd
            if monotony > 2 {
                insights.append(Insight(id: "load.monotony", category: .load, severity: .watch,
                                        title: "Entraînement trop uniforme",
                                        evidence: [String(format: "Monotonie : %.1f (repère : < 2)", monotony),
                                                   String(format: "Contrainte hebdo : %.0f", mean * 7 * monotony)],
                                        recommendation: "Alterne vraiment les jours durs et les jours faciles (ou de repos) : la même charge tous les jours fatigue plus qu'elle ne fait progresser.",
                                        references: [Science.foster1998]))
            }
        }

        if today.form < -30 {
            insights.append(Insight(id: "load.form", category: .load, severity: .warning,
                                    title: "Fatigue très élevée",
                                    evidence: [String(format: "Forme : %.0f (repère de surcharge : < −30)", today.form)],
                                    recommendation: "Au-delà de −30, le risque de méforme et de maladie augmente. Prévois 2 à 3 jours faciles.",
                                    references: [Science.allenCoggan, Science.banister1975]))
        }

        if let readiness = input.readiness, readiness.level == .low, today.tss > 80 {
            insights.append(Insight(id: "load.ignoredReadiness", category: .recovery, severity: .watch,
                                    title: "Grosse séance malgré une récupération basse",
                                    evidence: ["Récupération : \(readiness.score)/100", String(format: "Charge du jour : %.0f TSS", today.tss)],
                                    recommendation: "Ponctuellement sans conséquence ; répété, la fatigue s'accumule. Demain : endurance facile ou repos conseillés.",
                                    references: [Science.kiviniemi2007]))
        }
        return insights
    }

    // MARK: Répartition 80/20

    static func intensityDistribution(_ input: InsightInput, calendar: Calendar) -> [Insight] {
        guard let start = calendar.date(byAdding: .day, value: -28, to: input.today) else { return [] }
        let rides = input.activities.filter { $0.date >= start && $0.sport != .strength && $0.intensityFactor != nil }
        let total = rides.reduce(0) { $0 + $1.durationSeconds }
        guard total >= 4 * 3600 else { return [] }

        let easy = rides.filter { ($0.intensityFactor ?? 0) < 0.75 }.reduce(0) { $0 + $1.durationSeconds }
        let hard = rides.filter { ($0.intensityFactor ?? 0) >= 0.9 }.reduce(0) { $0 + $1.durationSeconds }
        let easyShare = easy / total
        let moderateShare = 1 - easyShare - hard / total
        let evidence = [String(format: "Sur 28 j : %.0f %% facile · %.0f %% modéré · %.0f %% intense", easyShare * 100, moderateShare * 100, hard / total * 100),
                        String(format: "Volume analysé : %.1f h", total / 3600)]

        if easyShare < 0.7 {
            return [Insight(id: "intensity.grey", category: .load, severity: .watch,
                            title: "Trop de « zone grise »",
                            evidence: evidence,
                            recommendation: "Une grande partie du temps se situe entre les deux intensités utiles. Rends les sorties faciles vraiment faciles (zone 2, tu peux parler) et garde 1 à 2 vraies séances intenses.",
                            references: [Science.seiler2010])]
        }
        if easyShare >= 0.78 {
            return [Insight(id: "intensity.polarized", category: .load, severity: .positive,
                            title: "Bonne répartition 80/20",
                            evidence: evidence,
                            recommendation: "Ta répartition correspond à celle des endurants performants.",
                            references: [Science.seiler2010])]
        }
        return []
    }

    // MARK: Musculation

    static func strength(_ input: InsightInput, calendar: Calendar) -> [Insight] {
        var insights: [Insight] = []
        guard let weekStart = calendar.date(byAdding: .day, value: -7, to: input.today) else { return [] }
        let week = input.strength.filter { $0.date >= weekStart }
        guard !week.isEmpty else { return [] }

        let volume = MuscleMap.weeklySets(week)
        let tracked: [Muscle] = [.chest, .lats, .upperBack, .sideDelts, .quads, .hamstrings, .glutes, .biceps, .triceps]
        let low = tracked.filter { (volume[$0] ?? 0) < MuscleMap.hypertrophyRange.lowerBound }
        let high = Muscle.allCases.filter { (volume[$0] ?? 0) > MuscleMap.hypertrophyRange.upperBound }

        if !low.isEmpty {
            insights.append(Insight(id: "strength.lowVolume", category: .strength, severity: .watch,
                                    title: "Volume insuffisant sur certains muscles",
                                    evidence: low.map { String(format: "%@ : %.1f séries cette semaine", $0.label, volume[$0] ?? 0) },
                                    recommendation: "Pour la prise de masse, vise au moins 10 séries par muscle et par semaine. Ajoute 2 à 3 séries sur ces muscles dans tes séances PPL (sauf zone blessée).",
                                    references: [Science.schoenfeld2017]))
        }
        if !high.isEmpty {
            insights.append(Insight(id: "strength.highVolume", category: .strength, severity: .info,
                                    title: "Volume très élevé",
                                    evidence: high.map { String(format: "%@ : %.1f séries", $0.label, volume[$0] ?? 0) },
                                    recommendation: "Au-delà de 20 séries, le gain supplémentaire devient faible et la récupération plus difficile, surtout avec le vélo en parallèle.",
                                    references: [Science.schoenfeld2017]))
        }

        // Stagnation : pente du 1RM estimé sur 6 semaines, non significativement positive.
        let byExercise = Dictionary(grouping: input.strength, by: \.exercise)
        guard let sixWeeksAgo = calendar.date(byAdding: .day, value: -42, to: input.today) else { return insights }
        var stalled: [String] = []
        for (exercise, sessions) in byExercise {
            let points: [DayValue] = sessions.filter { $0.date >= sixWeeksAgo && $0.bestEstimated1RM > 0 }
                .sorted { $0.date < $1.date }
                .map { DayValue(date: $0.date, value: $0.bestEstimated1RM) }
            guard points.count >= 4, let fit = Robust.regression(points) else { continue }
            let perWeek = fit.slopePerDay * 7
            // Progression < 0,25 % / semaine et non significative (t < 2) = stagnation.
            let mean = Stats.mean(points.map(\.value)) ?? 1
            if perWeek / mean < 0.0025 && fit.t < 2 {
                stalled.append(String(format: "%@ : %+.1f kg/sem de 1RM estimé sur %d séances", exercise, perWeek, points.count))
            }
        }
        stalled.sort()
        if !stalled.isEmpty {
            insights.append(Insight(id: "strength.stalled", category: .strength, severity: .watch,
                                    title: "Stagnation détectée",
                                    evidence: stalled,
                                    recommendation: "Causes fréquentes : manque de sommeil, calories insuffisantes ou fatigue du vélo. Essaie une semaine de décharge, puis repars 5 % plus léger avec plus de répétitions.",
                                    references: [Science.epley1985, Science.helms2016]))
        }

        // Jambes lourdes la veille d'une séance vélo intense.
        let heavyLegDays = input.strength.filter { session in
            MuscleMap.targets(for: session.exercise).primary.contains { $0.region == .lowerBody } && session.workingSets.count >= 3
        }.map { calendar.startOfDay(for: $0.date) }
        let hardRides = input.activities.filter { ($0.intensityFactor ?? 0) >= 0.85 && $0.sport.isCycling }
        let clashes = hardRides.filter { ride in
            let rideDay = calendar.startOfDay(for: ride.date)
            return heavyLegDays.contains { legDay in
                let gap = calendar.dateComponents([.day], from: legDay, to: rideDay).day ?? 99
                return gap == 0 || gap == 1
            }
        }
        if clashes.count >= 2 {
            insights.append(Insight(id: "strength.interference", category: .strength, severity: .info,
                                    title: "Séance jambes trop proche des séances vélo intenses",
                                    evidence: ["\(clashes.count) séances vélo intenses le jour même ou le lendemain d'une séance jambes"],
                                    recommendation: "Place la séance Legs après la séance vélo intense (ou 48 h avant) pour garder la qualité des deux.",
                                    references: [Science.wilson2012]))
        }
        return insights
    }

    // MARK: Nutrition

    static func nutrition(_ input: InsightInput, calendar: Calendar) -> [Insight] {
        var insights: [Insight] = []
        guard let weekStart = calendar.date(byAdding: .day, value: -7, to: input.today) else { return [] }
        let logged = input.nutrition.filter { $0.date >= weekStart && $0.kcal > 300 }

        if logged.count >= 3, input.weightKg > 0 {
            let protein = (Stats.mean(logged.map(\.protein)) ?? 0) / input.weightKg
            let evidence = [String(format: "Protéines : %.1f g/kg/j en moyenne sur %d jours", protein, logged.count)]
            if protein < 1.6 {
                insights.append(Insight(id: "nutrition.protein", category: .nutrition, severity: .warning,
                                        title: "Protéines insuffisantes pour la prise de masse",
                                        evidence: evidence,
                                        recommendation: String(format: "Vise %.0f g par jour (1,8 g/kg) répartis en 4 prises de 30–40 g.", input.weightKg * 1.8),
                                        references: [Science.morton2018]))
            } else if protein <= 2.4 {
                insights.append(Insight(id: "nutrition.proteinOK", category: .nutrition, severity: .positive,
                                        title: "Apport en protéines optimal",
                                        evidence: evidence,
                                        recommendation: "Au-delà de 2,2 g/kg le bénéfice est négligeable : inutile d'en rajouter.",
                                        references: [Science.morton2018]))
            }

            // Glucides les jours de longue sortie.
            let longDays = Set(input.activities.filter { $0.durationSeconds >= 2 * 3600 && $0.date >= weekStart }
                .map { calendar.startOfDay(for: $0.date) })
            let lowCarbLongDays = logged.filter { longDays.contains(calendar.startOfDay(for: $0.date)) && $0.carbs / input.weightKg < 6 }
            if !lowCarbLongDays.isEmpty {
                insights.append(Insight(id: "nutrition.carbs", category: .nutrition, severity: .watch,
                                        title: "Pas assez de glucides les jours de sortie longue",
                                        evidence: lowCarbLongDays.map { String(format: "%@ : %.1f g/kg de glucides", $0.date.formatted(date: .abbreviated, time: .omitted), $0.carbs / input.weightKg) },
                                        recommendation: "Les jours de 2 h et plus, vise 6 à 10 g/kg de glucides, dont 60 à 90 g par heure pendant la sortie.",
                                        references: [Science.burke2011, Science.jeukendrup2014]))
            }
        }

        // Vitesse de prise de poids (tendance lissée).
        let weights = input.wellness.compactMap { sample in sample.weightKg.map { DayValue(date: sample.date, value: $0) } }
        let recentWeights = Stats.lastDays(28, of: weights, today: input.today, calendar: calendar)
        if recentWeights.count >= 8 {
            let trend = Stats.exponentialTrend(recentWeights)
            if let first = trend.first, let last = trend.last {
                let weeks = max(last.date.timeIntervalSince(first.date) / (7 * 86_400), 1)
                let ratePercent = (last.value - first.value) / first.value / weeks * 100
                let evidence = [String(format: "Tendance du poids : %+.2f %% par semaine (%+.2f kg/sem)", ratePercent, (last.value - first.value) / weeks),
                                String(format: "Poids lissé actuel : %.1f kg", last.value)]
                let gaining = input.phase.map { [TrainingPhase.reprise, .base, .build].contains($0) } ?? true
                if gaining && ratePercent > 0.75 {
                    insights.append(Insight(id: "nutrition.gainFast", category: .nutrition, severity: .watch,
                                            title: "Prise de poids trop rapide",
                                            evidence: evidence,
                                            recommendation: "Au-delà de 0,5 %/semaine, l'excédent part surtout en gras. Réduis d'environ 200 kcal par jour.",
                                            references: [Science.iraki2019]))
                } else if gaining && ratePercent < 0.1 {
                    insights.append(Insight(id: "nutrition.gainSlow", category: .nutrition, severity: .watch,
                                            title: "Pas de prise de poids",
                                            evidence: evidence,
                                            recommendation: "Pour construire du muscle, il faut un léger surplus. Ajoute environ 200 kcal par jour, de préférence en glucides autour des séances.",
                                            references: [Science.iraki2019, Science.hall2008]))
                } else if gaining {
                    insights.append(Insight(id: "nutrition.gainOK", category: .nutrition, severity: .positive,
                                            title: "Prise de masse au bon rythme",
                                            evidence: evidence,
                                            recommendation: "Rythme idéal : 0,25 à 0,5 % du poids par semaine.",
                                            references: [Science.iraki2019]))
                }
            }
        }
        return insights
    }

    // MARK: Qualité des données

    static func dataQuality(_ input: InsightInput, calendar: Calendar) -> [Insight] {
        var insights: [Insight] = []
        let lastWeek = (0..<7).compactMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: input.today)) }
        let byDay = Dictionary(input.wellness.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { first, _ in first })

        let missingHRV = lastWeek.filter { byDay[$0]?.hrv == nil }.count
        if missingHRV >= 3 {
            insights.append(Insight(id: "data.hrvMissing", category: .data, severity: .info,
                                    title: "VFC manquante",
                                    evidence: ["\(missingHRV) nuits sans VFC sur les 7 dernières"],
                                    recommendation: "Porte ta Fenix la nuit (bracelet bien ajusté) : le score de récupération en dépend.",
                                    references: [Science.plews2013]))
        }

        if input.hrvSourcesMixed {
            insights.append(Insight(id: "data.hrvMixed", category: .data, severity: .info,
                                    title: "Deux types de VFC différents",
                                    evidence: ["Apple Santé fournit la VFC en SDNN, Garmin en rMSSD : les valeurs ne sont pas comparables."],
                                    recommendation: "Vigor utilise la VFC Garmin (rMSSD, nuit complète) dès qu'elle est disponible via Intervals.icu, et ne mélange jamais les deux.",
                                    references: [Science.buchheit2014]))
        }

        // Valeur de VFC aberrante (> 3 écarts-types) : artefact probable.
        let hrv = input.wellness.compactMap { sample in sample.hrv.map { DayValue(date: sample.date, value: log($0)) } }
        let baseline = Stats.lastDays(60, of: hrv, today: input.today, calendar: calendar).map(\.value)
        if baseline.count >= 21, let mean = Stats.mean(baseline), let sd = Stats.standardDeviation(baseline), sd > 0,
           let latest = hrv.max(by: { $0.date < $1.date }), abs(latest.value - mean) > 3 * sd {
            insights.append(Insight(id: "data.hrvOutlier", category: .data, severity: .info,
                                    title: "Mesure de VFC inhabituelle",
                                    evidence: [String(format: "Dernière VFC : %.0f ms, très loin de ta moyenne (%.0f ms)", exp(latest.value), exp(mean))],
                                    recommendation: "Alcool, repas tardif, maladie qui commence ou capteur mal placé ? Une valeur isolée ne change pas le plan : c'est la tendance qui compte.",
                                    references: [Science.plews2013]))
        }

        // FTP probablement sous-estimée.
        if let ftp = input.ftp {
            let strongRides = input.activities.filter { $0.sport.isCycling && $0.durationSeconds >= 20 * 60 && ($0.averagePower ?? 0) > ftp * 1.02 }
            if !strongRides.isEmpty {
                insights.append(Insight(id: "data.ftpLow", category: .data, severity: .watch,
                                        title: "FTP probablement sous-estimée",
                                        evidence: ["\(strongRides.count) sortie(s) de 20 min ou plus avec une puissance moyenne au-dessus de ta FTP (\(Int(ftp)) W)"],
                                        recommendation: "Une FTP trop basse surestime la charge de toutes tes sorties. Fais un test (20 min ou rampe) dès que l'ischio le permet et mets-la à jour.",
                                        references: [Science.allenCoggan]))
            }
        }

        let weights = input.wellness.filter { $0.weightKg != nil }.map(\.date)
        let recentWeight = weights.contains { $0 >= (calendar.date(byAdding: .day, value: -7, to: input.today) ?? input.today) }
        if !recentWeight {
            insights.append(Insight(id: "data.weightMissing", category: .data, severity: .info,
                                    title: "Pas de pesée récente",
                                    evidence: ["Aucun poids enregistré depuis 7 jours"],
                                    recommendation: "Pèse-toi au moins 3 fois par semaine, le matin à jeun : c'est indispensable pour piloter la prise de masse.",
                                    references: [Science.iraki2019]))
        }
        return insights
    }
}
