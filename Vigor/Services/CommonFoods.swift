import Foundation

/// Aliments sans code-barres les plus courants.
/// Valeurs moyennes pour 100 g (ordre de grandeur des tables Ciqual/ANSES et USDA FoodData Central, arrondies).
enum CommonFoods {
    private static func food(_ name: String, _ kcal: Double, _ protein: Double, _ carbs: Double, _ fat: Double,
                             fiber: Double? = nil, serving: Double? = nil) -> FoodProduct {
        FoodProduct(key: "ref|\(name)", barcode: nil, name: name, brand: "", source: "Référence",
                    kcal100: kcal, protein100: protein, carbs100: carbs, fat100: fat,
                    fiber100: fiber, sugar100: nil, saturatedFat100: nil, salt100: nil, servingGrams: serving)
    }

    static let all: [FoodProduct] = [
        food("Riz blanc cuit", 130, 2.7, 28, 0.3, fiber: 0.4, serving: 180),
        food("Riz complet cuit", 123, 2.7, 26, 1, fiber: 1.6, serving: 180),
        food("Pâtes cuites", 150, 5.2, 30, 0.9, fiber: 1.8, serving: 200),
        food("Pommes de terre cuites", 85, 2, 18, 0.1, fiber: 1.8, serving: 200),
        food("Patate douce cuite", 86, 1.6, 20, 0.1, fiber: 3, serving: 200),
        food("Quinoa cuit", 120, 4.4, 21, 1.9, fiber: 2.8, serving: 180),
        food("Flocons d'avoine", 370, 13, 60, 7, fiber: 10, serving: 60),
        food("Pain complet", 245, 9, 42, 3, fiber: 7, serving: 60),
        food("Baguette", 270, 9, 55, 1.2, fiber: 2.7, serving: 60),
        food("Blanc de poulet cuit", 165, 31, 0, 3.6, serving: 150),
        food("Steak haché 5 % cuit", 150, 26, 0, 5, serving: 125),
        food("Saumon cuit", 206, 22, 0, 13, serving: 130),
        food("Thon au naturel", 115, 26, 0, 1, serving: 100),
        food("Œuf entier", 143, 12.6, 0.7, 9.5, serving: 55),
        food("Blanc d'œuf", 52, 11, 0.7, 0.2, serving: 33),
        food("Fromage blanc 0 %", 47, 7.5, 4, 0.2, serving: 150),
        food("Skyr nature", 60, 10.5, 4, 0.2, serving: 150),
        food("Yaourt nature", 60, 4, 5, 3, serving: 125),
        food("Lait demi-écrémé", 46, 3.3, 4.8, 1.6, serving: 250),
        food("Emmental", 380, 28, 0, 29, serving: 30),
        food("Tofu ferme", 144, 15, 3, 8, fiber: 2, serving: 100),
        food("Lentilles cuites", 116, 9, 20, 0.4, fiber: 8, serving: 200),
        food("Pois chiches cuits", 164, 8.9, 27, 2.6, fiber: 7.6, serving: 150),
        food("Brocoli cuit", 35, 2.4, 7, 0.4, fiber: 3.3, serving: 150),
        food("Haricots verts cuits", 31, 1.8, 7, 0.1, fiber: 3.2, serving: 150),
        food("Banane", 89, 1.1, 23, 0.3, fiber: 2.6, serving: 120),
        food("Pomme", 52, 0.3, 14, 0.2, fiber: 2.4, serving: 150),
        food("Orange", 47, 0.9, 12, 0.1, fiber: 2.4, serving: 150),
        food("Dattes", 280, 2.5, 66, 0.4, fiber: 7, serving: 30),
        food("Amandes", 580, 21, 9, 50, fiber: 12, serving: 30),
        food("Beurre de cacahuète", 590, 25, 16, 50, fiber: 6, serving: 20),
        food("Avocat", 160, 2, 9, 15, fiber: 7, serving: 100),
        food("Huile d'olive", 900, 0, 0, 100, serving: 10),
        food("Miel", 304, 0.3, 82, 0, serving: 20),
        food("Chocolat noir 70 %", 600, 8, 46, 43, fiber: 11, serving: 20),
        food("Whey (poudre)", 380, 78, 7, 5, serving: 30),
    ]

    static func search(_ query: String) -> [FoodProduct] {
        let needle = query.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        guard !needle.isEmpty else { return all }
        return all.filter {
            $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).contains(needle)
        }
    }
}
