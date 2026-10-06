import Foundation

/// Grands groupes pour filtrer la banque d'exercices.
enum MuscleGroup: String, CaseIterable, Identifiable {
    case chest, back, shoulders, arms, legs, core

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: "Pectoraux"
        case .back: "Dos"
        case .shoulders: "Épaules"
        case .arms: "Bras"
        case .legs: "Jambes"
        case .core: "Abdos"
        }
    }

    var symbol: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .shoulders: "figure.arms.open"
        case .arms: "dumbbell.fill"
        case .legs: "figure.step.training"
        case .core: "figure.core.training"
        }
    }

    var muscles: Set<Muscle> {
        switch self {
        case .chest: [.chest]
        case .back: [.lats, .upperBack, .lowerBack]
        case .shoulders: [.frontDelts, .sideDelts, .rearDelts]
        case .arms: [.biceps, .triceps, .forearms]
        case .legs: [.quads, .hamstrings, .glutes, .adductors, .calves]
        case .core: [.abs, .obliques]
        }
    }

    static func of(_ muscle: Muscle) -> MuscleGroup? {
        allCases.first { $0.muscles.contains(muscle) }
    }
}

/// Un exercice de la banque (intégré ou créé par toi).
struct LibraryExercise: Identifiable, Hashable {
    var id: String { name.lowercased() }
    let name: String
    let equipment: Equipment
    var isCustom = false

    var targets: MuscleTargets { MuscleMap.targets(for: name) }
    var group: MuscleGroup? { targets.primary.first.flatMap(MuscleGroup.of) }
    var musclesText: String { targets.primary.map(\.label).joined(separator: ", ") }
}

/// Banque d'exercices intégrée (noms reconnus par la carte des muscles, donc volume et fraîcheur calculés).
enum ExerciseLibrary {
    private static func e(_ name: String, _ equipment: Equipment) -> LibraryExercise {
        LibraryExercise(name: name, equipment: equipment)
    }

    static let builtIn: [LibraryExercise] = [
        // Pectoraux
        e("Développé couché (barre)", .barbell), e("Développé couché (haltères)", .dumbbell),
        e("Développé incliné (barre)", .barbell), e("Développé incliné (haltères)", .dumbbell),
        e("Développé décliné (barre)", .barbell), e("Chest press (machine)", .machine),
        e("Écarté couché (haltères)", .dumbbell), e("Écarté à la poulie", .cable), e("Pec deck", .machine),
        e("Pompes", .bodyweight), e("Dips", .bodyweight),
        // Dos
        e("Tractions", .bodyweight), e("Tractions prise neutre", .bodyweight), e("Tirage vertical (poulie)", .cable),
        e("Tirage horizontal (poulie)", .cable), e("Rowing barre", .barbell), e("Rowing haltère", .dumbbell),
        e("Rowing T-bar", .barbell), e("Pullover à la poulie", .cable), e("Soulevé de terre (barre)", .barbell),
        e("Shrugs (haltères)", .dumbbell), e("Extension lombaire", .bodyweight),
        // Épaules
        e("Développé militaire (barre)", .barbell), e("Développé épaules (haltères)", .dumbbell),
        e("Développé Arnold", .dumbbell), e("Élévation latérale (haltères)", .dumbbell),
        e("Élévation latérale à la poulie", .cable), e("Élévation frontale (haltères)", .dumbbell),
        e("Oiseau (haltères)", .dumbbell), e("Reverse fly (machine)", .machine), e("Face pull", .cable),
        e("Rowing menton", .barbell),
        // Bras
        e("Curl biceps (barre)", .barbell), e("Curl biceps (haltères)", .dumbbell), e("Curl incliné (haltères)", .dumbbell),
        e("Curl marteau", .dumbbell), e("Curl pupitre", .machine), e("Curl à la poulie", .cable),
        e("Extension triceps à la poulie", .cable), e("Barre au front", .barbell), e("Extension nuque (haltère)", .dumbbell),
        e("Développé couché prise serrée", .barbell),
        // Jambes
        e("Squat (barre)", .barbell), e("Front squat", .barbell), e("Goblet squat", .dumbbell), e("Hack squat", .machine),
        e("Presse à cuisses", .machine), e("Fentes marchées (haltères)", .dumbbell), e("Fentes bulgares", .dumbbell),
        e("Montée sur banc (haltères)", .dumbbell), e("Leg extension", .machine), e("Leg curl allongé", .machine),
        e("Leg curl assis", .machine), e("Nordic curl", .bodyweight), e("Soulevé de terre roumain (barre)", .barbell),
        e("Soulevé de terre roumain (haltères)", .dumbbell), e("Hip thrust", .barbell), e("Good morning", .barbell),
        e("Mollets debout", .machine), e("Mollets assis", .machine), e("Adducteurs (machine)", .machine),
        e("Abducteurs (machine)", .machine),
        // Abdos
        e("Crunch", .bodyweight), e("Crunch à la poulie", .cable), e("Gainage", .bodyweight), e("Gainage latéral", .bodyweight),
        e("Relevé de jambes suspendu", .bodyweight), e("Roue abdominale", .other), e("Russian twist", .bodyweight)
    ]

    /// Banque complète : tes exercices perso, ceux de ton historique, puis la banque intégrée (sans doublon).
    static func all(custom: [CustomExercise], history: [String]) -> [LibraryExercise] {
        var seen = Set<String>()
        var result: [LibraryExercise] = []
        func add(_ exercise: LibraryExercise) {
            let key = exercise.name.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            result.append(exercise)
        }
        for item in custom { add(LibraryExercise(name: item.name, equipment: item.equipment, isCustom: true)) }
        for exercise in builtIn { add(exercise) }
        for name in history { add(LibraryExercise(name: name, equipment: MuscleMap.equipment(for: name))) }
        return result
    }

    /// Recopie les muscles des exercices perso dans la carte des muscles.
    static func registerCustom(_ exercises: [CustomExercise]) {
        var map: [String: MuscleTargets] = [:]
        for exercise in exercises {
            map[exercise.name.lowercased().replacingOccurrences(of: "-", with: " ")] =
                MuscleTargets(primary: exercise.primary, secondary: exercise.secondary)
        }
        MuscleMap.custom = map
    }
}

/// Programmes prêts à l'emploi.
enum ProgramTemplates {
    static let pplName = "PPL"

    /// PPL hypertrophie 3×/semaine, compatible avec le vélo (jambes sans excès d'excentrique, ischio protégé).
    static func ppl() -> [(name: String, items: [RoutineItem])] {
        [
            (name: "Push", items: [
                RoutineItem(exercise: "Développé couché (barre)", sets: 4, repLow: 6, repHigh: 10, restSeconds: 180),
                RoutineItem(exercise: "Développé incliné (haltères)", sets: 3, repLow: 8, repHigh: 12, restSeconds: 120),
                RoutineItem(exercise: "Développé épaules (haltères)", sets: 3, repLow: 8, repHigh: 12, restSeconds: 120),
                RoutineItem(exercise: "Élévation latérale (haltères)", sets: 4, repLow: 12, repHigh: 15, restSeconds: 75),
                RoutineItem(exercise: "Écarté à la poulie", sets: 3, repLow: 12, repHigh: 15, restSeconds: 75),
                RoutineItem(exercise: "Extension triceps à la poulie", sets: 3, repLow: 10, repHigh: 15, restSeconds: 75)
            ]),
            (name: "Pull", items: [
                RoutineItem(exercise: "Tractions", sets: 4, repLow: 6, repHigh: 10, restSeconds: 150),
                RoutineItem(exercise: "Rowing barre", sets: 3, repLow: 8, repHigh: 12, restSeconds: 120),
                RoutineItem(exercise: "Tirage vertical (poulie)", sets: 3, repLow: 10, repHigh: 12, restSeconds: 90),
                RoutineItem(exercise: "Face pull", sets: 3, repLow: 12, repHigh: 15, restSeconds: 60),
                RoutineItem(exercise: "Curl incliné (haltères)", sets: 3, repLow: 10, repHigh: 12, restSeconds: 75),
                RoutineItem(exercise: "Curl marteau", sets: 3, repLow: 10, repHigh: 12, restSeconds: 60)
            ]),
            (name: "Legs", items: [
                RoutineItem(exercise: "Squat (barre)", sets: 4, repLow: 6, repHigh: 10, restSeconds: 180),
                RoutineItem(exercise: "Presse à cuisses", sets: 3, repLow: 10, repHigh: 12, restSeconds: 120),
                RoutineItem(exercise: "Leg extension", sets: 3, repLow: 12, repHigh: 15, restSeconds: 75),
                RoutineItem(exercise: "Leg curl assis", sets: 3, repLow: 10, repHigh: 12, restSeconds: 90,
                            note: "Charge légère et sans douleur tant que l'ischio gauche est sensible."),
                RoutineItem(exercise: "Hip thrust", sets: 3, repLow: 8, repHigh: 12, restSeconds: 120),
                RoutineItem(exercise: "Mollets debout", sets: 4, repLow: 10, repHigh: 15, restSeconds: 60)
            ])
        ]
    }
}
