import AppIntents
import SwiftData
import Foundation

/// « Dis Siri, note mon effort dans Vigor » : RPE de la dernière séance.
struct LogEffortIntent: AppIntent {
    static var title: LocalizedStringResource = "Noter l'effort ressenti"
    static var description = IntentDescription("Enregistre le RPE (1 à 10) de ta dernière séance.")

    @Parameter(title: "Effort (1–10)", inclusiveRange: (1, 10))
    var rpe: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SharedStore.container.mainContext
        var activityDescriptor = FetchDescriptor<CardioActivity>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        activityDescriptor.fetchLimit = 1
        var workoutDescriptor = FetchDescriptor<StrengthWorkout>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        workoutDescriptor.fetchLimit = 1
        let activity = try? context.fetch(activityDescriptor).first
        let workout = try? context.fetch(workoutDescriptor).first
        if let activity, activity.start >= (workout?.start ?? .distantPast) {
            activity.rpe = rpe
            try? context.save()
            return .result(dialog: "Effort \(rpe) sur 10 noté pour \(activity.title).")
        }
        if let workout {
            workout.rpe = rpe
            try? context.save()
            return .result(dialog: "Effort \(rpe) sur 10 noté pour \(workout.title).")
        }
        return .result(dialog: "Aucune séance récente à noter.")
    }
}

/// « Dis Siri, ajoute de l'eau dans Vigor ».
struct AddWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Ajouter de l'eau"
    static var description = IntentDescription("Ajoute un verre ou une gourde à ton hydratation du jour.")

    @Parameter(title: "Quantité (ml)", default: 500)
    var milliliters: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        QuickActions.addWater(Double(milliliters), context: SharedStore.container.mainContext)
        return .result(dialog: "\(milliliters) ml ajoutés.")
    }
}

/// « Dis Siri, quel est mon plan du jour dans Vigor ».
struct TodayVerdictIntent: AppIntent {
    static var title: LocalizedStringResource = "Plan du jour"
    static var description = IntentDescription("Donne le verdict du jour (go, adapter, repos) et la séance conseillée.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel()
        guard let snapshot = model.makeSnapshot(context: SharedStore.container.mainContext) else {
            return .result(dialog: "Ouvre Vigor une première fois pour configurer ton profil.")
        }
        return .result(dialog: "\(snapshot.brief.verdict.label). \(snapshot.brief.headline)")
    }
}

struct VigorShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: TodayVerdictIntent(), phrases: ["Quel est mon plan du jour dans \(.applicationName)",
                                                            "Verdict du jour \(.applicationName)"],
                    shortTitle: "Plan du jour", systemImageName: "sun.max.fill")
        AppShortcut(intent: LogEffortIntent(), phrases: ["Note mon effort dans \(.applicationName)"],
                    shortTitle: "Noter l'effort", systemImageName: "gauge.with.dots.needle.67percent")
        AppShortcut(intent: AddWaterIntent(), phrases: ["Ajoute de l'eau dans \(.applicationName)"],
                    shortTitle: "Ajouter de l'eau", systemImageName: "drop.fill")
    }
}
