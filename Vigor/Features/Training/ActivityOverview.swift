import SwiftUI
import SwiftData

/// Haut de l'onglet Charge, façon Bevel : la semaine en calendrier, l'effort du jour et la fraîcheur musculaire.
struct ActivityOverview: View {
    let snapshot: CoachSnapshot
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    @Query(sort: \CardioActivity.start, order: .reverse) private var activities: [CardioActivity]

    var body: some View {
        VStack(spacing: 12) {
            if !snapshot.weekStatus.isEmpty {
                if let week = snapshot.plan.currentWeek {
                    NavigationLink { WeekDetailView(week: week) } label: { weekCard }.buttonStyle(.plain)
                } else {
                    weekCard
                }
            }

            NavigationLink {
                EffortDetailView(today: snapshot.effortToday, target: snapshot.effortTarget, history: snapshot.effortHistory,
                                 verdict: snapshot.brief.verdict)
            } label: { effortCard }
            .buttonStyle(.plain)

            let entries = freshness
            NavigationLink {
                DetailPage(title: "Fraîcheur musculaire") { MuscleFreshnessList(entries: entries) }
            } label: {
                GlassCard(tint: Theme.recovery) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            IconBadge(symbol: "figure.strengthtraining.traditional", tint: Theme.recovery, size: 24)
                            Text("Fraîcheur musculaire").font(.headline)
                            Spacer()
                            DetailChevron()
                        }
                        let tired = entries.sorted { $0.percent < $1.percent }.prefix(4)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                            ForEach(Array(tired)) { entry in MuscleFreshnessCell(entry: entry) }
                        }
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var weekCard: some View {
        GlassCard(tint: Theme.sleep) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    IconBadge(symbol: "calendar", tint: Theme.sleep, size: 24)
                    Text("Cette semaine").font(.headline)
                    Spacer()
                    if let week = snapshot.plan.currentWeek {
                        Text("\(week.phase.label) · \(week.targetHours.hoursText)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    DetailChevron()
                }
                WeekStrip(days: snapshot.weekStatus)
            }
        }
    }

    private var effortCard: some View {
        let target = snapshot.effortTarget
        return GlassCard(tint: Theme.strain) {
            HStack(spacing: 16) {
                ZStack {
                    GradientRing(fraction: snapshot.effortToday / 21, colors: Theme.strainGradient, lineWidth: 10)
                    VStack(spacing: 0) {
                        Text(snapshot.effortToday.oneDecimal).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                        Text("/ 21").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Effort du jour").font(.headline)
                    Text(EffortScore.label(snapshot.effortToday)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.strain)
                    Text(String(format: "Cible : %.0f – %.0f", target.lowerBound, target.upperBound))
                        .font(.caption).foregroundStyle(.secondary)
                    GradientBar(fraction: min(1, snapshot.effortToday / max(target.upperBound, 1)), colors: Theme.strainGradient, height: 8)
                }
                DetailChevron()
            }
        }
    }

    private var freshness: [MuscleFreshness.Entry] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
        let sessions: [ExerciseSession] = workouts.filter { $0.start >= weekAgo }.flatMap(\.exerciseSessions)
        var cardio: [(date: Date, sport: Sport, tss: Double)] = []
        for activity in activities where activity.start >= weekAgo {
            let tss: Double = activity.providedTSS ?? activity.durationSeconds / 3600 * 50
            cardio.append((date: activity.start, sport: activity.sport, tss: tss))
        }
        return MuscleFreshness.compute(sessions: sessions, cardio: cardio)
    }
}

extension MuscleFreshness.Entry {
    var color: Color {
        percent >= 80 ? Theme.recovery : (percent >= 55 ? Theme.nutrition : Theme.strain)
    }
}

struct MuscleFreshnessCell: View {
    let entry: MuscleFreshness.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.muscle.label).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                Text("\(Int(entry.percent.rounded())) %").font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(entry.color)
            }
            DotGrid(fraction: entry.percent / 100, color: entry.color, rows: 1, columns: 10)
        }
    }
}

struct MuscleFreshnessList: View {
    let entries: [MuscleFreshness.Entry]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(entries.sorted { $0.percent < $1.percent }) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        MuscleFreshnessCell(entry: entry)
                        if let last = entry.lastWorked {
                            Text("Dernière sollicitation : \(last.formatted(.relative(presentation: .named)))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        ExplanationCard(title: "Comment c'est calculé", symbol: "function", text: """
        Chaque série effective (principale = 1, secondaire = ½) fatigue le muscle, puis cette fatigue s'efface avec le temps (constante de 36 h) : la force et la réparation musculaire reviennent à la normale en 48 à 72 h après une séance d'hypertrophie. Les sorties vélo et course comptent aussi pour les jambes (charge TSS ÷ 25).
        En dessous de 55 %, évite de recharger lourdement ce muscle aujourd'hui ; au-dessus de 80 %, il est prêt.
        """)
    }
}
