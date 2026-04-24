#if canImport(SwiftData)
import Foundation
import SwiftData

/// VOL-67 Copilot (fixup #13): idempotent post-bootstrap backfill of
/// the outbound sync queue for pre-VOL-67 records.
///
/// Why this lives outside the V3→V4 migration stage:
/// production creates a `ModelContainer` with TWO configurations — a
/// primary store for syncable records and a SEPARATE store for
/// `OutboundSyncQueueRecord`. A `MigrationStage.custom` closure's
/// context is bound to the store being migrated, so
/// `context.insert(OutboundSyncQueueRecord(...))` from inside that
/// closure silently drops the row when the queue lives in a different
/// config. Running the backfill here with a container-scoped
/// `ModelContext` gives us both configs in scope, so inserts route
/// correctly.
///
/// Why this is idempotent: the backfill checks a caller-provided
/// `UserDefaults` key to skip repeat runs AND deduplicates against
/// existing queue rows by `(recordType, recordIdentifier)`. A crash
/// between `context.save()` and the defaults-flag set leaves the
/// queue in a valid partial state that the next run correctly
/// completes.
///
/// Per-kind timestamp rules:
/// - Singletons (profile, plan) clamp to `.distantPast` in both the
///   embedded payload `updatedAt` AND the queue row `queuedAt`.
///   Pre-fixup-#10 installs seeded these singletons with launch-time
///   timestamps that look newer than older-but-authoritative cloud
///   data, so clamping makes the backfill a lowest-priority floor:
///   it reaches CloudKit but any real data wins `shouldApply`.
/// - Per-record kinds (workout, memory) keep real timestamps because
///   they reflect concrete user actions, not seeded defaults.
public enum OutboundQueueBackfill {
    /// Run the backfill if it hasn't already run (as recorded by
    /// `userDefaults.bool(forKey: flagKey)`). After a successful save,
    /// sets the flag to skip future runs.
    ///
    /// VOL-87: the four per-kind loops here share the `existingKeys`,
    /// `context`, and `encodeFailures` counters. Splitting them into
    /// helpers would force each helper to return a `(Int, Bool)`
    /// accumulator and force the fixup #25/#26 seeded-default heuristics
    /// to live away from the insert call, obscuring the record-level
    /// parity the comments document. The body length and complexity are
    /// accepted here.
    @MainActor
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    public static func performIfNeeded(
        container: ModelContainer,
        userDefaults: UserDefaults,
        flagKey: String
    ) throws {
        if userDefaults.bool(forKey: flagKey) {
            return
        }

        let context = ModelContext(container)

        let workouts = try context.fetch(FetchDescriptor<WorkoutRecord>())
        let profiles = try context.fetch(FetchDescriptor<UserProfileRecord>())
        let plans = try context.fetch(FetchDescriptor<TrainingPlanRecord>())
        let memories = try context.fetch(FetchDescriptor<CoachMemoryRecord>())

        // Deduplicate against already-queued rows so a crash between
        // insert and flag-set doesn't produce duplicates on retry.
        //
        // VOL-67 Codex P2 (fixup #31): only count VALID existing rows
        // when building the dedupe set. If a queue row exists for a
        // key but its payload/kind/operation is malformed (legacy row
        // from a pre-rename build, corrupted write, etc.), the push
        // cycle will later quarantine and delete that row via
        // `CloudSyncCoordinator.push`'s fixup #11/#14 quarantine path.
        // Without this filter, the backfill would see the malformed
        // row in `existingKeys`, skip enqueueing a fresh upsert, and
        // mark the flag complete — leaving the record with NO
        // outbound row after quarantine cleanup. The record would
        // then never sync unless the user edits it again.
        //
        // By filtering to only valid rows, malformed rows are treated
        // as if they didn't exist for dedupe purposes. The backfill
        // enqueues a fresh upsert alongside the malformed row; the
        // push cycle's coalesce picks the newer row (the fresh
        // backfill), successfully pushes it, and cleans up all
        // drained rows for the key (including the malformed one).
        // Both layers converge on the correct state.
        let existingQueue = try context.fetch(FetchDescriptor<OutboundSyncQueueRecord>())
        let existingKeys: Set<String> = Set(
            existingQueue
                .filter { Self.isValidOutboundQueueRow($0) }
                .map { queueKey(recordType: $0.recordType, identifier: $0.recordIdentifier) }
        )

        var insertedAny = false
        // VOL-67 Copilot (fixup #19): track records that were skipped
        // because their payload couldn't be encoded. If any encode
        // fails, we must NOT mark the flag complete — otherwise a
        // subsequent launch will short-circuit out of the backfill
        // helper and those records stay permanently un-queued. A later
        // run can retry (e.g., after the user edits the record, or
        // after a schema/encoder update fixes the encode path).
        var encodeFailures = 0

        for workout in workouts {
            let key = queueKey(
                recordType: CloudSyncRecord.Kind.workout.rawValue,
                identifier: workout.identifier
            )
            guard !existingKeys.contains(key) else { continue }
            guard let payloadJSON = SyncPayloadCodec.encodeWorkoutPayload(from: workout) else {
                encodeFailures += 1
                continue
            }
            context.insert(OutboundSyncQueueRecord(
                recordType: CloudSyncRecord.Kind.workout.rawValue,
                recordIdentifier: workout.identifier,
                operation: CloudSyncRecord.Operation.upsert.rawValue,
                payloadJSON: payloadJSON,
                queuedAt: workout.updatedAt
            ))
            insertedAny = true
        }

        // VOL-67 Codex P1 fixup #26: the backfill clamp must match the
        // record-level clamp (fixup #25) — both gate on the seeded-
        // default heuristic. Unconditionally clamping the backfill
        // payload/queuedAt to `.distantPast` was silently dropping
        // recency information even for user-edited singleton data:
        //
        // 1. Device A upgrades with customized profile (local updatedAt
        //    = real edit time).
        // 2. Fixup #25: record-level clamp gated on field match, so
        //    local profile.updatedAt stays at the real edit time.
        // 3. Backfill (pre-#26) unconditionally used the *ForMigration
        //    encoder + `queuedAt: .distantPast`, so the pushed payload
        //    carried `.distantPast` as its modified-at.
        // 4. Device A's sync pushes the distantPast-tagged profile to
        //    CloudKit.
        // 5. Device B pulls — inbound is distantPast, B's local is any
        //    non-distantPast → B rejects the inbound, Device A's real
        //    edits never propagate.
        //
        // Fix: if the profile matches the seeded default, use the
        // migration encoder + distantPast (fixup #13 semantics —
        // default data is lowest-priority cross-device). Otherwise use
        // the regular encoder and the record's REAL `updatedAt` so
        // genuine user edits reach other devices normally.
        for profile in profiles {
            let key = queueKey(
                recordType: CloudSyncRecord.Kind.userProfile.rawValue,
                identifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier
            )
            guard !existingKeys.contains(key) else { continue }

            let isSeededDefault = VolumeArcSchemaMigrationPlan.isSeededDefaultProfile(profile)
            let encoded: String?
            let queueRowTimestamp: Date
            if isSeededDefault {
                encoded = SyncPayloadCodec.encodeUserProfilePayloadForMigration(from: profile)
                queueRowTimestamp = .distantPast
            } else {
                encoded = SyncPayloadCodec.encodeUserProfilePayload(from: profile)
                queueRowTimestamp = profile.updatedAt
            }
            guard let payloadJSON = encoded else {
                encodeFailures += 1
                continue
            }
            context.insert(OutboundSyncQueueRecord(
                recordType: CloudSyncRecord.Kind.userProfile.rawValue,
                recordIdentifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier,
                operation: CloudSyncRecord.Operation.upsert.rawValue,
                payloadJSON: payloadJSON,
                queuedAt: queueRowTimestamp
            ))
            insertedAny = true
        }

        for plan in plans {
            let key = queueKey(
                recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
                identifier: CloudSyncRecord.Kind.trainingPlan.defaultIdentifier
            )
            guard !existingKeys.contains(key) else { continue }

            // VOL-67 Codex P1 fixup #26: same heuristic as profiles —
            // default plans get the distantPast demotion, customized
            // plans push with their real `updatedAt`.
            let isSeededDefault = VolumeArcSchemaMigrationPlan.isSeededDefaultPlan(plan)
            let encoded: String?
            let queueRowTimestamp: Date
            if isSeededDefault {
                encoded = SyncPayloadCodec.encodeTrainingPlanPayloadForMigration(from: plan)
                queueRowTimestamp = .distantPast
            } else {
                encoded = SyncPayloadCodec.encodeTrainingPlanPayload(from: plan)
                queueRowTimestamp = plan.updatedAt
            }
            guard let payloadJSON = encoded else {
                encodeFailures += 1
                continue
            }
            context.insert(OutboundSyncQueueRecord(
                recordType: CloudSyncRecord.Kind.trainingPlan.rawValue,
                recordIdentifier: CloudSyncRecord.Kind.trainingPlan.defaultIdentifier,
                operation: CloudSyncRecord.Operation.upsert.rawValue,
                payloadJSON: payloadJSON,
                queuedAt: queueRowTimestamp
            ))
            insertedAny = true
        }

        for memory in memories {
            let key = queueKey(
                recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
                identifier: memory.identifier
            )
            guard !existingKeys.contains(key) else { continue }
            guard let payloadJSON = SyncPayloadCodec.encodeCoachMemoryPayload(from: memory) else {
                encodeFailures += 1
                continue
            }
            context.insert(OutboundSyncQueueRecord(
                recordType: CloudSyncRecord.Kind.coachMemory.rawValue,
                recordIdentifier: memory.identifier,
                operation: CloudSyncRecord.Operation.upsert.rawValue,
                payloadJSON: payloadJSON,
                queuedAt: memory.createdAt
            ))
            insertedAny = true
        }

        if insertedAny {
            try context.save()
        }

        // VOL-67 Copilot (fixup #19): only mark the backfill flag
        // complete when every candidate record reached the queue (as
        // a fresh insert or via existing-row dedupe). If ANY record
        // was skipped due to a failed payload encode, leave the flag
        // unset so a future launch re-runs the backfill and has
        // another chance to queue those records. The successful
        // inserts from this run still persisted via the `save()`
        // above, so the retry is idempotent — existingKeys will
        // dedupe them on the next attempt.
        if encodeFailures == 0 {
            userDefaults.set(true, forKey: flagKey)
        }
    }

    /// VOL-67 Codex P2 (fixup #31): a queue row counts as "valid"
    /// for dedupe purposes only if the push path would accept it —
    /// parseable `recordType`, parseable `operation`, and (for
    /// upserts) a `payloadJSON` that decodes via the per-kind decoder.
    /// Delete rows have empty `payloadJSON` by design (fixup #19) and
    /// are always valid as long as kind/operation parse.
    ///
    /// This check mirrors the validations performed by
    /// `CloudSyncCoordinator.makeCloudSyncRecord` and the pull-path
    /// decode in `CloudKitSyncTransport.pullChanges` (fixup #30), so
    /// the backfill's view of "existing valid row" agrees with what
    /// the push cycle will actually accept.
    private static func isValidOutboundQueueRow(_ row: OutboundSyncQueueRecord) -> Bool {
        guard let kind = CloudSyncRecord.Kind.parse(row.recordType) else { return false }
        guard CloudSyncRecord.Operation(rawValue: row.operation) != nil else { return false }
        if row.operation == CloudSyncRecord.Operation.delete.rawValue {
            // Delete tombstones carry empty payloadJSON by design.
            return true
        }
        return SyncPayloadCodec.modifiedAt(for: kind, payloadJSON: row.payloadJSON) != nil
    }

    /// VOL-67 Copilot (fixup #15): build the dedupe key from the
    /// normalized `Kind` raw value and the canonical queue identifier,
    /// so legacy long-form rows (`recordType="userProfile",
    /// recordIdentifier="userProfile"`) collapse to the same slot as
    /// canonical short-form rows (`recordType="profile",
    /// recordIdentifier="profile"`). Without this, a device that still
    /// has legacy-form rows left in its queue at first post-VOL-67
    /// launch would not get deduplicated against the freshly-built
    /// canonical row the backfill tries to enqueue — producing a
    /// duplicate outbound upsert for the same logical singleton.
    ///
    /// Mirrors `CloudSyncCoordinator.coalesceKey(for:)` so the backfill
    /// dedupe and push-time coalescing agree on which rows are "the
    /// same logical record". Unknown/future record types fall back to
    /// the raw pair so we don't accidentally merge kinds we don't
    /// understand.
    private static func queueKey(recordType: String, identifier: String) -> String {
        if let kind = CloudSyncRecord.Kind.parse(recordType) {
            return "\(kind.rawValue)|\(kind.canonicalQueueIdentifier(from: identifier))"
        }
        return "\(recordType)|\(identifier)"
    }
}
#endif
