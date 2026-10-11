import SwiftUI
import SwiftData

/// « Démarrer » : tu choisis une de tes séances types (ou une séance libre) au moment de commencer.
/// La feuille de séance est présentée par l'écran parent (`onPick(nil)` = séance libre), pour qu'elle
/// ne se ferme pas si la ligne qui contient ce bouton est recalculée pendant la séance.
struct RoutineStartMenu: View {
    @Query(sort: \WorkoutRoutine.order) private var routines: [WorkoutRoutine]
    var title = "Démarrer"
    let onPick: (WorkoutRoutine?) -> Void

    var body: some View {
        Menu {
            if routines.isEmpty {
                Text("Crée tes séances types dans Sport → Musculation")
            }
            ForEach(routines) { routine in
                Button { onPick(routine) } label: {
                    Label(routine.name, systemImage: "dumbbell.fill")
                }
            }
            Divider()
            Button { onPick(nil) } label: {
                Label("Séance libre", systemImage: "plus")
            }
        } label: {
            Label(title, systemImage: "play.fill").font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .accessibilityHint("Choisis la séance type à faire")
    }
}
