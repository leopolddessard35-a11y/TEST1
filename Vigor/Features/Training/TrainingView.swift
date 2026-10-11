import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

/// Entraînement : la semaine, la muscu, le vélo, la saison, puis la charge pour qui veut creuser.
/// Plus de segments : une seule page, dans l'ordre d'usage.
struct TrainingView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { profile, snapshot in
                    VStack(spacing: 12) {
                        WeekOverviewCard(snapshot: snapshot)

                        SectionHeader(title: "Musculation", symbol: "dumbbell.fill")
                        StrengthPlansSection()
                        MuscleFreshnessCard()
                        NavigationLink {
                            DetailPage(title: "Progression muscu") { StrengthProgressContent() }
                        } label: {
                            GlassCard {
                                LinkRow(symbol: "chart.bar.xaxis", title: "Progression",
                                        subtitle: "Prochaines charges, volume par muscle, tonnage, records")
                            }
                        }
                        .buttonStyle(.plain)

                        SectionHeader(title: "Vélo et endurance", symbol: "bicycle")
                        EnduranceSummaryCard(profile: profile)

                        SectionHeader(title: "Saison", symbol: "flag.checkered")
                        NavigationLink { SeasonPlanView() } label: {
                            SeasonCard(plan: snapshot.plan, raceName: profile.raceName, raceDate: profile.raceDate)
                        }
                        .buttonStyle(.plain)

                        SectionHeader(title: "Charge et fatigue", symbol: "gauge.with.needle")
                        GlassCard {
                            VStack(spacing: 0) {
                                NavigationLink {
                                    DetailPage(title: "Charge d'entraînement") { LoadSummarySection(snapshot: snapshot) }
                                } label: {
                                    LinkRow(symbol: "chart.line.uptrend.xyaxis", title: "Indicateurs de charge",
                                            subtitle: loadSummary(snapshot))
                                }
                                Divider().padding(.leading, 44)
                                NavigationLink {
                                    DetailPage(title: "Hors sport") { LifeSection(lifeLoad7: snapshot.lifeLoad7) }
                                } label: {
                                    LinkRow(symbol: "hammer", title: "Hors sport",
                                            subtitle: "Travaux, journées debout, pas : \(snapshot.lifeLoad7.noDecimal) pts sur 7 jours")
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
            .navigationTitle("Entraînement")
        }
    }

    /// Résumé en langage courant (le ratio technique reste dans le détail).
    private func loadSummary(_ snapshot: CoachSnapshot) -> String {
        let ratio = snapshot.disciplineLoads.first { $0.name == "Global" }?.ratio
        guard let ratio else { return "Charge, fraîcheur, régularité des séances" }
        switch ratio {
        case ..<0.8: return "Charge récente en baisse"
        case ..<1.3: return "Charge récente normale"
        case ..<1.5: return "Charge récente élevée : reste vigilant"
        default: return "Pic de charge : risque de blessure accru"
        }
    }
}

/// La dernière sortie + l'accès à toutes les sorties.
private struct EnduranceSummaryCard: View {
    let profile: AthleteProfile
    @Query(sort: \CardioActivity.start, order: .reverse) private var activities: [CardioActivity]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                if let last = activities.first {
                    CapsLabel("Dernière sortie")
                    NavigationLink {
                        ActivityDetailView(activity: last, thresholds: profile.thresholds)
                    } label: {
                        ActivityRow(activity: last, thresholds: profile.thresholds)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Aucune sortie pour l'instant : relie Garmin (Réglages → Intervals.icu) ou Apple Santé.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Divider()
                NavigationLink {
                    DetailPage(title: "Sorties") { EnduranceSection() }
                } label: {
                    LinkRow(symbol: "list.bullet", title: "Toutes les sorties",
                            subtitle: "FTP \(profile.ftp.noDecimal) W · \(activities.count) séances enregistrées")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Compte à rebours et phase de la saison.
private struct SeasonCard: View {
    let plan: SeasonPlan
    let raceName: String
    let raceDate: Date

    var body: some View {
        let days = max(0, Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                          to: Calendar.current.startOfDay(for: raceDate)).day ?? 0)
        let progress = plan.targetCTL > 0 ? min(1, plan.startCTL / plan.targetCTL) : 0
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(raceName).font(.headline)
                        Text(raceDate.formatted(date: .long, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("J-\(days)").font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit()
                    DetailChevron()
                }
                if let week = plan.currentWeek {
                    Text("Phase \(week.phase.label.lowercased()) · \(week.kind.label.lowercased())")
                        .font(.subheadline.weight(.semibold))
                }
                GradientBar(fraction: progress, colors: Theme.recoveryGradient, height: 8)
                Text("Condition \(plan.startCTL.noDecimal) sur \(plan.targetCTL.noDecimal) visés le jour J")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Musculation

/// Suivi détaillé de la muscu (2e niveau) : charges conseillées, volume, tonnage, records, dernières séances.
struct StrengthProgressContent: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    @State private var importing = false

    var body: some View {
        SnapshotReader { _, snapshot in
            let injured = snapshot.activeInjuries.reduce(into: Set<Muscle>()) { $0.formUnion($1.muscles) }
            VStack(spacing: 16) {
                if workouts.isEmpty {
                    EmptyStateCard(
                        title: "Aucune séance pour l'instant",
                        message: "Lance une séance type ou une séance libre ci-dessus : séries, charges et repos se notent en direct, et le coach propose les charges suivantes.",
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
                Button { importing = true } label: {
                    Label("Récupérer mon historique Hevy (CSV)", systemImage: "square.and.arrow.down")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
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
                SimpleTile(title: "Charge récente", value: ratioWord(global?.ratio),
                           caption: global?.ratio.map { String(format: "ratio 7 j / 28 j : %.2f", $0) } ?? "moyennes exponentielles",
                           symbol: "gauge.with.needle", tint: ratioColor(global?.ratio))
            }
            NavigationLink { detail } label: {
                SimpleTile(title: "Fraîcheur", value: snapshot.today?.form.noDecimal ?? "–",
                           caption: "condition de fond \(snapshot.today?.ctl.noDecimal ?? "–")", symbol: "chart.line.uptrend.xyaxis", tint: Theme.good)
            }
            NavigationLink { detail } label: {
                SimpleTile(title: "Volume semaine", value: lastWeek.map { $0.sportHours.hoursText } ?? "–",
                           caption: snapshot.volumeAlerts.isEmpty ? "progression OK" : "⚠︎ +10 % dépassé", symbol: "calendar", tint: Theme.sleep)
            }
            NavigationLink { detail } label: {
                SimpleTile(title: "Variété des séances", value: (snapshot.monotony ?? 0) > 2 ? "Trop uniforme" : "OK",
                           caption: snapshot.monotony.map { String(format: "monotonie %.1f (repère < 2)", $0) } ?? "repère < 2",
                           symbol: "waveform", tint: (snapshot.monotony ?? 0) > 2 ? Theme.caution : Theme.good)
            }
            NavigationLink {
                DetailPage(title: "Efficiency Factor") {
                    TrendChart(title: "Efficiency Factor vélo (NP / FC)", color: Theme.recovery, points: snapshot.efSeries, days: 120)
                    ExplanationCard(title: "Ce que ça mesure", symbol: "lightbulb", text: "Puissance produite par battement cardiaque, sur des sorties d'endurance comparables (≥ 45 min, peu de dénivelé). Il monte quand ta base aérobie progresse : c'est l'indicateur de progrès sans chrono.")
                }
            } label: {
                SimpleTile(title: "Endurance aérobie", value: snapshot.efSeries.last.map { String(format: "%.2f", $0.value) } ?? "–",
                           caption: "puissance / FC", symbol: "bolt.heart.fill", tint: Theme.recovery)
            }
            NavigationLink { detail } label: {
                SimpleTile(title: "Hors sport 7 j", value: "\(snapshot.lifeLoad7.noDecimal) pts",
                           caption: "travaux, debout, pas", symbol: "hammer.fill", tint: Theme.strain)
            }
        }
        .buttonStyle(.plain)
    }

    private func ratioWord(_ ratio: Double?) -> String {
        guard let ratio else { return "–" }
        if ratio > 1.5 { return "Pic" }
        if ratio > 1.3 { return "Élevée" }
        if ratio < 0.8 { return "Basse" }
        return "Normale"
    }

    private func ratioColor(_ ratio: Double?) -> Color {
        guard let ratio else { return Theme.accent }
        if ratio > 1.5 { return Theme.alert }
        if ratio > 1.3 || ratio < 0.8 { return Theme.caution }
        return Theme.good
    }

    private func ratioCaption(_ ratio: Double?) -> String {
        guard let ratio else { return "moyennes exponentielles" }
        if ratio > 1.5 { return "⚠︎ pic (> 1,5)" }
        if ratio > 1.3 { return "↗ haut (1,3–1,5)" }
        if ratio < 0.8 { return "↘ bas (< 0,8)" }
        return "✓ zone sûre"
    }
}
