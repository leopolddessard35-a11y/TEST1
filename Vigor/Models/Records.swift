import Foundation
import SwiftData

/// Données de santé d'une journée (sommeil de la nuit précédente, VFC, FC repos…).
@Model
final class DailyWellness {
    @Attribute(.unique) var day: Date
    var sleepHours: Double?
    var hrvMs: Double?
    var restingHeartRate: Double?
    var steps: Double?
    var activeEnergyKcal: Double?
    var weightKg: Double?
    var vo2Max: Double?

    init(day: Date) {
        self.day = day
    }
}

/// Séance d'endurance (vélo, home trainer, course…).
@Model
final class CardioActivity {
    @Attribute(.unique) var externalID: String
    var source: String
    var sportRaw: String
    var title: String
    var start: Date
    var durationSeconds: Double
    var distanceMeters: Double?
    var averageHeartRate: Double?
    var averagePower: Double?
    var normalizedPower: Double?
    var energyKcal: Double?
    /// TSS fourni par la source (ex. Intervals.icu). Sinon il est estimé à l'affichage.
    var providedTSS: Double?

    var sport: Sport { Sport(rawValue: sportRaw) ?? .other }

    init(externalID: String, source: String, sport: Sport, title: String, start: Date, durationSeconds: Double) {
        self.externalID = externalID
        self.source = source
        self.sportRaw = sport.rawValue
        self.title = title
        self.start = start
        self.durationSeconds = durationSeconds
    }
}

/// Séance de musculation importée depuis Hevy.
@Model
final class StrengthWorkout {
    @Attribute(.unique) var externalID: String
    var title: String
    var start: Date
    var end: Date?
    var notes: String
    @Relationship(deleteRule: .cascade, inverse: \StrengthSet.workout)
    var sets: [StrengthSet] = []

    var durationSeconds: Double {
        guard let end else { return 3600 }
        return max(0, end.timeIntervalSince(start))
    }

    init(externalID: String, title: String, start: Date, end: Date?, notes: String) {
        self.externalID = externalID
        self.title = title
        self.start = start
        self.end = end
        self.notes = notes
    }
}

/// Une série (tout le détail de l'export Hevy est conservé).
@Model
final class StrengthSet {
    var exercise: String
    var exerciseNotes: String
    var setIndex: Int
    /// normal, warmup, failure, dropset
    var setType: String
    var weightKg: Double?
    var reps: Int?
    var distanceKm: Double?
    var durationSeconds: Double?
    var rpe: Double?
    var supersetID: Int?
    var workout: StrengthWorkout?

    var isWarmup: Bool { setType.lowercased() == "warmup" }

    init(exercise: String, exerciseNotes: String, setIndex: Int, setType: String,
         weightKg: Double?, reps: Int?, distanceKm: Double?, durationSeconds: Double?,
         rpe: Double?, supersetID: Int?) {
        self.exercise = exercise
        self.exerciseNotes = exerciseNotes
        self.setIndex = setIndex
        self.setType = setType
        self.weightKg = weightKg
        self.reps = reps
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.rpe = rpe
        self.supersetID = supersetID
    }
}

/// Période où tu ne peux pas t'entraîner (maladie, déplacement, vacances…).
@Model
final class Unavailability {
    var start: Date
    var end: Date
    var reasonRaw: String
    var note: String

    var reason: UnavailabilityReason { UnavailabilityReason(rawValue: reasonRaw) ?? .other }

    init(start: Date, end: Date, reason: UnavailabilityReason, note: String = "") {
        self.start = start
        self.end = end
        self.reasonRaw = reason.rawValue
        self.note = note
    }
}

/// Blessure en cours ou passée.
@Model
final class Injury {
    var title: String
    var musclesRaw: [String]
    var affectsRunning: Bool
    var affectsCycling: Bool
    /// 1 = gêne légère, 2 = modérée, 3 = sévère
    var severity: Int
    var start: Date
    var resolvedAt: Date?
    var note: String

    var muscles: Set<Muscle> { Set(musclesRaw.compactMap(Muscle.init(rawValue:))) }
    var isActive: Bool { resolvedAt == nil }

    init(title: String, muscles: Set<Muscle>, affectsRunning: Bool, affectsCycling: Bool,
         severity: Int, start: Date, note: String = "") {
        self.title = title
        self.musclesRaw = muscles.map(\.rawValue).sorted()
        self.affectsRunning = affectsRunning
        self.affectsCycling = affectsCycling
        self.severity = severity
        self.start = start
        self.note = note
    }
}

/// Profil sportif et objectifs. Une seule instance.
@Model
final class AthleteProfile {
    var ftp: Double = 206
    /// FC au seuil en vélo (0 = inconnue, estimée depuis la FC max).
    var cyclingLTHR: Double = 0
    /// FC au seuil en course (0 = inconnue).
    var runningLTHR: Double = 0
    var maxHeartRate: Double = 0
    var weightKg: Double = 0
    var raceName: String = "The Traka 100"
    var raceDate: Date = AthleteProfile.defaultRaceDate
    /// Condition (CTL) visée le jour de la course.
    var targetRaceCTL: Double = 60
    var weeklyHoursAvailable: Double = 8
    var strengthSessionsPerWeek: Int = 3
    var sleepNeedHours: Double = 8

    init() {}

    static var defaultRaceDate: Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), year: 2027, month: 4, day: 25).date ?? .now
    }

    var thresholds: Thresholds {
        Thresholds(
            ftp: ftp > 0 ? ftp : nil,
            cyclingLTHR: cyclingLTHR > 0 ? cyclingLTHR : nil,
            runningLTHR: runningLTHR > 0 ? runningLTHR : nil,
            maxHeartRate: maxHeartRate > 0 ? maxHeartRate : nil
        )
    }
}
