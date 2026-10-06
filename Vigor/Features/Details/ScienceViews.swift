import SwiftUI

/// Bloc « Comment c'est calculé / pourquoi » façon Ultrahuman.
struct ExplanationCard: View {
    let title: String
    let symbol: String
    let text: String

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: title, symbol: symbol)
                Text(text).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Justifications des règles (sans les références bibliographiques).
struct ReferencesCard: View {
    let references: [Reference]

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle(title: "Pourquoi ces repères", symbol: "lightbulb.fill")
                ForEach(references) { reference in
                    Text("• \(reference.finding)").font(.footnote).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    var caption: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.semibold).monospacedDigit())
            if !caption.isEmpty { Text(caption).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

/// Sélecteur de période pour les graphiques.
struct RangePicker: View {
    @Binding var days: Int

    var body: some View {
        Picker("Période", selection: $days) {
            Text("30 j").tag(30)
            Text("90 j").tag(90)
            Text("1 an").tag(365)
        }
        .pickerStyle(.segmented)
    }
}
