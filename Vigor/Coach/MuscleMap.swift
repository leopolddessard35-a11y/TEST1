import Foundation

struct MuscleTargets: Equatable {
    let primary: [Muscle]
    let secondary: [Muscle]

    static let unknown = MuscleTargets(primary: [], secondary: [])
}

enum Equipment {
    case barbell, dumbbell, machine, cable, bodyweight, other
}

/// Associe un exercice (nom Hevy, en anglais ou en français) aux muscles sollicités.
enum MuscleMap {
    private struct Rule {
        let keywords: [String]
        let targets: MuscleTargets
        let compound: Bool
    }

    private static func rule(_ keywords: [String], _ primary: [Muscle], _ secondary: [Muscle] = [], compound: Bool = false) -> Rule {
        Rule(keywords: keywords, targets: MuscleTargets(primary: primary, secondary: secondary), compound: compound)
    }

    /// L'ordre compte : les règles les plus précises d'abord (« leg curl » avant « curl »).
    private static let rules: [Rule] = [
        rule(["romanian deadlift", "rdl", "stiff leg", "soulevé de terre roumain"], [.hamstrings, .glutes], [.lowerBack, .forearms], compound: true),
        rule(["leg curl", "hamstring curl", "nordic", "leg curl allongé", "leg curl assis"], [.hamstrings], [.calves]),
        rule(["good morning", "back extension", "hyperextension", "extension lombaire"], [.lowerBack, .hamstrings], [.glutes]),
        rule(["deadlift", "soulevé de terre"], [.glutes, .hamstrings, .lowerBack], [.quads, .upperBack, .forearms], compound: true),
        rule(["hip thrust", "glute bridge", "pont fessier"], [.glutes], [.hamstrings], compound: true),
        rule(["bulgarian", "split squat", "lunge", "fente"], [.quads, .glutes], [.hamstrings, .adductors], compound: true),
        rule(["leg press", "presse à cuisses", "hack squat", "squat"], [.quads, .glutes], [.adductors, .lowerBack], compound: true),
        rule(["leg extension", "extension des jambes"], [.quads]),
        rule(["calf", "mollet"], [.calves]),
        rule(["hip adduction", "adductor", "adducteur"], [.adductors]),
        rule(["hip abduction", "abductor", "abducteur"], [.glutes]),
        rule(["close grip bench", "développé couché prise serrée"], [.triceps], [.chest, .frontDelts], compound: true),
        rule(["bench press", "chest press", "développé couché", "développé incliné", "push up", "pompe"], [.chest], [.triceps, .frontDelts], compound: true),
        rule(["chest dip", "dip"], [.chest, .triceps], [.frontDelts], compound: true),
        rule(["reverse fly", "rear delt", "face pull", "oiseau"], [.rearDelts], [.upperBack]),
        rule(["fly", "pec deck", "crossover", "écarté"], [.chest], [.frontDelts]),
        rule(["upright row", "rowing menton"], [.sideDelts], [.upperBack]),
        rule(["lateral raise", "élévation latérale"], [.sideDelts]),
        rule(["front raise", "élévation frontale"], [.frontDelts]),
        rule(["overhead press", "shoulder press", "military press", "arnold", "développé militaire", "développé épaules"], [.frontDelts], [.sideDelts, .triceps], compound: true),
        rule(["triceps", "skull crusher", "pushdown", "extension nuque"], [.triceps]),
        rule(["hammer curl", "curl marteau"], [.biceps], [.forearms]),
        rule(["wrist curl", "poignet"], [.forearms]),
        rule(["curl"], [.biceps], [.forearms]),
        rule(["pull up", "pullup", "chin up", "chinup", "traction"], [.lats], [.biceps, .upperBack], compound: true),
        rule(["pulldown", "tirage vertical", "pullover"], [.lats], [.biceps, .upperBack], compound: true),
        rule(["row", "rowing", "tirage horizontal"], [.upperBack, .lats], [.biceps, .rearDelts], compound: true),
        rule(["shrug", "haussement"], [.upperBack]),
        rule(["russian twist", "woodchop", "side plank", "oblique"], [.obliques], [.abs]),
        rule(["crunch", "plank", "gainage", "leg raise", "sit up", "situp", "ab wheel", "relevé de jambes"], [.abs], [.obliques]),
    ]

    private static func normalized(_ title: String) -> String {
        title.lowercased().replacingOccurrences(of: "-", with: " ")
    }

    private static func matchingRule(_ title: String) -> Rule? {
        let name = normalized(title)
        return rules.first { rule in rule.keywords.contains { name.contains($0) } }
    }

    static func targets(for exercise: String) -> MuscleTargets {
        matchingRule(exercise)?.targets ?? .unknown
    }

    static func isCompound(_ exercise: String) -> Bool {
        matchingRule(exercise)?.compound ?? false
    }

    static func equipment(for exercise: String) -> Equipment {
        let name = normalized(exercise)
        if name.contains("barbell") || name.contains("barre") { return .barbell }
        if name.contains("dumbbell") || name.contains("haltère") { return .dumbbell }
        if name.contains("machine") || name.contains("smith") { return .machine }
        if name.contains("cable") || name.contains("poulie") { return .cable }
        if name.contains("bodyweight") || name.contains("poids du corps") { return .bodyweight }
        return .other
    }

    /// Plage de répétitions conseillée pour la prise de masse.
    static func repRange(for exercise: String) -> ClosedRange<Int> {
        isCompound(exercise) ? 6...10 : 10...15
    }

    /// Plus petite augmentation de charge raisonnable (kg).
    static func increment(for exercise: String) -> Double {
        let lowerBody = targets(for: exercise).primary.contains { $0.region == .lowerBody }
        switch equipment(for: exercise) {
        case .barbell: return lowerBody ? 5 : 2.5
        case .dumbbell: return 2
        case .machine, .cable: return lowerBody ? 5 : 2.5
        case .bodyweight, .other: return 2.5
        }
    }

    /// Nombre de séries effectives par muscle (principal = 1, secondaire = 0,5).
    static func weeklySets(_ sessions: [ExerciseSession]) -> [Muscle: Double] {
        var volume: [Muscle: Double] = [:]
        for session in sessions {
            let sets = Double(session.workingSets.count)
            guard sets > 0 else { continue }
            let targets = targets(for: session.exercise)
            for muscle in targets.primary { volume[muscle, default: 0] += sets }
            for muscle in targets.secondary { volume[muscle, default: 0] += sets * 0.5 }
        }
        return volume
    }

    /// Volume hebdomadaire conseillé pour la prise de masse (séries par muscle).
    static let hypertrophyRange: ClosedRange<Double> = 10...20
}
