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
        static let alertsEnabled = "notif.alerts.enabled"
        static func mealEnabled(_ meal: Meal) -> String { "notif.meal.\(meal.rawValue).enabled" }
        static func mealMinutes(_ meal: Meal) -> String { "notif.meal.\(meal.rawValue).minutes" }
    }

    /// Repas qui ont un rappel (pas « pendant l'effort »).
    static let remindedMeals: [Meal] = [.breakfast, .lunch, .snack, .dinner]

    static func defaultMinutes(for meal: Meal) -> Int {
        switch meal {
        case .breakfast: 7 * 60 + 45
        case .lunch: 12 * 60 + 15
        case .snack: 16 * 60 + 30
        case .dinner, .training: 19 * 60 + 30
        }
    }

    static func mealEnabled(_ meal: Meal) -> Bool {
        UserDefaults.standard.object(forKey: Keys.mealEnabled(meal)) as? Bool ?? true
    }

    static func mealMinutes(_ meal: Meal) -> Int {
        UserDefaults.standard.object(forKey: Keys.mealMinutes(meal)) as? Int ?? defaultMinutes(for: meal)
    }

    /// Part des apports du jour visée à chaque repas.
    static func share(of meal: Meal) -> Double {
        switch meal {
        case .breakfast: 0.25
        case .lunch: 0.30
        case .snack: 0.15
        case .dinner: 0.30
        case .training: 0
        }
    }

    static var morningEnabled: Bool { UserDefaults.standard.object(forKey: Keys.morningEnabled) as? Bool ?? true }
    static var eveningEnabled: Bool { UserDefaults.standard.object(forKey: Keys.eveningEnabled) as? Bool ?? true }
    /// Minutes après minuit (7 h 15 par défaut).
    static var morningMinutes: Int { UserDefaults.standard.object(forKey: Keys.morningMinutes) as? Int ?? 7 * 60 + 15 }
    /// Minutes après minuit (21 h 30 par défaut).
    static var eveningMinutes: Int { UserDefaults.standard.object(forKey: Keys.eveningMinutes) as? Int ?? 21 * 60 + 30 }

    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Reprogramme les notifications à partir du dernier calcul du coach.
    static func refresh(with snapshot: CoachSnapshot, now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }
        let pending = await center.pendingNotificationRequests()
        let mealIDs = pending.map(\.identifier).filter { $0.hasPrefix("vigor.meal.") }
        center.removePendingNotificationRequests(withIdentifiers: [morningID, eveningID] + mealIDs)

        let calendar = Calendar.current
        if morningEnabled, let content = morningFallback(snapshot) {
            // Matin de demain : séance prévue. Le contenu est remplacé par le vrai bilan si l'app
            // se réveille en arrière-plan avant (synchronisation Intervals.icu).
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            schedule(id: morningID, content: content, at: tomorrow, minutes: morningMinutes)
        }
        scheduleMeals(snapshot, now: now)
        scheduleWeeklyReport(snapshot, now: now)
        await sendThresholdAlerts(snapshot, now: now)
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
        lines.append("Besoin de sommeil cette nuit : \(snapshot.sleepNeed.total.hoursText). Couche-toi vers \(snapshot.sleepNeed.bedtimeText).")
        guard !lines.isEmpty else { return nil }
        let content = UNMutableNotificationContent()
        content.title = "Bilan du soir"
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        return content
    }

    // MARK: Bilan hebdomadaire

    /// Le dimanche à 19 h : bilan des 7 derniers jours.
    private static func scheduleWeeklyReport(_ snapshot: CoachSnapshot, now: Date) {
        guard eveningEnabled, let report = snapshot.weeklyReport else { return }
        let calendar = Calendar.current
        var components = DateComponents()
        components.weekday = 1
        components.hour = 19
        components.minute = 0
        guard let next = calendar.nextDate(after: now, matching: components, matchingPolicy: .nextTime) else { return }
        let content = UNMutableNotificationContent()
        content.title = "Ton bilan de la semaine"
        var lines: [String] = []
        if let recovery = report.current.recovery { lines.append(String(format: "Récup moyenne %.0f", recovery)) }
        if let effort = report.current.effort { lines.append(String(format: "effort moyen %.1f/21", effort)) }
        if let sleep = report.current.sleepHours { lines.append(String(format: "sommeil %.1f h", sleep)) }
        content.body = ([lines.joined(separator: " · ")] + report.highlights.prefix(2)).joined(separator: "\n")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: next), repeats: false)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["vigor.weekly"])
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "vigor.weekly", content: content, trigger: trigger))
    }

    // MARK: Alertes de seuil

    /// Seuils importants seulement : surcharge, surmenage, dette de sommeil, symptôme récurrent.
    static let alertIDs: [String] = ["load.acwr", "load.form", "recovery.overreaching", "sleep.debt", "discipline.", "symptom.", "illness."]

    private static func sendThresholdAlerts(_ snapshot: CoachSnapshot, now: Date) async {
        guard UserDefaults.standard.object(forKey: Keys.alertsEnabled) as? Bool ?? true else { return }
        let dayKey = Calendar.current.startOfDay(for: now).timeIntervalSince1970
        for insight in snapshot.insights where insight.severity == .warning {
            guard alertIDs.contains(where: { insight.id.hasPrefix($0) }) else { continue }
            let key = "notif.alert.\(insight.id)"
            guard UserDefaults.standard.double(forKey: key) != dayKey else { continue }
            let content = UNMutableNotificationContent()
            content.title = "⚠️ \(insight.title)"
            content.body = ([insight.evidence.first].compactMap { $0 } + [insight.recommendation]).joined(separator: "\n")
            content.sound = .default
            let request = UNNotificationRequest(identifier: "vigor.alert.\(insight.id)", content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
            UserDefaults.standard.set(dayKey, forKey: key)
        }
    }

    // MARK: Repas

    /// Rappels de repas pour aujourd'hui (s'ils ne sont pas encore renseignés) et demain.
    private static func scheduleMeals(_ snapshot: CoachSnapshot, now: Date) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        for meal in remindedMeals where mealEnabled(meal) {
            let minutes = mealMinutes(meal)
            let todayAt = calendar.date(byAdding: .minute, value: minutes, to: today) ?? today
            if todayAt > now, !snapshot.loggedMealsToday.contains(meal),
               let content = mealContent(meal, snapshot: snapshot, forTomorrow: false) {
                schedule(id: "vigor.meal.\(meal.rawValue).today", content: content, at: today, minutes: minutes)
            }
            if let content = mealContent(meal, snapshot: snapshot, forTomorrow: true) {
                schedule(id: "vigor.meal.\(meal.rawValue).tomorrow", content: content, at: tomorrow, minutes: minutes)
            }
        }
    }

    /// Contenu d'un rappel de repas : quantités visées + conseil adapté aux séances de la journée.
    static func mealContent(_ meal: Meal, snapshot: CoachSnapshot, forTomorrow: Bool) -> UNMutableNotificationContent? {
        guard let targets = snapshot.macroTargets else {
            let content = UNMutableNotificationContent()
            content.title = meal.label
            content.body = "Pense à noter ton repas dans Vigor."
            content.sound = .default
            return content
        }
        let sessions = forTomorrow ? snapshot.tomorrowPlan : snapshot.brief.adapted
        let mealShare = share(of: meal)

        // Aujourd'hui : on répartit ce qui reste sur les repas restants. Demain : part standard.
        var kcal = targets.kcal * mealShare
        var protein = targets.protein * mealShare
        var carbs = targets.carbs * mealShare
        if !forTomorrow {
            let remainingMeals = remindedMeals.filter { !snapshot.loggedMealsToday.contains($0) && mealMinutes($0) >= mealMinutes(meal) }
            let remainingShare = remainingMeals.reduce(0.0) { $0 + Self.share(of: $1) }
            if remainingShare > 0 {
                let factor = mealShare / remainingShare
                kcal = max(0, targets.kcal - snapshot.todayNutrition.kcal) * factor
                protein = max(0, targets.protein - snapshot.todayNutrition.protein) * factor
                carbs = max(0, targets.carbs - snapshot.todayNutrition.carbs) * factor
            }
        }

        var lines = [String(format: "Vise ~%.0f kcal · %.0f g de protéines · %.0f g de glucides.", kcal, protein, carbs)]
        if let tip = mealTip(meal, sessions: sessions, tomorrowSessions: snapshot.tomorrowPlan, forTomorrow: forTomorrow) {
            lines.append(tip)
        }
        let content = UNMutableNotificationContent()
        content.title = "\(meal.label) · Vigor"
        content.body = lines.joined(separator: "\n")
        content.sound = .default
        return content
    }

    /// Conseil selon le moment de la séance : avant = glucides, après = protéines + glucides.
    static func mealTip(_ meal: Meal, sessions: [SessionPrescription], tomorrowSessions: [SessionPrescription], forTomorrow: Bool) -> String? {
        let intense = sessions.first { $0.kind.isIntense }
        let long = sessions.first { $0.kind == .longRide || ($0.kind.isBike && $0.minutes >= 150) }
        let strength = sessions.first { $0.kind.isStrength }
        switch meal {
        case .breakfast:
            if let long { return "\(long.title) aujourd'hui : petit-déjeuner riche en glucides (flocons d'avoine, pain, miel, banane)." }
            if let intense { return "\(intense.title) aujourd'hui : garde des glucides à chaque repas pour avoir du jus." }
            return "Une source de protéines dès le matin (skyr, œufs, fromage blanc) aide la prise de muscle."
        case .lunch:
            if let intense { return "\(intense.title) plus tard : déjeuner riche en glucides (riz, pâtes, pommes de terre), léger en graisses." }
            if let strength { return "Séance \(strength.kind.label.lowercased()) aujourd'hui : protéines + glucides au déjeuner." }
            return "Assiette équilibrée : ½ légumes, ¼ féculents, ¼ protéines."
        case .snack:
            if intense != nil || long != nil { return "Séance à venir : collation glucidique 1 h avant (banane, dattes, barre de céréales)." }
            if strength != nil { return "Avant/après la muscu : 20–30 g de protéines (skyr, shaker) + un fruit." }
            return "Collation protéinée : skyr, amandes ou fromage blanc."
        case .dinner:
            if let next = tomorrowSessions.first(where: { $0.kind == .longRide || $0.kind.isIntense }), !forTomorrow {
                return "\(next.title) demain : dîner riche en glucides ce soir pour remplir les réserves."
            }
            if strength != nil || intense != nil { return "Récupération : protéines (poulet, poisson, œufs) + glucides pour reconstruire." }
            return "Protéines au dîner : elles nourrissent les muscles pendant la nuit."
        case .training:
            return nil
        }
    }

    private static func schedule(id: String, content: UNMutableNotificationContent, at day: Date, minutes: Int) {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = minutes / 60
        components.minute = minutes % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }
}
