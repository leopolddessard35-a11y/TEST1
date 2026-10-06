import SwiftUI
import Charts

// MARK: - Trois cadrans : récupération, effort, sommeil

struct ScoreTrio: View {
    let snapshot: CoachSnapshot

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                ReadinessDetailView(readiness: snapshot.readiness, history: Array(snapshot.readinessHistory.suffix(30)),
                                    hrvSource: snapshot.hrvSource)
            } label: {
                Dial(title: "Récup", value: Double(snapshot.readiness?.score ?? 0), maximum: 100,
                     text: snapshot.readiness.map { "\($0.score)" } ?? "–", suffix: "%",
                     color: snapshot.readiness.map { Theme.color(for: $0.level) } ?? .secondary)
            }
            NavigationLink {
                EffortDetailView(today: snapshot.effortToday, target: snapshot.effortTarget, history: snapshot.effortHistory,
                                 verdict: snapshot.brief.verdict)
            } label: {
                Dial(title: "Effort", value: snapshot.effortToday, maximum: 21,
                     text: snapshot.effortToday.oneDecimal, suffix: "",
                     color: Theme.strain, target: snapshot.effortTarget)
            }
            NavigationLink {
                SleepNeedDetailView(need: snapshot.sleepNeed, performance: snapshot.lastSleepPerformance,
                                    lastNight: snapshot.wellness.last.flatMap { Calendar.current.isDateInToday($0.day) ? $0.sleepHours : nil },
                                    regularity: snapshot.bedtimeRegularity)
            } label: {
                Dial(title: "Sommeil", value: (snapshot.lastSleepPerformance ?? 0) * 100, maximum: 100,
                     text: snapshot.lastSleepPerformance.map { "\(Int(($0 * 100).rounded()))" } ?? "–", suffix: "%",
                     color: Theme.sleep)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Cadran circulaire animé, avec la zone cible en option (effort).
struct Dial: View {
    let title: String
    let value: Double
    let maximum: Double
    let text: String
    let suffix: String
    let color: Color
    var target: ClosedRange<Double>?
    @State private var shown: Double = 0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 9)
                if let target {
                    Circle()
                        .trim(from: target.lowerBound / maximum, to: target.upperBound / maximum)
                        .stroke(Color.primary.opacity(0.25), style: StrokeStyle(lineWidth: 15, lineCap: .butt))
                        .rotationEffect(.degrees(-90))
                }
                Circle()
                    .trim(from: 0, to: max(0.001, min(1, shown / maximum)))
                    .stroke(color, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: color.opacity(0.4), radius: 6)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(text).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    if !suffix.isEmpty { Text(suffix).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                }
            }
            .frame(width: 88, height: 88)
            Text(title).font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .card(cornerRadius: 22)
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.8).delay(0.1)) { shown = value } }
        .onChange(of: value) { withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) { shown = value } }
    }
}

// MARK: - Effort

struct EffortDetailView: View {
    let today: Double
    let target: ClosedRange<Double>
    let history: [DayValue]
    let verdict: Verdict

    var body: some View {
        let remaining = max(0, EffortScore.load(for: target.lowerBound) - EffortScore.load(for: today))
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(spacing: 12) {
                        Dial(title: EffortScore.label(today), value: today, maximum: 21, text: today.oneDecimal, suffix: "/21",
                             color: Theme.strain, target: target)
                        Text(String(format: "Cible du jour : %.0f – %.0f", target.lowerBound, target.upperBound)).font(.headline)
                        Text(status(remaining: remaining)).font(.subheadline).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "30 derniers jours", symbol: "calendar")
                        Chart(history, id: \.date) { point in
                            BarMark(x: .value("Jour", point.date, unit: .day), y: .value("Effort", point.value))
                                .foregroundStyle(Theme.strain.opacity(point.value >= 14 ? 1 : 0.55))
                                .cornerRadius(3)
                        }
                        .chartYScale(domain: 0...21)
                        .frame(height: 160)
                        if let mean = Stats.mean(history.suffix(7).map(\.value)) {
                            Text(String(format: "Moyenne 7 jours : %.1f / 21", mean)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                ExplanationCard(title: "Comment c'est calculé", symbol: "function", text: """
                L'effort additionne tout ce qui fatigue ton corps dans la journée : séances (charge TSS, via puissance, FC ou effort ressenti), musculation, activités hors sport et pas au-delà de 12 000.
                L'échelle va de 0 à 21 et elle est logarithmique : passer de 10 à 14 demande autant que de 0 à 10, et dépasser 18 demande un très gros effort. Repères : 1 h facile ≈ 9 · 1 h au seuil ≈ 14 · 3 h de sortie longue ≈ 18.
                La cible dépend de ta récupération du matin : 14–18 si tu es prêt, 10–14 si la récup est moyenne, 4–9 si elle est basse.
                """)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Effort")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func status(remaining: Double) -> String {
        if today > target.upperBound { return "Tu as dépassé ta cible : place-toi en récupération pour le reste de la journée." }
        if today >= target.lowerBound { return "Cible atteinte : bonne journée d'entraînement." }
        if verdict == .rest { return "Journée de repos : reste sous la cible." }
        return String(format: "Encore ≈ %.0f points de charge pour atteindre ta cible (≈ %@ en endurance).", remaining, (remaining / 50).hoursText)
    }
}

// MARK: - Sommeil

struct SleepNeedDetailView: View {
    let need: SleepNeed
    let performance: Double?
    let lastNight: Double?
    let regularity: (sd: Double, average: String)?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(spacing: 10) {
                        Text("Besoin de sommeil cette nuit").font(.subheadline).foregroundStyle(.secondary)
                        Text(need.total.hoursText).font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                        HStack(spacing: 6) {
                            Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.sleep)
                            Text("Couche-toi vers \(need.bedtimeText)").font(.headline)
                        }
                        Text(String(format: "pour %@ au lit (efficacité de sommeil %.0f %%) avant ton réveil habituel de %d h %02d",
                                    need.timeInBed.hoursText, need.efficiency * 100, need.usualWakeMinutes / 60, need.usualWakeMinutes % 60))
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionTitle(title: "D'où vient ce besoin", symbol: "plus.forwardslash.minus")
                        row("Besoin de base", need.base, "réglable dans Réglages")
                        row("Effort du jour", need.effortExtra, "+4 min par point d'effort au-delà de 10")
                        row("Rattrapage de dette", need.debtExtra, "¼ de la dette des 7 derniers jours, 1 h max")
                        Divider()
                        row("Total", need.total, "")
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Nuit dernière", value: lastNight?.hoursText ?? "–")
                    StatTile(title: "Performance", value: performance.map { "\(Int(($0 * 100).rounded())) %" } ?? "–", caption: "sommeil / besoin")
                    StatTile(title: "Coucher moyen", value: regularity?.average ?? "–")
                    StatTile(title: "Régularité", value: regularity.map { String(format: "±%.0f min", $0.sd) } ?? "–", caption: "repère : ±30 min")
                }
                ExplanationCard(title: "Pourquoi ton besoin change chaque jour", symbol: "lightbulb", text: "Plus la journée a été exigeante, plus le corps a besoin de sommeil pour réparer les muscles et reconstituer ses réserves. Une dette accumulée se rembourse progressivement, pas en une nuit. Viser ce besoin plutôt qu'un chiffre fixe est la meilleure façon de garder une récupération haute.")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle("Sommeil")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ hours: Double, _ caption: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline)
                if !caption.isEmpty { Text(caption).font(.caption2).foregroundStyle(.secondary) }
            }
            Spacer()
            let absolute: Bool = title == "Total" || title == "Besoin de base"
            let text: String = absolute ? hours.hoursText : (hours > 0 ? "+" + hours.hoursText : "—")
            Text(text).font(.subheadline.monospacedDigit().weight(title == "Total" ? .bold : .regular))
        }
    }
}

// MARK: - Bilan hebdomadaire

struct WeeklyReportCard: View {
    let report: WeeklyReport

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(title: "Bilan des 7 derniers jours", symbol: "doc.text.magnifyingglass")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    compare("Récupération", report.current.recovery, report.previous.recovery, "%.0f")
                    compare("Effort moyen", report.current.effort, report.previous.effort, "%.1f")
                    compare("Sommeil", report.current.sleepHours, report.previous.sleepHours, "%.1f h")
                    compare("Perf. sommeil", report.current.sleepPerformance.map { $0 * 100 }, report.previous.sleepPerformance.map { $0 * 100 }, "%.0f %%")
                    compare("Entraînement", report.current.trainingHours, report.previous.trainingHours, "%.1f h")
                    compare("Calories / jour", report.current.kcal, report.previous.kcal, "%.0f")
                }
                ForEach(report.highlights, id: \.self) { line in
                    Label(line, systemImage: "sparkle").font(.footnote)
                }
            }
        }
    }

    private func compare(_ title: String, _ now: Double?, _ before: Double?, _ format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(now.map { String(format: format, $0) } ?? "–").font(.title3.weight(.semibold).monospacedDigit())
            if let now, let before, before != 0 {
                let delta = now - before
                Text(String(format: "%@ vs sem. préc.", String(format: format, before)))
                    .font(.caption2).foregroundStyle(delta >= 0 ? Theme.recovery : Theme.nutrition)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Revue du dimanche

/// Prévu vs réalisé, charge, 1 point fort, 1 point de vigilance, ajustement proposé.
struct WeeklyReviewCard: View {
    let report: WeeklyReport
    let review: WeeklyReport.Review
    @State private var narration: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(title: "Revue de la semaine", symbol: "calendar.badge.checkmark")
                HStack {
                    StatTile(title: "Prévu / réalisé",
                             value: "\(review.doneHours.oneDecimal) / \(review.plannedHours.map { $0.oneDecimal } ?? "–") h")
                    StatTile(title: "Muscu", value: "\(review.doneStrength) / \(review.plannedStrength)")
                    StatTile(title: "Charge", value: report.current.load.noDecimal, caption: "TSS sur 7 j")
                }
                Label(review.strongPoint, systemImage: "hand.thumbsup.fill").font(.footnote)
                Label(review.vigilance, systemImage: "eye.fill").font(.footnote)
                Label(review.adjustment, systemImage: "arrow.triangle.turn.up.right.circle.fill").font(.footnote.weight(.semibold))
                if let narration {
                    Divider()
                    Text(narration).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .task {
            // Reformulation par le modèle local d'Apple si disponible : il ne calcule rien, il raconte.
            narration = await WeeklyNarrator.narrate(report: report, review: review)
        }
    }
}
