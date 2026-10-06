import SwiftUI
import SwiftData

/// Expériences N = 1 : tester un changement 2 à 3 semaines et comparer avant / pendant.
struct ExperimentsCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Experiment.start, order: .reverse) private var experiments: [Experiment]
    let snapshot: CoachSnapshot
    @State private var adding = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Expériences N = 1", symbol: "flask.fill")
                    Spacer()
                    Button { adding = true } label: { Image(systemName: "plus") }.buttonStyle(.glass)
                }
                if experiments.isEmpty {
                    Text("Teste un changement (dîner plus tôt, coucher fixe, autre chaussure, pas d'écran le soir…) pendant 2 à 3 semaines : l'app compare la métrique choisie avant et pendant.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(experiments) { experiment in
                    let series = ExperimentsCard.series(for: experiment.metricRaw, snapshot: snapshot)
                    let result = ExperimentAnalysis.analyze(series: series, start: experiment.start, end: experiment.end)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(experiment.name).font(.subheadline.weight(.semibold))
                            Spacer()
                            Menu {
                                if experiment.end == nil {
                                    Button("Terminer aujourd'hui") { experiment.end = .now; save() }
                                }
                                Button("Supprimer", role: .destructive) { context.delete(experiment); save() }
                            } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                        }
                        Text("\(ExperimentsCard.metricLabel(experiment.metricRaw)) · depuis le \(experiment.start.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            StatTile(title: "Avant", value: result.before.map { $0.oneDecimal } ?? "–", caption: "\(result.nBefore) j")
                            StatTile(title: "Pendant", value: result.during.map { $0.oneDecimal } ?? "–", caption: "\(result.nDuring) j")
                            StatTile(title: "Écart", value: result.changePercent.map { String(format: "%+.0f %%", $0) } ?? "–",
                                     caption: result.effectSize.map { String(format: "d = %.2f", $0) } ?? "")
                        }
                        Text(result.verdict).font(.footnote)
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { ExperimentForm() }
    }

    private func save() {
        try? context.save()
        app.dataVersion += 1
    }

    struct MetricOption: Identifiable {
        var id: String { raw }
        let raw: String
        let label: String
    }

    static let metrics: [MetricOption] = [
        MetricOption(raw: "readiness", label: "Récupération"),
        MetricOption(raw: MetricKind.hrv.rawValue, label: "VFC"),
        MetricOption(raw: MetricKind.sleep.rawValue, label: "Sommeil"),
        MetricOption(raw: MetricKind.restingHR.rawValue, label: "FC au repos"),
        MetricOption(raw: MetricKind.respiration.rawValue, label: "Respiration"),
    ]

    static func metricLabel(_ raw: String) -> String { metrics.first { $0.raw == raw }?.label ?? raw }

    static func series(for raw: String, snapshot: CoachSnapshot) -> [DayValue] {
        if raw == "readiness" { return snapshot.readinessHistory }
        if raw == MetricKind.hrv.rawValue { return snapshot.hrvSeries }
        guard let kind = MetricKind(rawValue: raw) else { return [] }
        return kind.series(from: snapshot.wellness)
    }
}

struct ExperimentForm: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app
    @State private var name = ""
    @State private var start = Date.now
    @State private var metricRaw = "readiness"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Changement testé (ex. dîner avant 19 h 30)", text: $name)
                DatePicker("Début", selection: $start, displayedComponents: .date)
                Picker("Métrique suivie", selection: $metricRaw) {
                    ForEach(ExperimentsCard.metrics) { Text($0.label).tag($0.raw) }
                }
                Section {
                    Text("Garde le reste stable pendant l'essai. Comparaison : moyenne pendant l'expérience vs la même durée juste avant, avec la taille d'effet (d de Cohen).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Nouvelle expérience")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Démarrer") {
                        context.insert(Experiment(name: name, start: start, metricRaw: metricRaw))
                        try? context.save()
                        app.dataVersion += 1
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
