import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncService.self) private var sync
    @Query private var profiles: [AthleteProfile]
    @State private var selection: AppTab = .today
    @State private var showQuickAdd = false
    /// Accueil en 3 écrans au premier lancement (déjà vu, ou app déjà utilisée = pas d'accueil).
    @AppStorage("onboarding.done") private var onboardingDone = false

    enum AppTab: Hashable {
        case today, activity, health, nutrition, add
    }

    var body: some View {
        // Barre d'onglets flottante d'iOS 26 ; l'onglet « + » (rôle recherche) est le bouton rond séparé, comme dans Bevel.
        TabView(selection: $selection) {
            Tab("Aujourd'hui", systemImage: "sun.max.fill", value: AppTab.today) { TodayView() }
            Tab("Santé", systemImage: "heart.fill", value: AppTab.health) { RecoveryView() }
            Tab("Sport", systemImage: "figure.outdoor.cycle", value: AppTab.activity) { TrainingView() }
            Tab("Nutrition", systemImage: "fork.knife", value: AppTab.nutrition) { NutritionView() }
            Tab("Ajouter", systemImage: "plus", value: AppTab.add, role: .search) { QuickAddView() }
        }
        .tint(Theme.accent)
        .overlay(alignment: .bottom) {
            if let item = app.undoItem {
                UndoToast(message: item.message) { app.performUndo(context: context) }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: item.id) {
                        try? await Task.sleep(for: .seconds(5))
                        if app.undoItem?.id == item.id { withAnimation { app.undoItem = nil } }
                    }
            }
        }
        .animation(.snappy, value: app.undoItem?.id)
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
            // App déjà utilisée avant cette version : pas d'accueil.
            if !onboardingDone,
               ((try? context.fetchCount(FetchDescriptor<DailyWellness>())) ?? 0) > 0 || !app.intervalsAPIKey.isEmpty {
                onboardingDone = true
            }
            // Pas de demande de notifications au premier lancement : elle vient quand tu actives un rappel
            // (Réglages) ou valides ta première série (`NotificationScheduler.requestAuthorizationIfNeeded`).
            app.scheduleBackgroundRefresh()
            // Pendant l'accueil, pas de synchro (ni de demande Apple Santé) : elle part à la fin de l'accueil.
            if onboardingDone {
                await app.foregroundSync(context: context, profile: profiles.first, sleep: sync)
            }
        }
        // Premier lancement : accueil en 3 écrans, puis la première synchro.
        .fullScreenCover(isPresented: Binding(get: { !onboardingDone }, set: { if !$0 { onboardingDone = true } })) {
            OnboardingView {
                onboardingDone = true
                Task {
                    await app.foregroundSync(context: context, profile: profiles.first, sleep: sync)
                    // Clé Garmin saisie à l'accueil : un an d'historique d'un coup.
                    if !app.intervalsAPIKey.isEmpty { await app.syncAll(context: context, profile: profiles.first) }
                }
            }
        }
        .onChange(of: sync.lastSyncDate) {
            app.dataVersion += 1
        }
        .task(id: app.dataVersion) {
            await app.refreshNotifications(context: context)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, onboardingDone {
                app.scheduleBackgroundRefresh()
                // Retour dans l'app (ex. le lendemain) : mêmes synchros, en série, puis notifications.
                Task {
                    await app.foregroundSync(context: context, profile: profiles.first, sleep: sync)
                    await app.refreshNotifications(context: context)
                }
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
