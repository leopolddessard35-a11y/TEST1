import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                SnapshotReader { profile, snapshot in
                    VStack(spacing: 16) {
                        ReadinessCard(readiness: snapshot.readiness)
                        WellnessGrid(wellness: snapshot.latestWellness)
                        LoadCard(point: snapshot.today)
                        if let week = snapshot.plan.currentWeek {
                            ThisWeekCard(week: week)
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
                        Task { await app.syncHealth(context: context) }
                    } label: {
                        if app.isSyncing { ProgressView() } else { Image(systemName: "arrow.triangle.2.circlepath") }
                    }
                }
            }
            .refreshable { await app.syncHealth(context: context) }
        }
    }
}

private struct ReadinessCard: View {
    let readiness: ReadinessResult?

    var body: some View {
        GlassCard {
            if let readiness {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 20) {
                        ScoreRing(value: Double(readiness.score), color: Theme.color(for: readiness.level), label: "Récupération")
                            .frame(width: 130, height: 130)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(readiness.level.label).font(.title3.weight(.semibold))
                            Text(readiness.level.advice).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    ForEach(readiness.components) { component in
                        HStack {
                            Text(component.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text(component.detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Récupération", systemImage: "heart.text.square").font(.headline)
                    Text("Synchronise Apple Santé (bouton en haut à droite). Le score apparaît dès que l'app a au moins 2 semaines de VFC ou ta nuit de sommeil.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct WellnessGrid: View {
    let wellness: DailyWellness?

    var body: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(title: "Sommeil", value: wellness?.sleepHours?.hoursText ?? "–", symbol: "bed.double.fill", tint: Theme.sleep)
            MetricTile(title: "VFC", value: wellness?.hrvMs?.noDecimal ?? "–", unit: "ms", symbol: "waveform.path.ecg", tint: Theme.recovery)
            MetricTile(title: "FC repos", value: wellness?.restingHeartRate?.noDecimal ?? "–", unit: "bpm", symbol: "heart.fill", tint: Theme.warning)
            MetricTile(title: "Pas", value: wellness?.steps?.noDecimal ?? "–", symbol: "figure.walk", tint: Theme.nutrition)
        }
    }
}

private struct LoadCard: View {
    let point: LoadPoint?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Charge d'entraînement", symbol: "chart.line.uptrend.xyaxis")
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
                SectionTitle(title: "Cette semaine · \(week.phase.label) · \(week.kind.label)", symbol: "calendar")
                HStack {
                    Label(week.targetHours.hoursText, systemImage: "clock")
                    Spacer()
                    Label("Longue : \(week.longRideHours.hoursText)", systemImage: "bicycle")
                    Spacer()
                    Label("\(week.strengthSessions)× muscu", systemImage: "dumbbell.fill")
                }
                .font(.subheadline)
                ForEach(week.notes, id: \.self) { note in
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
