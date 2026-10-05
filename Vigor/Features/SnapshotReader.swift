import SwiftUI
import SwiftData

/// Charge les données et fournit le calcul du coach à la vue qu'il contient.
struct SnapshotReader<Content: View>: View {
    @Query(sort: \DailyWellness.day) private var wellness: [DailyWellness]
    @Query(sort: \CardioActivity.start) private var activities: [CardioActivity]
    @Query(sort: \StrengthWorkout.start) private var strength: [StrengthWorkout]
    @Query(sort: \Unavailability.start) private var unavailabilities: [Unavailability]
    @Query(sort: \Injury.start) private var injuries: [Injury]
    @Query private var profiles: [AthleteProfile]

    private let content: (AthleteProfile, CoachSnapshot) -> Content

    init(@ViewBuilder content: @escaping (AthleteProfile, CoachSnapshot) -> Content) {
        self.content = content
    }

    var body: some View {
        if let profile = profiles.first {
            content(profile, CoachSnapshot.build(
                profile: profile,
                wellness: wellness,
                activities: activities,
                strength: strength,
                unavailabilities: unavailabilities,
                injuries: injuries))
        } else {
            ProgressView()
        }
    }
}
