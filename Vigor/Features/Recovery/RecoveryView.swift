import SwiftUI
import Charts
import SwiftData

/// Onglet Récup : chaque chiffre avec son contexte (écart à ta base + tendance),
/// explorateur jour par jour avec axe de temps synchronisé, tendances et croisements.
struct RecoveryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(SyncService.self) private var sync
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { _, snapshot in
                    // Santé = surveiller. Chaque mesure a ici son unique « domicile » ; les analyses sont au 2e niveau.
                    VStack(spacing: 12) {
                        SectionHeader(title: "Moniteur", trailing: "vs ta normale", symbol: "heart.text.square.fill")
                        HealthMonitorGrid(snapshot: snapshot)

                        SectionHeader(title: "Sommeil", symbol: "bed.double.fill")
                        SleepSummaryCard(snapshot: snapshot)

                        SectionHeader(title: "Corps", symbol: "figure.stand")
                        BodyJournalCard(snapshot: snapshot)

                        SectionHeader(title: "Analyses", symbol: "chart.xyaxis.line")
                        GlassCard {
                            VStack(spacing: 0) {
                                NavigationLink {
                                    ReadinessDetailView(readiness: snapshot.readiness, history: Array(snapshot.readinessHistory.suffix(30)),
                                                        hrvSource: snapshot.hrvSource)
                                } label: {
                                    LinkRow(symbol: "heart.text.square", title: "Récupération",
                                            subtitle: "Comment le score est calculé, 30 derniers jours")
                                }
                                Divider().padding(.leading, 44)
                                NavigationLink {
                                    DetailPage(title: "Jour par jour") { DayExplorer(snapshot: snapshot) }
                                } label: {
                                    LinkRow(symbol: "calendar.day.timeline.left", title: "Jour par jour",
                                            subtitle: "Sommeil, VFC, charge et repas sur un même axe")
                                }
                                Divider().padding(.leading, 44)
                                NavigationLink {
                                    DetailPage(title: "Tendances") { TrendsSection(snapshot: snapshot) }
                                } label: {
                                    LinkRow(symbol: "chart.line.uptrend.xyaxis", title: "Tendances et liens",
                                            subtitle: "Ce qui influence ta forme, expériences")
                                }
                                Divider().padding(.leading, 44)
                                NavigationLink {
                                    InsightsView(insights: snapshot.insights)
                                } label: {
                                    LinkRow(symbol: "brain.head.profile", title: "Analyse du coach",
                                            subtitle: snapshot.insights.first?.title ?? "Rien à signaler",
                                            badge: snapshot.insights.isEmpty ? nil : "\(snapshot.insights.count)")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(AppBackground())
            .navigationTitle("Santé")
            // « Tire vers le bas pour synchroniser » : même synchro que l'accueil.
            .refreshable {
                try? await sync.syncSleepData(force: true)
                await app.syncAll(context: context, profile: profiles.first)
            }
        }
    }
}

/// La nuit dernière et la nuit à venir.
private struct SleepSummaryCard: View {
    let snapshot: CoachSnapshot

    var body: some View {
        let last = snapshot.wellness.last { $0.anySleepHours != nil }
        NavigationLink {
            SleepDetailView(snapshot: snapshot)
        } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            CapsLabel(last.map { Calendar.current.isDateInToday($0.day) ? "Cette nuit" : $0.day.formatted(.dateTime.weekday(.wide).day()) } ?? "Dernière nuit")
                            if let hours = last?.anySleepHours {
                                Text(hours.hoursText)
                                    .font(.system(.title, design: .rounded).weight(.heavy)).monospacedDigit()
                            } else {
                                Text("Pas encore de nuit : ouvre l'app de ta montre (Garmin Connect…) puis tire vers le bas pour synchroniser.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let score = snapshot.lastSleepScore {
                            StatusPill(text: "Score \(score.score) · \(score.label.lowercased())",
                                       symbol: score.score >= 70 ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                       color: score.score >= 70 ? Theme.good : (score.score >= 50 ? Theme.caution : Theme.alert))
                        }
                        DetailChevron()
                    }
                    if let bed = last?.bedtime, let wake = last?.wakeTime {
                        Label("\(bed.formatted(date: .omitted, time: .shortened)) → \(wake.formatted(date: .omitted, time: .shortened))",
                              systemImage: "clock")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Divider()
                    HStack {
                        Label("Ce soir : coucher vers \(snapshot.sleepNeed.bedtimeText)", systemImage: "moon.zzz.fill")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(snapshot.sleepNeed.total.hoursText).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

/// Symptômes et blessures : un résumé, le détail au tap.
private struct BodyJournalCard: View {
    let snapshot: CoachSnapshot
    @Query(sort: \Injury.start, order: .reverse) private var injuries: [Injury]
    @Query(sort: \Symptom.date, order: .reverse) private var symptoms: [Symptom]
    @State private var addingInjury = false

    var body: some View {
        let active = injuries.filter(\.isActive)
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let recent = symptoms.filter { $0.date >= weekAgo }.count
        GlassCard {
            VStack(spacing: 0) {
                NavigationLink {
                    DetailPage(title: "Blessures") {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 10) {
                                if active.isEmpty {
                                    Text("Aucune blessure en cours.").foregroundStyle(.secondary)
                                }
                                ForEach(active) { injury in InjuryRow(injury: injury) }
                            }
                        }
                        Button { addingInjury = true } label: {
                            Label("Déclarer une blessure", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(Theme.accent)
                        .controlSize(.large)
                    }
                    .sheet(isPresented: $addingInjury) { InjuryForm() }
                } label: {
                    LinkRow(symbol: "cross.case", title: "Blessures",
                            subtitle: active.isEmpty ? "Aucune en cours" : active.map(\.title).joined(separator: ", "),
                            badge: active.isEmpty ? nil : "\(active.count)", badgeColor: Theme.alert)
                }
                Divider().padding(.leading, 44)
                NavigationLink {
                    DetailPage(title: "Symptômes") { JournalSection(patterns: snapshot.symptomPatterns) }
                } label: {
                    LinkRow(symbol: "bandage", title: "Journal des symptômes",
                            subtitle: symptomSubtitle(recent: recent),
                            badge: recent == 0 ? nil : "\(recent)", badgeColor: Theme.caution)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func symptomSubtitle(recent: Int) -> String {
        if recent == 0 { return "Rien cette semaine" }
        let recurrent = snapshot.symptomPatterns.contains(where: \.isRecurrent)
        return "\(recent) cette semaine" + (recurrent ? " · motifs récurrents détectés" : "")
    }
}

// MARK: - Explorateur jour par jour (axe synchronisé)

struct DayExplorer: View {
    let snapshot: CoachSnapshot
    @State private var selected: Date?
    @State private var days = 30

    var body: some View {
        let todayStart = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: todayStart) ?? .now
        // Fin du domaine = fin de la journée : la barre ou le point d'aujourd'hui n'est pas coupé.
        let end = Calendar.current.date(byAdding: .day, value: 1, to: todayStart) ?? .now
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
                            StatTile(title: "Sommeil", value: record?.anySleepHours?.hoursText ?? "–")
                            StatTile(title: "VFC", value: (record?.hrvRMSSD ?? record?.hrvMs)?.noDecimal ?? "–")
                            StatTile(title: "FC repos", value: record?.anyRestingHeartRate?.noDecimal ?? "–")
                            StatTile(title: "Charge", value: point.map { $0.tss.noDecimal } ?? "–")
                            StatTile(title: "Forme", value: point.map { $0.form.noDecimal } ?? "–")
                            StatTile(title: "Poids", value: record?.anyWeightKg?.oneDecimal ?? "–")
                            StatTile(title: "Calories", value: nutrition.map { $0.kcal.noDecimal } ?? "–")
                            StatTile(title: "Protéines", value: nutrition.map { "\($0.protein.noDecimal) g" } ?? "–")
                            StatTile(title: "Respiration", value: record?.anyRespiration?.oneDecimal ?? "–")
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
                        RuleMark(x: .value("Sélection", Calendar.current.startOfDay(for: selected)))
                            .foregroundStyle(Color.primary.opacity(0.4))
                    }
                }
                .chartXScale(domain: domain)
                .chartYScale(domain: .automatic(includesZero: bars))
                .chartXSelection(value: $selected)
                .dateAxis(days: max(1, Int(domain.upperBound.timeIntervalSince(domain.lowerBound) / 86_400)))
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
