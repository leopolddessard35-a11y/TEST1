import SwiftUI
import SwiftData
import Charts

/// Calendrier des échéances avec la condition prévue à chaque date.
struct GoalsCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Goal.date) private var goals: [Goal]
    let plan: SeasonPlan
    @State private var editing: Goal?
    @State private var adding = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Échéances", symbol: "flag.checkered")
                    Spacer()
                    Button { adding = true } label: { Image(systemName: "plus") }.buttonStyle(.glass)
                }
                if goals.isEmpty {
                    Text("Ajoute tes objectifs (100 km, semi, 200 km, 30 km…). L'objectif A pilote le plan, les B et C servent de jalons.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(goals.filter { $0.date >= Calendar.current.startOfDay(for: .now) }) { goal in
                    Button { editing = goal } label: { row(goal) }.buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $adding) { GoalForm(goal: nil) }
        .sheet(item: $editing) { goal in GoalForm(goal: goal) }
    }

    private func row(_ goal: Goal) -> some View {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                   to: Calendar.current.startOfDay(for: goal.date)).day ?? 0
        let week = plan.weeks.last { $0.start <= goal.date }
        return HStack(alignment: .top, spacing: 10) {
            Text(goal.priority.rawValue)
                .font(.caption.weight(.bold))
                .frame(width: 26, height: 26)
                .background((goal.priority == .a ? Theme.strain : (goal.priority == .b ? Theme.sleep : Theme.recovery)).opacity(0.3), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(goal.name).font(.subheadline.weight(.semibold))
                Text("\(goal.date.formatted(date: .abbreviated, time: .omitted)) · \(goal.distanceKm.noDecimal) km · \(goal.sport.label)")
                    .font(.caption).foregroundStyle(.secondary)
                if let week {
                    Text(String(format: "Condition prévue ≈ %.0f · phase %@", week.projectedCTL, week.phase.label))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("J-\(max(days, 0))").font(.subheadline.weight(.bold).monospacedDigit())
        }
    }
}

struct GoalForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    let goal: Goal?
    @State private var name = ""
    @State private var date = Date.now
    @State private var sportRaw = Sport.cycling.rawValue
    @State private var distance = 100.0
    @State private var priorityRaw = GoalPriority.b.rawValue
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex. Semi de Paris)", text: $name)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Sport", selection: $sportRaw) {
                    ForEach([Sport.cycling, .running, .other]) { Text($0.label).tag($0.rawValue) }
                }
                HStack {
                    Text("Distance (km)")
                    Spacer()
                    TextField("km", value: $distance, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 80)
                }
                Picker("Priorité", selection: $priorityRaw) {
                    ForEach(GoalPriority.allCases) { Text($0.label).tag($0.rawValue) }
                }
                TextField("Note", text: $note)
                if let goal {
                    Button("Supprimer", role: .destructive) {
                        context.delete(goal)
                        try? context.save()
                        app.dataVersion += 1
                        dismiss()
                    }
                }
            }
            .navigationTitle(goal == nil ? "Nouvelle échéance" : "Échéance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.disabled(name.isEmpty)
                }
            }
            .onAppear {
                guard let goal else { return }
                name = goal.name
                date = goal.date
                sportRaw = goal.sportRaw
                distance = goal.distanceKm
                priorityRaw = goal.priorityRaw
                note = goal.note
            }
        }
    }

    private func save() {
        let target = goal ?? Goal(name: name, date: date, sport: .cycling, distanceKm: distance, priority: .b)
        if goal == nil { context.insert(target) }
        target.name = name
        target.date = date
        target.sportRaw = sportRaw
        target.distanceKm = distance
        target.priorityRaw = priorityRaw
        target.note = note
        // L'objectif A le plus proche devient la course qui pilote le plan.
        if priorityRaw == GoalPriority.a.rawValue, let profile = try? context.fetch(FetchDescriptor<AthleteProfile>()).first {
            profile.raceName = name
            profile.raceDate = date
        }
        try? context.save()
        app.dataVersion += 1
        dismiss()
    }
}

/// Semaine en cours : prévu vs réalisé, séances manquées visibles.
struct WeekStatusCard: View {
    let days: [DayStatus]

    var body: some View {
        let missed = days.filter { $0.status == .missed }.count
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Prévu vs réalisé · cette semaine", symbol: "checklist")
                    Spacer()
                    if missed > 0 {
                        Text("\(missed) manquée\(missed > 1 ? "s" : "")").font(.caption.weight(.semibold)).foregroundStyle(Theme.warning)
                    }
                }
                HStack(spacing: 6) {
                    ForEach(days) { day in
                        VStack(spacing: 4) {
                            Text(day.date.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold))
                            Image(systemName: day.status.symbol)
                                .font(.title3)
                                .foregroundStyle(Self.color(day.status))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                HStack {
                    Spacer()
                    Text("Détail de la semaine").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    DetailChevron()
                }
            }
        }
    }

    static func color(_ status: DayStatus.Status) -> Color {
        switch status {
        case .done: Theme.recovery
        case .partial: Theme.nutrition
        case .missed: Theme.warning
        case .rest: Theme.sleep
        case .upcoming, .today: .secondary
        }
    }
}

/// Condition prévue (mémorisée à la création du plan) vs condition réelle.
struct FormCurveCard: View {
    let baselines: [PlanBaseline]
    let load: [LoadPoint]
    let plan: SeasonPlan

    var body: some View {
        let firstWeek: Date = baselines.map(\.weekStart).min() ?? Date.now
        let actual: [LoadPoint] = load.filter { $0.date >= firstWeek }
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Forme attendue vs réelle", symbol: "chart.xyaxis.line")
                Chart {
                    ForEach(baselines) { baseline in
                        LineMark(x: .value("Semaine", baseline.weekStart), y: .value("Condition", baseline.projectedCTL))
                            .foregroundStyle(by: .value("Courbe", "Prévue"))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
                    }
                    ForEach(plan.weeks) { week in
                        LineMark(x: .value("Semaine", week.start), y: .value("Condition", week.projectedCTL))
                            .foregroundStyle(by: .value("Courbe", "Projection actuelle"))
                    }
                    ForEach(actual) { point in
                        LineMark(x: .value("Semaine", point.date), y: .value("Condition", point.ctl))
                            .foregroundStyle(by: .value("Courbe", "Réelle"))
                            .lineStyle(StrokeStyle(lineWidth: 3))
                    }
                }
                .chartForegroundStyleScale(["Prévue": Color.secondary, "Projection actuelle": Theme.sleep, "Réelle": Theme.recovery])
                .frame(height: 200)
                Text("« Prévue » : la projection faite la première fois que chaque semaine est apparue. L'écart avec « Réelle » montre ton avance ou ton retard sur le plan.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct MilestonesCard: View {
    let milestones: [Milestone]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Jalons", symbol: "mappin.and.ellipse")
                ForEach(milestones) { milestone in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: milestone.date < .now ? "checkmark.circle" : "circle")
                            .foregroundStyle(milestone.date < .now ? Theme.recovery : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(milestone.title) · \(milestone.date.formatted(.dateTime.day().month(.abbreviated)))").font(.subheadline.weight(.semibold))
                            Text(milestone.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
