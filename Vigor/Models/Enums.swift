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
