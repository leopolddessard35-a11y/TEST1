import SwiftUI
import SwiftData
import Charts
import Combine

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
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \FoodEntry.date) private var entries: [FoodEntry]
    @State private var day = Calendar.current.startOfDay(for: .now)
    /// Vrai tant que le jour affiché est « aujourd'hui » : il suit alors le passage de minuit.
    @State private var followsToday = true
    @State private var adding = false

    var body: some View {
        SnapshotReader { _, snapshot in
            let dayEntries = entries.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            let totals: NutritionDay = NutritionView.totals(of: dayEntries, day: day)
            VStack(spacing: 12) {
                DayPicker(day: $day)

                if let targets = snapshot.macroTargets {
                    NavigationLink {
                        MacroTargetsDetailView(targets: targets, today: totals)
                    } label: {
                        MacroSummaryTile(targets: targets, totals: totals)
                    }
                    .buttonStyle(.plain)
                    NavigationLink {
                        NutritionGoalsView()
                    } label: {
                        Label("Modifier mes objectifs", systemImage: "slider.horizontal.3")
                            .font(.footnote.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                } else {
                    EmptyStateCard(title: "Objectifs du jour indisponibles",
                                   message: "Renseigne ton poids et ta taille dans Réglages → Profil et objectif pour calculer tes calories et tes macros.",
                                   symbol: "person.crop.circle.badge.questionmark")
                }

                Button { adding = true } label: {
                    Label("Ajouter un aliment", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                YesterdayMealsCard(day: day, entries: entries)

                if dayEntries.isEmpty {
                    EmptyStateCard(title: Calendar.current.isDateInToday(day) ? "Aucun repas noté aujourd'hui" : "Aucun repas noté ce jour-là",
                                   message: "Touche « Ajouter un aliment » : recherche, scan du code-barres ou tes favoris en un tap.",
                                   symbol: "fork.knife")
                }

                ForEach(Meal.allCases) { meal in
                    let items = dayEntries.filter { $0.meal == meal }
                    if !items.isEmpty {
                        MealCard(meal: meal, entries: items)
                    }
                }

                HStack(spacing: 12) {
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
            AddFoodView(meal: FoodTiming.defaultMeal(for: day), day: day) { app.dataVersion += 1 }
        }
        .onAppear { rollOverToToday() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { rollOverToToday() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            rollOverToToday()
        }
        .onChange(of: day) { _, newDay in
            followsToday = Calendar.current.isDateInToday(newDay)
        }
    }

    /// Si « aujourd'hui » était affiché, on passe au nouveau jour après minuit.
    private func rollOverToToday() {
        let today = Calendar.current.startOfDay(for: .now)
        if followsToday && day != today { day = today }
    }
}

/// Calories en anneau + macros en barres, dans une seule tuile.
private struct MacroSummaryTile: View {
    let targets: MacroTargets
    let totals: NutritionDay

    var body: some View {
        GlassCard(tint: Theme.nutrition) {
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
    @State private var editing: FoodEntry?
    @State private var naming = false
    @State private var templateName = ""

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(meal.label, systemImage: meal.symbol).font(.headline)
                    Spacer()
                    Text("\(NutritionView.totals(of: entries, day: .now).kcal.noDecimal) kcal").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Menu {
                        Button("Enregistrer comme repas type", systemImage: "square.and.arrow.down") {
                            templateName = "\(meal.label) habituel"
                            naming = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Options du repas \(meal.label)")
                }
                ForEach(entries) { entry in
                    HStack {
                        Button { editing = entry } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name).font(.subheadline).lineLimit(1)
                                    Text("\(entry.grams.noDecimal) g · P \(entry.protein.noDecimal) · G \(entry.carbs.noDecimal) · L \(entry.fat.noDecimal)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(entry.kcal.noDecimal) kcal").font(.footnote.monospacedDigit())
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Modifier la quantité ou le repas")
                        Menu {
                            Button("Modifier", systemImage: "pencil") { editing = entry }
                            Button("Supprimer", systemImage: "trash", role: .destructive) { delete(entry) }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Options pour \(entry.name)")
                    }
                }
            }
        }
        .sheet(item: $editing) { entry in
            FoodEntryEditor(entry: entry) { app.dataVersion += 1 }
        }
        .alert("Nouveau repas type", isPresented: $naming) {
            TextField("Nom", text: $templateName)
            Button("Enregistrer") {
                MealTemplates.save(name: templateName, meal: meal, entries: entries, context: context)
                app.statusMessage = "Repas type « \(templateName) » enregistré : retrouve-le en haut de « Ajouter un aliment »."
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("\(entries.count) aliment\(entries.count > 1 ? "s" : "") · \(NutritionView.totals(of: entries, day: .now).kcal.noDecimal) kcal, avec leurs quantités.")
        }
    }

    /// Suppression annulable quelques secondes (bandeau « Annuler »).
    private func delete(_ entry: FoodEntry) {
        let copy = FoodEntryCopy(entry)
        context.delete(entry)
        try? context.save()
        app.dataVersion += 1
        app.offerUndo("\(copy.name) supprimé") { undoContext in
            undoContext.insert(copy.makeEntry())
        }
    }
}

/// Copie des valeurs d'un aliment noté, pour le recréer si la suppression est annulée.
private struct FoodEntryCopy {
    let date: Date
    let meal: Meal
    let grams: Double
    let itemKey: String
    let name: String
    let brand: String
    let kcal100: Double
    let protein100: Double
    let carbs100: Double
    let fat100: Double
    let fiber100: Double?
    let sugar100: Double?

    init(_ entry: FoodEntry) {
        date = entry.date
        meal = entry.meal
        grams = entry.grams
        itemKey = entry.itemKey
        name = entry.name
        brand = entry.brand
        kcal100 = entry.kcal100
        protein100 = entry.protein100
        carbs100 = entry.carbs100
        fat100 = entry.fat100
        fiber100 = entry.fiber100
        sugar100 = entry.sugar100
    }

    func makeEntry() -> FoodEntry {
        // Aliment temporaire (jamais inséré) : sert seulement à recopier les valeurs dans l'entrée.
        let item = FoodItem(key: itemKey, name: name, brand: brand, barcode: nil, source: "",
                            kcal100: kcal100, protein100: protein100, carbs100: carbs100, fat100: fat100)
        item.fiber100 = fiber100
        item.sugar100 = sugar100
        return FoodEntry(date: date, meal: meal, grams: grams, item: item)
    }
}

/// Modification d'un aliment déjà noté : quantité et repas (les valeurs pour 100 g ne changent pas).
private struct FoodEntryEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let entry: FoodEntry
    let onSaved: () -> Void
    @State private var grams: Double
    @State private var meal: Meal

    init(entry: FoodEntry, onSaved: @escaping () -> Void) {
        self.entry = entry
        self.onSaved = onSaved
        self._grams = State(initialValue: entry.grams)
        self._meal = State(initialValue: entry.meal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.name).font(.headline)
                    if !entry.brand.isEmpty { Text(entry.brand).foregroundStyle(.secondary) }
                }
                Section("Quantité") {
                    HStack {
                        DecimalFieldNonOptional("Grammes", value: $grams)
                        Text("g").foregroundStyle(.secondary)
                    }
                    Picker("Repas", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Pour \(grams.noDecimal) g") {
                    LabeledContent("Calories", value: "\((entry.kcal100 * grams / 100).noDecimal) kcal")
                    LabeledContent("Protéines", value: "\((entry.protein100 * grams / 100).oneDecimal) g")
                    LabeledContent("Glucides", value: "\((entry.carbs100 * grams / 100).oneDecimal) g")
                    LabeledContent("Lipides", value: "\((entry.fat100 * grams / 100).oneDecimal) g")
                }
            }
            .navigationTitle("Modifier")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }.disabled(grams <= 0)
                }
            }
        }
    }

    private func save() {
        entry.grams = grams
        entry.mealRaw = meal.rawValue
        try? context.save()
        onSaved()
        dismiss()
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
                    .dateAxis(days: 42)
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
                    .dateAxis(days: 42)
                    .frame(height: 110)
                }
                HStack {
                    StatTile(title: "Apport moyen 14 j", value: intake14.map { "\($0.noDecimal) kcal" } ?? "–")
                    StatTile(title: "Dépense (\(method))", value: expenditure.map { "\($0.noDecimal) kcal" } ?? "–")
                    StatTile(title: "Poids 14 j", value: change.map { "\($0.formatted(.number.precision(.fractionLength(1)).sign(strategy: .always()))) kg" } ?? "–")
                }
                Text(verdict(intake: intake14, change: change)).font(.footnote)
            }
        }
    }

    private func verdict(intake: Double?, change: Double?) -> String {
        guard let intake, let change else { return "Note tes repas et pèse-toi 3 fois par semaine pour vérifier que ton apport tient face à ta dépense." }
        if abs(change) < 0.3 {
            return "Poids stable à ~\(intake.noDecimal) kcal/j : c'est ton niveau de maintien actuel."
        }
        return change > 0
            ? "Tu prends du poids à ~\(intake.noDecimal) kcal/j : tu es au-dessus de ton maintien."
            : "Tu perds du poids à ~\(intake.noDecimal) kcal/j : ton maintien est plus haut que ça."
    }
}
