import Foundation

// VOL-87: Pre-VOL-67 legacy CKRecord → canonical `payloadJSON` synthesis.
// Lives in its own file to keep `SyncPayloadCodec.swift` under the 500-line
// file_length warning and to isolate the defensive legacy-field readers
// from the forward-looking encode/decode pipeline.
public extension SyncPayloadCodec {

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
    static func synthesizeLegacyPayloadJSON(
        kind: CloudSyncRecord.Kind,
        fields: [String: Any]
    ) -> String? {
        switch kind {
        case .workout:
            return synthesizeWorkout(fields: fields)
        case .userProfile:
            return synthesizeUserProfile(fields: fields)
        case .trainingPlan:
            return synthesizeTrainingPlan(fields: fields)
        case .coachMemory:
            return synthesizeCoachMemory(fields: fields)
        }
    }

    private static func synthesizeWorkout(fields: [String: Any]) -> String? {
        guard
            let title = fields["title"] as? String,
            let startedAt = readDate(fields["startedAt"]),
            let updatedAt = readDate(fields["updatedAt"])
        else { return nil }

        let payload = WorkoutPayload(
            title: title,
            startedAt: startedAt,
            completedAt: readDate(fields["completedAt"]),
            durationMinutes: (fields["durationMinutes"] as? Int)
                ?? (fields["durationMinutes"] as? NSNumber)?.intValue ?? 0,
            exerciseIDsCSV: (fields["exerciseIDsCSV"] as? String) ?? "",
            setsJSON: (fields["setsJSON"] as? String) ?? "[]",
            totalVolumeLoad: (fields["totalVolumeLoad"] as? Double)
                ?? (fields["totalVolumeLoad"] as? NSNumber)?.doubleValue ?? 0,
            averageRPE: (fields["averageRPE"] as? Double)
                ?? (fields["averageRPE"] as? NSNumber)?.doubleValue ?? 0,
            completedSetCount: (fields["completedSetCount"] as? Int)
                ?? (fields["completedSetCount"] as? NSNumber)?.intValue ?? 0,
            summary: (fields["summary"] as? String) ?? "",
            updatedAt: updatedAt
        )
        return encode(WorkoutEnvelope(workout: payload))
    }

    private static func synthesizeUserProfile(fields: [String: Any]) -> String? {
        guard
            let name = fields["name"] as? String,
            let updatedAt = readDate(fields["updatedAt"])
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
            preferredRepRangeLower: (fields["preferredRepRangeLower"] as? Int)
                ?? (fields["preferredRepRangeLower"] as? NSNumber)?.intValue ?? 5,
            preferredRepRangeUpper: (fields["preferredRepRangeUpper"] as? Int)
                ?? (fields["preferredRepRangeUpper"] as? NSNumber)?.intValue ?? 8,
            sessionTimeBudgetMinutes: (fields["sessionTimeBudgetMinutes"] as? Int)
                ?? (fields["sessionTimeBudgetMinutes"] as? NSNumber)?.intValue ?? 60,
            weeklyTrainingDays: (fields["weeklyTrainingDays"] as? Int)
                ?? (fields["weeklyTrainingDays"] as? NSNumber)?.intValue ?? 4,
            onboardingCompleted: (fields["onboardingCompleted"] as? Bool)
                ?? (fields["onboardingCompleted"] as? NSNumber)?.boolValue ?? false,
            updatedAt: updatedAt
        )
        return encode(UserProfileEnvelope(profile: payload))
    }

    private static func synthesizeTrainingPlan(fields: [String: Any]) -> String? {
        guard
            let workoutsJSON = fields["workoutsJSON"] as? String,
            let updatedAt = readDate(fields["updatedAt"])
        else { return nil }

        let payload = TrainingPlanPayload(
            workoutsJSON: workoutsJSON,
            updatedAt: updatedAt
        )
        return encode(TrainingPlanEnvelope(plan: payload))
    }

    private static func synthesizeCoachMemory(fields: [String: Any]) -> String? {
        guard
            let content = fields["content"] as? String,
            let createdAt = readDate(fields["createdAt"])
        else { return nil }

        let payload = CoachMemoryPayload(
            content: content,
            theme: (fields["theme"] as? String) ?? "",
            createdAt: createdAt
        )
        return encode(CoachMemoryEnvelope(memory: payload))
    }

    /// Coerce an arbitrary `Any?` field value into a `Date`. Supports
    /// direct `Date` values (what `CKRecord` returns for date fields)
    /// as well as `TimeInterval` / numeric types for defensive
    /// compatibility with older wire formats.
    ///
    /// VOL-67 Codex P2 (fixup #32): also accept string forms. The
    /// pre-`payloadJSON` transport stored some CKRecord field values
    /// as `NSString` (particularly on early builds that serialized
    /// through plist / JSON intermediates), so legacy records with
    /// string timestamps would otherwise fail `synthesizeLegacyPayloadJSON`
    /// and get dropped by the pull path. Fixup #21/#30's cursor-
    /// reset behavior then traps affected devices in an infinite
    /// re-fetch loop: pull → skip malformed → reset cursor → pull →
    /// skip again → forever, without ever applying those records.
    ///
    /// Accept both ISO 8601 (`"2024-01-15T12:34:56Z"`) and numeric
    /// string (`"1705321096"` / `"1705321096.5"`) forms. Numeric
    /// strings are interpreted as Unix timestamps in seconds since
    /// 1970, matching the `TimeInterval`/`NSNumber` branches above.
    static func readDate(_ raw: Any?) -> Date? {
        if let date = raw as? Date {
            return date
        }
        if let seconds = raw as? TimeInterval {
            return Date(timeIntervalSince1970: seconds)
        }
        if let number = raw as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let string = raw as? String {
            // Try numeric string first (e.g., "1705321096" from a
            // plist/JSON that preserved the epoch as a string).
            if let seconds = TimeInterval(string) {
                return Date(timeIntervalSince1970: seconds)
            }
            // Fall back to ISO 8601 for well-formed timestamp strings.
            if let parsed = iso8601Formatter.date(from: string) {
                return parsed
            }
            // Also accept the ISO 8601 variant without fractional
            // seconds (the default for `ISO8601DateFormatter` without
            // options), in case the upstream producer omitted the
            // `.withFractionalSeconds` flag.
            if let parsed = iso8601FormatterNoFraction.date(from: string) {
                return parsed
            }
        }
        return nil
    }

    /// ISO 8601 parsers for legacy timestamp strings. Computed
    /// properties (not `static let`) because Swift 6 strict
    /// concurrency treats `ISO8601DateFormatter` as non-`Sendable`
    /// and rejects shared static instances. Same pattern as the
    /// `encoder`/`decoder` properties in the main file — allocating
    /// a fresh formatter per call is cheap compared to the parse
    /// work itself.
    private static var iso8601Formatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static var iso8601FormatterNoFraction: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }
}
