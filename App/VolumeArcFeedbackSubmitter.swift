// VOL-176: App-layer glue that turns a (`FeedbackBundle.Category`,
// description) pair from `FeedbackView` into a fully-loaded
// `FeedbackBundle`, encodes it as JSON, forwards it to Sentry via
// `SentrySDK.captureUserFeedback(_:)` when Sentry is wired, and records
// a `feedback.submitted` telemetry event.
//
// The submitter lives at the App layer (not VolumeArcUI) because:
//   - It reads `Bundle.main` / `ProcessInfo` / `UIDevice` for build
//     metadata. VolumeArcUI compiles into the watch + widget extensions
//     where some of those APIs aren't available.
//   - It imports `Sentry`. VolumeArcUI deliberately stays Sentry-free
//     so tests + SwiftUI previews don't need the SDK.
//
// Architecture lines up with the `TelemetrySink` injection pattern: a
// single closure is constructed at startup, captured by `RootDashboardView`,
// and propagated to `ProfileView`.

import Foundation
import VolumeArcCore

#if canImport(UIKit)
import UIKit
#endif

#if canImport(Sentry)
import Sentry
#endif

@MainActor
struct VolumeArcFeedbackSubmitter {
    /// Reads recent telemetry to attach to outgoing bundles. The live
    /// app passes a closure backed by `InMemoryTelemetrySink.currentEvents`
    /// (deterministic / debug builds) or `UserDefaultsTelemetrySink.loadEvents()`
    /// (release). Tests substitute a deterministic stub.
    private let recentTelemetry: @MainActor () -> [TelemetryEvent]

    /// Sink that receives the `feedback.submitted` confirmation event.
    /// Same fanout that other App-layer surfaces use (Sentry + UserDefaults
    /// + OSLog + InMemory in deterministic builds).
    private let telemetrySink: any TelemetrySink

    private let assembler = FeedbackBundleAssembler()
    private let maxAttachedEvents: Int

    init(
        telemetrySink: any TelemetrySink,
        recentTelemetry: @escaping @MainActor () -> [TelemetryEvent],
        maxAttachedEvents: Int = 50
    ) {
        self.telemetrySink = telemetrySink
        self.recentTelemetry = recentTelemetry
        self.maxAttachedEvents = maxAttachedEvents
    }

    /// Public submission entry point — the closure handed to
    /// `RootDashboardView(onSendFeedback:)`.
    func submit(category: FeedbackBundle.Category, description: String) {
        let inputs = makeInputs(category: category, description: description)
        let bundle = assembler.makeBundle(inputs: inputs, maxTelemetryEvents: maxAttachedEvents)

        let encoded: String
        do {
            encoded = try assembler.encodeJSON(bundle)
        } catch {
            // The JSON encoder should never fail on `FeedbackBundle`'s
            // pure-value-type shape, but if it does we still record the
            // confirmation telemetry so the UX surfaces a successful
            // submission. The Sentry payload is the lossy step.
            telemetrySink.record(makeConfirmationEvent(
                category: category,
                buildNumber: inputs.buildNumber,
                encodedBytes: 0,
                isFallback: true
            ))
            return
        }

        #if canImport(Sentry)
        let feedback = SentryFeedback(
            message: encoded,
            name: nil,
            email: nil,
            source: .custom
        )
        feedback.contactEmail = nil
        SentrySDK.capture(feedback: feedback)
        #endif

        telemetrySink.record(makeConfirmationEvent(
            category: category,
            buildNumber: inputs.buildNumber,
            encodedBytes: encoded.utf8.count,
            isFallback: false
        ))
    }

    // MARK: - Inputs

    private func makeInputs(
        category: FeedbackBundle.Category,
        description: String
    ) -> FeedbackBundleAssembler.Inputs {
        let info = Bundle.main.infoDictionary ?? [:]
        let buildVersion = (info["CFBundleShortVersionString"] as? String) ?? "0.0"
        let buildNumber = (info["CFBundleVersion"] as? String) ?? "0"

        #if canImport(UIKit)
        let osVersion = UIDevice.current.systemVersion
        let deviceModel = UIDevice.current.model
        #else
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let deviceModel = "Unknown"
        #endif

        let snapshots = recentTelemetry().map { event in
            FeedbackBundle.TelemetrySnapshot(
                category: event.category,
                name: event.name,
                severity: event.severity.rawValue,
                message: event.message,
                timestampISO8601: Self.iso8601Formatter.string(from: event.timestamp)
            )
        }

        // App-state hash is intentionally coarse — it's a fingerprint
        // for "are two reports from the same approximate runtime?" Not
        // a forensic anchor. Use the number of cached events plus the
        // build number for a sub-1ms identifier.
        let appStateHash = "events=\(snapshots.count)|build=\(buildNumber)"

        return FeedbackBundleAssembler.Inputs(
            category: category,
            userDescription: description,
            buildVersion: buildVersion,
            buildNumber: buildNumber,
            osVersion: osVersion,
            deviceModel: deviceModel,
            recentTelemetry: snapshots,
            appStateHash: appStateHash,
            submittedAt: .now
        )
    }

    private func makeConfirmationEvent(
        category: FeedbackBundle.Category,
        buildNumber: String,
        encodedBytes: Int,
        isFallback: Bool
    ) -> TelemetryEvent {
        var metadata: [String: String] = [
            "category": category.rawValue,
            "build": buildNumber,
            "bytes": String(encodedBytes)
        ]
        if isFallback {
            metadata["fallback"] = "encoding_failed"
        }
        return TelemetryEvent(
            category: "feedback",
            name: "submitted",
            severity: .info,
            message: "User submitted feedback",
            metadata: metadata
        )
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
