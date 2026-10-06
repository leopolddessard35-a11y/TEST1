import Foundation

/// Une ou deux phrases simples, recalculées à chaque ouverture : est-ce que ça va aujourd'hui, et quoi en faire.
enum CoachSummary {
    struct Result: Equatable {
        let text: String
        /// Libellé de la pastille (tient compte d'un jour de repos prévu).
        let pill: String
        let pillSymbol: String
        let isRestDay: Bool
    }

    static func make(_ snapshot: CoachSnapshot) -> Result {
        let brief = snapshot.brief
        let sessions = brief.adapted
        let isRestDay = sessions.isEmpty || sessions.allSatisfy { $0.kind == .rest }
        let sleepHours: Double? = snapshot.wellness.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0.sleepHours : nil }
        let sleepText: String = sleepHours.map { " (\($0.hoursText))" } ?? ""
        let performance = snapshot.lastSleepPerformance

        // 1. Comment tu vas.
        let state: String
        if let respiratory = snapshot.respiratory, respiratory.isWarning {
            state = "Ta respiration nocturne est plus rapide que d'habitude\(respiratory.restingHRUp ? " et ton cœur aussi" : "") : ton corps lutte peut-être contre quelque chose."
        } else if brief.redSignals.count >= 2 {
            state = "Plusieurs signaux sont au rouge ce matin (\(brief.redSignals.prefix(2).joined(separator: ", "))) : journée à ménager."
        } else if let readiness = snapshot.readiness {
            switch readiness.level {
            case .ready:
                if let performance, performance < 0.8 {
                    state = "Tu es bien récupéré malgré une nuit un peu courte\(sleepText)."
                } else {
                    state = "Tu es en forme : récupération solide et bonne nuit\(sleepText)."
                }
            case .moderate:
                if let performance, performance < 0.8 {
                    state = "Forme moyenne : ta nuit a été courte\(sleepText) et ta récupération n'est pas complète."
                } else {
                    state = "Forme correcte, sans plus : ton corps n'a pas encore tout récupéré."
                }
            case .low:
                state = "Ta récupération est basse aujourd'hui : fatigue accumulée ou nuit difficile\(sleepText)."
            }
        } else if let performance {
            state = performance >= 0.85
                ? "Bonne nuit\(sleepText). Il manque encore quelques jours de VFC pour juger ta récupération."
                : "Nuit un peu courte\(sleepText). Il manque encore quelques jours de VFC pour juger ta récupération."
        } else {
            state = "Pas encore assez de données pour juger ta forme : synchronise ta montre."
        }

        // 2. Ce que tu en fais.
        let action: String
        if isRestDay {
            switch brief.verdict {
            case .push, .go: action = "C'est ton jour de repos : profites-en pour bien manger et te coucher à l'heure."
            default: action = "Repos prévu, ça tombe bien : marche, étirements et sommeil."
            }
        } else {
            let main = sessions.first { $0.kind != .rest } ?? sessions[0]
            let name = main.kind.label.lowercased()
            switch brief.verdict {
            case .push: action = "Feu vert pour pousser sur ta séance (\(name))."
            case .go: action = "Ta séance du jour (\(name)) est validée telle quelle."
            case .adjust: action = "Séance maintenue (\(name)), mais en version allégée."
            case .easy: action = "On remplace l'intensité par une séance douce (\(name))."
            case .rest: action = "Mieux vaut te reposer aujourd'hui."
            }
        }

        let pill: String
        let symbol: String
        if isRestDay && (brief.verdict == .push || brief.verdict == .go) {
            pill = "Jour de repos"
            symbol = "bed.double.fill"
        } else {
            pill = brief.verdict.label
            symbol = brief.verdict.symbol
        }
        return Result(text: "\(state) \(action)", pill: pill, pillSymbol: symbol, isRestDay: isRestDay)
    }
}
