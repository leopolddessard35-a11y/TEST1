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

enum WeightGoal: String, CaseIterable, Identifiable {
    case lose, maintain, gain

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lose: "Perdre"
        case .maintain: "Maintenir"
        case .gain: "Prendre"
        }
    }

    /// Écart calorique conseillé (kcal/j) : −400 ≈ −0,5 %/sem, +300 ≈ +0,25–0,5 %/sem.
    var suggestedAdjustment: Double {
        switch self {
        case .lose: -400
        case .maintain: 0
        case .gain: 300
        }
    }
}

/// Calories et macros fixées à la main.
struct ManualMacros: Equatable {
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
}

/// Ce que tu vises : objectif de poids, écart calorique, protéines et lipides, ou tout à la main.
struct NutritionGoal: Equatable {
    var goal: WeightGoal = .gain
    var adjustment: Double = 300
    var proteinPerKg: Double = 1.8
    var fatPerKg: Double = 1.0
    var manual: ManualMacros?
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
        // La journée en cours (incomplète) n'entre pas dans la moyenne : sinon l'objectif baisse à chaque repas.
        let todayStart = calendar.startOfDay(for: today)
        let logged = nutrition.filter { $0.date >= start && $0.date < todayStart && $0.kcal > 800 }
        let recentWeights = weights.filter { $0.date >= start }
        guard logged.count >= 10, recentWeights.count >= 8,
              let intake = Stats.mean(logged.map(\.kcal)) else { return nil }
        let trend = Stats.exponentialTrend(recentWeights)
        guard let first = trend.first, let last = trend.last else { return nil }
        let days = max(last.date.timeIntervalSince(first.date) / 86_400, 7)
        let expenditure = intake - (last.value - first.value) * 7_700 / days
        return min(5_000, max(1_500, expenditure))
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
                        adaptiveExpenditure: Double?,
                        goal: NutritionGoal = NutritionGoal()) -> MacroTargets? {
        guard weightKg > 0 else { return nil }
        var explanation: [String] = []

        let expenditure: Double
        let method: String
        if let adaptiveExpenditure {
            // La dépense mesurée est une moyenne : on ajoute l'écart lié au sport du jour.
            expenditure = adaptiveExpenditure + max(0, trainingHours - 1) * 450
            method = "mesurée"
            explanation.append(String(format: "Dépense mesurée sur 3 semaines (apports − variation de poids) : %.0f kcal/j", locale: Locale.current, adaptiveExpenditure))
        } else {
            let bmr: Double
            if heightCm > 0, let age {
                bmr = basalMetabolicRate(weightKg: weightKg, heightCm: heightCm, age: age, sex: sex)
                explanation.append(String(format: "Métabolisme de base (Mifflin-St Jeor) : %.0f kcal", locale: Locale.current, bmr))
            } else {
                bmr = 22 * weightKg
                explanation.append(String(format: "Métabolisme de base estimé (22 kcal/kg, renseigne taille et âge pour plus de précision) : %.0f kcal", locale: Locale.current, bmr))
            }
            let activity = activeKcal ?? (bmr * 0.35 + trainingHours * 550)
            // L'effet thermique des aliments représente ~10 % de la dépense totale.
            expenditure = (bmr + activity) / 0.9
            method = "estimée"
            explanation.append(String(format: "Activité du jour (%@) : %.0f kcal", locale: Locale.current, activeKcal == nil ? "estimée" : "Garmin / Apple Santé", activity))
        }

        if let manual = goal.manual {
            explanation.append("Objectifs fixés à la main : \(manual.kcal.noDecimal) kcal · \(manual.protein.noDecimal) g de protéines · \(manual.carbs.noDecimal) g de glucides · \(manual.fat.noDecimal) g de lipides")
            let difference = manual.kcal - expenditure
            explanation.append(abs(difference) < 50
                ? "C'est à peu près ta dépense du jour"
                : "Soit \(difference > 0 ? "+" : "−")\(abs(difference).noDecimal) kcal par rapport à ta dépense du jour")
            return MacroTargets(kcal: manual.kcal.rounded(), protein: manual.protein.rounded(), carbs: manual.carbs.rounded(),
                                fat: manual.fat.rounded(), expenditure: expenditure.rounded(), expenditureMethod: method,
                                explanation: explanation)
        }

        let surplus = goal.adjustment
        switch goal.goal {
        case .gain:
            explanation.append("Prise de poids : +\(max(0, surplus).noDecimal) kcal (≈ +0,25–0,5 % de poids par semaine)")
        case .maintain:
            explanation.append(surplus == 0 ? "Maintien : apports = dépense" : "Maintien, écart choisi : \(surplus > 0 ? "+" : "−")\(abs(surplus).noDecimal) kcal")
        case .lose:
            explanation.append("Perte de poids : −\(abs(min(0, surplus)).noDecimal) kcal (≈ −0,5 % de poids par semaine au maximum)")
        }

        let protein = goal.proteinPerKg * weightKg
        let fat = goal.fatPerKg * weightKg
        let carbFloor = carbsPerKg(trainingHours: trainingHours) * weightKg
        var kcal = expenditure + surplus
        var carbs = (kcal - protein * 4 - fat * 9) / 4
        // En perte de poids, on accepte de descendre sous le repère glucides plutôt que d'annuler le déficit.
        if carbs < carbFloor, goal.goal != .lose {
            carbs = carbFloor
            kcal = protein * 4 + carbs * 4 + fat * 9
            explanation.append("Glucides relevés au minimum conseillé pour ton entraînement du jour")
        }
        carbs = max(0, carbs)
        explanation.append("Protéines : \(goal.proteinPerKg.oneDecimal) g/kg = \(protein.noDecimal) g · Lipides : \(goal.fatPerKg.oneDecimal) g/kg = \(fat.noDecimal) g")
        explanation.append("Glucides : \((carbs / weightKg).oneDecimal) g/kg = \(carbs.noDecimal) g (\(trainingHours.oneDecimal) h d'entraînement aujourd'hui)")

        return MacroTargets(kcal: kcal.rounded(), protein: protein.rounded(), carbs: carbs.rounded(), fat: fat.rounded(),
                            expenditure: expenditure.rounded(), expenditureMethod: method, explanation: explanation)
    }
}
