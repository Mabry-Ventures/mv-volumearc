import Foundation
#if canImport(SwiftData)
import SwiftData

/// Applies remote sync records to local SwiftData repositories.
/// Uses last-write-wins based on the record's `modifiedAt` timestamp.
public struct DefaultSyncPayloadApplier: Sendable {
    public let workoutRepository: SwiftDataWorkoutRepository
    public let coachMemoryRepository: SwiftDataCoachMemoryRepository
    public let userProfileRepository: SwiftDataUserProfileRepository
    public let trainingPlanRepository: SwiftDataTrainingPlanRepository
    // VOL-74: promoted from `private` to `internal` so the per-kind
    // apply methods can access them from a sibling extension file.
    internal let telemetrySink: (any TelemetrySink)?
    internal let outboundQueue: (any OutboundSyncQueue)?

    public init(
        workoutRepository: SwiftDataWorkoutRepository,
        coachMemoryRepository: SwiftDataCoachMemoryRepository,
        userProfileRepository: SwiftDataUserProfileRepository,
        trainingPlanRepository: SwiftDataTrainingPlanRepository,
        telemetrySink: (any TelemetrySink)? = nil,
        outboundQueue: (any OutboundSyncQueue)? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.coachMemoryRepository = coachMemoryRepository
        self.userProfileRepository = userProfileRepository
        self.trainingPlanRepository = trainingPlanRepository
        self.telemetrySink = telemetrySink
        self.outboundQueue = outboundQueue
    }

    /// Apply a pull result to the local repositories.
    @MainActor
    public func apply(result: CloudSyncPullResult) async throws {
        for record in result.changedRecords {
            if record.operation == .delete {
                try applyDeletion(record)
            } else {
                try applyRecord(record)
            }
        }
        for deletedID in result.deletedRecordIDs {
            try applyDeletion(identifier: deletedID)
        }
    }

    @MainActor
    private func applyRecord(_ record: CloudSyncRecord) throws {
        switch record.kind {
        case .workout:
            try applyWorkout(record)
        case .userProfile:
            try applyUserProfile(record)
        case .trainingPlan:
            try applyTrainingPlan(record)
        case .coachMemory:
            try applyCoachMemory(record)
        }
    }

    /// VOL-67 Codex P1 (fixup #18): check whether the outbound queue
    /// holds a pending delete tombstone for `(kind, recordIdentifier)`
    /// whose `queuedAt` is strictly newer than `inboundTimestamp`.
    ///
    /// Used by the per-kind apply methods' "no existing local record"
    /// branch to avoid resurrecting a record the user just deleted.
    /// Scenario: `syncCycle()` pulls before pushing. The pull returns
    /// an inbound upsert for a record whose local row was already
    /// removed by a queued delete. Without this check, the apply path
    /// would insert the record back into the local store; the
    /// subsequent push would send the tombstone to CloudKit (deleting
    /// the server copy) but the newly-reinserted local row would
    /// survive, leaving the UI showing a zombie record until the next
    /// pull/apply cycle noticed the divergence.
    ///
    /// Identifier matching canonicalizes via `Kind.parse` +
    /// `canonicalQueueIdentifier(from:)` so the check also catches
    /// legacy-form queue rows (e.g., `recordType="userProfile"`
    /// matching against canonical `.userProfile` kind). Strict `>`
    /// matches the applier's `shouldApply` semantics: equal timestamps
    /// give priority to the inbound record, so only delete intents
    /// that are strictly newer than the inbound modification suppress
    /// the resurrection.
    ///
    /// VOL-67 Copilot (fixup #19): delegates to the queue's
    /// `hasPendingDeleteTombstone` method, which pushes the identifier
    /// + operation + timestamp filter into SwiftData via `#Predicate`.
    /// Previously this scanned the full pending-records list in
    /// application code, which was O(n) per inbound insert and could
    /// noticeably slow the pull/apply phase on devices with a large
    /// offline backlog. The predicate-narrowed fetch returns at most
    /// a handful of rows, so this check is now effectively O(1) per
    /// inbound record.
    @MainActor
    internal func hasNewerLocalDeleteTombstone(
        kind: CloudSyncRecord.Kind,
        recordIdentifier: String,
        inboundTimestamp: Date
    ) throws -> Bool {
        guard let outboundQueue else { return false }

        // Build the candidate identifier set: canonical form plus any
        // singleton long-form alias (legacy rows may use either).
        let canonicalID = kind.canonicalQueueIdentifier(from: recordIdentifier)
        var candidateIdentifiers: Set<String> = [canonicalID, recordIdentifier]
        if kind.isSingleton {
            candidateIdentifiers.insert(kind.defaultIdentifier)
            switch kind {
            case .userProfile:
                candidateIdentifiers.insert("userProfile")
            case .trainingPlan:
                candidateIdentifiers.insert("trainingPlan")
            case .workout, .coachMemory:
                break
            }
        }

        // Build the candidate record-type set: canonical + any known
        // long-form alias for this kind.
        var candidateRecordTypes: Set<String> = [kind.rawValue]
        switch kind {
        case .userProfile:
            candidateRecordTypes.insert("userProfile")
        case .trainingPlan:
            candidateRecordTypes.insert("trainingPlan")
        case .coachMemory:
            candidateRecordTypes.insert("coachMemory")
        case .workout:
            break
        }

        return try outboundQueue.hasPendingDeleteTombstone(
            candidateRecordTypes: candidateRecordTypes,
            candidateIdentifiers: candidateIdentifiers,
            newerThan: inboundTimestamp
        )
    }

    @MainActor
    internal func recordSuppressedInboundInsert(
        kind: CloudSyncRecord.Kind,
        recordIdentifier: String,
        inboundTimestamp: Date
    ) {
        telemetrySink?.record(TelemetryEvent(
            category: "sync",
            name: "inbound_upsert_suppressed_by_tombstone",
            severity: .info,
            message: "Pull upsert for \(kind.rawValue)/\(recordIdentifier) suppressed: local delete tombstone is newer than inbound",
            metadata: [
                "recordType": kind.rawValue,
                "recordIdentifier": recordIdentifier,
                "inboundTimestamp": ISO8601DateFormatter().string(from: inboundTimestamp),
            ]
        ))
    }

    @MainActor
    private func applyDeletion(identifier: String) throws {
        // Best-effort fallback for legacy deleted-record callbacks that don't
        // include a record kind. The identifier is matched against each
        // entity store; at most one hit is expected.
        let context = ModelContext(workoutRepository.container)

        // VOL-67 Codex P2 (fixup #7): accept both the current canonical
        // singleton identifier and the pre-rename legacy long form.
        // A legacy CK delete callback for "userProfile" must still
        // resolve to the profile entity and clear the canonical
        // "profile" queue row.
        let profileCanonical = CloudSyncRecord.Kind.userProfile.defaultIdentifier
        let planCanonical = CloudSyncRecord.Kind.trainingPlan.defaultIdentifier
        let isProfileIdentifier = (identifier == profileCanonical || identifier == "userProfile")
        let isPlanIdentifier = (identifier == planCanonical || identifier == "trainingPlan")

        if isProfileIdentifier {
            var profileDescriptor = FetchDescriptor<UserProfileRecord>()
            profileDescriptor.fetchLimit = 1
            if let profile = try context.fetch(profileDescriptor).first {
                context.delete(profile)
            }
        }

        if isPlanIdentifier {
            var planDescriptor = FetchDescriptor<TrainingPlanRecord>()
            planDescriptor.fetchLimit = 1
            if let plan = try context.fetch(planDescriptor).first {
                context.delete(plan)
            }
        }

        var workoutDescriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == identifier
            }
        )
        workoutDescriptor.fetchLimit = 1
        if let workout = try context.fetch(workoutDescriptor).first {
            context.delete(workout)
        }

        var memoryDescriptor = FetchDescriptor<CoachMemoryRecord>(
            predicate: #Predicate<CoachMemoryRecord> { memory in
                memory.identifier == identifier
            }
        )
        memoryDescriptor.fetchLimit = 1
        if let memory = try context.fetch(memoryDescriptor).first {
            context.delete(memory)
        }

        try context.save()

        // VOL-67 fixup: the legacy callback doesn't tell us which record
        // kind the deletion applies to, so sweep the queue for every kind.
        // For non-singleton kinds (workout, coachMemory), pass the
        // identifier through. For singletons, sweep the canonical queue
        // identifier only when the inbound ID looks like that singleton
        // (so a workout-UUID delete doesn't spuriously clear a queued
        // profile row).
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: identifier,
            olderThan: nil
        )
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
            recordIdentifier: identifier,
            olderThan: nil
        )
        if isProfileIdentifier {
            try outboundQueue?.invalidateEntries(
                recordType: CloudSyncRecord.Kind.userProfile.rawValue,
                recordIdentifier: profileCanonical,
                olderThan: nil
            )
        }
        if isPlanIdentifier {
            try outboundQueue?.invalidateEntries(
                recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
                recordIdentifier: planCanonical,
                olderThan: nil
            )
        }
    }

    @MainActor
    private func applyDeletion(_ record: CloudSyncRecord) throws {
        let context = ModelContext(workoutRepository.container)

        switch record.kind {
        case .workout:
            var descriptor = FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate<WorkoutRecord> { workout in
                    workout.identifier == record.identifier
                }
            )
            descriptor.fetchLimit = 1
            if let workout = try context.fetch(descriptor).first {
                context.delete(workout)
            }
        case .userProfile:
            var descriptor = FetchDescriptor<UserProfileRecord>()
            descriptor.fetchLimit = 1
            if let profile = try context.fetch(descriptor).first {
                context.delete(profile)
            }
        case .trainingPlan:
            var descriptor = FetchDescriptor<TrainingPlanRecord>()
            descriptor.fetchLimit = 1
            if let plan = try context.fetch(descriptor).first {
                context.delete(plan)
            }
        case .coachMemory:
            var descriptor = FetchDescriptor<CoachMemoryRecord>(
                predicate: #Predicate<CoachMemoryRecord> { memory in
                    memory.identifier == record.identifier
                }
            )
            descriptor.fetchLimit = 1
            if let memory = try context.fetch(descriptor).first {
                context.delete(memory)
            }
        }

        try context.save()

        // VOL-67 fixup: unconditionally invalidate every queued entry for
        // this record. A delete is authoritative — we never want a stale
        // queued upsert to resurrect a record that was deleted on another
        // device. `olderThan: nil` clears the queue slot regardless of
        // timestamp for the exact `(recordType, recordIdentifier)`.
        // Normalize singleton identifiers to the canonical queue form
        // so a legacy CK delete for "userProfile" still clears the
        // queued "profile" row.
        try outboundQueue?.invalidateEntries(
            recordType: record.kind.rawValue,
            recordIdentifier: record.kind.canonicalQueueIdentifier(from: record.identifier),
            olderThan: nil
        )
    }

    // VOL-74: promoted from `private` to `internal` so the per-kind
    // apply methods (now in SyncPayloadApplier+PerKind.swift) can call
    // this same-type helper across files. Swift `private` is scoped to
    // the defining file, so a sibling extension cannot reach a `private`
    // member even within the same module.
    internal func shouldApply(
        kind: CloudSyncRecord.Kind,
        identifier: String,
        localTimestamp: Date,
        inboundTimestamp: Date
    ) -> Bool {
        guard localTimestamp > inboundTimestamp else { return true }

        telemetrySink?.record(TelemetryEvent(
            category: "sync",
            name: "sync_conflict_local_wins",
            severity: .info,
            message: "Dropped older inbound sync payload for \(kind.rawValue) \(identifier)",
            metadata: [
                "recordType": kind.rawValue,
                "identifier": identifier,
                "localTimestamp": ISO8601DateFormatter().string(from: localTimestamp),
                "inboundTimestamp": ISO8601DateFormatter().string(from: inboundTimestamp),
            ]
        ))

        return false
    }
}
#endif
