#if canImport(SwiftData)
import Foundation
import SwiftData

/// SwiftData-backed repository for the single-row `UserProfileRecord`.
public struct SwiftDataUserProfileRepository: Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Fetch the user profile, if one exists.
    @MainActor
    public func loadProfile() throws -> UserProfileRecord? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<UserProfileRecord>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Create or update the user profile. Single-row pattern.
    @MainActor
    public func upsertProfile(_ profile: UserProfileDefaults) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<UserProfileRecord>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            existing.name = profile.name
            existing.coachingStyle = profile.coachingStyle.rawValue
            existing.privacyMode = profile.privacyMode.rawValue
            existing.advancementLevel = profile.advancementLevel.rawValue
            existing.availableEquipmentCSV = profile.availableEquipment.map(\.rawValue).sorted().joined(separator: ",")
            existing.preferredRepRangeLower = profile.preferredRepRangeLower
            existing.preferredRepRangeUpper = profile.preferredRepRangeUpper
            existing.sessionTimeBudgetMinutes = profile.sessionTimeBudgetMinutes
            existing.weeklyTrainingDays = profile.weeklyTrainingDays
            existing.updatedAt = .now
        } else {
            let record = UserProfileRecord(
                name: profile.name,
                coachingStyle: profile.coachingStyle.rawValue,
                privacyMode: profile.privacyMode.rawValue,
                advancementLevel: profile.advancementLevel.rawValue,
                availableEquipmentCSV: profile.availableEquipment.map(\.rawValue).sorted().joined(separator: ","),
                preferredRepRangeLower: profile.preferredRepRangeLower,
                preferredRepRangeUpper: profile.preferredRepRangeUpper,
                sessionTimeBudgetMinutes: profile.sessionTimeBudgetMinutes,
                weeklyTrainingDays: profile.weeklyTrainingDays
            )
            context.insert(record)
        }

        try context.save()
    }

    /// Mark onboarding as complete.
    @MainActor
    public func markOnboardingComplete() throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<UserProfileRecord>()
        descriptor.fetchLimit = 1
        guard let profile = try context.fetch(descriptor).first else { return }
        profile.onboardingCompleted = true
        profile.updatedAt = .now
        try context.save()
    }

    /// Check whether onboarding has been completed.
    @MainActor
    public func isOnboardingComplete() throws -> Bool {
        try loadProfile()?.onboardingCompleted ?? false
    }

    /// Build an `AthleteProfile` projection from the persisted profile.
    @MainActor
    public func athleteProfile() throws -> AthleteProfile {
        guard let record = try loadProfile() else {
            return VolumeArcProductDefaults.athleteProfile
        }
        let equipment: Set<Equipment> = Set(
            record.availableEquipmentCSV.split(separator: ",")
                .compactMap { Equipment(rawValue: String($0)) }
        )
        return AthleteProfile(
            name: record.name,
            coachingStyle: CoachingStyle(rawValue: record.coachingStyle) ?? .motivational,
            privacyMode: PrivacyMode(rawValue: record.privacyMode) ?? .standard,
            advancementLevel: AdvancementLevel(rawValue: record.advancementLevel) ?? .intermediate,
            availableEquipment: equipment.isEmpty ? [.barbell, .dumbbell, .machine, .bodyweight] : equipment,
            sessionTimeBudgetMinutes: record.sessionTimeBudgetMinutes,
            weeklyTrainingDays: record.weeklyTrainingDays,
            preferredRepRange: record.preferredRepRangeLower...record.preferredRepRangeUpper
        )
    }
}

/// SwiftData-backed repository for the single-row `TrainingPlanRecord`.
public struct SwiftDataTrainingPlanRepository: Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Fetch the current training plan.
    @MainActor
    public func loadPlan() throws -> TrainingPlanRecord? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<TrainingPlanRecord>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Upsert the training plan from a list of weekly workouts.
    @MainActor
    public func upsertPlan(_ workouts: [WeeklyWorkout]) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<TrainingPlanRecord>()
        descriptor.fetchLimit = 1

        guard let json = SyncPayloadCodec.encode(workouts) else { return }

        if let existing = try context.fetch(descriptor).first {
            existing.workoutsJSON = json
            existing.updatedAt = .now
        } else {
            context.insert(TrainingPlanRecord(workoutsJSON: json))
        }

        try context.save()
    }

    /// Decode the persisted plan into `WeeklyWorkout` models.
    @MainActor
    public func weeklyWorkouts() throws -> [WeeklyWorkout] {
        guard let record = try loadPlan(),
              let data = record.workoutsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WeeklyWorkout].self, from: data)
        else {
            return []
        }
        return decoded
    }

    /// Get the next scheduled workout relative to today.
    @MainActor
    public func nextWorkout(from date: Date = .now) throws -> WeeklyWorkout? {
        let workouts = try weeklyWorkouts()
        guard !workouts.isEmpty else { return nil }
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: date)
        // Find next workout on or after today
        if let next = workouts.first(where: { $0.dayOfWeek >= todayWeekday }) {
            return next
        }
        return workouts.first
    }
}

/// SwiftData-backed repository for `CoachMemoryRecord`.
public struct SwiftDataCoachMemoryRepository: Sendable {
    public let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Append a new memory entry.
    @MainActor
    public func append(content: String, theme: String = "") throws {
        let context = ModelContext(container)
        context.insert(CoachMemoryRecord(content: content, theme: theme))
        try context.save()
    }

    /// Fetch the N most recent memory entries.
    @MainActor
    public func recent(limit: Int = 10) throws -> [CoachMemoryRecord] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CoachMemoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Build a `CoachMemory` projection for the progression engine.
    @MainActor
    public func coachMemory() throws -> CoachMemory {
        let records = try recent(limit: 20)
        let entries = records.map { record in
            CoachMemory.Entry(
                createdAt: record.createdAt,
                summary: record.content,
                theme: record.theme.isEmpty ? nil : record.theme
            )
        }
        return CoachMemory(entries: entries)
    }

    /// Delete all memory entries older than the given date (for retention).
    @MainActor
    public func pruneOlderThan(_ cutoff: Date) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CoachMemoryRecord>(
            predicate: #Predicate<CoachMemoryRecord> { record in
                record.createdAt < cutoff
            }
        )
        let oldRecords = try context.fetch(descriptor)
        for record in oldRecords {
            context.delete(record)
        }
        try context.save()
    }
}
#endif
