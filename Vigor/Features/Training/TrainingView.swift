import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct TrainingView: View {
    enum Segment: String, CaseIterable {
        case summary = "Vue"
        case endurance = "Endurance"
        case strength = "Muscu"
        case life = "Hors sport"
    }

    @State private var segment: Segment = .summary
    @State private var showPlan = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Type", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch segment {
                    case .summary:
                        SnapshotReader { _, snapshot in
                            VStack(spacing: 12) {
                                ActivityOverview(snapshot: snapshot)
                                SectionHeader(title: "Charge d'entraînement", symbol: "chart.line.uptrend.xyaxis", tint: Theme.strain)
                                LoadSummarySection(snapshot: snapshot)
                            }
                        }
                    case .strength: StrengthSection()
                    case .life: SnapshotReader { _, snapshot in LifeSection(lifeLoad7: snapshot.lifeLoad7) }
                    case .endurance: EnduranceSection()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Activité")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showPlan = true } label: { Label("Plan", systemImage: "calendar") }
                }
            }
            .sheet(isPresented: $showPlan) { PlanView(presentedAsSheet: true) }
        }
    }
}

// MARK: - Musculation

private struct StrengthSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    @State private var importing = false
    @State private var logging = false

    var body: some View {
        SnapshotReader { _, snapshot in
            let injured = snapshot.activeInjuries.reduce(into: Set<Muscle>()) { $0.formUnion($1.muscles) }
            VStack(spacing: 16) {
                HStack(spacing: 10) {
                    Button { logging = true } label: {
                        Label("Démarrer une séance", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.strain)
                    Button { importing = true } label: {
                        Label("Import Hevy", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
                .controlSize(.large)

                if workouts.isEmpty {
                    EmptyStateCard(
                        title: "Aucune séance de muscu",
                        message: "Dans Hevy : Profil → Réglages → Exporter et importer → Exporter les séances. Enregistre le fichier dans Fichiers, puis importe-le ici. Tu peux réimporter l'export complet à chaque fois, sans doublon.",
                        symbol: "dumbbell")
                } else {
                    let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
                    let weekSets = MuscleMap.weeklySets(workouts.filter { $0.start >= weekAgo }.flatMap(\.exerciseSessions))
                    let lowMuscles = [Muscle.chest, .lats, .upperBack, .sideDelts, .quads, .glutes, .biceps, .triceps]
                        .filter { (weekSets[$0] ?? 0) < MuscleMap.hypertrophyRange.lowerBound }.count
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        NavigationLink {
                            DetailPage(title: "Prochaines charges") {
                                ProgressionCard(workouts: workouts, readiness: snapshot.readiness?.level, injured: injured)
                            }
                        } label: {
                            SimpleTile(title: "Prochaines charges", value: "\(Set(workouts.prefix(6).flatMap { $0.sets.map(\.exercise) }).count) exos",
                                       caption: "charge conseillée", symbol: "scalemass.fill", tint: Theme.strain)
                        }
                        NavigationLink {
                            DetailPage(title: "Volume par muscle") { MuscleVolumeCard(workouts: workouts) }
                        } label: {
                            SimpleTile(title: "Volume 7 j", value: lowMuscles == 0 ? "OK" : "\(lowMuscles) en retard",
                                       caption: "objectif 10–20 séries", symbol: "figure.arms.open", tint: Theme.recovery)
                        }
                        NavigationLink {
                            DetailPage(title: "Tonnage") { TonnageCard(volumes: snapshot.weeklyVolumes) }
                        } label: {
                            SimpleTile(title: "Tonnage", value: snapshot.weeklyVolumes.dropLast().last.map { String(format: "%.1f t", $0.tonnage / 1000) } ?? "–",
                                       caption: "semaine dernière", symbol: "chart.bar.fill", tint: Theme.nutrition)
                        }
                        NavigationLink {
                            DetailPage(title: "Exercices") { ExerciseListCard(workouts: workouts) }
                        } label: {
                            SimpleTile(title: "Records", value: "1RM", caption: "par exercice", symbol: "trophy.fill", tint: Theme.sleep)
                        }
                    }
                    .buttonStyle(.plain)
                    WorkoutListCard(workouts: Array(workouts.prefix(5)))
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            if case .success(let url) = result {
                app.importHevy(from: url, context: context)
            }
        }
        .sheet(isPresented: $logging) { WorkoutLoggerView() }
    }
}

private struct MuscleVolumeCard: View {
    let workouts: [StrengthWorkout]

    var body: some View {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let sessions = workouts.filter { $0.start >= weekAgo }.flatMap(\.exerciseSessions)
        let volume = MuscleMap.weeklySets(sessions)
        let range = MuscleMap.hypertrophyRange

        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Volume par muscle · 7 derniers jours", symbol: "figure.arms.open")
                Text("Objectif prise de masse : \(Int(range.lowerBound))–\(Int(range.upperBound)) séries par muscle et par semaine.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(BodyRegion.allCases, id: \.self) { region in
                    Text(region.label).font(.caption.weight(.semibold)).padding(.top, 4)
                    ForEach(Muscle.allCases.filter { $0.region == region }) { muscle in
                        let sets = volume[muscle] ?? 0
                        HStack {
                            Text(muscle.label).font(.footnote).frame(width: 150, alignment: .leading)
                            AnimatedBar(fraction: min(sets, range.upperBound) / range.upperBound,
                                        color: sets < range.lowerBound ? Theme.nutrition : (sets > range.upperBound ? Theme.warning : Theme.recovery))
                            Text(sets.oneDecimal).font(.footnote.monospacedDigit()).frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

private struct ProgressionCard: View {
    let workouts: [StrengthWorkout]
    let readiness: ReadinessLevel?
    let injured: Set<Muscle>

    var body: some View {
        let cutoff = Calendar.current.date(byAdding: .day, value: -45, to: .now) ?? .now
        let recent = workouts.filter { $0.start >= cutoff }
        let byExercise = Dictionary(grouping: recent.flatMap(\.exerciseSessions), by: \.exercise)
        let advice = byExercise.keys.sorted().compactMap { exercise in
            StrengthProgression.advise(exercise: exercise, sessions: byExercise[exercise] ?? [],
                                       readiness: readiness, injuredMuscles: injured)
        }

        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Prochaines charges", symbol: "scalemass.fill")
                if advice.isEmpty {
                    Text("Aucun exercice sur les 45 derniers jours.").font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(advice) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.action.symbol)
                            .foregroundStyle(color(item.action))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.exercise).font(.subheadline.weight(.semibold))
                                Spacer()
                                if let weight = item.suggestedWeightKg {
                                    Text("\(weight.oneDecimal) kg · \(item.targetReps.lowerBound)–\(item.targetReps.upperBound)")
                                        .font(.subheadline.monospacedDigit())
                                }
                            }
                            Text(item.reason).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func color(_ action: ProgressionAdvice.Action) -> Color {
        switch action {
        case .increase: Theme.recovery
        case .keep: .secondary
        case .decrease, .deload: Theme.nutrition
        case .avoid: Theme.warning
        }
    }
}

private struct WorkoutListCard: View {
    let workouts: [StrengthWorkout]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Dernières séances", symbol: "list.bullet")
                ForEach(workouts) { workout in
                    NavigationLink {
                        StrengthWorkoutDetailView(workout: workout)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(workout.title).font(.subheadline.weight(.semibold))
                                Text(workout.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(workout.sets.filter { !$0.isWarmup }.count) séries").font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct StrengthWorkoutDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Bindable var workout: StrengthWorkout

    var body: some View {
        List {
            Section("Effort ressenti de la séance (RPE)") {
                RPEPicker(value: workout.rpe) { value in
                    workout.rpe = value
                    try? context.save()
                    app.dataVersion += 1
                }
            }
            if !workout.notes.isEmpty {
                Section("Notes") { Text(workout.notes) }
            }
            ForEach(workout.exerciseSessions, id: \.exercise) { session in
                Section(session.exercise) {
                    let targets = MuscleMap.targets(for: session.exercise)
                    if !targets.primary.isEmpty {
                        Text(targets.primary.map(\.label).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(session.sets.enumerated()), id: \.offset) { index, set in
                        HStack {
                            Text(set.isWarmup ? "Échauffement" : "Série \(index + 1)")
                            Spacer()
                            Text("\(set.weightKg?.oneDecimal ?? "–") kg × \(set.reps.map(String.init) ?? "–")")
                                .monospacedDigit()
                            if let rpe = set.rpe { Text("RPE \(rpe.oneDecimal)").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
        }
        .navigationTitle(workout.title)
    }
}

// MARK: - Endurance

private struct EnduranceSection: View {
    @Query(sort: \CardioActivity.start, order: .reverse) private var activities: [CardioActivity]

    var body: some View {
        SnapshotReader { profile, snapshot in
            VStack(spacing: 16) {
                if activities.isEmpty {
                    EmptyStateCard(title: "Aucune séance d'endurance",
                                   message: "Synchronise Apple Santé depuis l'onglet Aujourd'hui. Garmin, Zwift et MyWhoosh (via Garmin) y écrivent tes sorties.",
                                   symbol: "bicycle")
                } else {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(title: "Dernières sorties", symbol: "list.bullet")
                            ForEach(activities.prefix(20)) { activity in
                                NavigationLink {
                                    ActivityDetailView(activity: activity, thresholds: profile.thresholds)
                                } label: {
                                    ActivityRow(activity: activity, thresholds: profile.thresholds)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct LoadChartCard: View {
    let points: [LoadPoint]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Condition, fatigue et forme · 4 mois", symbol: "chart.xyaxis.line")
                Chart {
                    ForEach(points) { point in
                        LineMark(x: .value("Jour", point.date), y: .value("Valeur", point.ctl))
                            .foregroundStyle(by: .value("Courbe", "Condition"))
                        LineMark(x: .value("Jour", point.date), y: .value("Valeur", point.atl))
                            .foregroundStyle(by: .value("Courbe", "Fatigue"))
                        LineMark(x: .value("Jour", point.date), y: .value("Valeur", point.form))
                            .foregroundStyle(by: .value("Courbe", "Forme"))
                    }
                }
                .chartForegroundStyleScale(["Condition": Theme.recovery, "Fatigue": Theme.strain, "Forme": Theme.sleep])
                .frame(height: 200)
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: CardioActivity
    let thresholds: Thresholds

    var body: some View {
        let tss = activity.providedTSS ?? TrainingLoad.estimateTSS(
            sport: activity.sport, durationSeconds: activity.durationSeconds,
            normalizedPower: activity.normalizedPower, averagePower: activity.averagePower,
            averageHeartRate: activity.averageHeartRate, thresholds: thresholds)
        HStack(spacing: 12) {
            Image(systemName: activity.sport.symbol).font(.title3).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(activity.start.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text((activity.durationSeconds / 3600).hoursText).font(.subheadline.monospacedDigit())
                HStack(spacing: 6) {
                    if let power = activity.averagePower { Text("\(power.noDecimal) W") }
                    if let hr = activity.averageHeartRate { Text("\(hr.noDecimal) bpm") }
                    Text("TSS \(tss.noDecimal)")
                }
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Tonnage et exercices

private struct TonnageCard: View {
    let volumes: [WeeklyVolume]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Tonnage hebdomadaire", symbol: "scalemass.fill")
                Chart(volumes) { week in
                    BarMark(x: .value("Semaine", week.weekStart, unit: .weekOfYear), y: .value("Tonnes", week.tonnage / 1000))
                        .foregroundStyle(Theme.strain.gradient)
                        .cornerRadius(4)
                }
                .frame(height: 140)
                if let last = volumes.dropLast().last {
                    Text(String(format: "Semaine dernière : %.1f t soulevées (séries de travail).", last.tonnage / 1000))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ExerciseListCard: View {
    let workouts: [StrengthWorkout]

    var body: some View {
        let sessions = workouts.flatMap(\.exerciseSessions)
        let grouped = Dictionary(grouping: sessions, by: \.exercise)
        let names = grouped.keys.sorted { (grouped[$0]?.count ?? 0) > (grouped[$1]?.count ?? 0) }
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Exercices · records et 1RM", symbol: "trophy.fill")
                ForEach(names.prefix(20), id: \.self) { name in
                    let items = grouped[name] ?? []
                    let best = items.map(\.bestEstimated1RM).max() ?? 0
                    NavigationLink {
                        ExerciseDetailView(exercise: name, sessions: items)
                    } label: {
                        HStack {
                            Text(name).font(.subheadline).lineLimit(1)
                            Spacer()
                            Text("1RM \(best.oneDecimal) kg").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            DetailChevron()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Synthèse de charge

/// Monnaie commune (TSS / sRPE), ratio 7 j / 28 j exponentiel par discipline, monotonie, strain, volume.
private struct LoadSummarySection: View {
    let snapshot: CoachSnapshot

    var body: some View {
        let global = snapshot.disciplineLoads.first { $0.name == "Global" }
        let detail = LoadDetailView(load: snapshot.load, disciplines: snapshot.disciplineLoads, volumes: snapshot.weeklyVolumes,
                                    alerts: snapshot.volumeAlerts, lifeLoad7: snapshot.lifeLoad7)
        let lastWeek = snapshot.weeklyVolumes.dropLast().last
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            NavigationLink { detail } label: {
                SimpleTile(title: "Ratio 7 j / 28 j", value: global?.ratio.map { String(format: "%.2f", $0) } ?? "–",
                           caption: ratioCaption(global?.ratio), symbol: "gauge.with.needle", tint: Theme.strain)
            }
            NavigationLink { detail } label: {
                SimpleTile(title: "Forme", value: snapshot.today?.form.noDecimal ?? "–",
                           caption: "condition \(snapshot.today?.ctl.noDecimal ?? "–")", symbol: "chart.line.uptrend.xyaxis", tint: Theme.recovery)
            }
            NavigationLink { detail } label: {
                SimpleTile(title: "Volume semaine", value: lastWeek.map { $0.sportHours.hoursText } ?? "–",
                           caption: snapshot.volumeAlerts.isEmpty ? "progression OK" : "⚠︎ +10 % dépassé", symbol: "calendar", tint: Theme.sleep)
            }
            NavigationLink { detail } label: {
                SimpleTile(title: "Monotonie", value: snapshot.monotony.map { String(format: "%.1f", $0) } ?? "–",
                           caption: (snapshot.monotony ?? 0) > 2 ? "⚠︎ trop uniforme" : "repère < 2", symbol: "waveform", tint: Theme.nutrition)
            }
            NavigationLink {
                DetailPage(title: "Efficiency Factor") {
                    TrendChart(title: "Efficiency Factor vélo (NP / FC)", color: Theme.recovery, points: snapshot.efSeries, days: 120)
                    ExplanationCard(title: "Ce que ça mesure", symbol: "lightbulb", text: "Puissance produite par battement cardiaque, sur des sorties d'endurance comparables (≥ 45 min, peu de dénivelé). Il monte quand ta base aérobie progresse : c'est l'indicateur de progrès sans chrono.")
                }
            } label: {
                SimpleTile(title: "Efficacité aérobie", value: snapshot.efSeries.last.map { String(format: "%.2f", $0.value) } ?? "–",
                           caption: "puissance / FC", symbol: "bolt.heart.fill", tint: Theme.recovery)
            }
            NavigationLink { detail } label: {
                SimpleTile(title: "Hors sport 7 j", value: "\(snapshot.lifeLoad7.noDecimal) pts",
                           caption: "travaux, debout, pas", symbol: "hammer.fill", tint: Theme.strain)
            }
        }
        .buttonStyle(.plain)
    }

    private func ratioCaption(_ ratio: Double?) -> String {
        guard let ratio else { return "moyennes exponentielles" }
        if ratio > 1.5 { return "⚠︎ pic (> 1,5)" }
        if ratio > 1.3 { return "↗ haut (1,3–1,5)" }
        if ratio < 0.8 { return "↘ bas (< 0,8)" }
        return "✓ zone sûre"
    }
}
