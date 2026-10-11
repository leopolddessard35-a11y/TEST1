import SwiftUI
import SwiftData

/// « Données reçues de Garmin » : ce qu'Intervals.icu envoie vraiment à Vigor (14 derniers jours), mesure par mesure.
/// Sert à comprendre une tuile vide : la donnée n'arrive pas d'Intervals, ou elle arrive mais n'est pas utilisée.
struct GarminDataCheckView: View {
    @Environment(AppModel.self) private var app
    @Query private var profiles: [AthleteProfile]
    @State private var rows: [Row] = []
    @State private var loading = false
    @State private var error: String?
    @State private var otherKeys: [String] = []

    private struct Row: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let latest: Double?
        let date: String?
        let days: Int
    }

    /// Champs de bien-être lus par Vigor.
    private static let fields: [(key: String, label: String)] = [
        ("hrv", "VFC (rMSSD)"), ("restingHR", "FC au repos"), ("sleepSecs", "Sommeil"), ("sleepScore", "Score de sommeil"),
        ("respiration", "Respiration"), ("spO2", "SpO2"), ("avgSleepingHR", "FC pendant le sommeil"),
        ("weight", "Poids"), ("bodyFat", "Masse grasse"), ("vo2max", "VO2max"), ("readiness", "Récupération Garmin"),
        ("steps", "Pas")
    ]

    var body: some View {
        List {
            Section {
                if loading {
                    HStack { ProgressView(); Text("Lecture d'Intervals.icu…") }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Theme.alert)
                }
                ForEach(rows) { row in
                    HStack {
                        Image(systemName: row.latest == nil ? "xmark.circle" : "checkmark.circle.fill")
                            .foregroundStyle(row.latest == nil ? Color.secondary : Theme.good)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.label).font(.subheadline.weight(.medium))
                            Text(row.latest == nil ? "Rien reçu sur 14 jours" : "\(row.days) jour\(row.days > 1 ? "s" : "") sur 14 · dernier le \(row.date ?? "?")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let value = row.latest {
                            Text(format(row.key, value)).font(.subheadline.monospacedDigit())
                        }
                    }
                }
            } header: {
                Text("Reçu d'Intervals.icu · 14 derniers jours")
            } footer: {
                Text("""
                Une mesure « Rien reçu » n'arrive pas de Garmin jusqu'à Intervals.icu : Vigor ne peut pas l'afficher.
                Sur intervals.icu → Settings → Connections → Garmin : vérifie que l'import des données de bien-être (« wellness ») est activé, avec les mesures voulues (poids, respiration, SpO2…). Puis, dans Garmin Connect, vérifie que la mesure existe (poids saisi ou balance Index, respiration et oxymètre activés sur la montre).
                Une fois reçue, tire l'accueil vers le bas : Vigor l'utilise en priorité sur Apple Santé.
                """)
            }
            if !otherKeys.isEmpty {
                Section {
                    Text(otherKeys.joined(separator: ", ")).font(.caption.monospaced()).foregroundStyle(.secondary)
                } header: {
                    Text("Autres données envoyées")
                } footer: {
                    Text("Champs présents chez Intervals.icu mais pas encore utilisés par Vigor.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground())
        .navigationTitle("Données reçues de Garmin")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    private func format(_ key: String, _ value: Double) -> String {
        switch key {
        case "sleepSecs": (value / 3600).hoursText
        case "weight", "respiration", "bodyFat", "vo2max": value.oneDecimal
        default: value.noDecimal
        }
    }

    private func load() async {
        let key = app.intervalsAPIKey
        guard !key.isEmpty else {
            error = "Ajoute d'abord ta clé Intervals.icu (Réglages → Connexions)."
            return
        }
        loading = true
        error = nil
        defer { loading = false }
        let client = IntervalsClient(apiKey: key, athleteID: profiles.first?.intervalsAthleteID ?? "0")
        let today = Calendar.current.startOfDay(for: .now)
        let oldest = Calendar.current.date(byAdding: .day, value: -13, to: today) ?? today
        do {
            let records = try await client.wellnessRaw(oldest: oldest, newest: today)
                .sorted { ($0["id"] as? String ?? "") < ($1["id"] as? String ?? "") }
            rows = Self.fields.map { field in
                let values: [(day: String, value: Double)] = records.compactMap { record in
                    guard let value = Self.number(record[field.key]) else { return nil }
                    return (record["id"] as? String ?? "?", value)
                }
                return Row(key: field.key, label: field.label, latest: values.last?.value,
                           date: values.last.map { Self.shortDate($0.day) }, days: values.count)
            }
            let known = Set(Self.fields.map(\.key) + ["id", "ctl", "atl", "rampRate", "ctlLoad", "atlLoad", "updated", "hrvSDNN"])
            var extra = Set<String>()
            for record in records {
                for (name, value) in record where !known.contains(name) && Self.number(value) != nil { extra.insert(name) }
            }
            otherKeys = extra.sorted()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let text as String: Double(text.replacingOccurrences(of: ",", with: "."))
        default: nil
        }
    }

    /// « 2026-10-11 » → « 11/10 ».
    private static func shortDate(_ id: String) -> String {
        let parts = id.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return id }
        return "\(parts[2])/\(parts[1])"
    }
}
