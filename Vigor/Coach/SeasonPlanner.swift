import Foundation

enum TrainingPhase: String, CaseIterable {
    case reprise, base, build, specific, taper, race

    var label: String {
        switch self {
        case .reprise: "Reprise"
        case .base: "Foncier"
        case .build: "Développement"
        case .specific: "Spécifique Traka"
        case .taper: "Affûtage"
        case .race: "Course"
        }
    }

    var summary: String {
        switch self {
        case .reprise: "Retour progressif après blessure : endurance facile, aucune intensité, renfo adapté."
        case .base: "Construire le moteur : beaucoup d'endurance (zone 2), sortie longue qui s'allonge, muscu prioritaire pour la masse."
        case .build: "Ajouter de l'intensité (seuil, sweet spot, VO2max) tout en gardant la sortie longue."
        case .specific: "Simuler la Traka : longues sorties gravel, efforts au seuil sur terrain varié, nutrition d'effort testée."
        case .taper: "Réduire le volume pour arriver frais, garder un peu d'intensité pour rester vif."
        case .race: "Semaine de course : repos, déblocage et c'est parti."
        }
    }

    var nutritionFocus: String {
        switch self {
        case .reprise, .base: "Prise de masse : léger surplus (+250 à +300 kcal/j), protéines 1,8–2,2 g/kg."
        case .build: "Surplus léger puis maintien, glucides augmentés les jours d'intensité."
        case .specific, .taper: "Maintien du poids, glucides adaptés aux sorties longues (60–90 g/h pendant l'effort)."
        case .race: "Charge glucidique les 2 jours avant la course."
        }
    }

    /// TSS moyen par heure attendu (plus d'intensité = plus de TSS par heure).
    var tssPerHour: Double {
        switch self {
        case .reprise: 40
        case .base: 45
        case .build: 55
        case .specific: 58
        case .taper, .race: 50
        }
    }

    var longRideCapHours: Double {
        switch self {
        case .reprise: 1.5
        case .base: 3.0
        case .build: 3.75
        case .specific: 4.5
        case .taper: 2.0
        case .race: 0
        }
    }

    var strengthSessions: Int {
        switch self {
        case .reprise, .base: 3
        case .build, .specific: 2
        case .taper: 1
        case .race: 0
        }
    }

    /// Progression maximale de la condition (points de CTL par semaine).
    var maxRamp: Double {
        switch self {
        case .reprise: 3
        case .base, .build: 5
        case .specific: 4
        case .taper, .race: 0
        }
    }
}

enum WeekKind: String {
    case load, recovery, taper, race

    var label: String {
        switch self {
        case .load: "Charge"
        case .recovery: "Récupération"
        case .taper: "Affûtage"
        case .race: "Course"
        }
    }
}

struct UnavailabilityPeriod: Equatable {
    let start: Date
    let end: Date
    let reason: UnavailabilityReason
}

struct InjuryStatus: Equatable {
    let name: String
    let muscles: Set<Muscle>
    let affectsRunning: Bool
    let affectsCycling: Bool
    let severity: Int
}

struct PlannerInput {
    var today: Date
    var raceDate: Date
    var raceName: String = "The Traka 100"
    var currentCTL: Double
    var targetRaceCTL: Double
    var weeklyHoursAvailable: Double
    var strengthSessionsPerWeek: Int
    var unavailabilities: [UnavailabilityPeriod] = []
    var injuries: [InjuryStatus] = []
}

struct PlannedWeek: Identifiable, Equatable {
    let id: Int
    let start: Date
    let phase: TrainingPhase
    var kind: WeekKind
    var targetTSS: Double
    var targetHours: Double
    var longRideHours: Double
    var intensitySessions: Int
    var strengthSessions: Int
    var runningAllowed: Bool
    var availableDays: Int
    var projectedCTL: Double
    var notes: [String]

    var isReduced: Bool { availableDays < 6 }
}

struct SeasonPlan {
    let weeks: [PlannedWeek]
    let startCTL: Double
    let targetCTL: Double
    let projectedPeakCTL: Double
    let warnings: [String]

    var currentWeek: PlannedWeek? { weeks.first }
}

/// Construit le plan vélo semaine par semaine jusqu'à la course.
/// Le plan est recalculé à chaque ouverture depuis ta condition RÉELLE :
/// une semaine ratée (maladie, blessure, vacances) est absorbée automatiquement.
enum SeasonPlanner {
    static var isoCalendar: Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        return calendar
    }

    static func makePlan(_ input: PlannerInput, calendar: Calendar = SeasonPlanner.isoCalendar) -> SeasonPlan {
        guard let firstStart = calendar.dateInterval(of: .weekOfYear, for: input.today)?.start,
              let raceStart = calendar.dateInterval(of: .weekOfYear, for: input.raceDate)?.start,
              raceStart >= firstStart else {
            return SeasonPlan(weeks: [], startCTL: input.currentCTL, targetCTL: input.targetRaceCTL,
                              projectedPeakCTL: input.currentCTL,
                              warnings: ["La date de course est passée : mets à jour ton objectif dans Réglages."])
        }

        let days = calendar.dateComponents([.day], from: firstStart, to: raceStart).day ?? 0
        let count = Int((Double(days) / 7).rounded()) + 1
        let repriseWeeks = !input.injuries.isEmpty ? 3 : (input.currentCTL < 20 ? 2 : 0)
        let phases = assignPhases(count: count, repriseWeeks: repriseWeeks)
        let starts = (0..<count).map { calendar.date(byAdding: .day, value: $0 * 7, to: firstStart) ?? firstStart }
        let availability = starts.map { unavailableDays(weekStart: $0, periods: input.unavailabilities, calendar: calendar) }

        // On cherche la progression hebdomadaire la plus douce qui atteint la condition visée.
        let maxRamp = 6.0
        var warnings: [String] = []
        let ramp: Double
        if simulate(input, phases: phases, starts: starts, availability: availability, ramp: maxRamp).peakCTL < input.targetRaceCTL {
            ramp = maxRamp
            warnings.append("Avec tes disponibilités, la condition visée (\(Int(input.targetRaceCTL))) ne sera pas atteinte. On fait au mieux, sans risque de surcharge.")
        } else {
            var low = 0.0, high = maxRamp
            for _ in 0..<30 {
                let mid = (low + high) / 2
                if simulate(input, phases: phases, starts: starts, availability: availability, ramp: mid).peakCTL >= input.targetRaceCTL {
                    high = mid
                } else {
                    low = mid
                }
            }
            ramp = high
        }

        let result = simulate(input, phases: phases, starts: starts, availability: availability, ramp: ramp)
        if result.capped {
            warnings.append("Certaines semaines sont limitées par tes heures disponibles (\(String(format: "%.0f", input.weeklyHoursAvailable)) h/sem).")
        }
        if input.injuries.contains(where: { $0.severity >= 3 }) {
            warnings.append("Blessure sévère déclarée : fais valider la reprise par un médecin ou un kiné.")
        }
        return SeasonPlan(weeks: result.weeks, startCTL: input.currentCTL, targetCTL: input.targetRaceCTL,
                          projectedPeakCTL: result.peakCTL, warnings: warnings)
    }

    static func assignPhases(count: Int, repriseWeeks: Int) -> [TrainingPhase] {
        guard count > 0 else { return [] }
        var phases = Array(repeating: TrainingPhase.base, count: count)
        var index = count - 1
        func fill(_ phase: TrainingPhase, _ weeks: Int) {
            var filled = 0
            while filled < weeks, index >= 0 {
                phases[index] = phase
                index -= 1
                filled += 1
            }
        }
        fill(.race, 1)
        fill(.taper, 1)
        fill(.specific, 6)
        fill(.build, 8)
        let reprise = min(repriseWeeks, index + 1)
        for week in 0..<reprise {
            phases[week] = .reprise
        }
        return phases
    }

    struct WeekAvailability: Equatable {
        var unavailable = 0
        var byReason: [UnavailabilityReason: Int] = [:]

        var illnessDays: Int { (byReason[.illness] ?? 0) + (byReason[.injury] ?? 0) }
    }

    static func unavailableDays(weekStart: Date, periods: [UnavailabilityPeriod], calendar: Calendar) -> WeekAvailability {
        var result = WeekAvailability()
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let match = periods.first { period in
                day >= calendar.startOfDay(for: period.start) && day <= calendar.startOfDay(for: period.end)
            }
            if let match {
                result.unavailable += 1
                result.byReason[match.reason, default: 0] += 1
            }
        }
        return result
    }

    private struct Simulation {
        var weeks: [PlannedWeek]
        var peakCTL: Double
        var capped: Bool
    }

    private static func simulate(_ input: PlannerInput,
                                 phases: [TrainingPhase],
                                 starts: [Date],
                                 availability: [WeekAvailability],
                                 ramp: Double) -> Simulation {
        let decay = pow(1 - 1 / TrainingLoad.ctlDays, 7)
        let response = TrainingLoad.weeklyCTLResponse
        let baseIndices = phases.indices.filter { phases[$0] == .base }
        let legInjury = input.injuries.filter { !$0.muscles.isDisjoint(with: Set(Muscle.allCases.filter(\.isLegDriver))) }
        let cyclingInjury = input.injuries.filter(\.affectsCycling)
        let runningAllowed = !input.injuries.contains(where: \.affectsRunning)

        var ctl = input.currentCTL
        var longRide = min(2.0, max(1.0, ctl / 20))
        var loadStreak = 0
        var peakCTL = ctl
        var capped = false
        var weeks: [PlannedWeek] = []

        for index in phases.indices {
            let phase = phases[index]
            let week = availability[index]
            var notes: [String] = []

            var kind: WeekKind
            switch phase {
            case .taper: kind = .taper
            case .race: kind = .race
            case .reprise: kind = .load
            case .base, .build, .specific: kind = loadStreak >= 3 ? .recovery : .load
            }
            if week.byReason[.fatigue] != nil, kind == .load {
                kind = .recovery
                notes.append("Grosse fatigue déclarée : semaine transformée en récupération.")
            }
            if kind == .recovery { loadStreak = 0 } else if kind == .load, phase != .reprise { loadStreak += 1 }

            // Charge cible de la semaine.
            let weekRamp = min(ramp, phase.maxRamp)
            var tss: Double
            switch kind {
            case .load: tss = max(7 * (ctl + weekRamp / response), phase == .reprise ? 90 : 120)
            case .recovery, .taper: tss = 7 * ctl * 0.6
            case .race: tss = 7 * ctl * 0.45
            }

            // Disponibilités, retour de maladie, blessures.
            let availableDays = 7 - week.unavailable
            let availabilityFactor = Double(availableDays) / 7
            tss *= availabilityFactor

            if index > 0 {
                let previousIllness = availability[index - 1].illnessDays
                if previousIllness >= 7 {
                    tss *= 0.6
                    notes.append("Retour après maladie/blessure longue : charge −40 %, endurance facile uniquement les premiers jours.")
                } else if previousIllness >= 3 {
                    tss *= 0.75
                    notes.append("Retour après maladie : charge −25 %, pas d'intensité les 3 premiers jours.")
                }
            }
            if let worst = cyclingInjury.map(\.severity).max() {
                tss *= worst >= 3 ? 0.5 : (worst == 2 ? 0.7 : 0.85)
            }

            var hours = tss / phase.tssPerHour
            let maxHours = input.weeklyHoursAvailable * availabilityFactor
            if hours > maxHours {
                hours = maxHours
                tss = hours * phase.tssPerHour
                if kind == .load { capped = true }
            }

            // Sortie longue.
            var weekLong: Double
            switch kind {
            case .load:
                longRide = min(phase.longRideCapHours, longRide + 0.25)
                weekLong = longRide
            case .recovery: weekLong = longRide * 0.6
            case .taper: weekLong = min(2, longRide * 0.5)
            case .race: weekLong = 0
            }
            weekLong = availableDays == 0 ? 0 : min(weekLong, max(1, hours * 0.45))
            weekLong = (weekLong * 4).rounded() / 4

            // Séances d'intensité.
            var intensity: Int
            switch phase {
            case .reprise, .race: intensity = 0
            case .base:
                let position = baseIndices.firstIndex(of: index) ?? 0
                intensity = position >= baseIndices.count / 2 ? 1 : 0
            case .build, .specific: intensity = 2
            case .taper: intensity = 1
            }
            if kind == .recovery { intensity = 0 }
            if let worst = legInjury.map(\.severity).max() {
                intensity = min(intensity, worst >= 2 ? 0 : 1)
            }
            if availabilityFactor < 0.5 { intensity = min(intensity, 1) }

            // Musculation (Push / Pull / Legs).
            var strength = min(phase.strengthSessions, input.strengthSessionsPerWeek)
            if kind == .recovery { strength = max(strength - 1, min(strength, 1)) }
            strength = min(strength, Int((Double(strength) * availabilityFactor).rounded(.up)))

            ctl = ctl * decay + (tss / 7) * response
            if phase != .taper, phase != .race { peakCTL = ctl }

            notes += weekNotes(kind: kind, week: week, input: input, legInjury: legInjury, runningAllowed: runningAllowed)

            weeks.append(PlannedWeek(
                id: index,
                start: starts[index],
                phase: phase,
                kind: kind,
                targetTSS: tss.rounded(),
                targetHours: (hours * 4).rounded() / 4,
                longRideHours: weekLong,
                intensitySessions: intensity,
                strengthSessions: strength,
                runningAllowed: runningAllowed,
                availableDays: availableDays,
                projectedCTL: ctl,
                notes: notes))
        }
        return Simulation(weeks: weeks, peakCTL: peakCTL, capped: capped)
    }

    private static func weekNotes(kind: WeekKind,
                                  week: WeekAvailability,
                                  input: PlannerInput,
                                  legInjury: [InjuryStatus],
                                  runningAllowed: Bool) -> [String] {
        var notes: [String] = []
        switch kind {
        case .recovery: notes.append("Semaine de récupération : volume −40 %, aucune intensité.")
        case .taper: notes.append("Affûtage : volume réduit, 1 séance courte d'intensité pour rester vif.")
        case .race: notes.append("🏁 \(input.raceName) : c'est la semaine de course !")
        case .load: break
        }

        for reason in UnavailabilityReason.allCases {
            guard let days = week.byReason[reason] else { continue }
            let prefix = "\(days) j indisponible\(days > 1 ? "s" : "") (\(reason.label.lowercased()))"
            switch reason {
            case .illness: notes.append("\(prefix) : repos complet tant qu'il y a fièvre ou symptômes sous le cou.")
            case .travel: notes.append("\(prefix) : séances courtes possibles (gainage, mobilité, renfo au poids du corps).")
            case .vacation: notes.append("\(prefix) : profite ! Une sortie plaisir si l'envie est là.")
            case .motivation: notes.append("\(prefix) : on ne rattrape pas les séances manquées, on reprend le plan normalement.")
            case .injury, .fatigue, .other: notes.append("\(prefix).")
            }
        }

        for injury in legInjury {
            if injury.muscles.contains(.hamstrings) {
                notes.append("Ischios (\(injury.name)) : pas de sprints ni de soulevé de terre lourd. Vélo en endurance OK si indolore.")
            } else {
                notes.append("Blessure (\(injury.name)) : intensité limitée, avis kiné recommandé.")
            }
        }
        if !runningAllowed { notes.append("Course à pied en pause (blessure).") }
        return notes
    }
}
