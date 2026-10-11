import Foundation
import SwiftData

/// Données de santé d'une journée (sommeil de la nuit précédente, VFC, FC repos…).
@Model
final class DailyWellness {
    @Attribute(.unique) var day: Date
    /// Durée de la nuit principale selon Apple Santé (siestes exclues). Garmin : `sleepHoursGarmin`.
    var sleepHours: Double?
    var hrvMs: Double?
    /// FC de repos Apple Santé. Garmin : `restingHeartRateGarmin`.
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
    /// Fréquence respiratoire Apple Santé. Garmin : `respirationGarmin`.
    var respiration: Double?
    var bodyFatPercent: Double?
    /// Valeurs Garmin (Intervals.icu), stockées à part pour ne jamais écraser ni mélanger les valeurs Apple :
    /// le coach choisit UNE source par métrique sur tout l'historique (voir `CoachSnapshot`).
    var sleepHoursGarmin: Double?
    var restingHeartRateGarmin: Double?
    var respirationGarmin: Double?
    /// VO2max et poids Garmin (Intervals.icu) : à part, pour ne jamais mélanger deux capteurs jour par jour.
    var vo2MaxGarmin: Double?
    var weightKgGarmin: Double?
    /// Heure d'endormissement et de réveil (régularité du sommeil).
    var bedtime: Date?
    var wakeTime: Date?
    /// Stades de sommeil (heures), lus dans Apple Santé quand la montre les fournit.
    var sleepDeepHours: Double?
    var sleepREMHours: Double?
    var sleepCoreHours: Double?
    /// Éveils pendant la nuit (heures).
    var sleepAwakeHours: Double?
    /// Eau bue (saisie manuelle), en ml.
    var waterMl: Double?

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
    /// Effort ressenti 1–10 (saisi après la séance).
    var rpe: Int?
    /// Secondes passées dans les zones de FC 1 à 5.
    var zoneSeconds: [Double] = []
    /// Dérive cardiaque / découplage (%) : < 5 % = bonne endurance aérobie.
    var decouplingPercent: Double?
    var averageCadence: Double?
    var elevationGain: Double?
    var terrainRaw: String?
    var shoeID: String?
    var zonesComputed: Bool = false

    var terrain: Terrain? { terrainRaw.flatMap(Terrain.init(rawValue:)) }

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
    /// Effort ressenti 1–10 (saisi après la séance).
    var rpe: Int?
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
    /// FTP en watts (0 = inconnue : pas de TSS calculé depuis la puissance).
    var ftp: Double = 0
    /// FC au seuil en vélo (0 = inconnue, estimée depuis la FC max).
    var cyclingLTHR: Double = 0
    /// FC au seuil en course (0 = inconnue).
    var runningLTHR: Double = 0
    var maxHeartRate: Double = 0
    var weightKg: Double = 0
    /// Nom de l'objectif (vide = pas encore renseigné, l'interface affiche « Objectif »).
    var raceName: String = ""
    var raceDate: Date = AthleteProfile.defaultRaceDate
    /// Condition (CTL) visée le jour de la course.
    var targetRaceCTL: Double = 60
    var weeklyHoursAvailable: Double = 8
    var strengthSessionsPerWeek: Int = 3
    /// Séances de vélo par semaine (sortie longue et intensité comprises).
    var bikeSessionsPerWeek: Int = 3
    var sleepNeedHours: Double = 8
    var heightCm: Double = 0
    var birthYear: Int = 0
    var sexRaw: String = Sex.male.rawValue
    var intervalsAthleteID: String = "0"
    /// Minutes disponibles par jour, du dimanche au samedi, séparées par des virgules (0 = pas de limite).
    var weekdayMinutesRaw: String = "0,0,0,0,0,0,0"
    /// Objectif de poids (WeightGoal.rawValue).
    var weightGoalRaw: String = WeightGoal.gain.rawValue
    /// Écart calorique visé par rapport à la dépense (kcal/j), en mode automatique.
    var calorieAdjustment: Double = 300
    var proteinPerKg: Double = 1.8
    var fatPerKg: Double = 1.0
    /// Mode manuel : calories et macros fixées à la main, chaque jour.
    var manualTargets: Bool = false
    var manualKcal: Double = 0
    var manualProtein: Double = 0
    var manualCarbs: Double = 0
    var manualFat: Double = 0

    var weightGoal: WeightGoal { WeightGoal(rawValue: weightGoalRaw) ?? .gain }

    /// Réglages nutrition passés au calcul des objectifs.
    var nutritionGoal: NutritionGoal {
        var goal = NutritionGoal(goal: weightGoal, adjustment: calorieAdjustment,
                                 proteinPerKg: proteinPerKg, fatPerKg: fatPerKg)
        if manualTargets, manualKcal > 0 {
            goal.manual = ManualMacros(kcal: manualKcal, protein: manualProtein, carbs: manualCarbs, fat: manualFat)
        }
        return goal
    }

    var weekdayMinutes: [Int] {
        let values = weekdayMinutesRaw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return values.count == 7 ? values : [0, 0, 0, 0, 0, 0, 0]
    }

    /// Minutes disponibles pour un jour (calendrier : 1 = dimanche), nil = pas de contrainte.
    func availableMinutes(weekday: Int) -> Int? {
        let minutes = weekdayMinutes[min(max(weekday - 1, 0), 6)]
        return minutes > 0 ? minutes : nil
    }

    var sex: Sex { Sex(rawValue: sexRaw) ?? .male }

    var age: Int? {
        guard birthYear > 1900 else { return nil }
        return Calendar.current.component(.year, from: .now) - birthYear
    }

    init() {}

    /// Objectif par défaut : dans 6 mois (à remplacer par la vraie date).
    static var defaultRaceDate: Date {
        let calendar = Calendar.current
        let inSixMonths = calendar.date(byAdding: .month, value: 6, to: .now) ?? .now
        return calendar.startOfDay(for: inSixMonths)
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

/// Activité physique hors sport : elle fatigue autant qu'une séance.
@Model
final class LifeActivity {
    var date: Date
    var kindRaw: String
    var minutes: Int
    /// 1 = légère, 2 = modérée, 3 = dure
    var intensity: Int
    var note: String

    var kind: LifeActivityKind { LifeActivityKind(rawValue: kindRaw) ?? .other }

    /// Équivalent TSS : ~20 / 35 / 50 points par heure selon l'intensité.
    var loadEquivalent: Double {
        let perHour: Double = intensity >= 3 ? 50 : (intensity == 2 ? 35 : 20)
        return Double(minutes) / 60 * perHour
    }

    init(date: Date, kind: LifeActivityKind, minutes: Int, intensity: Int, note: String = "") {
        self.date = date
        self.kindRaw = kind.rawValue
        self.minutes = minutes
        self.intensity = intensity
        self.note = note
    }
}

/// Entrée du journal de symptômes.
@Model
final class Symptom {
    var date: Date
    var zoneRaw: String
    var sideRaw: String
    var typeRaw: String
    /// 0–10
    var intensity: Int
    /// Minutes après le début de l'effort (nil = hors effort).
    var onsetMinutes: Int?
    var sportRaw: String?
    var shoeID: String?
    var terrainRaw: String?
    /// Fatigue ressentie avant 1–5.
    var fatigue: Int
    /// Durée du symptôme en minutes.
    var durationMinutes: Int?
    var note: String

    var zone: BodyZone { BodyZone(rawValue: zoneRaw) ?? .other }
    var side: BodySide { BodySide(rawValue: sideRaw) ?? .center }
    var type: SymptomType { SymptomType(rawValue: typeRaw) ?? .other }
    var terrain: Terrain? { terrainRaw.flatMap(Terrain.init(rawValue:)) }
    var sport: Sport? { sportRaw.flatMap(Sport.init(rawValue:)) }
    /// « Engourdissement · pied gauche »
    var key: String { "\(type.label) · \(zone.label.lowercased()) \(side == .center ? "" : side.label.lowercased())".trimmingCharacters(in: .whitespaces) }

    init(date: Date, zone: BodyZone, side: BodySide, type: SymptomType, intensity: Int, fatigue: Int) {
        self.date = date
        self.zoneRaw = zone.rawValue
        self.sideRaw = side.rawValue
        self.typeRaw = type.rawValue
        self.intensity = intensity
        self.fatigue = fatigue
        self.note = ""
    }
}

/// Paire de chaussures (kilométrage).
@Model
final class Shoe {
    @Attribute(.unique) var shoeID: String
    var name: String
    var initialKm: Double
    var retired: Bool
    var isDefault: Bool
    var addedAt: Date

    init(name: String, initialKm: Double = 0, isDefault: Bool = false) {
        self.shoeID = UUID().uuidString
        self.name = name
        self.initialKm = initialKm
        self.retired = false
        self.isDefault = isDefault
        self.addedAt = .now
    }
}

/// Échéance du calendrier (course, sortie objectif…).
@Model
final class Goal {
    var name: String
    var date: Date
    var sportRaw: String
    var distanceKm: Double
    var priorityRaw: String
    var note: String

    var sport: Sport { Sport(rawValue: sportRaw) ?? .cycling }
    var priority: GoalPriority { GoalPriority(rawValue: priorityRaw) ?? .b }

    init(name: String, date: Date, sport: Sport, distanceKm: Double, priority: GoalPriority, note: String = "") {
        self.name = name
        self.date = date
        self.sportRaw = sport.rawValue
        self.distanceKm = distanceKm
        self.priorityRaw = priority.rawValue
        self.note = note
    }
}

/// Condition prévue par le plan, mémorisée la première fois qu'une semaine apparaît (prévu vs réel).
@Model
final class PlanBaseline {
    @Attribute(.unique) var weekStart: Date
    var projectedCTL: Double
    var targetHours: Double

    init(weekStart: Date, projectedCTL: Double, targetHours: Double) {
        self.weekStart = weekStart
        self.projectedCTL = projectedCTL
        self.targetHours = targetHours
    }
}

/// Jour choisi à la main pour une séance de la semaine, ou séance retirée de la semaine (`day == nil`).
@Model
final class SessionPlacement {
    /// « début de semaine | séance » : une seule décision par séance et par semaine.
    @Attribute(.unique) var key: String
    var weekStart: Date
    /// Identifiant de la séance dans la semaine (« intense-0 », « strength-1 »…).
    var slot: String
    var day: Date?

    init(weekStart: Date, slot: String, day: Date?) {
        self.key = Self.key(weekStart: weekStart, slot: slot)
        self.weekStart = weekStart
        self.slot = slot
        self.day = day
    }

    /// Clé par date de calendrier (« 2026-10-12|threshold-0 ») : stable même après un changement de fuseau.
    static func key(weekStart: Date, slot: String, calendar: Calendar = .current) -> String {
        "\(FrozenWeek.dayKey(weekStart, calendar: calendar))|\(slot)"
    }
}

/// Composition d'une semaine figée le jour où elle devient la semaine en cours :
/// les séances ne changent plus en cours de semaine (le coach du jour adapte l'intensité au jour le jour).
@Model
final class FrozenWeek {
    @Attribute(.unique) var key: String
    var weekStart: Date
    var phaseRaw: String
    var kindRaw: String
    var targetTSS: Double
    var targetHours: Double
    var longRideHours: Double
    var intensitySessions: Int
    var strengthSessions: Int
    var bikeSessions: Int?

    init(week: PlannedWeek, calendar: Calendar = .current) {
        self.key = Self.dayKey(week.start, calendar: calendar)
        self.weekStart = calendar.startOfDay(for: week.start)
        self.phaseRaw = week.phase.rawValue
        self.kindRaw = week.kind.rawValue
        self.targetTSS = week.targetTSS
        self.targetHours = week.targetHours
        self.longRideHours = week.longRideHours
        self.intensitySessions = week.intensitySessions
        self.strengthSessions = week.strengthSessions
        self.bikeSessions = week.bikeSessions
    }

    /// « 2026-10-12 » (date de calendrier locale).
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    var kind: WeekKind { WeekKind(rawValue: kindRaw) ?? .load }

    /// La semaine du plan avec la composition figée (séances, volume) ; le reste vient du plan recalculé.
    func apply(to week: PlannedWeek) -> PlannedWeek {
        PlannedWeek(id: week.id, start: week.start, phase: TrainingPhase(rawValue: phaseRaw) ?? week.phase, kind: kind,
                    targetTSS: targetTSS, targetHours: targetHours, longRideHours: longRideHours,
                    intensitySessions: intensitySessions, strengthSessions: strengthSessions,
                    runningAllowed: week.runningAllowed, availableDays: week.availableDays,
                    projectedCTL: week.projectedCTL, notes: week.notes, raceDay: week.raceDay,
                    bikeSessions: bikeSessions ?? week.bikeSessions)
    }
}

/// Expérience N = 1 : tester un changement (dîner plus tôt, autre chaussure…) et comparer avant / pendant.
@Model
final class Experiment {
    var name: String
    var start: Date
    var end: Date?
    /// Métrique suivie (MetricKind.rawValue ou "readiness").
    var metricRaw: String
    var note: String

    init(name: String, start: Date, metricRaw: String, note: String = "") {
        self.name = name
        self.start = start
        self.metricRaw = metricRaw
        self.note = note
    }
}

extension DailyWellness {
    /// Durée de la nuit : Apple Santé (avec horaires et stades) si présente, sinon Garmin (Intervals.icu).
    var anySleepHours: Double? { sleepHours ?? sleepHoursGarmin }
    /// FC au repos de la journée, quelle que soit la source (affichage d'un jour isolé).
    var anyRestingHeartRate: Double? { restingHeartRate ?? restingHeartRateGarmin }
    /// Respiration nocturne, quelle que soit la source (affichage d'un jour isolé).
    var anyRespiration: Double? { respiration ?? respirationGarmin }
    /// Poids du jour : pesée Apple Santé ou saisie, sinon Garmin.
    var anyWeightKg: Double? { weightKg ?? weightKgGarmin }
    /// VO2max du jour, quelle que soit la source (affichage d'un jour isolé).
    var anyVO2Max: Double? { vo2Max ?? vo2MaxGarmin }
}
