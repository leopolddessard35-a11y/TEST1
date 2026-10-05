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

/// Base collaborative Open Food Facts (gratuite, très complète pour les produits français).
enum OpenFoodFacts {
    struct ProductResponse: Decodable {
        let status: Int?
        let product: RawProduct?
    }

    struct SearchResponse: Decodable {
        let products: [RawProduct]?
    }

    struct RawProduct: Decodable {
        let code: String?
        let productName: String?
        let productNameFR: String?
        let brands: String?
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
        case notFound, incomplete, network(Int)

        var errorDescription: String? {
            switch self {
            case .notFound: "Produit introuvable dans Open Food Facts. Tu peux le créer à la main."
            case .incomplete: "Ce produit n'a pas de valeurs nutritionnelles complètes. Tu peux le créer à la main."
            case .network(let code): "Erreur réseau (\(code))."
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

    static func search(_ query: String) async throws -> [FoodProduct] {
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

        let name = [raw.productNameFR, raw.productName].compactMap { $0 }.first { !$0.isEmpty } ?? "Produit sans nom"
        let barcode = raw.code ?? fallbackBarcode
        let brand = raw.brands?.split(separator: ",").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
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

    private static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Vigor/0.2 (app iOS personnelle)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { throw OFFError.notFound }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw OFFError.network(http.statusCode) }
        return data
    }
}
