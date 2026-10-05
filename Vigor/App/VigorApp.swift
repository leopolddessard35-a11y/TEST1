import SwiftUI
import SwiftData

@main
struct VigorApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
        }
        .modelContainer(for: [
            DailyWellness.self,
            CardioActivity.self,
            StrengthWorkout.self,
            StrengthSet.self,
            Unavailability.self,
            Injury.self,
            AthleteProfile.self,
            PlannedWorkout.self,
            FoodItem.self,
            FoodEntry.self,
        ])
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

    var intervalsAPIKey: String {
        get { Keychain.get(IntervalsClient.apiKeyAccount) ?? "" }
        set { Keychain.set(newValue, for: IntervalsClient.apiKeyAccount) }
    }

    func syncAll(context: ModelContext, profile: AthleteProfile?) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer {
            isSyncing = false
            dataVersion += 1
        }
        var messages: [String] = []
        do {
            try await health.requestAuthorization()
            messages.append(try await DataStore.syncHealth(health, into: context).summary)
        } catch {
            messages.append("Apple Santé : \(error.localizedDescription)")
        }
        let key = intervalsAPIKey
        if !key.isEmpty {
            do {
                let client = IntervalsClient(apiKey: key, athleteID: profile?.intervalsAthleteID ?? "0")
                messages.append(try await DataStore.syncIntervals(client, into: context))
            } catch {
                messages.append("Intervals.icu : \(error.localizedDescription)")
            }
        }
        statusMessage = messages.joined(separator: "\n")
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
