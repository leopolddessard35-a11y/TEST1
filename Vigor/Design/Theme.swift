import SwiftUI

extension Color {
    /// Couleur hexadécimale (« 656D4A »).
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    /// Couleur qui change en mode sombre.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Couleur claire / sombre d'une palette.
struct ColorPair {
    let light: UInt32
    let dark: UInt32

    init(_ light: UInt32, _ dark: UInt32) {
        self.light = light
        self.dark = dark
    }

    var color: Color { Color(light: light, dark: dark) }
}

/// Palettes au choix (Réglages → Apparence). La couleur sert d'abord au STATUT :
/// « bien » = OK, « à surveiller », « alerte » ; l'accent sert aux boutons et à l'onglet actif.
enum ThemePalette: String, CaseIterable, Identifiable {
    case earth, simple, ocean, plum

    static let storageKey = "vigor.palette"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .earth: "Terre et forêt"
        case .simple: "Simple"
        case .ocean: "Océan"
        case .plum: "Prune"
        }
    }

    /// Palette en cours (lue à chaque construction des vues ; l'app se redessine quand elle change).
    static var current: ThemePalette {
        UserDefaults.standard.string(forKey: storageKey).flatMap(ThemePalette.init(rawValue:)) ?? .earth
    }

    struct Colors {
        let good, caution, alert, accent: ColorPair
        let background, card, well: ColorPair
        let strain, sleep, nutrition: ColorPair
        /// Début clair des dégradés d'anneaux.
        let recoveryLight, strainLight, sleepLight, nutritionLight: ColorPair
        /// Halos colorés du haut de l'écran.
        let halos: [UInt32]
        /// Grain « papier » (palette Terre seulement).
        let grain: Bool
        /// Stades de sommeil : profond, léger, paradoxal, éveil.
        let deep, core, rem, awake: ColorPair
    }

    var colors: Colors {
        switch self {
        case .earth:
            // 582F0E · 7F4F24 · 936639 · A68A64 · B6AD90 · C2C5AA · A4AC86 · 656D4A · 414833 · 333D29
            Colors(good: ColorPair(0x656D4A, 0xA4AC86), caution: ColorPair(0x936639, 0xE0A85C),
                   alert: ColorPair(0x9C4221, 0xD0805A), accent: ColorPair(0x7F4F24, 0xA68A64),
                   background: ColorPair(0xF3F1EA, 0x1A1E15), card: ColorPair(0xFCFBF7, 0x262C1F), well: ColorPair(0xE9E6DB, 0x333D29),
                   strain: ColorPair(0x582F0E, 0xD8CDB0), sleep: ColorPair(0x414833, 0xC2C5AA), nutrition: ColorPair(0xA68A64, 0xB6AD90),
                   recoveryLight: ColorPair(0xA4AC86, 0x656D4A), strainLight: ColorPair(0xA68A64, 0x936639),
                   sleepLight: ColorPair(0xA4AC86, 0x656D4A), nutritionLight: ColorPair(0xC2C5AA, 0x936639),
                   halos: [0xA68A64, 0xA4AC86, 0x656D4A], grain: true,
                   deep: ColorPair(0x333D29, 0x656D4A), core: ColorPair(0xA4AC86, 0xA4AC86),
                   rem: ColorPair(0x7F4F24, 0xA68A64), awake: ColorPair(0xD8CDB0, 0xE0A85C))
        case .simple:
            // Blanc pur / noir profond, couleurs vives seulement pour les statuts (façon apps d'habitudes).
            Colors(good: ColorPair(0x16A34A, 0x30D158), caution: ColorPair(0xD97706, 0xFFB340),
                   alert: ColorPair(0xDC2626, 0xFF6961), accent: ColorPair(0xEA580C, 0xFF8A3D),
                   background: ColorPair(0xF5F5F3, 0x000000), card: ColorPair(0xFFFFFF, 0x161616), well: ColorPair(0xECECEA, 0x262626),
                   strain: ColorPair(0xEA580C, 0xFF9F5A), sleep: ColorPair(0x5B5BD6, 0x9B9BF5), nutrition: ColorPair(0x0891B2, 0x38BDF8),
                   recoveryLight: ColorPair(0x86EFAC, 0x166534), strainLight: ColorPair(0xFDBA74, 0x9A3412),
                   sleepLight: ColorPair(0xC7C7F5, 0x3730A3), nutritionLight: ColorPair(0xA5F3FC, 0x155E75),
                   halos: [0xFB923C, 0x8B5CF6, 0x38BDF8], grain: false,
                   deep: ColorPair(0x3730A3, 0x6366F1), core: ColorPair(0x818CF8, 0xA5B4FC),
                   rem: ColorPair(0x06B6D4, 0x67E8F9), awake: ColorPair(0xFDBA74, 0xFDBA74))
        case .ocean:
            Colors(good: ColorPair(0x0F766E, 0x2DD4BF), caution: ColorPair(0xB45309, 0xFBBF24),
                   alert: ColorPair(0xB91C1C, 0xF87171), accent: ColorPair(0x1D4ED8, 0x60A5FA),
                   background: ColorPair(0xF1F5F9, 0x0B1220), card: ColorPair(0xFFFFFF, 0x131C2E), well: ColorPair(0xE2E8F0, 0x1E293B),
                   strain: ColorPair(0x1E3A8A, 0x93C5FD), sleep: ColorPair(0x4338CA, 0xA5B4FC), nutrition: ColorPair(0x0E7490, 0x67E8F9),
                   recoveryLight: ColorPair(0x99F6E4, 0x115E59), strainLight: ColorPair(0x93C5FD, 0x1E40AF),
                   sleepLight: ColorPair(0xC7D2FE, 0x3730A3), nutritionLight: ColorPair(0xA5F3FC, 0x155E75),
                   halos: [0x60A5FA, 0x2DD4BF, 0x1D4ED8], grain: false,
                   deep: ColorPair(0x1E3A8A, 0x3B82F6), core: ColorPair(0x60A5FA, 0x93C5FD),
                   rem: ColorPair(0x14B8A6, 0x5EEAD4), awake: ColorPair(0xFCD34D, 0xFCD34D))
        case .plum:
            Colors(good: ColorPair(0x15803D, 0x4ADE80), caution: ColorPair(0xC2410C, 0xFDBA74),
                   alert: ColorPair(0xBE123C, 0xFB7185), accent: ColorPair(0x7C3AED, 0xA78BFA),
                   background: ColorPair(0xF7F5FB, 0x120F1A), card: ColorPair(0xFFFFFF, 0x1C1828), well: ColorPair(0xEDE9F6, 0x2A2438),
                   strain: ColorPair(0x6D28D9, 0xC4B5FD), sleep: ColorPair(0x4F46E5, 0xA5B4FC), nutrition: ColorPair(0xDB2777, 0xF9A8D4),
                   recoveryLight: ColorPair(0xBBF7D0, 0x166534), strainLight: ColorPair(0xDDD6FE, 0x5B21B6),
                   sleepLight: ColorPair(0xC7D2FE, 0x3730A3), nutritionLight: ColorPair(0xFBCFE8, 0x9D174D),
                   halos: [0xA78BFA, 0xF472B6, 0x7C3AED], grain: false,
                   deep: ColorPair(0x4C1D95, 0x7C3AED), core: ColorPair(0xA78BFA, 0xC4B5FD),
                   rem: ColorPair(0xF472B6, 0xF9A8D4), awake: ColorPair(0xFDE68A, 0xFDE68A))
        }
    }

    /// Quatre pastilles pour l'aperçu dans les réglages.
    var swatches: [ColorPair] { [colors.accent, colors.good, colors.sleep, colors.background] }
}

/// Couleurs de l'app, selon la palette choisie.
enum Theme {
    private static var palette: ThemePalette.Colors { ThemePalette.current.colors }

    // Rôles fonctionnels. La couleur sert d'abord au STATUT : OK, à surveiller, alerte.
    /// OK / récupéré / dans la norme.
    static var good: Color { palette.good.color }
    /// À surveiller.
    static var caution: Color { palette.caution.color }
    /// Alerte.
    static var alert: Color { palette.alert.color }
    /// Couleur de marque : boutons, onglet actif, pastilles d'icône.
    static var accent: Color { palette.accent.color }

    // Surfaces.
    static var background: Color { palette.background.color }
    static var card: Color { palette.card.color }
    static var well: Color { palette.well.color }

    // Familles de mesures (anneaux, graphiques).
    static var recovery: Color { good }
    /// Effort : teinte à part, pour ne pas ressembler à un « à surveiller ».
    static var strain: Color { palette.strain.color }
    static var sleep: Color { palette.sleep.color }
    static var nutrition: Color { palette.nutrition.color }
    static var warning: Color { alert }

    /// Dégradés des anneaux (clair → profond).
    static var recoveryGradient: [Color] { [palette.recoveryLight.color, good] }
    static var strainGradient: [Color] { [palette.strainLight.color, strain] }
    static var sleepGradient: [Color] { [palette.sleepLight.color, sleep] }
    static var nutritionGradient: [Color] { [palette.nutritionLight.color, nutrition] }

    /// Stades de sommeil.
    static var sleepDeep: Color { palette.deep.color }
    static var sleepCore: Color { palette.core.color }
    static var sleepREM: Color { palette.rem.color }
    static var sleepAwake: Color { palette.awake.color }

    /// Halos du fond et grain papier.
    static var halos: [Color] { palette.halos.map { Color(hex: $0) } }
    static var hasGrain: Bool { palette.grain }

    static let cardRadius: CGFloat = 22

    static func color(for level: ReadinessLevel) -> Color {
        switch level {
        case .ready: good
        case .moderate: caution
        case .low: alert
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
        let halos = Theme.halos
        ZStack {
            Theme.background
            // Halo coloré en haut de l'écran, qui s'efface vers le milieu.
            if halos.count >= 3 {
                ZStack {
                    Circle().fill(halos[0].opacity(dark ? 0.20 : 0.22)).frame(width: 340).blur(radius: 110).offset(x: -150, y: -330)
                    Circle().fill(halos[1].opacity(dark ? 0.18 : 0.24)).frame(width: 320).blur(radius: 120).offset(x: 160, y: -280)
                    Circle().fill(halos[2].opacity(dark ? 0.14 : 0.08)).frame(width: 300).blur(radius: 130).offset(x: 40, y: -120)
                }
            }
            LinearGradient(colors: [.clear, Theme.background.opacity(0.0), Theme.background],
                           startPoint: .top, endPoint: .center)
            if Theme.hasGrain {
                PaperGrain(opacity: dark ? 0.05 : 0.035)
            }
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
                    shape.fill(Theme.card)
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

    /// Tuile de grille harmonisée : même marge, même arrondi, même hauteur partout dans l'app.
    func tile(height: CGFloat = Theme.tileHeight) -> some View {
        padding(Theme.tilePadding)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
            .card(cornerRadius: Theme.tileRadius)
    }
}

extension Theme {
    /// Tuiles « widget » (2 par ligne) : moniteur, raccourcis, indicateurs.
    static let tileHeight: CGFloat = 144
    /// Petites tuiles de chiffres dans les pages de détail.
    static let compactTileHeight: CGFloat = 92
    static let tileRadius: CGFloat = 22
    static let tilePadding: CGFloat = 16
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
    var tint: Color = Theme.accent

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
    /// Affichage uniquement (séparateur décimal de la langue : « 72,5 » en français). Ne jamais relire comme un nombre.
    var oneDecimal: String { formatted(.number.precision(.fractionLength(1)).grouping(.never)) }
    var noDecimal: String { formatted(.number.precision(.fractionLength(0)).grouping(.never)) }

    /// `digits` décimales, séparateur de la langue ; `signed` affiche toujours le signe (« +0,42 »).
    func decimals(_ digits: Int, signed: Bool = false) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(digits)).grouping(.never)
        return signed ? formatted(style.sign(strategy: .always(includingZero: false))) : formatted(style)
    }

    /// 1,75 h → « 1 h 45 »
    var hoursText: String {
        let totalMinutes = Int((self * 60).rounded())
        let hours = totalMinutes / 60, minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        return minutes == 0 ? "\(hours) h" : String(format: "%d h %02d", locale: Locale.current, hours, minutes)
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
                Text(caption).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .tile()
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
            VStack(spacing: 12) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
