import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Query private var profiles: [AthleteProfile]
    @State private var selection: AppTab = .today
    @State private var showQuickAdd = false

    enum AppTab: Hashable {
        case today, activity, health, nutrition, add
    }

    var body: some View {
        // Barre d'onglets flottante d'iOS 26 ; l'onglet « + » (rôle recherche) est le bouton rond séparé, comme dans Bevel.
        TabView(selection: $selection) {
            Tab("Accueil", systemImage: "house.fill", value: AppTab.today) { TodayView() }
            Tab("Santé", systemImage: "heart.fill", value: AppTab.health) { RecoveryView() }
            Tab("Activité", systemImage: "figure.outdoor.cycle", value: AppTab.activity) { TrainingView() }
            Tab("Nutrition", systemImage: "fork.knife", value: AppTab.nutrition) { NutritionView() }
            Tab("Ajouter", systemImage: "plus", value: AppTab.add, role: .search) { QuickAddView() }
        }
        .tint(Theme.strain)
        .onChange(of: selection) { old, new in
            // Le « + » ouvre la feuille d'ajout rapide sans quitter l'écran en cours.
            if new == .add {
                selection = old
                showQuickAdd = true
            }
        }
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView(isSheet: true)
                .presentationDetents([.medium, .large])
        }
        .task {
            if profiles.isEmpty {
                context.insert(AthleteProfile())
                try? context.save()
            }
            ExerciseLibrary.registerCustom((try? context.fetch(FetchDescriptor<CustomExercise>())) ?? [])
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
