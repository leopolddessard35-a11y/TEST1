import Foundation

/// Versions des formules : chaque changement d'algorithme incrémente sa version
/// pour que l'historique reste interprétable (affichées dans Réglages et dans l'export).
enum FormulaVersion {
    static let readiness = "readiness-2 (médiane/MAD 60 j, ln VFC)"
    static let load = "load-2 (TSS / sRPE, ACWR exponentiel 7/28 j)"
    static let effort = "effort-1 (0–21 logarithmique, k = 100/ln 3)"
    static let sleepNeed = "sleep-2 (base + effort + dette 14 j pondérée)"
    static let decision = "decision-2 (règles hiérarchisées, signaux rouges)"
    static let correlations = "corr-2 (Spearman, décalages J/J+1/J+2, IC 95 %)"

    static var all: [String] { [readiness, load, effort, sleepNeed, decision, correlations] }
}

/// Statistiques robustes (insensibles aux valeurs aberrantes).
enum Robust {
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    /// Écart absolu médian, mis à l'échelle (× 1,4826) pour être comparable à un écart-type.
    static func mad(_ values: [Double]) -> Double? {
        guard let center = median(values) else { return nil }
        return median(values.map { abs($0 - center) }).map { $0 * 1.4826 }
    }

    /// Score z robuste : (x − médiane) / MAD, avec un plancher de dispersion.
    static func z(_ value: Double, baseline: [Double], floor: Double) -> Double? {
        guard baseline.count >= 7, let center = median(baseline), let spread = mad(baseline) else { return nil }
        return (value - center) / max(spread, floor)
    }

    /// Rangs (ex aequo = rang moyen), pour Spearman.
    static func ranks(_ values: [Double]) -> [Double] {
        let indexed = values.enumerated().sorted { $0.element < $1.element }
        var ranks = [Double](repeating: 0, count: values.count)
        var index = 0
        while index < indexed.count {
            var end = index
            while end + 1 < indexed.count && indexed[end + 1].element == indexed[index].element { end += 1 }
            let rank = Double(index + end) / 2 + 1
            for position in index...end { ranks[indexed[position].offset] = rank }
            index = end + 1
        }
        return ranks
    }

    static func spearman(_ xs: [Double], _ ys: [Double]) -> Double? {
        guard xs.count == ys.count, xs.count >= 5 else { return nil }
        return Correlations.pearson(ranks(xs), ranks(ys))
    }

    /// Intervalle de confiance à 95 % d'un coefficient de corrélation (transformation de Fisher).
    static func confidenceInterval(r: Double, n: Int) -> ClosedRange<Double>? {
        guard n > 3 else { return nil }
        let clamped = min(max(r, -0.999), 0.999)
        let z = 0.5 * log((1 + clamped) / (1 - clamped))
        let se = 1 / Double(n - 3).squareRoot()
        let low = tanh(z - 1.96 * se), high = tanh(z + 1.96 * se)
        return low...high
    }

    /// Pente de régression (par jour) et statistique t associée.
    static func regression(_ points: [DayValue]) -> (slopePerDay: Double, t: Double)? {
        guard points.count >= 4, let first = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.value)
        guard let mx = Stats.mean(xs), let my = Stats.mean(ys) else { return nil }
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        let slope = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx
        let intercept = my - slope * mx
        let residual = zip(xs, ys).reduce(0) { $0 + pow($1.1 - (intercept + slope * $1.0), 2) }
        let se = (residual / Double(points.count - 2) / sxx).squareRoot()
        return (slope, se > 0 ? slope / se : (slope == 0 ? 0 : 99))
    }

    /// Moyenne exponentielle sur une série quotidienne (constante de temps en jours).
    static func ewma(_ daily: [Double], days: Double) -> Double {
        var value = 0.0
        let alpha = 1 - exp(-1 / days)
        for load in daily { value += alpha * (load - value) }
        return value
    }

    /// ACWR exponentiel : moyenne 7 j / moyenne 28 j (moins sensible aux effets de bord).
    static func acuteChronicRatio(_ daily: [Double]) -> Double? {
        guard daily.count >= 28 else { return nil }
        let acute = ewma(daily, days: 7)
        let chronic = ewma(daily, days: 28)
        return chronic > 3 ? acute / chronic : nil
    }

    /// Dette de sommeil sur 14 jours, les nuits anciennes pesant moins (× 0,85 par jour).
    static func decayedSleepDebt(need: Double, sleeps: [(daysAgo: Int, hours: Double)]) -> Double {
        sleeps.filter { $0.daysAgo < 14 }.reduce(0) { total, night in
            total + max(0, need - night.hours) * pow(0.85, Double(night.daysAgo))
        }
    }

    /// Décalage horaire social : différence moyenne d'heure de lever week-end vs semaine (minutes).
    static func socialJetlag(wakeTimes: [Date], calendar: Calendar = .current) -> Double? {
        var weekday: [Double] = []
        var weekend: [Double] = []
        for date in wakeTimes {
            let parts = calendar.dateComponents([.hour, .minute, .weekday], from: date)
            let minutes = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            if parts.weekday == 1 || parts.weekday == 7 { weekend.append(minutes) } else { weekday.append(minutes) }
        }
        guard weekday.count >= 3, weekend.count >= 2, let a = median(weekday), let b = median(weekend) else { return nil }
        return b - a
    }

    /// TRIMP d'Edwards : minutes par zone × coefficient de la zone (1 à 5).
    static func edwardsTRIMP(zoneSeconds: [Double]) -> Double? {
        guard zoneSeconds.count == 5, zoneSeconds.reduce(0, +) > 0 else { return nil }
        return zoneSeconds.enumerated().reduce(0) { $0 + $1.element / 60 * Double($1.offset + 1) }
    }

    /// Efficiency Factor : puissance normalisée (ou vitesse en m/min) / FC moyenne.
    static func efficiencyFactor(sport: Sport, normalizedPower: Double?, averagePower: Double?,
                                 meters: Double?, seconds: Double, averageHeartRate: Double?) -> Double? {
        guard let hr = averageHeartRate, hr > 60 else { return nil }
        if sport.isCycling, let power = normalizedPower ?? averagePower, power > 0 { return power / hr }
        if sport == .running, let meters, meters > 0, seconds > 0 { return meters / (seconds / 60) / hr }
        return nil
    }
}

/// Score de confiance d'une journée : combien de sources de données sont présentes.
struct DataConfidence: Equatable {
    let present: [String]
    let missing: [String]

    var ratio: Double { Double(present.count) / Double(max(1, present.count + missing.count)) }
    var label: String {
        switch ratio {
        case 0.8...: "Données complètes"
        case 0.5..<0.8: "Données partielles"
        default: "Données insuffisantes"
        }
    }
}
