import Foundation

/// Produit alimentaire normalisé (valeurs pour 100 g).
struct FoodProduct: Equatable, Identifiable {
    var id: String { key }
    let key: String
    let barcode: String?
    let name: String
    let brand: String
    let source: String
    let kcal100: Double
    let protein100: Double
    let carbs100: Double
    let fat100: Double
    let fiber100: Double?
    let sugar100: Double?
    let saturatedFat100: Double?
    let salt100: Double?
    let servingGrams: Double?
}

/// Accepte un nombre ou un texte (Open Food Facts mélange les deux).
struct FlexibleDouble: Decodable {
    let value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Double.self) {
            value = number
        } else if let text = try? container.decode(String.self) {
            value = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
        } else {
            value = nil
        }
    }
}

/// Accepte un texte, une liste de textes ou un texte par langue (selon l'API d'Open Food Facts).
struct FlexibleText: Decodable {
    let text: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            text = value
        } else if let list = try? container.decode([String].self) {
            text = list.joined(separator: ", ")
        } else if let byLanguage = try? container.decode([String: String].self) {
            text = byLanguage["fr"] ?? byLanguage["main"] ?? byLanguage["en"] ?? byLanguage.values.first
        } else if let number = try? container.decode(Int.self) {
            text = String(number)
        } else {
            text = nil
        }
    }
}

/// Base collaborative Open Food Facts (gratuite, très complète pour les produits français).
enum OpenFoodFacts {
    struct ProductResponse: Decodable {
        let status: Int?
        let product: RawProduct?
    }

    struct SearchResponse: Decodable {
        let products: [RawProduct]?
    }

    /// Réponse du moteur de recherche « search-a-licious » (search.openfoodfacts.org).
    struct ModernSearchResponse: Decodable {
        let hits: [RawProduct]?
    }

    struct RawProduct: Decodable {
        let code: FlexibleText?
        let productName: FlexibleText?
        let productNameFR: FlexibleText?
        let brands: FlexibleText?
        let servingQuantity: FlexibleDouble?
        let nutriments: [String: FlexibleDouble]?

        enum CodingKeys: String, CodingKey {
            case code
            case productName = "product_name"
            case productNameFR = "product_name_fr"
            case brands
            case servingQuantity = "serving_quantity"
            case nutriments
        }
    }

    enum OFFError: LocalizedError {
        case notFound, incomplete, network(Int), offline, busy

        var errorDescription: String? {
            switch self {
            case .notFound: "Produit introuvable dans Open Food Facts. Tu peux le créer à la main."
            case .incomplete: "Ce produit n'a pas de valeurs nutritionnelles complètes. Tu peux le créer à la main."
            case .network(let code): "Open Food Facts ne répond pas (code \(code)). Réessaie dans un instant ou utilise les aliments courants."
            case .offline: "Pas de connexion Internet. Les aliments courants, favoris et récents restent disponibles."
            case .busy: "Open Food Facts est surchargé. Réessaie dans une minute, ou scanne le code-barres (plus fiable)."
            }
        }
    }

    private static let fields = "code,product_name,product_name_fr,brands,serving_quantity,nutriments"

    static func product(barcode: String) async throws -> FoodProduct {
        var components = URLComponents(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json")!
        components.queryItems = [URLQueryItem(name: "fields", value: fields)]
        let data = try await get(components.url!)
        let response = try JSONDecoder().decode(ProductResponse.self, from: data)
        guard response.status == 1, let raw = response.product else { throw OFFError.notFound }
        guard let product = normalize(raw, fallbackBarcode: barcode) else { throw OFFError.incomplete }
        return product
    }

    /// Recherche texte : d'abord le nouveau moteur (rapide, peu limité), puis l'ancien en secours.
    static func search(_ query: String) async throws -> [FoodProduct] {
        do {
            let products = try await modernSearch(query)
            if !products.isEmpty { return products }
        } catch OFFError.offline {
            throw OFFError.offline
        } catch {
            // On tente l'ancienne API ci-dessous.
        }
        return try await legacySearch(query)
    }

    private static func modernSearch(_ query: String) async throws -> [FoodProduct] {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "langs", value: "fr,en"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: fields),
        ]
        let data = try await get(components.url!)
        let response = try JSONDecoder().decode(ModernSearchResponse.self, from: data)
        return (response.hits ?? []).compactMap { normalize($0, fallbackBarcode: nil) }
    }

    private static func legacySearch(_ query: String) async throws -> [FoodProduct] {
        var components = URLComponents(string: "https://world.openfoodfacts.org/cgi/search.pl")!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "search_simple", value: "1"),
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page_size", value: "25"),
            URLQueryItem(name: "fields", value: fields),
        ]
        let data = try await get(components.url!)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (response.products ?? []).compactMap { normalize($0, fallbackBarcode: nil) }
    }

    static func normalize(_ raw: RawProduct, fallbackBarcode: String?) -> FoodProduct? {
        let nutriments = raw.nutriments ?? [:]
        func value(_ key: String) -> Double? { nutriments[key]?.value }

        let kcal = value("energy-kcal_100g") ?? value("energy_100g").map { $0 / 4.184 }
        guard let kcal, let protein = value("proteins_100g"),
              let carbs = value("carbohydrates_100g"), let fat = value("fat_100g") else { return nil }

        let names: [String] = [raw.productNameFR?.text, raw.productName?.text].compactMap { $0 }
        let name = names.first { !$0.isEmpty } ?? "Produit sans nom"
        let barcode = raw.code?.text ?? fallbackBarcode
        let brand = raw.brands?.text?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
        return FoodProduct(
            key: "off|\(barcode ?? name)",
            barcode: barcode,
            name: name,
            brand: brand,
            source: "Open Food Facts",
            kcal100: kcal,
            protein100: protein,
            carbs100: carbs,
            fat100: fat,
            fiber100: value("fiber_100g"),
            sugar100: value("sugars_100g"),
            saturatedFat100: value("saturated-fat_100g"),
            salt100: value("salt_100g"),
            servingGrams: raw.servingQuantity?.value)
    }

    private static func get(_ url: URL, attempt: Int = 0) async throws -> Data {
        var request = URLRequest(url: url)
        // Open Food Facts demande un User-Agent « App/Version (contact) ».
        request.setValue("Vigor/0.8 (app iOS personnelle; contact: vigor-app)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                throw OFFError.offline
            case .timedOut where attempt == 0:
                return try await get(url, attempt: 1)
            default:
                throw OFFError.network(error.errorCode)
            }
        }
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300:
            return data
        case 404:
            throw OFFError.notFound
        case 429, 502, 503, 504:
            // Limite de requêtes ou serveur saturé : un seul nouvel essai après une courte pause.
            if attempt == 0 {
                try await Task.sleep(for: .seconds(1.5))
                return try await get(url, attempt: 1)
            }
            throw OFFError.busy
        default:
            throw OFFError.network(http.statusCode)
        }
    }
}
