import SwiftUI
import SwiftData

/// Banque d'exercices : recherche, filtres par groupe et matériel, exercices perso.
/// En mode choix (`onPick`), un tap ajoute l'exercice ; sinon il ouvre sa fiche et ton historique.
struct ExerciseLibraryView: View {
    @Query(sort: \CustomExercise.name) private var custom: [CustomExercise]
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    var onPick: ((String) -> Void)?
    @State private var query = ""
    @State private var group: MuscleGroup?
    @State private var equipment: Equipment?
    @State private var creating = false

    var body: some View {
        let history = WorkoutLoggerView.history(of: workouts)
        let all = ExerciseLibrary.all(custom: custom, history: Array(history.keys).sorted())
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let filtered: [LibraryExercise] = all.filter { exercise in
            (trimmed.isEmpty || exercise.name.localizedCaseInsensitiveContains(trimmed)
                || exercise.musclesText.localizedCaseInsensitiveContains(trimmed))
                && (group == nil || exercise.group == group)
                && (equipment == nil || exercise.equipment == equipment)
        }
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip("Tout", selected: group == nil) { group = nil }
                        ForEach(MuscleGroup.allCases) { item in
                            chip(item.label, selected: group == item) { group = group == item ? nil : item }
                        }
                    }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Equipment.allCases) { item in
                            chip(item.label, selected: equipment == item, tint: Theme.sleep) { equipment = equipment == item ? nil : item }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            if !trimmed.isEmpty && !all.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                Section {
                    Button { creating = true } label: {
                        Label("Créer « \(trimmed) »", systemImage: "plus.circle.fill")
                    }
                }
            }

            Section("\(filtered.count) exercices") {
                ForEach(filtered) { exercise in
                    if let onPick {
                        Button { onPick(exercise.name) } label: { row(exercise, sessions: history[exercise.name]?.count ?? 0) }
                    } else {
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise.name, sessions: history[exercise.name] ?? [])
                        } label: { row(exercise, sessions: history[exercise.name]?.count ?? 0) }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Exercice ou muscle")
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Exercices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Label("Créer", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $creating) {
            CustomExerciseForm(initialName: trimmed) { name in onPick?(name) }
        }
    }

    private func row(_ exercise: LibraryExercise, sessions: Int) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: exercise.group?.symbol ?? "dumbbell.fill", tint: exercise.isCustom ? Theme.sleep : Theme.strain, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.subheadline.weight(.semibold)).foregroundStyle(Color.primary)
                Text([exercise.musclesText, exercise.equipment.label].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if sessions > 0 {
                Text("\(sessions)×").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
            }
            if onPick != nil {
                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.strain)
            }
        }
    }

    private func chip(_ title: String, selected: Bool, tint: Color = Theme.strain, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background(selected ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color(uiColor: .secondarySystemGroupedBackground)),
                            in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Création d'un exercice perso : nom, muscles principaux / secondaires, matériel.
struct CustomExerciseForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    var initialName = ""
    var onCreated: (String) -> Void = { _ in }
    @State private var name = ""
    @State private var primary: Set<Muscle> = []
    @State private var secondary: Set<Muscle> = []
    @State private var equipment: Equipment = .machine

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nom de l'exercice", text: $name)
                Picker("Matériel", selection: $equipment) {
                    ForEach(Equipment.allCases) { Text($0.label).tag($0) }
                }
                Section("Muscles principaux") { muscleGrid($primary) }
                Section("Muscles secondaires (comptent pour ½)") { muscleGrid($secondary) }
            }
            .navigationTitle("Nouvel exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Créer") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || primary.isEmpty)
                }
            }
            .onAppear { if name.isEmpty { name = initialName } }
        }
    }

    private func muscleGrid(_ selection: Binding<Set<Muscle>>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(Muscle.allCases) { muscle in
                let on = selection.wrappedValue.contains(muscle)
                Button {
                    if on { selection.wrappedValue.remove(muscle) } else { selection.wrappedValue.insert(muscle) }
                } label: {
                    Text(muscle.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .background(on ? AnyShapeStyle(Theme.strain.gradient) : AnyShapeStyle(Color.secondary.opacity(0.12)), in: .capsule)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let clean = name.trimmingCharacters(in: .whitespaces)
        context.insert(CustomExercise(name: clean, primary: Array(primary), secondary: Array(secondary.subtracting(primary)),
                                      equipment: equipment))
        try? context.save()
        ExerciseLibrary.registerCustom((try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [])
        onCreated(clean)
        dismiss()
    }
}
