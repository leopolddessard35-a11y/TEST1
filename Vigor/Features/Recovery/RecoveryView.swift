import SwiftUI
import Charts

/// Onglet Récup : chaque chiffre avec son contexte (écart à ta base + tendance),
/// explorateur jour par jour avec axe de temps synchronisé, tendances et croisements.
struct RecoveryView: View {
    enum Segment: String, CaseIterable {
        case today = "Vue"
        case explore = "Jour par jour"
        case trends = "Tendances"
        case symptoms = "Symptômes"
    }

    @State private var segment: Segment = .today

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
                        case .today: RecoveryTodaySection(snapshot: snapshot)
                        case .explore: DayExplorer(snapshot: snapshot)
                        case .trends: TrendsSection(snapshot: snapshot)
                        case .symptoms: JournalSection(patterns: snapshot.symptomPatterns)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Récup")
        }
    }
}

// MARK: - Chiffre avec contexte

/// Valeur + écart à la base personnelle + flèche de tendance (jamais un chiffre seul).
struct ContextTile: View {
    let kind: MetricKind
    let series: [DayValue]
    var sourceNote: String?
    var events: [ChartEvent] = []

    var body: some View {
        let context = MetricContext(series: series)
        NavigationLink {
            MetricDetailView(kind: kind, series: series, sourceNote: sourceNote, events: events)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(kind.title, systemImage: kind.symbol).font(.caption.weight(.medium)).foregroundStyle(kind.color)
                    Spacer()
                    DetailChevron()
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(context.latest.map { kind.format($0) } ?? "–").font(.title2.weight(.semibold)).monospacedDigit()
                    Text(kind == .sleep ? "" : kind.unit).font(.caption).foregroundStyle(.secondary)
                }
                if let delta = context.deltaText(kind) {
                    HStack(spacing: 4) {
                        Image(systemName: context.trendSymbol)
                        Text(delta)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(context.isFavorable(kind) ? Theme.recovery : (context.isUnfavorable(kind) ? Theme.warning : .secondary))
                } else {
                    Text("Base en cours de calcul").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }
}

/// Dernière valeur comparée à la médiane 60 j (écart robuste) + pente sur 14 j.
struct MetricContext {
    let latest: Double?
    let median: Double?
    let spread: Double?
    let slope: Double?

    init(series: [DayValue], today: Date = .now) {
        let sorted = series.sorted { $0.date < $1.date }
        latest = Stats.lastDays(3, of: sorted, today: today).last?.value
        let base = Stats.lastDays(60, of: sorted, today: today).map(\.value)
        median = base.count >= 7 ? Robust.median(base) : nil
        spread = base.count >= 7 ? Robust.mad(base) : nil
        slope = Stats.slopePerDay(Stats.lastDays(14, of: sorted, today: today))
    }

    var z: Double? {
        guard let latest, let median, let spread, spread > 0 else { return nil }
        return (latest - median) / spread
    }

    var trendSymbol: String {
        guard let slope else { return "arrow.right" }
        if abs(slope) < 0.001 { return "arrow.right" }
        return slope > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    func deltaText(_ kind: MetricKind) -> String? {
        guard let latest, let median, median != 0 else { return nil }
        if kind == .sleep { return "\(latest - median >= 0 ? "+" : "−")\(abs(latest - median).hoursText) vs ta base" }
        if kind == .restingHR || kind == .respiration {
            return String(format: "%+.1f %@ vs ta base", latest - median, kind.unit)
        }
        return String(format: "%+.0f %% vs ta base", (latest / median - 1) * 100)
    }

    func isFavorable(_ kind: MetricKind) -> Bool {
        guard let z, let better = kind.higherIsBetter else { return false }
        return better ? z > 0.5 : z < -0.5
    }

    func isUnfavorable(_ kind: MetricKind) -> Bool {
        guard let z, let better = kind.higherIsBetter else { return false }
        return better ? z < -1 : z > 1
    }
}

// MARK: - Aujourd'hui

private struct RecoveryTodaySection: View {
    let snapshot: CoachSnapshot

    var body: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                NavigationLink {
                    ReadinessDetailView(readiness: snapshot.readiness, history: Array(snapshot.readinessHistory.suffix(30)),
                                        hrvSource: snapshot.hrvSource)
                } label: {
                    SimpleTile(title: "Récupération", value: snapshot.readiness.map { "\($0.score) %" } ?? "–",
                               caption: snapshot.readiness?.level.label ?? "en attente de données",
                               symbol: "heart.text.square.fill", tint: snapshot.readiness.map { Theme.color(for: $0.level) } ?? .secondary)
                }
                NavigationLink {
                    SleepNeedDetailView(need: snapshot.sleepNeed, performance: snapshot.lastSleepPerformance,
                                        lastNight: snapshot.wellness.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0.sleepHours : nil },
                                        regularity: snapshot.bedtimeRegularity)
                } label: {
                    SimpleTile(title: "Besoin cette nuit", value: snapshot.sleepNeed.total.hoursText,
                               caption: "coucher vers \(snapshot.sleepNeed.bedtimeText)", symbol: "moon.zzz.fill", tint: Theme.sleep)
                }
                ContextTile(kind: .hrv, series: snapshot.hrvSeries, sourceNote: snapshot.hrvSource, events: snapshot.chartEvents)
                ContextTile(kind: .restingHR, series: MetricKind.restingHR.series(from: snapshot.wellness), events: snapshot.chartEvents)
                ContextTile(kind: .sleep, series: MetricKind.sleep.series(from: snapshot.wellness), events: snapshot.chartEvents)
                ContextTile(kind: .respiration, series: snapshot.respirationSeries, events: snapshot.chartEvents)
                ContextTile(kind: .weight, series: MetricKind.weight.series(from: snapshot.wellness), events: snapshot.chartEvents)
                ContextTile(kind: .vo2max, series: MetricKind.vo2max.series(from: snapshot.wellness), events: snapshot.chartEvents)
            }
            .buttonStyle(.plain)
            NavigationLink {
                InsightsView(insights: snapshot.insights)
            } label: {
                SimpleTile(title: "Analyse du coach", value: "\(snapshot.insights.count) observations",
                           caption: snapshot.insights.first?.title ?? "rien à signaler", symbol: "brain.head.profile", tint: Theme.strain)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Explorateur jour par jour (axe synchronisé)

private struct DayExplorer: View {
    let snapshot: CoachSnapshot
    @State private var selected: Date?
    @State private var days = 30

    var body: some View {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        let end = Date.now
        let sleep = MetricKind.sleep.series(from: snapshot.wellness).filter { $0.date >= start }
        let hrv = snapshot.hrvSeries.filter { $0.date >= start }
        let load = snapshot.load.filter { $0.date >= start }.map { DayValue(date: $0.date, value: $0.tss) }
        let weight = snapshot.weightMA7.filter { $0.date >= start }
        let day = selected.map { Calendar.current.startOfDay(for: $0) }

        VStack(spacing: 12) {
            RangePicker(days: $days)
            Text("Touche un jour sur n'importe quelle courbe : toutes les métriques de ce jour s'affichent.")
                .font(.caption).foregroundStyle(.secondary)
            SyncedChart(title: "Sommeil (h)", color: Theme.sleep, points: sleep, domain: start...end, selected: $selected, bars: false)
            SyncedChart(title: "VFC (ms)", color: Theme.recovery, points: hrv, domain: start...end, selected: $selected, bars: false)
            SyncedChart(title: "Charge (TSS)", color: Theme.strain, points: load, domain: start...end, selected: $selected, bars: true)
            SyncedChart(title: "Poids (kg, moy. 7 j)", color: Theme.nutrition, points: weight, domain: start...end, selected: $selected, bars: false)

            if let day {
                let record = snapshot.wellness.first { Calendar.current.isDate($0.day, inSameDayAs: day) }
                let nutrition = snapshot.nutritionDays.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
                let point = snapshot.load.first { Calendar.current.isDate($0.date, inSameDayAs: day) }
                let events = snapshot.chartEvents.filter { Calendar.current.startOfDay(for: $0.start) <= day && Calendar.current.startOfDay(for: $0.end) >= day }
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day.formatted(date: .complete, time: .omitted)).font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            StatTile(title: "Sommeil", value: record?.sleepHours?.hoursText ?? "–")
                            StatTile(title: "VFC", value: (record?.hrvRMSSD ?? record?.hrvMs)?.noDecimal ?? "–")
                            StatTile(title: "FC repos", value: record?.restingHeartRate?.noDecimal ?? "–")
                            StatTile(title: "Charge", value: point.map { $0.tss.noDecimal } ?? "–")
                            StatTile(title: "Forme", value: point.map { $0.form.noDecimal } ?? "–")
                            StatTile(title: "Poids", value: record?.weightKg?.oneDecimal ?? "–")
                            StatTile(title: "Calories", value: nutrition.map { $0.kcal.noDecimal } ?? "–")
                            StatTile(title: "Protéines", value: nutrition.map { "\($0.protein.noDecimal) g" } ?? "–")
                            StatTile(title: "Respiration", value: record?.respiration?.oneDecimal ?? "–")
                        }
                        ForEach(events) { event in
                            Label(event.label, systemImage: event.symbol).font(.footnote)
                        }
                    }
                }
            }
        }
    }
}

/// Courbe partageant le même axe de temps que les autres ; les trous de données restent visibles.
struct SyncedChart: View {
    let title: String
    let color: Color
    let points: [DayValue]
    let domain: ClosedRange<Date>
    @Binding var selected: Date?
    let bars: Bool

    var body: some View {
        let segments = DataGaps.segments(points)
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Chart {
                    if bars {
                        ForEach(points, id: \.date) { point in
                            BarMark(x: .value("Jour", point.date, unit: .day), y: .value(title, point.value))
                                .foregroundStyle(color.opacity(0.7))
                        }
                    } else {
                        ForEach(segments.indices, id: \.self) { index in
                            ForEach(segments[index], id: \.date) { point in
                                LineMark(x: .value("Jour", point.date), y: .value(title, point.value),
                                         series: .value("Segment", index))
                                    .foregroundStyle(color)
                                PointMark(x: .value("Jour", point.date), y: .value(title, point.value))
                                    .foregroundStyle(color)
                                    .symbolSize(10)
                            }
                        }
                    }
                    if let selected {
                        RuleMark(x: .value("Sélection", Calendar.current.startOfDay(for: selected), unit: .day))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: .automatic(includesZero: bars))
                .chartXSelection(value: $selected)
                .frame(height: 90)
            }
        }
    }
}

/// Découpe une série aux jours manquants : pas d'interpolation silencieuse.
enum DataGaps {
    static func segments(_ points: [DayValue], maxGapDays: Double = 1.5) -> [[DayValue]] {
        let sorted = points.sorted { $0.date < $1.date }
        var result: [[DayValue]] = []
        var current: [DayValue] = []
        for point in sorted {
            if let last = current.last, point.date.timeIntervalSince(last.date) > maxGapDays * 86_400 {
                result.append(current)
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Jours sans donnée dans la période (affichés comme « trous »).
    static func missingDays(_ points: [DayValue], days: Int, today: Date = .now, calendar: Calendar = .current) -> Int {
        let present = Set(points.map { calendar.startOfDay(for: $0.date) })
        var missing = 0
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: today)) else { continue }
            if !present.contains(day) { missing += 1 }
        }
        return missing
    }
}
