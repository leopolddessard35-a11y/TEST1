import SwiftUI
import SwiftData

struct PlanView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanBaseline.weekStart) private var baselines: [PlanBaseline]
    @Query(sort: \Unavailability.start, order: .reverse) private var unavailabilities: [Unavailability]
    @Query(sort: \Injury.start, order: .reverse) private var injuries: [Injury]
    @State private var showUnavailability = false
    @State private var showInjury = false
    @Environment(\.dismiss) private var dismiss
    /// Ouvert en feuille depuis l'onglet Activité : affiche un bouton OK.
    var presentedAsSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { profile, snapshot in
                    VStack(spacing: 16) {
                        PlanHeaderCard(plan: snapshot.plan, raceName: profile.raceName)

                        if let week = snapshot.plan.currentWeek, !snapshot.weekStatus.isEmpty {
                            NavigationLink { WeekDetailView(week: week) } label: { WeekStatusCard(days: snapshot.weekStatus) }
                                .buttonStyle(.plain)
                        }

                        HStack(spacing: 12) {
                            Button { showUnavailability = true } label: {
                                Label("Je ne peux pas", systemImage: "calendar.badge.minus").frame(maxWidth: .infinity)
                            }
                            Button { showInjury = true } label: {
                                Label("Blessure", systemImage: "bandage").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)

                        let activeInjuries = injuries.filter(\.isActive)
                        let upcoming = unavailabilities.filter { $0.end >= Calendar.current.startOfDay(for: .now) }
                        if !activeInjuries.isEmpty || !upcoming.isEmpty {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(activeInjuries) { injury in InjuryRow(injury: injury) }
                                    ForEach(upcoming) { item in UnavailabilityRow(item: item) }
                                }
                            }
                        }

                        GoalsCard(plan: snapshot.plan)

                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            NavigationLink {
                                DetailPage(title: "Forme attendue vs réelle") {
                                    FormCurveCard(baselines: baselines, load: snapshot.load, plan: snapshot.plan)
                                    if !snapshot.milestones.isEmpty { MilestonesCard(milestones: snapshot.milestones) }
                                }
                            } label: {
                                SimpleTile(title: "Forme", value: "prévu / réel", caption: "\(snapshot.milestones.count) jalons",
                                           symbol: "chart.xyaxis.line", tint: Theme.recovery)
                            }
                            NavigationLink {
                                DetailPage(title: "Toutes les semaines") {
                                    ForEach(snapshot.plan.weeks) { week in
                                        NavigationLink { WeekDetailView(week: week) } label: { WeekCard(week: week) }
                                            .buttonStyle(.plain)
                                    }
                                }
                            } label: {
                                SimpleTile(title: "Semaines", value: "\(snapshot.plan.weeks.count)", caption: "jusqu'à la course",
                                           symbol: "list.bullet.rectangle", tint: Theme.sleep)
                            }
                            if let report = snapshot.weeklyReport, let review = snapshot.weeklyReview {
                                NavigationLink {
                                    DetailPage(title: "Revue de la semaine") { WeeklyReviewCard(report: report, review: review) }
                                } label: {
                                    SimpleTile(title: "Revue", value: "7 derniers jours", caption: review.vigilance,
                                               symbol: "calendar.badge.checkmark", tint: Theme.nutrition)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .task(id: snapshot.plan.weeks.count) { saveBaselines(snapshot.plan) }
                }
            }
            .background(AppBackground())
            .navigationTitle("Plan")
            .toolbar {
                if presentedAsSheet {
                    ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } }
                }
            }
            .sheet(isPresented: $showUnavailability) { UnavailabilityForm() }
            .sheet(isPresented: $showInjury) { InjuryForm() }
        }
    }
}

extension PlanView {
    /// Mémorise la projection de chaque semaine la première fois qu'elle apparaît (courbe « prévue »).
    func saveBaselines(_ plan: SeasonPlan) {
        let known = Set(baselines.map(\.weekStart))
        var changed = false
        for week in plan.weeks where !known.contains(week.start) {
            context.insert(PlanBaseline(weekStart: week.start, projectedCTL: week.projectedCTL, targetHours: week.targetHours))
            changed = true
        }
        if changed { try? context.save() }
    }
}

private struct PlanHeaderCard: View {
    let plan: SeasonPlan
    let raceName: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if let week = plan.currentWeek {
                    Text("Phase actuelle : \(week.phase.label)").font(.title3.weight(.semibold))
                    Text(week.phase.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack {
                    VStack(alignment: .leading) {
                        Text("Condition actuelle").font(.caption).foregroundStyle(.secondary)
                        Text(plan.startCTL.noDecimal).font(.title2.weight(.bold))
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("Prévue avant \(raceName)").font(.caption).foregroundStyle(.secondary)
                        Text("\(plan.projectedPeakCTL.noDecimal) / \(plan.targetCTL.noDecimal)").font(.title2.weight(.bold))
                    }
                }
                ForEach(plan.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.nutrition)
                }
            }
        }
    }
}

private struct WeekCard: View {
    let week: PlannedWeek

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Sem. du \(week.start.formatted(.dateTime.day().month(.abbreviated)))").font(.headline)
                    Spacer()
                    Text(week.phase.label)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .glassEffect(.regular.tint(tint.opacity(0.5)), in: .capsule)
                }
                HStack(spacing: 14) {
                    Label(week.targetHours.hoursText, systemImage: "clock")
                    Label("TSS \(week.targetTSS.noDecimal)", systemImage: "flame")
                    if week.longRideHours > 0 {
                        Label(week.longRideHours.hoursText, systemImage: "road.lanes")
                    }
                }
                .font(.footnote)
                HStack(spacing: 14) {
                    Label("\(week.intensitySessions) intensité", systemImage: "bolt.fill")
                    Label("\(week.strengthSessions)× PPL", systemImage: "dumbbell.fill")
                    Label(week.runningAllowed ? "Course OK" : "Pas de course", systemImage: "figure.run")
                }
                .font(.footnote).foregroundStyle(.secondary)
                ForEach(week.notes, id: \.self) { note in
                    Text("• \(note)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var tint: Color {
        switch week.kind {
        case .recovery: Theme.sleep
        case .taper, .race: Theme.nutrition
        case .load: week.isReduced ? Theme.warning : Theme.recovery
        }
    }
}

private struct InjuryRow: View {
    @Environment(\.modelContext) private var context
    let injury: Injury

    var body: some View {
        HStack {
            Image(systemName: "bandage.fill").foregroundStyle(Theme.warning)
            VStack(alignment: .leading) {
                Text(injury.title).font(.subheadline.weight(.semibold))
                Text(injury.muscles.map(\.label).sorted().joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Guérie") {
                injury.resolvedAt = .now
                try? context.save()
            }
            .buttonStyle(.glass)
            .font(.caption)
        }
    }
}

private struct UnavailabilityRow: View {
    @Environment(\.modelContext) private var context
    let item: Unavailability

    var body: some View {
        HStack {
            Image(systemName: item.reason.symbol)
            VStack(alignment: .leading) {
                Text(item.reason.label).font(.subheadline.weight(.semibold))
                Text("\(item.start.formatted(date: .abbreviated, time: .omitted)) → \(item.end.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                context.delete(item)
                try? context.save()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.glass)
        }
    }
}

struct UnavailabilityForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var reason: UnavailabilityReason = .illness
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Pourquoi ?", selection: $reason) {
                    ForEach(UnavailabilityReason.allCases) { reason in
                        Label(reason.label, systemImage: reason.symbol).tag(reason)
                    }
                }
                DatePicker("Du", selection: $start, displayedComponents: .date)
                DatePicker("Au", selection: $end, in: start..., displayedComponents: .date)
                TextField("Note (facultatif)", text: $note, axis: .vertical)
                Section {
                    Text(explanation).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Indisponibilité")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        context.insert(Unavailability(start: start, end: max(start, end), reason: reason, note: note))
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }

    private var explanation: String {
        switch reason {
        case .illness: "Repos complet pendant la maladie, puis la semaine suivante est allégée automatiquement."
        case .injury: "Déclare aussi la blessure (bouton « Blessure ») pour adapter les exercices."
        case .travel: "La semaine est réduite, avec des idées de séances courtes sans matériel."
        case .vacation: "La charge est ajustée aux jours disponibles."
        case .fatigue: "La semaine devient une semaine de récupération."
        case .motivation: "Pas de culpabilité : les séances manquées ne sont pas rattrapées."
        case .other: "La charge est ajustée aux jours disponibles."
        }
    }
}

struct InjuryForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var muscles: Set<Muscle> = []
    @State private var affectsRunning = true
    @State private var affectsCycling = false
    @State private var severity = 2
    @State private var start = Date.now

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom (ex. ischio gauche)", text: $title)
                DatePicker("Depuis le", selection: $start, displayedComponents: .date)
                Picker("Gravité", selection: $severity) {
                    Text("Légère").tag(1)
                    Text("Modérée").tag(2)
                    Text("Sévère").tag(3)
                }
                Toggle("Empêche la course à pied", isOn: $affectsRunning)
                Toggle("Gêne à vélo", isOn: $affectsCycling)
                Section("Zones touchées") {
                    ForEach(Muscle.allCases) { muscle in
                        Toggle(muscle.label, isOn: Binding(
                            get: { muscles.contains(muscle) },
                            set: { isOn in
                                if isOn { muscles.insert(muscle) } else { muscles.remove(muscle) }
                            }))
                    }
                }
            }
            .navigationTitle("Blessure")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        let name = title.isEmpty ? "Blessure" : title
                        context.insert(Injury(title: name, muscles: muscles, affectsRunning: affectsRunning,
                                              affectsCycling: affectsCycling, severity: severity, start: start))
                        try? context.save()
                        dismiss()
                    }
                    .disabled(muscles.isEmpty)
                }
            }
        }
    }
}
