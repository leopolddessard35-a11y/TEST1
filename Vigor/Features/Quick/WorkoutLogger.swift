import SwiftUI
import SwiftData

/// Séance en cours, sauvegardée à chaque modification : rien n'est perdu si tu quittes l'app pendant la séance.
struct WorkoutDraft: Codable, Equatable {
    struct SetDraft: Codable, Equatable, Identifiable {
        var id = UUID()
        var weight: Double?
        var reps: Int?
        var warmup = false
        var done = false
    }

    struct ExerciseDraft: Codable, Equatable, Identifiable {
        var id = UUID()
        var name: String
        var sets: [SetDraft]
        /// Repos après chaque série (secondes) ; défaut selon l'exercice.
        var restSeconds: Int?
        /// Objectif de la séance type (« 8–12 »).
        var targetReps: String?
        var note: String?
    }

    var title: String = ""
    var start: Date = .now
    var exercises: [ExerciseDraft] = []
    var routineID: String?

    static let storageKey = "vigor.workoutDraft"

    static func load() -> WorkoutDraft? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(WorkoutDraft.self, from: data)
    }

    func persist() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    var completedSets: Int {
        var count = 0
        for exercise in exercises {
            count += exercise.sets.filter { $0.done && ($0.reps ?? 0) > 0 }.count
        }
        return count
    }

    var tonnage: Double {
        var total = 0.0
        for exercise in exercises {
            for set in exercise.sets where set.done && !set.warmup {
                total += (set.weight ?? 0) * Double(set.reps ?? 0)
            }
        }
        return total
    }
}

/// Saisie d'une séance de musculation en direct, à la manière de Hevy.
struct WorkoutLoggerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    /// Séance type à lancer (sinon séance libre).
    var routine: WorkoutRoutine?
    @State private var draft = WorkoutDraft()
    @State private var restExercise = ""
    @State private var restNext = ""
    @State private var loaded = false
    @State private var picking = false
    @State private var finishing = false
    @State private var confirmLeave = false
    @State private var restEnd: Date?

    var body: some View {
        let history = Self.history(of: workouts)
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if draft.exercises.isEmpty {
                        templates
                    }
                    ForEach($draft.exercises) { $exercise in
                        let sessions: [ExerciseSession] = history[exercise.name] ?? []
                        ExerciseLogCard(exercise: $exercise,
                                        previous: sessions.last,
                                        advice: StrengthProgression.advise(exercise: exercise.name, sessions: sessions),
                                        onSetDone: { setID in startRest(after: setID, in: exercise.id) },
                                        onDelete: { remove(exercise.id) })
                    }
                    Button { picking = true } label: {
                        Label("Ajouter un exercice", systemImage: "plus").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                }
                .padding(16)
                .padding(.bottom, restEnd == nil ? 0 : 70)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .safeAreaInset(edge: .bottom) {
                if let restEnd {
                    RestBanner(end: restEnd,
                               onAdjust: { delta in setRest(until: restEnd.addingTimeInterval(delta)) },
                               onSkip: { setRest(until: nil) })
                }
            }
            .navigationTitle("Séance de muscu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        if draft.exercises.isEmpty {
                            WorkoutDraft.clear()
                            dismiss()
                        } else {
                            confirmLeave = true
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminer") { finishing = true }
                        .disabled(draft.exercises.allSatisfy { exercise in exercise.sets.allSatisfy { ($0.reps ?? 0) == 0 } })
                }
            }
            .confirmationDialog("Séance en cours", isPresented: $confirmLeave) {
                Button("Continuer plus tard") { dismiss() }
                Button("Abandonner la séance", role: .destructive) {
                    WorkoutDraft.clear()
                    setRest(until: nil)
                    dismiss()
                }
                Button("Continuer la séance", role: .cancel) {}
            } message: {
                Text("Ta séance reste enregistrée en brouillon : tu la retrouves en rouvrant « Séance de muscu ».")
            }
            .sheet(isPresented: $picking) {
                ExercisePicker { name in add(name, history: history) }
            }
            .sheet(isPresented: $finishing) {
                FinishWorkoutSheet(draft: draft) { rpe, notes in save(rpe: rpe, notes: notes) }
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let saved = WorkoutDraft.load(), !saved.exercises.isEmpty {
                    draft = saved
                } else if let routine {
                    draft = WorkoutDraft(title: routine.name, start: .now, exercises: [], routineID: routine.routineID)
                    for item in routine.items {
                        add(item.exercise, history: history, setCount: item.sets, target: item.repText,
                            rest: item.restSeconds, note: item.note, defaultReps: item.repLow)
                    }
                } else {
                    draft = WorkoutDraft(title: Self.suggestedTitle(workouts), start: .now, exercises: [])
                }
            }
            .onChange(of: draft) { draft.persist() }
        }
    }

    // MARK: En-tête

    private var header: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Nom de la séance", text: $draft.title).font(.title3.weight(.bold))
                HStack(spacing: 8) {
                    ForEach(["Push", "Pull", "Legs", "Full body"], id: \.self) { name in
                        Button(name) { draft.title = name }
                            .buttonStyle(.bordered)
                            .tint(draft.title == name ? Theme.strain : .secondary)
                            .font(.caption.weight(.semibold))
                    }
                }
                HStack(spacing: 16) {
                    Label { Text(draft.start, style: .timer).monospacedDigit() } icon: { Image(systemName: "stopwatch") }
                    Label("\(draft.completedSets) séries", systemImage: "checkmark.circle")
                    Label(String(format: "%.0f kg", draft.tonnage), systemImage: "scalemass")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            }
        }
    }

    /// Reprendre une séance passée : mêmes exercices, charges déjà ajustées par le coach.
    private var templates: some View {
        let history = Self.history(of: workouts)
        var seen = Set<String>()
        var recent: [StrengthWorkout] = []
        for workout in workouts where !seen.contains(workout.title) {
            seen.insert(workout.title)
            recent.append(workout)
            if recent.count == 4 { break }
        }
        return Group {
            if !recent.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Répéter une séance").font(.headline)
                        Text("Mêmes exercices, charges proposées selon ta dernière séance.").font(.caption).foregroundStyle(.secondary)
                        ForEach(recent, id: \.externalID) { workout in
                            Button {
                                draft.title = workout.title
                                for session in workout.exerciseSessions { add(session.exercise, history: history) }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise.circle.fill").foregroundStyle(Theme.strain)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(workout.title).font(.subheadline.weight(.semibold))
                                        Text("\(workout.exerciseSessions.count) exercices · \(workout.start.formatted(.relative(presentation: .named)))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func add(_ name: String, history: [String: [ExerciseSession]], setCount: Int? = nil, target: String? = nil,
                     rest: Int? = nil, note: String? = nil, defaultReps: Int? = nil) {
        let sessions: [ExerciseSession] = history[name] ?? []
        var sets: [WorkoutDraft.SetDraft] = []
        if let last = sessions.last {
            let advice = StrengthProgression.advise(exercise: name, sessions: sessions)
            for set in last.sets where (set.reps ?? 0) > 0 {
                let weight: Double? = set.isWarmup ? set.weightKg : (advice?.suggestedWeightKg ?? set.weightKg)
                sets.append(WorkoutDraft.SetDraft(weight: weight, reps: set.reps, warmup: set.isWarmup))
            }
        }
        // Nombre de séries de travail imposé par la séance type.
        if let setCount {
            let warmups = sets.filter(\.warmup)
            var working = sets.filter { !$0.warmup }
            let template = working.last ?? WorkoutDraft.SetDraft(weight: nil, reps: defaultReps)
            if working.count > setCount { working = Array(working.prefix(setCount)) }
            while working.count < setCount {
                working.append(WorkoutDraft.SetDraft(weight: template.weight, reps: template.reps))
            }
            sets = warmups + working
        }
        if sets.isEmpty {
            sets = [WorkoutDraft.SetDraft(), WorkoutDraft.SetDraft(), WorkoutDraft.SetDraft()]
        }
        draft.exercises.append(WorkoutDraft.ExerciseDraft(name: name, sets: sets, restSeconds: rest, targetReps: target,
                                                          note: (note ?? "").isEmpty ? nil : note))
    }

    private func remove(_ id: UUID) {
        draft.exercises.removeAll { $0.id == id }
    }

    /// Lance le repos après une série validée : Dynamic Island + notification avec la prochaine série.
    private func startRest(after setID: UUID, in exerciseID: UUID) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let exercise = draft.exercises[index]
        let seconds = Double(exercise.restSeconds ?? (MuscleMap.isCompound(exercise.name) ? 150 : 90))
        restExercise = exercise.name
        restNext = nextSetText(from: index)
        setRest(until: Date.now.addingTimeInterval(seconds))
    }

    private func nextSetText(from index: Int) -> String {
        for exerciseIndex in index..<draft.exercises.count {
            let exercise = draft.exercises[exerciseIndex]
            if let position = exercise.sets.firstIndex(where: { !$0.done }) {
                let set = exercise.sets[position]
                var text = exerciseIndex == index ? "Série \(position + 1)/\(exercise.sets.count)" : exercise.name
                if let weight = set.weight, weight > 0, let reps = set.reps {
                    text += " · \(weight.formatted()) kg × \(reps)"
                } else if let reps = set.reps {
                    text += " · \(reps) reps"
                }
                return text
            }
        }
        return "Dernière série faite : termine la séance"
    }

    private func setRest(until date: Date?) {
        restEnd = date
        guard let date, date > .now else {
            RestTimer.stop()
            return
        }
        RestTimer.start(end: date, exercise: restExercise, next: restNext,
                        workout: draft.title.isEmpty ? "Séance" : draft.title)
    }

    private func save(rpe: Int?, notes: String) {
        let end: Date = min(Date.now, draft.start.addingTimeInterval(4 * 3600))
        let title = draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Séance" : draft.title
        let workout = StrengthWorkout(externalID: "vigor-\(UUID().uuidString)", title: title, start: draft.start, end: end, notes: notes)
        workout.rpe = rpe
        context.insert(workout)
        var models: [StrengthSet] = []
        var index = 0
        for exercise in draft.exercises {
            // Séries cochées ; si aucune ne l'est pour cet exercice, toutes celles qui ont des répétitions.
            let anyDone = exercise.sets.contains { $0.done }
            for set in exercise.sets where (set.reps ?? 0) > 0 && (set.done || !anyDone) {
                models.append(StrengthSet(exercise: exercise.name, exerciseNotes: "", setIndex: index,
                                          setType: set.warmup ? "warmup" : "normal", weightKg: set.weight, reps: set.reps,
                                          distanceKm: nil, durationSeconds: nil, rpe: nil, supersetID: nil))
                index += 1
            }
        }
        let records = Self.records(in: draft, history: Self.history(of: workouts))
        workout.sets = models
        try? context.save()
        WorkoutDraft.clear()
        setRest(until: nil)
        app.dataVersion += 1
        var message = "Séance « \(title) » enregistrée : \(models.count) séries."
        if !records.isEmpty {
            message += "\n🏆 Records : " + records.joined(separator: ", ") + "."
        }
        app.statusMessage = message
        dismiss()
    }

    // MARK: Historique

    static func history(of workouts: [StrengthWorkout]) -> [String: [ExerciseSession]] {
        var result: [String: [ExerciseSession]] = [:]
        for workout in workouts.prefix(80) {
            for session in workout.exerciseSessions {
                result[session.exercise, default: []].append(session)
            }
        }
        for key in result.keys {
            result[key]?.sort { $0.date < $1.date }
        }
        return result
    }

    /// Exercices où le meilleur 1RM estimé du jour dépasse tout l'historique.
    static func records(in draft: WorkoutDraft, history: [String: [ExerciseSession]]) -> [String] {
        var result: [String] = []
        for exercise in draft.exercises {
            var best: (e1rm: Double, weight: Double, reps: Int)?
            for set in exercise.sets where set.done && !set.warmup {
                guard let weight = set.weight, weight > 0, let reps = set.reps, reps > 0 else { continue }
                let e1rm = StrengthProgression.estimated1RM(weight: weight, reps: reps)
                if best == nil || e1rm > best!.e1rm { best = (e1rm, weight, reps) }
            }
            guard let best else { continue }
            let previous = (history[exercise.name] ?? []).map(\.bestEstimated1RM).max() ?? 0
            if previous > 0 && best.e1rm > previous {
                result.append("\(exercise.name) \(best.weight.formatted()) kg × \(best.reps)")
            }
        }
        return result
    }

    /// Propose la suite logique du PPL (après Push → Pull → Legs).
    static func suggestedTitle(_ workouts: [StrengthWorkout]) -> String {
        guard let last = workouts.first?.title.lowercased() else { return "Push" }
        if last.contains("push") { return "Pull" }
        if last.contains("pull") { return "Legs" }
        if last.contains("leg") { return "Push" }
        return ""
    }
}

// MARK: - Carte d'exercice

private struct ExerciseLogCard: View {
    @Binding var exercise: WorkoutDraft.ExerciseDraft
    let previous: ExerciseSession?
    let advice: ProgressionAdvice?
    let onSetDone: (UUID) -> Void
    let onDelete: () -> Void

    private static let restPresets: [Int] = [45, 60, 75, 90, 120, 150, 180, 240]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name).font(.headline)
                        Text(MuscleMap.targets(for: exercise.name).primary.map(\.label).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("Ajouter une série", systemImage: "plus") { addSet() }
                        Menu("Temps de repos") {
                            ForEach(Self.restPresets, id: \.self) { seconds in
                                Button(String(format: "%d:%02d", seconds / 60, seconds % 60)) { exercise.restSeconds = seconds }
                            }
                        }
                        Button("Supprimer l'exercice", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                    }
                }
                HStack(spacing: 6) {
                    if let target = exercise.targetReps {
                        StatusPill(text: "Objectif \(target) reps", symbol: "target", color: Theme.sleep)
                    }
                    StatusPill(text: restText, symbol: "timer", color: Theme.strain)
                }
                if let note = exercise.note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                if let advice {
                    Label(advice.reason, systemImage: advice.action.symbol)
                        .font(.caption)
                        .foregroundStyle(advice.action == .increase ? Theme.recovery : .secondary)
                }
                HStack(spacing: 8) {
                    Text("Série").frame(width: 34)
                    Text("Précédent").frame(maxWidth: .infinity, alignment: .leading)
                    Text("kg").frame(width: 64)
                    Text("Reps").frame(width: 52)
                    Image(systemName: "checkmark").frame(width: 30)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach($exercise.sets) { $set in
                    let number = (exercise.sets.firstIndex { $0.id == set.id } ?? 0) + 1
                    SetLogRow(number: number, set: $set, previous: previousText(number - 1), onDone: { onSetDone(set.id) })
                        .contextMenu {
                            Button("Supprimer la série", systemImage: "trash", role: .destructive) {
                                exercise.sets.removeAll { $0.id == set.id }
                            }
                        }
                }

                Button { addSet() } label: {
                    Label("Ajouter une série", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var restText: String {
        let seconds = exercise.restSeconds ?? (MuscleMap.isCompound(exercise.name) ? 150 : 90)
        return String(format: "Repos %d:%02d", seconds / 60, seconds % 60)
    }

    private func previousText(_ index: Int) -> String {
        guard let previous, index < previous.sets.count else { return "–" }
        let set = previous.sets[index]
        guard let reps = set.reps else { return "–" }
        if let weight = set.weightKg, weight > 0 { return "\(weight.formatted()) × \(reps)" }
        return "\(reps) reps"
    }

    private func addSet() {
        let last = exercise.sets.last
        exercise.sets.append(WorkoutDraft.SetDraft(weight: last?.weight, reps: last?.reps))
    }
}

private struct SetLogRow: View {
    let number: Int
    @Binding var set: WorkoutDraft.SetDraft
    let previous: String
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { set.warmup.toggle() } label: {
                Text(set.warmup ? "É" : "\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(set.warmup ? Theme.nutrition : Color.primary)
                    .frame(width: 34, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.warmup ? "Série d'échauffement" : "Série \(number)")

            Text(previous).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)

            TextField("kg", value: $set.weight, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 32)
                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
            TextField("reps", value: $set.reps, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 52, height: 32)
                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))

            Button {
                set.done.toggle()
                if set.done { onDone() }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.done ? Theme.recovery : Color.secondary)
                    .frame(width: 30)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.success, trigger: set.done)
        }
        .font(.subheadline.monospacedDigit())
        .padding(.vertical, 2)
        .background(set.done ? Theme.recovery.opacity(0.10) : Color.clear, in: .rect(cornerRadius: 8))
    }
}

// MARK: - Repos

private struct RestBanner: View {
    let end: Date
    let onAdjust: (Double) -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = Int(max(0, end.timeIntervalSince(timeline.date)).rounded(.up))
            HStack(spacing: 10) {
                Image(systemName: "timer").foregroundStyle(Theme.strain)
                Text(remaining > 0 ? String(format: "Repos %d:%02d", remaining / 60, remaining % 60) : "Repos terminé")
                    .font(.headline.monospacedDigit())
                Spacer()
                Button("−15") { onAdjust(-15) }
                Button("+15") { onAdjust(15) }
                Button(remaining > 0 ? "Passer" : "OK", action: onSkip)
            }
            .buttonStyle(.bordered)
            .padding(12)
            .card(cornerRadius: 20)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Fin de séance

private struct FinishWorkoutSheet: View {
    let draft: WorkoutDraft
    let onSave: (Int?, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Int?
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Durée", value: (Date.now.timeIntervalSince(draft.start) / 3600).hoursText)
                    LabeledContent("Exercices", value: "\(draft.exercises.count)")
                    LabeledContent("Séries validées", value: "\(draft.completedSets)")
                    LabeledContent("Tonnage", value: String(format: "%.0f kg", draft.tonnage))
                }
                Section("Effort ressenti de la séance") {
                    RPEPicker(value: rpe) { rpe = $0 }
                }
                Section("Notes") {
                    TextField("Sensations, douleur…", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle("Terminer la séance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Retour") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        onSave(rpe, notes)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Choix d'exercice

/// Choix d'un exercice dans la banque (feuille).
struct ExercisePicker: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseLibraryView(onPick: { name in
                onPick(name)
                dismiss()
            })
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
    }
}
