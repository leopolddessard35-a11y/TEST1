import AudioToolbox
import UIKit
import UserNotifications

/// Retours sonores et vibrations (fonctionnent sans extension ni réglage particulier).
@MainActor
enum Feedback {
    /// Fin du repos : vibration « succès » + son d'alerte (le son suit le bouton silence, la vibration non).
    static func restFinished() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        AudioServicesPlayAlertSound(SystemSoundID(1005))
    }

    /// Petit tic des 3 dernières secondes du repos.
    static func tick() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Série validée.
    static func setDone() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}

/// Affiche les notifications même quand Vigor est ouverte (sinon iOS les rend muettes au premier plan).
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Fin de repos : l'écran de séance joue déjà son et vibration, la bannière suffit.
        if notification.request.identifier == "vigor.rest" {
            completionHandler([.banner, .list])
        } else {
            completionHandler([.banner, .sound, .list])
        }
    }
}
