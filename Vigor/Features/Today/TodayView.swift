import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query private var profiles: [AthleteProfile]

    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { profile, snapshot in
                    VStack(spacing: 16) {
                        NavigationLink {
                            ReadinessDetailView(readiness: snapshot.readiness, history: snapshot.readinessHistory, hrvSource: snapshot.hrvSource)
                        } label: {
                            ReadinessCard(readiness: snapshot.readiness, advice: snapshot.todayAdvice)
                        }
                        .buttonStyle(.plain)

                        if !snapshot.plannedToday.isEmpty {
                            PlannedTodayCard(workouts: snapshot.plannedToday)
                        }

                        NavigationLink {
                            InsightsView(insights: snapshot.insights)
                        } label: {
                            CoachCard(insights: snapshot.insights)
                        }
                        .buttonStyle(.plain)

                        WellnessGrid(snapshot: snapshot)

                        if let targets = snapshot.macroTargets {
                            NavigationLink {
                                MacroTargetsDetailView(targets: targets, today: snapshot.todayNutrition)
                            } label: {
                                NutritionSummaryCard(targets: targets, today: snapshot.todayNutrition)
                            }
                            .buttonStyle(.plain)
                        }

                        NavigationLink {
                            LoadDetailView(load: snapshot.load)
                        } label: {
                            LoadCard(point: snapshot.today)
                        }
                        .buttonStyle(.plain)

                        if let week = snapshot.plan.currentWeek {
                            NavigationLink {
                                WeekDetailView(week: week)
                            } label: {
                                ThisWeekCard(week: week)
                            }
                            .buttonStyle(.plain)
                        }
                        RaceCountdownCard(name: profile.raceName, date: profile.raceDate)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .background(AppBackground())
            .navigationTitle("Aujourd'hui")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await app.syncAll(context: context, profile: profiles.first) }
                    } label: {
                        if app.isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                }
            }
            .refreshable { await app.syncAll(context: context, profile: profiles.first) }
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

private struct PlannedTodayCard: View {
    let workouts: [PlannedWorkout]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Prévu aujourd'hui (Intervals.icu)", symbol: "calendar.badge.clock")
                ForEach(workouts) { workout in
                    HStack {
                        Image(systemName: workout.sport.symbol)
                        VStack(alignment: .leading) {
                            Text(workout.name).font(.subheadline.weight(.semibold))
                            HStack(spacing: 8) {
                                if let seconds = workout.plannedSeconds { Text((seconds / 3600).hoursText) }
                                if let tss = workout.plannedTSS { Text("TSS \(tss.noDecimal)") }
                            }
                            .font(.caption).foregroundStyle(.secondary)
                        }
                    }
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
            tile(.sleep, value: latest?.sleepHours?.hoursText ?? "–", unit: "", series: MetricKind.sleep.series(from: wellness))
            tile(.hrv, value: snapshot.hrvSeries.last?.value.noDecimal ?? "–", unit: "ms", series: snapshot.hrvSeries, note: snapshot.hrvSource)
            tile(.restingHR, value: latest?.restingHeartRate?.noDecimal ?? "–", unit: "bpm", series: MetricKind.restingHR.series(from: wellness))
            tile(.steps, value: latest?.steps?.noDecimal ?? "–", unit: "", series: MetricKind.steps.series(from: wellness))
            let weights = MetricKind.weight.series(from: wellness)
            tile(.weight, value: weights.last?.value.oneDecimal ?? "–", unit: "kg", series: weights)
            let vo2 = MetricKind.vo2max.series(from: wellness)
            tile(.vo2max, value: vo2.last?.value.oneDecimal ?? "–", unit: "", series: vo2)
        }
    }

    private func tile(_ kind: MetricKind, value: String, unit: String, series: [DayValue], note: String? = nil) -> some View {
        NavigationLink {
            MetricDetailView(kind: kind, series: series, sourceNote: note)
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
            ProgressView(value: min(value, target), total: max(target, 1)).tint(color)
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
                    Text("J-\(max(days, 0))").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("\(max(days, 0) / 7) semaines").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
