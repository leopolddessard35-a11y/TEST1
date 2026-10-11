import Foundation

/// Score de sommeil 0–100 (formule « sleep-4 »), proche de ce que font Bevel ou Whoop :
/// pas seulement « as-tu dormi assez », mais aussi la qualité de la nuit.
///
/// - Durée vs besoin (50 %) : 100 % du besoin = 100 ; −2,5 points par % manquant.
/// - Efficacité (15 %) : temps endormi / temps entre endormissement et réveil. ≥ 90 % = 100, ≤ 70 % = 0.
/// - Stades (20 %) : sommeil profond ≥ 15 % et paradoxal ≥ 20 % de la nuit (repères adultes).
/// - Régularité (15 %) : écart de l'heure de coucher à ta médiane des 14 nuits ; 15 min de tolérance.
/// Une composante absente (pas de stades, pas d'historique) est retirée et les poids sont renormalisés.
struct SleepScoreResult: Equatable {
    let score: Int
    let components: [ReadinessComponent]

    var label: String {
        switch score {
        case 85...: "Excellente nuit"
        case 70..<85: "Bonne nuit"
        case 50..<70: "Nuit moyenne"
        default: "Nuit difficile"
        }
    }
}

enum SleepScoreCalculator {
    static func compute(asleepHours: Double,
                        needHours: Double,
                        bedtime: Date?,
                        wake: Date?,
                        deepHours: Double?,
                        remHours: Double?,
                        awakeHours: Double?,
                        usualBedtimeMinutes: Double?,
                        calendar: Calendar = .current) -> SleepScoreResult? {
        guard asleepHours > 0 else { return nil }
        var parts: [(ReadinessComponent, Double)] = []

        let ratio = asleepHours / max(needHours, 1)
        let durationScore = clamp(ratio >= 1 ? 100 : 100 - (1 - ratio) * 250)
        parts.append((ReadinessComponent(name: "Durée",
                                         score: durationScore,
                                         detail: "\(asleepHours.hoursText) dormies pour un besoin de \(needHours.hoursText)"), 0.5))

        if let bedtime, let wake, wake > bedtime {
            let window = wake.timeIntervalSince(bedtime) / 3600
            let awake = max(awakeHours ?? max(0, window - asleepHours), 0)
            let efficiency = min(1, asleepHours / max(asleepHours + awake, 0.1))
            let score = clamp((efficiency - 0.70) / 0.20 * 100)
            parts.append((ReadinessComponent(name: "Efficacité",
                                             score: score,
                                             detail: String(format: "%.0f %% du temps au lit passé à dormir · %@ d'éveils", locale: Locale.current,
                                                            efficiency * 100, awake.hoursText)), 0.15))
        }

        if let deepHours, let remHours, deepHours + remHours > 0 {
            let deepShare = deepHours / asleepHours
            let remShare = remHours / asleepHours
            let score = (min(1, deepShare / 0.15) + min(1, remShare / 0.20)) / 2 * 100
            parts.append((ReadinessComponent(name: "Stades",
                                             score: score,
                                             detail: String(format: "Profond %.0f %% (repère ≥ 15 %%) · paradoxal %.0f %% (repère ≥ 20 %%)", locale: Locale.current,
                                                            deepShare * 100, remShare * 100)), 0.2))
        }

        if let bedtime, let usualBedtimeMinutes {
            let tonight = SleepAnalytics.eveningMinutes(bedtime, calendar: calendar)
            let deviation = abs(tonight - usualBedtimeMinutes)
            let score = clamp(100 - max(0, deviation - 15) * 1.5)
            parts.append((ReadinessComponent(name: "Régularité",
                                             score: score,
                                             detail: String(format: "Coucher à %.0f min de ton heure habituelle", locale: Locale.current, deviation)), 0.15))
        }

        let total = parts.reduce(0) { $0 + $1.1 }
        let score = parts.reduce(0) { $0 + $1.0.score * $1.1 } / total
        let components: [ReadinessComponent] = parts.map { part in
            var component = part.0
            component.weight = part.1 / total
            return component
        }
        return SleepScoreResult(score: Int(clamp(score).rounded()), components: components)
    }

    private static func clamp(_ value: Double) -> Double { min(100, max(0, value)) }
}
