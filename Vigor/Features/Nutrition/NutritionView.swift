import SwiftUI
import SwiftData

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var addingMeal: Meal?

    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { profile, snapshot in
                    let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
                    let totals: NutritionDay = NutritionView.totals(of: dayEntries, day: day)
                    VStack(spacing: 16) {
                        DayPicker(day: $day)

                        if let targets = snapshot.macroTargets {
                            NavigationLink {
                                MacroTargetsDetailView(targets: targets, today: totals)
                            } label: {
                                GlassCard {
                                    VStack(alignment: .leading, spacing: 10) {
                                        HStack {
                                            SectionTitle(title: "Objectifs · dépense \(targets.expenditureMethod)", symbol: "target")
                                            Spacer()
                                            DetailChevron()
                                        }
                                        MacroBar(label: "Calories", value: totals.kcal, target: targets.kcal, unit: "kcal", color: Theme.nutrition)
                                        MacroBar(label: "Protéines", value: totals.protein, target: targets.protein, unit: "g", color: Theme.recovery)
                                        MacroBar(label: "Glucides", value: totals.carbs, target: targets.carbs, unit: "g", color: Theme.sleep)
                                        MacroBar(label: "Lipides", value: totals.fat, target: targets.fat, unit: "g", color: Theme.strain)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        } else {
                            EmptyStateCard(title: "Objectifs à calculer",
                                           message: "Renseigne ton poids, ta taille et ton année de naissance dans Réglages (ou synchronise ton poids depuis Garmin).",
                                           symbol: "person.text.rectangle")
                        }

                        ForEach(Meal.allCases) { meal in
                            MealCard(meal: meal, entries: dayEntries.filter { $0.meal == meal }) {
                                addingMeal = meal
                            }
                        }

                        if let phase = snapshot.plan.currentWeek?.phase {
                            ExplanationCard(title: "Objectif de la phase \(phase.label)", symbol: "flag.checkered", text: phase.nutritionFocus)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(AppBackground())
            .navigationTitle("Nutrition")
            .sheet(item: $addingMeal) { meal in
                AddFoodView(meal: meal, day: day) { app.dataVersion += 1 }
            }
        }
    }
}

extension NutritionView {
    static func totals(of entries: [FoodEntry], day: Date) -> NutritionDay {
        var kcal = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0
        for entry in entries {
            kcal += entry.kcal
            protein += entry.protein
            carbs += entry.carbs
            fat += entry.fat
        }
        return NutritionDay(date: day, kcal: kcal, protein: protein, carbs: carbs, fat: fat)
    }
}

private struct DayPicker: View {
    @Binding var day: Date

    var body: some View {
        HStack {
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(label).font(.headline)
            Spacer()
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .disabled(Calendar.current.isDateInToday(day))
        }
        .buttonStyle(.glass)
    }

    private var label: String {
        if Calendar.current.isDateInToday(day) { return "Aujourd'hui" }
        if Calendar.current.isDateInYesterday(day) { return "Hier" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func shift(_ days: Int) {
        day = Calendar.current.date(byAdding: .day, value: days, to: day) ?? day
    }
}

private struct MealCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    let meal: Meal
    let entries: [FoodEntry]
    let onAdd: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(meal.label, systemImage: meal.symbol).font(.headline)
                    Spacer()
                    if !entries.isEmpty {
                        Text("\(NutritionView.totals(of: entries, day: .now).kcal.noDecimal) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Button(action: onAdd) { Image(systemName: "plus") }
                        .buttonStyle(.glassProminent)
                }
                ForEach(entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.name).font(.subheadline).lineLimit(1)
                            Text("\(entry.grams.noDecimal) g · P \(entry.protein.noDecimal) · G \(entry.carbs.noDecimal) · L \(entry.fat.noDecimal)")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.kcal.noDecimal) kcal").font(.footnote.monospacedDigit())
                        Menu {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                context.delete(entry)
                                try? context.save()
                                app.dataVersion += 1
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}
