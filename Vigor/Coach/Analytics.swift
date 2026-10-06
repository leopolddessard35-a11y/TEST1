import Foundation

// MARK: - Zones de FC et dérive cardiaque

enum HeartRateZones {
    static let labels = ["Z1 récup", "Z2 endurance", "Z3 tempo", "Z4 seuil", "Z5 VO2max"]

    struct Sample: Equatable {
        let time: Date
        let bpm: Double
    }

    /// Bornes hautes des zones 1 à 4 (bpm). Zones de Friel sur la FC seuil, sinon % de FC max.
    static func bounds(thresholds: Thresholds, sport: Sport) -> [Double]? {
        if sport == .running, let lthr = thresholds.runningLTHR ?? thresholds.cyclingLTHR {
            return [0.85, 0.90, 0.95, 1.0].map { $0 * lthr }
        }
        if sport != .running, let lthr = thresholds.cyclingLTHR {
            return [0.81, 0.90, 0.94, 1.0].map { $0 * lthr }
        }
        if let maxHR = thresholds.maxHeartRate {
            return [0.70, 0.80, 0.87, 0.93].map { $0 * maxHR }
        }
        return nil
    }

    static func zone(for bpm: Double, bounds: [Double]) -> Int {
        for (index, bound) in bounds.enumerated() where bpm < bound { return index }
        return 4
    }

    /// Temps par zone (s) et dérive cardiaque (%) entre 1re et 2e moitié (hors 10 min d'échauffement).
    static func analyze(_ samples: [Sample], bounds: [Double]) -> (zones: [Double], drift: Double?) {
        let sorted = samples.sorted { $0.time < $1.time }
        var zones = [Double](repeating: 0, count: 5)
        guard sorted.count > 1, let first = sorted.first, let last = sorted.last else { return (zones, nil) }
        for index in 0..<(sorted.count - 1) {
            let gap = min(sorted[index + 1].time.timeIntervalSince(sorted[index].time), 30)
            zones[zone(for: sorted[index].bpm, bounds: bounds)] += max(0, gap)
        }

        let total = last.time.timeIntervalSince(first.time)
        guard total >= 45 * 60 else { return (zones, nil) }
        let start = first.time.addingTimeInterval(10 * 60)
        let middle = start.addingTimeInterval(last.time.timeIntervalSince(start) / 2)
        let firstHalf = sorted.filter { $0.time >= start && $0.time < middle }.map(\.bpm)
        let secondHalf = sorted.filter { $0.time >= middle }.map(\.bpm)
        guard let a = Stats.mean(firstHalf), let b = Stats.mean(secondHalf), a > 0 else { return (zones, nil) }
        return (zones, (b / a - 1) * 100)
    }
}

// MARK: - Charge par discipline et volume

struct LoadItem: Equatable {
    let date: Date
    let tss: Double
    let discipline: String
}

struct DisciplineLoad: Identifiable, Equatable {
    var id: String { name }
    let name: String
    /// Charge moyenne par jour sur 7 jours.
    let acute: Double
    /// Charge moyenne par jour sur 28 jours.
    let chronic: Double

    var ratio: Double? { chronic > 3 ? acute / chronic : nil }
}

struct VolumeSample: Equatable {
    let date: Date
    let sport: Sport
    let seconds: Double
    let meters: Double
}

struct WeeklyVolume: Identifiable, Equatable {
    var id: Date { weekStart }
    let weekStart: Date
    var bikeHours: Double = 0
    var runKm: Double = 0
    var runHours: Double = 0
    var tonnage: Double = 0
    var lifeHours: Double = 0

    var sportHours: Double { bikeHours + runHours }
}

enum LoadAnalytics {
    /// Charge aiguë / chronique par discipline en moyennes exponentielles 7 j / 28 j (sur 90 jours).
    static func disciplineLoads(_ items: [LoadItem], today: Date, calendar: Calendar = .current) -> [DisciplineLoad] {
        let end = calendar.startOfDay(for: today)
        let window = 90
        guard let start = calendar.date(byAdding: .day, value: -(window - 1), to: end) else { return [] }
        var perDiscipline: [String: [Double]] = [:]
        for item in items {
            let day = calendar.startOfDay(for: item.date)
            guard day >= start, day <= end,
                  let index = calendar.dateComponents([.day], from: start, to: day).day, index >= 0, index < window else { continue }
            if perDiscipline[item.discipline] == nil { perDiscipline[item.discipline] = [Double](repeating: 0, count: window) }
            perDiscipline[item.discipline]?[index] += item.tss
        }
        func loads(_ daily: [Double]) -> (acute: Double, chronic: Double) {
            // Amorçage sur la moyenne des 28 premiers jours pour éviter l'effet de bord du départ à zéro.
            let seed = Stats.mean(Array(daily.prefix(28))) ?? 0
            var acute = seed, chronic = seed
            let alphaAcute = 1 - exp(-1 / 7.0), alphaChronic = 1 - exp(-1 / 28.0)
            for load in daily {
                acute += alphaAcute * (load - acute)
                chronic += alphaChronic * (load - chronic)
            }
            return (acute, chronic)
        }
        var result: [DisciplineLoad] = []
        var total = [Double](repeating: 0, count: window)
        for name in perDiscipline.keys.sorted() {
            let daily = perDiscipline[name] ?? []
            for index in daily.indices { total[index] += daily[index] }
            let value = loads(daily)
            result.append(DisciplineLoad(name: name, acute: value.acute, chronic: value.chronic))
        }
        let global = loads(total)
        result.insert(DisciplineLoad(name: "Global", acute: global.acute, chronic: global.chronic), at: 0)
        return result
    }

    /// Volume des `weeks` dernières semaines (lundi → dimanche), la plus récente en dernier.
    static func weeklyVolumes(samples: [VolumeSample],
                              tonnage: [(date: Date, kg: Double)],
                              life: [(date: Date, minutes: Double)],
                              weeks: Int,
                              today: Date,
                              calendar: Calendar = SeasonPlanner.isoCalendar) -> [WeeklyVolume] {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        var volumes: [Date: WeeklyVolume] = [:]
        var starts: [Date] = []
        for offset in stride(from: weeks - 1, through: 0, by: -1) {
            guard let start = calendar.date(byAdding: .day, value: -7 * offset, to: currentWeek) else { continue }
            starts.append(start)
            volumes[start] = WeeklyVolume(weekStart: start)
        }
        func weekStart(_ date: Date) -> Date? { calendar.dateInterval(of: .weekOfYear, for: date)?.start }

        for sample in samples {
            guard let start = weekStart(sample.date), volumes[start] != nil else { continue }
            if sample.sport.isCycling {
                volumes[start]?.bikeHours += sample.seconds / 3600
            } else if sample.sport == .running {
                volumes[start]?.runHours += sample.seconds / 3600
                volumes[start]?.runKm += sample.meters / 1000
            }
        }
        for item in tonnage {
            guard let start = weekStart(item.date), volumes[start] != nil else { continue }
            volumes[start]?.tonnage += item.kg
        }
        for item in life {
            guard let start = weekStart(item.date), volumes[start] != nil else { continue }
            volumes[start]?.lifeHours += item.minutes / 60
        }
        return starts.compactMap { volumes[$0] }
    }

    /// Progression de la dernière semaine complète par rapport à la précédente (règle des ~10 %).
    static func progressionAlerts(_ volumes: [WeeklyVolume]) -> [String] {
        guard volumes.count >= 3 else { return [] }
        let last = volumes[volumes.count - 2]
        let previous = volumes[volumes.count - 3]
        var alerts: [String] = []
        func check(_ name: String, _ now: Double, _ before: Double, _ unit: String, minimum: Double) {
            guard before >= minimum else { return }
            let change = (now / before - 1) * 100
            if change > 10 {
                alerts.append(String(format: "%@ : %+.0f %% (%.1f → %.1f %@)", name, change, before, now, unit))
            }
        }
        check("Vélo", last.bikeHours, previous.bikeHours, "h", minimum: 1)
        check("Course", last.runKm, previous.runKm, "km", minimum: 5)
        check("Tonnage muscu", last.tonnage / 1000, previous.tonnage / 1000, "t", minimum: 1)
        return alerts
    }
}

// MARK: - Régularité du sommeil

enum SleepAnalytics {
    /// Minutes depuis 18 h (pour qu'un coucher à 23 h 30 et à 0 h 30 restent proches).
    static func eveningMinutes(_ date: Date, calendar: Calendar = .current) -> Double {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        var minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        if minutes < 18 * 60 { minutes += 24 * 60 }
        return minutes - 18 * 60
    }

    /// Écart-type de l'heure de coucher (minutes) et heure moyenne.
    static func bedtimeRegularity(_ bedtimes: [Date], calendar: Calendar = .current) -> (sd: Double, average: String)? {
        guard bedtimes.count >= 5 else { return nil }
        let values = bedtimes.map { eveningMinutes($0, calendar: calendar) }
        guard let mean = Stats.mean(values), let sd = Stats.standardDeviation(values) else { return nil }
        let clock = Int(mean + 18 * 60) % (24 * 60)
        return (sd, String(format: "%d h %02d", clock / 60, clock % 60))
    }
}

// MARK: - Croisements

struct DayRecord: Equatable {
    let date: Date
    var sleep: Double?
    var hrv: Double?
    var restingHR: Double?
    var load: Double = 0
    var lifeLoad: Double = 0
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var readiness: Double?
    var rpe: Double?
    /// Efficiency Factor moyen des séances d'endurance du jour.
    var ef: Double?
}

struct Correlation: Identifiable, Equatable {
    let id: String
    let title: String
    /// Coefficient de Spearman.
    let r: Double
    let n: Int
    let interpretation: String
    /// Décalage en jours (0 = même jour, 1 = lendemain, 2 = surlendemain).
    var lag: Int = 0
    var confidence: ClosedRange<Double>?

    /// Moins de 30 points ou intervalle qui contient 0 : simple indice, pas un résultat.
    var isHint: Bool {
        guard n >= 30, let confidence else { return true }
        return confidence.contains(0)
    }

    var lagLabel: String { lag == 0 ? "même jour" : (lag == 1 ? "J+1" : "J+2") }

    var strength: String {
        switch abs(r) {
        case ..<0.2: "pas de lien net"
        case ..<0.4: "lien faible"
        case ..<0.6: "lien modéré"
        default: "lien fort"
        }
    }
}

enum Correlations {
    static func pearson(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 3, let mx = Stats.mean(xs), let my = Stats.mean(ys) else { return nil }
        var numerator = 0.0, sx = 0.0, sy = 0.0
        for index in xs.indices {
            let dx = xs[index] - mx, dy = ys[index] - my
            numerator += dx * dy
            sx += dx * dx
            sy += dy * dy
        }
        let denominator = (sx * sy).squareRoot()
        return denominator > 0 ? numerator / denominator : nil
    }

    private struct Pair {
        let id: String
        let title: String
        let lag: Int
        let x: (DayRecord) -> Double?
        let y: (DayRecord) -> Double?
        let positive: String
        let negative: String
    }

    /// Croise tes données jour par jour, en Spearman, avec décalage J / J+1 / J+2 (on garde le plus marqué).
    static func analyze(_ records: [DayRecord], minimum: Int = 14) -> [Correlation] {
        let sorted = records.sorted { $0.date < $1.date }
        let pairs: [Pair] = [
            Pair(id: "sleep-hrv", title: "Sommeil → VFC du matin", lag: 0, x: { $0.sleep }, y: { $0.hrv },
                 positive: "Plus tu dors, plus ta VFC est haute au réveil.",
                 negative: "Tes nuits longues ne s'accompagnent pas d'une meilleure VFC : la qualité compte plus que la durée."),
            Pair(id: "load-hrv", title: "Charge du jour → VFC du lendemain", lag: 1, x: { $0.load }, y: { $0.hrv },
                 positive: "Ta VFC tient bien après les grosses journées : bonne tolérance à la charge.",
                 negative: "Les grosses journées font baisser ta VFC le lendemain : place un jour facile après."),
            Pair(id: "life-hrv", title: "Charge hors sport → VFC du lendemain", lag: 1, x: { $0.lifeLoad }, y: { $0.hrv },
                 positive: "Les journées physiques hors sport ne pèsent pas sur ta récupération.",
                 negative: "Les journées de travaux / debout font baisser ta VFC : compte-les comme une séance."),
            Pair(id: "sleep-rpe", title: "Sommeil → effort ressenti des séances", lag: 0, x: { $0.sleep }, y: { $0.rpe },
                 positive: "Bizarrement, tes séances semblent plus dures après une longue nuit.",
                 negative: "Mieux tu dors, plus tes séances te paraissent faciles."),
            Pair(id: "sleep-ef", title: "Sommeil → efficacité aérobie (EF)", lag: 1, x: { $0.sleep }, y: { $0.ef },
                 positive: "Après une bonne nuit, tu produis plus de puissance pour la même FC.",
                 negative: "Pas de bénéfice visible du sommeil sur ton efficacité aérobie."),
            Pair(id: "carbs-readiness", title: "Glucides → récupération du lendemain", lag: 1, x: { $0.carbs }, y: { $0.readiness },
                 positive: "Les jours où tu manges plus de glucides, tu récupères mieux le lendemain.",
                 negative: "Pas de bénéfice visible des glucides sur ta récupération du lendemain."),
            Pair(id: "kcal-hrv", title: "Calories → VFC du lendemain", lag: 1, x: { $0.kcal }, y: { $0.hrv },
                 positive: "Bien manger se voit sur ta VFC le lendemain.",
                 negative: "Les gros repas font baisser ta VFC la nuit suivante (repas tardif ? alcool ?)."),
            Pair(id: "protein-readiness", title: "Protéines → récupération du lendemain", lag: 1, x: { $0.protein }, y: { $0.readiness },
                 positive: "Les jours riches en protéines sont suivis d'une meilleure récupération.",
                 negative: "Pas de lien visible entre protéines et récupération du lendemain."),
        ]

        var results: [Correlation] = []
        for pair in pairs {
            var best: Correlation?
            let lags: [Int] = pair.lag == 0 ? [0, 1] : [1, 2]
            for lag in lags {
                var xs: [Double] = []
                var ys: [Double] = []
                for index in sorted.indices where index + lag < sorted.count {
                    guard let x = pair.x(sorted[index]), let y = pair.y(sorted[index + lag]) else { continue }
                    xs.append(x)
                    ys.append(y)
                }
                guard xs.count >= minimum, let r = Robust.spearman(xs, ys) else { continue }
                if let current = best, abs(current.r) >= abs(r) { continue }
                let text = abs(r) < 0.2 ? "Aucun lien net pour l'instant dans tes données." : (r > 0 ? pair.positive : pair.negative)
                best = Correlation(id: pair.id, title: pair.title, r: r, n: xs.count, interpretation: text,
                                   lag: lag, confidence: Robust.confidenceInterval(r: r, n: xs.count))
            }
            if let best { results.append(best) }
        }
        return results.sorted { abs($0.r) > abs($1.r) }
    }
}

// MARK: - Journal de symptômes

struct SymptomRecord: Equatable {
    let date: Date
    let key: String
    let intensity: Int
    let onsetMinutes: Int?
    let shoe: String?
    let terrain: String?
    let fatigue: Int
    let previousSleep: Double?
    /// Charge (TSS) de la veille.
    var previousLoad: Double?
}

struct SymptomPattern: Identifiable, Equatable {
    var id: String { key }
    let key: String
    let count: Int
    let recentCount: Int
    let last: Date
    let averageIntensity: Double
    let averageOnset: Double?
    let findings: [String]

    /// ≥ 3 épisodes sur 14 jours.
    var isRecurrent: Bool { recentCount >= 3 }
}

enum SymptomAnalysis {
    /// Regroupe les épisodes identiques et cherche ce qui les déclenche ou les retarde.
    static func patterns(_ records: [SymptomRecord], runsByShoe: [String: Int] = [:], today: Date) -> [SymptomPattern] {
        let recentStart = today.addingTimeInterval(-14 * 86_400)
        var result: [SymptomPattern] = []
        for (key, episodes) in Dictionary(grouping: records, by: \.key) {
            let sorted = episodes.sorted { $0.date < $1.date }
            guard let last = sorted.last else { continue }
            var findings: [String] = []
            let onsets = sorted.compactMap(\.onsetMinutes).map(Double.init)
            // Médianes (robustes) plutôt que moyennes.
            func medianOnset(_ items: [SymptomRecord]) -> Double? { Robust.median(items.compactMap(\.onsetMinutes).map(Double.init)) }

            // Par chaussure : apparition et fréquence.
            let byShoe = Dictionary(grouping: sorted.filter { $0.shoe != nil }, by: { $0.shoe ?? "" })
            if byShoe.count >= 2 || (byShoe.count == 1 && !runsByShoe.isEmpty) {
                for (shoe, items) in byShoe.sorted(by: { $0.key < $1.key }) {
                    let onset = medianOnset(items)
                    var line = "\(shoe) : \(items.count) épisode\(items.count > 1 ? "s" : "")"
                    if let runs = runsByShoe[shoe], runs > 0 { line += " sur \(runs) sortie\(runs > 1 ? "s" : "")" }
                    if let onset { line += String(format: ", apparition médiane à %.0f min", onset) }
                    findings.append(line)
                }
            }
            // Par terrain.
            let byTerrain = Dictionary(grouping: sorted.filter { $0.terrain != nil }, by: { $0.terrain ?? "" })
            if byTerrain.count >= 2 {
                for (terrain, items) in byTerrain.sorted(by: { $0.value.count > $1.value.count }) {
                    let onset = medianOnset(items)
                    findings.append("\(terrain) : \(items.count) épisode(s)" + (onset.map { String(format: ", médiane %.0f min", $0) } ?? ""))
                }
            }
            // Fatigue : le symptôme arrive-t-il plus tôt quand tu es fatigué ?
            if let a = medianOnset(sorted.filter { $0.fatigue >= 4 }), let b = medianOnset(sorted.filter { $0.fatigue <= 2 }), abs(a - b) >= 5 {
                findings.append(String(format: "Fatigué : apparition vers %.0f min · frais : vers %.0f min", a, b))
            }
            // Sommeil de la veille.
            if let a = medianOnset(sorted.filter { ($0.previousSleep ?? 99) < 7 }),
               let b = medianOnset(sorted.filter { ($0.previousSleep ?? 0) >= 7 }), abs(a - b) >= 5 {
                findings.append(String(format: "Après une nuit < 7 h : vers %.0f min · après une bonne nuit : vers %.0f min", a, b))
            }
            // Charge de la veille.
            let loads = sorted.compactMap(\.previousLoad)
            if loads.count >= 4, let middle = Robust.median(loads),
               let heavy = medianOnset(sorted.filter { ($0.previousLoad ?? 0) > middle }),
               let light = medianOnset(sorted.filter { ($0.previousLoad ?? .infinity) <= middle }), abs(heavy - light) >= 5 {
                findings.append(String(format: "Veille chargée : médiane %.0f min · veille légère : %.0f min", heavy, light))
            }
            // Évolution de l'intensité.
            if sorted.count >= 4 {
                let half = sorted.count / 2
                let before = Stats.mean(sorted.prefix(half).map { Double($0.intensity) }) ?? 0
                let after = Stats.mean(sorted.suffix(sorted.count - half).map { Double($0.intensity) }) ?? 0
                if after - before >= 1 {
                    findings.append(String(format: "Intensité en hausse : %.1f → %.1f / 10. Consulte si ça continue.", before, after))
                } else if before - after >= 1 {
                    findings.append(String(format: "Intensité en baisse : %.1f → %.1f / 10.", before, after))
                }
            }

            result.append(SymptomPattern(
                key: key,
                count: sorted.count,
                recentCount: sorted.filter { $0.date >= recentStart }.count,
                last: last.date,
                averageIntensity: Stats.mean(sorted.map { Double($0.intensity) }) ?? 0,
                averageOnset: Robust.median(onsets),
                findings: findings))
        }
        return result.sorted { $0.last > $1.last }
    }
}

// MARK: - Prévu vs réalisé

struct DayStatus: Identifiable, Equatable {
    enum Status: String {
        case done, partial, missed, rest, upcoming, today

        var label: String {
            switch self {
            case .done: "Fait"
            case .partial: "Partiel"
            case .missed: "Manqué"
            case .rest: "Repos"
            case .upcoming: "À venir"
            case .today: "Aujourd'hui"
            }
        }

        var symbol: String {
            switch self {
            case .done: "checkmark.circle.fill"
            case .partial: "circle.lefthalf.filled"
            case .missed: "xmark.circle.fill"
            case .rest: "moon.zzz.fill"
            case .upcoming: "circle.dotted"
            case .today: "smallcircle.filled.circle"
            }
        }
    }

    var id: Date { date }
    let date: Date
    let planned: [SessionPrescription]
    let done: [String]
    let status: Status
}

struct Milestone: Identifiable, Equatable {
    var id: String { title }
    let date: Date
    let title: String
    let detail: String
}

enum PlanTracking {
    static func weekStatus(week: PlannedWeek,
                           bikeDays: Set<Date>,
                           strengthDays: Set<Date>,
                           doneLabels: [Date: [String]],
                           today: Date,
                           ftp: Double?,
                           calendar: Calendar = .current) -> [DayStatus] {
        let todayStart = calendar.startOfDay(for: today)
        var days: [DayStatus] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: week.start)) else { continue }
            let planned = DailyCoach.template(for: week, weekday: calendar.component(.weekday, from: date), ftp: ftp)
            let needsBike = planned.contains { $0.kind.isBike }
            let needsStrength = planned.contains { $0.kind.isStrength }
            let didBike = bikeDays.contains(date)
            let didStrength = strengthDays.contains(date)
            let status: DayStatus.Status
            if date > todayStart {
                status = .upcoming
            } else if !needsBike && !needsStrength {
                status = .rest
            } else if (!needsBike || didBike) && (!needsStrength || didStrength) {
                status = .done
            } else if didBike || didStrength {
                status = .partial
            } else {
                status = date == todayStart ? .today : .missed
            }
            days.append(DayStatus(date: date, planned: planned, done: doneLabels[date] ?? [], status: status))
        }
        return days
    }

    /// Jalons intermédiaires : fin de chaque phase (condition visée + sortie longue).
    static func milestones(plan: SeasonPlan) -> [Milestone] {
        var result: [Milestone] = []
        let weeks = plan.weeks
        for index in weeks.indices {
            let week = weeks[index]
            let isLastOfPhase = index == weeks.count - 1 || weeks[index + 1].phase != week.phase
            guard isLastOfPhase, week.phase != .race else { continue }
            let end = week.start.addingTimeInterval(6 * 86_400)
            let longest = weeks.filter { $0.phase == week.phase }.map(\.longRideHours).max() ?? 0
            result.append(Milestone(
                date: end,
                title: "Fin de phase \(week.phase.label)",
                detail: String(format: "Condition ≈ %.0f · sortie longue de %@ tenue en zone 2", week.projectedCTL, longest.hoursText)))
        }
        return result
    }
}
