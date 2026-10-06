import Foundation

/// Fraîcheur musculaire (0–100 %) : la fatigue de chaque muscle décroît de façon exponentielle après l'effort.
///
/// Fatigue = Σ séries effectives × e^(−heures / 36). La synthèse protéique et la récupération de la force
/// reviennent à la normale en 48 à 72 h après une séance d'hypertrophie : avec τ = 36 h, il reste ~26 % de la
/// fatigue à 48 h et ~14 % à 72 h. Les sorties vélo / course fatiguent aussi les jambes (TSS / 25 ≈ séries).
/// Fraîcheur = 100 × (1 − F / (F + 6)) : 6 séries « fraîches » ⇒ 50 %.
enum MuscleFreshness {
    struct Entry: Identifiable, Equatable {
        var id: Muscle { muscle }
        let muscle: Muscle
        let percent: Double
        let lastWorked: Date?
    }

    static let tauHours = 36.0
    static let halfPointSets = 6.0

    /// Muscles affichés (les plus parlants pour un PPL + vélo).
    static let displayed: [Muscle] = [.chest, .frontDelts, .sideDelts, .triceps, .biceps, .lats, .upperBack,
                                      .lowerBack, .abs, .glutes, .quads, .hamstrings, .calves]

    static func compute(sessions: [ExerciseSession],
                        cardio: [(date: Date, sport: Sport, tss: Double)],
                        now: Date = .now) -> [Entry] {
        var fatigue: [Muscle: Double] = [:]
        var last: [Muscle: Date] = [:]

        func add(_ muscle: Muscle, _ sets: Double, at date: Date) {
            let hours = max(0, now.timeIntervalSince(date) / 3600)
            guard hours < 24 * 7 else { return }
            fatigue[muscle, default: 0] += sets * exp(-hours / tauHours)
            if let previous = last[muscle] {
                if date > previous { last[muscle] = date }
            } else {
                last[muscle] = date
            }
        }

        for session in sessions {
            let sets = Double(session.workingSets.count)
            guard sets > 0 else { continue }
            let targets = MuscleMap.targets(for: session.exercise)
            for muscle in targets.primary { add(muscle, sets, at: session.date) }
            for muscle in targets.secondary { add(muscle, sets * 0.5, at: session.date) }
        }

        for ride in cardio {
            let equivalent = ride.tss / 25
            switch ride.sport {
            case .cycling, .indoorCycling:
                add(.quads, equivalent, at: ride.date)
                add(.glutes, equivalent * 0.7, at: ride.date)
                add(.calves, equivalent * 0.3, at: ride.date)
                add(.hamstrings, equivalent * 0.3, at: ride.date)
            case .running:
                add(.calves, equivalent, at: ride.date)
                add(.hamstrings, equivalent * 0.7, at: ride.date)
                add(.quads, equivalent * 0.7, at: ride.date)
                add(.glutes, equivalent * 0.5, at: ride.date)
            case .strength, .other:
                break
            }
        }

        return displayed.map { muscle in
            let f = fatigue[muscle] ?? 0
            return Entry(muscle: muscle, percent: 100 * (1 - f / (f + halfPointSets)), lastWorked: last[muscle])
        }
    }
}
