import Foundation

/// Type de sport d'une séance.
enum Sport: String, Codable, CaseIterable, Identifiable {
    case cycling
    case indoorCycling
    case running
    case strength
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cycling: "Vélo"
        case .indoorCycling: "Home trainer"
        case .running: "Course à pied"
        case .strength: "Musculation"
        case .other: "Autre"
        }
    }

    var symbol: String {
        switch self {
        case .cycling: "bicycle"
        case .indoorCycling: "figure.indoor.cycle"
        case .running: "figure.run"
        case .strength: "dumbbell.fill"
        case .other: "figure.mixed.cardio"
        }
    }

    var isCycling: Bool { self == .cycling || self == .indoorCycling }
}

/// Grandes zones du corps, pour regrouper les muscles.
enum BodyRegion: String, Codable, CaseIterable {
    case upperBody, core, lowerBody

    var label: String {
        switch self {
        case .upperBody: "Haut du corps"
        case .core: "Tronc"
        case .lowerBody: "Bas du corps"
        }
    }
}

/// Muscles suivis pour le volume d'entraînement et les blessures.
enum Muscle: String, Codable, CaseIterable, Identifiable {
    case chest, frontDelts, sideDelts, rearDelts, triceps, biceps, forearms
    case lats, upperBack, lowerBack, abs, obliques
    case glutes, quads, hamstrings, adductors, calves

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chest: "Pectoraux"
        case .frontDelts: "Épaules (avant)"
        case .sideDelts: "Épaules (côté)"
        case .rearDelts: "Épaules (arrière)"
        case .triceps: "Triceps"
        case .biceps: "Biceps"
        case .forearms: "Avant-bras"
        case .lats: "Grand dorsal"
        case .upperBack: "Haut du dos / trapèzes"
        case .lowerBack: "Lombaires"
        case .abs: "Abdominaux"
        case .obliques: "Obliques"
        case .glutes: "Fessiers"
        case .quads: "Quadriceps"
        case .hamstrings: "Ischio-jambiers"
        case .adductors: "Adducteurs"
        case .calves: "Mollets"
        }
    }

    var region: BodyRegion {
        switch self {
        case .chest, .frontDelts, .sideDelts, .rearDelts, .triceps, .biceps, .forearms, .lats, .upperBack:
            .upperBody
        case .lowerBack, .abs, .obliques:
            .core
        case .glutes, .quads, .hamstrings, .adductors, .calves:
            .lowerBody
        }
    }

    /// Muscles fortement sollicités au vélo et en course : une blessure ici limite l'intensité.
    var isLegDriver: Bool {
        [.glutes, .quads, .hamstrings, .calves, .adductors].contains(self)
    }
}

/// Raison pour laquelle tu ne peux pas t'entraîner.
enum UnavailabilityReason: String, Codable, CaseIterable, Identifiable {
    case illness, injury, travel, vacation, fatigue, motivation, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .illness: "Maladie"
        case .injury: "Blessure"
        case .travel: "Déplacement pro"
        case .vacation: "Vacances"
        case .fatigue: "Grosse fatigue"
        case .motivation: "Pas motivé"
        case .other: "Autre"
        }
    }

    var symbol: String {
        switch self {
        case .illness: "facemask.fill"
        case .injury: "bandage.fill"
        case .travel: "briefcase.fill"
        case .vacation: "sun.horizon.fill"
        case .fatigue: "battery.25percent"
        case .motivation: "sofa.fill"
        case .other: "calendar.badge.exclamationmark"
        }
    }
}

enum Sex: String, Codable, CaseIterable, Identifiable {
    case male, female

    var id: String { rawValue }
    var label: String { self == .male ? "Homme" : "Femme" }
}

enum Meal: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, snack, dinner, training

    var id: String { rawValue }

    var label: String {
        switch self {
        case .breakfast: "Petit-déjeuner"
        case .lunch: "Déjeuner"
        case .snack: "Goûter"
        case .dinner: "Dîner"
        case .training: "Pendant l'effort"
        }
    }

    var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .snack: "carrot.fill"
        case .dinner: "moon.stars.fill"
        case .training: "bicycle"
        }
    }

    /// Repas proposé par défaut selon l'heure.
    static func suggested(for date: Date = .now) -> Meal {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<15: .lunch
        case 15..<18: .snack
        default: .dinner
        }
    }
}

// MARK: - Journal de symptômes

enum BodyZone: String, Codable, CaseIterable, Identifiable {
    case foot, ankle, calf, shin, knee, hamstring, quad, hip, glute, lowerBack, upperBack, neck, shoulder, elbow, wrist, hand, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .foot: "Pied"
        case .ankle: "Cheville"
        case .calf: "Mollet"
        case .shin: "Tibia"
        case .knee: "Genou"
        case .hamstring: "Ischio"
        case .quad: "Quadriceps"
        case .hip: "Hanche"
        case .glute: "Fessier"
        case .lowerBack: "Bas du dos"
        case .upperBack: "Haut du dos"
        case .neck: "Nuque"
        case .shoulder: "Épaule"
        case .elbow: "Coude"
        case .wrist: "Poignet"
        case .hand: "Main"
        case .other: "Autre"
        }
    }
}

enum BodySide: String, Codable, CaseIterable, Identifiable {
    case left, right, both, center

    var id: String { rawValue }

    var label: String {
        switch self {
        case .left: "Gauche"
        case .right: "Droite"
        case .both: "Les deux"
        case .center: "Centre"
        }
    }
}

enum SymptomType: String, Codable, CaseIterable, Identifiable {
    case pain, numbness, tingling, stiffness, cramp, swelling, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pain: "Douleur"
        case .numbness: "Engourdissement"
        case .tingling: "Fourmillements"
        case .stiffness: "Raideur"
        case .cramp: "Crampe"
        case .swelling: "Gonflement"
        case .other: "Autre"
        }
    }
}

enum Terrain: String, Codable, CaseIterable, Identifiable {
    case road, trail, gravel, track, treadmill, indoor

    var id: String { rawValue }

    var label: String {
        switch self {
        case .road: "Route"
        case .trail: "Trail / chemin"
        case .gravel: "Gravel"
        case .track: "Piste"
        case .treadmill: "Tapis"
        case .indoor: "Home trainer"
        }
    }
}

// MARK: - Charge hors sport

enum LifeActivityKind: String, Codable, CaseIterable, Identifiable {
    case renovation, gardening, moving, standing, physicalWork, carrying, longWalk, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .renovation: "Travaux / rénovation"
        case .gardening: "Jardinage"
        case .moving: "Déménagement"
        case .standing: "Journée debout"
        case .physicalWork: "Travail physique"
        case .carrying: "Port de charges"
        case .longWalk: "Longue marche"
        case .other: "Autre"
        }
    }

    var symbol: String {
        switch self {
        case .renovation: "hammer.fill"
        case .gardening: "leaf.fill"
        case .moving: "shippingbox.fill"
        case .standing: "figure.stand"
        case .physicalWork: "wrench.and.screwdriver.fill"
        case .carrying: "figure.strengthtraining.functional"
        case .longWalk: "figure.walk"
        case .other: "ellipsis.circle"
        }
    }
}

enum GoalPriority: String, Codable, CaseIterable, Identifiable {
    case a = "A", b = "B", c = "C"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .a: "A · objectif principal"
        case .b: "B · objectif secondaire"
        case .c: "C · étape / préparation"
        }
    }
}
