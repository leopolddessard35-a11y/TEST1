import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Le modèle de langage sert à la narration, jamais au calcul : il reformule des chiffres déjà calculés.
/// Utilise le modèle Apple Intelligence intégré à l'iPhone (local, privé). Sans lui, rien ne s'affiche.
enum WeeklyNarrator {
    static func narrate(report: WeeklyReport, review: WeeklyReport.Review) async -> String? {
        #if canImport(FoundationModels)
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        var facts: [String] = []
        if let recovery = report.current.recovery { facts.append(String(format: "récupération moyenne %.0f/100", recovery)) }
        if let before = report.previous.recovery { facts.append(String(format: "semaine précédente %.0f", before)) }
        if let sleep = report.current.sleepHours { facts.append(String(format: "sommeil moyen %.1f h", sleep)) }
        facts.append(String(format: "entraînement %.1f h", review.doneHours))
        facts.append("point fort : \(review.strongPoint)")
        facts.append("vigilance : \(review.vigilance)")
        facts.append("ajustement : \(review.adjustment)")
        let instructions = """
        Tu es un coach sportif. Reformule ces faits en 2 phrases en français, ton factuel et bienveillant, \
        sans culpabiliser, sans ajouter aucun chiffre ni conseil qui ne figure pas dans les faits.
        """
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: facts.joined(separator: " ; "))
            return response.content
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }
}
