import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        TabView {
            Tab("Aujourd'hui", systemImage: "sun.max.fill") { TodayView() }
            Tab("Entraînement", systemImage: "figure.strengthtraining.traditional") { TrainingView() }
            Tab("Plan", systemImage: "calendar") { PlanView() }
            Tab("Nutrition", systemImage: "fork.knife") { NutritionView() }
            Tab("Réglages", systemImage: "gearshape.fill") { SettingsView() }
        }
        .task {
            if profiles.isEmpty {
                context.insert(AthleteProfile())
                try? context.save()
            }
        }
        .alert("Vigor", isPresented: Binding(
            get: { app.statusMessage != nil },
            set: { if !$0 { app.statusMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(app.statusMessage ?? "")
        }
    }
}
