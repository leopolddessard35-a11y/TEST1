import Foundation

// MARK: - Entrées

/// Une séance faite, vue par l'organisateur de la semaine.
struct DoneSession: Equatable, Identifiable {
    let id: String
    let date: Date
    let title: String
    let symbol: String
    let minutes: Int
    let isStrength: Bool
    /// Cardio intense : IF ≥ 0,76 (tempo et au-delà) ou effort ressenti ≥ 7.
    let isIntense: Bool
    /// Muscu avec au moins 3 séries pour le bas du corps.
    var isLegs = false
}

/// Les grandes familles de séances : c'est sur elles que se fait la correspondance « prévu ↔ fait ».
enum SessionCategory: String, CaseIterable {
    case race, long, intense, strength, endurance

    init(_ kind: SessionKind) {
        switch kind {
        case .race: self = .race
        case .longRide: self = .long
        case _ where kind.isStrength: self = .strength
        case _ where kind.isIntense: self = .intense
        default: self = .endurance
        }
    }

    var label: String {
        switch self {
        case .race: "Course"
        case .long: "Sortie longue"
        case .intense: "Séance intense"
        case .strength: "Musculation"
        case .endurance: "Endurance"
        }
    }

    var isCardio: Bool { self != .strength }
    /// Séances « dures » qu'on évite d'enchaîner deux jours de suite.
    var isHard: Bool { self == .long || self == .intense || self == .race }

    /// Ordre de placement : les séances clés d'abord, l'endurance remplit les trous.
    var priority: Int {
        switch self {
        case .race: 0
        case .long: 1
        case .intense: 2
        case .strength: 3
        case .endurance: 4
        }
    }
}

/// Tes habitudes, apprises sur les 8 dernières semaines : quel jour tu fais tes sorties longues,
/// ta muscu, tes séances intenses. Elles servent à placer les séances là où tu les fais vraiment.
struct TrainingHabits: Equatable {
    /// Pour chaque famille : part relative de chaque jour (1 = dimanche … 7 = samedi), le jour le plus fréquent valant 1.
    var shares: [SessionCategory: [Int: Double]] = [:]
    var counts: [SessionCategory: Int] = [:]

    /// Seuil de séances d'une famille avant de s'y fier.
    static let minimumSessions = 4

    static func learn(from sessions: [DoneSession], before: Date, weeks: Int = 8, calendar: Calendar = .current) -> TrainingHabits {
        guard let start = calendar.date(byAdding: .day, value: -7 * weeks, to: before) else { return TrainingHabits() }
        var tally: [SessionCategory: [Int: Int]] = [:]
        for session in sessions where session.date >= start && session.date < before {
            let weekday = calendar.component(.weekday, from: session.date)
            for category in categories(of: session) {
                tally[category, default: [:]][weekday, default: 0] += 1
            }
        }
        var habits = TrainingHabits()
        for (category, byDay) in tally {
            let top = byDay.values.max() ?? 0
            habits.counts[category] = byDay.values.reduce(0, +)
            guard top > 0 else { continue }
            habits.shares[category] = byDay.mapValues { Double($0) / Double(top) }
        }
        return habits
    }

    /// Familles auxquelles une séance faite appartient (une sortie longue est aussi de l'endurance).
    static func categories(of session: DoneSession) -> [SessionCategory] {
        if session.isStrength { return [.strength] }
        var result: [SessionCategory] = [.endurance]
        if session.minutes >= 120 { result.append(.long) }
        if session.isIntense { result.append(.intense) }
        return result
    }

    /// Affinité 0–1 d'une famille pour un jour ; 0 tant que l'historique est trop court.
    func affinity(_ category: SessionCategory, weekday: Int) -> Double {
        let key: SessionCategory = category == .race ? .long : category
        guard (counts[key] ?? 0) >= Self.minimumSessions else { return 0 }
        return shares[key]?[weekday] ?? 0
    }

    var isLearned: Bool { counts.values.contains { $0 >= Self.minimumSessions } }

    func isLearned(_ category: SessionCategory) -> Bool {
        let key: SessionCategory = category == .race ? .long : category
        return (counts[key] ?? 0) >= Self.minimumSessions
    }
}

// MARK: - Résultat

/// La semaine organisée : ce qui est fait, ce qui reste et où, ce qui n'a pas trouvé de place.
struct WeekPlan: Equatable {
    enum State: Equatable {
        case done(DoneSession)
        case planned
        /// Pas de jour possible d'ici dimanche, ou retirée à la main.
        case dropped
    }

    struct Item: Identifiable, Equatable {
        /// Identifiant stable dans la semaine (« intense-0 », « strength-1 »…).
        let id: String
        let session: SessionPrescription
        let category: SessionCategory
        /// Jour proposé par le plan type.
        let defaultDay: Date
        var day: Date?
        var state: State = .planned
        /// Jour choisi à la main.
        var isPinned = false
        /// Retirée de la semaine à la main.
        var isRemoved = false
        /// Déplacée automatiquement : son jour est passé sans séance.
        var wasRescheduled = false
        /// Faite, mais avec une séance d'un autre type (ex. endurance à la place du seuil).
        var isSubstitute = false

        var isDone: Bool {
            if case .done = state { return true }
            return false
        }

        var isPending: Bool { state == .planned }

        var doneSession: DoneSession? {
            if case .done(let session) = state { return session }
            return nil
        }
    }

    let week: PlannedWeek
    /// Les 7 jours de la semaine (lundi → dimanche), en début de journée.
    let days: [Date]
    let items: [Item]
    /// Séances faites en plus du plan.
    let extras: [DoneSession]

    /// Préfixe des choix « ne compte pas pour le plan » enregistrés comme placements.
    static let exclusionPrefix = "exclude:"
    let unavailableDays: Set<Date>
    let today: Date
    let habitsLearned: Bool
    /// Séances faites que tu as exclues du plan (« ne compte pas pour cette séance »).
    var excluded: Set<String> = []

    func items(on day: Date) -> [Item] { items.filter { $0.day == day } }
    func extras(on day: Date, calendar: Calendar = .current) -> [DoneSession] {
        extras.filter { calendar.isDate($0.date, inSameDayAs: day) }
    }

    var doneCount: Int { items.filter(\.isDone).count }
    var pendingCount: Int { items.filter(\.isPending).count }
    var droppedCount: Int { items.filter { $0.state == .dropped && !$0.isRemoved }.count }

    /// Séances encore à faire aujourd'hui.
    var pendingToday: [Item] { items(on: today).filter(\.isPending) }

    /// Jours où une séance peut encore être placée (aujourd'hui → dimanche).
    var remainingDays: [Date] { days.filter { $0 >= today } }

    func contains(_ day: Date) -> Bool { days.contains(day) }
}

// MARK: - Organisation

/// Organise la semaine du plan de saison : les séances viennent du plan, les jours viennent de toi.
///
/// 1. Les séances faites sont reconnues par leur type, quel que soit le jour (le seuil du mardi fait le mercredi compte).
/// 2. Une séance que tu as placée à la main reste à son jour.
/// 3. Les autres sont placées au mieux : jour habituel appris sur tes 8 dernières semaines, sinon jour du plan type,
///    en respectant quelques règles (pas deux séances dures d'affilée, pas d'intensité au lendemain des jambes,
///    pas de séance un jour indisponible ou trop court).
/// 4. Une séance dont le jour est passé sans être faite est replacée plus tard dans la semaine si possible ;
///    sinon elle est simplement abandonnée : jamais rattrapée, jamais comptée comme une faute.
enum WeekPlanner {
    /// Un jour déjà occupé (séance faite, en plus, ou déjà placée).
    struct Occupant: Equatable {
        let id: String
        let day: Date
        let category: SessionCategory
        let isLegs: Bool
    }

    struct Assessment: Equatable {
        var penalty: Double = 0
        var blocked = false
        /// Enchaînement à éviter (deux séances dures d'affilée, jambes la veille) : interdit pour une séance replacée.
        var hardConflict = false
        var reasons: [String] = []
    }

    static func make(week: PlannedWeek,
                     ftp: Double?,
                     done: [DoneSession],
                     habits: TrainingHabits,
                     pinned: [String: Date],
                     removed: Set<String>,
                     excluded: Set<String> = [],
                     unavailable: [UnavailabilityPeriod],
                     availableMinutes: (Int) -> Int?,
                     now: Date,
                     calendar: Calendar = .current) -> WeekPlan {
        let weekStart = calendar.startOfDay(for: week.start)
        let days: [Date] = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
        let todayStart = calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        var unavailableDays = Set<Date>()
        for day in days where unavailable.contains(where: {
            calendar.startOfDay(for: $0.start) <= day && day <= calendar.startOfDay(for: $0.end)
        }) {
            unavailableDays.insert(day)
        }

        // 1. Les séances du plan type de la semaine.
        var items: [WeekPlan.Item] = []
        // Identifiant = type de séance + rang (« threshold-0 », « gym-1 ») : un choix reste attaché à la même séance.
        var counters: [SessionKind: Int] = [:]
        for day in days {
            let sessions = DailyCoach.template(for: week, weekday: calendar.component(.weekday, from: day), ftp: ftp)
            for session in sessions where session.kind != .rest {
                let category = SessionCategory(session.kind)
                let index = counters[session.kind, default: 0]
                counters[session.kind] = index + 1
                let id = "\(session.kind.rawValue)-\(index)"
                var item = WeekPlan.Item(id: id, session: session, category: category, defaultDay: day, day: day)
                if removed.contains(id) {
                    item.isRemoved = true
                    item.isPinned = true
                    item.state = .dropped
                    item.day = nil
                } else if let choice = pinned[id].map({ calendar.startOfDay(for: $0) }), days.contains(choice) {
                    item.day = choice
                    item.isPinned = true
                }
                items.append(item)
            }
        }

        // 2. Ce qui a été fait cette semaine, reconnu par type (sauf ce que tu as exclu à la main).
        let weekDone = done.filter { $0.date >= weekStart && $0.date < weekEnd }.sorted { $0.date < $1.date }
        var extras: [DoneSession] = []
        for session in weekDone {
            if excluded.contains(session.id) {
                extras.append(session)
                continue
            }
            let day = calendar.startOfDay(for: session.date)
            var best: (index: Int, cost: Double, substitute: Bool)?
            for index in items.indices where !items[index].isDone {
                guard let match = matchCost(session, day: day, item: items[index], calendar: calendar) else { continue }
                if best == nil || match.cost < best!.cost { best = (index, match.cost, match.substitute) }
            }
            if let best {
                items[best.index].state = .done(session)
                items[best.index].day = day
                items[best.index].isSubstitute = best.substitute
                items[best.index].isRemoved = false
            } else {
                extras.append(session)
            }
        }

        // 3. Jours occupés : séances faites, en plus, et séances placées à la main encore à venir.
        var occupants: [Occupant] = []
        for item in items {
            guard let day = item.day else { continue }
            if let session = item.doneSession {
                occupants.append(Occupant(id: item.id, day: day, category: category(of: session, matched: item.category), isLegs: session.isLegs))
            } else if item.isPending, (item.isPinned && day >= todayStart) || item.category == .race {
                occupants.append(Occupant(id: item.id, day: day, category: item.category, isLegs: false))
            }
        }
        // Une séance exclue (« ne compte pas ») n'occupe pas non plus son jour.
        for session in extras where !excluded.contains(session.id) {
            occupants.append(Occupant(id: session.id, day: calendar.startOfDay(for: session.date),
                                      category: category(of: session, matched: nil), isLegs: session.isLegs))
        }

        // 4. Placement du reste, séances clés d'abord.
        let hour = calendar.component(.hour, from: now)
        let order = items.indices.filter { index in
            let item = items[index]
            guard item.isPending else { return false }
            if item.category == .race { return false }
            // Placée à la main pour un jour à venir : on n'y touche pas.
            if item.isPinned, let day = item.day, day >= todayStart { return false }
            return true
        }.sorted { lhs, rhs in
            let a = items[lhs], b = items[rhs]
            // Les séances encore à l'heure d'abord : une séance en retard se glisse dans ce qui reste.
            let lateA = (a.isPinned ? (a.day ?? a.defaultDay) : a.defaultDay) < todayStart
            let lateB = (b.isPinned ? (b.day ?? b.defaultDay) : b.defaultDay) < todayStart
            if lateA != lateB { return !lateA }
            if a.category.priority != b.category.priority { return a.category.priority < b.category.priority }
            return a.defaultDay < b.defaultDay
        }
        for index in order {
            let item = items[index]
            let reference = item.isPinned ? (item.day ?? item.defaultDay) : item.defaultDay
            var best: (day: Date, score: Double)?
            for day in days where day >= todayStart {
                let assessment = assess(category: item.category, kind: item.session.kind, minutes: item.session.minutes,
                                        day: day, ignoring: item.id, occupants: occupants, unavailable: unavailableDays,
                                        availableMinutes: availableMinutes(calendar.component(.weekday, from: day)),
                                        calendar: calendar)
                if assessment.blocked { continue }
                // Une séance replacée ne doit jamais créer un enchaînement dur.
                if reference < todayStart, assessment.hardConflict { continue }
                // Trop tard ce soir pour une séance qui n'était pas prévue aujourd'hui.
                if day == todayStart, hour >= 20, reference != todayStart { continue }
                var score = -assessment.penalty
                // Habitudes apprises : elles comptent plus que le jour du plan type (mais un jour choisi reste prioritaire).
                let learned = habits.isLearned(item.category)
                if day == reference { score += (learned && !item.isPinned) ? 1 : 3 }
                score += (learned ? 3 : 2) * habits.affinity(item.category, weekday: calendar.component(.weekday, from: day))
                let distance = abs(Double(calendar.dateComponents([.day], from: reference, to: day).day ?? 0))
                score -= 0.3 * distance
                if best == nil || score > best!.score { best = (day, score) }
            }
            if let best {
                items[index].day = best.day
                items[index].wasRescheduled = reference < todayStart
                // Un jour choisi déjà passé ne compte plus comme choix.
                if reference < todayStart { items[index].isPinned = false }
                occupants.append(Occupant(id: item.id, day: best.day, category: item.category, isLegs: false))
            } else {
                items[index].day = nil
                items[index].state = .dropped
                items[index].wasRescheduled = reference < todayStart
            }
        }

        let ordered = items.sorted { lhs, rhs in
            switch (lhs.day, rhs.day) {
            case let (a?, b?): return a == b ? lhs.category.priority < rhs.category.priority : a < b
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return lhs.defaultDay < rhs.defaultDay
            }
        }
        return WeekPlan(week: week, days: days, items: ordered, extras: extras, unavailableDays: unavailableDays,
                        today: todayStart, habitsLearned: habits.isLearned, excluded: excluded)
    }

    /// Coût de la correspondance entre une séance faite et une séance du plan ; nil = incompatible.
    static func matchCost(_ session: DoneSession, day: Date, item: WeekPlan.Item,
                          calendar: Calendar) -> (cost: Double, substitute: Bool)? {
        let reference = item.day ?? item.defaultDay
        let distance = abs(Double(calendar.dateComponents([.day], from: reference, to: day).day ?? 0))
        var cost = distance + (item.isRemoved ? 50 : 0)
        if session.isStrength {
            guard item.category == .strength else { return nil }
            return (cost, false)
        }
        switch item.category {
        case .strength:
            return nil
        case .race:
            return distance == 0 ? (cost, false) : nil
        case .endurance:
            // Trop courte pour valoir la séance prévue : comptée « en plus ».
            guard Double(session.minutes) >= 0.5 * Double(item.session.minutes) else { return nil }
            // Une sortie intense ou longue remplit d'abord sa propre séance.
            if session.isIntense || session.minutes >= 120 { cost += 10 }
            return (cost, false)
        case .long:
            if Double(session.minutes) >= 0.75 * Double(item.session.minutes) { return (cost, false) }
            return distance <= 1 ? (cost + 100, true) : nil
        case .intense:
            if session.isIntense { return (cost, false) }
            return distance <= 1 ? (cost + 100, true) : nil
        }
    }

    /// Famille d'une séance faite (pour les règles d'enchaînement).
    static func category(of session: DoneSession, matched: SessionCategory?) -> SessionCategory {
        if session.isStrength { return .strength }
        if session.isIntense { return .intense }
        if session.minutes >= 120 || matched == .long { return .long }
        return .endurance
    }

    /// Ce que coûte un jour pour une séance : règles d'enchaînement, disponibilité, temps libre.
    static func assess(category: SessionCategory,
                       kind: SessionKind,
                       minutes: Int,
                       day: Date,
                       ignoring id: String,
                       occupants: [Occupant],
                       unavailable: Set<Date>,
                       availableMinutes: Int?,
                       calendar: Calendar = .current) -> Assessment {
        var result = Assessment()
        let others = occupants.filter { $0.id != id }
        let sameDay = others.filter { $0.day == day }
        let previous = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let neighbours = others.filter { $0.day == previous || $0.day == next }

        if unavailable.contains(day) {
            result.blocked = true
            result.reasons.append("Jour indisponible")
        }
        if category.isCardio, sameDay.contains(where: { $0.category.isCardio }) {
            result.blocked = true
            result.reasons.append("Déjà une séance de vélo ce jour-là")
        }
        if category == .strength, sameDay.contains(where: { $0.category == .strength }) {
            result.blocked = true
            result.reasons.append("Déjà une séance de muscu ce jour-là")
        }
        if sameDay.count >= 2 {
            result.blocked = true
            result.reasons.append("Déjà deux séances ce jour-là")
        }
        if category.isHard, neighbours.contains(where: { $0.category.isHard }) {
            result.penalty += 4
            result.hardConflict = true
            result.reasons.append("Deux séances dures d'affilée")
        }
        if category.isHard, others.contains(where: { $0.isLegs && $0.day == previous }) {
            result.penalty += 2
            result.hardConflict = true
            result.reasons.append("Jambes encore fatiguées par la muscu de la veille")
        }
        if category.isHard, sameDay.contains(where: { $0.isLegs }) {
            result.penalty += 3
            result.reasons.append("Muscu des jambes le même jour")
        }
        if let availableMinutes, minutes > 0, availableMinutes < minutes {
            result.penalty += availableMinutes * 2 < minutes ? 4 : 2
            result.reasons.append("\(availableMinutes) min disponibles ce jour-là")
        }
        return result
    }

    /// Avertissements si tu places une séance à ce jour (affichés dans le menu « Déplacer »).
    static func warnings(for item: WeekPlan.Item, on day: Date, in plan: WeekPlan,
                         availableMinutes: Int?, calendar: Calendar = .current) -> [String] {
        var occupants: [Occupant] = []
        for other in plan.items where other.id != item.id {
            guard let otherDay = other.day, other.isDone || other.isPending else { continue }
            let category = other.doneSession.map { self.category(of: $0, matched: other.category) } ?? other.category
            occupants.append(Occupant(id: other.id, day: otherDay, category: category,
                                      isLegs: other.doneSession?.isLegs ?? false))
        }
        for session in plan.extras {
            occupants.append(Occupant(id: session.id, day: calendar.startOfDay(for: session.date),
                                      category: category(of: session, matched: nil), isLegs: session.isLegs))
        }
        return assess(category: item.category, kind: item.session.kind, minutes: item.session.minutes, day: day,
                      ignoring: item.id, occupants: occupants, unavailable: plan.unavailableDays,
                      availableMinutes: availableMinutes, calendar: calendar).reasons
    }
}
