import SwiftUI

enum Theme {
    // Palette inspirée de Bevel : couleurs franches, lisibles sur fond clair comme sombre.
    static let recovery = Color(red: 0.20, green: 0.78, blue: 0.47)
    static let strain = Color(red: 1.00, green: 0.52, blue: 0.22)
    static let sleep = Color(red: 0.42, green: 0.45, blue: 0.98)
    static let nutrition = Color(red: 0.98, green: 0.72, blue: 0.18)
    static let warning = Color(red: 0.96, green: 0.30, blue: 0.33)

    /// Dégradés des anneaux (clair → saturé), comme les cadrans de Bevel.
    static let recoveryGradient = [Color(red: 0.62, green: 0.93, blue: 0.55), recovery]
    static let strainGradient = [Color(red: 1.00, green: 0.80, blue: 0.36), strain]
    static let sleepGradient = [Color(red: 0.62, green: 0.80, blue: 1.00), sleep]
    static let nutritionGradient = [Color(red: 1.00, green: 0.88, blue: 0.45), nutrition]

    static let cardRadius: CGFloat = 26

    static func color(for level: ReadinessLevel) -> Color {
        switch level {
        case .ready: recovery
        case .moderate: nutrition
        case .low: warning
        }
    }
}

/// Apparence choisie dans les réglages : clair par défaut.
enum Appearance: String, CaseIterable, Identifiable {
    case light, dark, system

    static let storageKey = "vigor.appearance"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .light: "Clair"
        case .dark: "Sombre"
        case .system: "Auto"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

/// Petit libellé en capitales espacées (façon Whoop) : « RÉCUPÉRATION », « COACHING »…
struct CapsLabel: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

/// Pastille de statut (façon Ultrahuman) : texte coloré sur fond teinté.
struct StatusPill: View {
    let text: String
    var symbol: String?
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(color.opacity(0.13), in: .capsule)
    }
}

/// Courbe miniature (14 derniers points), trait dégradé et aire estompée.
struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let points = Self.points(values, in: proxy.size)
            if points.count >= 2 {
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x, y: proxy.size.height))
                        for point in points { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: points[points.count - 1].x, y: proxy.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: points[0])
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(LinearGradient(colors: [color.opacity(0.45), color], startPoint: .leading, endPoint: .trailing),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    Circle().fill(color).frame(width: 5, height: 5).position(points[points.count - 1])
                }
            }
        }
    }

    static func points(_ values: [Double], in size: CGSize) -> [CGPoint] {
        guard values.count >= 2, let low = values.min(), let high = values.max() else { return [] }
        let range = max(high - low, 0.0001)
        let step = size.width / CGFloat(values.count - 1)
        var result: [CGPoint] = []
        for (index, value) in values.enumerated() {
            let y = size.height - 3 - CGFloat((value - low) / range) * (size.height - 6)
            result.append(CGPoint(x: CGFloat(index) * step, y: y))
        }
        return result
    }
}

/// Fond clair avec un voile de couleur pastel en haut et un grain très fin : du relief sans perdre la propreté.
struct AppBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            Color(uiColor: .systemGroupedBackground)
            // Halo coloré en haut de l'écran, qui s'efface vers le milieu.
            ZStack {
                Circle().fill(Theme.strain.opacity(dark ? 0.22 : 0.16)).frame(width: 340).blur(radius: 110).offset(x: -150, y: -330)
                Circle().fill(Theme.sleep.opacity(dark ? 0.24 : 0.14)).frame(width: 320).blur(radius: 120).offset(x: 160, y: -280)
                Circle().fill(Theme.recovery.opacity(dark ? 0.16 : 0.10)).frame(width: 300).blur(radius: 130).offset(x: 40, y: -120)
            }
            LinearGradient(colors: [.clear, Color(uiColor: .systemGroupedBackground).opacity(0.0), Color(uiColor: .systemGroupedBackground)],
                           startPoint: .top, endPoint: .center)
            PaperGrain(opacity: dark ? 0.05 : 0.035)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Grain très fin (façon papier), dessiné une seule fois avec un tirage pseudo-aléatoire fixe.
struct PaperGrain: View {
    var opacity: Double

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            let count = Int(size.width * size.height / 90)
            for _ in 0..<count {
                let x = next() * size.width, y = next() * size.height
                let light = next() > 0.5
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)),
                             with: .color(light ? .white : .black))
            }
        }
        .opacity(opacity)
        .drawingGroup()
    }
}

/// Surface de carte : blanc légèrement bombé (dégradé), liseré lumineux, ombre douce en deux couches,
/// et en option un voile de couleur dans le coin supérieur.
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.cardRadius
    var tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let dark = colorScheme == .dark
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(Color(uiColor: .secondarySystemGroupedBackground))
                    shape.fill(LinearGradient(colors: [.white.opacity(dark ? 0.05 : 0.6), .clear],
                                              startPoint: .top, endPoint: .bottom))
                    if let tint {
                        shape.fill(RadialGradient(colors: [tint.opacity(dark ? 0.16 : 0.07), .clear],
                                                  center: .topLeading, startRadius: 0, endRadius: 220))
                    }
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.14 : 0.95), Color.black.opacity(dark ? 0.04 : 0.05)],
                                                  startPoint: .top, endPoint: .bottom),
                                   lineWidth: 1)
            }
            .shadow(color: .black.opacity(dark ? 0 : 0.04), radius: 2, y: 1)
            .shadow(color: .black.opacity(dark ? 0 : 0.06), radius: 18, y: 8)
    }
}

extension View {
    func card(cornerRadius: CGFloat = Theme.cardRadius, tint: Color? = nil) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius, tint: tint))
    }
}

/// Carte standard (nom historique conservé : plus de verre, une carte blanche façon Bevel).
struct GlassCard<Content: View>: View {
    private let tint: Color?
    private let content: Content

    init(tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: tint)
            .scrollAppear()
    }
}

/// Pastille d'icône colorée (dégradé), utilisée dans les titres et les tuiles.
struct IconBadge: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.32, style: .continuous))
            .shadow(color: tint.opacity(0.35), radius: 4, y: 2)
    }
}

/// Titre de section en dehors des cartes (« Moniteur de santé », « Activité »…).
struct SectionHeader: View {
    let title: String
    var trailing: String?
    var symbol: String?
    var tint: Color = Theme.strain

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            if let symbol { IconBadge(symbol: symbol, tint: tint, size: 24) }
            Text(title).font(.title3.weight(.bold))
            Spacer()
            if let trailing {
                Text(trailing).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
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
                .stroke(AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                        startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, min(1, shown / 100)))),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                CountingText(value: shown).font(.system(.largeTitle, design: .rounded).weight(.heavy))
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, lineWidth + 8)
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
        .card(cornerRadius: 22, tint: tint == .primary ? nil : tint)
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

/// Tuile simple et cliquable : un chiffre, son contexte, un chevron.
struct SimpleTile: View {
    let title: String
    let value: String
    var caption: String = ""
    let symbol: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: symbol).font(.caption.weight(.medium)).foregroundStyle(tint)
                Spacer()
                DetailChevron()
            }
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            if !caption.isEmpty {
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 22, tint: tint == .primary ? nil : tint)
    }
}

/// Page de détail générique (fond, défilement, titre).
struct DetailPage<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
