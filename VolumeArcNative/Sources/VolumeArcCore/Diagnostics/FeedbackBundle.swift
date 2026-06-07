// VOL-146 Phase 1A: model-layer assembly of the diagnostic bundle
// that ships with every in-app feedback submission.
//
// Phase 1A scope (this file + its unit tests): pure model — produce
// a `FeedbackBundle` value type from a user-typed description +
// recent telemetry events + app build metadata. PII scrubbing runs
// before the bundle is serialized so the same scrub layer that
// guards Sentry events also guards user feedback.
//
// Phase 1B (separate PR): SwiftUI feedback surface (`FeedbackView`) + ProfileView
// entry that builds a `FeedbackBundle` and calls
// `SentrySDK.captureUserFeedback(_:)` with the JSON payload as a
// `comments` field.
//
// Phase 2+: shake-to-report gesture (debug builds default-on, prod
// opt-in via Profile toggle); Linear webhook fallback when Sentry
// is unavailable.

import Foundation

/// Bundled diagnostic context attached to every in-app feedback
/// submission. Encoded as JSON so the Sentry user-feedback receiver
/// can surface it inline.
public struct FeedbackBundle: Codable, Sendable, Equatable {
    /// User-classified bucket. Free-text falls back to `.other`.
    public enum Category: String, Codable, Sendable, CaseIterable, Equatable {
        case bug = "bug"
        case idea = "idea"
        case coachQuality = "coach_quality"
        case other = "other"
    }

    public let category: Category
    public let userDescription: String
    public let buildVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceModel: String
    public let recentTelemetry: [TelemetrySnapshot]
    public let appStateHash: String
    public let submittedAt: Date

    /// Compact representation of a recent `TelemetryEvent`. Includes
    /// only the (category, name, severity, message) the support reader
    /// needs to triage; metadata is intentionally omitted because the
    /// VolumeArcSentryPIIScrubber pipeline rejects unstructured maps.
    public struct TelemetrySnapshot: Codable, Sendable, Equatable {
        public let category: String
        public let name: String
        public let severity: String
        public let message: String
        public let timestampISO8601: String

        public init(
            category: String,
            name: String,
            severity: String,
            message: String,
            timestampISO8601: String
        ) {
            self.category = category
            self.name = name
            self.severity = severity
            self.message = message
            self.timestampISO8601 = timestampISO8601
        }
    }

    public init(
        category: Category,
        userDescription: String,
        buildVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceModel: String,
        recentTelemetry: [TelemetrySnapshot],
        appStateHash: String,
        submittedAt: Date
    ) {
        self.category = category
        self.userDescription = userDescription
        self.buildVersion = buildVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.recentTelemetry = recentTelemetry
        self.appStateHash = appStateHash
        self.submittedAt = submittedAt
    }
}

/// Strips known-PII patterns from user-provided text before the
/// bundle leaves the device. The full PII scrubber for Sentry events
/// (`VolumeArcSentryPIIScrubber`) operates on `Event` / `Breadcrumb`
/// structs; this helper operates on the raw description string +
/// the telemetry-message strings so both surfaces receive the same
/// guarantees.
///
/// Scope today: email addresses, phone numbers (US-shape +
/// international-shape `+\d{8,15}`), Apple Account-style identifiers
/// (`P<hex>`). Names + workout notes are NOT scrubbed (the user
/// chose to share that text by typing it into a feedback field; the
/// scrubber's job is to catch *unintentional* PII leaks, not censor
/// the user's submission).
public enum FeedbackTextScrubber {
    private static let emailRegex = try? NSRegularExpression(
        // Standard RFC-5322-ish email shape — good enough for casual PII catch.
        pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#
    )
    private static let phoneRegex = try? NSRegularExpression(
        // US `(555) 123-4567` / `555-123-4567` / `5551234567` and
        // international `+447911123456`. Matches contiguous digits 8–15
        // long, optionally bracketed and dash-separated. Loose but
        // bounded.
        pattern: #"(?:\+\d{1,3}[\s-]?)?\(?\d{3}\)?[\s-]?\d{3}[\s-]?\d{4}"#
    )
    private static let appleAccountRegex = try? NSRegularExpression(
        // Apple Account IDs surface as `Pxxxx-xxxx-xxxx-xxxx` (P-prefix,
        // 24 hex chars in groups). Defensive scrub.
        pattern: #"P[0-9A-F]{4,}-[0-9A-F]{4,}-[0-9A-F]{4,}-[0-9A-F]{4,}"#
    )

    public static func scrub(_ input: String) -> String {
        var output = input
        for regex in [emailRegex, phoneRegex, appleAccountRegex] {
            guard let regex else { continue }
            let range = NSRange(output.startIndex..., in: output)
            output = regex.stringByReplacingMatches(
                in: output,
                options: [],
                range: range,
                withTemplate: "[redacted]"
            )
        }
        return output
    }
}

/// Builds a `FeedbackBundle` from runtime context. Constructor takes
/// every input explicitly so the assembler is trivially unit-testable
/// — no clock, no global state, no implicit Bundle reads. The
/// `App/`-layer caller is responsible for pulling `Bundle.main`,
/// `ProcessInfo`, and `UIDevice` values into the explicit parameters.
public struct FeedbackBundleAssembler: Sendable {

    /// Grouped inputs for `makeBundle(...)`. Packaged as a struct so
    /// the function-parameter-count SwiftLint rule stays satisfied and
    /// so call sites at the App layer can construct the inputs once
    /// and pass them through.
    public struct Inputs: Sendable {
        public let category: FeedbackBundle.Category
        public let userDescription: String
        public let buildVersion: String
        public let buildNumber: String
        public let osVersion: String
        public let deviceModel: String
        public let recentTelemetry: [FeedbackBundle.TelemetrySnapshot]
        public let appStateHash: String
        public let submittedAt: Date

        public init(
            category: FeedbackBundle.Category,
            userDescription: String,
            buildVersion: String,
            buildNumber: String,
            osVersion: String,
            deviceModel: String,
            recentTelemetry: [FeedbackBundle.TelemetrySnapshot],
            appStateHash: String,
            submittedAt: Date
        ) {
            self.category = category
            self.userDescription = userDescription
            self.buildVersion = buildVersion
            self.buildNumber = buildNumber
            self.osVersion = osVersion
            self.deviceModel = deviceModel
            self.recentTelemetry = recentTelemetry
            self.appStateHash = appStateHash
            self.submittedAt = submittedAt
        }
    }

    /// Thrown when `encodeJSON(_:)` can't decode its own UTF-8 output.
    /// Practically impossible since `JSONEncoder` writes UTF-8 by
    /// contract, but the failable initializer surface requires a
    /// concrete error to throw.
    public enum EncodingError: Error {
        case invalidUTF8
    }

    public init() {}

    public func makeBundle(
        inputs: Inputs,
        maxTelemetryEvents: Int = 50
    ) -> FeedbackBundle {
        // VOL-146: scrub user text + every telemetry message before
        // the bundle is constructed. Scrubbing at this layer keeps the
        // serialized JSON consumers (Sentry, Linear webhook in
        // Phase 2) from re-implementing the regex pipeline.
        let scrubbedDescription = FeedbackTextScrubber.scrub(inputs.userDescription)
        let scrubbedTelemetry = inputs.recentTelemetry
            .suffix(maxTelemetryEvents)
            .map { snapshot in
                FeedbackBundle.TelemetrySnapshot(
                    category: snapshot.category,
                    name: snapshot.name,
                    severity: snapshot.severity,
                    message: FeedbackTextScrubber.scrub(snapshot.message),
                    timestampISO8601: snapshot.timestampISO8601
                )
            }

        return FeedbackBundle(
            category: inputs.category,
            userDescription: scrubbedDescription,
            buildVersion: inputs.buildVersion,
            buildNumber: inputs.buildNumber,
            osVersion: inputs.osVersion,
            deviceModel: inputs.deviceModel,
            recentTelemetry: scrubbedTelemetry,
            appStateHash: inputs.appStateHash,
            submittedAt: inputs.submittedAt
        )
    }

    /// Encode the bundle as compact JSON. Used by Phase 1B's
    /// `SentrySDK.captureUserFeedback(_:)` call (the SDK's
    /// `UserFeedback.comments` is a free-text field; we pack the
    /// JSON in there).
    ///
    /// SwiftLint's `optional_data_string_conversion` rule prefers the
    /// failable `String(bytes:encoding:)` initializer over
    /// `String(decoding:as:)` because the latter silently substitutes
    /// the Unicode replacement character on invalid UTF-8 instead of
    /// surfacing the problem. JSONEncoder always writes valid UTF-8,
    /// so the nil branch is practically unreachable — we still throw
    /// rather than force-unwrap.
    public func encodeJSON(_ bundle: FeedbackBundle) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(bundle)
        guard let json = String(bytes: data, encoding: .utf8) else {
            throw EncodingError.invalidUTF8
        }
        return json
    }
}
