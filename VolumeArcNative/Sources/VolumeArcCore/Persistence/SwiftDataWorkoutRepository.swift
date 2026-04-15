#if canImport(SwiftData)
import Foundation
import SwiftData

/// SwiftData-backed repository for `WorkoutRecord`.
public struct SwiftDataWorkoutRepository: Sendable {
    public let container: ModelContainer
    private let outboundQueue: any OutboundSyncQueue

    public init(container: ModelContainer, outboundQueue: (any OutboundSyncQueue)? = nil) {
        self.container = container
        self.outboundQueue = outboundQueue ?? NoOpOutboundSyncQueue()
    }

    // MARK: - Create

    /// Create and persist a new workout session.
    @MainActor
    public func createWorkout(
        title: String,
        startedAt: Date = .now,
        updatedAt: Date = .now
    ) throws -> WorkoutRecord {
        let context = ModelContext(container)
        let workout = WorkoutRecord(title: title, startedAt: startedAt, updatedAt: updatedAt)
        context.insert(workout)
        try stageUpsert(for: workout, into: context)
        try context.save()
        return workout
    }

    // MARK: - Read

    /// Fetch all workouts completed within the given date range.
    @MainActor
    public func workouts(from start: Date, to end: Date) throws -> [WorkoutRecord] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.startedAt >= start && workout.startedAt <= end
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 200
        return try context.fetch(descriptor)
    }

    /// Fetch the N most recent completed workouts.
    @MainActor
    public func recentWorkouts(limit: Int = 10) throws -> [WorkoutRecord] {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    /// Find the in-progress workout (completedAt == nil), if any.
    @MainActor
    public func activeWorkout() throws -> WorkoutRecord? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.completedAt == nil
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Fetch a workout by its identifier.
    @MainActor
    public func workout(withIdentifier identifier: String) throws -> WorkoutRecord? {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == identifier
            }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Update

    /// Append a logged set to a workout's JSON set array.
    @MainActor
    public func appendSet(
        _ set: WorkoutSetPerformance,
        forExercise exerciseID: String,
        to workoutIdentifier: String
    ) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == workoutIdentifier
            }
        )
        descriptor.fetchLimit = 1
        guard let workout = try context.fetch(descriptor).first else { return }

        // Decode existing sets, append the new one, re-encode.
        var logged: [LoggedSet] = []
        if let data = workout.setsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([LoggedSet].self, from: data) {
            logged = decoded
        }
        logged.append(LoggedSet(exerciseID: exerciseID, set: set))

        if let encoded = try? JSONEncoder().encode(logged),
           let json = String(data: encoded, encoding: .utf8) {
            workout.setsJSON = json
        }

        // Update aggregates
        workout.completedSetCount = logged.count
        workout.totalVolumeLoad = logged.reduce(0) { $0 + ($1.set.weight * Double($1.set.reps)) }
        let rpeValues = logged.map(\.set.rpe)
        workout.averageRPE = rpeValues.isEmpty ? 0 : rpeValues.reduce(0, +) / Double(rpeValues.count)

        // Add exercise ID to CSV if not present
        var exerciseIDs = Set(workout.exerciseIDsCSV.split(separator: ",").map(String.init))
        exerciseIDs.insert(exerciseID)
        workout.exerciseIDsCSV = exerciseIDs.sorted().joined(separator: ",")
        workout.updatedAt = .now

        try stageUpsert(for: workout, into: context)
        try context.save()
    }

    /// Mark a workout as completed.
    @MainActor
    public func completeWorkout(identifier: String, summary: String = "") throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == identifier
            }
        )
        descriptor.fetchLimit = 1
        guard let workout = try context.fetch(descriptor).first else { return }

        let now = Date.now
        workout.completedAt = now
        workout.durationMinutes = max(1, Int(now.timeIntervalSince(workout.startedAt) / 60))
        if !summary.isEmpty { workout.summary = summary }
        workout.updatedAt = now
        try stageUpsert(for: workout, into: context)
        try context.save()
    }

    // MARK: - Delete

    /// Delete a workout by identifier.
    @MainActor
    public func deleteWorkout(identifier: String) throws {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.identifier == identifier
            }
        )
        descriptor.fetchLimit = 1
        if let workout = try context.fetch(descriptor).first {
            // VOL-67 Codex P1 fixup: tombstones need the actual deletion
            // wall-clock time (see comment in the delete paths of the
            // coach-memory repository). VOL-67 Codex P2 fixup: stage the
            // queue row into the same context as the delete and let one
            // `context.save()` commit both atomically, so a queue write
            // failure can't leave a deleted record with no tombstone.
            //
            // VOL-67 Copilot (fixup #19): delete tombstones do NOT need
            // the full serialized payload. `CloudSyncCoordinator.makeCloudSyncRecord`
            // uses `queuedAt` as the authoritative delete timestamp and
            // ignores `payloadJSON` for `.delete` operations, and
            // `DefaultSyncPayloadApplier` doesn't decode the payload on
            // deletions either. Serializing the full workout body into
            // the tombstone retained deleted user content in the queue
            // (and in CloudKit) with no functional benefit — it just
            // inflated record size and prolonged data retention.
            // Staging an empty string keeps the delete row valid while
            // dropping the deleted content from the queue entirely.
            let deletedAt = Date()
            context.delete(workout)
            outboundQueue.stage(
                into: context,
                recordType: CloudSyncRecord.Kind.workout.rawValue,
                recordIdentifier: identifier,
                operation: CloudSyncRecord.Operation.delete.rawValue,
                payloadJSON: "",
                queuedAt: deletedAt
            )
            try context.save()
        }
    }

    // MARK: - Projections

    /// Build `RecentSession` projections for the progression engine.
    @MainActor
    public func recentSessions(limit: Int = 20) throws -> [RecentSession] {
        let records = try recentWorkouts(limit: limit)
        return records
            .filter { $0.completedAt != nil }
            .map { record in
                RecentSession(
                    date: record.completedAt ?? record.startedAt,
                    durationMinutes: record.durationMinutes,
                    exerciseIDs: record.exerciseIDsCSV.split(separator: ",").map(String.init),
                    totalVolumeLoad: record.totalVolumeLoad,
                    averageRPE: record.averageRPE,
                    completedSetCount: record.completedSetCount
                )
            }
    }

    /// Build an `ExerciseHistory` projection for a single exercise.
    @MainActor
    public func history(forExercise exerciseID: String, limit: Int = 20) throws -> ExerciseHistory {
        let workouts = try recentWorkouts(limit: 200)
        let sessions: [ExerciseSession] = workouts.compactMap { workout in
            guard let data = workout.setsJSON.data(using: .utf8),
                  let logged = try? JSONDecoder().decode([LoggedSet].self, from: data)
            else { return nil }
            let sets = logged.filter { $0.exerciseID == exerciseID }.map(\.set)
            guard !sets.isEmpty else { return nil }
            return ExerciseSession(
                date: workout.completedAt ?? workout.startedAt,
                sets: sets
            )
        }
        return ExerciseHistory(exerciseID: exerciseID, sessions: Array(sessions.prefix(limit)))
    }
}

/// Internal wrapper for encoding sets with their exercise ID in `WorkoutRecord.setsJSON`.
private struct LoggedSet: Codable {
    let exerciseID: String
    let set: WorkoutSetPerformance
}

extension SwiftDataWorkoutRepository {
    /// Stage an upsert queue row into the same context as the record
    /// mutation. The caller saves the context once, committing both
    /// writes atomically. See `OutboundSyncQueue.stage(into:)` for
    /// the VOL-67 Codex P2 rationale behind this pattern.
    ///
    /// VOL-67 Codex P2 (fixup #28): throws
    /// `OutboundQueueStagingError.payloadEncodingFailed` when the
    /// workout can't be serialized to JSON (e.g., non-finite
    /// `Double` fields from bad instrumentation data). Before the
    /// fix this method silently returned, letting the caller save
    /// the primary record change without a corresponding queue row
    /// — local write committed but never sync'd. Now the caller's
    /// `try context.save()` never runs because the error aborts the
    /// whole repository method before the save, so the record
    /// mutation is rolled back and the caller sees the failure.
    @MainActor
    fileprivate func stageUpsert(for workout: WorkoutRecord, into context: ModelContext) throws {
        guard let payloadJSON = SyncPayloadCodec.encodeWorkoutPayload(from: workout) else {
            throw OutboundQueueStagingError.payloadEncodingFailed(
                recordType: CloudSyncRecord.Kind.workout.rawValue,
                recordIdentifier: workout.identifier
            )
        }
        outboundQueue.stage(
            into: context,
            recordType: CloudSyncRecord.Kind.workout.rawValue,
            recordIdentifier: workout.identifier,
            operation: CloudSyncRecord.Operation.upsert.rawValue,
            payloadJSON: payloadJSON,
            queuedAt: workout.updatedAt
        )
    }
}
#endif
