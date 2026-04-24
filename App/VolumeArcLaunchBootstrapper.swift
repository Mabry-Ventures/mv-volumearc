#if canImport(SwiftData)
import Foundation
import SwiftData
import VolumeArcCore

@MainActor
enum VolumeArcLaunchBootstrapper {
    /// VOL-99: number of deterministic history sessions seeded when
    /// `-PerfTestMode 1` is set. The perf suite's scroll test
    /// asserts frame rate / hitches while scrolling this many rows
    /// on the Today tab, matching the Linear acceptance criteria
    /// ("scrolling through workout history with 50 sessions loaded").
    static let perfTestSessionCount: Int = 50

    static func applyLaunchArguments(
        to container: ModelContainer,
        isUITestMode: Bool,
        skipOnboarding: Bool,
        seedFixtures: Bool,
        isPerfTestMode: Bool = false
    ) throws {
        // VOL-99: perf mode implies a deterministic seed, skipped
        // onboarding, and UI test mode (for accessibility identifiers
        // and no permission prompts). Unpack it into the regular flags
        // so the existing branch structure stays minimally changed.
        let resolvedUITestMode = isUITestMode || isPerfTestMode
        let resolvedSkipOnboarding = skipOnboarding || isPerfTestMode
        let resolvedSeedFixtures = seedFixtures || isPerfTestMode

        guard resolvedUITestMode || resolvedSkipOnboarding || resolvedSeedFixtures else { return }

        // Reset persisted state before applying any deterministic seed. The
        // seed path (`seedDeterministicFixtures`) inserts new workouts and
        // coach memories on every call, so without a reset, running with
        // `-SeedFixtures 1` across multiple launches would accumulate
        // duplicate fixture rows and the "deterministic" state would drift.
        //
        // `isUITestMode` alone also resets, for any test setup that doesn't
        // need fixtures but still wants a clean slate (e.g., the onboarding
        // gate test that verifies first-launch behavior).
        if resolvedUITestMode || resolvedSeedFixtures {
            try resetState(in: container)
        }

        if resolvedSkipOnboarding || resolvedSeedFixtures {
            try seedBaseState(
                into: container,
                profile: resolvedSeedFixtures ? deterministicUserProfile() : VolumeArcProductDefaults.userProfile,
                onboardingCompleted: resolvedSkipOnboarding
            )
        }

        if resolvedSeedFixtures {
            try seedDeterministicFixtures(
                into: container,
                extraSessionCount: isPerfTestMode ? perfTestSessionCount : 0
            )
        }
    }

    private static func resetState(in container: ModelContainer) throws {
        let context = ModelContext(container)

        for profile in try context.fetch(FetchDescriptor<UserProfileRecord>()) {
            context.delete(profile)
        }
        for trainingPlan in try context.fetch(FetchDescriptor<TrainingPlanRecord>()) {
            context.delete(trainingPlan)
        }
        for workout in try context.fetch(FetchDescriptor<WorkoutRecord>()) {
            context.delete(workout)
        }
        for memory in try context.fetch(FetchDescriptor<CoachMemoryRecord>()) {
            context.delete(memory)
        }
        for queuedChange in try context.fetch(FetchDescriptor<OutboundSyncQueueRecord>()) {
            context.delete(queuedChange)
        }

        try context.save()
    }

    private static func seedBaseState(
        into container: ModelContainer,
        profile: UserProfileDefaults,
        onboardingCompleted: Bool
    ) throws {
        let context = ModelContext(container)
        if let existingProfile = try context.fetch(FetchDescriptor<UserProfileRecord>()).first {
            existingProfile.name = profile.name
            existingProfile.coachingStyle = profile.coachingStyle.rawValue
            existingProfile.privacyMode = profile.privacyMode.rawValue
            existingProfile.advancementLevel = profile.advancementLevel.rawValue
            existingProfile.availableEquipmentCSV = profile.availableEquipment.map(\.rawValue).sorted().joined(separator: ",")
            existingProfile.preferredRepRangeLower = profile.preferredRepRangeLower
            existingProfile.preferredRepRangeUpper = profile.preferredRepRangeUpper
            existingProfile.sessionTimeBudgetMinutes = profile.sessionTimeBudgetMinutes
            existingProfile.weeklyTrainingDays = profile.weeklyTrainingDays
            existingProfile.onboardingCompleted = onboardingCompleted
            existingProfile.updatedAt = .now
        } else {
            context.insert(
                UserProfileRecord(
                    name: profile.name,
                    coachingStyle: profile.coachingStyle.rawValue,
                    privacyMode: profile.privacyMode.rawValue,
                    advancementLevel: profile.advancementLevel.rawValue,
                    availableEquipmentCSV: profile.availableEquipment.map(\.rawValue).sorted().joined(separator: ","),
                    preferredRepRangeLower: profile.preferredRepRangeLower,
                    preferredRepRangeUpper: profile.preferredRepRangeUpper,
                    sessionTimeBudgetMinutes: profile.sessionTimeBudgetMinutes,
                    weeklyTrainingDays: profile.weeklyTrainingDays,
                    onboardingCompleted: onboardingCompleted
                )
            )
        }

        if let existingPlan = try context.fetch(FetchDescriptor<TrainingPlanRecord>()).first {
            existingPlan.workoutsJSON = SyncPayloadCodec.encode(VolumeArcProductDefaults.weeklySchedule) ?? "[]"
            existingPlan.updatedAt = .now
        } else {
            context.insert(
                TrainingPlanRecord(
                    workoutsJSON: SyncPayloadCodec.encode(VolumeArcProductDefaults.weeklySchedule) ?? "[]"
                )
            )
        }
        try context.save()
    }

    private static func seedDeterministicFixtures(
        into container: ModelContainer,
        extraSessionCount: Int = 0
    ) throws {
        let context = ModelContext(container)
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: .now).addingTimeInterval(18 * 60 * 60)

        let fixturePlan = [
            WeeklyWorkout(dayOfWeek: 1, title: "Lower Strength"),
            WeeklyWorkout(dayOfWeek: 3, title: "Upper Strength"),
            WeeklyWorkout(dayOfWeek: 5, title: "Lower Volume"),
        ]

        if let plan = try context.fetch(FetchDescriptor<TrainingPlanRecord>()).first {
            plan.workoutsJSON = SyncPayloadCodec.encode(fixturePlan) ?? "[]"
            plan.updatedAt = .now
        }

        let memories = [
            CoachMemoryRecord(
                content: "Back squat has been moving cleanly when the brace stays locked in.",
                theme: "squat",
                createdAt: calendar.date(byAdding: .day, value: -1, to: anchor) ?? anchor
            ),
            CoachMemoryRecord(
                content: "Bench press responded well to a 2.5-pound jump after a smooth top set.",
                theme: "bench",
                createdAt: calendar.date(byAdding: .day, value: -3, to: anchor) ?? anchor
            ),
        ]
        for memory in memories {
            context.insert(memory)
        }

        for workout in deterministicWorkouts(relativeTo: anchor) {
            context.insert(workout)
        }

        // VOL-99: seed an additional deterministic history pool when
        // perf-test mode asks for it. The scroll perf test needs a
        // realistic list length (50 rows) to expose hitches and
        // frame-rate regressions; the three default fixtures above are
        // not enough.
        if extraSessionCount > 0 {
            for workout in deterministicHistoryPool(count: extraSessionCount, relativeTo: anchor) {
                context.insert(workout)
            }
        }

        try context.save()
    }

    /// VOL-99: produces a deterministic sequence of completed workouts
    /// spaced one day apart, walking backwards from the anchor. Used
    /// by perf-test mode to populate the dashboard with enough history
    /// to exercise the scroll performance gate.
    private static func deterministicHistoryPool(
        count: Int,
        relativeTo anchor: Date
    ) -> [WorkoutRecord] {
        guard count > 0 else { return [] }
        let templates: [(title: String, exercise: String, baseWeight: Double, reps: Int)] = [
            ("Lower Strength", "back-squat", 225, 5),
            ("Upper Strength", "bench-press", 155, 5),
            ("Lower Volume", "back-squat", 205, 8),
            ("Upper Volume", "bench-press", 135, 8),
            ("Pull Strength", "barbell-row", 145, 5),
            ("Hinge Day", "romanian-deadlift", 185, 6),
            ("Accessory", "walking-lunge", 40, 10),
        ]
        let hourStart: TimeInterval = -170 * 60 * 60

        return (0..<count).map { index in
            let template = templates[index % templates.count]
            let sessionStart = anchor.addingTimeInterval(hourStart - TimeInterval(index) * 24 * 60 * 60)
            let sessionEnd = sessionStart.addingTimeInterval(55 * 60)
            let sets: [SeedLoggedSet] = (0..<3).map { setIndex in
                SeedLoggedSet(
                    exerciseID: template.exercise,
                    set: WorkoutSetPerformance(
                        weight: template.baseWeight,
                        reps: template.reps,
                        rpe: 7.0 + Double(setIndex) * 0.5,
                        completedAt: sessionStart.addingTimeInterval(TimeInterval(setIndex) * 120)
                    )
                )
            }
            return makeWorkout(
                title: template.title,
                startedAt: sessionStart,
                completedAt: sessionEnd,
                sets: sets
            )
        }
    }

    private static func deterministicUserProfile() -> UserProfileDefaults {
        UserProfileDefaults(
            name: "Taylor",
            coachingStyle: .analytical,
            privacyMode: .standard,
            advancementLevel: .intermediate,
            availableEquipment: [.barbell, .dumbbell, .machine, .bodyweight],
            preferredRepRangeLower: 4,
            preferredRepRangeUpper: 8,
            sessionTimeBudgetMinutes: 60,
            weeklyTrainingDays: 4
        )
    }

    private static func deterministicWorkouts(relativeTo anchor: Date) -> [WorkoutRecord] {
        [
            makeWorkout(
                title: "Lower Strength",
                startedAt: anchor.addingTimeInterval(-(26 * 60 * 60)),
                completedAt: anchor.addingTimeInterval(-(25 * 60 * 60)),
                sets: [
                    SeedLoggedSet(exerciseID: "back-squat", set: WorkoutSetPerformance(weight: 225, reps: 5, rpe: 7.5, completedAt: anchor.addingTimeInterval(-(25 * 60 * 60)))),
                    SeedLoggedSet(exerciseID: "back-squat", set: WorkoutSetPerformance(weight: 225, reps: 5, rpe: 8.0, completedAt: anchor.addingTimeInterval(-(25 * 60 * 60) + 120))),
                    SeedLoggedSet(exerciseID: "romanian-deadlift", set: WorkoutSetPerformance(weight: 185, reps: 8, rpe: 7.0, completedAt: anchor.addingTimeInterval(-(25 * 60 * 60) + 360))),
                ]
            ),
            makeWorkout(
                title: "Upper Strength",
                startedAt: anchor.addingTimeInterval(-(74 * 60 * 60)),
                completedAt: anchor.addingTimeInterval(-(73 * 60 * 60)),
                sets: [
                    SeedLoggedSet(exerciseID: "bench-press", set: WorkoutSetPerformance(weight: 155, reps: 5, rpe: 7.5, completedAt: anchor.addingTimeInterval(-(73 * 60 * 60)))),
                    SeedLoggedSet(exerciseID: "bench-press", set: WorkoutSetPerformance(weight: 155, reps: 5, rpe: 8.0, completedAt: anchor.addingTimeInterval(-(73 * 60 * 60) + 120))),
                    SeedLoggedSet(exerciseID: "barbell-row", set: WorkoutSetPerformance(weight: 135, reps: 8, rpe: 7.0, completedAt: anchor.addingTimeInterval(-(73 * 60 * 60) + 360))),
                ]
            ),
            makeWorkout(
                title: "Lower Volume",
                startedAt: anchor.addingTimeInterval(-(122 * 60 * 60)),
                completedAt: anchor.addingTimeInterval(-(121 * 60 * 60)),
                sets: [
                    SeedLoggedSet(exerciseID: "back-squat", set: WorkoutSetPerformance(weight: 205, reps: 8, rpe: 7.0, completedAt: anchor.addingTimeInterval(-(121 * 60 * 60)))),
                    SeedLoggedSet(exerciseID: "walking-lunge", set: WorkoutSetPerformance(weight: 40, reps: 10, rpe: 6.5, completedAt: anchor.addingTimeInterval(-(121 * 60 * 60) + 180))),
                    SeedLoggedSet(exerciseID: "walking-lunge", set: WorkoutSetPerformance(weight: 40, reps: 10, rpe: 7.0, completedAt: anchor.addingTimeInterval(-(121 * 60 * 60) + 360))),
                ]
            ),
        ]
    }

    private static func makeWorkout(
        title: String,
        startedAt: Date,
        completedAt: Date,
        sets: [SeedLoggedSet]
    ) -> WorkoutRecord {
        let exerciseIDs = Array(Set(sets.map(\.exerciseID))).sorted().joined(separator: ",")
        let totalVolume = sets.reduce(0) { partialResult, loggedSet in
            partialResult + (loggedSet.set.weight * Double(loggedSet.set.reps))
        }
        let averageRPE = sets.map(\.set.rpe).reduce(0, +) / Double(max(sets.count, 1))
        let setsJSON: String
        if let data = try? JSONEncoder().encode(sets),
           let encoded = String(data: data, encoding: .utf8) {
            setsJSON = encoded
        } else {
            setsJSON = "[]"
        }

        return WorkoutRecord(
            title: title,
            startedAt: startedAt,
            completedAt: completedAt,
            durationMinutes: max(1, Int(completedAt.timeIntervalSince(startedAt) / 60)),
            exerciseIDsCSV: exerciseIDs,
            setsJSON: setsJSON,
            totalVolumeLoad: totalVolume,
            averageRPE: averageRPE,
            completedSetCount: sets.count,
            summary: "Deterministic fixture",
            updatedAt: completedAt
        )
    }
}

private struct SeedLoggedSet: Codable {
    let exerciseID: String
    let set: WorkoutSetPerformance
}
#endif
