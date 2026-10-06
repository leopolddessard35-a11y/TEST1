import ActivityKit
import Foundation
import UserNotifications

/// Minuteur de repos : Live Activity (Dynamic Island, écran verrouillé) + notification de fin.
@MainActor
enum RestTimer {
    private static let notificationID = "vigor.rest"

    /// Live Activity (Dynamic Island) désactivée : l'extension VigorWidgets prendrait une 4e place
    /// d'app sur le compte gratuit. Pour la réactiver, voir Extras/VigorWidgets/README.md.
    static let liveActivityEnabled = false

    static func start(start: Date = .now, end: Date, exercise: String, next: String, workout: String) {
        scheduleNotification(at: end, next: next)
        guard liveActivityEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestTimerAttributes.ContentState(start: start, end: end, exercise: exercise, next: next)
        let content = ActivityContent(state: state, staleDate: end)
        if let current = Activity<RestTimerAttributes>.activities.first {
            Task { await current.update(content) }
        } else {
            do {
                _ = try Activity.request(attributes: RestTimerAttributes(workoutTitle: workout), content: content, pushType: nil)
            } catch {
                // Live Activities désactivées dans Réglages : la notification suffit.
            }
        }
    }

    static func stop() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard liveActivityEnabled else { return }
        for activity in Activity<RestTimerAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    private static func scheduleNotification(at date: Date, next: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [notificationID])
        guard date > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Repos terminé"
        content.body = next.isEmpty ? "Prochaine série." : next
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger))
    }
}
