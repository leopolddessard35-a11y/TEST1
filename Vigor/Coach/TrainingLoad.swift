import Foundation

/// Seuils physiologiques utilisés pour estimer la charge d'une séance.
struct Thresholds: Equatable {
    var ftp: Double?
    var cyclingLTHR: Double?
    var runningLTHR: Double?
    var maxHeartRate: Double?
}

/// Un jour du modèle de charge (Performance Management Chart).
struct LoadPoint: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    /// Charge du jour (TSS).
    let tss: Double
    /// Condition physique (Chronic Training Load, moyenne ~42 jours).
    let ctl: Double
    /// Fatigue (Acute Training Load, moyenne ~7 jours).
    let atl: Double
    /// Forme du jour = condition − fatigue de la veille (Training Stress Balance).
    let form: Double
}

enum TrainingLoad {
    static let ctlDays = 42.0
    static let atlDays = 7.0

    /// Part de l'écart (charge quotidienne − CTL) absorbée par la CTL en une semaine.
    static let weeklyCTLResponse = 1 - pow(1 - 1 / ctlDays, 7)

    /// Estime le TSS d'une séance à partir de la puissance, sinon de la FC, sinon de la durée.
    static func estimateTSS(sport: Sport,
                            durationSeconds: Double,
                            normalizedPower: Double? = nil,
                            averagePower: Double? = nil,
                            averageHeartRate: Double? = nil,
                            thresholds: Thresholds) -> Double {
        let hours = durationSeconds / 3600
        guard hours > 0 else { return 0 }

        if sport.isCycling, let ftp = thresholds.ftp, ftp > 0,
           let power = normalizedPower ?? averagePower.map({ $0 * 1.05 }), power > 0 {
            let intensity = power / ftp
            return hours * intensity * intensity * 100
        }

        let lthr: Double?
        if sport == .running {
            lthr = thresholds.runningLTHR ?? thresholds.cyclingLTHR ?? thresholds.maxHeartRate.map({ $0 * 0.89 })
        } else {
            lthr = thresholds.cyclingLTHR ?? thresholds.maxHeartRate.map({ $0 * 0.87 })
        }
        if let hr = averageHeartRate, hr > 0, let lthr, lthr > 0 {
            let intensity = min(hr / lthr, 1.2)
            return hours * intensity * intensity * 100
        }

        switch sport {
        case .strength: return hours * 40
        default: return hours * 50
        }
    }

    /// Intensité relative au seuil (IF) : puissance / FTP, sinon FC / FC seuil.
    static func intensityFactor(sport: Sport,
                                normalizedPower: Double? = nil,
                                averagePower: Double? = nil,
                                averageHeartRate: Double? = nil,
                                thresholds: Thresholds) -> Double? {
        if sport.isCycling, let ftp = thresholds.ftp, ftp > 0,
           let power = normalizedPower ?? averagePower.map({ $0 * 1.05 }), power > 0 {
            return power / ftp
        }
        let lthr = sport == .running
            ? (thresholds.runningLTHR ?? thresholds.cyclingLTHR ?? thresholds.maxHeartRate.map({ $0 * 0.89 }))
            : (thresholds.cyclingLTHR ?? thresholds.maxHeartRate.map({ $0 * 0.87 }))
        if let hr = averageHeartRate, hr > 0, let lthr, lthr > 0 {
            return min(hr / lthr, 1.2)
        }
        return nil
    }

    /// Additionne les TSS par jour.
    static func dailyTotals(_ items: [(date: Date, tss: Double)], calendar: Calendar = .current) -> [Date: Double] {
        var totals: [Date: Double] = [:]
        for item in items {
            totals[calendar.startOfDay(for: item.date), default: 0] += item.tss
        }
        return totals
    }

    /// Calcule condition / fatigue / forme jour par jour.
    static func series(daily: [Date: Double],
                       from start: Date,
                       to end: Date,
                       initialCTL: Double = 0,
                       initialATL: Double = 0,
                       calendar: Calendar = .current) -> [LoadPoint] {
        var ctl = initialCTL
        var atl = initialATL
        var points: [LoadPoint] = []
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)

        while day <= last {
            let tss = daily[day] ?? 0
            let form = ctl - atl
            ctl += (tss - ctl) / ctlDays
            atl += (tss - atl) / atlDays
            points.append(LoadPoint(date: day, tss: tss, ctl: ctl, atl: atl, form: form))
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return points
    }

    /// Progression de la condition sur 7 jours (points de CTL par semaine).
    static func rampRate(_ points: [LoadPoint]) -> Double? {
        guard points.count > 7, let last = points.last else { return nil }
        return last.ctl - points[points.count - 8].ctl
    }
}
