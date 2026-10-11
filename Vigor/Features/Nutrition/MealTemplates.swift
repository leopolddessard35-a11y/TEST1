import SwiftUI
import SwiftData

/// Repas types et « reprendre le repas d'hier » : noter 3 000 kcal par jour sans tout ressaisir.
@MainActor
enum MealTemplates {
    /// Ajoute tous les aliments d'un repas type au repas et au jour choisis.
    @discardableResult
    static func add(_ template: MealTemplate, meal: Meal, day: Date, context: ModelContext) -> [FoodEntry] {
        let date = FoodTiming.entryDate(for: day)
        let entries = template.items.map { FoodEntry(date: date, meal: meal, templateItem: $0) }
        for entry in entries { context.insert(entry) }
        template.lastUsed = .now
        template.useCount += 1
        try? context.save()
        return entries
    }

    /// Recopie des aliments déjà notés (ex. le petit-déjeuner d'hier) vers un autre jour.
    @discardableResult
    static func copy(_ source: [FoodEntry], meal: Meal, day: Date, context: ModelContext) -> [FoodEntry] {
        let date = FoodTiming.entryDate(for: day)
        let entries = source.map { FoodEntry(date: date, meal: meal, templateItem: MealTemplateItem(entry: $0)) }
        for entry in entries { context.insert(entry) }
        try? context.save()
        return entries
    }

    /// Enregistre les aliments d'un repas comme repas type.
    static func save(name: String, meal: Meal, entries: [FoodEntry], context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entries.isEmpty else { return }
        context.insert(MealTemplate(name: trimmed.isEmpty ? "\(meal.label) habituel" : trimmed, meal: meal,
                                    items: entries.map(MealTemplateItem.init(entry:))))
        try? context.save()
    }
}

/// Section « Repas types » de l'ajout d'aliment : un tap ajoute tout le repas.
struct MealTemplatesSection: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \MealTemplate.lastUsed, order: .reverse) private var templates: [MealTemplate]
    let meal: Meal
    let day: Date
    /// Libellé ajouté (bandeau « Ajouté »).
    let onAdded: (String, [FoodEntry]) -> Void

    var body: some View {
        if !templates.isEmpty {
            Section {
                ForEach(templates) { template in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name).font(.subheadline.weight(.medium)).lineLimit(1)
                            Text("\(template.items.count) aliment\(template.items.count > 1 ? "s" : "") · \(template.kcal.noDecimal) kcal · P \(template.protein.noDecimal) g")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            let entries = MealTemplates.add(template, meal: meal, day: day, context: context)
                            onAdded(template.name, entries)
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Theme.recovery)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ajouter le repas type \(template.name)")
                    }
                    .swipeActions {
                        Button("Supprimer", role: .destructive) {
                            context.delete(template)
                            try? context.save()
                        }
                    }
                }
            } header: {
                Text("Repas types · + = tout le repas")
            } footer: {
                Text("Pour en créer un : dans Nutrition, menu ••• d'un repas → « Enregistrer comme repas type ». Glisse vers la gauche pour supprimer.")
            }
        }
    }
}

/// Repas d'hier absents aujourd'hui : « Reprendre » les recopie en un tap.
struct YesterdayMealsCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    let day: Date
    let entries: [FoodEntry]

    var body: some View {
        let calendar = Calendar.current
        let previous = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: day)) ?? day
        let yesterday = entries.filter { calendar.isDate($0.date, inSameDayAs: previous) }
        let todayMeals = Set(entries.filter { calendar.isDate($0.date, inSameDayAs: day) }.map(\.meal))
        let meals = Meal.allCases.filter { meal in !todayMeals.contains(meal) && yesterday.contains { $0.meal == meal } }
        if !meals.isEmpty {
            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    CapsLabel("Comme hier ?")
                    ForEach(meals) { meal in
                        let items = yesterday.filter { $0.meal == meal }
                        HStack {
                            Label(meal.label, systemImage: meal.symbol).font(.subheadline.weight(.medium))
                            Text("\(items.reduce(0) { $0 + $1.kcal }.noDecimal) kcal · \(items.count) aliment\(items.count > 1 ? "s" : "")")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Spacer()
                            Button("Reprendre") {
                                let added = MealTemplates.copy(items, meal: meal, day: day, context: context)
                                app.dataVersion += 1
                                app.offerUndo("\(meal.label) d'hier repris") { undoContext in
                                    for entry in added { undoContext.delete(entry) }
                                }
                            }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.bordered)
                            .tint(Theme.accent)
                            .frame(minHeight: 44)
                        }
                    }
                }
            }
        }
    }
}
