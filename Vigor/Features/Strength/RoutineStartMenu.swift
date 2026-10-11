import SwiftUI
import SwiftData

/// « Démarrer » : tu choisis une de tes séances types (ou une séance libre) au moment de commencer.
struct RoutineStartMenu: View {
    @Query(sort: \WorkoutRoutine.order) private var routines: [WorkoutRoutine]
    @State private var startingRoutine: WorkoutRoutine?
    @State private var startingFree = false
    var title = "Démarrer"

    var body: some View {
        Menu {
            if routines.isEmpty {
                Text("Crée tes séances types dans Sport → Musculation")
            }
            ForEach(routines) { routine in
                Button { startingRoutine = routine } label: {
                    Label(routine.name, systemImage: "dumbbell.fill")
                }
            }
            Divider()
            Button { startingFree = true } label: {
                Label("Séance libre", systemImage: "plus")
            }
        } label: {
            Label(title, systemImage: "play.fill").font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .accessibilityHint("Choisis la séance type à faire")
        .sheet(item: $startingRoutine) { routine in WorkoutLoggerView(routine: routine) }
        .sheet(isPresented: $startingFree) { WorkoutLoggerView() }
    }
}
