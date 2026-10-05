import Foundation
import SwiftData

/// Données fictives pour essayer l'app dans le simulateur (sans iPhone ni Apple Santé).
@MainActor
enum DemoData {
    static let prefix = "demo|"

    static func load(into context: ModelContext, now: Date = .now) throws {
        try clear(context)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var random = SeededGenerator(seed: 42)

        // 120 jours de sommeil, VFC, FC repos, pas, poids.
        for offset in 0..<120 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let record = DailyWellness(day: day)
            record.sleepHours = Double.random(in: 6.2...8.4, using: &random)
            record.hrvMs = Double.random(in: 52...72, using: &random)
            record.restingHeartRate = Double.random(in: 46...53, using: &random)
            record.steps = Double.random(in: 6000...14000, using: &random)
            record.activeEnergyKcal = Double.random(in: 450...1100, using: &random)
            record.weightKg = 72 + Double(120 - offset) * 0.01 + Double.random(in: -0.3...0.3, using: &random)
            context.insert(record)
        }

        // Sorties vélo : 4 par semaine, dont une longue le week-end.
        for offset in 1..<120 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: day) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let hours: Double
            switch weekday {
            case 1: hours = Double.random(in: 2.0...3.0, using: &random)   // dimanche : sortie longue
            case 3, 5: hours = Double.random(in: 0.9...1.2, using: &random) // mardi, jeudi : home trainer
            case 7: hours = 1.5                                             // samedi
            default: continue
            }
            let indoor = weekday == 3 || weekday == 5
            let activity = CardioActivity(externalID: "\(prefix)ride-\(offset)", source: indoor ? "Zwift" : "Garmin",
                                          sport: indoor ? .indoorCycling : .cycling,
                                          title: indoor ? "Home trainer · Zwift" : "Sortie vélo · Garmin",
                                          start: start, durationSeconds: hours * 3600)
            activity.averagePower = indoor ? Double.random(in: 165...195, using: &random) : Double.random(in: 135...160, using: &random)
            activity.averageHeartRate = Double.random(in: 128...150, using: &random)
            activity.distanceMeters = hours * 27_000
            context.insert(activity)
        }

        // Musculation Push / Pull / Legs, lundi-mercredi-vendredi, charges qui progressent.
        let program: [(title: String, exercises: [(name: String, start: Double, step: Double)])] = [
            ("Push", [("Bench Press (Barbell)", 60, 2.5), ("Seated Overhead Press (Dumbbell)", 18, 1), ("Lateral Raise (Dumbbell)", 8, 0.5), ("Triceps Pushdown (Cable)", 25, 1)]),
            ("Pull", [("Lat Pulldown (Cable)", 50, 2.5), ("Bent Over Row (Barbell)", 55, 2.5), ("Face Pull (Cable)", 20, 1), ("Bicep Curl (Dumbbell)", 12, 0.5)]),
            ("Legs", [("Squat (Barbell)", 70, 2.5), ("Leg Press (Machine)", 120, 5), ("Leg Extension (Machine)", 40, 2.5), ("Standing Calf Raise (Machine)", 60, 2.5)]),
        ]
        var session = 0
        for offset in stride(from: 119, through: 1, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let start = calendar.date(bySettingHour: 12, minute: 15, second: 0, of: day) else { continue }
            guard [2, 4, 6].contains(calendar.component(.weekday, from: day)) else { continue }
            let block = program[session % 3]
            let progression = Double(session / 6) // +1 palier toutes les 2 semaines
            let workout = StrengthWorkout(externalID: "\(prefix)lift-\(offset)", title: block.title, start: start,
                                          end: start.addingTimeInterval(3900), notes: "")
            context.insert(workout)
            var sets: [StrengthSet] = []
            for exercise in block.exercises {
                let weight = exercise.start + exercise.step * progression
                let isCompound = MuscleMap.isCompound(exercise.name)
                let range = MuscleMap.repRange(for: exercise.name)
                for index in 0..<3 {
                    let reps = Int.random(in: range.lowerBound...range.upperBound, using: &random)
                    sets.append(StrengthSet(exercise: exercise.name, exerciseNotes: "", setIndex: index, setType: "normal",
                                            weightKg: weight, reps: reps, distanceKm: nil, durationSeconds: nil,
                                            rpe: isCompound ? 8 : 8.5, supersetID: nil))
                }
            }
            workout.sets = sets
            session += 1
        }

        // Ta blessure actuelle, pour voir l'adaptation du plan.
        if let injuryStart = calendar.date(byAdding: .day, value: -10, to: today) {
            context.insert(Injury(title: "Ischio gauche (démo)", muscles: [.hamstrings], affectsRunning: true,
                                  affectsCycling: false, severity: 2, start: injuryStart))
        }
        try context.save()
    }

    /// Efface toutes les données de l'app (le profil est conservé).
    static func clear(_ context: ModelContext) throws {
        try context.delete(model: DailyWellness.self)
        try context.delete(model: CardioActivity.self)
        try context.delete(model: StrengthSet.self)
        try context.delete(model: StrengthWorkout.self)
        try context.delete(model: Unavailability.self)
        try context.delete(model: Injury.self)
        try context.save()
    }
}

/// Générateur pseudo-aléatoire reproductible (mêmes données de démo à chaque fois).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
