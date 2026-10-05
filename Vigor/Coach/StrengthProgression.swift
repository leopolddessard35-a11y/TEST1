import Foundation

struct LoggedSet: Equatable {
    var weightKg: Double?
    var reps: Int?
    var rpe: Double?
    var isWarmup: Bool = false
}

/// Toutes les séries d'un exercice lors d'une séance.
struct ExerciseSession: Equatable {
    let date: Date
    let exercise: String
    let sets: [LoggedSet]

    var workingSets: [LoggedSet] { sets.filter { !$0.isWarmup && ($0.reps ?? 0) > 0 } }

    var topWeight: Double { workingSets.compactMap(\.weightKg).max() ?? 0 }

    /// Répétitions minimales sur les séries faites à la charge maximale.
    var minRepsAtTop: Int {
        let top = topWeight
        return workingSets.filter { ($0.weightKg ?? 0) == top }.compactMap(\.reps).min() ?? 0
    }

    var bestEstimated1RM: Double {
        workingSets.map { StrengthProgression.estimated1RM(weight: $0.weightKg ?? 0, reps: $0.reps ?? 0) }.max() ?? 0
    }
}

struct ProgressionAdvice: Equatable, Identifiable {
    enum Action: String {
        case increase, keep, decrease, deload, avoid

        var label: String {
            switch self {
            case .increase: "Augmente"
            case .keep: "Garde"
            case .decrease: "Allège"
            case .deload: "Décharge"
            case .avoid: "Évite"
            }
        }

        var symbol: String {
            switch self {
            case .increase: "arrow.up.circle.fill"
            case .keep: "equal.circle.fill"
            case .decrease: "arrow.down.circle.fill"
            case .deload: "arrow.down.to.line.circle.fill"
            case .avoid: "exclamationmark.triangle.fill"
            }
        }
    }

    var id: String { exercise }
    let exercise: String
    let action: Action
    let suggestedWeightKg: Double?
    let targetReps: ClosedRange<Int>
    let reason: String
}

/// Progression des charges en « double progression » :
/// on monte les répétitions dans la plage, puis la charge quand le haut de la plage est atteint.
enum StrengthProgression {
    /// 1RM estimé (formule d'Epley).
    static func estimated1RM(weight: Double, reps: Int) -> Double {
        guard weight > 0, reps > 0 else { return 0 }
        return reps == 1 ? weight : weight * (1 + Double(reps) / 30)
    }

    static func roundToPlate(_ weight: Double, step: Double = 0.5) -> Double {
        (weight / step).rounded() * step
    }

    static func advise(exercise: String,
                       sessions: [ExerciseSession],
                       readiness: ReadinessLevel? = nil,
                       injuredMuscles: Set<Muscle> = []) -> ProgressionAdvice? {
        let range = MuscleMap.repRange(for: exercise)
        let increment = MuscleMap.increment(for: exercise)
        let targets = MuscleMap.targets(for: exercise)
        let ordered = sessions.filter { !$0.workingSets.isEmpty }.sorted { $0.date < $1.date }
        guard let last = ordered.last else { return nil }

        let top = last.topWeight
        let minReps = last.minRepsAtTop

        if !injuredMuscles.isDisjoint(with: targets.primary) {
            let zones = targets.primary.filter { injuredMuscles.contains($0) }.map(\.label).joined(separator: ", ")
            return ProgressionAdvice(exercise: exercise, action: .avoid, suggestedWeightKg: nil, targetReps: range,
                                     reason: "Zone blessée (\(zones)) : remplace cet exercice ou demande l'avis de ton kiné.")
        }

        // Exercice au poids du corps : on progresse en répétitions.
        if top == 0 {
            if minReps >= range.upperBound {
                return ProgressionAdvice(exercise: exercise, action: .increase, suggestedWeightKg: nil, targetReps: range,
                                         reason: "Haut de plage atteint : ajoute du lest ou passe à une variante plus dure.")
            }
            return ProgressionAdvice(exercise: exercise, action: .keep, suggestedWeightKg: nil, targetReps: range,
                                     reason: "Vise +1 répétition par série.")
        }

        // Trois séances de suite en baisse nette : décharge.
        let lastThree = Array(ordered.suffix(3)).map(\.bestEstimated1RM)
        if lastThree.count == 3, lastThree[0] > lastThree[1], lastThree[1] > lastThree[2],
           (lastThree[0] - lastThree[2]) / lastThree[0] > 0.05 {
            return ProgressionAdvice(exercise: exercise, action: .deload, suggestedWeightKg: roundToPlate(top * 0.85),
                                     targetReps: range,
                                     reason: "Performance en baisse sur 3 séances : semaine allégée (−15 %, moitié des séries) pour relancer la progression.")
        }

        if minReps >= range.upperBound {
            if readiness == .low {
                return ProgressionAdvice(exercise: exercise, action: .keep, suggestedWeightKg: top, targetReps: range,
                                         reason: "Progression validée, mais récupération basse aujourd'hui : garde \(format(top)) kg et monte la prochaine fois.")
            }
            return ProgressionAdvice(exercise: exercise, action: .increase, suggestedWeightKg: top + increment,
                                     targetReps: range.lowerBound...range.upperBound,
                                     reason: "\(minReps) reps sur toutes les séries à \(format(top)) kg : passe à \(format(top + increment)) kg et repars vers \(range.lowerBound) reps.")
        }

        if minReps < range.lowerBound {
            let previous = ordered.dropLast().last
            let stalled = previous.map { $0.topWeight == top && $0.minRepsAtTop < range.lowerBound } ?? false
            if stalled {
                let lighter = roundToPlate(top * 0.9)
                return ProgressionAdvice(exercise: exercise, action: .decrease, suggestedWeightKg: lighter, targetReps: range,
                                         reason: "Deux séances sous \(range.lowerBound) reps à \(format(top)) kg : redescends à \(format(lighter)) kg pour reconstruire.")
            }
            return ProgressionAdvice(exercise: exercise, action: .keep, suggestedWeightKg: top, targetReps: range,
                                     reason: "Charge encore un peu lourde : garde \(format(top)) kg et consolide.")
        }

        return ProgressionAdvice(exercise: exercise, action: .keep, suggestedWeightKg: top, targetReps: range,
                                 reason: "Garde \(format(top)) kg et vise +1 rep par série jusqu'à \(range.upperBound).")
    }

    private static func format(_ weight: Double) -> String {
        weight.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", weight) : String(format: "%.1f", weight)
    }
}
