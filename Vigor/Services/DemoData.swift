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
            record.hrvRMSSD = Double.random(in: 48...66, using: &random)
            record.sleepScore = Double.random(in: 62...90, using: &random)
            record.respiration = Double.random(in: 14.2...15.2, using: &random)
            let vo2Drift: Double = Double(120 - offset) * 0.008
            record.vo2Max = 52 + vo2Drift
            record.restingHeartRate = Double.random(in: 46...53, using: &random)
            record.steps = Double.random(in: 6000...14000, using: &random)
            record.activeEnergyKcal = Double.random(in: 450...1100, using: &random)
            let bedMinutes = Int.random(in: -50...70, using: &random)
            if let bed = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day.addingTimeInterval(-86_400)) {
                record.bedtime = bed.addingTimeInterval(Double(bedMinutes) * 60)
                record.wakeTime = record.bedtime?.addingTimeInterval((record.sleepHours ?? 7.5) * 3600 + 1800)
            }
            if offset < 10 { record.waterMl = Double.random(in: 1500...3200, using: &random) }
            let drift: Double = Double(120 - offset) * 0.01
            let noise: Double = Double.random(in: -0.3...0.3, using: &random)
            record.weightKg = 72 + drift + noise
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
            // Zones de FC et dérive cardiaque simulées (la dérive diminue avec les semaines).
            let seconds = hours * 3600
            activity.zoneSeconds = indoor
                ? [seconds * 0.15, seconds * 0.35, seconds * 0.2, seconds * 0.22, seconds * 0.08]
                : [seconds * 0.2, seconds * 0.6, seconds * 0.15, seconds * 0.05, 0]
            activity.zonesComputed = true
            if hours >= 1.5 { activity.decouplingPercent = 2.5 + Double(offset) * 0.05 + Double.random(in: -1...1, using: &random) }
            if offset < 14 { activity.rpe = indoor ? Int.random(in: 6...8, using: &random) : Int.random(in: 3...5, using: &random) }
            if !indoor { activity.terrainRaw = (weekday == 1 ? Terrain.gravel : Terrain.road).rawValue }
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

        // Repas des 3 dernières semaines.
        let menuSpec: [(Meal, String, Double)] = [
            (.breakfast, "Flocons d'avoine", 80), (.breakfast, "Skyr", 150), (.breakfast, "Banane", 120),
            (.lunch, "Riz blanc", 250), (.lunch, "Blanc de poulet", 160), (.lunch, "Brocoli", 150),
            (.snack, "Amandes", 30),
            (.dinner, "Pâtes", 250), (.dinner, "Saumon", 140), (.dinner, "Huile", 10),
        ]
        let menu: [(Meal, FoodProduct, Double)] = menuSpec.compactMap { entry in
            CommonFoods.search(entry.1).first.map { (entry.0, $0, entry.2) }
        }
        var items: [String: FoodItem] = [:]
        for offset in 0..<21 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            for (meal, product, grams) in menu {
                let item = items[product.key] ?? {
                    let created = FoodItem(key: product.key, name: product.name, brand: product.brand, barcode: nil,
                                           source: product.source, kcal100: product.kcal100, protein100: product.protein100,
                                           carbs100: product.carbs100, fat100: product.fat100)
                    created.fiber100 = product.fiber100
                    created.servingGrams = product.servingGrams
                    created.lastUsed = now
                    context.insert(created)
                    return created
                }()
                items[product.key] = item
                let hour: Int
                switch meal {
                case .breakfast: hour = 7
                case .lunch: hour = 12
                case .snack: hour = 16
                default: hour = 20
                }
                let date = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
                let portion = grams * Double.random(in: 0.85...1.15, using: &random)
                context.insert(FoodEntry(date: date, meal: meal, grams: portion.rounded(), item: item))
            }
        }

        // Chaussures, sorties course (avant la blessure) et journal du pied gauche.
        let shoeA = Shoe(name: "Pegasus 41", initialKm: 420, isDefault: true)
        let shoeB = Shoe(name: "Novablast 5", initialKm: 80)
        context.insert(shoeA)
        context.insert(shoeB)
        for offset in stride(from: 100, through: 40, by: -4) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today),
                  let start = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: day) else { continue }
            let useA = offset % 8 == 0
            let minutes = Double(Int.random(in: 35...60, using: &random))
            let run = CardioActivity(externalID: "\(prefix)run-\(offset)", source: "Garmin", sport: .running,
                                     title: "Course · Garmin", start: start, durationSeconds: minutes * 60)
            run.distanceMeters = minutes / 5.5 * 1000
            run.averageHeartRate = Double.random(in: 140...152, using: &random)
            run.elevationGain = Double.random(in: 20...120, using: &random)
            run.averageCadence = Double.random(in: 166...176, using: &random)
            run.shoeID = useA ? shoeA.shoeID : shoeB.shoeID
            run.terrainRaw = (offset % 3 == 0 ? Terrain.trail : Terrain.road).rawValue
            run.rpe = Int.random(in: 4...6, using: &random)
            context.insert(run)
            // Engourdissement fréquent avec la paire A, plus tardif quand on est frais.
            if useA || offset % 12 == 0 {
                let fatigue = Int.random(in: 2...5, using: &random)
                let symptom = Symptom(date: start.addingTimeInterval(25 * 60), zone: .foot, side: .left, type: .numbness,
                                      intensity: Int.random(in: 3...6, using: &random), fatigue: fatigue)
                symptom.onsetMinutes = (useA ? 22 : 34) + (fatigue >= 4 ? -4 : 3)
                symptom.sportRaw = Sport.running.rawValue
                symptom.shoeID = run.shoeID
                symptom.terrainRaw = run.terrainRaw
                symptom.durationMinutes = 10
                context.insert(symptom)
            }
        }
        if let recent = calendar.date(byAdding: .day, value: -3, to: today) {
            let symptom = Symptom(date: recent, zone: .hamstring, side: .left, type: .pain, intensity: 3, fatigue: 3)
            symptom.note = "Gêne en montant les escaliers"
            context.insert(symptom)
        }

        // Charge hors sport : travaux le week-end dernier.
        if let renovation = calendar.date(byAdding: .day, value: -2, to: today) {
            context.insert(LifeActivity(date: renovation, kind: .renovation, minutes: 360, intensity: 2, note: "Peinture + ponçage"))
        }
        if let standing = calendar.date(byAdding: .day, value: -6, to: today) {
            context.insert(LifeActivity(date: standing, kind: .standing, minutes: 480, intensity: 1))
        }

        // Échéances.
        let goals: [(String, Int, Int, Sport, Double, GoalPriority)] = [
            ("The Traka 100", 2027, 4, .cycling, 100, .a),
            ("Semi-marathon", 2027, 3, .running, 21.1, .b),
            ("Sortie 200 km", 2027, 6, .cycling, 200, .b),
            ("Trail 30 km", 2027, 9, .running, 30, .c),
        ]
        for (name, year, month, sport, distance, priority) in goals {
            if let date = DateComponents(calendar: calendar, year: year, month: month, day: month == 4 ? 25 : 15).date {
                context.insert(Goal(name: name, date: date, sport: sport, distanceKm: distance, priority: priority))
            }
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
        try context.delete(model: FoodEntry.self)
        try context.delete(model: PlannedWorkout.self)
        try context.delete(model: LifeActivity.self)
        try context.delete(model: Symptom.self)
        try context.delete(model: Shoe.self)
        try context.delete(model: Goal.self)
        try context.delete(model: PlanBaseline.self)
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
