import SwiftUI
import SwiftData

/// Barre de saisie rapide (< 10 secondes) : effort ressenti, symptôme, eau, activité hors sport.
struct QuickEntryBar: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @State private var sheet: QuickSheet?

    enum QuickSheet: String, Identifiable {
        case rpe, symptom, life
        var id: String { rawValue }
    }

    var body: some View {
        HStack(spacing: 10) {
            button("Effort", "gauge.with.dots.needle.67percent") { sheet = .rpe }
            button("Symptôme", "bandage") { sheet = .symptom }
            Menu {
                ForEach([250.0, 500, 750], id: \.self) { ml in
                    Button("+ \(Int(ml)) ml") { addWater(ml) }
                }
            } label: {
                label("Eau", "drop.fill")
            }
            button("Hors sport", "hammer") { sheet = .life }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .rpe: RPESheet()
            case .symptom: SymptomForm()
            case .life: LifeActivityForm()
            }
        }
    }

    private func button(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { label(title, symbol) }
            .buttonStyle(.plain)
    }

    private func label(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.title3)
            Text(title).font(.caption2.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
    }

    private func addWater(_ ml: Double) {
        QuickActions.addWater(ml, context: context)
        app.dataVersion += 1
    }
}

enum QuickActions {
    @MainActor
    static func addWater(_ ml: Double, context: ModelContext, date: Date = .now) {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyWellness>(predicate: #Predicate { $0.day == day })
        let record: DailyWellness
        if let existing = try? context.fetch(descriptor).first {
            record = existing
        } else {
            record = DailyWellness(day: day)
            context.insert(record)
        }
        record.waterMl = (record.waterMl ?? 0) + ml
        try? context.save()
    }
}

// MARK: - RPE

/// Note l'effort ressenti des dernières séances (1 = très facile, 10 = maximal).
struct RPESheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query(sort: \CardioActivity.start, order: .reverse) private var activities: [CardioActivity]
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]

    var body: some View {
        let cutoff = Date.now.addingTimeInterval(-4 * 86_400)
        NavigationStack {
            List {
                Section {
                    Text("1–2 très facile · 3–4 facile · 5–6 soutenu · 7–8 dur · 9–10 maximal")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Endurance") {
                    ForEach(activities.filter { $0.start >= cutoff }) { activity in
                        RPERow(title: activity.title, date: activity.start, value: activity.rpe) { value in
                            activity.rpe = value
                            save()
                        }
                    }
                }
                Section("Musculation") {
                    ForEach(workouts.filter { $0.start >= cutoff }) { workout in
                        RPERow(title: workout.title, date: workout.start, value: workout.rpe) { value in
                            workout.rpe = value
                            save()
                        }
                    }
                }
            }
            .navigationTitle("Effort ressenti")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
    }

    private func save() {
        try? context.save()
        app.dataVersion += 1
    }
}

struct RPERow: View {
    let title: String
    let date: Date
    let value: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer()
                Text(date.formatted(.dateTime.weekday(.abbreviated).hour().minute())).font(.caption).foregroundStyle(.secondary)
            }
            RPEPicker(value: value, onSelect: onSelect)
        }
        .padding(.vertical, 4)
    }
}

struct RPEPicker: View {
    let value: Int?
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...10, id: \.self) { rpe in
                Button {
                    onSelect(rpe)
                } label: {
                    Text("\(rpe)")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 30)
                        .background(value == rpe ? RPEPicker.color(rpe) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 8))
                        .foregroundStyle(value == rpe ? .white : .primary)
                }
                .buttonStyle(.plain)
            }
        }
        .sensoryFeedback(.selection, trigger: value)
    }

    static func color(_ rpe: Int) -> Color {
        switch rpe {
        case ..<5: Theme.recovery
        case 5...6: Theme.nutrition
        case 7...8: Theme.strain
        default: Theme.warning
        }
    }
}

// MARK: - Symptôme

/// Saisie rapide d'un symptôme. Les derniers choix sont mémorisés pour aller vite.
struct SymptomForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @Query private var shoes: [Shoe]
    @AppStorage("symptom.last.zone") private var zoneRaw = BodyZone.foot.rawValue
    @AppStorage("symptom.last.side") private var sideRaw = BodySide.left.rawValue
    @AppStorage("symptom.last.type") private var typeRaw = SymptomType.numbness.rawValue
    @AppStorage("symptom.last.sport") private var sportRaw = Sport.running.rawValue
    @AppStorage("symptom.last.terrain") private var terrainRaw = Terrain.road.rawValue
    @AppStorage("symptom.last.shoe") private var shoeID = ""
    @AppStorage("symptom.last.onset") private var onset = 25
    @State private var intensity = 4.0
    @State private var duringEffort = true
    @State private var fatigue = 3
    @State private var durationMinutes = 10
    @State private var note = ""
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Zone", selection: $zoneRaw) {
                        ForEach(BodyZone.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Côté", selection: $sideRaw) {
                        ForEach(BodySide.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Type", selection: $typeRaw) {
                        ForEach(SymptomType.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    VStack(alignment: .leading) {
                        Text("Intensité : \(Int(intensity)) / 10")
                        Slider(value: $intensity, in: 0...10, step: 1)
                            .tint(RPEPicker.color(Int(intensity)))
                    }
                }
                Section("Contexte") {
                    Toggle("Pendant un effort", isOn: $duringEffort)
                    if duringEffort {
                        Stepper("Apparu après \(onset) min", value: $onset, in: 0...300, step: 5)
                        Picker("Sport", selection: $sportRaw) {
                            ForEach([Sport.running, .cycling, .indoorCycling, .strength, .other]) { Text($0.label).tag($0.rawValue) }
                        }
                        Picker("Terrain", selection: $terrainRaw) {
                            ForEach(Terrain.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        if !shoes.isEmpty {
                            Picker("Chaussures", selection: $shoeID) {
                                Text("Aucune / autre").tag("")
                                ForEach(shoes.filter { !$0.retired }) { Text($0.name).tag($0.shoeID) }
                            }
                        }
                    }
                    Picker("Fatigue avant", selection: $fatigue) {
                        ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper("A duré \(durationMinutes) min", value: $durationMinutes, in: 0...600, step: 5)
                    DatePicker("Quand", selection: $date)
                    TextField("Note (facultatif)", text: $note, axis: .vertical)
                }
            }
            .navigationTitle("Symptôme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Enregistrer") { save() } }
            }
        }
    }

    private func save() {
        let symptom = Symptom(date: date, zone: BodyZone(rawValue: zoneRaw) ?? .other, side: BodySide(rawValue: sideRaw) ?? .center,
                              type: SymptomType(rawValue: typeRaw) ?? .other, intensity: Int(intensity), fatigue: fatigue)
        if duringEffort {
            symptom.onsetMinutes = onset
            symptom.sportRaw = sportRaw
            symptom.terrainRaw = terrainRaw
            symptom.shoeID = shoeID.isEmpty ? nil : shoeID
        }
        symptom.durationMinutes = durationMinutes
        symptom.note = note
        context.insert(symptom)
        try? context.save()
        app.dataVersion += 1
        dismiss()
    }
}

// MARK: - Activité hors sport

struct LifeActivityForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @AppStorage("life.last.kind") private var kindRaw = LifeActivityKind.renovation.rawValue
    @State private var minutes = 120
    @State private var intensity = 2
    @State private var date = Date.now
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Activité", selection: $kindRaw) {
                    ForEach(LifeActivityKind.allCases) { Label($0.label, systemImage: $0.symbol).tag($0.rawValue) }
                }
                Stepper("Durée : \((Double(minutes) / 60).hoursText)", value: $minutes, in: 15...720, step: 15)
                Picker("Intensité", selection: $intensity) {
                    Text("Légère").tag(1)
                    Text("Modérée").tag(2)
                    Text("Dure").tag(3)
                }
                .pickerStyle(.segmented)
                DatePicker("Quand", selection: $date, displayedComponents: .date)
                TextField("Note (facultatif)", text: $note)
                Section {
                    let perHour: Double = intensity >= 3 ? 50 : (intensity == 2 ? 35 : 20)
                    let load: Double = Double(minutes) / 60 * perHour
                    Text(String(format: "≈ %.0f points de charge ajoutés à ta fatigue (comme une séance de %@ en endurance).", load, (load / 50).hoursText))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activité hors sport")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        context.insert(LifeActivity(date: date, kind: LifeActivityKind(rawValue: kindRaw) ?? .other,
                                                    minutes: minutes, intensity: intensity, note: note))
                        try? context.save()
                        app.dataVersion += 1
                        dismiss()
                    }
                }
            }
        }
    }
}
