import SwiftUI
import SwiftData

/// Charge les données et fournit le calcul du coach à la vue qu'il contient.
struct SnapshotReader<Content: View>: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \DailyWellness.day) private var wellness: [DailyWellness]
    @Query(sort: \CardioActivity.start) private var activities: [CardioActivity]
    @Query(sort: \StrengthWorkout.start) private var strength: [StrengthWorkout]
    @Query(sort: \Unavailability.start) private var unavailabilities: [Unavailability]
    @Query(sort: \Injury.start) private var injuries: [Injury]
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query(sort: \PlannedWorkout.date) private var planned: [PlannedWorkout]
    @Query(sort: \LifeActivity.date) private var lifeActivities: [LifeActivity]
    @Query(sort: \Symptom.date) private var symptoms: [Symptom]
    @Query private var shoes: [Shoe]
    @Query private var profiles: [AthleteProfile]

    private let content: (AthleteProfile, CoachSnapshot) -> Content

    init(@ViewBuilder content: @escaping (AthleteProfile, CoachSnapshot) -> Content) {
        self.content = content
    }

    var body: some View {
        if let profile = profiles.first {
            let snapshot = app.snapshotCache.snapshot(for: cacheKey(profile)) {
                CoachSnapshot.build(profile: profile, wellness: wellness, activities: activities, strength: strength,
                                    unavailabilities: unavailabilities, injuries: injuries, foods: foods, planned: planned,
                                    lifeActivities: lifeActivities, symptoms: symptoms, shoes: shoes)
            }
            content(profile, snapshot)
        } else {
            ProgressView()
        }
    }

    /// Empreinte des données : si rien n'a changé, le calcul précédent est réutilisé.
    private func cacheKey(_ profile: AthleteProfile) -> Int {
        var hasher = Hasher()
        hasher.combine(app.dataVersion)
        hasher.combine(Calendar.current.startOfDay(for: .now))
        hasher.combine(wellness.count)
        hasher.combine(wellness.last?.day)
        hasher.combine(activities.count)
        hasher.combine(activities.last?.start)
        hasher.combine(strength.count)
        hasher.combine(strength.last?.start)
        hasher.combine(unavailabilities.count)
        hasher.combine(injuries.count)
        hasher.combine(injuries.filter(\.isActive).count)
        hasher.combine(foods.count)
        hasher.combine(foods.reduce(0) { $0 + $1.grams })
        hasher.combine(planned.count)
        hasher.combine(lifeActivities.count)
        hasher.combine(symptoms.count)
        hasher.combine(shoes.count)
        hasher.combine(profile.ftp)
        hasher.combine(profile.cyclingLTHR)
        hasher.combine(profile.runningLTHR)
        hasher.combine(profile.maxHeartRate)
        hasher.combine(profile.weightKg)
        hasher.combine(profile.heightCm)
        hasher.combine(profile.birthYear)
        hasher.combine(profile.sexRaw)
        hasher.combine(profile.raceDate)
        hasher.combine(profile.targetRaceCTL)
        hasher.combine(profile.weeklyHoursAvailable)
        hasher.combine(profile.strengthSessionsPerWeek)
        hasher.combine(profile.sleepNeedHours)
        return hasher.finalize()
    }
}
