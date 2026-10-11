import Foundation

/// Événement à annoter sur les courbes (sans lui, une baisse de VFC est ininterprétable).
struct ChartEvent: Identifiable, Equatable {
    var id: String { "\(label)-\(start.timeIntervalSince1970)" }
    let start: Date
    let end: Date
    let label: String
    let symbol: String
}

extension WeeklyReport {
    /// Revue du dimanche : prévu vs réalisé, 1 point fort, 1 point de vigilance, 1 ajustement.
    struct Review: Equatable {
        var plannedHours: Double?
        var doneHours: Double
        var plannedStrength: Int
        var doneStrength: Int
        var strongPoint: String
        var vigilance: String
        var adjustment: String
    }

    static func review(report: WeeklyReport, plannedHours: Double?, plannedStrength: Int, doneStrength: Int,
                       acuteChronic: Double?) -> Review {
        let current = report.current, previous = report.previous

        // Point fort : la meilleure évolution parmi récup, sommeil, régularité de l'entraînement.
        var strong = current.trainingHours < 0.5
            ? "Semaine calme : le repos fait aussi partie de l'entraînement."
            : "Régularité : \(current.trainingHours.oneDecimal) h d'entraînement sur 7 jours."
        if let now = current.recovery, let before = previous.recovery, now - before >= 3 {
            strong = String(format: "Récupération en hausse (%.0f → %.0f).", locale: Locale.current, before, now)
        } else if let performance = current.sleepPerformance, performance >= 0.9 {
            strong = String(format: "Sommeil : %.0f %% de ton besoin couvert.", locale: Locale.current, performance * 100)
        } else if let planned = plannedHours, planned > 0, current.trainingHours >= planned * 0.9 {
            strong = "Volume prévu tenu : \(current.trainingHours.oneDecimal) h sur \(planned.oneDecimal) h."
        }

        // Point de vigilance : le signal le plus préoccupant.
        var vigilance = "Rien de préoccupant dans les données de la semaine."
        var adjustment = "Semaine suivante : progression normale du plan (+5 à 10 % de volume au maximum)."
        if let ratio = acuteChronic, ratio > 1.5 {
            vigilance = String(format: "Charge en forte hausse (ratio 7 j / 28 j : %.2f).", locale: Locale.current, ratio)
            adjustment = "Semaine suivante : volume −15 %, une seule séance intense."
        } else if let performance = current.sleepPerformance, performance < 0.85 {
            vigilance = String(format: "Sommeil à %.0f %% du besoin.", locale: Locale.current, performance * 100)
            adjustment = "Semaine suivante : coucher avancé de 30 min, intensité placée après les meilleures nuits."
        } else if let now = current.recovery, let before = previous.recovery, before - now >= 5 {
            vigilance = String(format: "Récupération en baisse (%.0f → %.0f).", locale: Locale.current, before, now)
            adjustment = "Semaine suivante : garder le volume, réduire l'intensité de 20 %."
        } else if let planned = plannedHours, planned > 0, current.trainingHours < planned * 0.7 {
            vigilance = "Volume réalisé \(current.trainingHours.oneDecimal) h pour \(planned.oneDecimal) h prévues."
            adjustment = "Semaine suivante : vérifie tes minutes disponibles par jour dans Réglages, ou place tes séances dans « Ma semaine »."
        }
        return Review(plannedHours: plannedHours, doneHours: current.trainingHours, plannedStrength: plannedStrength,
                      doneStrength: doneStrength, strongPoint: strong, vigilance: vigilance, adjustment: adjustment)
    }
}
