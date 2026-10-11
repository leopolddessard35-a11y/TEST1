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

/// Échantillon de sommeil brut, indépendant de HealthKit (pour pouvoir tester le regroupement en sessions).
struct RawSleepSample {
    enum Kind { case deep, core, rem, unspecified, awake }
    let start: Date
    let end: Date
    let kind: Kind
    let source: String
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

    /// Écart maximal entre deux échantillons « endormi » d'une même session : au-delà, c'est une autre
    /// session (sieste, réveil prolongé).
    nonisolated static let sessionGap: TimeInterval = 90 * 60

    /// Nuits de sommeil (rattachées au jour du réveil) : durée, coucher, réveil.
    /// Si plusieurs sources (Garmin + iPhone), on garde la plus complète pour ne pas compter deux fois.
    func sleepNights(days: Int) async throws -> [Date: SleepNight] {
        let (start, end) = range(days: days)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)])
        let samples = try await descriptor.result(for: store)
        let raw: [RawSleepSample] = samples.compactMap { sample in
            let kind: RawSleepSample.Kind
            switch sample.value {
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: kind = .deep
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: kind = .rem
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: kind = .core
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: kind = .unspecified
            case HKCategoryValueSleepAnalysis.awake.rawValue: kind = .awake
            default: return nil   // « au lit » : ignoré
            }
            return RawSleepSample(start: sample.startDate, end: sample.endDate, kind: kind,
                                  source: sample.sourceRevision.source.bundleIdentifier)
        }
        return Self.nights(from: raw)
    }

    /// Regroupe les échantillons en sessions (écart > 90 min entre deux échantillons endormis = nouvelle
    /// session), puis garde par jour la session principale : la plus longue qui se termine entre 3 h et 14 h
    /// (à défaut la plus longue). Les siestes (autres sessions) n'entrent ni dans la durée, ni dans le coucher,
    /// le réveil ou les stades. Entre sources, on garde la session principale la plus longue.
    nonisolated static func nights(from samples: [RawSleepSample], calendar: Calendar = .current) -> [Date: SleepNight] {
        struct Session {
            var seconds: Double = 0
            var deep: Double = 0
            var rem: Double = 0
            var core: Double = 0
            var awake: Double = 0
            var first: Date
            var last: Date
        }
        var best: [Date: Session] = [:]
        let bySource = Dictionary(grouping: samples, by: \.source)
        for (_, sourceSamples) in bySource {
            let asleep = sourceSamples.filter { $0.kind != .awake }.sorted { $0.start < $1.start }
            var sessions: [Session] = []
            for sample in asleep {
                let duration = max(0, sample.end.timeIntervalSince(sample.start))
                if let last = sessions.last, sample.start.timeIntervalSince(last.last) <= sessionGap {
                    sessions[sessions.count - 1].last = max(last.last, sample.end)
                } else {
                    sessions.append(Session(first: sample.start, last: sample.end))
                }
                let index = sessions.count - 1
                sessions[index].seconds += duration
                switch sample.kind {
                case .deep: sessions[index].deep += duration
                case .rem: sessions[index].rem += duration
                case .core: sessions[index].core += duration
                case .unspecified, .awake: break
                }
            }
            // Éveils : rattachés à la session qu'ils chevauchent (éveils nocturnes).
            for sample in sourceSamples where sample.kind == .awake {
                guard let index = sessions.firstIndex(where: { sample.start < $0.last && sample.end > $0.first }) else { continue }
                let overlapStart = max(sample.start, sessions[index].first)
                let overlapEnd = min(sample.end, sessions[index].last)
                sessions[index].awake += max(0, overlapEnd.timeIntervalSince(overlapStart))
            }
            // Session principale de chaque jour pour cette source.
            let byDay = Dictionary(grouping: sessions) { nightDay(forSegmentEnding: $0.last, calendar: calendar) }
            for (day, daySessions) in byDay {
                let morning = daySessions.filter { session in
                    let hour = calendar.component(.hour, from: session.last)
                    let minute = calendar.component(.minute, from: session.last)
                    return hour >= 3 && (hour < 14 || (hour == 14 && minute == 0))
                }
                let candidates = morning.isEmpty ? daySessions : morning
                guard let main = candidates.max(by: { $0.seconds < $1.seconds }), main.seconds > 0 else { continue }
                if let current = best[day], current.seconds >= main.seconds { continue }
                best[day] = main
            }
        }
        var nights: [Date: SleepNight] = [:]
        for (day, session) in best {
            let staged = session.deep + session.rem + session.core > 0
            nights[day] = SleepNight(hours: session.seconds / 3600, bedtime: session.first, wake: session.last,
                                     deep: staged ? session.deep / 3600 : nil,
                                     rem: staged ? session.rem / 3600 : nil,
                                     core: staged ? session.core / 3600 : nil,
                                     awake: staged || session.awake > 0 ? session.awake / 3600 : nil)
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
