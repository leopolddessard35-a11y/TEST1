import SwiftUI
import SwiftData

/// Organiser ma semaine : les séances viennent du plan de saison, les jours viennent de toi.
/// Déplacer, retirer ou laisser Vigor choisir ; ce que tu fais est reconnu par type, quel que soit le jour.
struct WeekPlannerView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var showNextWeek = false

    var body: some View {
        ScrollView {
            SnapshotReader { profile, snapshot in
                VStack(spacing: 12) {
                    if snapshot.nextWeekPlan != nil {
                        Picker("Semaine", selection: $showNextWeek) {
                            Text("Cette semaine").tag(false)
                            Text("Semaine prochaine").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    let showingNext = showNextWeek && snapshot.nextWeekPlan != nil
                    if let plan = showingNext ? snapshot.nextWeekPlan : snapshot.weekPlan {
                        header(plan)
                        if showingNext {
                            Label("Provisoire : la semaine prochaine se fixe lundi, d'après ta forme du moment. Tes choix de jours sont gardés.",
                                  systemImage: "info.circle")
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        daysCard(plan, profile: profile)
                        let dropped = plan.items.filter { $0.state == .dropped }
                        if !dropped.isEmpty { droppedCard(dropped, plan: plan, profile: profile) }
                        ExplanationCard(title: "Comment ça marche", symbol: "wand.and.stars", text: """
                        • Les séances de la semaine viennent du plan de saison ; les jours, c'est toi qui décides. Touche ••• pour déplacer une séance ou la retirer.
                        • Ce que tu fais compte quel que soit le jour : un seuil prévu mardi et fait mercredi est validé. Une sortie facile un jour de seuil compte comme séance faite, mais en endurance.
                        • Une séance que tu n'as pas placée est mise au meilleur jour : celui où tu la fais d'habitude (appris sur 8 semaines), sinon le jour du plan type. Vigor évite deux séances dures d'affilée, l'intensité au lendemain des jambes, les jours indisponibles ou trop courts.
                        • Un jour passé sans séance ? La séance est replacée plus tard dans la semaine s'il reste de la place. Sinon elle est abandonnée : on ne rattrape jamais, et le plan de la saison s'ajuste à ce que tu as vraiment fait.
                        """)
                    } else {
                        EmptyStateCard(title: "Pas de plan cette semaine",
                                       message: "Renseigne ton objectif et sa date dans Réglages : Vigor en déduit les séances de chaque semaine, que tu places ensuite où tu veux.",
                                       symbol: "calendar.badge.clock")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .task(id: snapshot.plan.currentWeek.map { FrozenWeek.dayKey($0.start) }) {
                    if WeekFreezer.update(plan: snapshot.plan, context: context) { app.dataVersion += 1 }
                }
            }
        }
        .background(AppBackground())
        .navigationTitle("Ma semaine")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Résumé d'une ligne (lien depuis le calendrier).
    static func summary(_ plan: WeekPlan) -> String {
        let total = plan.items.filter { !$0.isRemoved }.count
        var text = "\(plan.doneCount)/\(total) séances faites"
        if let next = plan.items.first(where: { $0.isPending && ($0.day ?? .distantPast) >= plan.today }), let day = next.day {
            let when = Calendar.current.isDate(day, inSameDayAs: plan.today) ? "aujourd'hui" : day.formatted(.dateTime.weekday(.wide))
            text += " · ensuite : \(shortLabel(next.session.kind)) \(when)"
        }
        return text
    }

    /// « Push (pecs, épaules, triceps) » → « Push ».
    static func shortLabel(_ kind: SessionKind) -> String {
        let label = kind.label
        return label.range(of: " (").map { String(label[..<$0.lowerBound]) } ?? label
    }

    // MARK: En-tête

    private func header(_ plan: WeekPlan) -> some View {
        let total = plan.items.filter { !$0.isRemoved }.count
        return GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                CapsLabel("Semaine du \(plan.week.start.formatted(.dateTime.day().month(.wide)))")
                Text("\(plan.week.phase.label) · \(plan.week.kind.label.lowercased())")
                    .font(.title3.weight(.bold))
                HStack(spacing: 8) {
                    StatusPill(text: "\(plan.doneCount)/\(total) faites", symbol: "checkmark.circle.fill", color: Theme.good)
                    if plan.pendingCount > 0 {
                        StatusPill(text: "\(plan.pendingCount) à venir", symbol: "calendar", color: Theme.accent)
                    }
                }
                if plan.droppedCount > 0 {
                    Text("\(plan.droppedCount) séance\(plan.droppedCount > 1 ? "s n'ont" : " n'a") plus de place d'ici dimanche : pas grave, on ne rattrape pas.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if plan.habitsLearned {
                    Label("Jours proposés d'après tes habitudes des 8 dernières semaines", systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Jours

    private func daysCard(_ plan: WeekPlan, profile: AthleteProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(plan.days.enumerated()), id: \.offset) { index, day in
                    if index > 0 { Divider().padding(.vertical, 8) }
                    dayRow(day, plan: plan, profile: profile)
                }
            }
            // Une séance déplacée glisse vers son nouveau jour.
            .animation(.snappy, value: plan)
        }
        .sensoryFeedback(.selection, trigger: plan.items.map(\.day))
    }

    private func dayRow(_ day: Date, plan: WeekPlan, profile: AthleteProfile) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDate(day, inSameDayAs: plan.today)
        let isPast = day < plan.today
        let items = plan.items(on: day)
        let extras = plan.extras(on: day)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(day.formatted(.dateTime.weekday(.wide).day()).capitalized)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isPast ? Color.secondary : Color.primary)
                if isToday { StatusPill(text: "Aujourd'hui", symbol: "smallcircle.filled.circle", color: Theme.accent) }
                Spacer()
                if plan.unavailableDays.contains(day) {
                    Label("Indisponible", systemImage: "calendar.badge.exclamationmark")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if items.isEmpty && extras.isEmpty {
                Text(isPast ? "Repos" : "Libre").font(.footnote).foregroundStyle(.tertiary)
            }
            ForEach(items) { item in
                itemRow(item, plan: plan, profile: profile)
            }
            ForEach(extras) { session in
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title).font(.subheadline.weight(.semibold))
                        Text("\(plan.excluded.contains(session.id) ? "Exclue du plan" : "En plus du plan") · \((Double(session.minutes) / 60).hoursText)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if plan.excluded.contains(session.id) {
                        Button("Recompter") { setExcluded(session, false, plan: plan) }
                            .font(.caption.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
            }
        }
    }

    private func itemRow(_ item: WeekPlan.Item, plan: WeekPlan, profile: AthleteProfile) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.isDone ? "checkmark.circle.fill" : item.session.kind.symbol)
                .foregroundStyle(item.isDone ? Theme.good : Theme.accent)
                .frame(width: 28, height: 28)
                .background(item.isDone ? Color.clear : Theme.well, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.session.title).font(.subheadline.weight(.semibold))
                if let done = item.doneSession {
                    Text(item.isSubstitute ? "Fait en endurance : \(done.title)" : "Fait : \(done.title)")
                        .font(.caption).foregroundStyle(.secondary)
                } else if !item.session.detail.isEmpty {
                    Text(item.session.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                if item.isPending && (item.isPinned || item.wasRescheduled) {
                    HStack(spacing: 6) {
                        if item.isPinned { tag("Jour choisi", symbol: "hand.point.up.left.fill") }
                        if item.wasRescheduled { tag("Replacée", symbol: "arrow.uturn.forward") }
                    }
                }
            }
            Spacer(minLength: 4)
            if let done = item.doneSession {
                Menu {
                    Button { setExcluded(done, true, plan: plan) } label: {
                        Label("Ne compte pas pour cette séance", systemImage: "xmark.circle")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(.rect)
                }
                .accessibilityLabel("Options de \(done.title)")
            } else if item.category != .race {
                moveMenu(item, plan: plan, profile: profile)
            }
        }
    }

    private func tag(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.well, in: .capsule)
    }

    // MARK: Séances sans place

    private func droppedCard(_ items: [WeekPlan.Item], plan: WeekPlan, profile: AthleteProfile) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Pas casées cette semaine", symbol: "tray")
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.session.kind.symbol).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.session.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                            Text(item.isRemoved ? "Retirée par toi" : "Plus de jour possible d'ici dimanche")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 4)
                        moveMenu(item, plan: plan, profile: profile)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Menu « Déplacer »

    private func moveMenu(_ item: WeekPlan.Item, plan: WeekPlan, profile: AthleteProfile) -> some View {
        Menu {
            Section(item.state == .dropped ? "Placer à" : "Déplacer à") {
                ForEach(plan.remainingDays.filter { $0 != item.day }, id: \.self) { day in
                    let warnings = WeekPlanner.warnings(for: item, on: day, in: plan,
                                                        availableMinutes: profile.availableMinutes(weekday: Calendar.current.component(.weekday, from: day)))
                    Button {
                        place(item, on: day, plan: plan)
                    } label: {
                        if let warning = warnings.first {
                            Label("\(dayLabel(day, plan: plan)) · \(warning)", systemImage: "exclamationmark.triangle")
                        } else {
                            Label(dayLabel(day, plan: plan), systemImage: "calendar")
                        }
                    }
                }
            }
            if item.isPending {
                Button(role: .destructive) { place(item, on: nil, plan: plan) } label: {
                    Label("Pas cette semaine", systemImage: "minus.circle")
                }
            }
            if item.isPinned {
                Button { reset(item, plan: plan) } label: {
                    Label("Laisser Vigor choisir", systemImage: "wand.and.stars")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .accessibilityLabel("Déplacer \(item.session.kind.label)")
    }

    private func dayLabel(_ day: Date, plan: WeekPlan) -> String {
        Calendar.current.isDate(day, inSameDayAs: plan.today) ? "Aujourd'hui" : day.formatted(.dateTime.weekday(.wide).day()).capitalized
    }

    // MARK: Enregistrement

    private func existing(_ item: WeekPlan.Item, plan: WeekPlan) -> SessionPlacement? {
        let key = SessionPlacement.key(weekStart: Calendar.current.startOfDay(for: plan.week.start), slot: item.id)
        let descriptor = FetchDescriptor<SessionPlacement>(predicate: #Predicate { $0.key == key })
        return try? context.fetch(descriptor).first
    }

    /// `day == nil` : retirée de la semaine.
    private func place(_ item: WeekPlan.Item, on day: Date?, plan: WeekPlan) {
        if let placement = existing(item, plan: plan) {
            placement.day = day
        } else {
            context.insert(SessionPlacement(weekStart: Calendar.current.startOfDay(for: plan.week.start), slot: item.id, day: day))
        }
        save()
    }

    /// « Ne compte pas pour cette séance » (ex. une sortie vélotaf reconnue à tort).
    private func setExcluded(_ session: DoneSession, _ excluded: Bool, plan: WeekPlan) {
        let weekStart = Calendar.current.startOfDay(for: plan.week.start)
        let slot = WeekPlan.exclusionPrefix + session.id
        let key = SessionPlacement.key(weekStart: weekStart, slot: slot)
        let descriptor = FetchDescriptor<SessionPlacement>(predicate: #Predicate { $0.key == key })
        let existing = try? context.fetch(descriptor).first
        if excluded {
            if existing == nil { context.insert(SessionPlacement(weekStart: weekStart, slot: slot, day: nil)) }
        } else if let existing {
            context.delete(existing)
        }
        save()
    }

    private func reset(_ item: WeekPlan.Item, plan: WeekPlan) {
        if let placement = existing(item, plan: plan) { context.delete(placement) }
        save()
    }

    private func save() {
        try? context.save()
        app.dataVersion += 1
        Feedback.tick()
    }
}

/// Fige la semaine en cours le jour où elle commence (ses séances ne bougent plus ensuite)
/// et oublie les choix de jours de plus de 4 semaines.
@MainActor
enum WeekFreezer {
    /// Vrai si quelque chose a été enregistré.
    @discardableResult
    static func update(plan: SeasonPlan, context: ModelContext) -> Bool {
        guard let week = plan.currentWeek else { return false }
        var changed = migrateLegacyPlacements(plan: plan, context: context)
        let key = FrozenWeek.dayKey(week.start)
        let descriptor = FetchDescriptor<FrozenWeek>(predicate: #Predicate { $0.key == key })
        if ((try? context.fetchCount(descriptor)) ?? 0) == 0 {
            context.insert(FrozenWeek(week: week))
            changed = true
        }
        let limit = Calendar.current.date(byAdding: .day, value: -28, to: Calendar.current.startOfDay(for: week.start)) ?? week.start
        let old = FetchDescriptor<SessionPlacement>(predicate: #Predicate { $0.weekStart < limit })
        for placement in (try? context.fetch(old)) ?? [] {
            context.delete(placement)
            changed = true
        }
        if changed { try? context.save() }
        return changed
    }

    /// Choix de jours enregistrés avant la mise à jour (clé horodatée, séance repérée par famille « intense-0 ») :
    /// convertis vers le nouveau format (clé par date, séance repérée par type « threshold-0 ») pour ne pas les perdre.
    static func migrateLegacyPlacements(plan: SeasonPlan, context: ModelContext, calendar: Calendar = .current) -> Bool {
        let all = (try? context.fetch(FetchDescriptor<SessionPlacement>())) ?? []
        let legacy = all.filter { placement in
            placement.key.split(separator: "|").first.map { $0.allSatisfy(\.isNumber) } ?? false
        }
        guard !legacy.isEmpty else { return false }
        var existingKeys = Set(all.map(\.key))
        for placement in legacy {
            let weekStart = calendar.startOfDay(for: placement.weekStart)
            var slot = placement.slot
            if !slot.hasPrefix(WeekPlan.exclusionPrefix),
               let week = plan.weeks.first(where: { calendar.isDate($0.start, inSameDayAs: weekStart) }) {
                slot = legacySlotMap(for: week, calendar: calendar)[slot] ?? slot
            }
            let key = SessionPlacement.key(weekStart: weekStart, slot: slot, calendar: calendar)
            if existingKeys.contains(key) {
                // Un choix existe déjà au nouveau format : il l'emporte.
                context.delete(placement)
            } else {
                existingKeys.remove(placement.key)
                placement.slot = slot
                placement.key = key
                existingKeys.insert(key)
            }
        }
        try? context.save()
        return true
    }

    /// Ancien identifiant (famille + rang) → nouveau (type de séance + rang), dans l'ordre des jours de la semaine.
    private static func legacySlotMap(for week: PlannedWeek, calendar: Calendar) -> [String: String] {
        var map: [String: String] = [:]
        var byCategory: [SessionCategory: Int] = [:]
        var byKind: [SessionKind: Int] = [:]
        let start = calendar.startOfDay(for: week.start)
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { continue }
            for session in DailyCoach.template(for: week, weekday: calendar.component(.weekday, from: day), ftp: nil)
            where session.kind != .rest {
                let category = SessionCategory(session.kind)
                let oldIndex = byCategory[category, default: 0]
                byCategory[category] = oldIndex + 1
                let newIndex = byKind[session.kind, default: 0]
                byKind[session.kind] = newIndex + 1
                map["\(category.rawValue)-\(oldIndex)"] = "\(session.kind.rawValue)-\(newIndex)"
            }
        }
        return map
    }
}
