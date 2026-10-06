import ActivityKit
import Foundation

/// Minuteur de repos affiché dans la Dynamic Island et sur l'écran verrouillé.
/// À partager avec l'extension VigorWidgets si elle est réactivée (voir Extras/VigorWidgets).
struct RestTimerAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Début et fin du repos en cours.
        var start: Date
        var end: Date
        /// Exercice qui vient d'être fait.
        var exercise: String
        /// Prochaine série (« Série 3/4 · 60 kg × 8 »).
        var next: String
    }

    /// Nom de la séance (« Push »…).
    var workoutTitle: String
}
