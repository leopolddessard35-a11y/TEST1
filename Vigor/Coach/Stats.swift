import Foundation

/// Petits outils statistiques partagés par les algorithmes.
enum Stats {
    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let mean = mean(values) else { return nil }
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count - 1)
        return variance.squareRoot()
    }

    /// Pente d'une régression linéaire (unités par jour).
    static func slopePerDay(_ points: [DayValue]) -> Double? {
        guard points.count >= 3, let first = points.first?.date else { return nil }
        let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = points.map(\.value)
        guard let mx = mean(xs), let my = mean(ys) else { return nil }
        let numerator = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let denominator = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        return denominator == 0 ? nil : numerator / denominator
    }

    /// Valeurs des `days` derniers jours (aujourd'hui inclus).
    static func lastDays(_ days: Int, of values: [DayValue], today: Date, calendar: Calendar = .current) -> [DayValue] {
        let end = calendar.startOfDay(for: today)
        guard let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) else { return [] }
        return values.filter {
            let day = calendar.startOfDay(for: $0.date)
            return day >= start && day <= end
        }
    }

    /// Moyenne mobile exponentielle (lissage du poids façon « Hacker's Diet »).
    static func exponentialTrend(_ values: [DayValue], alpha: Double = 0.1) -> [DayValue] {
        var trend: Double?
        return values.sorted { $0.date < $1.date }.map { point in
            let next = trend.map { $0 + alpha * (point.value - $0) } ?? point.value
            trend = next
            return DayValue(date: point.date, value: next)
        }
    }
}
