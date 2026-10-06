import Foundation

struct DayValue: Equatable {
    let date: Date
    let value: Double
}

enum ReadinessLevel: String {
    case ready, moderate, low

    var label: String {
        switch self {
        case .ready: "Prêt à charger"
        case .moderate: "Récupération moyenne"
        case .low: "Récupération basse"
        }
    }

    var advice: String {
        switch self {
        case .ready:
            "Bonne récupération : séance clé ou intensité OK aujourd'hui."
        case .moderate:
            "Séance prévue OK, mais garde l'intensité maîtrisée et écoute tes sensations."
        case .low:
            "Récupération sous ta normale : endurance très facile, mobilité ou repos conseillés."
        }
    }
}

struct ReadinessComponent: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let score: Double
    let detail: String
    /// Poids dans le score final (0–1).
    var weight: Double = 0

    /// Points apportés au score final.
    var contribution: Double { score * weight }
}

struct ReadinessResult: Equatable {
    let score: Int
    let level: ReadinessLevel
    let components: [ReadinessComponent]
}

/// Score de récupération inspiré de Bevel / HRV4Training : chaque mesure est comparée
/// à TA propre moyenne récente, pas à une norme générale.
enum ReadinessCalculator {
    static func compute(hrv: [DayValue],
                        restingHR: [DayValue],
                        lastNightSleepHours: Double?,
                        sleepNeedHours: Double,
                        form: Double?,
                        today: Date = .now,
                        calendar: Calendar = .current) -> ReadinessResult? {
        var weighted: [(component: ReadinessComponent, weight: Double)] = []

        if let component = hrvComponent(hrv, today: today, calendar: calendar) {
            weighted.append((component, 0.45))
        }
        if let component = restingHRComponent(restingHR, today: today, calendar: calendar) {
            weighted.append((component, 0.25))
        }
        if let hours = lastNightSleepHours, hours > 0 {
            let ratio = hours / max(sleepNeedHours, 1)
            let score = clamp(ratio >= 1 ? 100 : 100 - (1 - ratio) * 200)
            let detail = String(format: "%.1f h dormies (besoin : %.1f h)", hours, sleepNeedHours)
            weighted.append((ReadinessComponent(name: "Sommeil", score: score, detail: detail), 0.30))
        }

        guard !weighted.isEmpty else { return nil }
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        var score = weighted.reduce(0) { $0 + $1.component.score * $1.weight } / totalWeight

        var components: [ReadinessComponent] = weighted.map { item in
            var component = item.component
            component.weight = item.weight / totalWeight
            return component
        }
        if let form, form < -25 {
            let penalty = form < -35 ? 20.0 : 10.0
            score -= penalty
            components.append(ReadinessComponent(
                name: "Fatigue d'entraînement",
                score: clamp(100 + form * 2),
                detail: String(format: "Forme %.0f : fatigue accumulée élevée", form)))
        }

        let rounded = Int(clamp(score).rounded())
        let level: ReadinessLevel = rounded >= 70 ? .ready : (rounded >= 45 ? .moderate : .low)
        return ReadinessResult(score: rounded, level: level, components: components)
    }

    /// VFC : tendance 7 jours (moyenne du ln) comparée à ta base 60 jours (médiane ± MAD, robuste).
    static func hrvComponent(_ values: [DayValue], today: Date, calendar: Calendar) -> ReadinessComponent? {
        let baseline = values.filter { $0.value > 0 && isWithin(days: 60, $0.date, of: today, calendar: calendar) }
        let recent = baseline.filter { isWithin(days: 7, $0.date, of: today, calendar: calendar) }
        guard baseline.count >= 14, !recent.isEmpty else { return nil }

        let logBaseline = baseline.map { log($0.value) }
        guard let center = Robust.median(logBaseline) else { return nil }
        let spread = max(Robust.mad(logBaseline) ?? 0, 0.05)
        let recentLog = recent.map { log($0.value) }.reduce(0, +) / Double(recent.count)
        let z = (recentLog - center) / spread
        let deltaPercent = (exp(recentLog - center) - 1) * 100

        let detail = String(format: "%.0f ms sur 7 j · %+.0f %% vs ta base (%.0f–%.0f ms)",
                            exp(recentLog), deltaPercent, exp(center - spread), exp(center + spread))
        return ReadinessComponent(name: "VFC", score: clamp(70 + 20 * z), detail: detail)
    }

    /// FC au repos : dernière valeur comparée à ta base 60 jours (médiane ± MAD). Plus haute = moins bien.
    static func restingHRComponent(_ values: [DayValue], today: Date, calendar: Calendar) -> ReadinessComponent? {
        let baseline = values.filter { $0.value > 0 && isWithin(days: 60, $0.date, of: today, calendar: calendar) }
            .sorted { $0.date < $1.date }
        guard baseline.count >= 7, let latest = baseline.last,
              isWithin(days: 2, latest.date, of: today, calendar: calendar) else { return nil }

        let samples = baseline.map(\.value)
        guard let center = Robust.median(samples) else { return nil }
        let spread = max(Robust.mad(samples) ?? 0, 1)
        let z = (latest.value - center) / spread
        let detail = String(format: "%.0f bpm · %+.0f bpm vs ta base (%.0f)", latest.value, latest.value - center, center)
        return ReadinessComponent(name: "FC au repos", score: clamp(70 - 15 * z), detail: detail)
    }

    private static func isWithin(days: Int, _ date: Date, of today: Date, calendar: Calendar) -> Bool {
        let startToday = calendar.startOfDay(for: today)
        guard let lowerBound = calendar.date(byAdding: .day, value: -(days - 1), to: startToday) else { return false }
        let day = calendar.startOfDay(for: date)
        return day >= lowerBound && day <= startToday
    }

    private static func standardDeviation(_ values: [Double], mean: Double) -> Double {
        guard values.count > 1 else { return 0 }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    private static func clamp(_ value: Double) -> Double { min(100, max(0, value)) }
}
