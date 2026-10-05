import Foundation
import HealthKit

struct WorkoutSummary {
    let id: UUID
    let sport: Sport
    let title: String
    let start: Date
    let duration: TimeInterval
    let distanceMeters: Double?
    let averageHeartRate: Double?
    let averagePower: Double?
    let energyKcal: Double?
    let sourceName: String
}

extension Sport {
    /// La muscu vient de Hevy (plus détaillé) : on l'ignore côté Apple Santé pour éviter les doublons.
    init?(healthKit type: HKWorkoutActivityType, indoor: Bool) {
        switch type {
        case .cycling: self = indoor ? .indoorCycling : .cycling
        case .running: self = .running
        case .traditionalStrengthTraining, .functionalStrengthTraining: return nil
        default: self = .other
        }
    }
}

/// Lecture des données Apple Santé (Garmin, Zwift, Hevy, iPhone… y écrivent tous).
@MainActor
final class HealthKitService {
    enum HealthError: LocalizedError {
        case unavailable

        var errorDescription: String? { "Apple Santé n'est pas disponible sur cet appareil." }
    }

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKCategoryType(.sleepAnalysis)]
        let quantities: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN, .restingHeartRate, .heartRate, .stepCount, .activeEnergyBurned,
            .bodyMass, .vo2Max, .cyclingPower, .distanceCycling, .distanceWalkingRunning,
            .dietaryEnergyConsumed, .dietaryProtein, .dietaryCarbohydrates, .dietaryFatTotal,
        ]
        for identifier in quantities {
            types.insert(HKQuantityType(identifier))
        }
        return types
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    private func range(days: Int) -> (start: Date, end: Date) {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: end)) ?? end
        return (start, end)
    }

    /// Une valeur par jour (somme ou moyenne selon la mesure).
    func daily(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, cumulative: Bool, days: Int) async throws -> [Date: Double] {
        let calendar = Calendar.current
        let (start, end) = range(days: days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(identifier), predicate: predicate),
            options: cumulative ? .cumulativeSum : .discreteAverage,
            anchorDate: calendar.startOfDay(for: end),
            intervalComponents: DateComponents(day: 1))
        let collection = try await descriptor.result(for: store)

        var values: [Date: Double] = [:]
        for statistics in collection.statistics() {
            let quantity = cumulative ? statistics.sumQuantity() : statistics.averageQuantity()
            if let quantity {
                values[calendar.startOfDay(for: statistics.startDate)] = quantity.doubleValue(for: unit)
            }
        }
        return values
    }

    /// Heures de sommeil par nuit (rattachées au jour du réveil).
    /// Si plusieurs sources (Garmin + iPhone), on garde la plus complète pour ne pas compter deux fois.
    func sleepHours(days: Int) async throws -> [Date: Double] {
        let calendar = Calendar.current
        let (start, end) = range(days: days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)

        let asleep: Set<Int> = [
            HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
            HKCategoryValueSleepAnalysis.asleepCore.rawValue,
            HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
            HKCategoryValueSleepAnalysis.asleepREM.rawValue,
        ]
        var perSource: [Date: [String: Double]] = [:]
        for sample in samples where asleep.contains(sample.value) {
            let day = calendar.startOfDay(for: sample.endDate)
            let source = sample.sourceRevision.source.bundleIdentifier
            perSource[day, default: [:]][source, default: 0] += sample.endDate.timeIntervalSince(sample.startDate)
        }
        return perSource.mapValues { ($0.values.max() ?? 0) / 3600 }
    }

    func workouts(days: Int) async throws -> [WorkoutSummary] {
        let (start, end) = range(days: days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)])
        let workouts = try await descriptor.result(for: store)

        let bpm = HKUnit.count().unitDivided(by: .minute())
        return workouts.compactMap { workout in
            let indoor = (workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool) ?? false
            guard let sport = Sport(healthKit: workout.workoutActivityType, indoor: indoor) else { return nil }
            let distanceStats = workout.statistics(for: HKQuantityType(.distanceCycling))
                ?? workout.statistics(for: HKQuantityType(.distanceWalkingRunning))
            let source = workout.sourceRevision.source.name
            return WorkoutSummary(
                id: workout.uuid,
                sport: sport,
                title: "\(sport.label) · \(source)",
                start: workout.startDate,
                duration: workout.duration,
                distanceMeters: distanceStats?.sumQuantity()?.doubleValue(for: .meter()),
                averageHeartRate: workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm),
                averagePower: workout.statistics(for: HKQuantityType(.cyclingPower))?.averageQuantity()?.doubleValue(for: .watt()),
                energyKcal: workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()),
                sourceName: source)
        }
    }
}
