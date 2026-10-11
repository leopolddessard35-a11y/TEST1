import SwiftUI
import SwiftData

/// Fraîcheur des muscles les plus sollicités : ouvre la liste complète.
struct MuscleFreshnessCard: View {
    @Query(sort: \StrengthWorkout.start, order: .reverse) private var workouts: [StrengthWorkout]
    @Query(sort: \CardioActivity.start, order: .reverse) private var activities: [CardioActivity]

    var body: some View {
        let entries = freshness
        let tired = Array(entries.sorted { $0.percent < $1.percent }.prefix(4))
        NavigationLink {
            DetailPage(title: "Fraîcheur musculaire") { MuscleFreshnessList(entries: entries) }
        } label: {
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        IconBadge(symbol: "figure.strengthtraining.traditional", tint: Theme.accent, size: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Fraîcheur musculaire").font(.headline)
                            Text("Les 4 muscles les moins récupérés").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        DetailChevron()
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(tired) { entry in MuscleFreshnessCell(entry: entry) }
                    }
                }
            }
        }
        .buttonStyle(.pressable)
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
        percent >= 80 ? Theme.good : (percent >= 55 ? Theme.caution : Theme.alert)
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
