import Foundation

struct HevySet: Equatable {
    let exercise: String
    let exerciseNotes: String
    let setIndex: Int
    let setType: String
    let weightKg: Double?
    let reps: Int?
    let distanceKm: Double?
    let durationSeconds: Double?
    let rpe: Double?
    let supersetID: Int?
}

struct HevyWorkout: Equatable {
    let externalID: String
    let title: String
    let start: Date
    let end: Date?
    let description: String
    var sets: [HevySet]
}

/// Lit l'export CSV de Hevy (Réglages → Exporter les données → Exporter les séances).
/// Toutes les colonnes sont conservées : exercice, notes, type de série, charge, reps, distance, durée, RPE, superset.
enum HevyImporter {
    enum ImportError: LocalizedError {
        case missingColumns([String])
        case empty

        var errorDescription: String? {
            switch self {
            case .missingColumns(let columns): "Ce fichier ne ressemble pas à un export Hevy (colonnes manquantes : \(columns.joined(separator: ", ")))."
            case .empty: "Le fichier est vide."
            }
        }
    }

    static func parse(_ text: String) throws -> [HevyWorkout] {
        let rows = CSVParser.parse(text)
        guard let header = rows.first else { throw ImportError.empty }
        let columns = Dictionary(header.enumerated().map { ($1.trimmingCharacters(in: .whitespaces).lowercased(), $0) },
                                 uniquingKeysWith: { first, _ in first })

        let required = ["title", "start_time", "exercise_title"]
        let missing = required.filter { columns[$0] == nil }
        guard missing.isEmpty else { throw ImportError.missingColumns(missing) }

        var order: [String] = []
        var workouts: [String: HevyWorkout] = [:]

        for row in rows.dropFirst() {
            func value(_ key: String) -> String {
                guard let index = columns[key], index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }

            let title = value("title")
            let startRaw = value("start_time")
            guard !startRaw.isEmpty, let start = parseDate(startRaw) else { continue }
            let id = "hevy|\(title)|\(startRaw)"

            if workouts[id] == nil {
                order.append(id)
                workouts[id] = HevyWorkout(externalID: id, title: title, start: start,
                                           end: parseDate(value("end_time")), description: value("description"), sets: [])
            }

            let exercise = value("exercise_title")
            guard !exercise.isEmpty else { continue }

            let weight = number(value("weight_kg")) ?? number(value("weight_lbs")).map { $0 * 0.45359237 }
            let distance = number(value("distance_km")) ?? number(value("distance_miles")).map { $0 * 1.609344 }
            let set = HevySet(
                exercise: exercise,
                exerciseNotes: value("exercise_notes"),
                setIndex: number(value("set_index")).map { Int($0) } ?? 0,
                setType: value("set_type").isEmpty ? "normal" : value("set_type").lowercased(),
                weightKg: weight,
                reps: number(value("reps")).map { Int($0) },
                distanceKm: distance,
                durationSeconds: number(value("duration_seconds")),
                rpe: number(value("rpe")),
                supersetID: number(value("superset_id")).map { Int($0) })
            workouts[id]?.sets.append(set)
        }
        return order.compactMap { workouts[$0] }
    }

    /// Parsing strict : vide, « -- », « – » ou « N/A » = valeur manquante (jamais 0) ;
    /// virgule décimale acceptée ; « 1:23:45 » ou « 23:45 » convertis en secondes.
    static func number(_ raw: String) -> Double? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !["--", "-", "–", "—", "n/a", "na", "null"].contains(text.lowercased()) else { return nil }
        if text.contains(":") {
            let parts = text.split(separator: ":").compactMap { Double($0.replacingOccurrences(of: ",", with: ".")) }
            guard parts.count >= 2, parts.count <= 3 else { return nil }
            return parts.reduce(0) { $0 * 60 + $1 }
        }
        return Double(text.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: ""))
    }

    private static let formatters: [DateFormatter] = {
        let patterns: [(String, String)] = [
            ("d MMM yyyy, HH:mm", "en_US_POSIX"),
            ("d MMM yyyy HH:mm", "en_US_POSIX"),
            ("d MMM yyyy, HH:mm", "fr_FR"),
            ("yyyy-MM-dd HH:mm:ss", "en_US_POSIX"),
            ("yyyy-MM-dd HH:mm", "en_US_POSIX"),
            ("dd/MM/yyyy HH:mm", "en_US_POSIX"),
        ]
        return patterns.map { pattern, locale in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: locale)
            formatter.timeZone = .current
            formatter.dateFormat = pattern
            return formatter
        }
    }()

    static func parseDate(_ raw: String) -> Date? {
        guard !raw.isEmpty else { return nil }
        for formatter in formatters {
            if let date = formatter.date(from: raw) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}
