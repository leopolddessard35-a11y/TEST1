import SwiftUI
import Charts

/// Le détail de la nuit dernière (façon Bevel) : score et ses composantes, hypnogramme, stades,
/// dette de sommeil, physiologie nocturne, puis la nuit à venir. Visible seulement quand on le demande.
struct SleepDetailView: View {
    let snapshot: CoachSnapshot
    @State private var segments: [SleepSegment] = []
    @State private var loaded = false

    private var night: DailyWellness? { snapshot.wellness.last { $0.sleepHours != nil } }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                if let score = snapshot.lastSleepScore { componentsCard(score) }
                if !segments.isEmpty { hypnogramCard }
                stagesCard
                debtCard
                physiologyGrid
                NavigationLink {
                    SleepNeedDetailView(need: snapshot.sleepNeed, performance: snapshot.lastSleepPerformance,
                                        lastNight: night.flatMap { Calendar.current.isDateInToday($0.day) ? $0.sleepHours : nil },
                                        regularity: snapshot.bedtimeRegularity)
                } label: {
                    GlassCard {
                        LinkRow(symbol: "moon.zzz.fill", title: "Ce soir : coucher vers \(snapshot.sleepNeed.bedtimeText)",
                                subtitle: "Besoin de \(snapshot.sleepNeed.total.hoursText), d'où il vient")
                    }
                }
                .buttonStyle(.plain)
                ExplanationCard(title: "Comment le score est calculé", symbol: "function", text: """
                Durée vs ton besoin (50 %), efficacité : temps endormi sur le temps au lit (15 %), stades : profond ≥ 15 % et paradoxal ≥ 20 % de la nuit (20 %), régularité : heure de coucher proche de ta médiane des 14 dernières nuits (15 %).
                Le sommeil profond sert surtout à la récupération physique (hormone de croissance), le paradoxal à la mémoire et à l'équilibre émotionnel. Les stades mesurés par une montre sont des estimations : regarde la tendance plutôt qu'une nuit isolée.
                """)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Sommeil")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded, let night, let bed = night.bedtime, let wake = night.wakeTime else { return }
            loaded = true
            segments = (try? await HealthKitService().sleepSegments(from: bed.addingTimeInterval(-3600),
                                                                   to: wake.addingTimeInterval(1800))) ?? []
        }
    }

    // MARK: Score

    private var header: some View {
        GlassCard {
            HStack(spacing: 18) {
                ZStack {
                    GradientRing(fraction: Double(snapshot.lastSleepScore?.score ?? 0) / 100, colors: Theme.sleepGradient, lineWidth: 11)
                    VStack(spacing: 0) {
                        Text(snapshot.lastSleepScore.map { "\($0.score)" } ?? "–")
                            .font(.system(.title, design: .rounded).weight(.heavy)).monospacedDigit()
                        Text("score").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 104, height: 104)
                VStack(alignment: .leading, spacing: 6) {
                    CapsLabel(night.map { Calendar.current.isDateInToday($0.day) ? "Cette nuit" : $0.day.formatted(.dateTime.weekday(.wide).day()) } ?? "Dernière nuit")
                    Text(night?.sleepHours?.hoursText ?? "Pas encore de nuit")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                    if let bed = night?.bedtime, let wake = night?.wakeTime {
                        Label("\(bed.formatted(date: .omitted, time: .shortened)) → \(wake.formatted(date: .omitted, time: .shortened))",
                              systemImage: "clock")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let score = snapshot.lastSleepScore {
                        StatusPill(text: score.label, symbol: score.score >= 70 ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                                   color: score.score >= 70 ? Theme.good : (score.score >= 50 ? Theme.caution : Theme.alert))
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func componentsCard(_ score: SleepScoreResult) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CapsLabel("Ce qui compose le score")
                ForEach(score.components) { component in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(component.name).font(.subheadline.weight(.semibold))
                            Text("· \(Int((component.weight * 100).rounded())) %").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int(component.score.rounded()))").font(.subheadline.weight(.bold).monospacedDigit())
                        }
                        GradientBar(fraction: component.score / 100, colors: Theme.sleepGradient, height: 6)
                        Text(component.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Hypnogramme et stades

    private var hypnogramCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel("Déroulé de la nuit")
                Chart(segments) { segment in
                    RectangleMark(xStart: .value("Début", segment.start), xEnd: .value("Fin", segment.end),
                                  y: .value("Stade", segment.stage.label), height: .ratio(0.8))
                        .foregroundStyle(Self.color(segment.stage))
                        .cornerRadius(2)
                }
                .chartYScale(domain: [SleepSegment.Stage.awake, .rem, .core, .deep].map(\.label))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                    }
                }
                .frame(height: 170)
            }
        }
    }

    private var stagesCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                CapsLabel("Stades de sommeil")
                if let night, let total = night.sleepHours, let deep = night.sleepDeepHours,
                   let rem = night.sleepREMHours, let core = night.sleepCoreHours {
                    stageRow(.deep, hours: deep, total: total, reference: "repère 13–23 %")
                    stageRow(.rem, hours: rem, total: total, reference: "repère 20–25 %")
                    stageRow(.core, hours: core, total: total, reference: "repère ≈ 50 %")
                    if let awake = night.sleepAwakeHours {
                        stageRow(.awake, hours: awake, total: total + awake, reference: "moins de 10 % idéalement")
                    }
                } else {
                    Text("Ta montre n'a pas transmis les stades pour cette nuit. Dans Garmin Connect → Applications connectées → Santé, vérifie que « Sommeil » est activé, puis synchronise.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stageRow(_ stage: SleepSegment.Stage, hours: Double, total: Double, reference: String) -> some View {
        let share = total > 0 ? hours / total : 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(Self.color(stage)).frame(width: 10, height: 10)
                Text(stage.label).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(hours.hoursText) · \(Int((share * 100).rounded())) %").font(.subheadline.monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.well)
                    Capsule().fill(Self.color(stage)).frame(width: max(6, proxy.size.width * min(1, share)))
                }
            }
            .frame(height: 6)
            Text(reference).font(.caption2).foregroundStyle(.secondary)
        }
    }

    static func color(_ stage: SleepSegment.Stage) -> Color {
        switch stage {
        case .deep: Color(light: 0x333D29, dark: 0x656D4A)
        case .core: Color(light: 0xA4AC86, dark: 0xA4AC86)
        case .rem: Color(light: 0x7F4F24, dark: 0xA68A64)
        case .awake: Color(light: 0xD8CDB0, dark: 0xE0A85C)
        }
    }

    // MARK: Dette et physiologie

    private var debtCard: some View {
        let need = snapshot.sleepNeed.base
        let start = Calendar.current.date(byAdding: .day, value: -13, to: Calendar.current.startOfDay(for: .now)) ?? .now
        let nights = snapshot.wellness.filter { $0.day >= start && $0.sleepHours != nil }
        let debt = snapshot.sleepDebt
        return GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        CapsLabel("Dette de sommeil · 14 nuits")
                        Text(debt < 0.25 ? "Aucune" : debt.hoursText)
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                    }
                    Spacer()
                    StatusPill(text: debt < 2 ? "Faible" : (debt < 5 ? "À rattraper" : "Élevée"),
                               symbol: debt < 2 ? "checkmark.circle.fill" : "exclamationmark.circle.fill",
                               color: debt < 2 ? Theme.good : (debt < 5 ? Theme.caution : Theme.alert))
                }
                Chart {
                    ForEach(nights, id: \.day) { record in
                        BarMark(x: .value("Nuit", record.day, unit: .day), y: .value("Sommeil", record.sleepHours ?? 0))
                            .foregroundStyle((record.sleepHours ?? 0) >= need ? Theme.good : Theme.caution)
                            .cornerRadius(3)
                    }
                    RuleMark(y: .value("Besoin", need))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("besoin \(need.hoursText)").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .dateAxis(days: 14)
                .frame(height: 140)
                Text("Chaque heure manquée s'ajoute à la dette ; les nuits anciennes comptent moins (× 0,85 par jour). On rattrape au mieux 1 h par nuit : mieux vaut se coucher plus tôt plusieurs soirs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var physiologyGrid: some View {
        let hrv = night?.hrvRMSSD ?? night?.hrvMs
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatTile(title: "FC pendant le sommeil", value: night?.sleepingHeartRate.map { "\($0.noDecimal) bpm" } ?? "–")
            StatTile(title: "VFC nocturne", value: hrv.map { "\($0.noDecimal) ms" } ?? "–")
            StatTile(title: "Respiration", value: night?.respiration.map { "\($0.oneDecimal) /min" } ?? "–")
            StatTile(title: "Score Garmin", value: night?.sleepScore.map { $0.noDecimal } ?? "–", caption: "pour comparer")
        }
    }
}
