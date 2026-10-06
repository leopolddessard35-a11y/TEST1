import SwiftUI
import SwiftData
import Charts

/// Écran autonome (conservé) : enveloppe le contenu nutrition.
struct NutritionView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                NutritionContent().padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Nutrition")
        }
    }
}

/// Contenu nutrition : objectifs du jour, ajout rapide, repas, puis tuiles vers le détail.
struct NutritionContent: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var adding = false

    var body: some View {
        SnapshotReader { _, snapshot in
            let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            let totals: NutritionDay = NutritionView.totals(of: dayEntries, day: day)
            VStack(spacing: 16) {
                DayPicker(day: $day)

                if let targets = snapshot.macroTargets {
                    NavigationLink {
                        MacroTargetsDetailView(targets: targets, today: totals)
                    } label: {
                        MacroSummaryTile(targets: targets, totals: totals)
                    }
                    .buttonStyle(.plain)
                }

                Button { adding = true } label: {
                    Label("Ajouter un aliment", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                ForEach(Meal.allCases) { meal in
                    let items = dayEntries.filter { $0.meal == meal }
                    if !items.isEmpty {
                        MealCard(meal: meal, entries: items)
                    }
                }

                HStack(spacing: 12) {
                    NavigationLink {
                        DetailPage(title: "Hydratation") {
                            HydrationCard(target: snapshot.hydrationTarget, today: snapshot.waterToday)
                        }
                    } label: {
                        SimpleTile(title: "Eau", value: String(format: "%.1f L", snapshot.waterToday / 1000),
                                   caption: String(format: "objectif %.1f L", snapshot.hydrationTarget / 1000),
                                   symbol: "drop.fill", tint: Theme.sleep)
                    }
                    NavigationLink {
                        DetailPage(title: "Bilan énergétique") {
                            EnergyBalanceCard(weights: snapshot.weightMA7, nutrition: snapshot.nutritionDays,
                                              expenditure: snapshot.macroTargets?.expenditure,
                                              method: snapshot.macroTargets?.expenditureMethod ?? "estimée")
                        }
                    } label: {
                        SimpleTile(title: "Poids 7 j", value: snapshot.weightMA7.last.map { "\($0.value.oneDecimal) kg" } ?? "–",
                                   caption: "vs apports", symbol: "scalemass.fill", tint: Theme.nutrition)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $adding) {
            AddFoodView(meal: Calendar.current.isDateInToday(day) ? Meal.suggested() : .lunch, day: day) { app.dataVersion += 1 }
        }
    }
}

/// Calories en anneau + macros en barres, dans une seule tuile.
private struct MacroSummaryTile: View {
    let targets: MacroTargets
    let totals: NutritionDay

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    ZStack {
                        GradientRing(fraction: totals.kcal / max(targets.kcal, 1), colors: Theme.nutritionGradient, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(totals.kcal.noDecimal).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                            Text("kcal").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Calories").font(.headline)
                        Text("\(max(0, targets.kcal - totals.kcal).noDecimal) kcal restantes").font(.subheadline).foregroundStyle(.secondary)
                        Text("objectif \(targets.kcal.noDecimal) kcal").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    DetailChevron()
                }
                HStack(alignment: .top, spacing: 12) {
                    MacroDots(label: "Protéines", value: totals.protein, target: targets.protein, color: Theme.recovery)
                    MacroDots(label: "Glucides", value: totals.carbs, target: targets.carbs, color: Theme.sleep)
                    MacroDots(label: "Lipides", value: totals.fat, target: targets.fat, color: Theme.strain)
                }
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

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(meal.label, systemImage: meal.symbol).font(.headline)
                    Spacer()
                    if !entries.isEmpty {
                        Text("\(NutritionView.totals(of: entries, day: .now).kcal.noDecimal) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
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

/// Poids en moyenne mobile 7 jours croisé avec les apports : la vraie mesure de l'équilibre énergétique.
struct EnergyBalanceCard: View {
    let weights: [DayValue]
    let nutrition: [NutritionDay]
    let expenditure: Double?
    let method: String

    var body: some View {
        let start: Date = Calendar.current.date(byAdding: .day, value: -42, to: .now) ?? .now
        let recentWeights: [DayValue] = weights.filter { $0.date >= start }
        let recentIntake: [NutritionDay] = nutrition.filter { $0.date >= start && $0.kcal > 800 }
        let twoWeeks: Date = Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let intake14: Double? = Stats.mean(nutrition.filter { $0.date >= twoWeeks && $0.kcal > 800 }.map(\.kcal))
        let change: Double? = {
            guard let last = recentWeights.last else { return nil }
            let reference = recentWeights.last { $0.date <= last.date.addingTimeInterval(-14 * 86_400) }
            return reference.map { last.value - $0.value }
        }()

        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Bilan énergétique · 6 semaines", symbol: "scalemass")
                if recentWeights.count >= 3 {
                    Chart {
                        ForEach(recentWeights, id: \.date) { point in
                            LineMark(x: .value("Jour", point.date), y: .value("Poids (kg)", point.value))
                                .foregroundStyle(Theme.nutrition)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 120)
                    Text("Poids en moyenne mobile 7 jours (jamais le chiffre du jour).").font(.caption2).foregroundStyle(.secondary)
                }
                if recentIntake.count >= 3 {
                    Chart {
                        ForEach(recentIntake, id: \.date) { day in
                            BarMark(x: .value("Jour", day.date, unit: .day), y: .value("kcal", day.kcal))
                                .foregroundStyle(Theme.sleep.opacity(0.7))
                        }
                        if let expenditure {
                            RuleMark(y: .value("Dépense", expenditure))
                                .foregroundStyle(Theme.warning)
                                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        }
                    }
                    .frame(height: 110)
                }
                HStack {
                    StatTile(title: "Apport moyen 14 j", value: intake14.map { "\($0.noDecimal) kcal" } ?? "–")
                    StatTile(title: "Dépense (\(method))", value: expenditure.map { "\($0.noDecimal) kcal" } ?? "–")
                    StatTile(title: "Poids 14 j", value: change.map { String(format: "%+.1f kg", $0) } ?? "–")
                }
                Text(verdict(intake: intake14, change: change)).font(.footnote)
            }
        }
    }

    private func verdict(intake: Double?, change: Double?) -> String {
        guard let intake, let change else { return "Note tes repas et pèse-toi 3 fois par semaine pour vérifier que ton apport tient face à ta dépense." }
        if abs(change) < 0.3 {
            return String(format: "Poids stable à ~%.0f kcal/j : c'est ton niveau de maintien actuel.", intake)
        }
        return change > 0
            ? String(format: "Tu prends du poids à ~%.0f kcal/j : tu es au-dessus de ton maintien.", intake)
            : String(format: "Tu perds du poids à ~%.0f kcal/j : ton maintien est plus haut que ça.", intake)
    }
}
