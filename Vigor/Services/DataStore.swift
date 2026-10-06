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
    static func syncHealth(_ health: HealthKitService, into context: ModelContext, days: Int = 365,
                           thresholds: Thresholds? = nil) async throws -> SyncReport {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let nights = try await health.sleepNights(days: days)
        let hrv = try await health.daily(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), cumulative: false, days: days)
        let restingHR = try await health.daily(.restingHeartRate, unit: bpm, cumulative: false, days: days)
        let steps = try await health.daily(.stepCount, unit: .count(), cumulative: true, days: days)
        let energy = try await health.daily(.activeEnergyBurned, unit: .kilocalorie(), cumulative: true, days: days)
        let weight = try await health.daily(.bodyMass, unit: .gramUnit(with: .kilo), cumulative: false, days: days)
        let vo2 = try await health.daily(.vo2Max, unit: HKUnit(from: "ml/kg*min"), cumulative: false, days: days)
        let respiration = (try? await health.daily(.respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute()),
                                                   cumulative: false, days: days)) ?? [:]

        var report = SyncReport()
        let existingDays = try context.fetch(FetchDescriptor<DailyWellness>())
        var byDay = Dictionary(existingDays.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        let allDays = Set(nights.keys).union(hrv.keys).union(restingHR.keys).union(steps.keys)
            .union(energy.keys).union(weight.keys).union(vo2.keys).union(respiration.keys)

        for day in allDays {
            let record: DailyWellness
            if let existing = byDay[day] {
                record = existing
            } else {
                record = DailyWellness(day: day)
                context.insert(record)
                byDay[day] = record
            }
            if let night = nights[day] {
                record.sleepHours = night.hours
                record.bedtime = night.bedtime
                record.wakeTime = night.wake
            }
            if let value = hrv[day] { record.hrvMs = value }
            if let value = restingHR[day] { record.restingHeartRate = value }
            if let value = steps[day] { record.steps = value }
            if let value = energy[day] { record.activeEnergyKcal = value }
            if let value = weight[day] { record.weightKg = value }
            if let value = vo2[day] { record.vo2Max = value }
            if let value = respiration[day], record.respiration == nil { record.respiration = value }
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
            activity.elevationGain = workout.elevationGain
            activity.averageCadence = workout.averageCadence
            if workout.sport == .indoorCycling { activity.terrainRaw = Terrain.indoor.rawValue }
            context.insert(activity)
            activities.append(activity)
            report.newActivities += 1
        }

        // Zones de FC et dérive cardiaque des séances récentes (une seule fois par séance).
        if let thresholds {
            let cutoff = Calendar.current.date(byAdding: .day, value: -120, to: .now) ?? .now
            for activity in activities where !activity.zonesComputed && activity.start >= cutoff {
                guard let bounds = HeartRateZones.bounds(thresholds: thresholds, sport: activity.sport) else { break }
                let end = activity.start.addingTimeInterval(activity.durationSeconds)
                let samples = (try? await health.heartRateSamples(from: activity.start, to: end)) ?? []
                guard samples.count > 10 else { continue }
                let analysis = HeartRateZones.analyze(samples, bounds: bounds)
                activity.zoneSeconds = analysis.zones
                if activity.decouplingPercent == nil { activity.decouplingPercent = analysis.drift }
                activity.zonesComputed = true
            }
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
    /// Synchronise Intervals.icu : données Garmin complètes + séances prévues.
    static func syncIntervals(_ client: IntervalsClient, into context: ModelContext, days: Int = 365) async throws -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let oldest = calendar.date(byAdding: .day, value: -days, to: today) ?? today
        let horizon = calendar.date(byAdding: .day, value: 14, to: today) ?? today

        let wellness = try await client.wellness(oldest: oldest, newest: today)
        let activities = try await client.activities(oldest: oldest, newest: today)
        let planned = try await client.plannedWorkouts(oldest: today, newest: horizon)

        // Bien-être Garmin.
        let existingDays = try context.fetch(FetchDescriptor<DailyWellness>())
        var byDay = Dictionary(existingDays.map { ($0.day, $0) }, uniquingKeysWith: { first, _ in first })
        for item in wellness {
            guard let date = IntervalsClient.dayFormatter.date(from: item.id) else { continue }
            let day = calendar.startOfDay(for: date)
            let record: DailyWellness
            if let existing = byDay[day] {
                record = existing
            } else {
                record = DailyWellness(day: day)
                context.insert(record)
                byDay[day] = record
            }
            if let value = item.hrv { record.hrvRMSSD = value }
            if let value = item.restingHR { record.restingHeartRate = value }
            if let value = item.sleepSecs, value > 0 { record.sleepHours = value / 3600 }
            if let value = item.sleepScore { record.sleepScore = value }
            if let value = item.readiness { record.garminReadiness = value }
            if let value = item.avgSleepingHR { record.sleepingHeartRate = value }
            if let value = item.spO2 { record.spO2 = value }
            if let value = item.respiration { record.respiration = value }
            if let value = item.vo2max { record.vo2Max = value }
            if let value = item.weight { record.weightKg = value }
            if let value = item.bodyFat { record.bodyFatPercent = value }
            if let value = item.steps, record.steps == nil { record.steps = value }
        }

        // Séances : Intervals est la source la plus riche, elle enrichit les doublons Apple Santé.
        var stored = try context.fetch(FetchDescriptor<CardioActivity>())
        let knownIDs = Set(stored.map(\.externalID))
        var added = 0
        for item in activities {
            guard let sport = item.sport, let start = IntervalsClient.parseLocal(item.startDateLocal),
                  let duration = item.movingTime, duration > 0 else { continue }
            let id = "intervals|\(item.id.value)"
            let target: CardioActivity
            if knownIDs.contains(id), let existing = stored.first(where: { $0.externalID == id }) {
                target = existing
            } else if let duplicate = stored.first(where: {
                ActivityDeduplicator.isSameSession(sportA: $0.sport, startA: $0.start, durationA: $0.durationSeconds,
                                                   sportB: sport, startB: start, durationB: duration)
            }) {
                target = duplicate
            } else {
                target = CardioActivity(externalID: id, source: "Garmin via Intervals.icu", sport: sport,
                                        title: item.name ?? sport.label, start: start, durationSeconds: duration)
                context.insert(target)
                stored.append(target)
                added += 1
            }
            target.source = "Garmin via Intervals.icu"
            if let name = item.name, !name.isEmpty { target.title = name }
            target.providedTSS = item.trainingLoad ?? target.providedTSS
            target.providedIntensity = item.intensityFactor ?? target.providedIntensity
            target.averagePower = item.averageWatts ?? target.averagePower
            target.normalizedPower = item.weightedAverageWatts ?? target.normalizedPower
            target.averageHeartRate = item.averageHeartRate ?? target.averageHeartRate
            target.distanceMeters = item.distance ?? target.distanceMeters
            target.energyKcal = item.calories ?? target.energyKcal
            target.decouplingPercent = item.decoupling ?? target.decouplingPercent
            target.averageCadence = item.averageCadence ?? target.averageCadence
            target.elevationGain = item.elevationGain ?? target.elevationGain
            if let zones = item.hrZoneTimes, !zones.isEmpty {
                // Intervals peut avoir 5 à 7 zones : on regroupe au-delà de la 5e.
                var five = Array(zones.prefix(5))
                while five.count < 5 { five.append(0) }
                if zones.count > 5 { five[4] += zones.dropFirst(5).reduce(0, +) }
                target.zoneSeconds = five
                target.zonesComputed = true
            }
            if sport == .indoorCycling, target.terrainRaw == nil { target.terrainRaw = Terrain.indoor.rawValue }
        }

        // Séances prévues : mise à jour du calendrier à venir.
        let existingPlanned = try context.fetch(FetchDescriptor<PlannedWorkout>())
        let plannedByID = Dictionary(existingPlanned.map { ($0.externalID, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        for event in planned {
            guard let date = IntervalsClient.parseLocal(event.startDateLocal) else { continue }
            let sport: Sport
            switch event.type ?? "" {
            case "VirtualRide": sport = .indoorCycling
            case "Ride", "GravelRide": sport = .cycling
            case "Run": sport = .running
            case "WeightTraining": sport = .strength
            default: sport = .other
            }
            let id = "intervals|event|\(event.id.value)"
            seen.insert(id)
            let workout: PlannedWorkout
            if let existing = plannedByID[id] {
                workout = existing
                workout.date = date
                workout.name = event.name ?? "Séance prévue"
                workout.details = event.description ?? ""
                workout.sportRaw = sport.rawValue
            } else {
                workout = PlannedWorkout(externalID: id, date: date, name: event.name ?? "Séance prévue",
                                         details: event.description ?? "", sport: sport)
                context.insert(workout)
            }
            workout.plannedSeconds = event.movingTime
            workout.plannedTSS = event.trainingLoad
        }
        for workout in existingPlanned where workout.date >= today && !seen.contains(workout.externalID) {
            context.delete(workout)
        }

        try context.save()
        return "Intervals.icu : \(wellness.count) jours Garmin, \(added) nouvelle(s) séance(s), \(planned.count) séance(s) prévue(s)."
    }
}
