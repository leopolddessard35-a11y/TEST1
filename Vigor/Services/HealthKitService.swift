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
    let end: Date
    let elevationGain: Double?
    let averageCadence: Double?
}

struct SleepNight {
    let hours: Double
    let bedtime: Date
    let wake: Date
    /// Stades (heures) ; nil si la source ne les détaille pas.
    var deep: Double? = nil
    var rem: Double? = nil
    var core: Double? = nil
    var awake: Double? = nil
}

/// Un segment de la nuit, pour l'hypnogramme.
struct SleepSegment: Identifiable, Equatable {
    enum Stage: Int, CaseIterable, Comparable {
        case deep = 0, core, rem, awake

        var label: String {
            switch self {
            case .deep: "Profond"
            case .core: "Léger"
            case .rem: "Paradoxal"
            case .awake: "Éveil"
            }
        }

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    var id: Date { start }
    let start: Date
    let end: Date
    let stage: Stage
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
            .heartRateVariabilitySDNN, .restingHeartRate, .heartRate, .respiratoryRate, .stepCount, .activeEnergyBurned,
            .bodyMass, .vo2Max, .cyclingPower, .cyclingCadence, .distanceCycling, .distanceWalkingRunning,
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

    /// Jour de la nuit = jour du réveil. Une nuit commence la veille au soir : tout segment qui se termine
    /// après 18 h appartient à la nuit suivante (sinon une nuit à cheval sur minuit était coupée en deux,
    /// avec des heures de coucher et de lever absurdes).
    nonisolated static func nightDay(forSegmentEnding end: Date, calendar: Calendar = .current) -> Date {
        let hour = calendar.component(.hour, from: end)
        let day = calendar.startOfDay(for: end)
        return hour >= 18 ? (calendar.date(byAdding: .day, value: 1, to: day) ?? day) : day
    }

    /// Nuits de sommeil (rattachées au jour du réveil) : durée, coucher, réveil.
    /// Si plusieurs sources (Garmin + iPhone), on garde la plus complète pour ne pas compter deux fois.
    func sleepNights(days: Int) async throws -> [Date: SleepNight] {
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
        struct Accumulator {
            var seconds: Double = 0
            var deep: Double = 0
            var rem: Double = 0
            var core: Double = 0
            var awake: Double = 0
            var first: Date = .distantFuture
            var last: Date = .distantPast
        }
        let awakeValue = HKCategoryValueSleepAnalysis.awake.rawValue
        var perSource: [Date: [String: Accumulator]] = [:]
        for sample in samples where asleep.contains(sample.value) || sample.value == awakeValue {
            let day = Self.nightDay(forSegmentEnding: sample.endDate, calendar: calendar)
            let source = sample.sourceRevision.source.bundleIdentifier
            var accumulator = perSource[day]?[source] ?? Accumulator()
            let duration = sample.endDate.timeIntervalSince(sample.startDate)
            if sample.value == awakeValue {
                accumulator.awake += duration
            } else {
                accumulator.seconds += duration
                accumulator.first = min(accumulator.first, sample.startDate)
                accumulator.last = max(accumulator.last, sample.endDate)
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: accumulator.deep += duration
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue: accumulator.rem += duration
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue: accumulator.core += duration
                default: break
                }
            }
            perSource[day, default: [:]][source] = accumulator
        }
        var nights: [Date: SleepNight] = [:]
        for (day, sources) in perSource {
            guard let best = sources.values.max(by: { $0.seconds < $1.seconds }), best.seconds > 0 else { continue }
            let staged = best.deep + best.rem + best.core > 0
            nights[day] = SleepNight(hours: best.seconds / 3600, bedtime: best.first, wake: best.last,
                                     deep: staged ? best.deep / 3600 : nil,
                                     rem: staged ? best.rem / 3600 : nil,
                                     core: staged ? best.core / 3600 : nil,
                                     awake: staged || best.awake > 0 ? best.awake / 3600 : nil)
        }
        return nights
    }

    /// Segments de la nuit (source la plus complète) pour l'hypnogramme.
    func sleepSegments(from start: Date, to end: Date) async throws -> [SleepSegment] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)
        func mapStage(_ value: Int) -> SleepSegment.Stage? {
            switch value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: return .deep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: return .rem
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                 HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: return .core
            case HKCategoryValueSleepAnalysis.awake.rawValue: return .awake
            default: return nil
            }
        }
        var bySource: [String: [SleepSegment]] = [:]
        for sample in samples {
            guard let stage = mapStage(sample.value) else { continue }
            bySource[sample.sourceRevision.source.bundleIdentifier, default: []]
                .append(SleepSegment(start: sample.startDate, end: sample.endDate, stage: stage))
        }
        let best = bySource.values.max { a, b in
            a.filter { $0.stage != .awake }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
                < b.filter { $0.stage != .awake }.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        }
        return best ?? []
    }

    /// Fréquence cardiaque seconde par seconde (ou presque) pendant une séance.
    func heartRateSamples(from start: Date, to end: Date) async throws -> [HeartRateZones.Sample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HKQuantityType(.heartRate), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return samples.map { HeartRateZones.Sample(time: $0.startDate, bpm: $0.quantity.doubleValue(for: bpm)) }
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
                sourceName: source,
                end: workout.endDate,
                elevationGain: (workout.metadata?[HKMetadataKeyElevationAscended] as? HKQuantity)?.doubleValue(for: .meter()),
                averageCadence: workout.statistics(for: HKQuantityType(.cyclingCadence))?.averageQuantity()?.doubleValue(for: bpm))
        }
    }
}
