#if canImport(SwiftData)
import Foundation
import SwiftData

/// SwiftData-backed repository for the single-row `UserProfileRecord`.
public struct SwiftDataUserProfileRepository: Sendable {
    public let container: ModelContainer
    private let outboundQueue: any OutboundSyncQueue

    public init(container: ModelContainer, outboundQueue: (any OutboundSyncQueue)? = nil) {
        self.container = container
        self.outboundQueue = outboundQueue ?? NoOpOutboundSyncQueue()
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

        let target: UserProfileRecord
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
            target = existing
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
            target = record
        }

        try stageUpsert(for: target, into: context)
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
        try stageUpsert(for: profile, into: context)
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
    private let outboundQueue: any OutboundSyncQueue

    public init(container: ModelContainer, outboundQueue: (any OutboundSyncQueue)? = nil) {
        self.container = container
        self.outboundQueue = outboundQueue ?? NoOpOutboundSyncQueue()
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
        try upsertPlan(workouts, in: context)
        try context.save()
    }

    /// Stage a training plan upsert into an existing context.
    @MainActor
    public func upsertPlan(_ workouts: [WeeklyWorkout], in context: ModelContext) throws {
        var descriptor = FetchDescriptor<TrainingPlanRecord>()
        descriptor.fetchLimit = 1

        guard let json = SyncPayloadCodec.encode(workouts) else { return }

        let target: TrainingPlanRecord
        if let existing = try context.fetch(descriptor).first {
            existing.workoutsJSON = json
            existing.updatedAt = .now
            target = existing
        } else {
            let record = TrainingPlanRecord(workoutsJSON: json)
            context.insert(record)
            target = record
        }

        try stageUpsert(for: target, into: context)
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
        let sortedWorkouts = workouts.sorted { $0.dayOfWeek < $1.dayOfWeek }
        let todayWeekday = WeeklyWorkout.trainingWeekday(for: date)
        // Find next workout on or after today
        if let next = sortedWorkouts.first(where: { $0.dayOfWeek >= todayWeekday }) {
            return next
        }
        return sortedWorkouts.first
    }
}

/// SwiftData-backed repository for `CoachMemoryRecord`.
public struct SwiftDataCoachMemoryRepository: Sendable {
    public let container: ModelContainer
    private let outboundQueue: any OutboundSyncQueue
    private let telemetrySink: (any TelemetrySink)?

    // VOL-79: retention policy. `CoachMemoryRecord` rows carry free-form
    // prompt/response text (potentially PII) and were previously appended
    // on every coaching turn with no pruning. Enforce both a time-based
    // TTL AND a size cap — whichever trims more wins on any given append.
    // `private static let` keeps these values grep-able and easy to tune.
    private static let retentionDays = 30
    private static let maxRows = 50

    public init(
        container: ModelContainer,
        outboundQueue: (any OutboundSyncQueue)? = nil,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.container = container
        self.outboundQueue = outboundQueue ?? NoOpOutboundSyncQueue()
        self.telemetrySink = telemetrySink
    }

    /// Append a new memory entry. Also prunes stale/overflow rows per the
    /// VOL-79 retention policy. Prune failures don't fail the append —
    /// they're logged as a telemetry warning so the local write still
    /// persists even if the sweep errors out.
    @MainActor
    public func append(content: String, theme: String = "") throws {
        let context = ModelContext(container)
        let record = CoachMemoryRecord(content: content, theme: theme)
        context.insert(record)
        try stageUpsert(for: record, into: context)
        try context.save()

        do {
            try performRetentionSweep(on: context)
        } catch {
            // VOL-79: prune MUST NOT fail the append. The user's newly
            // appended memory row is already saved; if the sweep errors
            // we just log and return.
            telemetrySink?.record(
                TelemetryEvent(
                    category: "persistence",
                    name: "coach.memory.prune.failed",
                    severity: .warning,
                    message: "Coach memory retention sweep failed after append",
                    metadata: ["error": String(describing: error)]
                )
            )
        }
    }

    /// One-shot retention sweep, typically called at launch to clean up
    /// pre-policy rows on existing installs. Runs the same logic as the
    /// post-append prune but independent of any append. Unlike the
    /// in-append prune this throws on error, letting the caller decide
    /// whether to log or ignore.
    @MainActor
    public func pruneLegacyRows() throws {
        let context = ModelContext(container)
        try performRetentionSweep(on: context)
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

    /// VOL-79 retention sweep. Fetches all rows sorted by `createdAt`
    /// descending, keeps the first `maxRows` that are within
    /// `retentionDays`, and deletes the rest in one batched sweep. Also
    /// stages outbound delete tombstones so other devices drop the same
    /// rows once the prune syncs.
    @MainActor
    private func performRetentionSweep(on context: ModelContext) throws {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        let descriptor = FetchDescriptor<CoachMemoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allRecords = try context.fetch(descriptor)

        // Compute the keep set: the first `maxRows` rows that are still
        // within the TTL. Rows outside the TTL are always pruned, even if
        // we're under the size cap.
        var keepCount = 0
        var rowsToDelete: [CoachMemoryRecord] = []
        for record in allRecords {
            if keepCount < Self.maxRows && record.createdAt >= cutoff {
                keepCount += 1
            } else {
                rowsToDelete.append(record)
            }
        }

        guard rowsToDelete.isEmpty == false else { return }

        // VOL-67 Codex P1 fixup: tombstone timestamp must be the actual
        // deletion wall-clock time, not `createdAt`. Applies here too —
        // see `pruneOlderThan` for the full rationale.
        let deletedAt = Date()
        for record in rowsToDelete {
            let identifier = record.identifier
            context.delete(record)
            outboundQueue.stage(
                into: context,
                recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
                recordIdentifier: identifier,
                operation: CloudSyncRecord.Operation.delete.rawValue,
                payloadJSON: "",
                queuedAt: deletedAt
            )
        }
        try context.save()

        telemetrySink?.record(
            TelemetryEvent(
                category: "persistence",
                name: "coach.memory.pruned",
                severity: .info,
                message: "Pruned stale coach memory rows per retention policy",
                metadata: [
                    "removedCount": String(rowsToDelete.count),
                    "retentionDays": String(Self.retentionDays),
                    "maxRows": String(Self.maxRows)
                ]
            )
        )
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
        // VOL-67 Codex P1 fixup: tombstone timestamp must be the actual
        // deletion wall-clock time, not the record's `createdAt`, so the
        // outbound delete doesn't get invalidated by a newer inbound
        // version that happens to sit between `createdAt` and the delete.
        // VOL-67 Codex P2 fixup: stage queue rows into the same context
        // as the deletes and commit everything in one atomic save.
        //
        // VOL-67 Copilot (fixup #19): empty `payloadJSON` on the delete
        // tombstone. See comment in `SwiftDataWorkoutRepository.deleteWorkout`
        // — the sync pipeline ignores the delete payload, so serializing
        // the full memory body just retained deleted user content in
        // the outbound queue and CloudKit tombstone for no benefit.
        let deletedAt = Date()
        for record in oldRecords {
            let identifier = record.identifier
            context.delete(record)
            outboundQueue.stage(
                into: context,
                recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
                recordIdentifier: identifier,
                operation: CloudSyncRecord.Operation.delete.rawValue,
                payloadJSON: "",
                queuedAt: deletedAt
            )
        }
        try context.save()
    }

    /// Delete a single memory entry by identifier.
    @MainActor
    public func deleteMemory(identifier: String) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<CoachMemoryRecord>(
            predicate: #Predicate<CoachMemoryRecord> { record in
                record.identifier == identifier
            }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else { return }

        // VOL-67 Codex P1 + P2 fixups: actual deletion wall-clock as
        // the tombstone timestamp AND atomic stage-then-save so the
        // delete and the queue row commit together.
        //
        // VOL-67 Copilot (fixup #19): empty `payloadJSON` on delete.
        // See the bulk-prune path above + the workout-delete path for
        // the full rationale.
        let deletedAt = Date()
        context.delete(record)
        outboundQueue.stage(
            into: context,
            recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
            recordIdentifier: identifier,
            operation: CloudSyncRecord.Operation.delete.rawValue,
            payloadJSON: "",
            queuedAt: deletedAt
        )
        try context.save()
    }
}

// VOL-67 Codex P2 fixup: these helpers stage the outbound queue row
// into the caller-provided context rather than creating a new context
// and saving independently. Every repository mutation above follows
// the pattern: insert/modify record → stageUpsert → `context.save()` —
// so a queue write failure can't leave the primary record persisted
// without its sync row.
// VOL-67 Codex P2 (fixup #28): all three staging helpers throw
// `OutboundQueueStagingError.payloadEncodingFailed` when the record
// can't be serialized. Before the fix they silently returned,
// letting the caller commit the primary record change without a
// matching queue row — local write persisted but never sync'd. Now
// the error aborts the enclosing repository method before
// `context.save()` runs, rolling back both the record mutation
// and the queue row (because neither was saved) and surfacing
// the failure to the caller.
extension SwiftDataUserProfileRepository {
    @MainActor
    fileprivate func stageUpsert(for profile: UserProfileRecord, into context: ModelContext) throws {
        guard let payloadJSON = SyncPayloadCodec.encodeUserProfilePayload(from: profile) else {
            throw OutboundQueueStagingError.payloadEncodingFailed(
                recordType: CloudSyncRecord.Kind.userProfile.rawValue,
                recordIdentifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier
            )
        }
        outboundQueue.stage(
            into: context,
            recordType: CloudSyncRecord.Kind.userProfile.rawValue,
            recordIdentifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier,
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: payloadJSON,
            queuedAt: profile.updatedAt
        )
    }
}

extension SwiftDataTrainingPlanRepository {
    @MainActor
    fileprivate func stageUpsert(for plan: TrainingPlanRecord, into context: ModelContext) throws {
        guard let payloadJSON = SyncPayloadCodec.encodeTrainingPlanPayload(from: plan) else {
            throw OutboundQueueStagingError.payloadEncodingFailed(
                recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
                recordIdentifier: CloudSyncRecord.Kind.trainingPlan.defaultIdentifier
            )
        }
        outboundQueue.stage(
            into: context,
            recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
            recordIdentifier: CloudSyncRecord.Kind.trainingPlan.defaultIdentifier,
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: payloadJSON,
            queuedAt: plan.updatedAt
        )
    }
}

extension SwiftDataCoachMemoryRepository {
    @MainActor
    fileprivate func stageUpsert(for record: CoachMemoryRecord, into context: ModelContext) throws {
        guard let payloadJSON = SyncPayloadCodec.encodeCoachMemoryPayload(from: record) else {
            throw OutboundQueueStagingError.payloadEncodingFailed(
                recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
                recordIdentifier: record.identifier
            )
        }
        outboundQueue.stage(
            into: context,
            recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
            recordIdentifier: record.identifier,
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: payloadJSON,
            queuedAt: record.createdAt
        )
    }
}
#endif
