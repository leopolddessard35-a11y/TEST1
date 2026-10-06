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

/// Fond uni gris très clair (blanc cassé) en mode clair, noir en mode sombre : les cartes blanches ressortent.
struct AppBackground: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
    }
}

/// Surface de carte : blanc arrondi + ombre douce (gris foncé en mode sombre).
struct CardBackground: ViewModifier {
    var cornerRadius: CGFloat = Theme.cardRadius
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0 : 0.06), radius: 14, y: 4)
    }
}

extension View {
    func card(cornerRadius: CGFloat = Theme.cardRadius) -> some View {
        modifier(CardBackground(cornerRadius: cornerRadius))
    }
}

/// Carte standard (nom historique conservé : plus de verre, une carte blanche façon Bevel).
struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
            .scrollAppear()
    }
}

/// Titre de section en dehors des cartes (« Moniteur de santé », « Activité »…).
struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
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
                CountingText(value: shown).font(.system(.largeTitle, design: .rounded).weight(.bold))
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
        .card(cornerRadius: 22)
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
        .card(cornerRadius: 22)
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
