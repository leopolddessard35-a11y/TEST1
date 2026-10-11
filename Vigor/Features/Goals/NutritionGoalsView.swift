import SwiftUI
import SwiftData

/// Objectif nutrition : prendre, maintenir ou perdre du poids, en automatique (calculé chaque jour
/// depuis ta dépense) ou à la main (tes calories et tes macros, fixes).
struct NutritionGoalsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        Group {
            if let profile = profiles.first {
                NutritionGoalsForm(profile: profile) {
                    try? context.save()
                    app.dataVersion += 1
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Objectif nutrition")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NutritionGoalsForm: View {
    @Bindable var profile: AthleteProfile
    let onChange: () -> Void

    var body: some View {
        Form {
            Section {
                Picker("Objectif", selection: goalBinding) {
                    ForEach(WeightGoal.allCases) { goal in Text(goal.label).tag(goal) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Mon poids")
            } footer: {
                Text(goalFooter)
            }

            Section {
                Toggle("Je fixe mes calories et mes macros", isOn: manualBinding)
            } footer: {
                Text(profile.manualTargets
                     ? "Les mêmes valeurs chaque jour. Vigor compare quand même à ta dépense du jour pour t'informer."
                     : "Calculé chaque jour : ta dépense (mesurée après 3 semaines de repas et de pesées, sinon estimée) + ton écart, protéines et lipides selon ton poids, glucides pour le reste avec un minimum selon l'entraînement du jour.")
            }

            if profile.manualTargets {
                manualSection
            } else {
                automaticSection
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .onChange(of: profile.calorieAdjustment) { onChange() }
        .onChange(of: profile.proteinPerKg) { onChange() }
        .onChange(of: profile.fatPerKg) { onChange() }
        .onChange(of: profile.manualKcal) { onChange() }
        .onChange(of: profile.manualProtein) { onChange() }
        .onChange(of: profile.manualCarbs) { onChange() }
        .onChange(of: profile.manualFat) { onChange() }
    }

    // MARK: Automatique

    private var automaticSection: some View {
        Section {
            Stepper(value: $profile.calorieAdjustment, in: -1000...1000, step: 50) {
                LabeledContent("Écart calorique", value: signed(profile.calorieAdjustment) + " kcal/j")
            }
            Stepper(value: $profile.proteinPerKg, in: 1.2...3.0, step: 0.1) {
                LabeledContent("Protéines", value: "\(profile.proteinPerKg.oneDecimal) g/kg")
            }
            Stepper(value: $profile.fatPerKg, in: 0.5...1.5, step: 0.1) {
                LabeledContent("Lipides", value: "\(profile.fatPerKg.oneDecimal) g/kg")
            }
            Button("Revenir aux valeurs conseillées") {
                profile.calorieAdjustment = profile.weightGoal.suggestedAdjustment
                profile.proteinPerKg = 1.8
                profile.fatPerKg = 1.0
            }
        } header: {
            Text("Réglages")
        } footer: {
            Text("Repères : prise de poids +250 à +400 kcal/j (≈ +0,25–0,5 % du poids par semaine), perte −300 à −500 kcal/j, protéines 1,6–2,2 g/kg.")
        }
    }

    // MARK: Manuel

    private var manualSection: some View {
        let fromMacros = profile.manualProtein * 4 + profile.manualCarbs * 4 + profile.manualFat * 9
        let gap = fromMacros - profile.manualKcal
        return Section {
            DecimalFieldNonOptional("Calories (kcal)", value: $profile.manualKcal, keyboard: .numberPad)
            DecimalFieldNonOptional("Protéines (g)", value: $profile.manualProtein, keyboard: .numberPad)
            DecimalFieldNonOptional("Glucides (g)", value: $profile.manualCarbs, keyboard: .numberPad)
            DecimalFieldNonOptional("Lipides (g)", value: $profile.manualFat, keyboard: .numberPad)
            if profile.manualKcal > 0, fromMacros > 0 {
                LabeledContent("Tes macros font", value: "\(fromMacros.noDecimal) kcal")
                if abs(gap) > profile.manualKcal * 0.05 {
                    Label("Écart de \(signed(gap)) kcal avec tes calories : ajuste les glucides ou les lipides.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Theme.caution)
                }
            }
            Button("Répartir les macros depuis mes calories") { splitFromCalories() }
                .disabled(profile.manualKcal <= 0 || profile.weightKg <= 0)
        } header: {
            Text("Mes objectifs du jour")
        } footer: {
            Text("1 g de protéines ou de glucides = 4 kcal, 1 g de lipides = 9 kcal. « Répartir » met \(profile.proteinPerKg.oneDecimal) g/kg de protéines, \(profile.fatPerKg.oneDecimal) g/kg de lipides et le reste en glucides.")
        }
    }

    private func splitFromCalories() {
        let weight = profile.weightKg
        guard weight > 0, profile.manualKcal > 0 else { return }
        let protein = (profile.proteinPerKg * weight).rounded()
        let fat = (profile.fatPerKg * weight).rounded()
        profile.manualProtein = protein
        profile.manualFat = fat
        profile.manualCarbs = max(0, ((profile.manualKcal - protein * 4 - fat * 9) / 4).rounded())
    }

    // MARK: Liaisons

    private var goalBinding: Binding<WeightGoal> {
        Binding {
            profile.weightGoal
        } set: { goal in
            profile.weightGoalRaw = goal.rawValue
            // Nouvel objectif : écart conseillé (modifiable ensuite).
            profile.calorieAdjustment = goal.suggestedAdjustment
            onChange()
        }
    }

    private var manualBinding: Binding<Bool> {
        Binding {
            profile.manualTargets
        } set: { manual in
            profile.manualTargets = manual
            // Première fois : on part d'une base cohérente plutôt que de zéros.
            if manual, profile.manualKcal <= 0, profile.weightKg > 0 {
                profile.manualKcal = (profile.weightKg * 33 + max(0, profile.calorieAdjustment)).rounded()
                splitFromCalories()
            }
            onChange()
        }
    }

    private var goalFooter: String {
        switch profile.weightGoal {
        case .gain: "Prise de poids : léger surplus pour construire du muscle sans trop de gras. Vigor surveille le rythme (idéal +0,25 à 0,5 % par semaine)."
        case .maintain: "Maintien : apports égaux à ta dépense, ajustés selon l'entraînement du jour."
        case .lose: "Perte de poids : déficit modéré pour garder ton muscle et ta récupération (au plus −1 % par semaine)."
        }
    }

    private func signed(_ value: Double) -> String {
        value > 0 ? "+\(value.noDecimal)" : (value < 0 ? "−\(abs(value).noDecimal)" : "0")
    }
}
