import Foundation

/// Une même sortie peut arriver plusieurs fois (Zwift + Garmin, par exemple).
enum ActivityDeduplicator {
    static func isSameSession(sportA: Sport, startA: Date, durationA: Double,
                              sportB: Sport, startB: Date, durationB: Double) -> Bool {
        let sameFamily = sportA == sportB || (sportA.isCycling && sportB.isCycling)
        guard sameFamily else { return false }
        let startGap = abs(startA.timeIntervalSince(startB))
        let longest = max(durationA, durationB, 1)
        let durationGap = abs(durationA - durationB) / longest
        return startGap < 15 * 60 && durationGap < 0.2
    }
}
