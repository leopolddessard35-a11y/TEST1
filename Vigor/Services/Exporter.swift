import Foundation
import SwiftData
import UIKit

/// Export complet (CSV + JSON) et PDF du journal de symptômes. Tout reste local jusqu'au partage.
@MainActor
enum Exporter {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static func date(_ value: Date?) -> String { value.map { isoFormatter.string(from: $0) } ?? "" }
    private static func number(_ value: Double?) -> String { value.map { String(format: "%.3f", $0) } ?? "" }
    private static func csvEscape(_ text: String) -> String {
        text.contains(",") || text.contains("\"") || text.contains("\n") ? "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\"" : text
    }

    /// Crée les fichiers d'export dans un dossier temporaire et renvoie leurs URL.
    static func exportAll(context: ModelContext) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Vigor-export-\(Int(Date.now.timeIntervalSince1970))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        var json: [String: Any] = ["exportedAt": date(.now), "formulas": FormulaVersion.all]

        func write(_ name: String, header: [String], rows: [[String]]) throws {
            let lines = [header.joined(separator: ",")] + rows.map { $0.map(csvEscape).joined(separator: ",") }
            let url = folder.appendingPathComponent("\(name).csv")
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            files.append(url)
            json[name] = rows.map { Dictionary(uniqueKeysWithValues: zip(header, $0)) }
        }

        let wellness = try context.fetch(FetchDescriptor<DailyWellness>(sortBy: [SortDescriptor(\.day)]))
        try write("sante_quotidienne",
                  header: ["jour", "sommeil_h", "coucher", "lever", "vfc_sdnn_ms", "vfc_rmssd_ms", "fc_repos", "respiration",
                           "pas", "energie_active_kcal", "poids_kg", "vo2max", "score_sommeil", "readiness_garmin", "eau_ml"],
                  rows: wellness.map { record in
                      [date(record.day), number(record.sleepHours), date(record.bedtime), date(record.wakeTime), number(record.hrvMs),
                       number(record.hrvRMSSD), number(record.restingHeartRate), number(record.respiration), number(record.steps),
                       number(record.activeEnergyKcal), number(record.weightKg), number(record.vo2Max), number(record.sleepScore),
                       number(record.garminReadiness), number(record.waterMl)]
                  })

        let activities = try context.fetch(FetchDescriptor<CardioActivity>(sortBy: [SortDescriptor(\.start)]))
        try write("seances_endurance",
                  header: ["debut", "sport", "titre", "source", "duree_s", "distance_m", "fc_moy", "puissance_moy", "np", "tss_source",
                           "rpe", "z1_s", "z2_s", "z3_s", "z4_s", "z5_s", "derive_pct", "cadence", "denivele_m", "terrain", "chaussures"],
                  rows: activities.map { activity -> [String] in
                      let zones: [String] = activity.zoneSeconds.count == 5 ? activity.zoneSeconds.map { number($0) } : ["", "", "", "", ""]
                      let rpe: String = activity.rpe.map { String($0) } ?? ""
                      var row: [String] = [date(activity.start), activity.sportRaw, activity.title, activity.source,
                                           number(activity.durationSeconds), number(activity.distanceMeters),
                                           number(activity.averageHeartRate), number(activity.averagePower),
                                           number(activity.normalizedPower), number(activity.providedTSS), rpe]
                      row.append(contentsOf: zones)
                      row.append(contentsOf: [number(activity.decouplingPercent), number(activity.averageCadence),
                                              number(activity.elevationGain), activity.terrainRaw ?? "", activity.shoeID ?? ""])
                      return row
                  })

        let workouts = try context.fetch(FetchDescriptor<StrengthWorkout>(sortBy: [SortDescriptor(\.start)]))
        var setRows: [[String]] = []
        for workout in workouts {
            for set in workout.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
                setRows.append([date(workout.start), workout.title, workout.rpe.map { String($0) } ?? "", set.exercise, String(set.setIndex),
                                set.setType, number(set.weightKg), set.reps.map { String($0) } ?? "", number(set.rpe), set.exerciseNotes])
            }
        }
        try write("musculation_series", header: ["debut", "seance", "rpe_seance", "exercice", "serie", "type", "charge_kg", "reps", "rpe", "notes"],
                  rows: setRows)

        let foods = try context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
        try write("repas", header: ["date", "repas", "aliment", "marque", "grammes", "kcal", "proteines_g", "glucides_g", "lipides_g"],
                  rows: foods.map { entry in
                      [date(entry.date), entry.mealRaw, entry.name, entry.brand, number(entry.grams), number(entry.kcal),
                       number(entry.protein), number(entry.carbs), number(entry.fat)]
                  })

        let symptoms = try context.fetch(FetchDescriptor<Symptom>(sortBy: [SortDescriptor(\.date)]))
        try write("symptomes", header: ["date", "zone", "cote", "type", "intensite", "apparition_min", "sport", "terrain", "chaussures", "fatigue", "duree_min", "note"],
                  rows: symptoms.map { symptom in
                      [date(symptom.date), symptom.zoneRaw, symptom.sideRaw, symptom.typeRaw, String(symptom.intensity),
                       symptom.onsetMinutes.map { String($0) } ?? "", symptom.sportRaw ?? "", symptom.terrainRaw ?? "",
                       symptom.shoeID ?? "", String(symptom.fatigue), symptom.durationMinutes.map { String($0) } ?? "", symptom.note]
                  })

        let life = try context.fetch(FetchDescriptor<LifeActivity>(sortBy: [SortDescriptor(\.date)]))
        try write("hors_sport", header: ["date", "activite", "minutes", "intensite", "charge", "note"],
                  rows: life.map { [date($0.date), $0.kindRaw, String($0.minutes), String($0.intensity), number($0.loadEquivalent), $0.note] })

        let jsonURL = folder.appendingPathComponent("vigor.json")
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: jsonURL)
        files.append(jsonURL)
        return files
    }

    /// PDF du journal de symptômes, à montrer à un podologue ou un médecin.
    static func symptomReport(symptoms: [Symptom], patterns: [SymptomPattern], shoes: [Shoe]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Vigor-symptomes.pdf")
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let shoeNames = Dictionary(shoes.map { ($0.shoeID, $0.name) }, uniquingKeysWith: { first, _ in first })
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 18)]
        let heading: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 10)]

        try renderer.writePDF(to: url) { context in
            var y: CGFloat = 40
            func line(_ text: String, _ attributes: [NSAttributedString.Key: Any], spacing: CGFloat = 4) {
                let rect = CGRect(x: 40, y: y, width: page.width - 80, height: .greatestFiniteMagnitude)
                let height = (text as NSString).boundingRect(with: rect.size, options: .usesLineFragmentOrigin, attributes: attributes, context: nil).height
                if y + height > page.height - 40 {
                    context.beginPage()
                    y = 40
                }
                (text as NSString).draw(with: CGRect(x: 40, y: y, width: rect.width, height: height), options: .usesLineFragmentOrigin, attributes: attributes, context: nil)
                y += height + spacing
            }
            context.beginPage()
            line("Journal de symptômes", title, spacing: 8)
            line("Exporté le \(Date.now.formatted(date: .long, time: .omitted)) depuis Vigor. Ces analyses sont des corrélations, pas un diagnostic.", body, spacing: 12)
            for pattern in patterns {
                line(pattern.key, heading)
                var summary = String(format: "%d épisodes (%d sur 14 j), intensité moyenne %.1f/10", pattern.count, pattern.recentCount, pattern.averageIntensity)
                if let onset = pattern.averageOnset { summary += String(format: ", apparition médiane après %.0f min", onset) }
                line(summary, body)
                for finding in pattern.findings { line("• " + finding, body) }
                y += 6
            }
            line("Détail des épisodes", heading, spacing: 6)
            for symptom in symptoms.sorted(by: { $0.date > $1.date }) {
                var parts = [symptom.date.formatted(date: .abbreviated, time: .shortened), symptom.key, "\(symptom.intensity)/10"]
                if let onset = symptom.onsetMinutes { parts.append("après \(onset) min") }
                if let sport = symptom.sport { parts.append(sport.label.lowercased()) }
                if let terrain = symptom.terrain { parts.append(terrain.label.lowercased()) }
                if let id = symptom.shoeID, let name = shoeNames[id] { parts.append(name) }
                parts.append("fatigue \(symptom.fatigue)/5")
                if let duration = symptom.durationMinutes { parts.append("durée \(duration) min") }
                if !symptom.note.isEmpty { parts.append(symptom.note) }
                line(parts.joined(separator: " · "), body)
            }
        }
        return url
    }
}
