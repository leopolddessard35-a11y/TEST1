import SwiftUI

// MARK: - Anneau à dégradé

/// Anneau qui se remplit avec un dégradé (clair → saturé), comme les cadrans de Bevel.
struct GradientRing: View {
    /// 0…1
    let fraction: Double
    let colors: [Color]
    var lineWidth: CGFloat = 10
    @State private var shown: Double = 0

    var body: some View {
        let trimmed = max(0.001, min(1, shown))
        ZStack {
            Circle().stroke(colors.last?.opacity(0.14) ?? Color.secondary.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: trimmed)
                .stroke(AngularGradient(colors: colors, center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * trimmed)),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .onAppear { withAnimation(.spring(response: 1.1, dampingFraction: 0.85).delay(0.1)) { shown = fraction } }
        .onChange(of: fraction) { withAnimation(.spring(response: 0.8, dampingFraction: 0.85)) { shown = fraction } }
    }
}

/// Un anneau, sa valeur au centre et son nom dessous.
struct RingStat: View {
    let title: String
    let fraction: Double
    let text: String
    var suffix: String = ""
    let colors: [Color]

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                GradientRing(fraction: fraction, colors: colors, lineWidth: 9)
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(text).font(.system(.title3, design: .rounded).weight(.bold)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !suffix.isEmpty { Text(suffix).font(.caption2.weight(.semibold)).foregroundStyle(.secondary) }
                }
            }
            .frame(width: 84, height: 84)
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Moniteur de santé

/// Où se situe la valeur du jour par rapport à TA normale (médiane ± écart robuste des 30 derniers jours).
struct HealthReading {
    enum Status {
        case normal, higher, lower, unknown

        var label: String {
            switch self {
            case .normal: "Normal"
            case .higher: "Supérieur"
            case .lower: "Inférieur"
            case .unknown: "En calibrage"
            }
        }

        var symbol: String {
            switch self {
            case .normal: "checkmark.circle.fill"
            case .higher: "arrow.up.circle.fill"
            case .lower: "arrow.down.circle.fill"
            case .unknown: "hourglass.circle.fill"
            }
        }
    }

    let latest: Double?
    let status: Status
    /// Position de la valeur sur la jauge (0 = bas, 1 = haut).
    let position: Double
    /// Bande « normale » sur la jauge.
    let band: ClosedRange<Double>
    /// Écart dans le sens défavorable et marqué (> 2 écarts) : affiché en rouge.
    let concerning: Bool

    static func evaluate(_ unsorted: [DayValue], higherIsBetter: Bool?) -> HealthReading {
        let series: [DayValue] = unsorted.sorted { $0.date < $1.date }
        guard let last = series.last else {
            return HealthReading(latest: nil, status: .unknown, position: 0.5, band: 0.35...0.65, concerning: false)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: last.date) ?? last.date
        let baseline: [Double] = series.dropLast().filter { $0.date >= cutoff }.map(\.value)
        guard baseline.count >= 5, let center = Robust.median(baseline) else {
            return HealthReading(latest: last.value, status: .unknown, position: 0.5, band: 0.35...0.65, concerning: false)
        }
        // Écart robuste, avec un plancher de 2 % pour les mesures très stables (respiration, poids).
        let spread = max(Robust.mad(baseline) ?? 0, abs(center) * 0.02, 0.0001)
        let low = center - 3 * spread, high = center + 3 * spread
        let position = min(1, max(0, (last.value - low) / (high - low)))
        let z = (last.value - center) / spread
        let status: Status = z > 1 ? .higher : (z < -1 ? .lower : .normal)
        var concerning = false
        if let higherIsBetter, abs(z) > 2 {
            concerning = higherIsBetter ? z < 0 : z > 0
        }
        return HealthReading(latest: last.value, status: status, position: position,
                             band: (1.0 / 3)...(2.0 / 3), concerning: concerning)
    }

    var color: Color {
        switch status {
        case .normal: Theme.recovery
        case .unknown: .secondary
        case .higher, .lower: concerning ? Theme.warning : Theme.strain
        }
    }
}

/// Petite jauge verticale : la zone normale est marquée, la pastille montre la valeur du jour.
struct VerticalGauge: View {
    let position: Double
    let band: ClosedRange<Double>
    let color: Color
    @State private var shown: Double = 0.5

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(Theme.recovery.opacity(0.35))
                    .frame(height: height * (band.upperBound - band.lowerBound))
                    .offset(y: -height * band.lowerBound)
                Circle()
                    .fill(color)
                    .overlay(Circle().stroke(Color(uiColor: .secondarySystemGroupedBackground), lineWidth: 2))
                    .frame(width: 12, height: 12)
                    .offset(y: -(height - 12) * shown)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 12)
        .onAppear { withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.15)) { shown = position } }
        .onChange(of: position) { withAnimation(.spring) { shown = position } }
    }
}

/// Tuile du « Moniteur de santé » : statut et jauge (Bevel), chiffre massif et courbe fine (Ultrahuman / Whoop).
struct HealthMonitorTile: View {
    let title: String
    let symbol: String
    let value: String
    let unit: String
    let reading: HealthReading
    var tint: Color = Theme.sleep
    var trend: [Double] = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    IconBadge(symbol: symbol, tint: tint, size: 22)
                    Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                }
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if !unit.isEmpty { Text(unit).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
                }
                if trend.count >= 2 {
                    Sparkline(values: trend, color: tint).frame(height: 22)
                }
                StatusPill(text: reading.status.label, symbol: reading.status.symbol, color: reading.color)
            }
            Spacer(minLength: 0)
            VerticalGauge(position: reading.position, band: reading.band, color: reading.color)
                .frame(height: 84)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 22, tint: tint)
    }
}

// MARK: - Grille de points (macros)

/// Grille de points qui se colorent selon le pourcentage atteint (10 colonnes).
struct DotGrid: View {
    let fraction: Double
    let color: Color
    var rows = 3
    var columns = 10

    var body: some View {
        let total = rows * columns
        let filled = Int((min(1, max(0, fraction)) * Double(total)).rounded())
        VStack(spacing: 4) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        Circle()
                            .fill(index < filled ? color : color.opacity(0.15))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.6), value: filled)
    }
}

/// Bloc macro : nom, grammes et grille de points.
struct MacroDots: View {
    let label: String
    let value: Double
    let target: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value.noDecimal).font(.headline.monospacedDigit())
                Text("/ \(target.noDecimal) g").font(.caption2).foregroundStyle(.secondary)
            }
            DotGrid(fraction: target > 0 ? value / target : 0, color: color, rows: 2, columns: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bande de calendrier

/// Les 7 jours de la semaine avec une icône par jour (fait, manqué, repos, à venir).
struct WeekStrip: View {
    let days: [DayStatus]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(days) { day in
                let isToday = Calendar.current.isDateInToday(day.date)
                VStack(spacing: 6) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(isToday ? Color.primary : Color.secondary)
                    Text(day.date.formatted(.dateTime.day()))
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .frame(width: 32, height: 32)
                        .background(isToday ? Theme.strain.opacity(0.18) : Color.clear, in: .circle)
                    Image(systemName: Self.symbol(day))
                        .font(.caption)
                        .foregroundStyle(WeekStatusCard.color(day.status))
                        .frame(height: 14)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    static func symbol(_ day: DayStatus) -> String {
        switch day.status {
        case .rest: return "moon.zzz.fill"
        case .missed: return "xmark"
        case .upcoming, .today:
            return day.planned.first?.kind.symbol ?? "circle.dotted"
        case .done, .partial:
            return day.planned.first?.kind.symbol ?? "checkmark"
        }
    }
}

// MARK: - Barre d'énergie

/// Barre horizontale à dégradé (énergie, charge…), avec la valeur en pourcentage.
struct GradientBar: View {
    let fraction: Double
    let colors: [Color]
    var height: CGFloat = 12
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.14))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * min(1, max(0, shown))))
            }
        }
        .frame(height: height)
        .onAppear { withAnimation(.spring(response: 1.0, dampingFraction: 0.85).delay(0.1)) { shown = fraction } }
        .onChange(of: fraction) { withAnimation(.spring) { shown = fraction } }
    }
}
