import Foundation

// MARK: - Séances

enum SessionKind: String, Equatable {
    case rest, mobility, recovery, endurance, tempo, sweetSpot, threshold, vo2max, openers, longRide, race
    /// Musculation : une de tes séances types, choisie au démarrage.
    case gym

    var isStrength: Bool { self == .gym }
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
        case .gym: "Musculation"
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
        case .gym: "dumbbell.fill"
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
    /// Signaux rouges détectés (VFC, sommeil, ACWR, douleur, respiration, fatigue).
    var redSignals: [String] = []
    /// Règles de décision déclenchées, dans l'ordre.
    var rules: [String] = []
    /// Séances déjà faites aujourd'hui.
    var doneToday: [String] = []
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
    /// Dette de sommeil pondérée sur 14 nuits (× 0,85 par jour d'ancienneté). Nom historique conservé.
    var sleepDebt7: Double?
    var load: LoadPoint?
    var acuteChronicRatio: Double?
    var yesterdayNutrition: NutritionDay?
    var expenditure: Double?
    var weightKg: Double
    var week: PlannedWeek?
    var externalPlan: [PlannedSessionInput] = []
    /// Séances placées aujourd'hui par l'organisateur de la semaine (prioritaires sur le plan type).
    var scheduledToday: [SessionPrescription]?
    /// Séances déjà faites aujourd'hui (titres).
    var doneToday: [String] = []
    /// Heures d'entraînement d'hier (repère glucides de la veille).
    var yesterdayTrainingHours: Double = 0
    var weightGoal: WeightGoal = .gain
    /// Écart calorique voulu (un déficit voulu n'est pas signalé comme un problème).
    var calorieAdjustment: Double = 300
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
    /// Fréquence respiratoire nocturne au-dessus de la normale (signal de maladie).
    var respiratory: RespiratorySignal?
    /// VFC 7 j vs base : écart en % et score z robuste.
    var hrvDeltaPercent: Double?
    var hrvZ: Double?
    /// Sommeil de la nuit / besoin.
    var sleepPerformance: Double?
    /// Douleur déclarée aujourd'hui (journal de symptômes, intensité ≥ 4).
    var painToday: String?
    /// Minutes disponibles aujourd'hui (nil = pas de contrainte).
    var availableMinutesToday: Int?
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
            // Tout se cale sur le vrai jour de la course (dimanche par défaut).
            let raceWeekday = week.raceDay.map { Calendar.current.component(.weekday, from: $0) } ?? 1
            // Position dans la semaine (lundi = 0) : rien n'est placé après la course.
            let daysBefore = (raceWeekday + 5) % 7 - (weekday + 5) % 7
            switch daysBefore {
            case 0: return [SessionPrescription(kind: .race, minutes: 0, detail: "Jour J : petit-déjeuner riche en glucides 3 h avant, 60–90 g de glucides par heure pendant la course.")]
            case 1: return [bike(.openers, minutes: 45, ftp: ftp, phase: week.phase)]
            case 3, 5: return [bike(.endurance, minutes: 45, ftp: ftp, phase: week.phase)]
            default: return [SessionPrescription(kind: .rest, minutes: 0, detail: "Repos, hydratation, sommeil.")]
            }
        }

        // Nombre de séances vélo choisi : d'abord la sortie longue, puis l'intensité, puis l'endurance.
        let bikeCount = max(1, week.bikeSessions)
        let hasLong = week.longRideHours > 0
        let intensityCount = min(week.intensitySessions, max(0, bikeCount - (hasLong ? 1 : 0)))
        let intensityDays: [Int] = intensityCount >= 2 ? [3, 5] : (intensityCount == 1 ? [3] : [])
        let enduranceCount = max(0, bikeCount - (hasLong ? 1 : 0) - intensityCount)
        // Jours proposés par défaut pour l'endurance (dimanche, mercredi, lundi, vendredi) : déplaçables dans « Ma semaine ».
        let enduranceDays = Array([1, 4, 2, 6].prefix(enduranceCount))
        if intensityDays.contains(weekday) {
            let kind = intensityKind(phase: week.phase, slot: intensityDays.firstIndex(of: weekday) ?? 0)
            sessions.append(bike(kind, minutes: kind == .openers ? 45 : 75, ftp: ftp, phase: week.phase))
        } else if weekday == 7, hasLong {
            sessions.append(bike(.longRide, minutes: Int(week.longRideHours * 60), ftp: ftp, phase: week.phase))
        } else if enduranceDays.contains(weekday) {
            // Le reste du volume en endurance, réparti sur les séances restantes.
            let intensityMinutes = Double(intensityDays.count) * (week.phase == .taper ? 45 : 75)
            let remaining = max(0, week.targetHours * 60 - week.longRideHours * 60 - intensityMinutes)
            let minutes = min(150, Int(remaining / Double(enduranceCount) / 15) * 15)
            sessions.append(bike(.endurance, minutes: max(45, minutes), ftp: ftp, phase: week.phase))
        }
        if sessions.isEmpty {
            sessions.append(SessionPrescription(kind: .rest, minutes: 0, detail: "Repos ou marche, 10 min de mobilité."))
        }
        return sessions
    }

    static func strengthSchedule(count: Int) -> [Int: SessionKind] {
        switch count {
        // Jours proposés par défaut (lundi, mercredi, vendredi, puis mardi, jeudi, dimanche) : déplaçables dans « Ma semaine ».
        case 1: [4: .gym]
        case 2: [2: .gym, 4: .gym]
        case 3...:
            Dictionary(uniqueKeysWithValues: [2, 4, 6, 3, 5, 1].prefix(min(count, 6)).map { ($0, SessionKind.gym) })
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
        case .longRide: detail = "Zone 2\(watts(ftp, 0.56, 0.75)), idéalement sur le terrain de ta course. Teste ta nutrition de course : 60–90 g de glucides/h."
        default: detail = ""
        }
        return SessionPrescription(kind: kind, minutes: minutes, detail: detail)
    }

    static func strengthSession(_ kind: SessionKind) -> SessionPrescription {
        SessionPrescription(kind: kind, minutes: 60, detail: "Une de tes séances types, au choix au démarrage.")
    }

    // MARK: Brief du jour

    static func brief(_ input: DailyCoachInput, calendar: Calendar = .current) -> DailyBrief {
        let weekday = calendar.component(.weekday, from: input.today)
        let planned: [SessionPrescription]
        if !input.externalPlan.isEmpty {
            planned = input.externalPlan.map { external(from: $0, ftp: input.ftp) }
        } else if let scheduled = input.scheduledToday {
            planned = scheduled
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
            // Calibré sur readiness-3 : une journée « dans ta normale » ≈ 60 (zones 67/34).
            // ≥ 67 : bonus · 45–66 : neutre (normal) · moyenne mais < 45 : −15 % · basse (< 34) : −40 %.
            let impact: Double
            switch readiness.level {
            case .ready: impact = 0.05
            case .low: impact = -0.4
            case .moderate: impact = readiness.score >= 45 ? 0 : -0.15
            }
            factors.append(CoachFactor(domain: .health, name: "Récupération", impact: impact,
                                       detail: "\(readiness.score)/100 · \(readiness.level.label.lowercased())"))
        }

        // Santé : nuit dernière. Déjà comptée dans la récupération quand elle existe : pas de double peine.
        let sleepInReadiness = input.readiness != nil
        if let sleep = input.lastNightSleep {
            if sleep < 6 {
                noIntensity = true
                factors.append(CoachFactor(domain: .health, name: "Nuit courte", impact: sleepInReadiness ? 0 : -0.2,
                                           detail: String(format: "%.1f h : la puissance et la force maximales baissent après moins de 6 h", locale: Locale.current, sleep)))
                priorities.append((0.9, "Nuit < 6 h : sieste de 20 min si possible, coucher avancé d'1 h ce soir."))
            } else if sleep < input.sleepNeed - 1 {
                factors.append(CoachFactor(domain: .health, name: "Nuit un peu courte", impact: sleepInReadiness ? 0 : -0.08,
                                           detail: String(format: "%.1f h pour un besoin de %.1f h", locale: Locale.current, sleep, input.sleepNeed)))
            } else {
                factors.append(CoachFactor(domain: .health, name: "Bonne nuit", impact: sleepInReadiness ? 0 : 0.03,
                                           detail: String(format: "%.1f h de sommeil", locale: Locale.current, sleep)))
            }
        }
        if let debt = input.sleepDebt7, debt >= 5 {
            factors.append(CoachFactor(domain: .health, name: "Dette de sommeil", impact: -0.1,
                                       detail: String(format: "%.1f h manquantes sur 14 nuits (les plus récentes pèsent plus)", locale: Locale.current, debt)))
            priorities.append((0.7, String(format: "Dette de sommeil de %.0f h : vise +45 min par nuit cette semaine.", locale: Locale.current, debt)))
        }

        // Entraînement : fatigue accumulée.
        // Fatigue accumulée : déjà comptée dans la récupération quand elle existe.
        if let form = input.load?.form {
            let counted = input.readiness != nil
            if form < -35 {
                factors.append(CoachFactor(domain: .sport, name: "Fatigue très élevée", impact: counted ? 0 : -0.3, detail: "Forme \(form.noDecimal)"))
                noIntensity = true
            } else if form < -25 {
                factors.append(CoachFactor(domain: .sport, name: "Fatigue élevée", impact: counted ? 0 : -0.15, detail: "Forme \(form.noDecimal)"))
            } else if form > 5 {
                factors.append(CoachFactor(domain: .sport, name: "Fraîcheur", impact: counted ? 0 : 0.05, detail: "Forme +\(form.noDecimal)"))
            }
        }
        if let ratio = input.acuteChronicRatio, ratio > 1.5 {
            factors.append(CoachFactor(domain: .sport, name: "Pic de charge", impact: -0.2,
                                       detail: String(format: "Ratio 7 j / 28 j : %.2f (zone sûre ≤ 1,3)", locale: Locale.current, ratio)))
        }

        // Entraînement : jambes encore fatiguées par la muscu du bas du corps.
        var legsRecent = false
        if let legs = input.lastLegsSession {
            let hours = input.today.timeIntervalSince(legs) / 3600
            if hours >= 0 && hours < 30 {
                legsRecent = true
                factors.append(CoachFactor(domain: .sport, name: "Muscu des jambes récente", impact: -0.05,
                                           detail: String(format: "Il y a %.0f h : jambes encore entamées pour une séance intense", locale: Locale.current, hours)))
            }
        }

        // Nutrition : la veille.
        var lowCarbs = false
        // Nutrition de la veille : seulement si la journée a vraiment été notée (≥ 60 % de la dépense).
        let dayLogged = input.yesterdayNutrition.map { day in
            day.kcal > 800 && (input.expenditure.map { day.kcal >= 0.6 * $0 } ?? true)
        } ?? false
        if let yesterday = input.yesterdayNutrition, dayLogged, input.weightKg > 0 {
            let carbsPerKg = yesterday.carbs / input.weightKg
            let proteinPerKg = yesterday.protein / input.weightKg
            // Un déficit voulu (objectif perte de poids) n'est signalé qu'au-delà de l'écart choisi.
            let allowedDeficit: Double = 500 + max(0, -input.calorieAdjustment)
            if let expenditure = input.expenditure, yesterday.kcal < expenditure - allowedDeficit {
                let deficit = expenditure - yesterday.kcal
                factors.append(CoachFactor(domain: .nutrition, name: "Déficit calorique hier", impact: -0.1,
                                           detail: "−\(deficit.noDecimal) kcal par rapport à ta dépense"))
                priorities.append((0.8, "Apport d'hier : −\(deficit.noDecimal) kcal vs ta dépense. Aujourd'hui, un apport un peu plus élevé soutient la récupération."))
            }
            // Repère glucides de la veille selon l'entraînement réellement fait hier (Burke 2011), 20 % de marge.
            let carbFloor = NutritionPlanner.carbsPerKg(trainingHours: input.yesterdayTrainingHours) * 0.8
            if carbsPerKg < carbFloor {
                lowCarbs = true
                factors.append(CoachFactor(domain: .nutrition, name: "Glucides bas hier", impact: -0.05,
                                           detail: "\(carbsPerKg.oneDecimal) g/kg pour \(input.yesterdayTrainingHours.oneDecimal) h d'entraînement : réserves de glycogène probablement incomplètes"))
            } else {
                factors.append(CoachFactor(domain: .nutrition, name: "Glucides OK hier", impact: 0,
                                           detail: "\(carbsPerKg.oneDecimal) g/kg"))
            }
            if proteinPerKg < 1.6 {
                factors.append(CoachFactor(domain: .nutrition, name: "Protéines basses hier", impact: -0.03,
                                           detail: "\(proteinPerKg.oneDecimal) g/kg (objectif ≥ 1,6)"))
                priorities.append((0.6, "Protéines : vise \((input.weightKg * 1.8).noDecimal) g aujourd'hui, en 4 prises de 30–40 g."))
            }
        }

        // Entraînement : charge hors sport de la veille.
        if input.lifeLoadYesterday >= 40 {
            let impact: Double = input.lifeLoadYesterday >= 80 ? -0.15 : -0.08
            factors.append(CoachFactor(domain: .sport, name: "Journée physique hier", impact: impact,
                                       detail: "Activité hors sport ≈ \(input.lifeLoadYesterday.noDecimal) points de charge (travaux, debout…)"))
        }
        if let steps = input.stepsYesterday, steps >= 20_000 {
            factors.append(CoachFactor(domain: .sport, name: "Beaucoup de pas hier", impact: -0.05,
                                       detail: String(format: "%.0f pas", locale: Locale.current, steps)))
        }
        if !input.recurrentLegSymptoms.isEmpty {
            factors.append(CoachFactor(domain: .health, name: "Symptôme récurrent", impact: -0.05,
                                       detail: input.recurrentLegSymptoms.joined(separator: ", ")))
            priorities.append((0.85, "Symptôme récurrent (\(input.recurrentLegSymptoms[0])) : note-le dans le journal s'il réapparaît, et consulte s'il persiste."))
        }

        // Santé : fréquence respiratoire (signal précoce d'infection).
        if let signal = input.respiratory, signal.isWarning {
            noIntensity = true
            let impact: Double = signal.restingHRUp ? -0.35 : -0.2
            factors.append(CoachFactor(domain: .health, name: "Respiration nocturne élevée", impact: impact,
                                       detail: String(format: "%.1f resp/min (normale %.1f)%@", locale: Locale.current, signal.latest, signal.baseline,
                                                      signal.restingHRUp ? " + FC de repos en hausse" : "")))
            priorities.append((1.0, signal.restingHRUp
                ? "Respiration et FC de repos en hausse : possible infection qui commence. Pas d'intensité, hydrate-toi, repos si symptômes."
                : "Respiration nocturne au-dessus de ta normale : surveille l'apparition de symptômes, pas d'intensité aujourd'hui."))
        }

        // Disponibilité et blessures.
        let legInjury = input.injuries.contains { !$0.muscles.isDisjoint(with: Set(Muscle.allCases.filter(\.isLegDriver))) }
        let hamstring = input.injuries.contains { $0.muscles.contains(.hamstrings) }

        var totalImpact: Double = 0
        for factor in factors { totalImpact += factor.impact }
        let capacity: Double = min(1.1, max(0, 1 + totalImpact))

        // Signaux rouges, décrits factuellement.
        var redSignals: [String] = []
        if let z = input.hrvZ, z < -1 {
            let delta = input.hrvDeltaPercent ?? 0
            redSignals.append("VFC 7 j \(delta >= 0 ? "+" : "−")\(abs(delta).noDecimal) % vs ta base")
        }
        if let sleep = input.lastNightSleep, sleep < 6 {
            redSignals.append("sommeil \(sleep.hoursText)")
        } else if let performance = input.sleepPerformance, performance < 0.75 {
            redSignals.append(String(format: "sommeil à %.0f %% du besoin", locale: Locale.current, performance * 100))
        }
        if let ratio = input.acuteChronicRatio, ratio > 1.5 {
            redSignals.append(String(format: "ratio de charge %.2f", locale: Locale.current, ratio))
        }
        if let form = input.load?.form, form < -30 {
            redSignals.append(String(format: "forme %.0f", locale: Locale.current, form))
        }
        if let signal = input.respiratory, signal.isWarning {
            redSignals.append(String(format: "respiration %+.1f/min", locale: Locale.current, signal.delta))
        }
        if let pain = input.painToday {
            redSignals.append(pain)
        }

        // Décision : capacité d'abord, puis règles explicites et hiérarchisées.
        var rules: [String] = []
        var verdict: Verdict
        if capacity < 0.45 { verdict = .rest }
        else if capacity < 0.65 { verdict = .easy }
        else if capacity < 0.85 || noIntensity { verdict = .adjust }
        else if capacity >= 1.0, input.readiness?.level == .ready { verdict = .push }
        else { verdict = .go }
        rules.append(String(format: "Capacité estimée %.0f %% → %@", locale: Locale.current, capacity * 100, verdict.label.lowercased()))

        if let reason = input.unavailableToday, [UnavailabilityReason.illness, .injury].contains(reason) {
            verdict = .rest
            rules.append("\(reason.label) déclarée aujourd'hui → repos")
            changes.append("\(reason.label) déclarée aujourd'hui : repos complet.")
        } else if input.painToday != nil || redSignals.count >= 3 {
            verdict = .rest
            rules.append(input.painToday != nil ? "Douleur déclarée → repos" : "\(redSignals.count) signaux rouges (≥ 3) → repos")
        } else if redSignals.count == 2 {
            if verdict == .go || verdict == .push || verdict == .adjust { verdict = .easy }
            rules.append("2 signaux rouges → séance adaptée (endurance facile)")
        } else if redSignals.count == 1, verdict == .push {
            verdict = .go
            rules.append("1 signal rouge → pas de séance au maximum")
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

        // Contrainte d'agenda : minutes disponibles aujourd'hui.
        if let available = input.availableMinutesToday, available > 0 {
            let total = adapted.reduce(0) { $0 + $1.minutes }
            if total > available {
                let ratio = Double(available) / Double(total)
                adapted = adapted.map { session in
                    session.minutes == 0 ? session : SessionPrescription(kind: session.kind, minutes: max(20, Int(Double(session.minutes) * ratio / 5) * 5), detail: session.detail)
                }
                changes.append("Disponibilité du jour : \(available) min, séances raccourcies en conséquence.")
                rules.append("Agenda : \(available) min disponibles → durée ajustée")
            }
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
            fueling.append(String(format: "Après : %.0f–%.0f g de protéines + glucides dans les 2 h.", locale: Locale.current, input.weightKg * 0.3, input.weightKg * 0.4))
        }

        if !changes.isEmpty { priorities.append((0.95, changes[0])) }
        let topPriorities = priorities.sorted { $0.weight > $1.weight }.map(\.text).prefix(3)

        return DailyBrief(
            verdict: verdict,
            capacity: capacity,
            headline: headline(verdict: verdict, redSignals: redSignals, factors: factors, adapted: adapted, doneToday: input.doneToday),
            planned: planned,
            adapted: adapted,
            changes: changes,
            factors: factors.sorted { $0.impact < $1.impact },
            fueling: fueling,
            priorities: Array(topPriorities),
            references: [Science.kiviniemi2007, Science.fullagar2015, Science.burke2011, Science.jeukendrup2014,
                         Science.mountjoy2018, Science.wilson2012, Science.morton2018],
            redSignals: redSignals,
            rules: rules,
            doneToday: input.doneToday)
    }

    static func external(from planned: PlannedSessionInput, ftp: Double?) -> SessionPrescription {
        if planned.sport == .strength { return SessionPrescription(kind: .gym, minutes: planned.minutes, detail: planned.name) }
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
            if hamstring {
                result = SessionPrescription(kind: session.kind, minutes: session.minutes,
                                             detail: session.detail + " Ischios blessés : pas de soulevé de terre ni de leg curl lourd.")
                changes.append("Muscu : évite les exercices lourds pour les ischios (blessure déclarée).")
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
                changes.append("\(session.kind.label) : muscu des jambes il y a moins de 30 h, vise le bas des fourchettes de watts (ou décale à demain).")
            }
            if verdict == .adjust && session.kind.isIntense {
                changes.append("\(session.kind.label) : une répétition de moins, au bas de la fourchette de watts.")
            }
            if legsRecent && session.kind == .longRide {
                let shorter = Int(Double(session.minutes) * 0.85 / 15) * 15
                changes.append("Muscu des jambes il y a moins de 30 h : sortie longue réduite à \((Double(shorter) / 60).hoursText), strictement en zone 2.")
                return [SessionPrescription(kind: .longRide, minutes: shorter, detail: session.detail)]
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

    /// Phrase factuelle : les signaux (chiffrés) puis la séance retenue. Jamais de jugement.
    private static func headline(verdict: Verdict, redSignals: [String], factors: [CoachFactor], adapted: [SessionPrescription],
                                 doneToday: [String] = []) -> String {
        let session = adapted.first.map { $0.title.lowercased() } ?? "repos"
        if adapted.isEmpty {
            // Rien de placé aujourd'hui : l'état du jour, sans séance à prescrire.
            let context = redSignals.isEmpty
                ? (factors.filter { $0.impact > 0 }.map { $0.detail }.prefix(2).joined(separator: ", "))
                : redSignals.prefix(3).joined(separator: ", ")
            let start = context.isEmpty ? "Indicateurs dans ta normale" : context
            if let done = doneToday.first {
                return "Séance faite (\(done)) : place à la récupération, protéines et glucides au prochain repas."
            }
            switch verdict {
            case .rest, .easy: return "\(start) : journée à ménager, rien de prévu aujourd'hui."
            default: return "\(start) : pas de séance prévue aujourd'hui."
            }
        }
        if redSignals.isEmpty {
            let positives = factors.filter { $0.impact > 0 }.map { $0.detail }.prefix(2)
            let context = positives.isEmpty ? "Indicateurs dans ta normale" : positives.joined(separator: ", ")
            switch verdict {
            case .push: return "\(context) : jour adapté à ta séance clé (\(session))."
            case .rest: return "\(context), mais capacité basse : repos conseillé."
            default: return "\(context) : \(session) comme prévu."
            }
        }
        let signals = redSignals.prefix(3).joined(separator: ", ")
        switch verdict {
        case .rest: return "\(signals) : repos conseillé."
        case .easy: return "\(signals) : \(session) conseillée."
        case .adjust: return "\(signals) : \(session), intensité réduite."
        case .go, .push: return "\(signals) : \(session) maintenue, à surveiller."
        }
    }
}
