import Foundation

// MARK: - Score d'effort (0–21)

/// Score d'effort quotidien sur une échelle 0–21, à la manière de Whoop :
/// logarithmique, donc chaque point devient plus difficile à gagner.
/// Il inclut tout ce qui fatigue : séances (TSS), musculation, activité hors sport et pas.
enum EffortScore {
    /// Constante calibrée pour : 50 TSS ≈ 9 · 100 TSS ≈ 14 · 200 TSS ≈ 18,7 · 300 TSS ≈ 20.
    static let scale = 100 / log(3.0)

    static func score(load: Double) -> Double {
        21 * (1 - exp(-max(0, load) / scale))
    }

    /// Charge (TSS) correspondant à un score donné.
    static func load(for score: Double) -> Double {
        let clamped = min(max(score, 0), 20.9)
        return -scale * log(1 - clamped / 21)
    }

    /// Cible d'effort selon la récupération (récup haute → on peut charger).
    static func target(for readiness: ReadinessLevel?, verdict: Verdict?) -> ClosedRange<Double> {
        if verdict == .rest { return 0...6 }
        switch readiness {
        case .ready?: return 14...18
        case .moderate?: return 10...14
        case .low?: return 4...9
        case nil: return 8...14
        }
    }

    static func label(_ score: Double) -> String {
        switch score {
        case ..<6: "Léger"
        case ..<10: "Modéré"
        case ..<14: "Soutenu"
        case ..<18: "Élevé"
        default: "Très élevé"
        }
    }
}

// MARK: - Besoin de sommeil

struct SleepNeed: Equatable {
    /// Besoin de base (réglages).
    let base: Double
    /// Supplément lié à l'effort du jour.
    let effortExtra: Double
    /// Rattrapage d'une partie de la dette de sommeil.
    let debtExtra: Double
    /// Heure de réveil habituelle (minutes après minuit).
    let usualWakeMinutes: Int
    /// Efficacité du sommeil (temps endormi / temps au lit).
    let efficiency: Double

    var total: Double { base + effortExtra + debtExtra }

    /// Temps à passer au lit pour dormir `total` heures.
    var timeInBed: Double { total / efficiency }

    /// Heure de coucher conseillée (minutes après minuit, peut dépasser 24 h).
    var bedtimeMinutes: Int {
        var minutes = usualWakeMinutes - Int((timeInBed * 60).rounded())
        while minutes < 0 { minutes += 24 * 60 }
        return minutes
    }

    var bedtimeText: String { String(format: "%d h %02d", bedtimeMinutes / 60, bedtimeMinutes % 60) }
}

enum SleepCoach {
    /// Besoin de sommeil de la nuit à venir :
    /// base + 4 min par point d'effort au-delà de 10 + rattrapage du quart de la dette (max 1 h).
    static func need(base: Double, effortToday: Double, debt7: Double, wakeTimes: [Date], bedTimes: [Date],
                     sleptHours: [Double], calendar: Calendar = .current) -> SleepNeed {
        let effortExtra = max(0, effortToday - 10) * 4 / 60
        let debtExtra = min(1, max(0, debt7) / 4)

        var wakeMinutes = 7 * 60
        let wakes: [Double] = wakeTimes.map { date in
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            return Double((parts.hour ?? 7) * 60 + (parts.minute ?? 0))
        }
        if let mean = Stats.mean(wakes) { wakeMinutes = Int(mean.rounded()) }

        // Efficacité = sommeil réel / temps entre coucher et réveil (par défaut 90 %).
        var efficiencies: [Double] = []
        for (index, bed) in bedTimes.enumerated() where index < wakeTimes.count && index < sleptHours.count {
            let inBed = wakeTimes[index].timeIntervalSince(bed) / 3600
            if inBed > 3 { efficiencies.append(min(1, sleptHours[index] / inBed)) }
        }
        let efficiency = min(0.98, max(0.75, Stats.mean(efficiencies) ?? 0.9))

        return SleepNeed(base: base, effortExtra: effortExtra, debtExtra: debtExtra,
                         usualWakeMinutes: wakeMinutes, efficiency: efficiency)
    }

    /// Performance de sommeil : sommeil obtenu / besoin (plafonnée à 100 %).
    static func performance(slept: Double, need: Double) -> Double {
        guard need > 0 else { return 0 }
        return min(1, slept / need)
    }
}

// MARK: - Fréquence respiratoire

struct RespiratorySignal: Equatable {
    let latest: Double
    let baseline: Double
    let delta: Double
    /// FC de repos également en hausse ?
    let restingHRUp: Bool

    var isWarning: Bool { delta >= 1.0 }
}

enum RespiratoryMonitor {
    /// Fréquence respiratoire nocturne : très stable chez une personne en bonne santé.
    /// Une hausse ≥ 1 respiration/min au-dessus de ta normale précède souvent une infection.
    static func signal(respiration: [DayValue], restingHR: [DayValue], today: Date,
                       calendar: Calendar = .current) -> RespiratorySignal? {
        let recent = Stats.lastDays(2, of: respiration, today: today, calendar: calendar).map(\.value)
        let history = Stats.lastDays(30, of: respiration, today: today, calendar: calendar)
        let cutoff: Date = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: today)) ?? today
        let baselineValues: [Double] = history.filter { $0.date < cutoff }.map(\.value)
        guard !recent.isEmpty, baselineValues.count >= 10,
              let latest = Stats.mean(recent), let baseline = Stats.mean(baselineValues) else { return nil }

        let hrRecent = Stats.mean(Stats.lastDays(2, of: restingHR, today: today, calendar: calendar).map(\.value))
        let hrBaseline = Stats.mean(Stats.lastDays(30, of: restingHR, today: today, calendar: calendar).map(\.value))
        let hrUp: Bool
        if let hrRecent, let hrBaseline { hrUp = hrRecent - hrBaseline >= 3 } else { hrUp = false }
        return RespiratorySignal(latest: latest, baseline: baseline, delta: latest - baseline, restingHRUp: hrUp)
    }
}

// MARK: - Bilan hebdomadaire

struct WeekSummary: Equatable {
    let start: Date
    var recovery: Double?
    var effort: Double?
    var sleepHours: Double?
    var sleepPerformance: Double?
    var trainingHours: Double = 0
    var load: Double = 0
    var kcal: Double?
    var protein: Double?
    var weightChange: Double?
    var bestDay: (date: Date, recovery: Double)?
    var worstDay: (date: Date, recovery: Double)?

    static func == (lhs: WeekSummary, rhs: WeekSummary) -> Bool {
        lhs.start == rhs.start && lhs.recovery == rhs.recovery && lhs.effort == rhs.effort && lhs.load == rhs.load
    }
}

struct WeeklyReport: Equatable {
    let current: WeekSummary
    let previous: WeekSummary
    /// Les faits marquants, rédigés.
    let highlights: [String]
}

enum WeeklyReportBuilder {
    struct Day {
        let date: Date
        var recovery: Double?
        var effort: Double = 0
        var load: Double = 0
        var sleep: Double?
        var sleepNeed: Double
        var trainingSeconds: Double = 0
        var kcal: Double?
        var protein: Double?
        var weight: Double?
    }

    /// 7 derniers jours (hier inclus, aujourd'hui exclu car incomplet) vs les 7 précédents.
    static func build(days: [Day], today: Date, calendar: Calendar = .current) -> WeeklyReport? {
        let end = calendar.startOfDay(for: today)
        guard let currentStart = calendar.date(byAdding: .day, value: -7, to: end),
              let previousStart = calendar.date(byAdding: .day, value: -14, to: end) else { return nil }
        let current = summarize(days.filter { $0.date >= currentStart && $0.date < end }, start: currentStart)
        let previous = summarize(days.filter { $0.date >= previousStart && $0.date < currentStart }, start: previousStart)
        guard current.recovery != nil || current.load > 0 || current.sleepHours != nil else { return nil }
        return WeeklyReport(current: current, previous: previous, highlights: highlights(current, previous))
    }

    static func summarize(_ days: [Day], start: Date) -> WeekSummary {
        var summary = WeekSummary(start: start)
        summary.recovery = Stats.mean(days.compactMap(\.recovery))
        summary.effort = days.isEmpty ? nil : Stats.mean(days.map(\.effort))
        let sleeps = days.compactMap(\.sleep)
        summary.sleepHours = Stats.mean(sleeps)
        let performances: [Double] = days.compactMap { day in day.sleep.map { SleepCoach.performance(slept: $0, need: day.sleepNeed) } }
        summary.sleepPerformance = Stats.mean(performances)
        summary.trainingHours = days.reduce(0) { $0 + $1.trainingSeconds } / 3600
        summary.load = days.reduce(0) { $0 + $1.load }
        summary.kcal = Stats.mean(days.compactMap(\.kcal))
        summary.protein = Stats.mean(days.compactMap(\.protein))
        let weights = days.compactMap(\.weight)
        if let first = weights.first, let last = weights.last, weights.count >= 2 { summary.weightChange = last - first }
        let withRecovery = days.compactMap { day in day.recovery.map { (date: day.date, recovery: $0) } }
        summary.bestDay = withRecovery.max { $0.recovery < $1.recovery }
        summary.worstDay = withRecovery.min { $0.recovery < $1.recovery }
        return summary
    }

    static func highlights(_ current: WeekSummary, _ previous: WeekSummary) -> [String] {
        var lines: [String] = []
        if let now = current.recovery, let before = previous.recovery {
            let delta = now - before
            if abs(delta) >= 3 {
                lines.append(String(format: "Récupération moyenne %@ de %.0f points (%.0f → %.0f).", delta > 0 ? "en hausse" : "en baisse", abs(delta), before, now))
            } else {
                lines.append(String(format: "Récupération stable autour de %.0f.", now))
            }
        }
        if previous.load > 0 {
            let change = (current.load / previous.load - 1) * 100
            if change > 10 {
                lines.append(String(format: "Charge en hausse de %.0f %% : surveille la fatigue la semaine prochaine.", change))
            } else if change < -25 {
                lines.append(String(format: "Charge en baisse de %.0f %% : semaine de récupération ou de coupure.", -change))
            }
        }
        if let performance = current.sleepPerformance {
            if performance < 0.85 {
                lines.append(String(format: "Sommeil à %.0f %% de ton besoin : c'est le levier n° 1 de la semaine prochaine.", performance * 100))
            } else if performance >= 0.95 {
                lines.append(String(format: "Excellent sommeil : %.0f %% de ton besoin couvert.", performance * 100))
            }
        }
        if let best = current.bestDay, let worst = current.worstDay, best.recovery - worst.recovery >= 20 {
            lines.append("Meilleure récup le \(best.date.formatted(.dateTime.weekday(.wide))), la plus basse le \(worst.date.formatted(.dateTime.weekday(.wide))) : regarde ce qui s'est passé la veille.")
        }
        if let change = current.weightChange, abs(change) >= 0.2 {
            lines.append(String(format: "Poids : %+.1f kg sur la semaine.", change))
        }
        return lines
    }
}
