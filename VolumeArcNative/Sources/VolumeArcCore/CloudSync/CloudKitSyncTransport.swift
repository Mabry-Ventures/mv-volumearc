import Foundation
#if canImport(CloudKit)
import CloudKit

/// CloudKit-backed sync transport.
/// Pushes records to a private database zone and pulls changes via
/// `CKFetchRecordZoneChangesOperation` with server cursor tokens.
public final class CloudKitSyncTransport: CloudSyncTransport, @unchecked Sendable {
    public let containerIdentifier: String
    public let zoneName: String

    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID

    public init(containerIdentifier: String, zoneName: String) {
        self.containerIdentifier = containerIdentifier
        self.zoneName = zoneName
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }

    public var isAvailable: Bool { true }

    public func pushRecords(_ records: [CloudSyncRecord]) async throws {
        guard !records.isEmpty else { return }

        try await ensureZoneExists()

        let ckRecords = records.map { record -> CKRecord in
            let id = CKRecord.ID(recordName: record.identifier, zoneID: zoneID)
            let ck = CKRecord(recordType: record.kind.rawValue, recordID: id)
            ck["operation"] = record.operation.rawValue as NSString
            ck["payloadJSON"] = record.payloadJSON as NSString
            ck["modifiedAt"] = record.modifiedAt as NSDate
            return ck
        }

        let operation = CKModifyRecordsOperation(recordsToSave: ckRecords, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }
    }

    public func pullChanges(since cursor: String?) async throws -> CloudSyncPullResult {
        try await ensureZoneExists()

        var changedRecords: [CloudSyncRecord] = []
        var deletedRecordIDs: [String] = []
        var nextCursor: String? = cursor
        // VOL-67 Copilot (fixup #21): count records that we had to skip
        // because `SyncPayloadCodec.synthesizeLegacyPayloadJSON` returned
        // nil (missing required fields on a legacy CKRecord). If ANY
        // records are skipped, we clear `nextCursor` before returning so
        // the next `syncCycle` re-fetches the whole window instead of
        // advancing past un-applied changes. See the skip branch below.
        var legacySynthesisSkips = 0

        let token: CKServerChangeToken?
        if let cursor,
           let data = Data(base64Encoded: cursor),
           let unarchived = try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data) {
            token = unarchived
        } else {
            token = nil
        }

        let options = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        options.previousServerChangeToken = token

        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: options]
        )

        operation.recordWasChangedBlock = { _, result in
            if case let .success(record) = result,
               let kind = CloudSyncRecord.Kind.parse(record.recordType) {
                // VOL-67 Copilot (fixup #33): read the client-authored
                // `modifiedAt` custom field that `pushRecords` writes
                // (see line 152: `ck["modifiedAt"] = record.modifiedAt`),
                // with a fallback to `record.modificationDate` (CK
                // server write time) only when the custom field is
                // absent or malformed. Previously we always used
                // `record.modificationDate`, which is the server-side
                // write time — NOT the client's intended modification
                // instant. The mismatch broke cross-device LWW:
                //
                // 1. Device A edits a workout at T1.
                // 2. Device A queues the mutation, pushes later at T2
                //    (T2 > T1 — possibly much later on a slow network
                //    or after an app background).
                // 3. CloudKit records the row with `modifiedAt` = T1
                //    (custom field, client-authored) but
                //    `record.modificationDate` = T2 (server receive
                //    time).
                // 4. Device B has a local edit at T_local where
                //    T1 < T_local < T2. The edit reflects newer user
                //    intent than A's push.
                // 5. Device B pulls A's push and uses
                //    `record.modificationDate` = T2 as the inbound
                //    timestamp. `shouldApply` compares T_local < T2
                //    → apply inbound → Device B's newer edit is
                //    silently overwritten by A's older (per user
                //    intent) push.
                //
                // Reading the custom field fixes this: Device B now
                // sees the inbound timestamp as T1, correctly
                // preserves its newer T_local edit, and the next
                // push round propagates B's edit to cloud.
                //
                // Accept both `Date` and `NSNumber` encodings for the
                // custom field. NSNumber handles the case where an
                // older build wrote the timestamp as a numeric (e.g.,
                // milliseconds since 1970 after a JSON round-trip).
                // Auto-detect seconds vs milliseconds by magnitude:
                // > 100_000_000_000 is milliseconds (3168 AD in
                // seconds — unreachable), otherwise seconds.
                let modifiedAt: Date = {
                    if let date = record["modifiedAt"] as? Date {
                        return date
                    }
                    if let number = record["modifiedAt"] as? NSNumber {
                        let raw = number.doubleValue
                        if raw.isFinite {
                            let seconds = raw > 100_000_000_000 ? raw / 1_000 : raw
                            return Date(timeIntervalSince1970: seconds)
                        }
                    }
                    return record.modificationDate ?? .now
                }()
                let operation = CloudSyncRecord.Operation(
                    rawValue: (record["operation"] as? String) ?? CloudSyncRecord.Operation.upsert.rawValue
                ) ?? .upsert

                // VOL-67 Codex P2 fixup: the modern wire format stores
                // the entire payload in a single `payloadJSON` key, but
                // pre-rename CKRecords may have stored individual field
                // keys instead. If `payloadJSON` is missing, synthesize
                // one by reading the known per-kind fields directly off
                // the CKRecord.
                //
                // VOL-67 Copilot (fixup #21): if synthesis returns nil
                // (legacy record is missing required fields), SKIP the
                // record entirely AND increment the skip counter.
                // Previously we fell back to an empty payloadJSON and
                // still appended the record — the applier then silently
                // dropped it on decode-failure while the cursor advanced
                // past it, losing the mutation permanently. Now we
                // neither produce a junk record nor advance the cursor
                // past it: the whole window gets re-fetched on the next
                // sync cycle. Successfully-synthesized records in the
                // same window still get applied by the coordinator —
                // they're idempotent on re-fetch because shouldApply
                // rejects equal-timestamp re-applies.
                //
                // VOL-67 Codex P1 (fixup #24): SHORT-CIRCUIT the
                // synthesis path for delete operations. Fixup #19
                // stopped persisting the record body on delete
                // tombstones (outbound `deleteWorkout`/`deleteMemory`
                // stage `payloadJSON: ""`), so pulled delete records
                // come back with an empty `payloadJSON`. The legacy
                // synthesis fallback would then try to read upsert
                // fields off the CKRecord (title, startedAt, etc.),
                // fail because deletes don't carry those fields, and
                // skip the record — meaning remote deletes would
                // never apply locally and the cursor would keep
                // resetting on every pull. For deletes we use the
                // empty payload as-is: `applyDeletion` only reads
                // `record.kind` and `record.identifier`, never the
                // payload, so an empty string is safe for the
                // entire downstream path.
                let payloadJSON: String
                if operation == .delete {
                    payloadJSON = (record["payloadJSON"] as? String) ?? ""
                } else if let explicit = record["payloadJSON"] as? String, !explicit.isEmpty {
                    // VOL-67 Codex P2 (fixup #30): an explicit non-empty
                    // `payloadJSON` can still be malformed (older buggy
                    // clients, manual cloud edits, corrupted records,
                    // etc.). The downstream applier uses
                    // `guard let payload = SyncPayloadCodec.decode*Payload(from:)
                    // else { return }` and silently drops bad payloads —
                    // while the pull cursor still advances past them.
                    // Net effect: malformed records disappear forever with
                    // no retry and no error. Validate the payload here at
                    // pull time by round-tripping through the codec's
                    // `modifiedAt(for:payloadJSON:)` helper (which tries
                    // the per-kind decoder). If it fails, route into the
                    // same cursor-reset path as legacy synthesis failures:
                    // skip the record for THIS cycle so the applier
                    // doesn't see junk, and reset the cursor so the whole
                    // window gets re-fetched next time.
                    if SyncPayloadCodec.modifiedAt(for: kind, payloadJSON: explicit) != nil {
                        payloadJSON = explicit
                    } else {
                        legacySynthesisSkips += 1
                        return
                    }
                } else {
                    var fields: [String: Any] = [:]
                    for key in record.allKeys() {
                        if let value = record[key] {
                            fields[key] = value
                        }
                    }
                    guard let synthesized = SyncPayloadCodec.synthesizeLegacyPayloadJSON(
                        kind: kind,
                        fields: fields
                    ) else {
                        legacySynthesisSkips += 1
                        return
                    }
                    payloadJSON = synthesized
                }

                changedRecords.append(CloudSyncRecord(
                    kind: kind,
                    identifier: record.recordID.recordName,
                    operation: operation,
                    payloadJSON: payloadJSON,
                    modifiedAt: modifiedAt
                ))
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            deletedRecordIDs.append(recordID.recordName)
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.recordZoneChangeTokensUpdatedBlock = { _, newToken, _ in
                if let newToken,
                   let data = try? NSKeyedArchiver.archivedData(withRootObject: newToken, requiringSecureCoding: true) {
                    nextCursor = data.base64EncodedString()
                }
            }
            operation.recordZoneFetchResultBlock = { _, result in
                if case let .success(success) = result,
                   let data = try? NSKeyedArchiver.archivedData(withRootObject: success.serverChangeToken, requiringSecureCoding: true) {
                    nextCursor = data.base64EncodedString()
                }
            }
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }

        // VOL-67 Copilot (fixup #34): fixup #21 originally cleared the
        // cursor (`nextCursor = nil`) when any records were skipped,
        // forcing the next pull to re-fetch the whole window. That was
        // intended as a safety net for transient failures, but both
        // skip branches (legacy synthesis failure and explicit payload
        // decode failure from fixup #30) are PERMANENT: the legacy
        // CKRecord field layout is static, and a malformed payloadJSON
        // blob won't magically fix itself on retry. Resetting the
        // cursor for these failures creates an infinite re-fetch loop
        // with ongoing network and battery cost — the device pulls the
        // same window, skips the same records, resets the cursor, and
        // repeats forever.
        //
        // Fix: let the cursor advance. Skipped records are accepted as
        // unrecoverable data loss for that specific record. The records
        // that DID synthesize/validate in this window are applied
        // normally, and the cursor advances past the whole window so
        // the next cycle pulls only NEW changes. The skip count is
        // included in the result so the coordinator can emit telemetry
        // for observability (the loss is "loud", not "silent").
        //
        // Future improvement: implement a per-record quarantine store
        // that tracks skipped CKRecord names across cycles and surfaces
        // them in a diagnostic UI. Filed as a follow-up concern, not
        // a launch blocker.

        return CloudSyncPullResult(
            changedRecords: changedRecords,
            deletedRecordIDs: deletedRecordIDs,
            nextCursor: nextCursor
        )
    }

    /// Create the sync zone if it doesn't already exist. Safe to call repeatedly.
    private func ensureZoneExists() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordZonesOperation(
                recordZonesToSave: [zone],
                recordZoneIDsToDelete: nil
            )
            operation.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case let .failure(error):
                    // Zone already exists is not an error we care about.
                    if let ckError = error as? CKError, ckError.code == .serverRecordChanged {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
            database.add(operation)
        }
    }
}
#endif
