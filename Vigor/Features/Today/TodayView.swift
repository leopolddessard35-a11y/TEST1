import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Environment(SyncService.self) private var sync
    @Query private var profiles: [AthleteProfile]
    @State private var showSettings = false
    @State private var addingFood = false

    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { _, snapshot in
                    // Niveau 1 : les trois anneaux + le coaching. Niveau 2 : le moniteur. Niveau 3 : le détail, au tap.
                    VStack(spacing: 12) {
                        SyncStatusBadge()
                        RingsCoachingCard(snapshot: snapshot)

                        SectionHeader(title: "Moniteur de santé", trailing: "vs ta normale", symbol: "heart.text.square.fill", tint: Theme.warning)
                        HealthMonitorGrid(snapshot: snapshot)

                        SectionHeader(title: "Énergie", symbol: "bolt.fill", tint: Theme.recovery)
                        NavigationLink {
                            DailyBriefDetailView(brief: snapshot.brief, confidence: snapshot.confidence)
                        } label: {
                            EnergyCard(brief: snapshot.brief)
                        }
                        .buttonStyle(.plain)

                        SectionHeader(title: "Aliments du jour", symbol: "fork.knife", tint: Theme.nutrition)
                        if let targets = snapshot.macroTargets {
                            TodayNutritionCard(targets: targets, today: snapshot.todayNutrition) { addingFood = true }
                        } else {
                            Button { addingFood = true } label: {
                                Label("Ajouter un repas", systemImage: "plus").font(.headline).frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                        }

                        if let report = snapshot.weeklyReport, let review = snapshot.weeklyReview,
                           [1, 2].contains(Calendar.current.component(.weekday, from: .now)) {
                            SectionHeader(title: "Revue de la semaine", symbol: "calendar", tint: Theme.sleep)
                            NavigationLink {
                                DetailPage(title: "Revue de la semaine") { WeeklyReviewCard(report: report, review: review) }
                            } label: {
                                SimpleTile(title: "Point fort", value: review.strongPoint, caption: review.adjustment,
                                           symbol: "calendar.badge.checkmark", tint: Theme.sleep)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(AppBackground())
            .navigationTitle("Aujourd'hui, \(Date.now.formatted(.dateTime.day().month(.abbreviated)))")
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $addingFood) { AddFoodView { app.dataVersion += 1 } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await app.syncAll(context: context, profile: profiles.first) }
                    } label: {
                        if app.isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                }
            }
            .refreshable {
                try? await sync.syncSleepData(force: true)
                await app.syncAll(context: context, profile: profiles.first)
            }
        }
    }
}

/// Carte principale façon Bevel : effort, récupération, sommeil en anneaux, puis le coaching du jour.
private struct RingsCoachingCard: View {
    let snapshot: CoachSnapshot

    var body: some View {
        let brief = snapshot.brief
        VStack(alignment: .leading, spacing: 16) {
            // Héros façon Whoop : la récupération en grand, colorée selon sa zone ; effort et sommeil autour (Bevel).
            HStack(alignment: .top, spacing: 4) {
                NavigationLink {
                    EffortDetailView(today: snapshot.effortToday, target: snapshot.effortTarget, history: snapshot.effortHistory,
                                     verdict: brief.verdict)
                } label: {
                    SideRing(title: "Effort", fraction: snapshot.effortToday / 21,
                             text: snapshot.effortToday < 0.05 ? "0" : snapshot.effortToday.oneDecimal,
                             suffix: "/21", colors: Theme.strainGradient)
                }
                NavigationLink {
                    ReadinessDetailView(readiness: snapshot.readiness, history: Array(snapshot.readinessHistory.suffix(30)),
                                        hrvSource: snapshot.hrvSource)
                } label: {
                    HeroRing(readiness: snapshot.readiness)
                }
                NavigationLink {
                    SleepNeedDetailView(need: snapshot.sleepNeed, performance: snapshot.lastSleepPerformance,
                                        lastNight: snapshot.wellness.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0.sleepHours : nil },
                                        regularity: snapshot.bedtimeRegularity)
                } label: {
                    SideRing(title: "Sommeil", fraction: snapshot.lastSleepPerformance ?? 0,
                             text: snapshot.lastSleepPerformance.map { "\(Int(($0 * 100).rounded()))" } ?? "–", suffix: "%",
                             colors: Theme.sleepGradient)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Divider()

            NavigationLink {
                DailyBriefDetailView(brief: brief, confidence: snapshot.confidence)
            } label: {
                let summary = CoachSummary.make(snapshot)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        CapsLabel("Coaching")
                        Spacer()
                        StatusPill(text: summary.pill, symbol: summary.pillSymbol,
                                   color: summary.isRestDay && summary.pill == "Jour de repos" ? Theme.sleep : brief.verdict.color)
                        DetailChevron()
                    }
                    Text(summary.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !summary.isRestDay {
                        ForEach(brief.adapted.filter { $0.kind != .rest }) { session in
                            SessionRow(session: session, changed: !brief.planned.contains(session), compact: true)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 14, style: .continuous))
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .scrollAppear()
    }
}

/// Grand anneau de récupération : couleur de zone (vert ≥ 67, jaune 34–66, rouge < 34), chiffre massif.
/// Le libellé est SOUS l'anneau : rien ne déborde, quelle que soit la taille de texte.
private struct HeroRing: View {
    let readiness: ReadinessResult?

    var body: some View {
        let color: Color = readiness.map { Theme.color(for: $0.level) } ?? .secondary
        let fraction = Double(readiness?.score ?? 0) / 100
        VStack(spacing: 8) {
            ZStack {
                GradientRing(fraction: fraction, colors: [color.opacity(0.5), color], lineWidth: 13)
                VStack(spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(readiness.map { "\($0.score)" } ?? "–")
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                        Text("%").font(.system(.headline, design: .rounded).weight(.bold)).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    Text(readiness?.level.label ?? "En calibrage")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 22)
            }
            .frame(width: 136, height: 136)
            CapsLabel("Récupération")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

/// Anneau latéral compact, libellé en capitales sous l'anneau.
private struct SideRing: View {
    let title: String
    let fraction: Double
    let text: String
    let suffix: String
    let colors: [Color]

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                GradientRing(fraction: fraction, colors: colors, lineWidth: 7)
                VStack(spacing: 0) {
                    Text(text).font(.system(.headline, design: .rounded).weight(.heavy)).monospacedDigit()
                    Text(suffix).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
            }
            .frame(width: 72, height: 72)
            .frame(height: 136)
            CapsLabel(title)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Grille 2 colonnes : chaque mesure du matin comparée à ta normale des 30 derniers jours.
private struct HealthMonitorGrid: View {
    let snapshot: CoachSnapshot

    var body: some View {
        let wellness = snapshot.wellness
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(.respiration, series: snapshot.respirationSeries,
                 note: snapshot.respiratory.map { String(format: "%+.1f resp/min vs ta normale", $0.delta) })
            tile(.restingHR, series: MetricKind.restingHR.series(from: wellness))
            tile(.hrv, series: snapshot.hrvSeries, note: snapshot.hrvSource)
            tile(.sleep, series: MetricKind.sleep.series(from: wellness), extra: sleepTiles)
            tile(.weight, series: MetricKind.weight.series(from: wellness))
            tile(.vo2max, series: MetricKind.vo2max.series(from: wellness))
        }
        .buttonStyle(.plain)
    }

    private var sleepTiles: [(title: String, value: String, caption: String)] {
        guard let regularity = snapshot.bedtimeRegularity else { return [] }
        return [(title: "Coucher moyen", value: regularity.average, caption: "14 dernières nuits"),
                (title: "Régularité", value: String(format: "±%.0f min", regularity.sd), caption: "repère : ±30 min")]
    }

    private func tile(_ kind: MetricKind, series: [DayValue], note: String? = nil,
                      extra: [(title: String, value: String, caption: String)] = []) -> some View {
        let reading = HealthReading.evaluate(series, higherIsBetter: kind.higherIsBetter)
        let unit = kind == .sleep ? "" : kind.unit
        return NavigationLink {
            MetricDetailView(kind: kind, series: series, sourceNote: note, extraTiles: extra, events: snapshot.chartEvents)
        } label: {
            HealthMonitorTile(title: kind.shortTitle, symbol: kind.symbol, value: reading.latest.map { kind.format($0) } ?? "–",
                              unit: unit, reading: reading, tint: kind.color,
                              trend: series.sorted { $0.date < $1.date }.suffix(14).map(\.value))
        }
    }
}

extension MetricKind {
    /// Titre court pour les tuiles du moniteur.
    var shortTitle: String {
        switch self {
        case .respiration: "Respiration"
        case .restingHR: "FC repos"
        default: title
        }
    }
}

/// Énergie disponible du jour (capacité estimée par le coach), en barre à dégradé.
private struct EnergyCard: View {
    let brief: DailyBrief

    var body: some View {
        let percent = Int((min(1.2, max(0, brief.capacity)) * 100).rounded())
        GlassCard(tint: Theme.recovery) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "bolt.fill").foregroundStyle(Theme.recovery)
                    Text("\(percent) %").font(.system(.title, design: .rounded).weight(.bold)).monospacedDigit()
                    Text("de ta capacité").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    DetailChevron()
                }
                GradientBar(fraction: min(1, brief.capacity), colors: [Theme.warning, Theme.nutrition, Theme.recovery], height: 12)
                if let first = brief.priorities.first {
                    Text(first).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }
    }
}

/// Aliments du jour façon Bevel : anneau des calories, grilles de points pour les macros, ajout en un tap.
struct TodayNutritionCard: View {
    let targets: MacroTargets
    let today: NutritionDay
    let onAdd: () -> Void

    var body: some View {
        GlassCard(tint: Theme.nutrition) {
            VStack(alignment: .leading, spacing: 14) {
                NavigationLink {
                    MacroTargetsDetailView(targets: targets, today: today)
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            GradientRing(fraction: today.kcal / max(targets.kcal, 1), colors: Theme.nutritionGradient, lineWidth: 10)
                            VStack(spacing: 0) {
                                Text(today.kcal.noDecimal).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                                Text("kcal").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 92, height: 92)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Calories").font(.headline)
                            Text("\(max(0, targets.kcal - today.kcal).noDecimal) kcal restantes").font(.subheadline).foregroundStyle(.secondary)
                            Text("objectif \(targets.kcal.noDecimal) kcal").font(.caption).foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 0)
                        DetailChevron()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)

                HStack(alignment: .top, spacing: 12) {
                    MacroDots(label: "Protéines", value: today.protein, target: targets.protein, color: Theme.recovery)
                    MacroDots(label: "Glucides", value: today.carbs, target: targets.carbs, color: Theme.sleep)
                    MacroDots(label: "Lipides", value: today.fat, target: targets.fat, color: Theme.strain)
                }

                Button(action: onAdd) {
                    Label("Ajouter un aliment", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.nutrition)
            }
        }
    }
}

private struct ReadinessCard: View {
    let readiness: ReadinessResult?
    let advice: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                if let readiness {
                    HStack(spacing: 20) {
                        ScoreRing(value: Double(readiness.score), color: Theme.color(for: readiness.level), label: "Récupération")
                            .frame(width: 130, height: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(readiness.level.label).font(.title3.weight(.semibold))
                            Text(advice).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        DetailChevron()
                    }
                } else {
                    HStack {
                        Label("Récupération", systemImage: "heart.text.square").font(.headline)
                        Spacer()
                        DetailChevron()
                    }
                    Text("Synchronise tes données (bouton en haut à droite). Le score apparaît dès 2 semaines de VFC ou avec ta nuit de sommeil.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct CoachCard: View {
    let insights: [Insight]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Analyse du coach", symbol: "brain.head.profile")
                    Spacer()
                    Text("\(insights.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    DetailChevron()
                }
                if insights.isEmpty {
                    Text("Pas assez de données pour une analyse. Synchronise et importe tes séances.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(insights.prefix(3)) { insight in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: insight.severity.symbol).foregroundStyle(InsightCard.color(insight.severity))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(insight.title).font(.subheadline.weight(.semibold))
                            if let first = insight.evidence.first {
                                Text(first).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct WellnessGrid: View {
    let snapshot: CoachSnapshot

    var body: some View {
        let wellness = snapshot.wellness
        let latest = snapshot.latestWellness
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            tile(.sleep, value: latest?.sleepHours?.hoursText ?? "–", unit: "", series: MetricKind.sleep.series(from: wellness),
                 extra: sleepTiles)
            tile(.hrv, value: snapshot.hrvSeries.last?.value.noDecimal ?? "–", unit: "ms", series: snapshot.hrvSeries, note: snapshot.hrvSource)
            tile(.restingHR, value: latest?.restingHeartRate?.noDecimal ?? "–", unit: "bpm", series: MetricKind.restingHR.series(from: wellness))
            tile(.steps, value: latest?.steps?.noDecimal ?? "–", unit: "", series: MetricKind.steps.series(from: wellness))
            let weights = MetricKind.weight.series(from: wellness)
            tile(.weight, value: weights.last?.value.oneDecimal ?? "–", unit: "kg", series: weights)
            let vo2 = MetricKind.vo2max.series(from: wellness)
            tile(.vo2max, value: vo2.last?.value.oneDecimal ?? "–", unit: "", series: vo2)
            tile(.respiration, value: snapshot.respirationSeries.last?.value.oneDecimal ?? "–", unit: "resp/min",
                 series: snapshot.respirationSeries,
                 note: snapshot.respiratory.map { String(format: "%+.1f resp/min vs ta normale", $0.delta) })
        }
    }

    private var sleepTiles: [(title: String, value: String, caption: String)] {
        guard let regularity = snapshot.bedtimeRegularity else { return [] }
        return [(title: "Coucher moyen", value: regularity.average, caption: "14 dernières nuits"),
                (title: "Régularité", value: String(format: "±%.0f min", regularity.sd), caption: "repère : ±30 min")]
    }

    private func tile(_ kind: MetricKind, value: String, unit: String, series: [DayValue], note: String? = nil,
                      extra: [(title: String, value: String, caption: String)] = []) -> some View {
        NavigationLink {
            MetricDetailView(kind: kind, series: series, sourceNote: note, extraTiles: extra)
        } label: {
            MetricTile(title: kind.title, value: value, unit: unit, symbol: kind.symbol, tint: kind.color)
                .overlay(alignment: .topTrailing) { DetailChevron().padding(12) }
        }
        .buttonStyle(.plain)
    }
}

private struct NutritionSummaryCard: View {
    let targets: MacroTargets
    let today: NutritionDay

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Nutrition du jour", symbol: "fork.knife")
                    Spacer()
                    DetailChevron()
                }
                MacroBar(label: "Calories", value: today.kcal, target: targets.kcal, unit: "kcal", color: Theme.nutrition)
                MacroBar(label: "Protéines", value: today.protein, target: targets.protein, unit: "g", color: Theme.recovery)
                MacroBar(label: "Glucides", value: today.carbs, target: targets.carbs, unit: "g", color: Theme.sleep)
                MacroBar(label: "Lipides", value: today.fat, target: targets.fat, unit: "g", color: Theme.strain)
            }
        }
    }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let target: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).font(.footnote.weight(.medium))
                Spacer()
                Text("\(value.noDecimal) / \(target.noDecimal) \(unit)").font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            AnimatedBar(fraction: target > 0 ? value / target : 0, color: color)
        }
    }
}

private struct LoadCard: View {
    let point: LoadPoint?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionTitle(title: "Charge d'entraînement", symbol: "chart.line.uptrend.xyaxis")
                    Spacer()
                    DetailChevron()
                }
                if let point {
                    HStack {
                        stat("Condition", point.ctl.noDecimal, Theme.recovery)
                        stat("Fatigue", point.atl.noDecimal, Theme.strain)
                        stat("Forme", point.form.noDecimal, formColor(point.form))
                    }
                    Text(formAdvice(point.form)).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Pas encore de séances importées.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formColor(_ form: Double) -> Color {
        form < -30 ? Theme.warning : (form < -10 ? Theme.nutrition : Theme.recovery)
    }

    private func formAdvice(_ form: Double) -> String {
        switch form {
        case ..<(-30): "Fatigue très élevée : risque de surmenage, lève le pied."
        case ..<(-10): "Zone de progression : tu charges, c'est normal d'être un peu fatigué."
        case ..<5: "Équilibre : charge et récupération sont alignées."
        default: "Frais : idéal pour une séance clé ou une course."
        }
    }
}

private struct ThisWeekCard: View {
    let week: PlannedWeek

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Cette semaine · \(week.phase.label) · \(week.kind.label)", symbol: "calendar")
                    Spacer()
                    DetailChevron()
                }
                HStack {
                    Label(week.targetHours.hoursText, systemImage: "clock")
                    Spacer()
                    Label("Longue : \(week.longRideHours.hoursText)", systemImage: "bicycle")
                    Spacer()
                    Label("\(week.strengthSessions)× muscu", systemImage: "dumbbell.fill")
                }
                .font(.subheadline)
                ForEach(week.notes.prefix(2), id: \.self) { note in
                    Text("• \(note)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct RaceCountdownCard: View {
    let name: String
    let date: Date

    var body: some View {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        GlassCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).font(.headline)
                    Text(date.formatted(date: .long, time: .omitted)).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("J-\(max(days, 0))").font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                    Text("\(max(days, 0) / 7) semaines").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Hydratation du jour, avec ajout en un geste.
struct HydrationCard: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    let target: Double
    let today: Double

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(title: "Hydratation", symbol: "drop.fill")
                    Spacer()
                    Text(String(format: "%.1f / %.1f L", today / 1000, target / 1000)).font(.subheadline.monospacedDigit())
                }
                AnimatedBar(fraction: target > 0 ? today / target : 0, color: Theme.sleep, height: 10)
                HStack {
                    ForEach([250.0, 500, 750], id: \.self) { ml in
                        Button("+\(Int(ml)) ml") {
                            QuickActions.addWater(ml, context: context)
                            app.dataVersion += 1
                        }
                        .buttonStyle(.glass)
                        .font(.caption)
                    }
                }
                Text("Objectif : 35 ml/kg + 600 ml par heure d'entraînement prévue.").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Indique si le verdict repose sur des données complètes ou partielles.
struct ConfidenceRow: View {
    let confidence: DataConfidence

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: confidence.ratio >= 0.8 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(confidence.label) · \(confidence.present.count)/\(confidence.present.count + confidence.missing.count) sources")
                    .font(.caption.weight(.semibold))
                if !confidence.missing.isEmpty {
                    Text("Manquant : " + confidence.missing.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .foregroundStyle(confidence.ratio >= 0.8 ? Theme.recovery : Theme.nutrition)
        .padding(.horizontal, 4)
    }
}
