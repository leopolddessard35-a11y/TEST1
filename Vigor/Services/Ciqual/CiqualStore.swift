import Foundation
import Observation

/// Un aliment générique de la table CIQUAL (ANSES), valeurs pour 100 g.
struct CiqualFood: Codable, Equatable, Identifiable {
    var id: String { code }
    let code: String
    let name: String
    let kcal: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    var fiber: Double?
    var sugar: Double?
    var saturatedFat: Double?
    var salt: Double?
}

extension FoodProduct {
    init(ciqual food: CiqualFood) {
        self.init(key: "ciqual|\(food.code)", barcode: nil, name: food.name, brand: "", source: "CIQUAL (ANSES)",
                  kcal100: food.kcal, protein100: food.protein, carbs100: food.carbs, fat100: food.fat,
                  fiber100: food.fiber, sugar100: food.sugar, saturatedFat100: food.saturatedFat, salt100: food.salt,
                  servingGrams: nil)
    }
}

/// Lecture de la table CIQUAL au format XML officiel (fichiers alim_*.xml, compo_*.xml, const_*.xml).
enum CiqualParser {
    enum ParseError: LocalizedError {
        case missingFiles

        var errorDescription: String? {
            "Fichiers CIQUAL introuvables : il faut l'archive XML (alim, compo, const) téléchargée sur ciqual.anses.fr."
        }
    }

    /// Constituants retenus, reconnus par leur nom (robuste aux changements de version), avec les codes 2020 en secours.
    private enum Nutrient: CaseIterable {
        case kcal, protein, carbs, fat, sugar, fiber, saturatedFat, salt

        var fallbackCode: String? {
            switch self {
            case .kcal: nil
            case .protein: "25000"
            case .carbs: "31000"
            case .fat: "40000"
            case .sugar: "32000"
            case .fiber: "34100"
            case .saturatedFat: "40302"
            case .salt: "10004"
            }
        }

        func matches(_ name: String) -> Bool {
            let n = name.lowercased()
            switch self {
            case .kcal: return n.contains("kcal/100") && (n.contains("1169") || n.hasPrefix("energie"))
            case .protein: return n.hasPrefix("protéines, n x facteur de jones")
            case .carbs: return n.hasPrefix("glucides (g/100")
            case .fat: return n.hasPrefix("lipides (g/100")
            case .sugar: return n.hasPrefix("sucres (g/100")
            case .fiber: return n.hasPrefix("fibres alimentaires")
            case .saturatedFat: return n.hasPrefix("ag saturés")
            case .salt: return n.hasPrefix("sel chlorure de sodium")
            }
        }
    }

    /// `files` : nom de fichier → contenu XML.
    static func parse(files: [String: Data]) throws -> [CiqualFood] {
        func file(_ prefix: String) -> Data? {
            files.first { key, _ in
                let name = (key as NSString).lastPathComponent.lowercased()
                return name.hasPrefix(prefix) && name.hasSuffix(".xml")
            }?.value
        }
        guard let alimData = file("alim_2") ?? file("alim_"), let compoData = file("compo_") else {
            throw ParseError.missingFiles
        }

        // 1. Codes des constituants utiles.
        var codes: [String: Nutrient] = [:]
        if let constData = file("const_") {
            for row in rows(constData, record: "CONST") {
                guard let code = row["const_code"], let name = row["const_nom_fr"] else { continue }
                for nutrient in Nutrient.allCases where nutrient.matches(name) && !codes.values.contains(nutrient) {
                    codes[code] = nutrient
                }
            }
        }
        for nutrient in Nutrient.allCases where !codes.values.contains(nutrient) {
            if let code = nutrient.fallbackCode { codes[code] = nutrient }
        }

        // 2. Noms des aliments.
        var names: [String: String] = [:]
        for row in rows(alimData, record: "ALIM") {
            if let code = row["alim_code"], let name = row["alim_nom_fr"], !name.isEmpty { names[code] = name }
        }

        // 3. Teneurs (fichier volumineux : on ne garde que les constituants utiles).
        var values: [String: [Nutrient: Double]] = [:]
        for row in rows(compoData, record: "COMPO", keep: { codes[$0["const_code"] ?? ""] != nil }) {
            guard let food = row["alim_code"], let code = row["const_code"], let nutrient = codes[code],
                  let value = number(row["teneur"]) else { continue }
            values[food, default: [:]][nutrient] = value
        }

        var foods: [CiqualFood] = []
        for (code, name) in names {
            guard let nutrients = values[code] else { continue }
            let protein = nutrients[.protein], carbs = nutrients[.carbs], fat = nutrients[.fat]
            guard protein != nil || carbs != nil || fat != nil else { continue }
            let p = protein ?? 0, c = carbs ?? 0, f = fat ?? 0
            let fiber = nutrients[.fiber]
            // Énergie absente : calculée selon les coefficients du règlement UE 1169/2011.
            let kcal = nutrients[.kcal] ?? (4 * p + 4 * c + 9 * f + 2 * (fiber ?? 0))
            foods.append(CiqualFood(code: code, name: name, kcal: kcal, protein: p, carbs: c, fat: f,
                                    fiber: fiber, sugar: nutrients[.sugar], saturatedFat: nutrients[.saturatedFat],
                                    salt: nutrients[.salt]))
        }
        return foods.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Teneur CIQUAL : « 12,5 », « < 0,5 » (moitié du seuil), « traces » (0), « - » (inconnu).
    static func number(_ raw: String?) -> Double? {
        guard var text = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text != "-" else { return nil }
        if text.lowercased().hasPrefix("trace") { return 0 }
        var halve = false
        if text.hasPrefix("<") {
            halve = true
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        guard let value = Double(text.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return halve ? value / 2 : value
    }

    private static func rows(_ data: Data, record: String, keep: (([String: String]) -> Bool)? = nil) -> [[String: String]] {
        let reader = RecordReader(record: record, keep: keep)
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.parse()
        return reader.rows
    }

    /// Lecteur XML en flux : chaque <RECORD> devient un dictionnaire balise → texte.
    private final class RecordReader: NSObject, XMLParserDelegate {
        let record: String
        let keep: (([String: String]) -> Bool)?
        var rows: [[String: String]] = []
        private var current: [String: String]?
        private var text = ""

        init(record: String, keep: (([String: String]) -> Bool)?) {
            self.record = record
            self.keep = keep
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == record { current = [:] }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == record {
                if let current, keep?(current) ?? true { rows.append(current) }
                current = nil
            } else if current != nil {
                current?[elementName] = text.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            text = ""
        }
    }
}

/// La table CIQUAL installée sur l'iPhone (fichier JSON local, recherche hors ligne).
@MainActor
@Observable
final class CiqualStore {
    static let shared = CiqualStore()

    private(set) var foods: [CiqualFood] = []
    private(set) var installedAt: Date?
    private(set) var isWorking = false
    private(set) var progress = ""
    private(set) var lastError: String?
    @ObservationIgnored private var folded: [String] = []

    private init() {
        loadFromDisk()
    }

    /// Adresses officielles essayées dans l'ordre (archive XML de l'ANSES).
    static let defaultURLs: [String] = [
        "https://ciqual.anses.fr/cms/sites/default/files/inline-files/XML_2020_07_07.zip"
    ]

    var isInstalled: Bool { !foods.isEmpty }

    private var fileURL: URL {
        let folder = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return folder.appendingPathComponent("ciqual.json")
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([CiqualFood].self, from: data) else { return }
        setFoods(decoded)
        installedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
    }

    /// Recherche hors ligne : tous les mots doivent apparaître (accents et casse ignorés) ;
    /// les noms qui commencent par le premier mot et les plus courts passent devant.
    func search(_ query: String, limit: Int = 20) -> [CiqualFood] {
        let tokens = Self.fold(query).split(separator: " ").map(String.init).filter { $0.count >= 2 }
        guard !tokens.isEmpty else { return [] }
        var hits: [(food: CiqualFood, rank: Int)] = []
        for (index, name) in folded.enumerated() where tokens.allSatisfy({ name.contains($0) }) {
            let rank = (name.hasPrefix(tokens[0]) ? 0 : 1000) + name.count
            hits.append((foods[index], rank))
        }
        return hits.sorted { $0.rank < $1.rank }.prefix(limit).map(\.food)
    }

    /// Télécharge l'archive officielle et l'installe.
    func download(from address: String) async {
        guard let url = URL(string: address) else { lastError = "Adresse invalide."; return }
        isWorking = true
        lastError = nil
        progress = "Téléchargement de la table CIQUAL…"
        defer { isWorking = false; progress = "" }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 120
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                lastError = "Téléchargement refusé (code \(http.statusCode)). Importe le fichier à la main (voir ci-dessous)."
                return
            }
            try await install(zipOrXML: [("ciqual.zip", data)])
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Installe à partir de fichiers choisis dans Fichiers : l'archive .zip, ou les fichiers .xml extraits.
    func importFiles(_ urls: [URL]) async {
        isWorking = true
        lastError = nil
        progress = "Lecture des fichiers…"
        defer { isWorking = false; progress = "" }
        var payloads: [(String, Data)] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { payloads.append((url.lastPathComponent, data)) }
        }
        do {
            try await install(zipOrXML: payloads)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        setFoods([])
        installedAt = nil
    }

    private func install(zipOrXML payloads: [(String, Data)]) async throws {
        progress = "Analyse de la table (environ 3 000 aliments)…"
        let foods: [CiqualFood] = try await Task.detached(priority: .userInitiated) {
            var files: [String: Data] = [:]
            for (name, data) in payloads {
                let bytes = [UInt8](data)
                if bytes.count > 4, bytes[0] == 0x50, bytes[1] == 0x4B {
                    for entry in try ZipReader.entries(in: bytes) where entry.name.lowercased().hasSuffix(".xml") {
                        files[entry.name] = try ZipReader.extract(entry, from: bytes)
                    }
                } else {
                    files[name] = data
                }
            }
            return try CiqualParser.parse(files: files)
        }.value
        guard !foods.isEmpty else { throw CiqualParser.ParseError.missingFiles }
        let data = try JSONEncoder().encode(foods)
        try data.write(to: fileURL, options: .atomic)
        setFoods(foods)
        installedAt = .now
    }

    private func setFoods(_ list: [CiqualFood]) {
        foods = list
        folded = list.map { Self.fold($0.name) }
    }

    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: ",", with: " ")
    }
}
