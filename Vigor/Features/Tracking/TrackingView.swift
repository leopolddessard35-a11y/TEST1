import SwiftUI
import SwiftData
import Charts

/// Onglet Suivi : tendances, croisements, journal de symptômes, charge hors sport.
struct TrackingView: View {
    enum Segment: String, CaseIterable {
        case trends = "Tendances"
        case journal = "Journal"
        case life = "Hors sport"
    }

    @State private var segment: Segment = .trends

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Vue", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    SnapshotReader { _, snapshot in
                        switch segment {
                        case .trends: TrendsSection(snapshot: snapshot)
                        case .journal: JournalSection(patterns: snapshot.symptomPatterns)
                        case .life: LifeSection(lifeLoad7: snapshot.lifeLoad7)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Suivi")
        }
    }
}

// MARK: - Tendances

struct TrendsSection: View {
    let snapshot: CoachSnapshot
    @State private var days = 90

    var body: some View {
        VStack(spacing: 16) {
            if let report = snapshot.weeklyReport {
                WeeklyReportCard(report: report)
            }
            RangePicker(days: $days)
            TrendChart(title: "Effort (0–21)", color: Theme.strain, points: snapshot.effortHistory, days: days)
            TrendChart(title: "Respiration nocturne (resp/min)", color: Theme.sleep, points: snapshot.respirationSeries, days: days)
            TrendChart(title: "Sommeil (h)", color: Theme.sleep, points: MetricKind.sleep.series(from: snapshot.wellness), days: days)
            TrendChart(title: "VFC (ms)", color: Theme.recovery, points: snapshot.hrvSeries, days: days)
            TrendChart(title: "FC au repos (bpm)", color: Theme.warning, points: MetricKind.restingHR.series(from: snapshot.wellness), days: days)
            TrendChart(title: "Condition (CTL)", color: Theme.strain,
                       points: snapshot.load.map { DayValue(date: $0.date, value: $0.ctl) }, days: days, smooth: false)
            TrendChart(title: "Poids (kg, moyenne 7 j)", color: Theme.nutrition, points: snapshot.weightMA7, days: days, smooth: false)
            TrendChart(title: "Calories (kcal)", color: Theme.sleep,
                       points: snapshot.nutritionDays.filter { $0.kcal > 800 }.map { DayValue(date: $0.date, value: $0.kcal) }, days: days)

            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(title: "Croisements de tes données", symbol: "point.3.connected.trianglepath.dotted")
                    if snapshot.correlations.isEmpty {
                        Text("Il faut au moins 14 jours de données croisées (sommeil, VFC, séances, repas) pour détecter des liens fiables.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(snapshot.correlations) { correlation in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(correlation.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(String(format: "r = %+.2f", correlation.r)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                            AnimatedBar(fraction: abs(correlation.r), color: correlation.r >= 0 ? Theme.recovery : Theme.strain, height: 6)
                            Text("\(correlation.isHint ? "Indice" : "Résultat") · \(correlation.strength) (\(correlation.lagLabel)) · \(correlation.interpretation)").font(.caption)
                            Text("n = \(correlation.n) jours" + (correlation.confidence.map { String(format: " · IC 95 %% : %+.2f à %+.2f", $0.lowerBound, $0.upperBound) } ?? ""))
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    Text("Spearman, de −1 à +1. « Indice » = moins de 30 jours ou intervalle de confiance qui inclut 0 : à confirmer. Un lien n'est pas une cause : teste-le avec une expérience N = 1 ci-dessous.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            ExperimentsCard(snapshot: snapshot)
        }
    }
}

/// Courbe avec moyenne mobile 7 jours (semaine / mois / saison selon la période).
struct TrendChart: View {
    let title: String
    let color: Color
    let points: [DayValue]
    let days: Int
    var smooth = true

    var body: some View {
        let visible: [DayValue] = Stats.lastDays(days, of: points.sorted { $0.date < $1.date }, today: .now)
        let average: [DayValue] = smooth ? TrendChart.movingAverage(visible, window: days > 120 ? 28 : 7) : []
        let mean: Double? = Stats.mean(visible.map(\.value))
        let center: Double? = visible.count >= 7 ? Robust.median(visible.map(\.value)) : nil
        let spread: Double = Robust.mad(visible.map(\.value)) ?? 0
        let segments: [[DayValue]] = DataGaps.segments(visible)
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let mean { Text("moy. \(mean.oneDecimal)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                }
                if visible.count < 2 {
                    Text("Pas assez de données.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Chart {
                        if let center, spread > 0, let first = visible.first?.date, let last = visible.last?.date {
                            RectangleMark(xStart: .value("Début", first), xEnd: .value("Fin", last),
                                          yStart: .value("Bas", center - spread), yEnd: .value("Haut", center + spread))
                                .foregroundStyle(color.opacity(0.1))
                        }
                        if smooth {
                            ForEach(visible, id: \.date) { point in
                                PointMark(x: .value("Jour", point.date), y: .value(title, point.value))
                                    .foregroundStyle(color.opacity(0.35))
                                    .symbolSize(12)
                            }
                        } else {
                            ForEach(segments.indices, id: \.self) { index in
                                ForEach(segments[index], id: \.date) { point in
                                    LineMark(x: .value("Jour", point.date), y: .value(title, point.value), series: .value("Segment", index))
                                        .foregroundStyle(color)
                                }
                            }
                        }
                        ForEach(average, id: \.date) { point in
                            LineMark(x: .value("Jour", point.date), y: .value("Moyenne", point.value))
                                .foregroundStyle(color)
                                .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 120)
                    if smooth {
                        Text(days > 120 ? "Ligne : moyenne mobile 28 jours" : "Ligne : moyenne mobile 7 jours").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    static func movingAverage(_ points: [DayValue], window: Int) -> [DayValue] {
        var result: [DayValue] = []
        for point in points {
            let start = point.date.addingTimeInterval(-Double(window - 1) * 86_400)
            let values: [Double] = points.filter { $0.date >= start && $0.date <= point.date }.map(\.value)
            if values.count >= max(2, window / 3), let mean = Stats.mean(values) {
                result.append(DayValue(date: point.date, value: mean))
            }
        }
        return result
    }
}

// MARK: - Journal de symptômes

struct JournalSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \Symptom.date, order: .reverse) private var symptoms: [Symptom]
    @Query private var shoes: [Shoe]
    let patterns: [SymptomPattern]
    @State private var adding = false
    @State private var pdf: URL?

    var body: some View {
        VStack(spacing: 16) {
            Button { adding = true } label: {
                Label("Noter un symptôme", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            if !symptoms.isEmpty {
                Button {
                    pdf = try? Exporter.symptomReport(symptoms: symptoms, patterns: patterns, shoes: shoes)
                } label: {
                    Label("Préparer le PDF pour ton podologue / médecin", systemImage: "doc.richtext")
                }
                .buttonStyle(.glass)
                if let pdf {
                    ShareLink(item: pdf) { Label("Partager le PDF", systemImage: "square.and.arrow.up") }
                }
                Text("L'app repère des corrélations, elle ne pose pas de diagnostic. Un engourdissement récurrent mérite un avis podologue ou médical.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if symptoms.isEmpty {
                EmptyStateCard(title: "Journal vide",
                               message: "Note chaque symptôme dès qu'il apparaît (ex. engourdissement du pied gauche après 25 min) : zone, intensité, moment, chaussures, terrain, fatigue. Après quelques entrées, l'app cherche ce qui le déclenche ou le retarde.",
                               symbol: "list.clipboard")
            }

            ForEach(patterns) { pattern in
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(pattern.key).font(.headline)
                            Spacer()
                            if pattern.isRecurrent {
                                Text("récurrent").font(.caption2.weight(.bold)).foregroundStyle(Theme.warning)
                            }
                        }
                        HStack {
                            StatTile(title: "Épisodes", value: "\(pattern.count)", caption: "\(pattern.recentCount) sur 14 j")
                            StatTile(title: "Intensité", value: String(format: "%.1f / 10", pattern.averageIntensity))
                            StatTile(title: "Apparition", value: pattern.averageOnset.map { String(format: "%.0f min", $0) } ?? "–")
                        }
                        let episodes = symptoms.filter { $0.key == pattern.key }
                        if episodes.count >= 2 {
                            Chart(episodes) { symptom in
                                PointMark(x: .value("Date", symptom.date), y: .value("Intensité", Double(symptom.intensity)))
                                    .foregroundStyle(Theme.warning)
                                if let onset = symptom.onsetMinutes {
                                    BarMark(x: .value("Date", symptom.date, unit: .day), y: .value("Apparition (min)", Double(onset) / 10))
                                        .foregroundStyle(Theme.sleep.opacity(0.35))
                                }
                            }
                            .chartYScale(domain: 0...10)
                            .frame(height: 110)
                            Text("Points : intensité · barres : minute d'apparition (÷ 10)").font(.caption2).foregroundStyle(.secondary)
                        }
                        if pattern.findings.isEmpty {
                            Text("Pas encore assez d'épisodes variés pour comparer les contextes (chaussures, terrain, fatigue).")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Ce qui change selon le contexte").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            ForEach(pattern.findings, id: \.self) { Text("• \($0)").font(.footnote) }
                        }
                    }
                }
            }

            if !symptoms.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Toutes les entrées", symbol: "list.bullet")
                        ForEach(symptoms.prefix(40)) { symptom in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(symptom.key).font(.subheadline.weight(.medium))
                                    Text(details(symptom)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(symptom.intensity)/10").font(.subheadline.monospacedDigit())
                                Menu {
                                    Button("Supprimer", systemImage: "trash", role: .destructive) {
                                        context.delete(symptom)
                                        try? context.save()
                                        app.dataVersion += 1
                                    }
                                } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { SymptomForm() }
    }

    private func details(_ symptom: Symptom) -> String {
        var parts = [symptom.date.formatted(date: .abbreviated, time: .shortened)]
        if let onset = symptom.onsetMinutes { parts.append("après \(onset) min") }
        if let sport = symptom.sport { parts.append(sport.label.lowercased()) }
        if let terrain = symptom.terrain { parts.append(terrain.label.lowercased()) }
        if let id = symptom.shoeID, let shoe = shoes.first(where: { $0.shoeID == id }) { parts.append(shoe.name) }
        parts.append("fatigue \(symptom.fatigue)/5")
        if !symptom.note.isEmpty { parts.append(symptom.note) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Charge hors sport

struct LifeSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \LifeActivity.date, order: .reverse) private var activities: [LifeActivity]
    let lifeLoad7: Double
    @State private var adding = false

    var body: some View {
        VStack(spacing: 16) {
            Button { adding = true } label: {
                Label("Ajouter une activité physique hors sport", systemImage: "plus.circle.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            GlassCard {
                VStack(alignment: .leading, spacing: 6) {
                    SectionTitle(title: "Pourquoi c'est compté", symbol: "lightbulb")
                    Text("Une journée de rénovation, un déménagement ou 10 h debout fatiguent autant qu'une séance. Vigor les convertit en charge (≈ 20 / 35 / 50 points par heure selon l'intensité) et ajoute les pas au-delà de 12 000 : ta fatigue et le plan du jour en tiennent compte.")
                        .font(.footnote)
                    Text(String(format: "Cette semaine : ≈ %.0f points de charge hors sport.", lifeLoad7)).font(.footnote.weight(.semibold))
                }
            }

            ForEach(activities.prefix(40)) { activity in
                GlassCard {
                    HStack {
                        Image(systemName: activity.kind.symbol).font(.title3).frame(width: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.kind.label).font(.subheadline.weight(.semibold))
                            Text("\(activity.date.formatted(date: .abbreviated, time: .omitted)) · \((Double(activity.minutes) / 60).hoursText) · \(["", "légère", "modérée", "dure"][min(max(activity.intensity, 1), 3)])")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(activity.loadEquivalent.noDecimal) pts").font(.caption.monospacedDigit())
                        Menu {
                            Button("Supprimer", systemImage: "trash", role: .destructive) {
                                context.delete(activity)
                                try? context.save()
                                app.dataVersion += 1
                            }
                        } label: { Image(systemName: "ellipsis.circle").foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .sheet(isPresented: $adding) { LifeActivityForm() }
    }
}
