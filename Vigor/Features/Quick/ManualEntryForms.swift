import SwiftUI
import SwiftData

/// Séance d'endurance saisie à la main (sans montre, salle, vélo d'un ami…).
struct CardioEntryForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query(sort: \CardioActivity.start, order: .reverse) private var activities: [CardioActivity]
    @State private var sportRaw = Sport.cycling.rawValue
    @State private var title = ""
    @State private var start = Date.now.addingTimeInterval(-3600)
    @State private var minutes = 60
    @State private var distanceKm: Double?
    @State private var elevation: Double?
    @State private var power: Double?
    @State private var heartRate: Double?
    @State private var rpe: Int?

    private var sport: Sport { Sport(rawValue: sportRaw) ?? .cycling }

    var body: some View {
        let duplicate = activities.prefix(50).first { activity in
            ActivityDeduplicator.isSameSession(sportA: activity.sport, startA: activity.start, durationA: activity.durationSeconds,
                                               sportB: sport, startB: start, durationB: Double(minutes) * 60)
        }
        NavigationStack {
            Form {
                Section {
                    Picker("Sport", selection: $sportRaw) {
                        ForEach([Sport.cycling, .indoorCycling, .running, .other]) { item in
                            Label(item.label, systemImage: item.symbol).tag(item.rawValue)
                        }
                    }
                    TextField("Nom (facultatif)", text: $title)
                    DatePicker("Début", selection: $start)
                    Stepper("Durée : \(minutes) min", value: $minutes, in: 5...600, step: 5)
                }
                Section("Détails (facultatifs)") {
                    numberField("Distance", unit: "km", value: $distanceKm)
                    numberField("Dénivelé", unit: "m", value: $elevation)
                    if sport.isCycling { numberField("Puissance moyenne", unit: "W", value: $power) }
                    numberField("FC moyenne", unit: "bpm", value: $heartRate)
                }
                Section("Effort ressenti") {
                    RPEPicker(value: rpe) { rpe = $0 }
                }
                if let duplicate {
                    Section {
                        Label("Une séance proche existe déjà (\(duplicate.title), \(duplicate.source)). L'enregistrer la compterait deux fois dans ta charge.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warning)
                    }
                }
            }
            .navigationTitle("Séance d'endurance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
        }
    }

    private func numberField(_ label: String, unit: String, value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("–", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces).isEmpty ? sport.label : title
        let activity = CardioActivity(externalID: "vigor-\(UUID().uuidString)", source: "Vigor", sport: sport,
                                      title: name, start: start, durationSeconds: Double(minutes) * 60)
        activity.distanceMeters = distanceKm.map { $0 * 1000 }
        activity.elevationGain = elevation
        activity.averagePower = sport.isCycling ? power : nil
        activity.averageHeartRate = heartRate
        activity.rpe = rpe
        context.insert(activity)
        try? context.save()
        app.dataVersion += 1
        dismiss()
    }
}

/// Pesée manuelle (balance non connectée à Apple Santé).
struct WeightEntryForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query(sort: \DailyWellness.day, order: .reverse) private var wellness: [DailyWellness]
    @State private var weight: Double = 72
    @State private var day = Date.now
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button { weight = max(30, weight - 0.1) } label: { Image(systemName: "minus.circle.fill").font(.title) }
                            .buttonStyle(.plain)
                        Spacer()
                        Text(String(format: "%.1f kg", weight)).font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                        Spacer()
                        Button { weight = min(250, weight + 0.1) } label: { Image(systemName: "plus.circle.fill").font(.title) }
                            .buttonStyle(.plain)
                    }
                    .foregroundStyle(Theme.nutrition)
                    .padding(.vertical, 8)
                    Slider(value: $weight, in: 40...130, step: 0.1)
                    DatePicker("Jour", selection: $day, displayedComponents: .date)
                }
                Section {
                    Text("Pèse-toi le matin, à jeun, après être passé aux toilettes : c'est la mesure la plus comparable d'un jour à l'autre. Vigor lisse la courbe sur 7 jours.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Pesée")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                if let last = wellness.first(where: { $0.weightKg != nil })?.weightKg { weight = last }
            }
        }
    }

    private func save() {
        let start = Calendar.current.startOfDay(for: day)
        let descriptor = FetchDescriptor<DailyWellness>(predicate: #Predicate { $0.day == start })
        let record: DailyWellness
        if let existing = try? context.fetch(descriptor).first {
            record = existing
        } else {
            record = DailyWellness(day: start)
            context.insert(record)
        }
        record.weightKg = (weight * 10).rounded() / 10
        try? context.save()
        app.dataVersion += 1
        dismiss()
    }
}
