import Foundation
import Testing
@testable import Vigor

struct CiqualTests {
    private let alim = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TABLE>
    <ALIM><alim_code> 9100 </alim_code><alim_nom_fr> Riz blanc, cuit </alim_nom_fr></ALIM>
    <ALIM><alim_code> 36000 </alim_code><alim_nom_fr> Poulet, filet, sans peau, cuit </alim_nom_fr></ALIM>
    </TABLE>
    """
    private let const = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TABLE>
    <CONST><const_code> 328 </const_code><const_nom_fr> Energie, Règlement UE N° 1169/2011 (kcal/100 g) </const_nom_fr></CONST>
    <CONST><const_code> 25000 </const_code><const_nom_fr> Protéines, N x facteur de Jones (g/100 g) </const_nom_fr></CONST>
    <CONST><const_code> 31000 </const_code><const_nom_fr> Glucides (g/100 g) </const_nom_fr></CONST>
    <CONST><const_code> 40000 </const_code><const_nom_fr> Lipides (g/100 g) </const_nom_fr></CONST>
    </TABLE>
    """
    private let compo = """
    <?xml version="1.0" encoding="UTF-8"?>
    <TABLE>
    <COMPO><alim_code> 9100 </alim_code><const_code> 328 </const_code><teneur> 146 </teneur></COMPO>
    <COMPO><alim_code> 9100 </alim_code><const_code> 25000 </const_code><teneur> 2,8 </teneur></COMPO>
    <COMPO><alim_code> 9100 </alim_code><const_code> 31000 </const_code><teneur> 31,7 </teneur></COMPO>
    <COMPO><alim_code> 9100 </alim_code><const_code> 40000 </const_code><teneur> &lt; 0,5 </teneur></COMPO>
    <COMPO><alim_code> 36000 </alim_code><const_code> 25000 </const_code><teneur> 30 </teneur></COMPO>
    <COMPO><alim_code> 36000 </alim_code><const_code> 40000 </const_code><teneur> traces </teneur></COMPO>
    </TABLE>
    """

    @Test func parsesOfficialXMLLayout() throws {
        let foods = try CiqualParser.parse(files: [
            "alim_2020_07_07.xml": Data(alim.utf8),
            "const_2020_07_07.xml": Data(const.utf8),
            "compo_2020_07_07.xml": Data(compo.utf8),
        ])
        let rice = try #require(foods.first { $0.code == "9100" })
        #expect(rice.name == "Riz blanc, cuit")
        #expect(rice.kcal == 146)
        #expect(rice.protein == 2.8)
        #expect(rice.carbs == 31.7)
        #expect(rice.fat == 0.25)
        // Énergie absente : recalculée à partir des macros (4/4/9).
        let chicken = try #require(foods.first { $0.code == "36000" })
        #expect(chicken.kcal == 120)
    }

    @Test func readsCiqualNumbers() {
        #expect(CiqualParser.number("12,5") == 12.5)
        #expect(CiqualParser.number("< 1") == 0.5)
        #expect(CiqualParser.number("traces") == 0)
        #expect(CiqualParser.number("-") == nil)
    }
}

struct FoodSearchTests {
    private func found(_ query: String, in name: String) -> Bool {
        CiqualStore.matches(CiqualStore.queryTokens(query), words: CiqualStore.words(CiqualStore.fold(name)))
    }

    @Test func matchesWordStartsOnly() {
        #expect(found("riz", in: "Riz blanc, cuit"))
        #expect(!found("riz", in: "Chorizo"))
    }

    @Test func toleratesPlurals() {
        #expect(found("oeufs", in: "Œuf, cru"))
        #expect(found("pommes", in: "Pomme, crue"))
        #expect(found("pommes de terre", in: "Pomme de terre, cuite"))
    }
}
