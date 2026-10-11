import SwiftUI

/// Grille 2 colonnes : chaque mesure du matin comparée à ta normale (60 derniers jours).
struct HealthMonitorGrid: View {
    let snapshot: CoachSnapshot

    var body: some View {
        let wellness = snapshot.wellness
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            tile(.respiration, series: snapshot.respirationSeries,
                 note: snapshot.respirationSource + (snapshot.respiratory.map { " · \($0.delta.decimals(1, signed: true)) resp/min vs ta normale" } ?? ""))
            tile(.restingHR, series: snapshot.restingHRSeries, note: snapshot.restingHRSource)
            tile(.hrv, series: snapshot.hrvSeries, note: snapshot.hrvSource)
            tile(.sleep, series: MetricKind.sleep.series(from: wellness), note: snapshot.sleepSource, extra: sleepTiles)
            tile(.weight, series: MetricKind.weight.series(from: wellness), note: MetricKind.weight.sourceLabel(from: wellness))
            tile(.vo2max, series: MetricKind.vo2max.series(from: wellness), note: MetricKind.vo2max.sourceLabel(from: wellness))
        }
        .buttonStyle(.pressable)
    }

    private var sleepTiles: [(title: String, value: String, caption: String)] {
        guard let regularity = snapshot.bedtimeRegularity else { return [] }
        return [(title: "Coucher moyen", value: regularity.average, caption: "14 dernières nuits"),
                (title: "Régularité", value: "±\(regularity.sd.noDecimal) min", caption: "repère : ±30 min")]
    }

    private func tile(_ kind: MetricKind, series: [DayValue], note: String? = nil,
                      extra: [(title: String, value: String, caption: String)] = []) -> some View {
        let reading = HealthReading.evaluate(series, higherIsBetter: kind.higherIsBetter)
        let unit = kind == .sleep ? "" : kind.unit
        // Courbe des 14 derniers JOURS (pas des 14 dernières valeurs : une montre oubliée ne doit pas étirer la période).
        let trend: [Double] = Stats.lastDays(14, of: series.sorted { $0.date < $1.date }, today: .now).map(\.value)
        return NavigationLink {
            MetricDetailView(kind: kind, series: series, sourceNote: note, extraTiles: extra, events: snapshot.chartEvents)
        } label: {
            HealthMonitorTile(title: kind.shortTitle, symbol: kind.symbol, value: reading.latest.map { kind.format($0) } ?? "–",
                              unit: unit, reading: reading, tint: kind.color, trend: trend,
                              higherIsBetter: kind.higherIsBetter)
        }
    }
}

extension MetricKind {
    /// Titre court pour les tuiles du moniteur.
    var shortTitle: String {
        switch self {
        case .respiration: "Respiration"
        case .restingHR: "FC repos"
        default: title
        }
    }
}

/// Indique si le verdict repose sur des données complètes ou partielles.
struct ConfidenceRow: View {
    let confidence: DataConfidence

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: confidence.ratio >= 0.8 ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(confidence.label) · \(confidence.present.count)/\(confidence.present.count + confidence.missing.count) sources")
                    .font(.caption.weight(.semibold))
                if !confidence.missing.isEmpty {
                    Text("Manquant : " + confidence.missing.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .foregroundStyle(confidence.ratio >= 0.8 ? Theme.recovery : Theme.nutrition)
        .padding(.horizontal, 4)
    }
}
