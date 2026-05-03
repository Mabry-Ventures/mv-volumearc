#if canImport(Sentry)
import Foundation
import Sentry
import VolumeArcCore

enum VolumeArcSentryConfiguration {
    private static let secureStore = VolumeArcSecureStore()
    private static let dsnKey = "sentry.dsn"

    static func bootstrapIfNeeded() {
        guard let dsn = resolveDSN() else { return }

        SentrySDK.start { options in
            options.dsn = dsn

            // VOL-129: explicit release name so Sentry events group per
            // release ("com.mabryventures.VolumeArc@1.0.2+12345"). dSYMs
            // are matched by debug-id (UUID), so symbolication doesn't
            // require this — but the release tag is what makes "filter to
            // crashes in 1.0.2" work in the Sentry UI.
            options.releaseName = computeReleaseName()

            // Sessions + crashes
            options.enableAutoSessionTracking = true
            options.enableCaptureFailedRequests = true

            // VOL-129: Performance + Profiling. tracesSampleRate stays at
            // 0.2 (20% of transactions become performance events).
            // profilesSampleRate is multiplied with the trace rate, so
            // 0.1 here = 2% of all transactions get a profile attached
            // (10% of the 20% sampled).
            options.tracesSampleRate = 0.2
            options.profilesSampleRate = 0.1

            // VOL-129: Session Replay for crashed sessions only.
            // sessionSampleRate=0 means we never replay normal sessions
            // (cost / privacy). onErrorSampleRate=1 means every crash
            // session gets a full replay so the engineer reproducing a
            // crash sees the user's last 30s of UI. maskAllText hides
            // every text element (workout notes, coach memory, profile
            // fields) so HealthKit numbers and free-text never appear in
            // the replay frames. Images are not masked because we don't
            // render PII in images today; revisit if/when we add user
            // photo uploads.
            //
            // Requires sentry-cocoa 8.36.0+. We are pinned to 8.58.1 in
            // `scripts/generate_xcode_project.rb` + `Package.resolved`.
            let replay = SentryReplayOptions(
                sessionSampleRate: 0.0,
                onErrorSampleRate: 1.0,
                maskAllText: true,
                maskAllImages: false
            )
            options.sessionReplay = replay

            // VOL-129: App-hang (ANR) detection. Default is 2s which is
            // too aggressive — many normal launches hit 2s briefly during
            // SwiftData / CloudKit warm-up. 5s matches Android's ANR
            // threshold and is the practical signal level for "the user
            // is actually stuck."
            options.enableAppHangTracking = true
            options.appHangTimeoutInterval = 5.0

            options.enableMetricKit = true
            options.attachScreenshot = false

            // VOL-72: strip email/phone/device-identifier/session-token
            // patterns from crash events and breadcrumbs before they
            // leave the device. Also drops breadcrumbs from the
            // user-input / coach.memory categories entirely and nils
            // Sentry's structured user fields (email/username/ipAddress).
            // Pure functions in `SentryPIIScrubber` so they're unit-testable
            // without a live Sentry; see `VolumeArcSentryPIIScrubberTests`.
            options.beforeSend = { event in
                SentryPIIScrubber.scrub(event: event)
            }
            options.beforeBreadcrumb = { crumb in
                SentryPIIScrubber.scrub(breadcrumb: crumb)
            }
            #if DEBUG
            options.debug = true
            options.environment = "development"
            #else
            options.environment = "production"
            #endif
        }
    }

    static var isConfigured: Bool {
        resolveDSN() != nil
    }

    static var startupWarning: String? {
        isConfigured
            ? nil
            : "Sentry DSN is not configured, so crash reporting is unavailable on this build."
    }

    private static func resolveDSN() -> String? {
        let dsn = (try? secureStore.load(dsnKey))
            ?? ProcessInfo.processInfo.environment["VOLUMEARC_SENTRY_DSN"]
            ?? Bundle.main.object(forInfoDictionaryKey: "VolumeArcSentryDSN") as? String

        guard let dsn, dsn.isEmpty == false else { return nil }
        return dsn
    }

    /// Build a release identifier matching Sentry's recommended convention
    /// `<bundleId>@<MARKETING_VERSION>+<CFBundleVersion>` (e.g.
    /// `com.mabryventures.VolumeArc@1.0.2+12345`).
    ///
    /// Two overloads: production calls the `bundle:` form (defaulting to
    /// `Bundle.main`); `VolumeArcSentryConfigurationTests` calls the
    /// 3-arg pure form directly so it doesn't have to subclass `Bundle`
    /// (which trips Foundation's `init(path:)` designated-initializer
    /// requirement).
    static func computeReleaseName(bundle: Bundle = .main) -> String {
        computeReleaseName(
            bundleID: bundle.bundleIdentifier,
            marketingVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            buildNumber: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        )
    }

    static func computeReleaseName(
        bundleID: String?,
        marketingVersion: String?,
        buildNumber: String?
    ) -> String {
        let resolvedBundleID = bundleID ?? "com.mabryventures.VolumeArc"
        let resolvedMarketing = marketingVersion ?? "0.0.0"
        let resolvedBuild = buildNumber ?? "0"
        return "\(resolvedBundleID)@\(resolvedMarketing)+\(resolvedBuild)"
    }
}

struct SentryTelemetrySink: TelemetrySink {
    func record(_ event: TelemetryEvent) {
        let breadcrumb = Breadcrumb(level: sentryLevel(for: event.severity), category: event.category)
        breadcrumb.message = event.message
        breadcrumb.data = event.metadata
        SentrySDK.addBreadcrumb(breadcrumb)

        if event.severity == .error {
            SentrySDK.capture(message: "[\(event.category)] \(event.name): \(event.message)")
        }
    }

    private func sentryLevel(for severity: TelemetrySeverity) -> SentryLevel {
        switch severity {
        case .info:
            return .info
        case .warning:
            return .warning
        case .error:
            return .error
        }
    }
}
#endif
