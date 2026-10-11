import SwiftUI
import UserNotifications
import SwiftData
import BackgroundTasks

@main
struct VigorApp: App {
    @State private var app = AppModel()
    let container: ModelContainer

    init() {
        container = SharedStore.container
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        VigorShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            AppearanceRoot()
                .environment(app)
                .environment(SyncService.shared)
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await app.backgroundRefresh(container: container)
        }
    }
}

/// Applique l'apparence choisie (clair par défaut) à toute l'app, feuilles comprises.
struct AppearanceRoot: View {
    @AppStorage(Appearance.storageKey) private var appearance = Appearance.light.rawValue

    var body: some View {
        ContentView()
            .preferredColorScheme((Appearance(rawValue: appearance) ?? .light).colorScheme)
    }
}

struct UndoItem: Identifiable {
    let id = UUID()
    let message: String
    let undo: @MainActor (ModelContext) -> Void
}

/// Base de données unique, partagée entre l'app et les Raccourcis Siri.
enum SharedStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: DailyWellness.self, CardioActivity.self, StrengthWorkout.self, StrengthSet.self,
                                      Unavailability.self, Injury.self, AthleteProfile.self, PlannedWorkout.self,
                                      FoodItem.self, FoodEntry.self, LifeActivity.self, Symptom.self, Shoe.self,
                                      Goal.self, PlanBaseline.self, Experiment.self,
                                      WorkoutRoutine.self, CustomExercise.self, SessionPlacement.self)
        } catch {
            fatalError("Base de données impossible à ouvrir : \(error)")
        }
    }()
}

/// État partagé de l'app (synchronisation, messages).
@MainActor
@Observable
final class AppModel {
    let health = HealthKitService()
    var isSyncing = false
    var statusMessage: String?
    /// Dernière saisie rapide annulable (bandeau « Annuler » quelques secondes).
    var undoItem: UndoItem?
    /// Incrémenté après chaque import : force le recalcul du coach.
    var dataVersion = 0
    @ObservationIgnored let snapshotCache = SnapshotCache()

    /// Date de la dernière synchronisation complète.
    var lastSync: Date {
        get { UserDefaults.standard.object(forKey: "sync.last") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "sync.last") }
    }

    var intervalsAPIKey: String {
        get { Keychain.get(IntervalsClient.apiKeyAccount) ?? "" }
        set { Keychain.set(newValue, for: IntervalsClient.apiKeyAccount) }
    }

    /// Synchronisation complète (Apple Santé puis Intervals.icu). Passe par `SyncGate` : jamais en même temps
    /// que la synchro du sommeil, la réparation de l'historique ou le réveil en arrière-plan.
    func syncAll(context: ModelContext, profile: AthleteProfile?, silent: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
        await SyncGate.run { [self] in
            await self.performSyncAll(context: context, profile: profile, silent: silent)
        }
    }

    /// Au premier plan (lancement, retour dans l'app) : sommeil du jour, réparation unique de l'historique,
    /// puis synchro complète si la dernière date de plus d'une heure — l'une après l'autre.
    func foregroundSync(context: ModelContext, profile: AthleteProfile?, sleep: SyncService) async {
        if !sleep.hasSyncedToday {
            await sleep.syncIfNeeded()
        }
        await repairSleepHistoryIfNeeded(context: context, profile: profile)
        if Date.now.timeIntervalSince(lastSync) > 3600 {
            await syncAll(context: context, profile: profile, silent: true)
        }
    }

    private func performSyncAll(context: ModelContext, profile: AthleteProfile?, silent: Bool) async {
        defer {
            isSyncing = false
            dataVersion += 1
        }
        var messages: [String] = []
        var hadError = false
        do {
            try await health.requestAuthorization()
            messages.append(try await DataStore.syncHealth(health, into: context, days: silent ? 30 : 365, thresholds: profile?.thresholds).summary)
        } catch {
            messages.append("Apple Santé : \(error.localizedDescription)")
            hadError = true
        }
        let key = intervalsAPIKey
        if !key.isEmpty {
            do {
                let client = IntervalsClient(apiKey: key, athleteID: profile?.intervalsAthleteID ?? "0")
                messages.append(try await DataStore.syncIntervals(client, into: context, days: silent ? 30 : 365))
            } catch {
                messages.append("Intervals.icu : \(error.localizedDescription)")
                hadError = true
            }
        }
        lastSync = .now
        // Synchronisation silencieuse : on n'affiche que les erreurs.
        if !silent || hadError {
            statusMessage = messages.joined(separator: "\n")
        }
    }

    static let refreshTaskID = "fr.leopold.vigor.refresh"

    /// Recalcule le coach depuis la base (hors affichage) : notifications et arrière-plan.
    func makeSnapshot(context: ModelContext) -> CoachSnapshot? {
        guard let profile = (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first else { return nil }
        return CoachSnapshot.build(
            profile: profile,
            wellness: (try? context.fetch(FetchDescriptor<DailyWellness>())) ?? [],
            activities: (try? context.fetch(FetchDescriptor<CardioActivity>())) ?? [],
            strength: (try? context.fetch(FetchDescriptor<StrengthWorkout>())) ?? [],
            unavailabilities: (try? context.fetch(FetchDescriptor<Unavailability>())) ?? [],
            injuries: (try? context.fetch(FetchDescriptor<Injury>())) ?? [],
            foods: (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? [],
            planned: (try? context.fetch(FetchDescriptor<PlannedWorkout>())) ?? [],
            lifeActivities: (try? context.fetch(FetchDescriptor<LifeActivity>())) ?? [],
            symptoms: (try? context.fetch(FetchDescriptor<Symptom>())) ?? [],
            shoes: (try? context.fetch(FetchDescriptor<Shoe>())) ?? [],
            baselines: (try? context.fetch(FetchDescriptor<PlanBaseline>())) ?? [],
            placements: (try? context.fetch(FetchDescriptor<SessionPlacement>())) ?? [])
    }

    func refreshNotifications(context: ModelContext) async {
        guard let snapshot = makeSnapshot(context: context) else { return }
        await NotificationScheduler.refresh(with: snapshot)
    }

    /// Demande à iOS de réveiller l'app tôt le matin pour préparer le bilan du jour : ce matin si l'heure
    /// (bilan − 1 h) n'est pas encore passée, sinon demain matin.
    func scheduleBackgroundRefresh(now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let offset = NotificationScheduler.morningMinutes - 60
        let todayAt = calendar.date(byAdding: .minute, value: offset, to: today) ?? now
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = todayAt > now ? todayAt : calendar.date(byAdding: .minute, value: offset, to: tomorrow)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Réveil en arrière-plan : synchronise Intervals.icu (et Apple Santé si l'iPhone est déverrouillé),
    /// puis envoie le bilan du matin adapté à la nuit.
    func backgroundRefresh(container: ModelContainer) async {
        scheduleBackgroundRefresh()
        await SyncGate.run { [self] in
            await self.performBackgroundRefresh(container: container)
        }
    }

    private func performBackgroundRefresh(container: ModelContainer) async {
        let context = container.mainContext
        let profile = (try? context.fetch(FetchDescriptor<AthleteProfile>()))?.first
        _ = try? await DataStore.syncHealth(health, into: context, days: 7, thresholds: profile?.thresholds)
        let key = intervalsAPIKey
        if !key.isEmpty {
            let client = IntervalsClient(apiKey: key, athleteID: profile?.intervalsAthleteID ?? "0")
            _ = try? await DataStore.syncIntervals(client, into: context, days: 7)
        }
        dataVersion += 1
        guard let snapshot = makeSnapshot(context: context) else { return }
        await NotificationScheduler.sendMorningBrief(snapshot)
        await NotificationScheduler.refresh(with: snapshot)
    }

    /// Propose d'annuler la dernière saisie pendant quelques secondes.
    func offerUndo(_ message: String, undo: @escaping @MainActor (ModelContext) -> Void) {
        undoItem = UndoItem(message: message, undo: undo)
    }

    func performUndo(context: ModelContext) {
        guard let item = undoItem else { return }
        undoItem = nil
        item.undo(context)
        try? context.save()
        dataVersion += 1
    }

    /// Une seule fois après la mise à jour : relit un an de nuits avec le bon découpage (coucher la veille au soir,
    /// siestes exclues de la nuit principale, sommeil Garmin séparé du sommeil Apple).
    func repairSleepHistoryIfNeeded(context: ModelContext, profile: AthleteProfile?) async {
        let key = "repair.sleepNights.v4"
        guard !UserDefaults.standard.bool(forKey: key), health.isAvailable else { return }
        await SyncGate.run { [self] in
            guard !UserDefaults.standard.bool(forKey: key) else { return }
            do {
                // Champs Apple remis à zéro puis relus (ils contenaient parfois des valeurs Garmin),
                // puis valeurs Garmin relues dans leurs propres champs.
                _ = try await DataStore.syncHealth(self.health, into: context, days: 365, thresholds: profile?.thresholds,
                                                   resetAppleFields: true)
                let apiKey = self.intervalsAPIKey
                if !apiKey.isEmpty {
                    let client = IntervalsClient(apiKey: apiKey, athleteID: profile?.intervalsAthleteID ?? "0")
                    _ = try? await DataStore.syncIntervals(client, into: context, days: 365)
                }
                UserDefaults.standard.set(true, forKey: key)
                self.dataVersion += 1
            } catch {
                // Données verrouillées ou accès refusé : on réessaiera au prochain lancement.
            }
        }
    }

    func importHevy(from url: URL, context: ModelContext) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let workouts = try HevyImporter.parse(text)
            let result = try DataStore.importHevy(workouts, into: context)
            dataVersion += 1
            statusMessage = "Hevy : \(result.added) nouvelle(s) séance(s), \(result.updated) mise(s) à jour."
        } catch {
            statusMessage = "Import Hevy impossible : \(error.localizedDescription)"
        }
    }
}
