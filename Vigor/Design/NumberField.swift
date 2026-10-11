import SwiftUI

/// Champ numérique qui met à jour la valeur À CHAQUE frappe (contrairement à `TextField(value:format:)`,
/// qui n'écrit qu'à la perte du focus). Accepte la virgule et le point. Une valeur modifiée de l'extérieur
/// (boutons ±) est reflétée dans le texte.
struct DecimalField: View {
    let title: String
    @Binding var value: Double?
    var keyboard: UIKeyboardType = .decimalPad
    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ title: String, value: Binding<Double?>, keyboard: UIKeyboardType = .decimalPad) {
        self.title = title
        self._value = value
        self.keyboard = keyboard
    }

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(keyboard)
            .focused($focused)
            .onAppear { text = Self.format(value) }
            .onChange(of: text) { _, newText in
                let parsed = Self.parse(newText)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, newValue in
                // Mise à jour externe (±, reprise d'un brouillon) : on ne réécrit pas pendant la frappe d'un nombre équivalent.
                if Self.parse(text) != newValue { text = Self.format(newValue) }
            }
    }

    static func parse(_ text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    static func format(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }
}

/// Variante pour un nombre non optionnel (0 = vide).
struct DecimalFieldNonOptional: View {
    let title: String
    @Binding var value: Double
    var keyboard: UIKeyboardType = .decimalPad

    init(_ title: String, value: Binding<Double>, keyboard: UIKeyboardType = .decimalPad) {
        self.title = title
        self._value = value
        self.keyboard = keyboard
    }

    var body: some View {
        DecimalField(title, value: Binding(
            get: { value == 0 ? nil : value },
            set: { value = $0 ?? 0 }), keyboard: keyboard)
    }
}

/// Variante entière (répétitions…).
struct IntegerField: View {
    let title: String
    @Binding var value: Int?

    init(_ title: String, value: Binding<Int?>) {
        self.title = title
        self._value = value
    }

    var body: some View {
        DecimalField(title, value: Binding(
            get: { value.map(Double.init) },
            set: { value = $0.map { Int($0.rounded()) } }), keyboard: .numberPad)
    }
}
