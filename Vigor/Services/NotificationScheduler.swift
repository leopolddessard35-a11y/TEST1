import Foundation
import UserNotifications

/// Notifications locales (fonctionnent avec un compte Apple gratuit).
enum NotificationScheduler {
    static let morningID = "vigor.morning"
    static let eveningID = "vigor.evening"

    enum Keys {
        static let morningEnabled = "notif.morning.enabled"
        static let morningMinutes = "notif.morning.minutes"
        static let eveningEnabled = "notif.evening.enabled"
        static let eveningMinutes = "notif.evening.minutes"
        static let lastMorningBrief = "notif.morning.lastBriefDay"
    }

    static var morningEnabled: Bool { UserDefaults.standard.object(forKey: Keys.morningEnabled) as? Bool ?? true }
    static var eveningEnabled: Bool { UserDefaults.standard.object(forKey: Keys.eveningEnabled) as? Bool ?? true }
    /// Minutes après minuit (7 h 15 par défaut).
    static var morningMinutes: Int { UserDefaults.standard.object(forKey: Keys.morningMinutes) as? Int ?? 7 * 60 + 15 }
    /// Minutes après minuit (20 h 30 par défaut).
    static var eveningMinutes: Int { UserDefaults.standard.object(forKey: Keys.eveningMinutes) as? Int ?? 20 * 60 + 30 }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Reprogramme les notifications à partir du dernier calcul du coach.
    static func refresh(with snapshot: CoachSnapshot, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        center.removePendingNotificationRequests(withIdentifiers: [morningID, eveningID])

        let calendar = Calendar.current
        if morningEnabled, let content = morningFallback(snapshot) {
            // Matin de demain : séance prévue. Le contenu est remplacé par le vrai bilan si l'app
            // se réveille en arrière-plan avant (synchronisation Intervals.icu).
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            schedule(id: morningID, content: content, at: tomorrow, minutes: morningMinutes)
        }
        if eveningEnabled, let content = evening(snapshot) {
            let todayAt = calendar.date(byAdding: .minute, value: eveningMinutes, to: calendar.startOfDay(for: now)) ?? now
            if todayAt > now {
                schedule(id: eveningID, content: content, at: calendar.startOfDay(for: now), minutes: eveningMinutes)
            }
        }
    }

    /// Bilan du matin, envoyé tout de suite (depuis la synchronisation en arrière-plan).
    static func sendMorningBrief(_ snapshot: CoachSnapshot, now: Date = .now) async {
        guard morningEnabled else { return }
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let dayKey = calendar.startOfDay(for: now).timeIntervalSince1970
        guard minutes >= morningMinutes - 90, minutes <= 11 * 60,
              UserDefaults.standard.double(forKey: Keys.lastMorningBrief) != dayKey else { return }

        let brief = snapshot.brief
        let content = UNMutableNotificationContent()
        let score = snapshot.readiness.map { " · récup \($0.score)" } ?? ""
        content.title = "\(brief.verdict.label)\(score)"
        var lines = [brief.headline]
        if let session = brief.adapted.first { lines.append("→ \(session.title)") }
        if let priority = brief.priorities.first { lines.append(priority) }
        content.body = lines.joined(separator: "\n")
        content.sound = .default

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [morningID])
        let request = UNNotificationRequest(identifier: morningID, content: content, trigger: nil)
        try? await center.add(request)
        UserDefaults.standard.set(dayKey, forKey: Keys.lastMorningBrief)
    }

    private static func morningFallback(_ snapshot: CoachSnapshot) -> UNMutableNotificationContent? {
        guard !snapshot.tomorrowPlan.isEmpty else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Ta journée d'entraînement"
        let sessions = snapshot.tomorrowPlan.map(\.title).joined(separator: " + ")
        content.body = "Prévu : \(sessions).\nOuvre Vigor : j'adapte la séance à ta nuit, ta récup et ce que tu as mangé."
        content.sound = .default
        return content
    }

    /// Le soir : protéines manquantes, préparation de la séance du lendemain, coucher.
    private static func evening(_ snapshot: CoachSnapshot) -> UNMutableNotificationContent? {
        var lines: [String] = []
        if let targets = snapshot.macroTargets, snapshot.todayNutrition.kcal > 300 {
            let missingProtein = targets.protein - snapshot.todayNutrition.protein
            if missingProtein > 20 {
                lines.append(String(format: "Il te manque %.0f g de protéines (ex. 250 g de skyr ou 150 g de poulet).", missingProtein))
            }
            let missingKcal = targets.kcal - snapshot.todayNutrition.kcal
            if missingKcal > 500 {
                lines.append(String(format: "Encore %.0f kcal pour ton objectif de prise de masse.", missingKcal))
            }
        }
        let tomorrowBike = snapshot.tomorrowPlan.filter { $0.kind.isBike }
        if let long = tomorrowBike.first(where: { $0.kind == .longRide || $0.minutes >= 150 }) {
            lines.append("Demain : \(long.title). Dîner riche en glucides ce soir (riz, pâtes, pommes de terre).")
        } else if let key = tomorrowBike.first(where: { $0.kind.isIntense }) {
            lines.append("Demain : \(key.title). Au lit tôt : une nuit de moins de 6 h supprimerait l'intensité.")
        }
        if snapshot.readiness?.level == .low {
            lines.append("Récupération basse aujourd'hui : vise 8 h de sommeil cette nuit.")
        }
        guard !lines.isEmpty else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Bilan du soir"
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        return content
    }

    private static func schedule(id: String, content: UNMutableNotificationContent, at day: Date, minutes: Int) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
