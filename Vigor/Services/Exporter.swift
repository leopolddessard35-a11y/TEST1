import Foundation
import SwiftData
import UIKit

/// Export complet (CSV + JSON) et PDF du journal de symptômes. Tout reste local jusqu'au partage.
/// CSV au format d'Excel en français : séparateur « ; », virgule décimale, dates à l'heure locale.
@MainActor
enum Exporter {
    /// Horodatage local avec décalage (« 2026-10-11T07:15:00+02:00 »).
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Jour de calendrier local (« 2026-10-11 »).
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func date(_ value: Date?) -> String { value.map { isoFormatter.string(from: $0) } ?? "" }
    private static func day(_ value: Date?) -> String { value.map { dayFormatter.string(from: $0) } ?? "" }
    /// Nombre avec point décimal (JSON) ; le CSV le convertit en virgule.
    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }
    private static func flag(_ value: Bool) -> String { value ? "oui" : "non" }

    /// Nombre au format « 12.5 » → « 12,5 » pour Excel en français (le texte n'est pas touché).
    private static func csvNumber(_ text: String) -> String {
        guard text.contains("."), Double(text) != nil,
              text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return text }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    private static func csvEscape(_ text: String) -> String {
        let value = csvNumber(text)
        let needsQuotes = value.contains(";") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        return needsQuotes ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" : value
    }

    /// Crée les fichiers d'export dans un dossier temporaire et renvoie leurs URL.
    static func exportAll(context: ModelContext) throws -> [URL] {
        // Fuseau horaire au moment de l'export (pas celui du premier lancement).
        isoFormatter.timeZone = .current
        dayFormatter.timeZone = .current
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Vigor-export-\(Int(Date.now.timeIntervalSince1970))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var files: [URL] = []
        var json: [String: Any] = ["exportedAt": date(.now), "formulas": FormulaVersion.all]

        func write(_ name: String, header: [String], rows: [[String]]) throws {
            let lines = [header.map(csvEscape).joined(separator: ";")] + rows.map { $0.map(csvEscape).joined(separator: ";") }
            let url = folder.appendingPathComponent("\(name).csv")
            // BOM UTF-8 : Excel reconnaît les accents ; fins de ligne Windows.
            try ("\u{FEFF}" + lines.joined(separator: "\r\n")).write(to: url, atomically: true, encoding: .utf8)
            files.append(url)
            json[name] = rows.map { Dictionary(zip(header, $0), uniquingKeysWith: { first, _ in first }) }
        }

        let wellness = try context.fetch(FetchDescriptor<DailyWellness>(sortBy: [SortDescriptor(\.day)]))
        try write("sante_quotidienne",
                  header: ["jour", "sommeil_h", "sommeil_profond_h", "sommeil_paradoxal_h", "sommeil_leger_h", "eveils_h",
                           "coucher", "lever", "vfc_sdnn_ms", "vfc_rmssd_ms", "fc_repos", "fc_sommeil", "respiration", "spo2",
                           "pas", "energie_active_kcal", "poids_kg", "masse_grasse_pct", "vo2max", "score_sommeil",
                           "readiness_garmin", "sommeil_garmin_h", "fc_repos_garmin", "respiration_garmin", "vo2max_garmin",
                           "poids_garmin_kg"],
                  rows: wellness.map { record -> [String] in
                      [day(record.day), number(record.sleepHours), number(record.sleepDeepHours), number(record.sleepREMHours),
                       number(record.sleepCoreHours), number(record.sleepAwakeHours), date(record.bedtime), date(record.wakeTime),
                       number(record.hrvMs), number(record.hrvRMSSD), number(record.restingHeartRate),
                       number(record.sleepingHeartRate), number(record.respiration), number(record.spO2), number(record.steps),
                       number(record.activeEnergyKcal), number(record.weightKg), number(record.bodyFatPercent),
                       number(record.vo2Max), number(record.sleepScore), number(record.garminReadiness),
                       number(record.sleepHoursGarmin), number(record.restingHeartRateGarmin), number(record.respirationGarmin),
                       number(record.vo2MaxGarmin), number(record.weightKgGarmin)]
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

        let routines = try context.fetch(FetchDescriptor<WorkoutRoutine>(sortBy: [SortDescriptor(\.order)]))
        var routineRows: [[String]] = []
        for routine in routines {
            for (index, item) in routine.items.enumerated() {
                routineRows.append([routine.program, routine.name, String(index + 1), item.exercise, String(item.sets),
                                    String(item.repLow), String(item.repHigh), String(item.restSeconds), item.note, routine.notes])
            }
        }
        try write("seances_types", header: ["programme", "seance", "ordre", "exercice", "series", "reps_min", "reps_max",
                                            "repos_s", "note_exercice", "note_seance"],
                  rows: routineRows)

        let exercises = try context.fetch(FetchDescriptor<CustomExercise>(sortBy: [SortDescriptor(\.name)]))
        try write("exercices_perso", header: ["nom", "muscles_principaux", "muscles_secondaires", "materiel", "cree_le"],
                  rows: exercises.map { [$0.name, $0.primaryRaw.joined(separator: ", "), $0.secondaryRaw.joined(separator: ", "),
                                         $0.equipmentRaw, date($0.createdAt)] })

        let foods = try context.fetch(FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.date)]))
        try write("repas", header: ["date", "repas", "aliment", "marque", "grammes", "kcal", "proteines_g", "glucides_g", "lipides_g"],
                  rows: foods.map { entry in
                      [date(entry.date), entry.meal.label, entry.name, entry.brand, number(entry.grams), number(entry.kcal),
                       number(entry.protein), number(entry.carbs), number(entry.fat)]
                  })

        // Aliments créés à la main (« Créer » dans l'ajout d'aliment).
        let customFoods = try context.fetch(FetchDescriptor<FoodItem>(sortBy: [SortDescriptor(\.name)]))
            .filter { $0.key.hasPrefix("custom|") }
        try write("aliments_perso", header: ["nom", "marque", "kcal_100g", "proteines_100g", "glucides_100g", "lipides_100g",
                                             "fibres_100g", "sucres_100g", "satures_100g", "sel_100g", "portion_g"],
                  rows: customFoods.map { item -> [String] in
                      [item.name, item.brand, number(item.kcal100), number(item.protein100), number(item.carbs100),
                       number(item.fat100), number(item.fiber100), number(item.sugar100), number(item.saturatedFat100),
                       number(item.salt100), number(item.servingGrams)]
                  })

        let goals = try context.fetch(FetchDescriptor<Goal>(sortBy: [SortDescriptor(\.date)]))
        try write("objectifs", header: ["nom", "date", "sport", "distance_km", "priorite", "note"],
                  rows: goals.map { [$0.name, day($0.date), $0.sportRaw, number($0.distanceKm), $0.priorityRaw, $0.note] })

        let unavailabilities = try context.fetch(FetchDescriptor<Unavailability>(sortBy: [SortDescriptor(\.start)]))
        try write("indisponibilites", header: ["debut", "fin", "raison", "note"],
                  rows: unavailabilities.map { [date($0.start), date($0.end), $0.reason.label, $0.note] })

        let injuries = try context.fetch(FetchDescriptor<Injury>(sortBy: [SortDescriptor(\.start)]))
        try write("blessures", header: ["titre", "muscles", "gene_course", "gene_velo", "gravite", "debut", "guerie_le", "note"],
                  rows: injuries.map { injury -> [String] in
                      [injury.title, injury.musclesRaw.joined(separator: ", "), flag(injury.affectsRunning),
                       flag(injury.affectsCycling), String(injury.severity), day(injury.start), day(injury.resolvedAt), injury.note]
                  })

        let shoes = try context.fetch(FetchDescriptor<Shoe>(sortBy: [SortDescriptor(\.addedAt)]))
        try write("chaussures", header: ["id", "nom", "km_initiaux", "retiree", "par_defaut", "ajoutee_le"],
                  rows: shoes.map { [$0.shoeID, $0.name, number($0.initialKm), flag($0.retired), flag($0.isDefault), day($0.addedAt)] })

        if let profile = try context.fetch(FetchDescriptor<AthleteProfile>()).first {
            let fields: [(String, String)] = [
                ("ftp_w", number(profile.ftp)), ("lthr_velo", number(profile.cyclingLTHR)),
                ("lthr_course", number(profile.runningLTHR)), ("fc_max", number(profile.maxHeartRate)),
                ("poids_kg", number(profile.weightKg)), ("taille_cm", number(profile.heightCm)),
                ("annee_naissance", profile.birthYear > 0 ? String(profile.birthYear) : ""), ("sexe", profile.sex.label),
                ("course_objectif", profile.raceName), ("date_course", day(profile.raceDate)),
                ("heures_par_semaine", number(profile.weeklyHoursAvailable)),
                ("muscu_par_semaine", String(profile.strengthSessionsPerWeek)), ("besoin_sommeil_h", number(profile.sleepNeedHours)),
                ("minutes_par_jour_dim_sam", profile.weekdayMinutesRaw), ("objectif_poids", profile.weightGoalRaw),
                ("ecart_calorique_kcal", number(profile.calorieAdjustment)), ("proteines_g_par_kg", number(profile.proteinPerKg)),
                ("lipides_g_par_kg", number(profile.fatPerKg)), ("objectifs_manuels", flag(profile.manualTargets)),
                ("kcal_manuel", number(profile.manualKcal)), ("proteines_manuel_g", number(profile.manualProtein)),
                ("glucides_manuel_g", number(profile.manualCarbs)), ("lipides_manuel_g", number(profile.manualFat)),
            ]
            try write("profil", header: ["champ", "valeur"], rows: fields.map { [$0.0, $0.1] })
        }

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
                var summary = "\(pattern.count) épisodes (\(pattern.recentCount) sur 14 j), intensité moyenne \(pattern.averageIntensity.oneDecimal)/10"
                if let onset = pattern.averageOnset { summary += ", apparition médiane après \(onset.noDecimal) min" }
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
