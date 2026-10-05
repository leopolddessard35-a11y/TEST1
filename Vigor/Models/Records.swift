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
    // Données Garmin complètes (via Intervals.icu)
    /// VFC nocturne Garmin (rMSSD). Différente de la VFC Apple (SDNN) : jamais mélangées.
    var hrvRMSSD: Double?
    var sleepScore: Double?
    var garminReadiness: Double?
    var sleepingHeartRate: Double?
    var spO2: Double?
    var respiration: Double?
    var bodyFatPercent: Double?

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
    /// Intensité relative au seuil fournie par la source (IF).
    var providedIntensity: Double?

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
    var heightCm: Double = 0
    var birthYear: Int = 0
    var sexRaw: String = Sex.male.rawValue
    var intervalsAthleteID: String = "0"

    var sex: Sex { Sex(rawValue: sexRaw) ?? .male }

    var age: Int? {
        guard birthYear > 1900 else { return nil }
        return Calendar.current.component(.year, from: .now) - birthYear
    }

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

/// Séance prévue (calendrier Intervals.icu).
@Model
final class PlannedWorkout {
    @Attribute(.unique) var externalID: String
    var date: Date
    var name: String
    var details: String
    var sportRaw: String
    var plannedSeconds: Double?
    var plannedTSS: Double?

    var sport: Sport { Sport(rawValue: sportRaw) ?? .other }

    init(externalID: String, date: Date, name: String, details: String, sport: Sport) {
        self.externalID = externalID
        self.date = date
        self.name = name
        self.details = details
        self.sportRaw = sport.rawValue
    }
}

/// Aliment connu (scanné, recherché, de référence ou créé à la main). Valeurs pour 100 g.
@Model
final class FoodItem {
    @Attribute(.unique) var key: String
    var name: String
    var brand: String
    var barcode: String?
    var source: String
    var kcal100: Double
    var protein100: Double
    var carbs100: Double
    var fat100: Double
    var fiber100: Double?
    var sugar100: Double?
    var saturatedFat100: Double?
    var salt100: Double?
    var servingGrams: Double?
    var lastUsed: Date = Date.distantPast
    var useCount: Int = 0

    init(key: String, name: String, brand: String, barcode: String?, source: String,
         kcal100: Double, protein100: Double, carbs100: Double, fat100: Double) {
        self.key = key
        self.name = name
        self.brand = brand
        self.barcode = barcode
        self.source = source
        self.kcal100 = kcal100
        self.protein100 = protein100
        self.carbs100 = carbs100
        self.fat100 = fat100
    }
}

/// Ce que tu as mangé. Les valeurs nutritionnelles sont copiées pour que l'historique ne change jamais.
@Model
final class FoodEntry {
    var date: Date
    var mealRaw: String
    var grams: Double
    var itemKey: String
    var name: String
    var brand: String
    var kcal100: Double
    var protein100: Double
    var carbs100: Double
    var fat100: Double
    var fiber100: Double?
    var sugar100: Double?

    var meal: Meal { Meal(rawValue: mealRaw) ?? .snack }
    var kcal: Double { kcal100 * grams / 100 }
    var protein: Double { protein100 * grams / 100 }
    var carbs: Double { carbs100 * grams / 100 }
    var fat: Double { fat100 * grams / 100 }
    var fiber: Double { (fiber100 ?? 0) * grams / 100 }

    init(date: Date, meal: Meal, grams: Double, item: FoodItem) {
        self.date = date
        self.mealRaw = meal.rawValue
        self.grams = grams
        self.itemKey = item.key
        self.name = item.name
        self.brand = item.brand
        self.kcal100 = item.kcal100
        self.protein100 = item.protein100
        self.carbs100 = item.carbs100
        self.fat100 = item.fat100
        self.fiber100 = item.fiber100
        self.sugar100 = item.sugar100
    }
}
