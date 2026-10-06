import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct VigorApp: App {
    @State private var app = AppModel()
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: DailyWellness.self, CardioActivity.self, StrengthWorkout.self, StrengthSet.self,
                                           Unavailability.self, Injury.self, AthleteProfile.self, PlannedWorkout.self,
                                           FoodItem.self, FoodEntry.self, LifeActivity.self, Symptom.self, Shoe.self,
                                           Goal.self, PlanBaseline.self)
        } catch {
            fatalError("Base de données impossible à ouvrir : \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
        }
        .modelContainer(container)
        .backgroundTask(.appRefresh(AppModel.refreshTaskID)) {
            await app.backgroundRefresh(container: container)
        }
    }
}

/// État partagé de l'app (synchronisation, messages).
@MainActor
@Observable
final class AppModel {
    let health = HealthKitService()
    var isSyncing = false
    var statusMessage: String?
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

    func syncAll(context: ModelContext, profile: AthleteProfile?, silent: Bool = false) async {
        guard !isSyncing else { return }
        isSyncing = true
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
            shoes: (try? context.fetch(FetchDescriptor<Shoe>())) ?? [])
    }

    func refreshNotifications(context: ModelContext) async {
        guard let snapshot = makeSnapshot(context: context) else { return }
        await NotificationScheduler.refresh(with: snapshot)
    }

    /// Demande à iOS de réveiller l'app tôt le matin pour préparer le bilan du jour.
    func scheduleBackgroundRefresh() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = calendar.date(byAdding: .minute, value: NotificationScheduler.morningMinutes - 60, to: tomorrow)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Réveil en arrière-plan : synchronise Intervals.icu (et Apple Santé si l'iPhone est déverrouillé),
    /// puis envoie le bilan du matin adapté à la nuit.
    func backgroundRefresh(container: ModelContainer) async {
        scheduleBackgroundRefresh()
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
