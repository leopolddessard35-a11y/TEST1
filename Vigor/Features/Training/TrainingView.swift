import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct TrainingView: View {
    enum Segment: String, CaseIterable {
        case strength = "Muscu"
        case endurance = "Endurance"
    }

    @State private var segment: Segment = .strength

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("Type", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    switch segment {
                    case .strength: StrengthSection()
                    case .endurance: EnduranceSection()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(AppBackground())
            .navigationTitle("Entraînement")
        }
    }
}

// MARK: - Musculation

private struct StrengthSection: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    @State private var importing = false

    var body: some View {
        SnapshotReader { _, snapshot in
            let injured = snapshot.activeInjuries.reduce(into: Set<Muscle>()) { $0.formUnion($1.muscles) }
            VStack(spacing: 16) {
                Button {
                    importing = true
                } label: {
                    Label("Importer l'export Hevy (CSV)", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                if workouts.isEmpty {
                    EmptyStateCard(
                        title: "Aucune séance de muscu",
                        message: "Dans Hevy : Profil → Réglages → Exporter et importer → Exporter les séances. Enregistre le fichier dans Fichiers, puis importe-le ici. Tu peux réimporter l'export complet à chaque fois, sans doublon.",
                        symbol: "dumbbell")
                } else {
                    MuscleVolumeCard(workouts: workouts)
                    ProgressionCard(workouts: workouts, readiness: snapshot.readiness?.level, injured: injured)
                    TonnageCard(volumes: snapshot.weeklyVolumes)
                    ExerciseListCard(workouts: workouts)
                    WorkoutListCard(workouts: Array(workouts.prefix(15)))
                }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text]) { result in
            if case .success(let url) = result {
                app.importHevy(from: url, context: context)
            }
        }
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
                LoadChartCard(points: Array(snapshot.load.suffix(120)))
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
