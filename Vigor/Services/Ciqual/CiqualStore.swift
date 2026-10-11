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
        case unreadable

        var errorDescription: String? {
            switch self {
            case .missingFiles:
                "Fichiers CIQUAL introuvables : il faut l'archive XML (alim, compo, const) téléchargée sur ciqual.anses.fr."
            case .unreadable:
                "Fichier CIQUAL illisible (format XML inattendu)."
            }
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
            for row in try rows(constData, record: "CONST") {
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
        for row in try rows(alimData, record: "ALIM") {
            if let code = row["alim_code"], let name = row["alim_nom_fr"], !name.isEmpty { names[code] = name }
        }

        // 3. Teneurs (fichier volumineux : on ne garde que les constituants utiles).
        var values: [String: [Nutrient: Double]] = [:]
        for row in try rows(compoData, record: "COMPO", keep: { codes[$0["const_code"] ?? ""] != nil }) {
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

    /// Lit les enregistrements ; si le XML est refusé (encodage Windows-1252 mal déclaré…),
    /// réessaie après conversion en UTF-8, sinon lève une erreur claire.
    private static func rows(_ data: Data, record: String, keep: (([String: String]) -> Bool)? = nil) throws -> [[String: String]] {
        if let rows = parseRows(data, record: record, keep: keep) { return rows }
        if let text = String(data: data, encoding: .windowsCP1252),
           let utf8 = declaringUTF8(text).data(using: .utf8),
           let rows = parseRows(utf8, record: record, keep: keep) {
            return rows
        }
        throw ParseError.unreadable
    }

    /// `nil` si l'analyse XML échoue.
    private static func parseRows(_ data: Data, record: String, keep: (([String: String]) -> Bool)?) -> [[String: String]]? {
        let reader = RecordReader(record: record, keep: keep)
        let parser = XMLParser(data: data)
        parser.delegate = reader
        return parser.parse() ? reader.rows : nil
    }

    /// Remplace l'attribut `encoding` de la déclaration XML par UTF-8 (le texte vient d'être réencodé).
    private static func declaringUTF8(_ text: String) -> String {
        guard let start = text.range(of: "<?xml"),
              let end = text.range(of: "?>", range: start.upperBound..<text.endIndex) else { return text }
        let declaration = String(text[start.lowerBound..<end.upperBound])
        guard let regex = try? NSRegularExpression(pattern: "encoding\\s*=\\s*[\"'][^\"']*[\"']") else { return text }
        let fixed = regex.stringByReplacingMatches(in: declaration, range: NSRange(declaration.startIndex..., in: declaration),
                                                   withTemplate: "encoding=\"UTF-8\"")
        return String(text[text.startIndex..<start.lowerBound]) + fixed + String(text[end.upperBound...])
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
    /// Version affichée : « CIQUAL 2025 (intégrée) » ou la version importée.
    private(set) var versionLabel = ""
    private(set) var isWorking = false
    private(set) var progress = ""
    private(set) var lastError: String?
    @ObservationIgnored private var folded: [String] = []
    /// Mots de chaque nom replié, pour une correspondance en début de mot (« riz » ≠ « chorizo »).
    @ObservationIgnored private var foldedWords: [[String]] = []

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

    /// Table importée par l'utilisateur si elle existe, sinon la table CIQUAL 2025 intégrée à l'app.
    private func loadFromDisk() {
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([CiqualFood].self, from: data), !decoded.isEmpty {
            setFoods(decoded)
            installedAt = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
            versionLabel = "Table importée"
            return
        }
        loadBundled()
    }

    private func loadBundled() {
        guard let url = Bundle.main.url(forResource: "ciqual_2025", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([CiqualFood].self, from: data) else { return }
        setFoods(decoded)
        installedAt = nil
        versionLabel = "CIQUAL 2025 (ANSES), intégrée à l'app"
    }

    /// Une table importée remplace la table intégrée ; la supprimer revient à la table intégrée.
    var hasImportedTable: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// Recherche hors ligne : chaque mot tapé doit commencer un mot du nom (accents et casse ignorés) ;
    /// les noms qui commencent par le premier mot et les plus courts passent devant.
    func search(_ query: String, limit: Int = 20) -> [CiqualFood] {
        let tokens = Self.words(Self.fold(query)).filter { $0.count >= 2 }
        guard !tokens.isEmpty else { return [] }
        var hits: [(food: CiqualFood, rank: Int)] = []
        for (index, words) in foldedWords.enumerated()
        where tokens.allSatisfy({ token in words.contains { $0.hasPrefix(token) } }) {
            let name = folded[index]
            let rank = ((words.first?.hasPrefix(tokens[0]) ?? false) ? 0 : 1000) + name.count
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
            try await install { [("ciqual.zip", data)] }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Installe à partir de fichiers choisis dans Fichiers : le classeur .xlsx, l'archive .zip, ou les fichiers .xml extraits.
    func importFiles(_ urls: [URL]) async {
        isWorking = true
        lastError = nil
        progress = "Lecture des fichiers…"
        defer { isWorking = false; progress = "" }
        do {
            // Lecture des fichiers hors du fil principal (archive de plusieurs Mo).
            try await install { Self.read(urls) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Supprime la table importée et revient à la table intégrée.
    func remove() {
        try? FileManager.default.removeItem(at: fileURL)
        loadBundled()
    }

    nonisolated private static func read(_ urls: [URL]) -> [(String, Data)] {
        var payloads: [(String, Data)] = []
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url) { payloads.append((url.lastPathComponent, data)) }
        }
        return payloads
    }

    /// `load` fournit les fichiers (.xlsx, .zip ou .xml) ; lecture, décompression, analyse et écriture se font hors du fil principal.
    private func install(load: @escaping @Sendable () throws -> [(String, Data)]) async throws {
        progress = "Analyse de la table (environ 3 000 aliments)…"
        let target = fileURL
        let foods: [CiqualFood] = try await Task.detached(priority: .userInitiated) {
            let payloads = try load()
            var files: [String: Data] = [:]
            for (name, data) in payloads {
                let lower = name.lowercased()
                // Ancien Excel (.xls, binaire) et archive 7-Zip : formats non lisibles sur iPhone.
                if lower.hasSuffix(".xls") || lower.hasSuffix(".7z") { throw CiqualXLSX.FormatError.unsupported(name) }
                let bytes = [UInt8](data)
                if bytes.count > 4, bytes[0] == 0x50, bytes[1] == 0x4B {
                    for entry in try ZipReader.entries(in: bytes) where entry.name.lowercased().hasSuffix(".xml") {
                        files[entry.name] = try ZipReader.extract(entry, from: bytes)
                    }
                } else {
                    files[name] = data
                }
            }
            let parsed = try (CiqualXLSX.isWorkbook(files) ? CiqualXLSX.parse(files: files) : CiqualParser.parse(files: files))
            guard !parsed.isEmpty else { throw CiqualParser.ParseError.missingFiles }
            let data = try JSONEncoder().encode(parsed)
            try data.write(to: target, options: .atomic)
            return parsed
        }.value
        setFoods(foods)
        installedAt = .now
        versionLabel = "Table importée"
    }

    private func setFoods(_ list: [CiqualFood]) {
        foods = list
        folded = list.map { Self.fold($0.name) }
        foldedWords = folded.map { Self.words($0) }
    }

    /// Minuscules sans accents ; « œ » → « oe », « æ » → « ae » (« bœuf » = « boeuf »).
    nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .replacingOccurrences(of: "œ", with: "oe")
            .replacingOccurrences(of: "Œ", with: "oe")
            .replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "Æ", with: "ae")
            .replacingOccurrences(of: ",", with: " ")
    }

    /// Découpe un texte replié en mots (lettres et chiffres).
    nonisolated static func words(_ folded: String) -> [String] {
        folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
    }
}
