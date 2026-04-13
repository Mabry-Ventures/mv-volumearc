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
            options.enableAutoSessionTracking = true
            options.enableCaptureFailedRequests = true
            options.tracesSampleRate = 0.2
            options.attachScreenshot = false
            options.enableMetricKit = true
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
