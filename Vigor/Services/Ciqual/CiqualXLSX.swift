import Foundation

/// Lecture de la table CIQUAL au format Excel moderne (.xlsx, publié par l'ANSES depuis 2025).
/// Un .xlsx est une archive ZIP de XML : chaînes partagées (xl/sharedStrings.xml) + feuille (xl/worksheets/sheet1.xml).
enum CiqualXLSX {
    enum FormatError: LocalizedError {
        case unsupported(String)
        case missingColumns

        var errorDescription: String? {
            switch self {
            case .unsupported(let name):
                "« \(name) » n'est pas lisible : choisis la version .xlsx (Excel récent) ou l'archive XML .zip de la table CIQUAL."
            case .missingColumns:
                "Colonnes CIQUAL introuvables dans le fichier Excel (nom, énergie, protéines, glucides, lipides)."
            }
        }
    }

    /// Vrai si les fichiers extraits ressemblent à un classeur Excel.
    static func isWorkbook(_ files: [String: Data]) -> Bool {
        files.keys.contains { $0.lowercased().hasPrefix("xl/worksheets/") }
    }

    static func parse(files: [String: Data]) throws -> [CiqualFood] {
        let shared = files.first { $0.key.lowercased() == "xl/sharedstrings.xml" }.map { SharedStrings.read($0.value) } ?? []
        guard let sheet = files.first(where: { $0.key.lowercased() == "xl/worksheets/sheet1.xml" })?.value
                ?? files.filter({ $0.key.lowercased().hasPrefix("xl/worksheets/") }).sorted(by: { $0.key < $1.key }).first?.value
        else { throw FormatError.missingColumns }
        let rows = SheetRows.read(sheet, shared: shared)
        guard let header = rows.first else { throw FormatError.missingColumns }

        // En-têtes sur plusieurs lignes dans Excel : espaces et retours à la ligne ramenés à un seul espace.
        let normalized = header.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased() }
        func column(_ matches: (String) -> Bool) -> Int? { normalized.firstIndex(where: matches) }
        guard let code = column({ $0 == "alim_code" }),
              let name = column({ $0 == "alim_nom_fr" }),
              let protein = column({ $0.hasPrefix("protéines, n x facteur de jones") }),
              let carbs = column({ $0.hasPrefix("glucides") }),
              let fat = column({ $0.hasPrefix("lipides") }) else { throw FormatError.missingColumns }
        let kcal = column { $0.hasPrefix("energie, règlement") && $0.contains("kcal") }
        let sugar = column { $0.hasPrefix("sucres") }
        let fiber = column { $0.hasPrefix("fibres alimentaires") }
        let saturated = column { $0.hasPrefix("ag saturés") }
        let salt = column { $0.hasPrefix("sel chlorure") }

        var foods: [CiqualFood] = []
        for row in rows.dropFirst() {
            func cell(_ index: Int?) -> String? {
                guard let index, index < row.count else { return nil }
                return row[index]
            }
            guard let foodCode = cell(code)?.trimmingCharacters(in: .whitespaces), !foodCode.isEmpty,
                  let foodName = cell(name)?.trimmingCharacters(in: .whitespaces), !foodName.isEmpty else { continue }
            let p = CiqualParser.number(cell(protein)), c = CiqualParser.number(cell(carbs)), f = CiqualParser.number(cell(fat))
            let fib = CiqualParser.number(cell(fiber))
            var energy = CiqualParser.number(cell(kcal))
            // Énergie absente : recalculée seulement si les trois macros sont connues, sinon l'aliment est écarté.
            if energy == nil {
                guard let p, let c, let f else { continue }
                energy = 4 * p + 4 * c + 9 * f + 2 * (fib ?? 0)
            }
            guard p != nil || c != nil || f != nil, let energy else { continue }
            foods.append(CiqualFood(code: foodCode, name: foodName, kcal: energy, protein: p ?? 0, carbs: c ?? 0, fat: f ?? 0,
                                    fiber: fib, sugar: CiqualParser.number(cell(sugar)),
                                    saturatedFat: CiqualParser.number(cell(saturated)), salt: CiqualParser.number(cell(salt))))
        }
        return foods.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// xl/sharedStrings.xml : <si><t>texte</t></si> (ou plusieurs <r><t>…</t></r> à concaténer).
    private final class SharedStrings: NSObject, XMLParserDelegate {
        var strings: [String] = []
        private var current = ""
        private var inText = false

        static func read(_ data: Data) -> [String] {
            let reader = SharedStrings()
            let parser = XMLParser(data: data)
            parser.delegate = reader
            parser.parse()
            return reader.strings
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            if elementName == "si" { current = "" }
            if elementName == "t" { inText = true }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inText { current += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "t" { inText = false }
            if elementName == "si" { strings.append(current) }
        }
    }

    /// xl/worksheets/sheetN.xml : lignes de cellules <c r="B2" t="s"><v>12</v></c>.
    private final class SheetRows: NSObject, XMLParserDelegate {
        let shared: [String]
        var rows: [[String]] = []
        private var row: [Int: String] = [:]
        private var column = 0
        private var type = ""
        private var value = ""
        private var capture = false

        init(shared: [String]) { self.shared = shared }

        static func read(_ data: Data, shared: [String]) -> [[String]] {
            let reader = SheetRows(shared: shared)
            let parser = XMLParser(data: data)
            parser.delegate = reader
            parser.parse()
            return reader.rows
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            switch elementName {
            case "row": row = [:]
            case "c":
                column = Self.columnIndex(attributeDict["r"] ?? "")
                type = attributeDict["t"] ?? ""
                value = ""
            case "v", "t": capture = true
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if capture { value += string }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            switch elementName {
            case "v", "t": capture = false
            case "c":
                if type == "s", let index = Int(value), index < shared.count {
                    row[column] = shared[index]
                } else {
                    row[column] = value
                }
            case "row":
                let width = (row.keys.max() ?? -1) + 1
                rows.append((0..<width).map { row[$0] ?? "" })
            default: break
            }
        }

        /// « AB12 » → 27 (A = 0).
        static func columnIndex(_ reference: String) -> Int {
            var index = 0
            for scalar in reference.unicodeScalars {
                guard scalar.value >= 65 && scalar.value <= 90 else { break }
                index = index * 26 + Int(scalar.value - 64)
            }
            return max(0, index - 1)
        }
    }
}
