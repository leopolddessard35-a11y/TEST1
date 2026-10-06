import SwiftUI

/// Nombre qui « compte » jusqu'à sa valeur pendant l'animation.
struct CountingText: View, Animatable {
    var value: Double
    var suffix: String = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))\(suffix)")
            .monospacedDigit()
    }
}

/// Jauge d'énergie en demi-cercle : se remplit et l'aiguille monte à l'ouverture.
struct EnergyGauge: View {
    /// 0…1,1 (capacité du jour)
    let value: Double
    let color: Color
    var label: String = "Énergie"
    @State private var progress: Double = 0
    @State private var glow = false

    var body: some View {
        let clamped = min(max(value, 0), 1.1) / 1.1
        VStack(spacing: 2) {
            ZStack {
                Arc(progress: 1)
                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                Arc(progress: progress)
                    .stroke(AngularGradient(colors: [Theme.warning, Theme.nutrition, Theme.recovery, Theme.recovery],
                                            center: .bottom, startAngle: .degrees(180), endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: 16, lineCap: .round))
                    .shadow(color: color.opacity(glow ? 0.7 : 0.25), radius: glow ? 14 : 6)
                Needle(progress: progress)
                    .stroke(Color.primary, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Hub().fill(Color.primary)
            }
            .frame(height: 110)
            CountingText(value: progress * 110, suffix: " %")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            withAnimation(.spring(response: 1.3, dampingFraction: 0.75).delay(0.15)) { progress = clamped }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(1.2)) { glow = true }
        }
        .onChange(of: value) {
            withAnimation(.spring(response: 1, dampingFraction: 0.8)) { progress = min(max(value, 0), 1.1) / 1.1 }
        }
    }

    private static func geometry(_ rect: CGRect) -> (center: CGPoint, radius: CGFloat) {
        (CGPoint(x: rect.midX, y: rect.maxY - 8), min(rect.width / 2, rect.height) - 10)
    }

    /// Aiguille, de 0 (gauche) à 1 (droite).
    private struct Needle: Shape {
        var progress: Double

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let (center, radius) = EnergyGauge.geometry(rect)
            let angle = Angle.degrees(180 + 180 * progress).radians
            var path = Path()
            path.move(to: center)
            path.addLine(to: CGPoint(x: center.x + cos(angle) * radius * 0.72, y: center.y + sin(angle) * radius * 0.72))
            return path
        }
    }

    private struct Hub: Shape {
        func path(in rect: CGRect) -> Path {
            let (center, _) = EnergyGauge.geometry(rect)
            return Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12))
        }
    }

    /// Demi-cercle ouvert vers le bas.
    private struct Arc: Shape {
        var progress: Double

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func path(in rect: CGRect) -> Path {
            let (center, radius) = EnergyGauge.geometry(rect)
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(180),
                        endAngle: .degrees(180 + 180 * progress), clockwise: false)
            return path
        }
    }
}

/// Barre qui se remplit avec un ressort.
struct AnimatedBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 8
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(LinearGradient(colors: [color.opacity(0.7), color], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, proxy.size.width * min(max(shown, 0), 1)))
                    .opacity(shown > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.8).delay(0.1)) { shown = fraction }
        }
        .onChange(of: fraction) {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { shown = fraction }
        }
    }
}

extension View {
    /// Les cartes apparaissent et s'estompent doucement au défilement.
    func scrollAppear() -> some View {
        scrollTransition(.animated(.smooth)) { content, phase in
            content
                .opacity(phase.isIdentity ? 1 : 0.4)
                .scaleEffect(phase.isIdentity ? 1 : 0.95)
                .blur(radius: phase.isIdentity ? 0 : 2)
        }
    }
}
