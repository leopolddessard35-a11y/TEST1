import Foundation
import Testing
@testable import Vigor

private func date(daysAgo: Int, from today: Date = DateComponents(calendar: .current, year: 2026, month: 10, day: 20, hour: 12).date!) -> Date {
    Calendar.current.date(byAdding: .day, value: -daysAgo, to: today)!
}

private let today = date(daysAgo: 0)

private func baseInput() -> InsightInput {
    InsightInput(today: today, wellness: [], load: [], activities: [], strength: [], nutrition: [],
                 weightKg: 72, ftp: 206, sleepNeedHours: 8, phase: .base, readiness: nil)
}

struct InsightEngineTests {
    @Test func detectsOverreachingFromHRVAndRestingHR() {
        var input = baseInput()
        input.wellness = (0..<60).map { offset in
            let recent = offset < 7
            return WellnessSample(date: date(daysAgo: offset), sleepHours: 8,
                                  hrv: recent ? 45 : 62 + Double(offset % 4),
                                  restingHR: recent ? 56 : 48 + Double(offset % 2), weightKg: nil)
        }
        let insights = InsightEngine.recovery(input, calendar: .current)
        #expect(insights.first?.id == "recovery.overreaching")
        #expect(insights.first?.severity == .warning)
        #expect(!(insights.first?.references.isEmpty ?? true))
    }

    @Test func detectsSleepDebt() {
        var input = baseInput()
        input.wellness = (0..<7).map { WellnessSample(date: date(daysAgo: $0), sleepHours: 6.2) }
        let insights = InsightEngine.sleep(input, calendar: .current)
        #expect(insights.contains { $0.id == "sleep.debt" })
    }

    @Test func detectsGreyZoneTraining() {
        var input = baseInput()
        input.activities = (1...8).map { ActivitySample(date: date(daysAgo: $0 * 3), sport: .cycling, durationSeconds: 5400,
                                                        tss: 90, intensityFactor: 0.82, averagePower: 170) }
        let insights = InsightEngine.intensityDistribution(input, calendar: .current)
        #expect(insights.first?.id == "intensity.grey")
    }

    @Test func detectsLowProtein() {
        var input = baseInput()
        input.nutrition = (0..<5).map { NutritionDay(date: date(daysAgo: $0), kcal: 2400, protein: 90, carbs: 300, fat: 80) }
        let insights = InsightEngine.nutrition(input, calendar: .current)
        #expect(insights.contains { $0.id == "nutrition.protein" && $0.severity == .warning })
    }

    @Test func flagsUnderestimatedFTP() {
        var input = baseInput()
        input.activities = [ActivitySample(date: date(daysAgo: 2), sport: .indoorCycling, durationSeconds: 1800,
                                           tss: 60, intensityFactor: 1.05, averagePower: 225)]
        let insights = InsightEngine.dataQuality(input, calendar: .current)
        #expect(insights.contains { $0.id == "data.ftpLow" })
    }

    @Test func detectsRapidLoadIncrease() {
        var input = baseInput()
        var daily: [Date: Double] = [:]
        for offset in 0..<60 {
            let day = Calendar.current.startOfDay(for: date(daysAgo: offset))
            daily[day] = offset < 7 ? 150 : 40
        }
        input.load = TrainingLoad.series(daily: daily, from: date(daysAgo: 59), to: today)
        let insights = InsightEngine.load(input, calendar: .current)
        #expect(insights.contains { $0.id == "load.ramp" })
        #expect(insights.contains { $0.id == "load.acwr" })
    }
}

struct NutritionPlannerTests {
    @Test func mifflinStJeor() {
        // 10 × 72 + 6,25 × 180 − 5 × 30 + 5 = 1 700
        #expect(NutritionPlanner.basalMetabolicRate(weightKg: 72, heightCm: 180, age: 30, sex: .male) == 1700)
    }

    @Test func massPhaseTargetsFollowGuidelines() {
        let targets = NutritionPlanner.targets(weightKg: 72, heightCm: 180, age: 30, sex: .male, activeKcal: 700,
                                               trainingHours: 1.5, phase: .base, adaptiveExpenditure: nil)!
        #expect(abs(targets.protein - 130) < 1)        // 1,8 g/kg
        #expect(targets.carbs / 72 >= 6.4)             // ≥ 6,5 g/kg pour 1,5 h (Burke 2011)
        #expect(targets.kcal > targets.expenditure)    // surplus en prise de masse
    }

    @Test func adaptiveExpenditureFromWeightTrend() {
        // 2 800 kcal/j et poids stable → dépense ≈ 2 800 kcal.
        let nutrition = (0..<21).map { NutritionDay(date: date(daysAgo: $0), kcal: 2800, protein: 140, carbs: 350, fat: 80) }
        let weights = (0..<21).map { DayValue(date: date(daysAgo: $0), value: 72) }
        let expenditure = NutritionPlanner.adaptiveExpenditure(nutrition: nutrition, weights: weights, today: today)
        #expect(expenditure.map { abs($0 - 2800) < 1 } == true)
    }
}

struct ConnectorDecodingTests {
    @Test func decodesOpenFoodFactsProduct() throws {
        let json = """
        {"status":1,"product":{"code":"3017620422003","product_name":"Nutella","brands":"Ferrero, Nutella",
        "serving_quantity":"15","nutriments":{"energy-kcal_100g":539,"proteins_100g":6.3,"carbohydrates_100g":57.5,
        "fat_100g":30.9,"sugars_100g":56.3,"salt_100g":0.107,"energy_unit":"kcal"}}}
        """
        let response = try JSONDecoder().decode(OpenFoodFacts.ProductResponse.self, from: Data(json.utf8))
        let product = OpenFoodFacts.normalize(response.product!, fallbackBarcode: nil)
        #expect(product?.name == "Nutella")
        #expect(product?.brand == "Ferrero")
        #expect(product?.kcal100 == 539)
        #expect(product?.servingGrams == 15)
    }

    @Test func decodesIntervalsActivity() throws {
        let json = """
        [{"id":"i98765","start_date_local":"2026-10-04T09:30:00","type":"GravelRide","name":"Sortie gravel",
        "moving_time":10800,"distance":72000,"icu_training_load":165,"icu_average_watts":158,
        "icu_weighted_avg_watts":176,"average_heartrate":139,"icu_intensity":85.4,"calories":1650}]
        """
        let activities = try JSONDecoder().decode([IntervalsClient.Activity].self, from: Data(json.utf8))
        #expect(activities.first?.sport == .cycling)
        #expect(activities.first?.intensityFactor.map { abs($0 - 0.854) < 0.001 } == true)
        #expect(IntervalsClient.parseLocal(activities.first?.startDateLocal) != nil)
    }

    @Test func decodesIntervalsWellness() throws {
        let json = """
        [{"id":"2026-10-04","restingHR":47,"hrv":61.5,"sleepSecs":27000,"sleepScore":82,"readiness":74,"weight":72.4}]
        """
        let wellness = try JSONDecoder().decode([IntervalsClient.Wellness].self, from: Data(json.utf8))
        #expect(wellness.first?.sleepSecs == 27000)
        #expect(wellness.first?.hrv == 61.5)
    }
}
