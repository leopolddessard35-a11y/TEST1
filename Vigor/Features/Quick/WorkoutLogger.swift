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
        /// Heure de validation : la durée réelle de la séance va de la première à la dernière série.
        var doneAt: Date?
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

    /// Exercices ayant au moins une série cochée (seuls ceux-ci sont enregistrés).
    var loggedExercises: Int {
        exercises.filter { exercise in exercise.sets.contains { $0.done && ($0.reps ?? 0) > 0 } }.count
    }

    /// Première et dernière série validées.
    var firstSetAt: Date? { exercises.flatMap(\.sets).compactMap(\.doneAt).min() }
    var lastSetAt: Date? { exercises.flatMap(\.sets).compactMap(\.doneAt).max() }

    /// Durée estimée : de la première à la dernière série + un repos ; sinon depuis l'ouverture (4 h au plus).
    var estimatedMinutes: Int {
        if let first = firstSetAt, let last = lastSetAt {
            return min(240, max(5, Int((last.timeIntervalSince(first) + 120) / 60)))
        }
        return min(240, max(5, Int(Date.now.timeIntervalSince(start) / 60)))
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

/// Champ de saisie actif (pour les boutons −/+ au-dessus du clavier).
enum LogField: Hashable {
    case weight(UUID)
    case reps(UUID)
}

/// Suppression annulable pendant quelques secondes.
private struct LoggerUndo: Identifiable {
    let id = UUID()
    let message: String
    let previous: WorkoutDraft
}

/// Saisie d'une séance de musculation en direct, à la manière de Hevy.
struct WorkoutLoggerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    @Query(sort: \WorkoutRoutine.order) private var routines: [WorkoutRoutine]
    @Query private var injuries: [Injury]
    /// Séance type à lancer (sinon séance libre).
    var routine: WorkoutRoutine?
    @State private var draft = WorkoutDraft()
    @State private var restExercise = ""
    @State private var restNext = ""
    @State private var loaded = false
    @State private var picking = false
    @State private var finishing = false
    @State private var confirmLeave = false
    @State private var confirmRoutineSwitch = false
    @State private var restEnd: Date?
    @State private var undo: LoggerUndo?
    @FocusState private var focus: LogField?

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
                                        advice: advice(for: exercise.name, sessions: sessions, target: exercise.targetReps),
                                        focus: $focus,
                                        onSetDone: { setID in startRest(after: setID, in: exercise.id) },
                                        onBeforeDelete: { message in offerUndo(message) },
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
                VStack(spacing: 8) {
                    if let undo {
                        UndoToast(message: undo.message) {
                            draft = undo.previous
                            self.undo = nil
                        }
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: undo.id) {
                            try? await Task.sleep(for: .seconds(5))
                            if self.undo?.id == undo.id { withAnimation { self.undo = nil } }
                        }
                    }
                    if let restEnd {
                        RestBanner(end: restEnd,
                                   onAdjust: { delta in
                                       // Repos déjà terminé : « +15 s » repart de maintenant.
                                       let base = restEnd < .now ? Date.now : restEnd
                                       setRest(until: base.addingTimeInterval(delta))
                                   },
                                   onSkip: { setRest(until: nil) })
                    }
                }
                .animation(.snappy, value: undo?.id)
            }
            .navigationTitle("Séance de muscu")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // En salle : ajuster sans retaper (±2,5 kg, ±1 rep), puis passer au champ suivant.
                ToolbarItemGroup(placement: .keyboard) {
                    if case .weight(let id) = focus {
                        let step = weightStep(for: id)
                        Button("−\(step.formatted())") { adjust(id, weight: -step) }
                        Button("+\(step.formatted())") { adjust(id, weight: step) }
                    }
                    if case .reps(let id) = focus {
                        Button("−1") { adjust(id, reps: -1) }
                        Button("+1") { adjust(id, reps: 1) }
                    }
                    Spacer()
                    Button("Suivant") { focusNext() }
                    Button("OK") { focus = nil }.fontWeight(.semibold)
                }
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
                        .disabled(draft.completedSets == 0)
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
                FinishWorkoutSheet(draft: draft) { rpe, notes, minutes in save(rpe: rpe, notes: notes, minutes: minutes) }
                    .presentationDetents([.medium, .large])
            }
            .onAppear {
                // L'écran reste allumé pendant la séance (repos, téléphone posé sur le banc).
                UIApplication.shared.isIdleTimerDisabled = true
                guard !loaded else { return }
                loaded = true
                if let saved = WorkoutDraft.load(), !saved.exercises.isEmpty {
                    draft = saved
                    // Une autre séance type a été lancée alors qu'une séance est en cours : on demande.
                    if let routine, saved.routineID != routine.routineID {
                        confirmRoutineSwitch = true
                    }
                } else if let routine {
                    start(routine, history: history)
                } else {
                    // Séance libre : titre vide (les raccourcis proposent tes propres noms).
                    draft = WorkoutDraft(title: "", start: .now, exercises: [])
                }
            }
            .confirmationDialog("Une séance est déjà en cours", isPresented: $confirmRoutineSwitch, titleVisibility: .visible) {
                Button("Reprendre la séance en cours") {}
                if let routine {
                    Button("Commencer \(routine.name)", role: .destructive) {
                        setRest(until: nil)
                        start(routine, history: history)
                    }
                }
            } message: {
                Text("Commencer la nouvelle séance abandonne celle en cours.")
            }
            .interactiveDismissDisabled(!draft.exercises.isEmpty)
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .onChange(of: draft) { draft.persist() }
            .task(id: restEnd) {
                // Compte à rebours sonore quand l'app est ouverte : tics sur les 3 dernières secondes, puis son + vibration.
                guard let end = restEnd else { return }
                while true {
                    let remaining = end.timeIntervalSinceNow
                    if remaining <= 0 { break }
                    if remaining <= 3.05 { Feedback.tick() }
                    try? await Task.sleep(for: .seconds(min(1, remaining)))
                    if Task.isCancelled { return }
                }
                // Retour dans l'app longtemps après la fin du repos : pas de son en retard (la notification a déjà sonné).
                if -end.timeIntervalSinceNow < 2 { Feedback.restFinished() }
            }
        }
    }

    // MARK: En-tête

    private var header: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Nom de la séance", text: $draft.title).font(.title3.weight(.bold))
                // Raccourcis : tes propres noms de séances déjà utilisés (rien de pré-rempli).
                let recentTitles: [String] = workouts.reduce(into: [String]()) { list, workout in
                    if list.count < 4 && !list.contains(workout.title) { list.append(workout.title) }
                }
                if !recentTitles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentTitles, id: \.self) { name in
                                Button(name) { draft.title = name }
                                    .buttonStyle(.bordered)
                                    .tint(draft.title == name ? Theme.accent : .secondary)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                HStack(spacing: 16) {
                    Label { Text(draft.start, style: .timer).monospacedDigit() } icon: { Image(systemName: "stopwatch") }
                    Label("\(draft.completedSets) séries", systemImage: "checkmark.circle")
                    Label(String(format: "%.0f kg", locale: Locale.current, draft.tonnage), systemImage: "scalemass")
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                if !draft.exercises.isEmpty {
                    Text("Touche le numéro d'une série pour la passer en échauffement, appui long pour la supprimer.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
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
            if !routines.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tes séances types").font(.headline)
                        ForEach(routines) { routine in
                            Button { start(routine, history: history) } label: {
                                HStack {
                                    Image(systemName: "dumbbell.fill").foregroundStyle(Theme.accent)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(routine.name).font(.subheadline.weight(.semibold))
                                        Text("\(routine.items.count) exercices").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .frame(minHeight: 44)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
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

    /// Nouvelle séance à partir d'une séance type (remplace le brouillon éventuel).
    private func start(_ routine: WorkoutRoutine, history: [String: [ExerciseSession]]) {
        draft = WorkoutDraft(title: routine.name, start: .now, exercises: [], routineID: routine.routineID)
        for item in routine.items {
            add(item.exercise, history: history, setCount: item.sets, target: item.repText,
                rest: item.restSeconds, note: item.note, defaultReps: item.repLow)
        }
    }

    private func add(_ name: String, history: [String: [ExerciseSession]], setCount: Int? = nil, target: String? = nil,
                     rest: Int? = nil, note: String? = nil, defaultReps: Int? = nil) {
        let sessions: [ExerciseSession] = history[name] ?? []
        var sets: [WorkoutDraft.SetDraft] = []
        var deload = false
        if let last = sessions.last {
            let progression = advice(for: name, sessions: sessions, target: target)
            for set in last.sets where (set.reps ?? 0) > 0 {
                let weight: Double? = set.isWarmup ? set.weightKg : (progression?.suggestedWeightKg ?? set.weightKg)
                sets.append(WorkoutDraft.SetDraft(weight: weight, reps: set.reps, warmup: set.isWarmup))
            }
            // Décharge conseillée : moitié des séries de travail (au moins 2), aussi pour une séance type.
            if progression?.action == .deload {
                let warmups = sets.filter(\.warmup)
                let working = sets.filter { !$0.warmup }
                sets = warmups + Array(working.prefix(max(2, working.count / 2)))
                deload = true
            }
        }
        // Nombre de séries de travail imposé par la séance type (divisé par deux en décharge).
        if let routineSets = setCount {
            let setCount = deload ? max(2, routineSets / 2) : routineSets
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

    /// Conseil de progression avec la plage de ta séance type, ta récup du jour et tes blessures
    /// (le même que sur la page Progression).
    private func advice(for name: String, sessions: [ExerciseSession], target: String?) -> ProgressionAdvice? {
        let injured = injuries.filter(\.isActive).reduce(into: Set<Muscle>()) { $0.formUnion($1.muscles) }
        return StrengthProgression.advise(exercise: name, sessions: sessions,
                                          readiness: app.snapshotCache.latest?.readiness?.level,
                                          injuredMuscles: injured,
                                          targetReps: StrengthProgression.repRange(fromText: target))
    }

    /// Pas des boutons ± du clavier : 2 kg pour les haltères, 2,5 kg sinon.
    private func weightStep(for setID: UUID) -> Double {
        let name = draft.exercises.first { $0.sets.contains { $0.id == setID } }?.name ?? ""
        return MuscleMap.equipment(for: name) == .dumbbell ? 2 : 2.5
    }

    private func offerUndo(_ message: String) {
        undo = LoggerUndo(message: message, previous: draft)
    }

    private func adjust(_ setID: UUID, weight delta: Double = 0, reps repsDelta: Int = 0) {
        for exerciseIndex in draft.exercises.indices {
            guard let setIndex = draft.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) else { continue }
            if delta != 0 {
                let current = draft.exercises[exerciseIndex].sets[setIndex].weight ?? 0
                draft.exercises[exerciseIndex].sets[setIndex].weight = max(0, current + delta)
            }
            if repsDelta != 0 {
                let current = draft.exercises[exerciseIndex].sets[setIndex].reps ?? 0
                draft.exercises[exerciseIndex].sets[setIndex].reps = max(0, current + repsDelta)
            }
            Feedback.tick()
            return
        }
    }

    /// kg → reps de la même série → kg de la série suivante.
    private func focusNext() {
        guard let focus else { return }
        let allSets: [WorkoutDraft.SetDraft] = draft.exercises.flatMap(\.sets)
        switch focus {
        case .weight(let id):
            self.focus = .reps(id)
        case .reps(let id):
            if let index = allSets.firstIndex(where: { $0.id == id }), index + 1 < allSets.count {
                self.focus = .weight(allSets[index + 1].id)
            } else {
                self.focus = nil
            }
        }
    }

    private func remove(_ id: UUID) {
        if let name = draft.exercises.first(where: { $0.id == id })?.name {
            offerUndo("\(name) supprimé")
        }
        draft.exercises.removeAll { $0.id == id }
    }

    /// Lance le repos après une série validée : notification avec la prochaine série.
    private func startRest(after setID: UUID, in exerciseID: UUID) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
        let exercise = draft.exercises[index]
        // Première série validée : c'est le bon moment pour demander les notifications (fin de repos écran verrouillé).
        if draft.completedSets <= 1 {
            Task { await NotificationScheduler.requestAuthorizationIfNeeded() }
        }
        // Plus aucune série à faire : pas de repos, la séance est finie.
        guard draft.exercises.contains(where: { $0.sets.contains { !$0.done } }) else {
            setRest(until: nil)
            return
        }
        let isWarmup = exercise.sets.first { $0.id == setID }?.warmup ?? false
        let seconds = isWarmup ? 60 : Double(exercise.restSeconds ?? (MuscleMap.isCompound(exercise.name) ? 150 : 90))
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

    /// `minutes` : durée confirmée dans la feuille de fin (par défaut, de la première à la dernière série).
    private func save(rpe: Int?, notes: String, minutes: Int) {
        // Datée de la première série validée (une séance reprise le lendemain garde le bon jour et la bonne durée).
        let start: Date = draft.firstSetAt.map { $0.addingTimeInterval(-60) } ?? draft.start
        let end: Date = start.addingTimeInterval(Double(max(5, minutes)) * 60)
        let title = draft.title.trimmingCharacters(in: .whitespaces).isEmpty ? "Séance" : draft.title
        let workout = StrengthWorkout(externalID: "vigor-\(UUID().uuidString)", title: title, start: start, end: end, notes: notes)
        workout.rpe = rpe
        context.insert(workout)
        var models: [StrengthSet] = []
        var index = 0
        for exercise in draft.exercises {
            // Seules les séries cochées (avec des répétitions) sont enregistrées ; un exercice sans série cochée est ignoré.
            for set in exercise.sets where set.done && (set.reps ?? 0) > 0 {
                models.append(StrengthSet(exercise: exercise.name, exerciseNotes: "", setIndex: index,
                                          setType: set.warmup ? "warmup" : "normal", weightKg: set.weight, reps: set.reps,
                                          distanceKm: nil, durationSeconds: nil, rpe: nil, supersetID: nil))
                index += 1
            }
        }
        // Records comparés à tout l'historique (pas seulement les séances récentes).
        let records = Self.records(in: draft, history: Self.history(of: workouts, limit: nil))
        workout.sets = models
        try? context.save()
        WorkoutDraft.clear()
        setRest(until: nil)
        app.dataVersion += 1
        var message = "Séance « \(title) » enregistrée : \(models.count) séries."
        if !records.isEmpty {
            message += "\nRecords : " + records.joined(separator: ", ") + "."
        }
        app.statusMessage = message
        Feedback.success()
        dismiss()
    }

    // MARK: Historique

    /// `limit` : nombre de séances récentes parcourues (performance) ; `nil` = tout l'historique.
    static func history(of workouts: [StrengthWorkout], limit: Int? = 80) -> [String: [ExerciseSession]] {
        var result: [String: [ExerciseSession]] = [:]
        let source: ArraySlice<StrengthWorkout> = limit.map { workouts.prefix($0) } ?? workouts[...]
        for workout in source {
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
            // Records sur 12 répétitions au plus : au-delà, le 1RM estimé n'est pas fiable.
            for set in exercise.sets where set.done && !set.warmup && (1...12).contains(set.reps ?? 0) {
                guard let weight = set.weight, weight > 0, let reps = set.reps, reps > 0 else { continue }
                let e1rm = StrengthProgression.estimated1RM(weight: weight, reps: reps)
                if best == nil || e1rm > best!.e1rm { best = (e1rm, weight, reps) }
            }
            guard let best else { continue }
            let previous = (history[exercise.name] ?? []).map { $0.best1RM(maxReps: 12) }.max() ?? 0
            if previous > 0 && best.e1rm > previous {
                result.append("\(exercise.name) \(best.weight.formatted()) kg × \(best.reps)")
            }
        }
        return result
    }

}

// MARK: - Carte d'exercice

private struct ExerciseLogCard: View {
    @Binding var exercise: WorkoutDraft.ExerciseDraft
    let previous: ExerciseSession?
    let advice: ProgressionAdvice?
    var focus: FocusState<LogField?>.Binding
    let onSetDone: (UUID) -> Void
    let onBeforeDelete: (String) -> Void
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
                                Button(String(format: "%d:%02d", locale: Locale.current, seconds / 60, seconds % 60)) { exercise.restSeconds = seconds }
                            }
                        }
                        Button("Supprimer l'exercice", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title3)
                            .frame(width: 44, height: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityLabel("Options de l'exercice")
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
                    Text("Série").frame(width: 40)
                    Text("Précédent").frame(maxWidth: .infinity, alignment: .leading)
                    Text("kg").frame(width: 64)
                    Text("Reps").frame(width: 56)
                    Image(systemName: "checkmark").frame(width: 44)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach($exercise.sets) { $set in
                    let number = (exercise.sets.firstIndex { $0.id == set.id } ?? 0) + 1
                    SetLogRow(number: number, set: $set, previous: previousText(number - 1), focus: focus,
                              onDone: { onSetDone(set.id) })
                        .contextMenu {
                            Button("Supprimer la série", systemImage: "trash", role: .destructive) {
                                onBeforeDelete("Série \(number) supprimée")
                                exercise.sets.removeAll { $0.id == set.id }
                            }
                        }
                        .accessibilityAction(named: "Supprimer la série") {
                            onBeforeDelete("Série \(number) supprimée")
                            exercise.sets.removeAll { $0.id == set.id }
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
        return String(format: "Repos %d:%02d", locale: Locale.current, seconds / 60, seconds % 60)
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
    var focus: FocusState<LogField?>.Binding
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button { set.warmup.toggle() } label: {
                Text(set.warmup ? "É" : "\(number)")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(set.warmup ? Theme.nutrition : Color.primary)
                    .frame(width: 40, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.warmup ? "Série d'échauffement" : "Série \(number)")
            .accessibilityHint("Touche pour basculer en série d'échauffement")

            Text(previous).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)

            // Valeur mise à jour à chaque frappe : les boutons ± du clavier partent de ce qui est affiché.
            DecimalField("kg", value: $set.weight, keyboard: .decimalPad)
                .focused(focus, equals: .weight(set.id))
                .multilineTextAlignment(.center)
                .frame(width: 64, height: 44)
                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))
            IntegerField("reps", value: $set.reps)
                .focused(focus, equals: .reps(set.id))
                .multilineTextAlignment(.center)
                .frame(width: 56, height: 44)
                .background(Color.secondary.opacity(0.12), in: .rect(cornerRadius: 8))

            Button {
                set.done.toggle()
                set.doneAt = set.done ? .now : nil
                if set.done {
                    Feedback.setDone()
                    onDone()
                }
            } label: {
                Image(systemName: set.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.done ? Theme.recovery : Color.secondary)
                    // La coche « saute » quand la série est validée.
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: set.done)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.done ? "Série \(number) validée" : "Valider la série \(number)")
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
                Text(remaining > 0 ? String(format: "Repos %d:%02d", locale: Locale.current, remaining / 60, remaining % 60) : "Repos terminé")
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: remaining)
                    // Dernières secondes : le texte prend la couleur de l'effort et grossit un peu.
                    .foregroundStyle(remaining > 0 && remaining <= 3 ? Theme.strain : Color.primary)
                    .scaleEffect(remaining > 0 && remaining <= 3 ? 1.06 : 1)
                Spacer()
                Button("−15 s") { onAdjust(-15) }
                Button("+15 s") { onAdjust(15) }
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
    let onSave: (Int?, String, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rpe: Int?
    @State private var notes = ""
    @State private var minutes: Int?
    /// Évite d'enregistrer deux fois sur un double tap.
    @State private var saving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: Binding(get: { minutes ?? draft.estimatedMinutes }, set: { minutes = $0 }), in: 5...300, step: 5) {
                        LabeledContent("Durée", value: (Double(minutes ?? draft.estimatedMinutes) / 60).hoursText)
                    }
                    LabeledContent("Exercices", value: "\(draft.loggedExercises)")
                    LabeledContent("Séries validées", value: "\(draft.completedSets)")
                    LabeledContent("Tonnage", value: String(format: "%.0f kg", locale: Locale.current, draft.tonnage))
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
                        guard !saving else { return }
                        saving = true
                        onSave(rpe, notes, minutes ?? draft.estimatedMinutes)
                        dismiss()
                    }
                    .disabled(saving)
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
