import Foundation

/// Versions des formules : chaque changement d'algorithme incrémente sa version
/// pour que l'historique reste interprétable (affichées dans Réglages et dans l'export).
enum FormulaVersion {
    static let readiness = "readiness-3 (VFC nuit 70 % + 7 j 30 %, médiane/MAD 60 j, zones 67/34, malus fatigue −10/−20)"
    static let load = "load-3 (TSS / sRPE, CTL/ATL et ACWR 7/28 j amorcés sur la moyenne des premiers jours, ACWR dès 21 j, alerte > 1,5)"
    static let effort = "effort-1 (0–21 logarithmique, k = 100/ln 3)"
    static let sleepNeed = "sleep-4 (nuit principale, siestes exclues ; besoin : base + effort + dette 14 nuits pondérées ; score : durée, efficacité, stades, régularité)"
    static let decision = "decision-3 (capacité : récup ≥ 67 +5 %, 45–66 neutre ; règles hiérarchisées, signaux rouges)"
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

    /// Valeur de départ d'une moyenne exponentielle : moyenne des N premiers jours disponibles
    /// (N = constante de temps, ou moins s'il y a moins de jours). Évite la sous-estimation du démarrage à 0.
    static func ewmaSeed(_ daily: [Double], days: Double) -> Double {
        let count = min(daily.count, max(1, Int(days.rounded())))
        guard count > 0 else { return 0 }
        return daily.prefix(count).reduce(0, +) / Double(count)
    }

    /// Moyenne exponentielle sur une série quotidienne (constante de temps en jours),
    /// amorcée par la moyenne des premiers jours (`ewmaSeed`).
    static func ewma(_ daily: [Double], days: Double) -> Double {
        var value = ewmaSeed(daily, days: days)
        let alpha = 1 - exp(-1 / days)
        for load in daily { value += alpha * (load - value) }
        return value
    }

    /// Historique minimal (jours) pour un ACWR fiable.
    static let minimumACWRDays = 21

    /// ACWR exponentiel : moyenne 7 j / moyenne 28 j (moins sensible aux effets de bord).
    /// nil s'il y a moins de 21 jours d'historique.
    static func acuteChronicRatio(_ daily: [Double]) -> Double? {
        guard daily.count >= minimumACWRDays else { return nil }
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
