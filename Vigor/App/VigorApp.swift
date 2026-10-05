import SwiftUI
import SwiftData

@main
struct VigorApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(app)
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [
            DailyWellness.self,
            CardioActivity.self,
            StrengthWorkout.self,
            StrengthSet.self,
            Unavailability.self,
            Injury.self,
            AthleteProfile.self,
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

    func syncHealth(context: ModelContext) async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await health.requestAuthorization()
            let report = try await DataStore.syncHealth(health, into: context)
            statusMessage = report.summary
        } catch {
            statusMessage = "Synchronisation impossible : \(error.localizedDescription)"
        }
    }

    func importHevy(from url: URL, context: ModelContext) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let workouts = try HevyImporter.parse(text)
            let result = try DataStore.importHevy(workouts, into: context)
            statusMessage = "Hevy : \(result.added) nouvelle(s) séance(s), \(result.updated) mise(s) à jour."
        } catch {
            statusMessage = "Import Hevy impossible : \(error.localizedDescription)"
        }
    }
}
