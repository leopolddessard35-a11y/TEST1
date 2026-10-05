import Foundation
import SwiftData
import HealthKit

struct SyncReport {
    var days = 0
    var newActivities = 0

    var summary: String {
        "Apple Santé synchronisé : \(days) jours, \(newActivities) nouvelle\(newActivities > 1 ? "s" : "") séance\(newActivities > 1 ? "s" : "")."
    }
}

/// Écrit les données importées dans la base locale de l'app (SwiftData).
@MainActor
enum DataStore {
    static func syncHealth(_ health: HealthKitService, into context: ModelContext, days: Int = 365) async throws -> SyncReport {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let sleep = try await health.sleepHours(days: days)
        let hrv = try await health.daily(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), cumulative: false, days: days)
        let restingHR = try await health.daily(.restingHeartRate, unit: bpm, cumulative: false, days: days)
        let steps = try await health.daily(.stepCount, unit: .count(), cumulative: true, days: days)
        let energy = try await health.daily(.activeEnergyBurned, unit: .kilocalorie(), cumulative: true, days: days)
        let weight = try await health.daily(.bodyMass, unit: .gramUnit(with: .kilo), cumulative: false, days: days)
        let vo2 = try await health.daily(.vo2Max, unit: HKUnit(from: "ml/kg*min"), cumulative: false, days: days)

        var report = SyncReport()
        let existingDays = try context.fetch(FetchDescriptor<DailyWellness>())
        var byDay = Dictionary(existingDays.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let allDays = Set(sleep.keys).union(hrv.keys).union(restingHR.keys).union(steps.keys)
            .union(energy.keys).union(weight.keys).union(vo2.keys)

        for day in allDays {
            let record: DailyWellness
            if let existing = byDay[day] {
                record = existing
            } else {
                record = DailyWellness(day: day)
                context.insert(record)
                byDay[day] = record
            }
            if let value = sleep[day] { record.sleepHours = value }
            if let value = hrv[day] { record.hrvMs = value }
            if let value = restingHR[day] { record.restingHeartRate = value }
            if let value = steps[day] { record.steps = value }
            if let value = energy[day] { record.activeEnergyKcal = value }
            if let value = weight[day] { record.weightKg = value }
            if let value = vo2[day] { record.vo2Max = value }
        }
        report.days = allDays.count

        var activities = try context.fetch(FetchDescriptor<CardioActivity>())
        let knownIDs = Set(activities.map(\.externalID))
        for workout in try await health.workouts(days: days) {
            let id = "healthkit|\(workout.id.uuidString)"
            guard !knownIDs.contains(id) else { continue }

            if let duplicate = activities.first(where: {
                ActivityDeduplicator.isSameSession(sportA: $0.sport, startA: $0.start, durationA: $0.durationSeconds,
                                                   sportB: workout.sport, startB: workout.start, durationB: workout.duration)
            }) {
                // On garde la version la plus riche (avec puissance).
                if duplicate.averagePower == nil, let power = workout.averagePower {
                    duplicate.averagePower = power
                }
                if duplicate.averageHeartRate == nil { duplicate.averageHeartRate = workout.averageHeartRate }
                continue
            }

            let activity = CardioActivity(externalID: id, source: workout.sourceName, sport: workout.sport,
                                          title: workout.title, start: workout.start, durationSeconds: workout.duration)
            activity.distanceMeters = workout.distanceMeters
            activity.averageHeartRate = workout.averageHeartRate
            activity.averagePower = workout.averagePower
            activity.energyKcal = workout.energyKcal
            context.insert(activity)
            activities.append(activity)
            report.newActivities += 1
        }

        try context.save()
        return report
    }

    /// Importe l'export Hevy. Tu peux réimporter l'export complet à chaque fois :
    /// les séances déjà connues sont mises à jour avec leur dernière version, rien n'est dupliqué.
    static func importHevy(_ workouts: [HevyWorkout], into context: ModelContext) throws -> (added: Int, updated: Int) {
        let existing = try context.fetch(FetchDescriptor<StrengthWorkout>())
        let byID = Dictionary(existing.map { ($0.externalID, $0) }, uniquingKeysWith: { first, _ in first })
        var added = 0, updated = 0

        for workout in workouts {
            let model: StrengthWorkout
            if let old = byID[workout.externalID] {
                model = old
                model.title = workout.title
                model.start = workout.start
                model.end = workout.end
                model.notes = workout.description
                for set in old.sets { context.delete(set) }
                updated += 1
            } else {
                model = StrengthWorkout(externalID: workout.externalID, title: workout.title,
                                        start: workout.start, end: workout.end, notes: workout.description)
                context.insert(model)
                added += 1
            }
            model.sets = workout.sets.map { set in
                StrengthSet(exercise: set.exercise, exerciseNotes: set.exerciseNotes, setIndex: set.setIndex,
                            setType: set.setType, weightKg: set.weightKg, reps: set.reps, distanceKm: set.distanceKm,
                            durationSeconds: set.durationSeconds, rpe: set.rpe, supersetID: set.supersetID)
            }
        }
        try context.save()
        return (added, updated)
    }
}
