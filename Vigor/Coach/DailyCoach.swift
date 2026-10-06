import Foundation

// MARK: - Séances

enum SessionKind: String, Equatable {
    case rest, mobility, recovery, endurance, tempo, sweetSpot, threshold, vo2max, openers, longRide, race
    case push, pull, legs, upper, fullBody

    var isStrength: Bool { [SessionKind.push, .pull, .legs, .upper, .fullBody].contains(self) }
    var isIntense: Bool { [SessionKind.tempo, .sweetSpot, .threshold, .vo2max, .openers, .race].contains(self) }
    var isBike: Bool { !isStrength && self != .rest && self != .mobility }

    var label: String {
        switch self {
        case .rest: "Repos"
        case .mobility: "Mobilité"
        case .recovery: "Récupération active"
        case .endurance: "Endurance Z2"
        case .tempo: "Tempo"
        case .sweetSpot: "Sweet spot"
        case .threshold: "Seuil"
        case .vo2max: "VO2max"
        case .openers: "Déblocage"
        case .longRide: "Sortie longue"
        case .race: "Course"
        case .push: "Push (pecs, épaules, triceps)"
        case .pull: "Pull (dos, biceps)"
        case .legs: "Legs (jambes)"
        case .upper: "Haut du corps (Push + Pull)"
        case .fullBody: "Full body"
        }
    }

    var symbol: String {
        switch self {
        case .rest: "bed.double.fill"
        case .mobility: "figure.flexibility"
        case .recovery, .endurance: "bicycle"
        case .tempo, .sweetSpot, .threshold, .vo2max, .openers: "bolt.fill"
        case .longRide: "road.lanes"
        case .race: "flag.checkered"
        case .push, .pull, .legs, .upper, .fullBody: "dumbbell.fill"
        }
    }
}

struct SessionPrescription: Equatable, Identifiable {
    var id: String { "\(kind.rawValue)-\(minutes)-\(detail)" }
    let kind: SessionKind
    let minutes: Int
    /// Structure concrète : intervalles, watts, séries…
    let detail: String

    var title: String { minutes > 0 ? "\(kind.label) · \((Double(minutes) / 60).hoursText)" : kind.label }
}

// MARK: - Analyse du jour

enum Verdict: String {
    case push, go, adjust, easy, rest

    var label: String {
        switch self {
        case .push: "Jour pour performer"
        case .go: "Feu vert"
        case .adjust: "On ajuste"
        case .easy: "On lève le pied"
        case .rest: "Repos"
        }
    }

    var symbol: String {
        switch self {
        case .push: "flame.fill"
        case .go: "checkmark.circle.fill"
        case .adjust: "slider.horizontal.3"
        case .easy: "tortoise.fill"
        case .rest: "bed.double.fill"
        }
    }
}

enum FactorDomain: String, CaseIterable {
    case health, sport, nutrition

    var label: String {
        switch self {
        case .health: "Santé & récupération"
        case .sport: "Entraînement"
        case .nutrition: "Nutrition"
        }
    }

    var symbol: String {
        switch self {
        case .health: "heart.fill"
        case .sport: "figure.outdoor.cycle"
        case .nutrition: "fork.knife"
        }
    }
}

/// Un facteur qui pèse sur ta capacité du jour.
struct CoachFactor: Identifiable, Equatable {
    var id: String { name }
    let domain: FactorDomain
    let name: String
    /// Effet sur la capacité (−0,4 = −40 %, +0,05 = bonus).
    let impact: Double
    let detail: String
}

struct DailyBrief: Equatable {
    let verdict: Verdict
    /// Capacité estimée du jour (1 = 100 %).
    let capacity: Double
    let headline: String
    let planned: [SessionPrescription]
    let adapted: [SessionPrescription]
    /// Ce qui a été modifié et pourquoi.
    let changes: [String]
    let factors: [CoachFactor]
    let fueling: [String]
    /// Les 3 actions les plus importantes du jour.
    let priorities: [String]
    let references: [Reference]
}

struct PlannedSessionInput: Equatable {
    let name: String
    let sport: Sport
    let minutes: Int
    let tss: Double?
}

struct DailyCoachInput {
    var today: Date
    var readiness: ReadinessResult?
    var lastNightSleep: Double?
    var sleepNeed: Double
    var sleepDebt7: Double?
    var load: LoadPoint?
    var acuteChronicRatio: Double?
    var yesterdayNutrition: NutritionDay?
    var expenditure: Double?
    var weightKg: Double
    var week: PlannedWeek?
    var externalPlan: [PlannedSessionInput] = []
    var ftp: Double?
    var injuries: [InjuryStatus] = []
    var unavailableToday: UnavailabilityReason?
    var lastLegsSession: Date?
    /// Charge hors sport d'hier (équivalent TSS : travaux, journée debout…).
    var lifeLoadYesterday: Double = 0
    /// Pas d'hier.
    var stepsYesterday: Double?
    /// Symptômes récurrents (14 j) touchant les jambes / pieds.
    var recurrentLegSymptoms: [String] = []
}

/// Le coach du jour : croise santé, entraînement et nutrition pour adapter concrètement tes séances.
enum DailyCoach {
    // MARK: Programme type de la semaine

    /// Répartit le volume de la semaine planifiée en jours (calendrier : 1 = dimanche … 7 = samedi).
    static func template(for week: PlannedWeek, weekday: Int, ftp: Double?) -> [SessionPrescription] {
        var sessions: [SessionPrescription] = []
        let strength = strengthSchedule(count: week.strengthSessions)
        if let kind = strength[weekday] {
            sessions.append(strengthSession(kind))
        }

        if week.kind == .race {
            switch weekday {
            case 1: return [SessionPrescription(kind: .race, minutes: 0, detail: "Jour J : petit-déjeuner riche en glucides 3 h avant, 60–90 g de glucides par heure pendant la course.")]
            case 6: return [bike(.openers, minutes: 45, ftp: ftp, phase: week.phase)]
            case 3, 5: return [bike(.endurance, minutes: 45, ftp: ftp, phase: week.phase)]
            default: return [SessionPrescription(kind: .rest, minutes: 0, detail: "Repos, hydratation, sommeil.")]
            }
        }

        let intensityDays: [Int] = week.intensitySessions >= 2 ? [3, 5] : (week.intensitySessions == 1 ? [3] : [])
        if intensityDays.contains(weekday) {
            sessions.append(bike(intensityKind(phase: week.phase, slot: intensityDays.firstIndex(of: weekday) ?? 0),
                                 minutes: 75, ftp: ftp, phase: week.phase))
        } else if weekday == 7, week.longRideHours > 0 {
            sessions.append(bike(.longRide, minutes: Int(week.longRideHours * 60), ftp: ftp, phase: week.phase))
        } else {
            // Le reste du volume en endurance, réparti sur dimanche, lundi et mercredi (jamais le jour Legs).
            let intensityMinutes = Double(intensityDays.count) * 75
            let remaining = max(0, week.targetHours * 60 - week.longRideHours * 60 - intensityMinutes)
            let enduranceDays = [1, 2, 4].filter { strength[$0] != .legs }
            if enduranceDays.contains(weekday), remaining >= 30 {
                let minutes = min(90, Int(remaining / Double(enduranceDays.count) / 15) * 15)
                if minutes >= 30 { sessions.append(bike(.endurance, minutes: minutes, ftp: ftp, phase: week.phase)) }
            }
        }
        if sessions.isEmpty {
            sessions.append(SessionPrescription(kind: .rest, minutes: 0, detail: "Repos ou marche, 10 min de mobilité."))
        }
        return sessions
    }

    static func strengthSchedule(count: Int) -> [Int: SessionKind] {
        switch count {
        case 3...: [2: .push, 4: .pull, 6: .legs]
        case 2: [2: .upper, 5: .legs]
        case 1: [4: .fullBody]
        default: [:]
        }
    }

    static func intensityKind(phase: TrainingPhase, slot: Int) -> SessionKind {
        switch phase {
        case .reprise: .endurance
        case .base: slot == 0 ? .sweetSpot : .tempo
        case .build: slot == 0 ? .threshold : .vo2max
        case .specific: slot == 0 ? .threshold : .sweetSpot
        case .taper: .openers
        case .race: .openers
        }
    }

    static func watts(_ ftp: Double?, _ low: Double, _ high: Double) -> String {
        guard let ftp, ftp > 0 else { return "" }
        return " à \(Int(ftp * low))–\(Int(ftp * high)) W"
    }

    static func bike(_ kind: SessionKind, minutes: Int, ftp: Double?, phase: TrainingPhase) -> SessionPrescription {
        let detail: String
        switch kind {
        case .recovery: detail = "Pédalage très souple\(watts(ftp, 0.40, 0.55)) (zone 1), cadence 90+."
        case .endurance: detail = "Continu\(watts(ftp, 0.56, 0.75)) (zone 2), tu dois pouvoir parler."
        case .tempo: detail = "2 × 20 min\(watts(ftp, 0.76, 0.87)), récup 5 min."
        case .sweetSpot: detail = (phase == .base ? "3 × 12 min" : "3 × 15 min") + "\(watts(ftp, 0.88, 0.94)), récup 4 min."
        case .threshold: detail = "4 × 8 min\(watts(ftp, 0.95, 1.05)), récup 4 min."
        case .vo2max: detail = "5 × 4 min\(watts(ftp, 1.06, 1.20)), récup 4 min."
        case .openers: detail = "45 min Z2 dont 3 × 1 min\(watts(ftp, 1.10, 1.20)) pour réveiller les jambes."
        case .longRide: detail = "Zone 2\(watts(ftp, 0.56, 0.75)), idéalement en gravel. Teste ta nutrition de course : 60–90 g de glucides/h."
        default: detail = ""
        }
        return SessionPrescription(kind: kind, minutes: minutes, detail: detail)
    }

    static func strengthSession(_ kind: SessionKind, sets: String = "3–4 séries", rpe: String = "RPE 8 (2 reps en réserve)") -> SessionPrescription {
        let exercises: String
        switch kind {
        case .push: exercises = "Développé couché, développé militaire, élévations latérales, triceps"
        case .pull: exercises = "Tractions ou tirage, rowing, face pull, curls"
        case .legs: exercises = "Squat ou presse, fentes, hip thrust, mollets"
        case .upper: exercises = "Développé couché, rowing, développé militaire, tirage vertical"
        default: exercises = "Squat, développé couché, rowing, gainage"
        }
        return SessionPrescription(kind: kind, minutes: 60, detail: "\(exercises) · \(sets), \(rpe).")
    }

    // MARK: Brief du jour

    static func brief(_ input: DailyCoachInput, calendar: Calendar = .current) -> DailyBrief {
        let weekday = calendar.component(.weekday, from: input.today)
        let planned: [SessionPrescription]
        if !input.externalPlan.isEmpty {
            planned = input.externalPlan.map { external(from: $0, ftp: input.ftp) }
        } else if let week = input.week {
            planned = template(for: week, weekday: weekday, ftp: input.ftp)
        } else {
            planned = []
        }

        var factors: [CoachFactor] = []
        var changes: [String] = []
        var priorities: [(weight: Double, text: String)] = []
        var fueling: [String] = []
        var noIntensity = false

        // Santé : récupération (VFC + FC repos + sommeil).
        if let readiness = input.readiness {
            let impact: Double = readiness.level == .ready ? 0.05 : (readiness.level == .moderate ? -0.15 : -0.4)
            factors.append(CoachFactor(domain: .health, name: "Récupération", impact: impact,
                                       detail: "\(readiness.score)/100 · \(readiness.level.label.lowercased())"))
        }

        // Santé : nuit dernière.
        if let sleep = input.lastNightSleep {
            if sleep < 6 {
                noIntensity = true
                factors.append(CoachFactor(domain: .health, name: "Nuit courte", impact: -0.2,
                                           detail: String(format: "%.1f h : la puissance et la force maximales baissent après moins de 6 h", sleep)))
                priorities.append((0.9, "Nuit courte : sieste de 20 min si possible, et au lit 1 h plus tôt ce soir."))
            } else if sleep < input.sleepNeed - 1 {
                factors.append(CoachFactor(domain: .health, name: "Nuit un peu courte", impact: -0.08,
                                           detail: String(format: "%.1f h pour un besoin de %.1f h", sleep, input.sleepNeed)))
            } else {
                factors.append(CoachFactor(domain: .health, name: "Bonne nuit", impact: 0.03,
                                           detail: String(format: "%.1f h de sommeil", sleep)))
            }
        }
        if let debt = input.sleepDebt7, debt >= 5 {
            factors.append(CoachFactor(domain: .health, name: "Dette de sommeil", impact: -0.1,
                                       detail: String(format: "%.1f h manquantes sur 7 jours", debt)))
            priorities.append((0.7, String(format: "Dette de sommeil de %.0f h : vise +45 min par nuit cette semaine.", debt)))
        }

        // Entraînement : fatigue accumulée.
        if let form = input.load?.form {
            if form < -35 {
                factors.append(CoachFactor(domain: .sport, name: "Fatigue très élevée", impact: -0.3, detail: String(format: "Forme %.0f", form)))
                noIntensity = true
            } else if form < -25 {
                factors.append(CoachFactor(domain: .sport, name: "Fatigue élevée", impact: -0.15, detail: String(format: "Forme %.0f", form)))
            } else if form > 5 {
                factors.append(CoachFactor(domain: .sport, name: "Fraîcheur", impact: 0.05, detail: String(format: "Forme +%.0f", form)))
            }
        }
        if let ratio = input.acuteChronicRatio, ratio > 1.5 {
            factors.append(CoachFactor(domain: .sport, name: "Pic de charge", impact: -0.2,
                                       detail: String(format: "Ratio 7 j / 28 j : %.2f (zone sûre ≤ 1,3)", ratio)))
        }

        // Entraînement : jambes encore fatiguées par la séance Legs.
        var legsRecent = false
        if let legs = input.lastLegsSession {
            let hours = input.today.timeIntervalSince(legs) / 3600
            if hours >= 0 && hours < 30 {
                legsRecent = true
                factors.append(CoachFactor(domain: .sport, name: "Séance Legs récente", impact: -0.05,
                                           detail: String(format: "Il y a %.0f h : jambes encore entamées pour une séance intense", hours)))
            }
        }

        // Nutrition : la veille.
        var lowCarbs = false
        if let yesterday = input.yesterdayNutrition, yesterday.kcal > 800, input.weightKg > 0 {
            let carbsPerKg = yesterday.carbs / input.weightKg
            let proteinPerKg = yesterday.protein / input.weightKg
            if let expenditure = input.expenditure, yesterday.kcal < expenditure - 500 {
                let deficit = expenditure - yesterday.kcal
                factors.append(CoachFactor(domain: .nutrition, name: "Déficit calorique hier", impact: -0.1,
                                           detail: String(format: "−%.0f kcal par rapport à ta dépense", deficit)))
                priorities.append((0.8, String(format: "Tu as mangé %.0f kcal de moins que ta dépense hier : rattrape aujourd'hui, sinon la récupération et la prise de muscle en pâtissent.", deficit)))
            }
            if carbsPerKg < 5 {
                lowCarbs = true
                factors.append(CoachFactor(domain: .nutrition, name: "Glucides bas hier", impact: -0.05,
                                           detail: String(format: "%.1f g/kg : réserves de glycogène probablement incomplètes", carbsPerKg)))
            } else {
                factors.append(CoachFactor(domain: .nutrition, name: "Glucides OK hier", impact: 0,
                                           detail: String(format: "%.1f g/kg", carbsPerKg)))
            }
            if proteinPerKg < 1.6 {
                factors.append(CoachFactor(domain: .nutrition, name: "Protéines basses hier", impact: -0.03,
                                           detail: String(format: "%.1f g/kg (objectif ≥ 1,6)", proteinPerKg)))
                priorities.append((0.6, String(format: "Protéines : vise %.0f g aujourd'hui, en 4 prises de 30–40 g.", input.weightKg * 1.8)))
            }
        }

        // Entraînement : charge hors sport de la veille.
        if input.lifeLoadYesterday >= 40 {
            let impact: Double = input.lifeLoadYesterday >= 80 ? -0.15 : -0.08
            factors.append(CoachFactor(domain: .sport, name: "Journée physique hier", impact: impact,
                                       detail: String(format: "Activité hors sport ≈ %.0f TSS (travaux, debout…)", input.lifeLoadYesterday)))
        }
        if let steps = input.stepsYesterday, steps >= 20_000 {
            factors.append(CoachFactor(domain: .sport, name: "Beaucoup de pas hier", impact: -0.05,
                                       detail: String(format: "%.0f pas", steps)))
        }
        if !input.recurrentLegSymptoms.isEmpty {
            factors.append(CoachFactor(domain: .health, name: "Symptôme récurrent", impact: -0.05,
                                       detail: input.recurrentLegSymptoms.joined(separator: ", ")))
            priorities.append((0.85, "Symptôme récurrent (\(input.recurrentLegSymptoms[0])) : note-le dans le journal s'il réapparaît, et consulte s'il persiste."))
        }

        // Disponibilité et blessures.
        let legInjury = input.injuries.contains { !$0.muscles.isDisjoint(with: Set(Muscle.allCases.filter(\.isLegDriver))) }
        let hamstring = input.injuries.contains { $0.muscles.contains(.hamstrings) }

        var totalImpact: Double = 0
        for factor in factors { totalImpact += factor.impact }
        let capacity: Double = min(1.1, max(0, 1 + totalImpact))
        let verdict: Verdict
        if let reason = input.unavailableToday, [UnavailabilityReason.illness, .injury].contains(reason) {
            verdict = .rest
            changes.append("\(reason.label) déclarée aujourd'hui : repos complet.")
        } else if capacity < 0.45 {
            verdict = .rest
        } else if capacity < 0.65 {
            verdict = .easy
        } else if capacity < 0.85 || noIntensity {
            verdict = .adjust
        } else if capacity >= 1.0, input.readiness?.level == .ready {
            verdict = .push
        } else {
            verdict = .go
        }
        if input.unavailableToday != nil, verdict != .rest {
            changes.append("Journée indisponible déclarée : séance courte uniquement si tu en as l'occasion.")
        }

        // Adaptation séance par séance.
        var adapted: [SessionPrescription] = []
        for session in planned {
            adapted += adapt(session, verdict: verdict, noIntensity: noIntensity, legsRecent: legsRecent,
                             legInjury: legInjury, hamstring: hamstring, ftp: input.ftp,
                             phase: input.week?.phase ?? .base, changes: &changes)
        }

        // Ravitaillement selon la séance retenue.
        var bikeMinutes = 0
        for session in adapted where session.kind.isBike { bikeMinutes += session.minutes }
        let intense = adapted.contains { $0.kind.isIntense }
        if bikeMinutes >= 150 {
            fueling.append("Avant : 1–2 g/kg de glucides 2–3 h avant (ex. \(Int(input.weightKg * 1.5)) g : riz, pain, banane).")
            fueling.append("Pendant : 60–90 g de glucides par heure (boisson + gels/barres), 500–750 ml d'eau par heure.")
        } else if bikeMinutes >= 75 || intense {
            fueling.append("Pendant : 30–60 g de glucides par heure (boisson sucrée ou barre).")
        } else if bikeMinutes > 0 {
            fueling.append("Séance courte : de l'eau suffit.")
        }
        if lowCarbs && (intense || bikeMinutes >= 120) {
            fueling.insert("Glucides bas hier : ajoute un repas riche en glucides avant la séance, sinon l'intensité sera difficile à tenir.", at: 0)
            priorities.append((0.75, "Recharge en glucides avant ta séance : tes réserves sont basses depuis hier."))
        }
        if adapted.contains(where: { $0.kind.isStrength }) || intense || bikeMinutes >= 90 {
            fueling.append(String(format: "Après : %.0f–%.0f g de protéines + glucides dans les 2 h.", input.weightKg * 0.3, input.weightKg * 0.4))
        }

        if !changes.isEmpty { priorities.append((0.95, changes[0])) }
        let topPriorities = priorities.sorted { $0.weight > $1.weight }.map(\.text).prefix(3)

        return DailyBrief(
            verdict: verdict,
            capacity: capacity,
            headline: headline(verdict: verdict, factors: factors),
            planned: planned,
            adapted: adapted,
            changes: changes,
            factors: factors.sorted { $0.impact < $1.impact },
            fueling: fueling,
            priorities: Array(topPriorities),
            references: [Science.kiviniemi2007, Science.fullagar2015, Science.burke2011, Science.jeukendrup2014,
                         Science.mountjoy2018, Science.wilson2012, Science.morton2018])
    }

    static func external(from planned: PlannedSessionInput, ftp: Double?) -> SessionPrescription {
        if planned.sport == .strength { return SessionPrescription(kind: .fullBody, minutes: planned.minutes, detail: planned.name) }
        // On déduit l'intensité de la charge prévue : IF = √(TSS / (heures × 100)).
        var kind: SessionKind = .endurance
        if let tss = planned.tss, planned.minutes > 0 {
            let intensity = (tss / (Double(planned.minutes) / 60 * 100)).squareRoot()
            if planned.minutes >= 150 { kind = .longRide } else if intensity >= 0.85 { kind = .threshold } else if intensity >= 0.76 { kind = .sweetSpot }
        }
        return SessionPrescription(kind: kind, minutes: planned.minutes, detail: "\(planned.name) (Intervals.icu)")
    }

    private static func adapt(_ session: SessionPrescription,
                              verdict: Verdict,
                              noIntensity: Bool,
                              legsRecent: Bool,
                              legInjury: Bool,
                              hamstring: Bool,
                              ftp: Double?,
                              phase: TrainingPhase,
                              changes: inout [String]) -> [SessionPrescription] {
        if session.kind == .rest || session.kind == .race { return [session] }

        // Musculation.
        if session.kind.isStrength {
            var result = session
            if session.kind == .legs && hamstring {
                result = SessionPrescription(kind: .legs, minutes: 50,
                                             detail: "Presse, leg extension, hip thrust léger, mollets. Pas de soulevé de terre ni de leg curl lourd (ischio).")
                changes.append("Legs adaptée à ta blessure aux ischios.")
            }
            switch verdict {
            case .rest:
                changes.append("\(session.kind.label) remplacée par 20 min de mobilité : récupération trop basse.")
                return [SessionPrescription(kind: .mobility, minutes: 20, detail: "Mobilité hanches / dos, gainage léger.")]
            case .easy:
                changes.append("\(session.kind.label) allégée : une série de moins par exercice, RPE 7 max, pas de nouvelle charge.")
                return [SessionPrescription(kind: result.kind, minutes: 45,
                                            detail: result.detail + " Version allégée : 2–3 séries, RPE 7 max, aucune série à l'échec.")]
            case .adjust:
                changes.append("\(session.kind.label) : garde les charges de la dernière fois, n'en ajoute pas aujourd'hui.")
                return [result]
            case .go, .push:
                return [result]
            }
        }

        // Vélo.
        switch verdict {
        case .rest:
            changes.append("\(session.kind.label) remplacée par du repos (ou 30 min très souples).")
            return [bike(.recovery, minutes: 30, ftp: ftp, phase: phase)]
        case .easy:
            if session.kind.isIntense || session.kind == .longRide {
                let minutes = session.kind == .longRide ? Int(Double(session.minutes) * 0.6) : 60
                changes.append("\(session.kind.label) remplacée par de l'endurance (\((Double(minutes) / 60).hoursText)) : ta capacité du jour est trop basse pour bénéficier de l'intensité.")
                return [bike(.endurance, minutes: minutes, ftp: ftp, phase: phase)]
            }
            changes.append("Endurance raccourcie de 25 %.")
            return [bike(.endurance, minutes: Int(Double(session.minutes) * 0.75), ftp: ftp, phase: phase)]
        case .adjust, .go, .push:
            if session.kind.isIntense && (noIntensity || legInjury) {
                changes.append("\(session.kind.label) passée en endurance : \(legInjury ? "blessure aux jambes" : "nuit trop courte ou fatigue trop élevée").")
                return [bike(.endurance, minutes: 60, ftp: ftp, phase: phase)]
            }
            if session.kind.isIntense && legsRecent {
                changes.append("\(session.kind.label) : séance Legs il y a moins de 30 h, vise le bas des fourchettes de watts (ou décale à demain).")
            }
            if verdict == .adjust && session.kind.isIntense {
                changes.append("\(session.kind.label) : une répétition de moins, au bas de la fourchette de watts.")
            }
            if verdict == .adjust && session.kind == .longRide {
                changes.append("Sortie longue maintenue, mais strictement en zone 2 et bien ravitaillée.")
            }
            if verdict == .push && session.kind.isIntense {
                changes.append("Excellente récupération : si les sensations suivent, vise le haut des fourchettes.")
            }
            return [session]
        }
    }

    private static func headline(verdict: Verdict, factors: [CoachFactor]) -> String {
        let negatives = factors.filter { $0.impact < 0 }.sorted { $0.impact < $1.impact }.prefix(2).map { $0.name.lowercased() }
        switch verdict {
        case .push: return "Tout est au vert : sommeil, récupération et fraîcheur. Jour idéal pour ta séance clé."
        case .go: return negatives.isEmpty ? "Bonne journée pour suivre le plan." : "Plan maintenu, malgré : \(negatives.joined(separator: ", "))."
        case .adjust: return "On garde la séance mais on l'ajuste (\(negatives.joined(separator: ", ")))."
        case .easy: return "Ton corps a besoin de récupérer (\(negatives.joined(separator: ", "))) : journée facile."
        case .rest: return "Repos aujourd'hui : c'est ce qui te fera progresser."
        }
    }
}
