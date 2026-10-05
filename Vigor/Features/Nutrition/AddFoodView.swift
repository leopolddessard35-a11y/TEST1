import SwiftUI
import SwiftData
import VisionKit

/// Ajout d'un aliment : scan, recherche (Open Food Facts + aliments de référence), récents, création.
struct AddFoodView: View {
    enum Mode: String, CaseIterable {
        case scan = "Scanner"
        case search = "Rechercher"
        case recent = "Récents"
    }

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.lastUsed, order: .reverse) private var recents: [FoodItem]
    let meal: Meal
    let day: Date
    let onSaved: () -> Void

    @State private var mode: Mode = .scan
    @State private var query = ""
    @State private var results: [FoodProduct] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var selected: FoodProduct?
    @State private var manualBarcode = ""
    @State private var creatingCustom = false
    @State private var lastScanned: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch mode {
                case .scan: scanView
                case .search: searchView
                case .recent: recentView
                }
            }
            .navigationTitle(meal.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Créer", systemImage: "square.and.pencil") { creatingCustom = true }
                }
            }
            .sheet(item: $selected) { product in
                FoodPortionView(product: product, meal: meal, day: day) {
                    onSaved()
                    dismiss()
                }
            }
            .sheet(isPresented: $creatingCustom) {
                CustomFoodForm { product in
                    creatingCustom = false
                    selected = product
                }
            }
        }
    }

    // MARK: Scan

    @ViewBuilder private var scanView: some View {
        VStack(spacing: 12) {
            if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                BarcodeScannerView { code in
                    guard code != lastScanned else { return }
                    lastScanned = code
                    Task { await lookup(barcode: code) }
                }
                .clipShape(.rect(cornerRadius: 24))
                .padding(.horizontal)
                Text("Vise le code-barres du produit").font(.footnote).foregroundStyle(.secondary)
            } else {
                ContentUnavailableView("Scanner indisponible",
                                       systemImage: "barcode.viewfinder",
                                       description: Text("La caméra n'est pas accessible (simulateur ou autorisation refusée). Tape le code-barres ci-dessous."))
            }
            HStack {
                TextField("Code-barres (ex. 3017620422003)", text: $manualBarcode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                Button("Chercher") { Task { await lookup(barcode: manualBarcode) } }
                    .buttonStyle(.glassProminent)
                    .disabled(manualBarcode.count < 8)
            }
            .padding(.horizontal)
            statusView
            Spacer()
        }
    }

    private func lookup(barcode: String) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            selected = try await OpenFoodFacts.product(barcode: barcode)
        } catch {
            self.error = error.localizedDescription
            lastScanned = nil
        }
    }

    // MARK: Recherche

    private var searchView: some View {
        List {
            Section {
                HStack {
                    TextField("Aliment ou marque", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    if isLoading { ProgressView() }
                }
            }
            let reference = CommonFoods.search(query)
            if !reference.isEmpty {
                Section("Aliments de référence") {
                    ForEach(reference) { product in productRow(product) }
                }
            }
            if !results.isEmpty {
                Section("Open Food Facts") {
                    ForEach(results) { product in productRow(product) }
                }
            }
            if let error { Section { Text(error).foregroundStyle(Theme.warning) } }
        }
        .scrollContentBackground(.hidden)
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            results = try await OpenFoodFacts.search(text)
            if results.isEmpty { error = "Aucun produit trouvé. Essaie la marque ou crée l'aliment." }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: Récents

    private var recentView: some View {
        List {
            if recents.isEmpty {
                Text("Les aliments que tu ajoutes apparaîtront ici.").foregroundStyle(.secondary)
            }
            ForEach(recents.prefix(50)) { item in
                productRow(FoodProduct(item: item))
            }
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: Commun

    private func productRow(_ product: FoodProduct) -> some View {
        Button {
            selected = product
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text([product.brand, product.source].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(product.kcal100.noDecimal) kcal").font(.footnote.monospacedDigit()).foregroundStyle(.primary)
                    Text("P \(product.protein100.oneDecimal) · G \(product.carbs100.oneDecimal) · L \(product.fat100.oneDecimal)")
                        .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var statusView: some View {
        if isLoading { ProgressView("Recherche du produit…") }
        if let error { Text(error).font(.footnote).foregroundStyle(Theme.warning).padding(.horizontal) }
    }
}

extension FoodProduct {
    init(item: FoodItem) {
        self.init(key: item.key, barcode: item.barcode, name: item.name, brand: item.brand, source: item.source,
                  kcal100: item.kcal100, protein100: item.protein100, carbs100: item.carbs100, fat100: item.fat100,
                  fiber100: item.fiber100, sugar100: item.sugar100, saturatedFat100: item.saturatedFat100,
                  salt100: item.salt100, servingGrams: item.servingGrams)
    }
}

/// Choix de la quantité et aperçu des macros.
struct FoodPortionView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let product: FoodProduct
    @State var meal: Meal
    let day: Date
    let onSaved: () -> Void
    @State private var grams: Double

    init(product: FoodProduct, meal: Meal, day: Date, onSaved: @escaping () -> Void) {
        self.product = product
        self._meal = State(initialValue: meal)
        self.day = day
        self.onSaved = onSaved
        self._grams = State(initialValue: product.servingGrams ?? 100)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(product.name).font(.headline)
                    if !product.brand.isEmpty { Text(product.brand).foregroundStyle(.secondary) }
                }
                Section("Quantité") {
                    HStack {
                        TextField("Grammes", value: $grams, format: .number)
                            .keyboardType(.decimalPad)
                        Text("g").foregroundStyle(.secondary)
                    }
                    HStack {
                        ForEach([50.0, 100, 150, 200], id: \.self) { value in
                            Button("\(Int(value)) g") { grams = value }.buttonStyle(.glass)
                        }
                    }
                    if let serving = product.servingGrams {
                        Button("1 portion (\(serving.noDecimal) g)") { grams = serving }
                    }
                    Picker("Repas", selection: $meal) {
                        ForEach(Meal.allCases) { Text($0.label).tag($0) }
                    }
                }
                Section("Pour \(grams.noDecimal) g") {
                    row("Calories", product.kcal100, "kcal")
                    row("Protéines", product.protein100, "g")
                    row("Glucides", product.carbs100, "g")
                    if let sugar = product.sugar100 { row("dont sucres", sugar, "g") }
                    row("Lipides", product.fat100, "g")
                    if let saturated = product.saturatedFat100 { row("dont saturés", saturated, "g") }
                    if let fiber = product.fiber100 { row("Fibres", fiber, "g") }
                    if let salt = product.salt100 { row("Sel", salt, "g") }
                }
                Section {
                    Text("Source : \(product.source)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Quantité")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") { save() }.disabled(grams <= 0)
                }
            }
        }
    }

    private func row(_ label: String, _ per100: Double, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text("\((per100 * grams / 100).oneDecimal) \(unit)").monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func save() {
        let key = product.key
        let descriptor = FetchDescriptor<FoodItem>(predicate: #Predicate { $0.key == key })
        let item: FoodItem
        if let existing = try? context.fetch(descriptor).first {
            item = existing
        } else {
            item = FoodItem(key: product.key, name: product.name, brand: product.brand, barcode: product.barcode,
                            source: product.source, kcal100: product.kcal100, protein100: product.protein100,
                            carbs100: product.carbs100, fat100: product.fat100)
            item.fiber100 = product.fiber100
            item.sugar100 = product.sugar100
            item.saturatedFat100 = product.saturatedFat100
            item.salt100 = product.salt100
            item.servingGrams = product.servingGrams
            context.insert(item)
        }
        item.lastUsed = .now
        item.useCount += 1

        // On garde l'heure actuelle si c'est aujourd'hui, sinon midi du jour choisi.
        let calendar = Calendar.current
        let date = calendar.isDateInToday(day) ? Date.now : (calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day)
        context.insert(FoodEntry(date: date, meal: meal, grams: grams, item: item))
        try? context.save()
        onSaved()
        dismiss()
    }
}

/// Création manuelle d'un aliment (valeurs de l'étiquette pour 100 g).
struct CustomFoodForm: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (FoodProduct) -> Void
    @State private var name = ""
    @State private var brand = ""
    @State private var kcal = 0.0
    @State private var protein = 0.0
    @State private var carbs = 0.0
    @State private var fat = 0.0
    @State private var fiber = 0.0
    @State private var serving = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $name)
                    TextField("Marque (facultatif)", text: $brand)
                }
                Section("Pour 100 g (voir l'étiquette)") {
                    field("Calories (kcal)", $kcal)
                    field("Protéines (g)", $protein)
                    field("Glucides (g)", $carbs)
                    field("Lipides (g)", $fat)
                    field("Fibres (g)", $fiber)
                }
                Section("Portion habituelle") {
                    field("Grammes (0 = aucune)", $serving)
                }
            }
            .navigationTitle("Nouvel aliment")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continuer") {
                        onCreate(FoodProduct(key: "custom|\(UUID().uuidString)", barcode: nil, name: name, brand: brand,
                                             source: "Créé par toi", kcal100: kcal, protein100: protein, carbs100: carbs,
                                             fat100: fat, fiber100: fiber > 0 ? fiber : nil, sugar100: nil,
                                             saturatedFat100: nil, salt100: nil, servingGrams: serving > 0 ? serving : nil))
                    }
                    .disabled(name.isEmpty || kcal <= 0)
                }
            }
        }
    }

    private func field(_ label: String, _ value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}
