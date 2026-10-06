import Foundation

struct ExperimentResult: Equatable {
    let before: Double?
    let during: Double?
    let nBefore: Int
    let nDuring: Int
    /// Taille d'effet (d de Cohen).
    let effectSize: Double?

    var changePercent: Double? {
        guard let before, let during, before != 0 else { return nil }
        return (during / before - 1) * 100
    }

    var verdict: String {
        guard nBefore >= 7, nDuring >= 7, let d = effectSize else {
            return "Pas encore assez de jours (7 avant et 7 pendant au minimum, idéalement 14 à 21)."
        }
        switch abs(d) {
        case ..<0.2: return "Pas d'effet visible pour l'instant."
        case ..<0.5: return "Effet faible, à confirmer en prolongeant l'essai."
        case ..<0.8: return "Effet modéré probable."
        default: return "Effet net."
        }
    }
}

enum ExperimentAnalysis {
    /// Compare la période de l'expérience à la même durée juste avant (max 21 jours de chaque côté).
    static func analyze(series: [DayValue], start: Date, end: Date?, today: Date = .now) -> ExperimentResult {
        let finish = min(end ?? today, today)
        let length = min(21 * 86_400, max(86_400, finish.timeIntervalSince(start)))
        let beforeStart = start.addingTimeInterval(-length)
        let before = series.filter { $0.date >= beforeStart && $0.date < start }.map(\.value)
        let during = series.filter { $0.date >= start && $0.date <= finish }.map(\.value)
        var effect: Double?
        if let a = Stats.mean(before), let b = Stats.mean(during),
           let sa = Stats.standardDeviation(before), let sb = Stats.standardDeviation(during) {
            let pooled = ((sa * sa + sb * sb) / 2).squareRoot()
            effect = pooled > 0 ? (b - a) / pooled : nil
        }
        return ExperimentResult(before: Stats.mean(before), during: Stats.mean(during),
                                nBefore: before.count, nDuring: during.count, effectSize: effect)
    }
}
