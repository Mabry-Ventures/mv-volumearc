import Foundation
#if canImport(SwiftData)
import SwiftData
#endif

public enum SyncPayloadCodec {
    public struct UserProfilePayload: Codable, Equatable, Sendable {
        public let name: String
        public let coachingStyle: String
        public let privacyMode: String
        public let advancementLevel: String
        public let availableEquipmentCSV: String
        public let preferredRepRangeLower: Int
        public let preferredRepRangeUpper: Int
        public let sessionTimeBudgetMinutes: Int
        public let weeklyTrainingDays: Int
        public let onboardingCompleted: Bool
        public let updatedAt: Date

        public init(
            name: String,
            coachingStyle: String,
            privacyMode: String,
            advancementLevel: String,
            availableEquipmentCSV: String,
            preferredRepRangeLower: Int,
            preferredRepRangeUpper: Int,
            sessionTimeBudgetMinutes: Int,
            weeklyTrainingDays: Int,
            onboardingCompleted: Bool,
            updatedAt: Date
        ) {
            self.name = name
            self.coachingStyle = coachingStyle
            self.privacyMode = privacyMode
            self.advancementLevel = advancementLevel
            self.availableEquipmentCSV = availableEquipmentCSV
            self.preferredRepRangeLower = preferredRepRangeLower
            self.preferredRepRangeUpper = preferredRepRangeUpper
            self.sessionTimeBudgetMinutes = sessionTimeBudgetMinutes
            self.weeklyTrainingDays = weeklyTrainingDays
            self.onboardingCompleted = onboardingCompleted
            self.updatedAt = updatedAt
        }
    }

    public struct WorkoutPayload: Codable, Equatable, Sendable {
        public let title: String
        public let startedAt: Date
        public let completedAt: Date?
        public let durationMinutes: Int
        public let exerciseIDsCSV: String
        public let setsJSON: String
        public let totalVolumeLoad: Double
        public let averageRPE: Double
        public let completedSetCount: Int
        public let summary: String
        public let updatedAt: Date

        public init(
            title: String,
            startedAt: Date,
            completedAt: Date?,
            durationMinutes: Int,
            exerciseIDsCSV: String,
            setsJSON: String,
            totalVolumeLoad: Double,
            averageRPE: Double,
            completedSetCount: Int,
            summary: String,
            updatedAt: Date
        ) {
            self.title = title
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.durationMinutes = durationMinutes
            self.exerciseIDsCSV = exerciseIDsCSV
            self.setsJSON = setsJSON
            self.totalVolumeLoad = totalVolumeLoad
            self.averageRPE = averageRPE
            self.completedSetCount = completedSetCount
            self.summary = summary
            self.updatedAt = updatedAt
        }
    }

    public struct TrainingPlanPayload: Codable, Equatable, Sendable {
        public let workoutsJSON: String
        public let updatedAt: Date

        public init(workoutsJSON: String, updatedAt: Date) {
            self.workoutsJSON = workoutsJSON
            self.updatedAt = updatedAt
        }
    }

    public struct CoachMemoryPayload: Codable, Equatable, Sendable {
        public let content: String
        public let theme: String
        public let createdAt: Date

        public init(content: String, theme: String, createdAt: Date) {
            self.content = content
            self.theme = theme
            self.createdAt = createdAt
        }
    }

    private struct UserProfileEnvelope: Codable, Equatable, Sendable {
        let profile: UserProfilePayload
    }

    private struct WorkoutEnvelope: Codable, Equatable, Sendable {
        let workout: WorkoutPayload
    }

    private struct TrainingPlanEnvelope: Codable, Equatable, Sendable {
        let plan: TrainingPlanPayload
    }

    private struct CoachMemoryEnvelope: Codable, Equatable, Sendable {
        let memory: CoachMemoryPayload
    }

    public static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from string: String) -> T? {
        guard let data = string.data(using: .utf8) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    public static func decodeUserProfilePayload(from string: String) -> UserProfilePayload? {
        decode(UserProfileEnvelope.self, from: string)?.profile
    }

    public static func decodeWorkoutPayload(from string: String) -> WorkoutPayload? {
        decode(WorkoutEnvelope.self, from: string)?.workout
    }

    public static func decodeTrainingPlanPayload(from string: String) -> TrainingPlanPayload? {
        decode(TrainingPlanEnvelope.self, from: string)?.plan
    }

    public static func decodeCoachMemoryPayload(from string: String) -> CoachMemoryPayload? {
        decode(CoachMemoryEnvelope.self, from: string)?.memory
    }

    public static func modifiedAt(for kind: CloudSyncRecord.Kind, payloadJSON: String) -> Date? {
        switch kind {
        case .workout:
            return decodeWorkoutPayload(from: payloadJSON)?.updatedAt
        case .userProfile:
            return decodeUserProfilePayload(from: payloadJSON)?.updatedAt
        case .trainingPlan:
            return decodeTrainingPlanPayload(from: payloadJSON)?.updatedAt
        case .coachMemory:
            return decodeCoachMemoryPayload(from: payloadJSON)?.createdAt
        }
    }

    // VOL-67 Copilot P2 (fixup #11): helpers that take SwiftData
    // `@Model` record types are gated on `canImport(SwiftData)` so
    // this file still compiles on platforms where SwiftData isn't
    // available. Everything above — the payload structs, the
    // generic encode/decode helpers, the per-kind decoders, the
    // `modifiedAt(for:)` helper, and the legacy-field synthesis
    // helper below — is pure JSON/Foundation and compiles
    // unconditionally.
    #if canImport(SwiftData)
    public static func encodeUserProfilePayload(from record: UserProfileRecord) -> String? {
        encode(UserProfileEnvelope(profile: UserProfilePayload(
            name: record.name,
            coachingStyle: record.coachingStyle,
            privacyMode: record.privacyMode,
            advancementLevel: record.advancementLevel,
            availableEquipmentCSV: record.availableEquipmentCSV,
            preferredRepRangeLower: record.preferredRepRangeLower,
            preferredRepRangeUpper: record.preferredRepRangeUpper,
            sessionTimeBudgetMinutes: record.sessionTimeBudgetMinutes,
            weeklyTrainingDays: record.weeklyTrainingDays,
            onboardingCompleted: record.onboardingCompleted,
            updatedAt: record.updatedAt
        )))
    }

    public static func encodeWorkoutPayload(from record: WorkoutRecord) -> String? {
        encode(WorkoutEnvelope(workout: WorkoutPayload(
            title: record.title,
            startedAt: record.startedAt,
            completedAt: record.completedAt,
            durationMinutes: record.durationMinutes,
            exerciseIDsCSV: record.exerciseIDsCSV,
            setsJSON: record.setsJSON,
            totalVolumeLoad: record.totalVolumeLoad,
            averageRPE: record.averageRPE,
            completedSetCount: record.completedSetCount,
            summary: record.summary,
            updatedAt: record.updatedAt
        )))
    }

    public static func encodeTrainingPlanPayload(from record: TrainingPlanRecord) -> String? {
        encode(TrainingPlanEnvelope(plan: TrainingPlanPayload(
            workoutsJSON: record.workoutsJSON,
            updatedAt: record.updatedAt
        )))
    }

    /// VOL-67 Codex P1 (fixup #13): migration-backfill encoders that
    /// clamp the embedded singleton `updatedAt` to `.distantPast`.
    ///
    /// During the V3→V4 migration we enqueue outbound upserts for every
    /// pre-existing singleton (profile, plan) so the user's existing
    /// data can reach CloudKit after upgrade. But pre-fixup-#10
    /// installs seeded those singletons with launch-time timestamps,
    /// NOT `.distantPast`. If we re-encoded those unchanged, the
    /// backfilled queue row would carry a "real-looking" modified-at
    /// and could beat older but authoritative cloud data in the
    /// applier's `shouldApply` check — clobbering server state that
    /// should have won. Clamping the payload's `updatedAt` to
    /// `.distantPast` makes the migrated backfill a "lowest-priority
    /// floor": the record gets pushed to CloudKit, but any real
    /// cloud data always wins the timestamp comparison. Per-record
    /// kinds (workout, memory) keep their real timestamps because
    /// they represent concrete user actions, not seeded defaults.
    public static func encodeUserProfilePayloadForMigration(from record: UserProfileRecord) -> String? {
        encode(UserProfileEnvelope(profile: UserProfilePayload(
            name: record.name,
            coachingStyle: record.coachingStyle,
            privacyMode: record.privacyMode,
            advancementLevel: record.advancementLevel,
            availableEquipmentCSV: record.availableEquipmentCSV,
            preferredRepRangeLower: record.preferredRepRangeLower,
            preferredRepRangeUpper: record.preferredRepRangeUpper,
            sessionTimeBudgetMinutes: record.sessionTimeBudgetMinutes,
            weeklyTrainingDays: record.weeklyTrainingDays,
            onboardingCompleted: record.onboardingCompleted,
            updatedAt: .distantPast
        )))
    }

    public static func encodeTrainingPlanPayloadForMigration(from record: TrainingPlanRecord) -> String? {
        encode(TrainingPlanEnvelope(plan: TrainingPlanPayload(
            workoutsJSON: record.workoutsJSON,
            updatedAt: .distantPast
        )))
    }

    public static func encodeCoachMemoryPayload(from record: CoachMemoryRecord) -> String? {
        encode(CoachMemoryEnvelope(memory: CoachMemoryPayload(
            content: record.content,
            theme: record.theme,
            createdAt: record.createdAt
        )))
    }

    public static func makeRecord(
        for workout: WorkoutRecord,
        operation: CloudSyncRecord.Operation = .upsert
    ) -> CloudSyncRecord? {
        guard let payloadJSON = encodeWorkoutPayload(from: workout) else { return nil }
        return CloudSyncRecord(
            kind: .workout,
            identifier: workout.identifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: workout.updatedAt
        )
    }

    public static func makeRecord(
        for profile: UserProfileRecord,
        operation: CloudSyncRecord.Operation = .upsert
    ) -> CloudSyncRecord? {
        guard let payloadJSON = encodeUserProfilePayload(from: profile) else { return nil }
        return CloudSyncRecord(
            kind: .userProfile,
            identifier: CloudSyncRecord.Kind.userProfile.defaultIdentifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: profile.updatedAt
        )
    }

    public static func makeRecord(
        for plan: TrainingPlanRecord,
        operation: CloudSyncRecord.Operation = .upsert
    ) -> CloudSyncRecord? {
        guard let payloadJSON = encodeTrainingPlanPayload(from: plan) else { return nil }
        return CloudSyncRecord(
            kind: .trainingPlan,
            identifier: CloudSyncRecord.Kind.trainingPlan.defaultIdentifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: plan.updatedAt
        )
    }

    public static func makeRecord(
        for memory: CoachMemoryRecord,
        operation: CloudSyncRecord.Operation = .upsert
    ) -> CloudSyncRecord? {
        guard let payloadJSON = encodeCoachMemoryPayload(from: memory) else { return nil }
        return CloudSyncRecord(
            kind: .coachMemory,
            identifier: memory.identifier,
            operation: operation,
            payloadJSON: payloadJSON,
            modifiedAt: memory.createdAt
        )
    }
    #endif // canImport(SwiftData) — SwiftData-model-dependent helpers

    /// VOL-67 Codex P2 fixup: synthesize a canonical payloadJSON from
    /// the individual-field format used by pre-VOL-67 CloudKit records.
    ///
    /// The modern wire format stores the entire payload under a single
    /// `payloadJSON` CKRecord key. But earlier (unshipped) iterations
    /// of this sync code wrote each field directly to the CKRecord
    /// (`title`, `startedAt`, `updatedAt`, etc.). After upgrading to
    /// the new transport, the pull path used to fall back to an empty
    /// string when `payloadJSON` was missing, which caused the applier
    /// to silently drop the record while the sync cursor advanced —
    /// effectively losing any existing cloud data.
    ///
    /// The transport now calls this helper when `payloadJSON` is
    /// absent. Caller constructs a `[String: Any]` dict from the
    /// CKRecord's field values; this helper reads the fields for the
    /// given `kind`, builds the matching payload struct, and encodes
    /// it via the canonical JSON encoder. Returns `nil` if the
    /// dictionary is missing fields required by the payload struct
    /// (truly unrecoverable — caller drops the record, same as
    /// before).
    ///
    /// Dates can come in as `Date` or as `TimeInterval`/`Double`
    /// (CloudKit may return either). The reader accepts both forms.
    public static func synthesizeLegacyPayloadJSON(
        kind: CloudSyncRecord.Kind,
        fields: [String: Any]
    ) -> String? {
        switch kind {
        case .workout:
            guard
                let title = fields["title"] as? String,
                let startedAt = Self.readDate(fields["startedAt"]),
                let updatedAt = Self.readDate(fields["updatedAt"])
            else { return nil }

            let payload = WorkoutPayload(
                title: title,
                startedAt: startedAt,
                completedAt: Self.readDate(fields["completedAt"]),
                durationMinutes: (fields["durationMinutes"] as? Int) ?? (fields["durationMinutes"] as? NSNumber)?.intValue ?? 0,
                exerciseIDsCSV: (fields["exerciseIDsCSV"] as? String) ?? "",
                setsJSON: (fields["setsJSON"] as? String) ?? "[]",
                totalVolumeLoad: (fields["totalVolumeLoad"] as? Double) ?? (fields["totalVolumeLoad"] as? NSNumber)?.doubleValue ?? 0,
                averageRPE: (fields["averageRPE"] as? Double) ?? (fields["averageRPE"] as? NSNumber)?.doubleValue ?? 0,
                completedSetCount: (fields["completedSetCount"] as? Int) ?? (fields["completedSetCount"] as? NSNumber)?.intValue ?? 0,
                summary: (fields["summary"] as? String) ?? "",
                updatedAt: updatedAt
            )
            return encode(WorkoutEnvelope(workout: payload))

        case .userProfile:
            guard
                let name = fields["name"] as? String,
                let updatedAt = Self.readDate(fields["updatedAt"])
            else { return nil }

            // VOL-67 Codex P2 (fixup #12): the pre-VOL-67 inbound applier
            // read the equipment CSV from `record.payload["equipment"]`
            // (see the legacy `DefaultSyncPayloadApplier` decode path in
            // the original CloudSync.swift — confirmed in git history at
            // commit a13b515). Any CKRecord that was pushed by that
            // older applier stores the CSV under the `equipment` key,
            // NOT the canonical `availableEquipmentCSV`. On upgrade
            // pulls we accept both; prefer the canonical key when
            // present so a newer-schema record doesn't get overridden
            // by a stale `equipment` leftover.
            let legacyEquipment = (fields["availableEquipmentCSV"] as? String)
                ?? (fields["equipment"] as? String)
                ?? ""
            let payload = UserProfilePayload(
                name: name,
                coachingStyle: (fields["coachingStyle"] as? String) ?? "motivational",
                privacyMode: (fields["privacyMode"] as? String) ?? "standard",
                advancementLevel: (fields["advancementLevel"] as? String) ?? "intermediate",
                availableEquipmentCSV: legacyEquipment,
                preferredRepRangeLower: (fields["preferredRepRangeLower"] as? Int) ?? (fields["preferredRepRangeLower"] as? NSNumber)?.intValue ?? 5,
                preferredRepRangeUpper: (fields["preferredRepRangeUpper"] as? Int) ?? (fields["preferredRepRangeUpper"] as? NSNumber)?.intValue ?? 8,
                sessionTimeBudgetMinutes: (fields["sessionTimeBudgetMinutes"] as? Int) ?? (fields["sessionTimeBudgetMinutes"] as? NSNumber)?.intValue ?? 60,
                weeklyTrainingDays: (fields["weeklyTrainingDays"] as? Int) ?? (fields["weeklyTrainingDays"] as? NSNumber)?.intValue ?? 4,
                onboardingCompleted: (fields["onboardingCompleted"] as? Bool) ?? (fields["onboardingCompleted"] as? NSNumber)?.boolValue ?? false,
                updatedAt: updatedAt
            )
            return encode(UserProfileEnvelope(profile: payload))

        case .trainingPlan:
            guard
                let workoutsJSON = fields["workoutsJSON"] as? String,
                let updatedAt = Self.readDate(fields["updatedAt"])
            else { return nil }

            let payload = TrainingPlanPayload(
                workoutsJSON: workoutsJSON,
                updatedAt: updatedAt
            )
            return encode(TrainingPlanEnvelope(plan: payload))

        case .coachMemory:
            guard
                let content = fields["content"] as? String,
                let createdAt = Self.readDate(fields["createdAt"])
            else { return nil }

            let payload = CoachMemoryPayload(
                content: content,
                theme: (fields["theme"] as? String) ?? "",
                createdAt: createdAt
            )
            return encode(CoachMemoryEnvelope(memory: payload))
        }
    }

    /// Coerce an arbitrary `Any?` field value into a `Date`. Supports
    /// direct `Date` values (what `CKRecord` returns for date fields)
    /// as well as `TimeInterval` / numeric types for defensive
    /// compatibility with older wire formats.
    private static func readDate(_ raw: Any?) -> Date? {
        if let date = raw as? Date {
            return date
        }
        if let seconds = raw as? TimeInterval {
            return Date(timeIntervalSince1970: seconds)
        }
        if let number = raw as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        return nil
    }

    // VOL-67 Copilot (fixup #29): `JSONEncoder` and `JSONDecoder` are
    // NOT thread-safe in Swift. `SyncPayloadCodec.encode/decode` is
    // called from multiple executors (main-actor repository staging,
    // the `CloudSyncCoordinator` actor pushing/pulling, the CloudKit
    // transport background queue, etc.) — a shared static instance
    // could race during concurrent encode/decode and intermittently
    // crash or corrupt output. Computed properties give every caller
    // a freshly constructed instance, which is safe. Modern Swift's
    // `JSONEncoder` is lightweight enough that the per-call
    // allocation cost is negligible compared to the serialization
    // work itself.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
