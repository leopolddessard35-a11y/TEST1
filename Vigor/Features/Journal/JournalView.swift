import SwiftUI
import SwiftData

/// Onglet Journal : tout ce que tu saisis (repas, effort ressenti, symptômes, activité hors sport).
struct JournalView: View {
    enum Segment: String, CaseIterable {
        case meals = "Repas"
        case effort = "Effort"
        case symptoms = "Symptômes"
        case life = "Hors sport"
    }

    @State private var segment: Segment = .meals

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Journal", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch segment {
                    case .meals: NutritionContent()
                    case .effort: EffortJournal()
                    case .symptoms:
                        SnapshotReader { _, snapshot in JournalSection(patterns: snapshot.symptomPatterns) }
                    case .life:
                        SnapshotReader { _, snapshot in LifeSection(lifeLoad7: snapshot.lifeLoad7) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Journal")
        }
    }
}

/// Effort ressenti des 14 derniers jours : un slider par séance.
private struct EffortJournal: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \CardioActivity.start, order: .reverse) private var activities: [CardioActivity]
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]

    var body: some View {
        let cutoff = Date.now.addingTimeInterval(-14 * 86_400)
        let recentActivities = activities.filter { $0.start >= cutoff }
        let recentWorkouts = workouts.filter { $0.start >= cutoff }
        VStack(spacing: 12) {
            GlassCard {
                Text("L'effort ressenti (RPE) × la durée donne la charge sRPE : une monnaie commune entre vélo, course, muscu et travaux. Il corrige aussi les capteurs quand une séance facile paraît dure.")
                    .font(.footnote)
            }
            if recentActivities.isEmpty && recentWorkouts.isEmpty {
                EmptyStateCard(title: "Aucune séance récente", message: "Synchronise ou importe tes séances pour noter l'effort ressenti.", symbol: "gauge.with.dots.needle.67percent")
            }
            ForEach(recentActivities) { activity in
                GlassCard {
                    RPERow(title: activity.title, date: activity.start, value: activity.rpe) { value in
                        activity.rpe = value
                        save()
                    }
                }
            }
            ForEach(recentWorkouts) { workout in
                GlassCard {
                    RPERow(title: workout.title, date: workout.start, value: workout.rpe) { value in
                        workout.rpe = value
                        save()
                    }
                }
            }
        }
    }

    private func save() {
        try? context.save()
        app.dataVersion += 1
    }
}
