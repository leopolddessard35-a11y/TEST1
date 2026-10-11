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
            case .unknown: "Normale en cours"
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
    /// Ta normale : médiane et écart robuste sur 60 jours (hors valeur du jour).
    var center: Double? = nil
    var spread: Double? = nil
    var z: Double? = nil
    /// Mesures déjà disponibles pour établir ta normale (il en faut `requiredBaseline`).
    var baselineCount: Int = 0
    static let requiredBaseline = 5

    /// Libellé qui dit si l'écart est bon ou non (« Haut, bon signe » plutôt que « Supérieur »).
    func label(higherIsBetter: Bool?) -> String {
        switch status {
        case .normal: return "Normal"
        case .unknown:
            if latest == nil { return "Pas encore de mesure" }
            let missing = max(1, Self.requiredBaseline - baselineCount)
            return "Normale dans \(missing) mesure\(missing > 1 ? "s" : "")"
        case .higher, .lower:
            let word = status == .higher ? "Haut" : "Bas"
            guard let higherIsBetter else { return status == .higher ? "Plus haut" : "Plus bas" }
            let good = (status == .higher) == higherIsBetter
            return good ? "\(word), bon signe" : "\(word), à surveiller"
        }
    }

    /// Règle unique, partagée par l'accueil et les pages de détail :
    /// |z| < 1 = normal ; 1–2 = légèrement au-dessus / en dessous ; > 2 = nettement.
    static func evaluate(_ unsorted: [DayValue], higherIsBetter: Bool?) -> HealthReading {
        let series: [DayValue] = unsorted.sorted { $0.date < $1.date }
        guard let last = series.last else {
            return HealthReading(latest: nil, status: .unknown, position: 0.5, band: 0.35...0.65, concerning: false)
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: last.date) ?? last.date
        let baseline: [Double] = series.dropLast().filter { $0.date >= cutoff }.map(\.value)
        guard baseline.count >= requiredBaseline, let center = Robust.median(baseline) else {
            return HealthReading(latest: last.value, status: .unknown, position: 0.5, band: 0.35...0.65, concerning: false,
                                 baselineCount: baseline.count)
        }
        // Écart robuste, avec un plancher de 2 % pour les mesures très stables (respiration, poids, FC).
        let spread = max(Robust.mad(baseline) ?? 0, abs(center) * 0.02, 0.0001)
        let low = center - 3 * spread, high = center + 3 * spread
        let position = min(1, max(0, (last.value - low) / (high - low)))
        let z = (last.value - center) / spread
        let status: Status = z >= 1 ? .higher : (z <= -1 ? .lower : .normal)
        var concerning = false
        if let higherIsBetter, abs(z) > 2 {
            concerning = higherIsBetter ? z < 0 : z > 0
        }
        return HealthReading(latest: last.value, status: status, position: position,
                             band: (1.0 / 3)...(2.0 / 3), concerning: concerning,
                             center: center, spread: spread, z: z, baselineCount: baseline.count)
    }

    /// Phrase de lecture, identique partout.
    func sentence(higherIsBetter: Bool?) -> String {
        guard let z else { return "Encore quelques jours de mesure pour connaître ta normale." }
        if abs(z) < 1 { return "Dans ta normale." }
        let direction = z > 0 ? "au-dessus" : "en dessous"
        let strength = abs(z) > 2 ? "Nettement" : "Légèrement"
        guard let higherIsBetter else { return "\(strength) \(direction) de ta normale." }
        let good = (z > 0) == higherIsBetter
        if abs(z) <= 2 { return "\(strength) \(direction) de ta normale\(good ? " : plutôt bon signe." : ", rien d'inquiétant seul.")" }
        return good ? "\(strength) \(direction) de ta normale : bon signe." : "\(strength) \(direction) de ta normale : à surveiller."
    }

    var color: Color {
        switch status {
        case .normal: Theme.good
        case .unknown: .secondary
        case .higher, .lower: concerning ? Theme.alert : Theme.caution
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
                    .overlay(Circle().stroke(Theme.card, lineWidth: 2))
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
    var higherIsBetter: Bool?

    var body: some View {
        // Un chiffre, une pastille de statut, UNE visualisation (la courbe des 14 derniers jours).
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                IconBadge(symbol: symbol, tint: Theme.accent, size: 22)
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.system(.title2, design: .rounded).weight(.heavy)).monospacedDigit()
                    .lineLimit(1)
                if !unit.isEmpty { Text(unit).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            }
            if trend.count >= 2 {
                Sparkline(values: trend, color: tint).frame(height: 20)
            } else {
                Text(reading.latest == nil ? "Synchronise ta montre" : "La courbe apparaît après 2 mesures")
                    .font(.caption2).foregroundStyle(.secondary).frame(height: 20, alignment: .leading)
            }
            StatusPill(text: reading.label(higherIsBetter: higherIsBetter), symbol: reading.status.symbol, color: reading.color)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .tile()
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

// MARK: - Ligne de navigation

/// Ligne « liste iOS » dans une carte : pastille, titre, détail, compteur éventuel, chevron.
struct LinkRow: View {
    let symbol: String
    let title: String
    var subtitle: String = ""
    var badge: String?
    var badgeColor: Color = Theme.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.well, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            if let badge {
                Text(badge)
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor, in: .capsule)
            }
            DetailChevron()
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}

// MARK: - Annuler

/// Bandeau « Annuler » après une saisie rapide (eau, série supprimée…).
struct UndoToast: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
            Text(message).font(.subheadline.weight(.medium)).lineLimit(2)
            Spacer(minLength: 8)
            Button("Annuler", action: onUndo)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .card(cornerRadius: 22)
    }
}
