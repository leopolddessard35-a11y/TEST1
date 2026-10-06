import Foundation
import SwiftData

/// Un exercice dans une séance type : séries, plage de répétitions, repos.
struct RoutineItem: Codable, Hashable, Identifiable {
    var id = UUID()
    var exercise: String
    var sets: Int = 3
    var repLow: Int = 8
    var repHigh: Int = 12
    var restSeconds: Int = 120
    var note: String = ""

    var repText: String { repLow == repHigh ? "\(repLow)" : "\(repLow)–\(repHigh)" }
    var restText: String { String(format: "%d:%02d", restSeconds / 60, restSeconds % 60) }
}

/// Séance type (« Push A »), rangée dans un programme (« PPL »).
@Model
final class WorkoutRoutine {
    @Attribute(.unique) var routineID: String
    var name: String
    var program: String
    var order: Int
    var notes: String
    /// Exercices encodés en JSON (plus robuste que les tableaux de structures dans SwiftData).
    var itemsData: Data
    var createdAt: Date

    var items: [RoutineItem] {
        get { (try? JSONDecoder().decode([RoutineItem].self, from: itemsData)) ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(name: String, program: String, order: Int = 0, notes: String = "", items: [RoutineItem] = []) {
        self.routineID = UUID().uuidString
        self.name = name
        self.program = program
        self.order = order
        self.notes = notes
        self.itemsData = (try? JSONEncoder().encode(items)) ?? Data()
        self.createdAt = .now
    }
}

/// Exercice créé par toi, avec ses muscles (utilisés pour le volume et la fraîcheur musculaire).
@Model
final class CustomExercise {
    @Attribute(.unique) var name: String
    var primaryRaw: [String]
    var secondaryRaw: [String]
    var equipmentRaw: String
    var createdAt: Date

    var primary: [Muscle] { primaryRaw.compactMap(Muscle.init(rawValue:)) }
    var secondary: [Muscle] { secondaryRaw.compactMap(Muscle.init(rawValue:)) }
    var equipment: Equipment { Equipment(rawValue: equipmentRaw) ?? .other }

    init(name: String, primary: [Muscle], secondary: [Muscle], equipment: Equipment) {
        self.name = name
        self.primaryRaw = primary.map(\.rawValue)
        self.secondaryRaw = secondary.map(\.rawValue)
        self.equipmentRaw = equipment.rawValue
        self.createdAt = .now
    }
}
