import Foundation

struct MacroTargets: Equatable {
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    /// Dépense énergétique totale estimée pour la journée.
    let expenditure: Double
    /// D'où vient la dépense : « mesurée » (tendance poids + apports) ou « estimée » (formule).
    let expenditureMethod: String
    /// Le raisonnement, chiffre par chiffre.
    let explanation: [String]
}

/// Calcule les objectifs du jour à partir de la science (Mifflin, Morton, Burke, Iraki)
/// et, dès qu'il y a assez de données, de ta dépense RÉELLE mesurée.
enum NutritionPlanner {
    /// Métabolisme de base (Mifflin-St Jeor, 1990).
    static func basalMetabolicRate(weightKg: Double, heightCm: Double, age: Int, sex: Sex) -> Double {
        10 * weightKg + 6.25 * heightCm - 5 * Double(age) + (sex == .male ? 5 : -161)
    }

    /// Dépense réelle = apports moyens − variation de poids × 7 700 kcal/kg (Hall 2008).
    /// Nécessite ≥ 10 jours renseignés et ≥ 8 pesées sur 21 jours.
    static func adaptiveExpenditure(nutrition: [NutritionDay], weights: [DayValue], today: Date,
                                    calendar: Calendar = .current) -> Double? {
        guard let start = calendar.date(byAdding: .day, value: -21, to: today) else { return nil }
        let logged = nutrition.filter { $0.date >= start && $0.kcal > 800 }
        let recentWeights = weights.filter { $0.date >= start }
        guard logged.count >= 10, recentWeights.count >= 8,
              let intake = Stats.mean(logged.map(\.kcal)) else { return nil }
        let trend = Stats.exponentialTrend(recentWeights)
        guard let first = trend.first, let last = trend.last else { return nil }
        let days = max(last.date.timeIntervalSince(first.date) / 86_400, 7)
        let expenditure = intake - (last.value - first.value) * 7_700 / days
        return min(5_000, max(1_500, expenditure))
    }

    static func surplus(for phase: TrainingPhase?) -> Double {
        switch phase {
        case .reprise?, .base?, nil: 300
        case .build?: 150
        case .specific?, .taper?, .race?: 0
        }
    }

    /// Glucides en g/kg selon le volume d'entraînement du jour (Burke 2011).
    static func carbsPerKg(trainingHours: Double) -> Double {
        switch trainingHours {
        case ..<0.5: 3.5
        case ..<1.25: 5
        case ..<2.5: 6.5
        default: 8
        }
    }

    static func targets(weightKg: Double,
                        heightCm: Double,
                        age: Int?,
                        sex: Sex,
                        activeKcal: Double?,
                        trainingHours: Double,
                        phase: TrainingPhase?,
                        adaptiveExpenditure: Double?) -> MacroTargets? {
        guard weightKg > 0 else { return nil }
        var explanation: [String] = []

        let expenditure: Double
        let method: String
        if let adaptiveExpenditure {
            // La dépense mesurée est une moyenne : on ajoute l'écart lié au sport du jour.
            expenditure = adaptiveExpenditure + max(0, trainingHours - 1) * 450
            method = "mesurée"
            explanation.append(String(format: "Dépense mesurée sur 3 semaines (apports − variation de poids) : %.0f kcal/j", adaptiveExpenditure))
        } else {
            let bmr: Double
            if heightCm > 0, let age {
                bmr = basalMetabolicRate(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex)
                explanation.append(String(format: "Métabolisme de base (Mifflin-St Jeor) : %.0f kcal", bmr))
            } else {
                bmr = 22 * weightKg
                explanation.append(String(format: "Métabolisme de base estimé (22 kcal/kg, renseigne taille et âge pour plus de précision) : %.0f kcal", bmr))
            }
            let activity = activeKcal ?? (bmr * 0.35 + trainingHours * 550)
            // L'effet thermique des aliments représente ~10 % de la dépense totale.
            expenditure = (bmr + activity) / 0.9
            method = "estimée"
            explanation.append(String(format: "Activité du jour (%@) : %.0f kcal", activeKcal == nil ? "estimée" : "Garmin / Apple Santé", activity))
        }

        let surplus = surplus(for: phase)
        explanation.append(surplus > 0
            ? String(format: "Surplus prise de masse : +%.0f kcal (≈ +0,25–0,5 %% de poids/semaine)", surplus)
            : "Pas de surplus : phase de maintien avant la course")

        let protein = 1.8 * weightKg
        let fat = 1.0 * weightKg
        let carbFloor = carbsPerKg(trainingHours: trainingHours) * weightKg
        var kcal = expenditure + surplus
        var carbs = (kcal - protein * 4 - fat * 9) / 4
        if carbs < carbFloor {
            carbs = carbFloor
            kcal = protein * 4 + carbs * 4 + fat * 9
            explanation.append("Glucides relevés au minimum conseillé pour ton entraînement du jour")
        }
        explanation.append(String(format: "Protéines : 1,8 g/kg = %.0f g · Lipides : 1 g/kg = %.0f g", protein, fat))
        explanation.append(String(format: "Glucides : %.1f g/kg = %.0f g (%.1f h d'entraînement prévues)", carbs / weightKg, carbs, trainingHours))

        return MacroTargets(kcal: kcal.rounded(), protein: protein.rounded(), carbs: carbs.rounded(), fat: fat.rounded(),
                            expenditure: expenditure.rounded(), expenditureMethod: method, explanation: explanation)
    }
}
