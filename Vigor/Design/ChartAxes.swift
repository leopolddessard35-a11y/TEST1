import Charts
import SwiftUI

extension View {
    /// Axe des dates lisible même sur le plus petit iPhone : 4 à 5 repères espacés, format court (« 6 oct. »),
    /// les libellés qui se chevauchent sont masqués automatiquement.
    func dateAxis(days: Int) -> some View {
        let step: Int
        switch days {
        case ...16: step = 3
        case ...35: step = 7
        case ...65: step = 14
        case ...130: step = 30
        default: step = 91
        }
        let style: Date.FormatStyle = days > 130 ? .dateTime.month(.abbreviated) : .dateTime.day().month(.abbreviated)
        return chartXAxis {
            AxisMarks(values: .stride(by: .day, count: step)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: style, collisionResolution: .greedy)
                    .font(.caption2)
            }
        }
    }
}
