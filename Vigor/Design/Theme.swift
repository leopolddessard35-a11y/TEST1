import SwiftUI

enum Theme {
    static let recovery = Color(red: 0.30, green: 0.89, blue: 0.78)
    static let strain = Color(red: 1.00, green: 0.56, blue: 0.30)
    static let sleep = Color(red: 0.55, green: 0.55, blue: 1.00)
    static let nutrition = Color(red: 0.98, green: 0.80, blue: 0.30)
    static let warning = Color(red: 1.00, green: 0.38, blue: 0.40)

    static func color(for level: ReadinessLevel) -> Color {
        switch level {
        case .ready: recovery
        case .moderate: nutrition
        case .low: warning
        }
    }
}

/// Fond dégradé qui suit le mode clair / sombre de l'iPhone : le verre Liquid Glass réfracte ces couleurs.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            LinearGradient(
                colors: dark
                    ? [Color(red: 0.04, green: 0.05, blue: 0.10), Color(red: 0.02, green: 0.10, blue: 0.14)]
                    : [Color(red: 0.95, green: 0.97, blue: 0.99), Color(red: 0.90, green: 0.95, blue: 0.96)],
                startPoint: .top, endPoint: .bottom)
            Circle().fill(Theme.recovery.opacity(dark ? 0.35 : 0.30)).frame(width: 320).blur(radius: 120).offset(x: -140, y: -300)
            Circle().fill(Theme.sleep.opacity(dark ? 0.30 : 0.25)).frame(width: 300).blur(radius: 120).offset(x: 160, y: 40)
            Circle().fill(Theme.strain.opacity(dark ? 0.22 : 0.18)).frame(width: 260).blur(radius: 120).offset(x: -100, y: 380)
        }
        .ignoresSafeArea()
    }
}

/// Carte en verre (Liquid Glass d'iOS 26+).
struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
            .scrollAppear()
    }
}

/// Petit chevron indiquant qu'une carte s'ouvre en détail.
struct DetailChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
    }
}

struct SectionTitle: View {
    let title: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { Image(systemName: symbol) }
            Text(title)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

/// Anneau de score façon Bevel : se remplit et compte jusqu'à la valeur.
struct ScoreRing: View {
    let value: Double
    let color: Color
    var lineWidth: CGFloat = 14
    var label: String
    @State private var shown: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, shown / 100)))
                .stroke(AngularGradient(colors: [color.opacity(0.5), color], center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: color.opacity(0.45), radius: 8)
            VStack(spacing: 2) {
                CountingText(value: shown).font(.system(size: 40, weight: .bold, design: .rounded))
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 1.2, dampingFraction: 0.8).delay(0.1)) { shown = value }
        }
        .onChange(of: value) {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8)) { shown = value }
        }
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    var unit: String = ""
    let symbol: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.title2.weight(.semibold).monospacedDigit())
                if !unit.isEmpty { Text(unit).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

struct EmptyStateCard: View {
    let title: String
    let message: String
    let symbol: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

extension Double {
    var oneDecimal: String { String(format: "%.1f", self) }
    var noDecimal: String { String(format: "%.0f", self) }

    /// 1,75 h → « 1 h 45 »
    var hoursText: String {
        let totalMinutes = Int((self * 60).rounded())
        let hours = totalMinutes / 60, minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : String(format: "%d h %02d", hours, minutes)
    }
}
