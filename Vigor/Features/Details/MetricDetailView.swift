import SwiftUI
import Charts

enum MetricKind: String, Identifiable, CaseIterable {
    case sleep, hrv, restingHR, steps, weight, vo2max, respiration

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sleep: "Sommeil"
        case .hrv: "VFC"
        case .restingHR: "FC au repos"
        case .steps: "Pas"
        case .weight: "Poids"
        case .vo2max: "VO2max"
        case .respiration: "Respiration"
        }
    }

    var unit: String {
        switch self {
        case .sleep: "h"
        case .hrv: "ms"
        case .restingHR: "bpm"
        case .steps: ""
        case .weight: "kg"
        case .vo2max: "ml/kg/min"
        case .respiration: "resp/min"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "bed.double.fill"
        case .hrv: "waveform.path.ecg"
        case .restingHR: "heart.fill"
        case .steps: "figure.walk"
        case .weight: "scalemass.fill"
        case .vo2max: "figure.run.circle"
        case .respiration: "lungs.fill"
        }
    }

    var color: Color {
        switch self {
        case .sleep: Theme.sleep
        case .hrv: Theme.recovery
        case .restingHR: Theme.warning
        case .steps, .weight: Theme.nutrition
        case .vo2max: Theme.strain
        case .respiration: Theme.sleep
        }
    }

    /// Plus haut = mieux ? (nil = ça dépend de l'objectif)
    var higherIsBetter: Bool? {
        switch self {
        case .sleep, .hrv, .steps, .vo2max: true
        case .restingHR, .respiration: false
        case .weight: nil
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .sleep: value.hoursText
        case .weight, .vo2max, .respiration: value.oneDecimal
        default: value.noDecimal
        }
    }

    func series(from wellness: [DailyWellness]) -> [DayValue] {
        wellness.compactMap { record in
            let value: Double?
            switch self {
            case .sleep: value = record.sleepHours
            case .hrv: value = record.hrvRMSSD ?? record.hrvMs
            case .restingHR: value = record.restingHeartRate
            case .steps: value = record.steps
            case .weight: value = record.weightKg
            case .vo2max: value = record.vo2Max
            case .respiration: value = record.respiration
            }
            return value.map { DayValue(date: record.day, value: $0) }
        }
    }

    var about: String {
        switch self {
        case .sleep:
            "Durée de sommeil réel (hors éveils) mesurée par ta montre. C'est pendant le sommeil profond que l'hormone de croissance est sécrétée et que les muscles se réparent."
        case .hrv:
            "La variabilité de la fréquence cardiaque mesure les micro-variations entre deux battements. Plus elle est haute par rapport à TA normale, plus ton système nerveux parasympathique (récupération) est actif."
        case .restingHR:
            "Fréquence cardiaque la plus basse pendant la nuit. Une hausse de 3 à 5 bpm au-dessus de ta moyenne signale souvent fatigue, déshydratation, alcool, chaleur ou maladie qui commence."
        case .steps:
            "Activité quotidienne hors entraînement (NEAT). Elle compte dans ta dépense énergétique et donc dans tes besoins caloriques."
        case .weight:
            "Le poids varie de ±1 kg d'un jour à l'autre (eau, glycogène, transit). Vigor lisse la courbe (moyenne exponentielle) pour voir la vraie tendance."
        case .respiration:
            "Nombre de respirations par minute pendant le sommeil. Elle varie très peu d'une nuit à l'autre chez toi : une hausse d'1 respiration/min ou plus est un des signaux les plus précoces d'une infection."
        case .vo2max:
            "Consommation maximale d'oxygène estimée par Garmin à partir de la relation puissance / FC. C'est le plafond de ton moteur aérobie."
        }
    }

    var howUsed: String {
        switch self {
        case .sleep: "30 % du score de récupération. Une dette de plus de 5 h sur 7 jours déclenche une alerte du coach."
        case .hrv: "45 % du score de récupération : moyenne des 3 derniers jours (en log) comparée à tes 60 derniers jours. La tendance sur 7 jours, croisée avec la FC de repos, sert à détecter le surmenage."
        case .restingHR: "25 % du score de récupération : dernière valeur comparée à ta moyenne et ta variabilité sur 30 jours."
        case .steps: "Intégrés à la dépense énergétique (via l'énergie active) pour calculer tes calories cibles."
        case .weight: "La tendance sert à piloter la prise de masse (+0,25 à 0,5 %/semaine) et à mesurer ta dépense énergétique réelle."
        case .respiration: "Comparée à ta moyenne des 30 derniers jours. Au-delà de +1 resp/min (surtout avec une FC de repos en hausse), le coach supprime l'intensité et t'alerte."
        case .vo2max: "Indicateur de progression de fond : elle doit monter pendant les phases Foncier et Développement."
        }
    }

    var improve: String {
        switch self {
        case .sleep: "Horaires réguliers, chambre fraîche (18–19 °C), pas d'écran 30 min avant, caféine avant 14 h, dîner 2–3 h avant le coucher."
        case .hrv: "Sommeil, régularité, endurance facile (zone 2), limiter l'alcool (même 1–2 verres font chuter la VFC la nuit suivante), gestion du stress."
        case .restingHR: "Elle baisse avec l'endurance de fond. Si elle monte plusieurs jours : allège, hydrate-toi, surveille les signes de maladie."
        case .steps: "Marcher 20–30 min par jour aide la récupération active sans fatiguer."
        case .weight: "Pèse-toi le matin, à jeun, après être allé aux toilettes, au moins 3 fois par semaine."
        case .respiration: "Tu n'as pas à l'améliorer : c'est un témoin. Si elle monte, repos, hydratation, et surveille fièvre et gorge."
        case .vo2max: "Séances VO2max (ex. 5 × 4 min à 110–120 % FTP) en phase Développement + volume d'endurance."
        }
    }

    var references: [Reference] {
        switch self {
        case .sleep: [Science.hirshkowitz2015, Science.mah2011, Science.milewski2014, Science.phillips2017]
        case .hrv: [Science.plews2013, Science.buchheit2014, Science.kiviniemi2007]
        case .restingHR: [Science.buchheit2014]
        case .steps: [Science.mifflin1990]
        case .weight: [Science.iraki2019, Science.hall2008]
        case .vo2max: [Science.seiler2010]
        case .respiration: [Science.buchheit2014]
        }
    }
}

struct MetricDetailView: View {
    let kind: MetricKind
    let series: [DayValue]
    var sourceNote: String?
    /// Tuiles supplémentaires (ex. régularité du coucher pour le sommeil).
    var extraTiles: [(title: String, value: String, caption: String)] = []
    /// Événements à annoter (maladie, voyage, travaux, chaussures…).
    var events: [ChartEvent] = []
    @State private var days = 30

    var body: some View {
        let sorted = series.sorted { $0.date < $1.date }
        let visible = Stats.lastDays(days, of: sorted, today: .now)
        let baseline = Stats.lastDays(60, of: sorted, today: .now).map(\.value)
        // Bande de normalité personnelle robuste : même règle que l'accueil (médiane ± écart, 60 jours).
        let reading = HealthReading.evaluate(sorted, higherIsBetter: kind.higherIsBetter)
        let mean: Double? = reading.center ?? (baseline.count >= 7 ? Robust.median(baseline) : nil)
        let sd: Double = reading.spread ?? (baseline.count >= 7 ? (Robust.mad(baseline) ?? 0) : 0)
        let segments: [[DayValue]] = DataGaps.segments(visible)
        let missing: Int = DataGaps.missingDays(sorted, days: days)
        let firstVisible: Date = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        let visibleEvents: [ChartEvent] = events.filter { $0.end >= firstVisible }
        let week = Stats.mean(Stats.lastDays(7, of: sorted, today: .now).map(\.value))
        let month = Stats.mean(Stats.lastDays(30, of: sorted, today: .now).map(\.value))
        let slope = Stats.slopePerDay(Stats.lastDays(28, of: sorted, today: .now)).map { $0 * 7 }

        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(kind.title, systemImage: kind.symbol).font(.headline).foregroundStyle(kind.color)
                        if let latest = sorted.last {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(kind.format(latest.value)).font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                                Text(kind == .sleep ? "" : kind.unit).foregroundStyle(.secondary)
                            }
                            Text(latest.date.formatted(date: .complete, time: .omitted)).font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                StatusPill(text: reading.status.label, symbol: reading.status.symbol, color: reading.color)
                                Text(reading.sentence(higherIsBetter: kind.higherIsBetter)).font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text("Pas encore de données.").foregroundStyle(.secondary)
                        }
                        if let sourceNote { Text("Source : \(sourceNote)").font(.caption).foregroundStyle(.secondary) }
                    }
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 14) {
                        RangePicker(days: $days)
                        Chart {
                            if let mean, sd > 0, let first = visible.first?.date, let last = visible.last?.date, kind != .steps {
                                RectangleMark(xStart: .value("Début", first), xEnd: .value("Fin", last),
                                              yStart: .value("Bas", mean - sd), yEnd: .value("Haut", mean + sd))
                                    .foregroundStyle(kind.color.opacity(0.12))
                                RuleMark(y: .value("Moyenne", mean))
                                    .foregroundStyle(kind.color.opacity(0.5))
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                            }
                            ForEach(visibleEvents) { event in
                                RectangleMark(xStart: .value("Début", max(event.start, firstVisible)),
                                              xEnd: .value("Fin", event.end.addingTimeInterval(86_400)))
                                    .foregroundStyle(Color.primary.opacity(0.05))
                                    // Icône posée DANS la zone du graphique (en haut), jamais par-dessus le sélecteur.
                                    .annotation(position: .overlay, alignment: .top, spacing: 0) {
                                        EventBadge(symbol: event.symbol)
                                    }
                            }
                            if kind == .steps {
                                ForEach(visible, id: \.date) { point in
                                    BarMark(x: .value("Jour", point.date, unit: .day), y: .value(kind.title, point.value))
                                        .foregroundStyle(kind.color.gradient)
                                }
                            } else {
                                // Une série par segment continu : un jour sans donnée laisse un trou visible.
                                ForEach(segments.indices, id: \.self) { index in
                                    ForEach(segments[index], id: \.date) { point in
                                        LineMark(x: .value("Jour", point.date), y: .value(kind.title, point.value),
                                                 series: .value("Segment", index))
                                            .foregroundStyle(kind.color)
                                        if days <= 30 {
                                            PointMark(x: .value("Jour", point.date), y: .value(kind.title, point.value))
                                                .foregroundStyle(kind.color)
                                                .symbolSize(18)
                                        }
                                    }
                                }
                            }
                        }
                        .chartYScale(domain: .automatic(includesZero: kind == .steps))
                        .frame(height: 220)
                        if kind != .steps {
                            Text("Bande colorée : ta zone normale (médiane ± écart robuste sur 60 jours). Trous = jours sans donnée\(missing > 0 ? " (\(missing) sur la période)" : ""). Zones grisées : événements (maladie, voyage, travaux, chaussures).")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    StatTile(title: "Moyenne 7 j", value: week.map { kind.format($0) } ?? "–")
                    StatTile(title: "Moyenne 30 j", value: month.map { kind.format($0) } ?? "–")
                    StatTile(title: "Zone normale", value: mean.map { "\(kind.format($0 - sd))–\(kind.format($0 + sd))" } ?? "–", caption: "médiane ± écart, 60 j")
                    StatTile(title: "Tendance", value: slope.map { String(format: "%+.1f", kind == .sleep ? $0 * 60 : $0) } ?? "–",
                             caption: kind == .sleep ? "min / semaine" : "\(kind.unit) / semaine")
                    ForEach(extraTiles.indices, id: \.self) { index in
                        StatTile(title: extraTiles[index].title, value: extraTiles[index].value, caption: extraTiles[index].caption)
                    }
                }

                ExplanationCard(title: "Qu'est-ce que c'est ?", symbol: "questionmark.circle", text: kind.about)
                ExplanationCard(title: "Comment Vigor l'utilise", symbol: "function", text: kind.howUsed)
                ExplanationCard(title: "Comment l'améliorer", symbol: "arrow.up.heart", text: kind.improve)
                ReferencesCard(references: kind.references)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Pastille d'événement (maladie, voyage…) : petite, sur fond de carte, lisible sur la courbe.
struct EventBadge: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 18, height: 18)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .circle)
            .overlay(Circle().stroke(Color.secondary.opacity(0.25), lineWidth: 0.5))
            .padding(.top, 2)
    }
}
