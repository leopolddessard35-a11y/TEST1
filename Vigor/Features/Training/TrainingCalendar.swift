import SwiftUI
import SwiftData

// MARK: - Modèle

/// Un jour du calendrier d'entraînement.
struct CalendarDay: Identifiable, Equatable {
    enum State: Equatable {
        /// Séance faite.
        case done
        /// Grosse séance (≥ 2 h 30 ou charge ≥ 150).
        case hard
        /// Séance placée à venir (organisateur de la semaine ou Intervals.icu).
        case planned
        /// Indisponible (maladie, voyage…).
        case unavailable(UnavailabilityReason)
        /// Jour passé sans séance.
        case rest
        /// Jour à venir sans rien de prévu.
        case open
    }

    struct Session: Equatable, Identifiable {
        /// Identifiant de la séance source (unique, même pour deux séances de même titre et durée).
        let id: String
        let title: String
        let symbol: String
        let minutes: Int
    }

    var id: Date { date }
    let date: Date
    let state: State
    let sessions: [Session]
    let planned: [String]

    var isToday: Bool { Calendar.current.isDateInToday(date) }
}

enum TrainingCalendar {
    /// Seuil de séances pour qu'une semaine compte dans la série.
    static let weeklyTarget = 3

    /// Grille du mois (cases vides en tête pour aligner sur le premier jour de la semaine).
    static func month(containing reference: Date,
                      activities: [CardioActivity],
                      workouts: [StrengthWorkout],
                      unavailabilities: [Unavailability],
                      planned: [PlannedWorkout],
                      plans: [WeekPlan],
                      calendar: Calendar = .current) -> [CalendarDay?] {
        guard let interval = calendar.dateInterval(of: .month, for: reference) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let built = days(in: interval, activities: activities, workouts: workouts, unavailabilities: unavailabilities,
                         planned: planned, plans: plans, calendar: calendar)
        return Array(repeating: nil, count: leading) + built.map { Optional($0) }
    }

    /// Les 7 jours de la semaine en cours (même à cheval sur deux mois).
    static func week(containing reference: Date,
                     activities: [CardioActivity],
                     workouts: [StrengthWorkout],
                     unavailabilities: [Unavailability],
                     planned: [PlannedWorkout],
                     plans: [WeekPlan],
                     calendar: Calendar = .current) -> [CalendarDay] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: reference) else { return [] }
        return days(in: interval, activities: activities, workouts: workouts, unavailabilities: unavailabilities,
                    planned: planned, plans: plans, calendar: calendar)
    }

    static func days(in interval: DateInterval,
                     activities: [CardioActivity],
                     workouts: [StrengthWorkout],
                     unavailabilities: [Unavailability],
                     planned: [PlannedWorkout],
                     plans: [WeekPlan],
                     calendar: Calendar = .current) -> [CalendarDay] {
        let today = calendar.startOfDay(for: .now)
        let sessionsByDay = self.sessionsByDay(activities: activities, workouts: workouts, calendar: calendar)
        // Semaines organisées : seules les séances encore à faire apparaissent (jamais de « manqué »).
        var plannedByDay: [Date: [String]] = [:]
        var organizedDays = Set<Date>()
        for plan in plans {
            organizedDays.formUnion(plan.days)
            for item in plan.items where item.isPending {
                if let day = item.day { plannedByDay[day, default: []].append(item.session.title) }
            }
        }
        for item in planned where !organizedDays.contains(calendar.startOfDay(for: item.date)) {
            plannedByDay[calendar.startOfDay(for: item.date), default: []].append(item.name)
        }

        var days: [CalendarDay] = []
        var day = interval.start
        while day < interval.end {
            let sessions = sessionsByDay[day] ?? []
            let plannedNames: [String] = day >= today ? (plannedByDay[day] ?? []) : []
            let unavailable = unavailabilities.first { calendar.startOfDay(for: $0.start) <= day && day <= calendar.startOfDay(for: $0.end) }

            let state: CalendarDay.State
            if !sessions.isEmpty {
                let hard = sessions.contains { $0.minutes >= 150 } || hardByLoad(day, activities: activities, calendar: calendar)
                state = hard ? .hard : .done
            } else if let unavailable {
                state = .unavailable(unavailable.reason)
            } else if !plannedNames.isEmpty {
                state = .planned
            } else {
                state = day < today ? .rest : .open
            }
            days.append(CalendarDay(date: day, state: state, sessions: sessions, planned: plannedNames))
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? interval.end
        }
        return days
    }

    static func sessionsByDay(activities: [CardioActivity], workouts: [StrengthWorkout],
                              calendar: Calendar = .current) -> [Date: [CalendarDay.Session]] {
        var result: [Date: [CalendarDay.Session]] = [:]
        for activity in activities {
            result[calendar.startOfDay(for: activity.start), default: []].append(
                CalendarDay.Session(id: "cardio-\(activity.externalID)", title: activity.title, symbol: activity.sport.symbol, minutes: Int(activity.durationSeconds / 60)))
        }
        for workout in workouts {
            result[calendar.startOfDay(for: workout.start), default: []].append(
                CalendarDay.Session(id: "muscu-\(workout.externalID)", title: workout.title, symbol: "dumbbell.fill", minutes: Int(workout.durationSeconds / 60)))
        }
        return result
    }

    private static func hardByLoad(_ day: Date, activities: [CardioActivity], calendar: Calendar) -> Bool {
        activities.contains { calendar.isDate($0.start, inSameDayAs: day) && ($0.providedTSS ?? 0) >= 150 }
    }

    /// Série actuelle et record : semaines consécutives avec au moins `weeklyTarget` séances.
    /// La semaine en cours compte dès que l'objectif est atteint (sinon elle ne casse pas la série).
    /// Une semaine avec un jour d'indisponibilité (maladie, voyage…) est neutre si l'objectif n'est pas atteint :
    /// elle ne casse pas la série et ne l'allonge pas.
    static func weeklyStreak(activities: [CardioActivity], workouts: [StrengthWorkout],
                             unavailabilities: [Unavailability] = [],
                             calendar: Calendar = .current) -> (current: Int, best: Int) {
        var counts: [Date: Int] = [:]
        let starts: [Date] = activities.map(\.start) + workouts.map(\.start)
        for start in starts {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: start)?.start else { continue }
            counts[week, default: 0] += 1
        }
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: .now)?.start,
              let oldest = counts.keys.min() else { return (0, 0) }

        var current = 0
        var best = 0
        var running = 0
        var week = oldest
        while week <= thisWeek {
            let reached = (counts[week] ?? 0) >= weeklyTarget
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: week) ?? week.addingTimeInterval(7 * 86_400)
            let unavailable = unavailabilities.contains { item in
                let start = calendar.startOfDay(for: item.start)
                let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: item.end)) ?? item.end
                return start < weekEnd && end > week
            }
            if reached {
                running += 1
            } else if week != thisWeek && !unavailable {
                running = 0
            }
            best = max(best, running)
            week = calendar.date(byAdding: .weekOfYear, value: 1, to: week) ?? thisWeek.addingTimeInterval(1)
        }
        current = running
        return (current, best)
    }
}

// MARK: - Vue

/// Grand calendrier du mois : séances faites, séances placées à venir, indisponibilités, série en cours.
struct TrainingCalendarCard: View {
    let snapshot: CoachSnapshot
    @Query(sort: \CardioActivity.start, order: .reverse) private var activities: [CardioActivity]
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    @Query(sort: \Unavailability.start, order: .reverse) private var unavailabilities: [Unavailability]
    @Query(sort: \PlannedWorkout.date) private var planned: [PlannedWorkout]
    @State private var month = Date.now
    @State private var selected: CalendarDay?
    /// Replié = la semaine (pour que la musculation reste visible) ; déplié = le mois en grand.
    @State private var expanded = false

    private var calendar: Calendar { .current }
    private var plans: [WeekPlan] { [snapshot.weekPlan, snapshot.nextWeekPlan].compactMap { $0 } }

    var body: some View {
        let days = TrainingCalendar.month(containing: month, activities: activities, workouts: workouts,
                                          unavailabilities: unavailabilities, planned: planned, plans: plans)
        let streak = TrainingCalendar.weeklyStreak(activities: activities, workouts: workouts, unavailabilities: unavailabilities)
        let monthDays = days.compactMap { $0 }
        let sessionCount = monthDays.reduce(0) { $0 + $1.sessions.count }
        let minutes = monthDays.reduce(0) { total, day in total + day.sessions.reduce(0) { $0 + $1.minutes } }

        GlassCard {
            VStack(spacing: 12) {
                // Série façon « streak » : semaines tenues, record, volume du mois.
                HStack(spacing: 0) {
                    stat(value: "\(streak.current)", unit: streak.current > 1 ? "semaines" : "semaine", title: "Série",
                         symbol: streak.current > 0 ? "flame.fill" : nil)
                    Divider().frame(height: 44)
                    stat(value: "\(streak.best)", unit: streak.best > 1 ? "semaines" : "semaine", title: "Record", symbol: "laurel.leading")
                    Divider().frame(height: 44)
                    stat(value: "\(sessionCount)", unit: sessionCount > 1 ? "séances" : "séance", title: "Ce mois", symbol: nil,
                         caption: (Double(minutes) / 60).hoursText)
                }
                // Respiration entre les chiffres et le calendrier.
                Divider().padding(.vertical, 6)
                if expanded {
                    Text("Une semaine compte dans la série à partir de \(TrainingCalendar.weeklyTarget) séances.")
                        .font(.caption2).foregroundStyle(.secondary)

                    HStack {
                        Image(systemName: "calendar").foregroundStyle(Theme.accent)
                        Text(month.formatted(.dateTime.month(.wide).year()).capitalized)
                            .font(.title3.weight(.bold))
                        Spacer()
                        Button { shift(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                            .accessibilityLabel("Mois précédent")
                        Button { shift(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                            .accessibilityLabel("Mois suivant")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                }

                // Jours de la semaine dans une pilule, puis la grille.
                HStack(spacing: 0) {
                    ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                        Text(symbol).font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                .padding(.vertical, 8)
                .background(Theme.well.opacity(0.7), in: .capsule)

                if expanded {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 10) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                            if let day {
                                Button { selected = day } label: { CalendarDayCell(day: day) }
                                    .buttonStyle(.plain)
                            } else {
                                Color.clear.frame(height: 44)
                            }
                        }
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 30).onEnded { value in
                        // Balayage nettement horizontal seulement : un défilement vertical ne change pas de mois.
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard abs(dx) > 2 * abs(dy) else { return }
                        if dx < -60 { shift(1) }
                        if dx > 60 { shift(-1) }
                    })
                    legend
                } else {
                    // Semaine du lundi au dimanche, comme l'organisateur, quel que soit le réglage de région.
                    let week = TrainingCalendar.week(containing: .now, activities: activities, workouts: workouts,
                                                     unavailabilities: unavailabilities, planned: planned,
                                                     plans: plans, calendar: SeasonPlanner.isoCalendar)
                    HStack(spacing: 4) {
                        ForEach(week) { day in
                            Button { selected = day } label: { CalendarDayCell(day: day) }
                                .buttonStyle(.plain)
                        }
                    }
                }

                Button {
                    withAnimation(.snappy) {
                        expanded.toggle()
                        if !expanded { month = .now }
                    }
                } label: {
                    Label(expanded ? "Réduire à la semaine" : "Voir le mois", systemImage: expanded ? "chevron.up" : "calendar")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)

                if let plan = snapshot.weekPlan {
                    NavigationLink { WeekPlannerView() } label: {
                        LinkRow(symbol: "calendar.badge.clock", title: "Organiser ma semaine",
                                subtitle: WeekPlannerView.summary(plan))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $selected) { day in
            CalendarDayDetail(day: day).presentationDetents([.medium])
        }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    private func shift(_ value: Int) {
        withAnimation(.snappy) {
            month = calendar.date(byAdding: .month, value: value, to: month) ?? month
        }
    }

    private func stat(value: String, unit: String, title: String, symbol: String?, caption: String? = nil) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.subheadline).foregroundStyle(Theme.caution) }
                Text(value).font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit()
            }
            Text(unit).font(.caption2).foregroundStyle(.secondary)
            if let caption {
                Text(caption).font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 6) {
            legendItem(Circle().fill(Theme.good), "Fait")
            legendItem(Circle().fill(Theme.accent), "Grosse séance")
            legendItem(Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])), "Prévu")
            legendItem(Circle().fill(Theme.well).overlay(Circle().strokeBorder(Color.secondary.opacity(0.6), lineWidth: 1)), "Indisponible")
            legendItem(Circle().fill(Theme.well.opacity(0.7)), "Repos")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem<S: View>(_ shape: S, _ label: String) -> some View {
        HStack(spacing: 4) {
            shape.frame(width: 10, height: 10)
            Text(label)
        }
    }
}

/// Une case du calendrier : rond plein (fait), pointillé (prévu), gris (repos).
struct CalendarDayCell: View {
    let day: CalendarDay
    /// Suit la taille de texte choisie dans Réglages iOS.
    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 38

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                background
                content
            }
            .frame(width: size, height: size)
            .overlay {
                if day.isToday {
                    Circle().stroke(Color.primary, lineWidth: 2).padding(-3)
                }
            }
            HStack(spacing: 2) {
                ForEach(0..<min(day.sessions.count, 3), id: \.self) { _ in
                    Circle().fill(Theme.good).frame(width: 4, height: 4)
                }
            }
            .frame(height: 4)
            .opacity(day.sessions.count > 1 ? 1 : 0)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var number: String { day.date.formatted(.dateTime.day()) }

    @ViewBuilder
    private var background: some View {
        switch day.state {
        case .done: Circle().fill(Theme.good)
        case .hard: Circle().fill(Theme.accent.gradient)
        case .planned: Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        case .unavailable: Circle().fill(Theme.well)
        case .rest: Circle().fill(Theme.well.opacity(0.7))
        case .open: Color.clear
        }
    }

    @ViewBuilder
    private var content: some View {
        switch day.state {
        case .done:
            Text(number).font(.subheadline.weight(.bold)).foregroundStyle(.white)
        case .hard:
            ZStack(alignment: .topTrailing) {
                Text(number).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                    .frame(width: size, height: size)
                Image(systemName: "flame.fill").font(.system(size: 10)).foregroundStyle(Theme.caution)
                    .padding(3)
                    .background(Theme.card, in: .circle)
                    .offset(x: 4, y: -4)
            }
        case .unavailable(let reason):
            Image(systemName: reason.symbol).font(.caption).foregroundStyle(.secondary)
        case .planned:
            Text(number).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
        case .rest:
            Text(number).font(.subheadline).foregroundStyle(.secondary)
        case .open:
            Text(number).font(.subheadline).foregroundStyle(.tertiary)
        }
    }

    private var accessibilityText: String {
        let date = day.date.formatted(date: .complete, time: .omitted)
        switch day.state {
        case .done, .hard: return "\(date), \(day.sessions.count) séance(s) faite(s)"
        case .planned: return "\(date), séance prévue"
        case .unavailable(let reason): return "\(date), indisponible : \(reason.label)"
        case .rest: return "\(date), repos"
        case .open: return date
        }
    }
}

/// Détail d'un jour touché dans le calendrier.
private struct CalendarDayDetail: View {
    let day: CalendarDay

    var body: some View {
        NavigationStack {
            List {
                if !day.sessions.isEmpty {
                    Section("Fait") {
                        ForEach(day.sessions) { session in
                            Label {
                                HStack {
                                    Text(session.title)
                                    Spacer()
                                    Text((Double(session.minutes) / 60).hoursText).foregroundStyle(.secondary).monospacedDigit()
                                }
                            } icon: {
                                Image(systemName: session.symbol).foregroundStyle(Theme.good)
                            }
                        }
                    }
                }
                if !day.planned.isEmpty {
                    Section {
                        ForEach(day.planned, id: \.self) { Text($0) }
                    } header: {
                        Text("Prévu")
                    } footer: {
                        Text("Pour changer de jour : Sport → Organiser ma semaine.")
                    }
                }
                if case .unavailable(let reason) = day.state {
                    Section { Label(reason.label, systemImage: reason.symbol) }
                }
                if day.sessions.isEmpty && day.planned.isEmpty {
                    Text(day.date < Calendar.current.startOfDay(for: .now) ? "Repos." : "Rien de prévu.")
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground())
            .navigationTitle(day.date.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
