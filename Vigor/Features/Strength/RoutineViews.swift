import SwiftUI
import SwiftData

/// Haut de l'onglet Muscu : démarrer, tes programmes et séances types, la banque d'exercices, l'historique.
struct StrengthPlansSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: [SortDescriptor(\WorkoutRoutine.program), SortDescriptor(\WorkoutRoutine.order)]) private var routines: [WorkoutRoutine]
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    @State private var startingRoutine: WorkoutRoutine?
    @State private var startingEmpty = false
    @State private var editing: WorkoutRoutine?
    @State private var creating = false

    var body: some View {
        let hasDraft = WorkoutDraft.load()?.exercises.isEmpty == false
        let programs: [String] = routines.reduce(into: [String]()) { list, routine in
            if !list.contains(routine.program) { list.append(routine.program) }
        }
        VStack(spacing: 12) {
            Button { startingEmpty = true } label: {
                Label(hasDraft ? "Reprendre la séance en cours" : "Séance libre", systemImage: hasDraft ? "play.circle.fill" : "plus.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.strain)
            .controlSize(.large)

            if routines.isEmpty {
                GlassCard(tint: Theme.strain) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            IconBadge(symbol: "list.bullet.clipboard.fill", tint: Theme.strain, size: 26)
                            Text("Programmes").font(.headline)
                        }
                        Text("Crée tes séances types (exercices, séries, répétitions, repos) et lance-les en un tap. Les charges sont proposées d'après ta dernière séance.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button { createPPL() } label: {
                            Label("Créer mon programme PPL", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.strain)
                        Button { creating = true } label: {
                            Label("Séance type vide", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                }
            } else {
                ForEach(programs, id: \.self) { program in
                    HStack {
                        CapsLabel(program.isEmpty ? "Mes séances" : program)
                        Spacer()
                        if program == programs.last {
                            Button { creating = true } label: { Label("Séance type", systemImage: "plus") }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                    ForEach(routines.filter { $0.program == program }) { routine in
                        RoutineCard(routine: routine, lastDone: lastDone(routine),
                                    onStart: { startingRoutine = routine },
                                    onEdit: { editing = routine })
                    }
                }
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                NavigationLink { ExerciseLibraryView() } label: {
                    SimpleTile(title: "Exercices", value: "\(ExerciseLibrary.builtIn.count)+", caption: "banque et records",
                               symbol: "books.vertical.fill", tint: Theme.sleep)
                }
                NavigationLink { StrengthHistoryView() } label: {
                    SimpleTile(title: "Historique", value: "\(workouts.count)", caption: "séances enregistrées",
                               symbol: "clock.arrow.circlepath", tint: Theme.recovery)
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $startingEmpty) { WorkoutLoggerView() }
        .sheet(item: $startingRoutine) { routine in WorkoutLoggerView(routine: routine) }
        .sheet(item: $editing) { routine in RoutineEditorView(routine: routine) }
        .sheet(isPresented: $creating) { RoutineEditorView(routine: nil, defaultProgram: programs.last ?? ProgramTemplates.pplName) }
    }

    private func lastDone(_ routine: WorkoutRoutine) -> Date? {
        workouts.first { $0.title.caseInsensitiveCompare(routine.name) == .orderedSame }?.start
    }

    private func createPPL() {
        for (index, template) in ProgramTemplates.ppl().enumerated() {
            context.insert(WorkoutRoutine(name: template.name, program: ProgramTemplates.pplName, order: index, items: template.items))
        }
        try? context.save()
        app.dataVersion += 1
    }
}

private struct RoutineCard: View {
    let routine: WorkoutRoutine
    let lastDone: Date?
    let onStart: () -> Void
    let onEdit: () -> Void

    var body: some View {
        let items = routine.items
        let sets = items.reduce(0) { $0 + $1.sets }
        let minutes = items.reduce(0) { $0 + $1.sets * (45 + $1.restSeconds) } / 60
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(routine.name).font(.title3.weight(.bold))
                        Text("\(items.count) exercices · \(sets) séries · ~\(minutes) min")
                            .font(.caption).foregroundStyle(.secondary)
                        if let lastDone {
                            Text("Dernière fois \(lastDone.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button(action: onEdit) { Image(systemName: "pencil.circle.fill").font(.title2) }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
                Text(items.prefix(4).map(\.exercise).joined(separator: " · ") + (items.count > 4 ? " …" : ""))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                Button(action: onStart) {
                    Label("Démarrer", systemImage: "play.fill").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.strain)
            }
        }
    }
}

/// Création / modification d'une séance type.
struct RoutineEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    let routine: WorkoutRoutine?
    var defaultProgram = ProgramTemplates.pplName
    @State private var name = ""
    @State private var program = ""
    @State private var notes = ""
    @State private var items: [RoutineItem] = []
    @State private var picking = false
    @State private var loaded = false
    @State private var confirmDelete = false

    private static let repPresets: [(Int, Int)] = [(3, 5), (5, 5), (6, 8), (6, 10), (8, 10), (8, 12), (10, 12), (10, 15), (12, 15), (15, 20)]
    private static let restPresets: [Int] = [45, 60, 75, 90, 120, 150, 180, 240]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Nom (ex. Push A)", text: $name)
                    TextField("Programme (ex. PPL)", text: $program)
                    TextField("Notes", text: $notes, axis: .vertical)
                }
                Section("Exercices") {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.exercise).font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                Menu {
                                    ForEach(1...8, id: \.self) { count in Button("\(count) séries") { item.sets = count } }
                                } label: { pill("\(item.sets) séries") }
                                Menu {
                                    ForEach(Self.repPresets.indices, id: \.self) { index in
                                        let preset = Self.repPresets[index]
                                        Button(preset.0 == preset.1 ? "\(preset.0) reps" : "\(preset.0)–\(preset.1) reps") {
                                            item.repLow = preset.0
                                            item.repHigh = preset.1
                                        }
                                    }
                                } label: { pill("\(item.repText) reps") }
                                Menu {
                                    ForEach(Self.restPresets, id: \.self) { seconds in
                                        Button(String(format: "Repos %d:%02d", seconds / 60, seconds % 60)) { item.restSeconds = seconds }
                                    }
                                } label: { pill("⏱ \(item.restText)") }
                            }
                            if !item.note.isEmpty {
                                Text(item.note).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove { items.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { items.remove(atOffsets: $0) }

                    Button { picking = true } label: { Label("Ajouter un exercice", systemImage: "plus.circle.fill") }
                }
                if routine != nil {
                    Section {
                        Button("Supprimer la séance type", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(routine == nil ? "Nouvelle séance type" : "Séance type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || items.isEmpty)
                }
            }
            .confirmationDialog("Supprimer cette séance type ?", isPresented: $confirmDelete) {
                Button("Supprimer", role: .destructive) {
                    if let routine { context.delete(routine) }
                    try? context.save()
                    app.dataVersion += 1
                    dismiss()
                }
            } message: {
                Text("Tes séances déjà faites restent dans l'historique.")
            }
            .sheet(isPresented: $picking) {
                ExercisePicker { exercise in
                    let range = MuscleMap.repRange(for: exercise)
                    items.append(RoutineItem(exercise: exercise, sets: 3, repLow: range.lowerBound, repHigh: range.upperBound,
                                             restSeconds: MuscleMap.isCompound(exercise) ? 150 : 90))
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let routine {
                    name = routine.name
                    program = routine.program
                    notes = routine.notes
                    items = routine.items
                } else {
                    program = defaultProgram
                }
            }
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.secondary.opacity(0.12), in: .capsule)
            .foregroundStyle(Color.primary)
    }

    private func save() {
        let target: WorkoutRoutine
        if let routine {
            target = routine
        } else {
            let siblings = (try? context.fetch(FetchDescriptor<WorkoutRoutine>()))?.filter { $0.program == program }.count ?? 0
            target = WorkoutRoutine(name: name, program: program, order: siblings)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.program = program.trimmingCharacters(in: .whitespaces)
        target.notes = notes
        target.items = items
        try? context.save()
        app.dataVersion += 1
        dismiss()
    }
}

/// Toutes tes séances, par mois, avec volume et records.
struct StrengthHistoryView: View {
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]

    var body: some View {
        let calendar = Calendar.current
        var months: [Date] = []
        for workout in workouts {
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: workout.start)) ?? workout.start
            if months.last != month { months.append(month) }
        }
        return List {
            if workouts.isEmpty {
                Text("Aucune séance pour l'instant. Lance une séance depuis l'onglet Muscu.").foregroundStyle(.secondary)
            }
            ForEach(months, id: \.self) { month in
                Section(month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(workouts.filter { calendar.isDate($0.start, equalTo: month, toGranularity: .month) }) { workout in
                        NavigationLink {
                            StrengthWorkoutDetailView(workout: workout)
                        } label: {
                            HistoryRow(workout: workout)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Historique")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HistoryRow: View {
    let workout: StrengthWorkout

    var body: some View {
        let working = workout.sets.filter { !$0.isWarmup }
        var tonnage = 0.0
        for set in working { tonnage += (set.weightKg ?? 0) * Double(set.reps ?? 0) }
        let exercises = Set(working.map(\.exercise)).count
        return HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(workout.start.formatted(.dateTime.day())).font(.headline.monospacedDigit())
                Text(workout.start.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).font(.subheadline.weight(.semibold))
                Text("\(exercises) exercices · \(working.count) séries · \(String(format: "%.1f t", tonnage / 1000)) · \((workout.durationSeconds / 3600).hoursText)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
