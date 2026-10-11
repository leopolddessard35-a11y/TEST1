import SwiftUI
import Charts

/// Cadran circulaire animé, avec la zone cible en option (effort).
struct Dial: View {
    let title: String
    let value: Double
    let maximum: Double
    let text: String
    let suffix: String
    let color: Color
    var target: ClosedRange<Double>?
    /// Fond de carte propre. À désactiver quand le cadran est déjà posé dans une carte (pas de carte dans la carte).
    var bordered: Bool = true
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
        .padding(.vertical, bordered ? 12 : 0)
        .background {
            if bordered { Color.clear.card(cornerRadius: 22) }
        }
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
            VStack(spacing: 12) {
                GlassCard {
                    VStack(spacing: 12) {
                        Dial(title: EffortScore.label(today), value: today, maximum: 21, text: today.oneDecimal, suffix: "/21",
                             color: Theme.strain, target: target, bordered: false)
                        Text("Cible du jour : \(target.lowerBound.noDecimal) – \(target.upperBound.noDecimal)").font(.headline)
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
                        .dateAxis(days: 30)
                        .frame(height: 160)
                        if let mean = Stats.mean(history.suffix(7).map(\.value)) {
                            Text("Moyenne 7 jours : \(mean.oneDecimal) / 21").font(.caption).foregroundStyle(.secondary)
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
        // Jour de repos : la « cible » est un plafond, pas un objectif à atteindre.
        if verdict == .rest {
            return today > target.upperBound
                ? "Journée de repos : tu as déjà dépassé le plafond, lève le pied pour le reste de la journée."
                : "Journée de repos : reste sous la cible."
        }
        if today > target.upperBound { return "Tu as dépassé ta cible : place-toi en récupération pour le reste de la journée." }
        if today >= target.lowerBound { return "Cible atteinte : bonne journée d'entraînement." }
        return "Encore ≈ \(remaining.noDecimal) points de charge pour atteindre ta cible (≈ \((remaining / 50).hoursText) en endurance)."
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
            VStack(spacing: 12) {
                GlassCard {
                    VStack(spacing: 10) {
                        Text("Besoin de sommeil cette nuit").font(.subheadline).foregroundStyle(.secondary)
                        Text(need.total.hoursText).font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                        HStack(spacing: 6) {
                            Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.sleep)
                            Text("Couche-toi vers \(need.bedtimeText)").font(.headline)
                        }
                        Text(String(format: "pour %@ au lit (efficacité de sommeil %.0f %%) avant ton réveil habituel de %@",
                                    need.timeInBed.hoursText, need.efficiency * 100, need.wakeText))
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
            let text: String = absolute ? hours.hoursText : (hours > 0 ? "+" + hours.hoursText : "–")
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
                    compare("Récupération", report.current.recovery, report.previous.recovery, decimals: 0, higherIsBetter: true)
                    compare("Effort moyen", report.current.effort, report.previous.effort, decimals: 1)
                    compare("Sommeil", report.current.sleepHours, report.previous.sleepHours, decimals: 1, unit: " h", higherIsBetter: true)
                    compare("Perf. sommeil", report.current.sleepPerformance.map { $0 * 100 }, report.previous.sleepPerformance.map { $0 * 100 },
                            decimals: 0, unit: " %", higherIsBetter: true)
                    compare("Entraînement", report.current.trainingHours, report.previous.trainingHours, decimals: 1, unit: " h")
                    compare("Calories / jour", report.current.kcal, report.previous.kcal, decimals: 0)
                }
                ForEach(report.highlights, id: \.self) { line in
                    Label(line, systemImage: "sparkle").font(.footnote)
                }
            }
        }
    }

    /// `higherIsBetter` : nil = ni bon ni mauvais en soi (effort, calories, volume) → couleur neutre.
    private func compare(_ title: String, _ now: Double?, _ before: Double?, decimals: Int, unit: String = "",
                         higherIsBetter: Bool? = nil) -> some View {
        let format: (Double) -> String = { value in
            value.decimals(decimals) + unit
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(now.map(format) ?? "–").font(.title3.weight(.semibold).monospacedDigit())
            if let now, let before, before != 0 {
                let delta = now - before
                let color: Color = {
                    guard let higherIsBetter, delta != 0 else { return .secondary }
                    return (delta > 0) == higherIsBetter ? Theme.recovery : Theme.nutrition
                }()
                Text("\(format(before)) vs sem. préc.")
                    .font(.caption2).foregroundStyle(color)
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
                    StatTile(title: "Réalisé / prévu",
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
