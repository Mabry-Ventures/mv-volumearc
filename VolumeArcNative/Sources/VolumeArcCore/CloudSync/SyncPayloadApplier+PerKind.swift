import Foundation
#if canImport(SwiftData)
import SwiftData

// VOL-74: the per-kind apply methods live in this sibling extension
// file to keep `SyncPayloadApplier.swift` under the per-file line
// budget. Each method reapplies `@MainActor` explicitly because Swift
// does not propagate isolation from an extension declaration down to
// its member functions.
extension DefaultSyncPayloadApplier {
    @MainActor
    internal func applyWorkout(_ record: CloudSyncRecord) throws {
        guard let payload = SyncPayloadCodec.decodeWorkoutPayload(from: record.payloadJSON) else { return }

        let context = ModelContext(workoutRepository.container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == record.identifier
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            guard shouldApply(
                kind: record.kind,
                identifier: record.identifier,
                localTimestamp: existing.updatedAt,
                inboundTimestamp: payload.updatedAt
            ) else { return }

            existing.title = payload.title
            existing.startedAt = payload.startedAt
            existing.completedAt = payload.completedAt
            existing.durationMinutes = payload.durationMinutes
            existing.exerciseIDsCSV = payload.exerciseIDsCSV
            existing.setsJSON = payload.setsJSON
            existing.totalVolumeLoad = payload.totalVolumeLoad
            existing.averageRPE = payload.averageRPE
            existing.completedSetCount = payload.completedSetCount
            existing.summary = payload.summary
            existing.updatedAt = payload.updatedAt
        } else {
            // VOL-67 Codex P1 (fixup #18): don't resurrect a record the
            // user just deleted locally. If the outbound queue has a
            // strictly newer delete tombstone for this workout, the
            // pending delete represents more recent user intent than
            // the inbound upsert — inserting here would make the
            // deleted workout visually reappear, and the subsequent
            // push would delete it on the server without removing the
            // reinserted local row. Skip and let the next push apply
            // the tombstone.
            if try hasNewerLocalDeleteTombstone(
                kind: record.kind,
                recordIdentifier: record.identifier,
                inboundTimestamp: payload.updatedAt
            ) {
                recordSuppressedInboundInsert(
                    kind: record.kind,
                    recordIdentifier: record.identifier,
                    inboundTimestamp: payload.updatedAt
                )
                return
            }

            context.insert(WorkoutRecord(
                identifier: record.identifier,
                title: payload.title,
                startedAt: payload.startedAt,
                completedAt: payload.completedAt,
                durationMinutes: payload.durationMinutes,
                exerciseIDsCSV: payload.exerciseIDsCSV,
                setsJSON: payload.setsJSON,
                totalVolumeLoad: payload.totalVolumeLoad,
                averageRPE: payload.averageRPE,
                completedSetCount: payload.completedSetCount,
                summary: payload.summary,
                updatedAt: payload.updatedAt
            ))
        }

        try context.save()

        // VOL-67 fixup: once the inbound record has been applied locally,
        // invalidate any queued outbound entry for the same workout that's
        // older than the inbound timestamp. Without this, the stale queued
        // payload would overwrite the newly-pulled server state on the
        // next push and we'd be right back in the "local clobbers server"
        // divergence Codex flagged.
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: record.identifier,
            olderThan: payload.updatedAt
        )
    }

    @MainActor
    internal func applyUserProfile(_ record: CloudSyncRecord) throws {
        guard let payload = SyncPayloadCodec.decodeUserProfilePayload(from: record.payloadJSON) else { return }

        let context = ModelContext(userProfileRepository.container)
        var descriptor = FetchDescriptor<UserProfileRecord>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            guard shouldApply(
                kind: record.kind,
                identifier: record.identifier,
                localTimestamp: existing.updatedAt,
                inboundTimestamp: payload.updatedAt
            ) else { return }

            existing.name = payload.name
            existing.coachingStyle = payload.coachingStyle
            existing.privacyMode = payload.privacyMode
            existing.advancementLevel = payload.advancementLevel
            existing.availableEquipmentCSV = payload.availableEquipmentCSV
            existing.preferredRepRangeLower = payload.preferredRepRangeLower
            existing.preferredRepRangeUpper = payload.preferredRepRangeUpper
            existing.sessionTimeBudgetMinutes = payload.sessionTimeBudgetMinutes
            existing.weeklyTrainingDays = payload.weeklyTrainingDays
            existing.onboardingCompleted = payload.onboardingCompleted
            existing.updatedAt = payload.updatedAt
        } else {
            // VOL-67 Codex P1 (fixup #18): tombstone-wins check — same
            // resurrection race as workouts/memories. For singletons
            // the `recordIdentifier` canonicalizes to
            // `CloudSyncRecord.Kind.userProfile.defaultIdentifier`, so
            // any pending delete tombstone for this kind (under any
            // alias form) matches regardless of how it's stored.
            if try hasNewerLocalDeleteTombstone(
                kind: record.kind,
                recordIdentifier: record.identifier,
                inboundTimestamp: payload.updatedAt
            ) {
                recordSuppressedInboundInsert(
                    kind: record.kind,
                    recordIdentifier: record.identifier,
                    inboundTimestamp: payload.updatedAt
                )
                return
            }

            context.insert(UserProfileRecord(
                name: payload.name,
                coachingStyle: payload.coachingStyle,
                privacyMode: payload.privacyMode,
                advancementLevel: payload.advancementLevel,
                availableEquipmentCSV: payload.availableEquipmentCSV,
                preferredRepRangeLower: payload.preferredRepRangeLower,
                preferredRepRangeUpper: payload.preferredRepRangeUpper,
                sessionTimeBudgetMinutes: payload.sessionTimeBudgetMinutes,
                weeklyTrainingDays: payload.weeklyTrainingDays,
                onboardingCompleted: payload.onboardingCompleted,
                updatedAt: payload.updatedAt
            ))
        }

        try context.save()

        // VOL-67 fixup: invalidate stale queued profile writes (see
        // applyWorkout). Singleton kind — normalize the inbound
        // identifier to the canonical queue form so a legacy CK
        // record named "userProfile" still invalidates the queued
        // row stored under "profile".
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.userProfile.rawValue,
            recordIdentifier: CloudSyncRecord.Kind.userProfile.canonicalQueueIdentifier(from: record.identifier),
            olderThan: payload.updatedAt
        )
    }

    @MainActor
    internal func applyTrainingPlan(_ record: CloudSyncRecord) throws {
        guard let payload = SyncPayloadCodec.decodeTrainingPlanPayload(from: record.payloadJSON) else { return }

        let context = ModelContext(trainingPlanRepository.container)
        var descriptor = FetchDescriptor<TrainingPlanRecord>()
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            guard shouldApply(
                kind: record.kind,
                identifier: record.identifier,
                localTimestamp: existing.updatedAt,
                inboundTimestamp: payload.updatedAt
            ) else { return }

            existing.workoutsJSON = payload.workoutsJSON
            existing.updatedAt = payload.updatedAt
        } else {
            // VOL-67 Codex P1 (fixup #18): tombstone-wins check.
            if try hasNewerLocalDeleteTombstone(
                kind: record.kind,
                recordIdentifier: record.identifier,
                inboundTimestamp: payload.updatedAt
            ) {
                recordSuppressedInboundInsert(
                    kind: record.kind,
                    recordIdentifier: record.identifier,
                    inboundTimestamp: payload.updatedAt
                )
                return
            }

            context.insert(TrainingPlanRecord(
                workoutsJSON: payload.workoutsJSON,
                updatedAt: payload.updatedAt
            ))
        }

        try context.save()

        // VOL-67 fixup: invalidate stale queued plan writes (see
        // applyWorkout). Singleton kind — normalize to canonical
        // queue identifier so a legacy CK record named
        // "trainingPlan" still clears the queued row stored under
        // "plan".
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
            recordIdentifier: CloudSyncRecord.Kind.trainingPlan.canonicalQueueIdentifier(from: record.identifier),
            olderThan: payload.updatedAt
        )
    }

    @MainActor
    internal func applyCoachMemory(_ record: CloudSyncRecord) throws {
        guard let payload = SyncPayloadCodec.decodeCoachMemoryPayload(from: record.payloadJSON) else { return }

        let context = ModelContext(coachMemoryRepository.container)
        var descriptor = FetchDescriptor<CoachMemoryRecord>(
            predicate: #Predicate<CoachMemoryRecord> { memory in
                memory.identifier == record.identifier
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            guard shouldApply(
                kind: record.kind,
                identifier: record.identifier,
                localTimestamp: existing.createdAt,
                inboundTimestamp: payload.createdAt
            ) else { return }

            existing.content = payload.content
            existing.theme = payload.theme
            existing.createdAt = payload.createdAt
        } else {
            // VOL-67 Codex P1 (fixup #18): tombstone-wins check — same
            // resurrection race as workouts. Skip the insert when the
            // outbound queue has a strictly newer delete for this
            // memory's identifier.
            if try hasNewerLocalDeleteTombstone(
                kind: record.kind,
                recordIdentifier: record.identifier,
                inboundTimestamp: payload.createdAt
            ) {
                recordSuppressedInboundInsert(
                    kind: record.kind,
                    recordIdentifier: record.identifier,
                    inboundTimestamp: payload.createdAt
                )
                return
            }

            context.insert(CoachMemoryRecord(
                identifier: record.identifier,
                content: payload.content,
                theme: payload.theme,
                createdAt: payload.createdAt
            ))
        }

        try context.save()

        // VOL-67 fixup: invalidate stale queued memory writes. Memories
        // use `createdAt` as the ordering field since they're append-only.
        try outboundQueue?.invalidateEntries(
            recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
            recordIdentifier: record.identifier,
            olderThan: payload.createdAt
        )
    }
}
#endif
