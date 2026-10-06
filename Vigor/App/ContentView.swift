import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        TabView {
            Tab("Aujourd'hui", systemImage: "sun.max.fill") { TodayView() }
            Tab("Charge", systemImage: "figure.outdoor.cycle") { TrainingView() }
            Tab("Récup", systemImage: "heart.fill") { RecoveryView() }
            Tab("Nutrition", systemImage: "fork.knife") { NutritionView() }
            Tab("Plan", systemImage: "calendar") { PlanView() }
        }
        .task {
            if profiles.isEmpty {
                context.insert(AthleteProfile())
                try? context.save()
            }
            _ = await NotificationScheduler.requestAuthorization()
            app.scheduleBackgroundRefresh()
        }
        .task(id: app.dataVersion) {
            await app.refreshNotifications(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                app.scheduleBackgroundRefresh()
                // Synchronisation automatique si la dernière date de plus d'une heure.
                if Date.now.timeIntervalSince(app.lastSync) > 3600 {
                    Task { await app.syncAll(context: context, profile: profiles.first, silent: true) }
                }
                Task { await app.refreshNotifications(context: context) }
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
