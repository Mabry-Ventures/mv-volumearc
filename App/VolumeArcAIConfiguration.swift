import Foundation
import VolumeArcCore

enum VolumeArcAIConfiguration {
    private static let secureStore = VolumeArcSecureStore()
    private static let baseURLKey = "ai.relay.baseURL"

    /// Hosts we will accept for the AI relay base URL. The relay is operated
    /// by Mabry Ventures — any other host would route prompt traffic (and
    /// in principle user PII) to a third party and must be rejected at
    /// read-time. Case-insensitive match; extend here when adding new relay
    /// endpoints.
    ///
    /// Current production target is `volumearc-ai-relay.jared-b6b.workers.dev`
    /// (auto-assigned Cloudflare subdomain). `relay.volumearc.app` ships when
    /// the custom domain is wired in Cloudflare — iOS accepts both so the
    /// flip is zero-downtime. `relay.mabryventures.com` is kept as a legacy
    /// fallback.
    static let allowedHosts: Set<String> = [
        "relay.volumearc.app",
        "volumearc-ai-relay.jared-b6b.workers.dev",
        "relay.mabryventures.com",
    ]

    /// Category used when emitting relay-URL validation telemetry. Kept as
    /// a constant so tests and downstream sinks can filter on it.
    static let telemetryCategory = "ai.relay.config"

    static func bootstrapRelaySecretsIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        let baseURLString = environment["VOLUMEARC_OPENAI_BASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "VolumeArcOpenAIBaseURL") as? String

        if let baseURLString, baseURLString.isEmpty == false {
            do {
                try secureStore.save(baseURLString, for: baseURLKey)
            } catch {
                // Relay URL will still be available from the environment or bundle
                // for the current launch, but won't persist to Keychain for next launch.
            }
        }
    }

    static var relayConfiguration: OpenAIRelayConfiguration? {
        relayConfiguration(telemetrySink: nil)
    }

    /// Resolve the relay configuration with an optional telemetry sink for
    /// validation failures. Tests inject a sink to assert which rule failed
    /// without relying on global state.
    ///
    /// The URL flows Info.plist / env var -> Keychain -> this read. A
    /// malformed value (missing scheme, whitespace-contaminated host,
    /// typo'd domain) must not silently reach request time: it would
    /// produce a confusing network error and, in principle, a stray value
    /// could route traffic to an unintended host. We validate here and
    /// fall back to `nil`, which the AI runtime factory already converts
    /// into `LocalHeuristicAICoachProvider`.
    static func relayConfiguration(telemetrySink: TelemetrySink?) -> OpenAIRelayConfiguration? {
        let rawString = (try? secureStore.load(baseURLKey))
            ?? ProcessInfo.processInfo.environment["VOLUMEARC_OPENAI_BASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "VolumeArcOpenAIBaseURL") as? String

        guard let baseURL = validatedRelayURL(from: rawString, telemetrySink: telemetrySink) else {
            return nil
        }

        return OpenAIRelayConfiguration(baseURL: baseURL, bearerToken: "session-managed")
    }

    /// Validate a candidate relay URL string. Returns the parsed `URL` or
    /// `nil` — never the raw value, so callers cannot accidentally log a
    /// credential-bearing string. Emits a `.error` telemetry event
    /// describing which rule failed (never the value itself).
    static func validatedRelayURL(
        from rawValue: String?,
        telemetrySink: TelemetrySink? = nil
    ) -> URL? {
        guard let rawValue else {
            emit(failure: "missing", sink: telemetrySink)
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty == false else {
            emit(failure: "empty", sink: telemetrySink)
            return nil
        }

        // Reject contamination: leading/trailing whitespace is a loud
        // configuration error, not something to silently paper over. This
        // catches Info.plist copy-paste mistakes and YAML values that
        // drift whitespace in through a pipeline.
        guard trimmed == rawValue else {
            emit(failure: "whitespace", sink: telemetrySink)
            return nil
        }

        guard let components = URLComponents(string: trimmed) else {
            emit(failure: "unparseable", sink: telemetrySink)
            return nil
        }

        guard let scheme = components.scheme, scheme.lowercased() == "https" else {
            emit(failure: "non-https-scheme", sink: telemetrySink)
            return nil
        }

        guard let host = components.host, host.isEmpty == false else {
            emit(failure: "missing-host", sink: telemetrySink)
            return nil
        }

        let normalizedHost = host.lowercased()
        guard allowedHosts.contains(normalizedHost) else {
            emit(failure: "host-not-allowlisted", sink: telemetrySink)
            return nil
        }

        guard let url = components.url else {
            emit(failure: "unresolvable-url", sink: telemetrySink)
            return nil
        }

        return url
    }

    static var startupWarning: String? {
        // Use the non-sink variant here: startup surfaces the warning via
        // the operational signal pipeline already, so we don't double-log.
        relayConfiguration == nil
            ? "OpenAI relay base URL is not configured or invalid, so cloud AI and live voice are unavailable on this build."
            : nil
    }

    /// Produce a startup warning AND fire the telemetry event exactly
    /// once, for wiring into the app's operational signals pipeline. The
    /// read-time getter (`relayConfiguration`) must stay quiet to avoid
    /// firing an .error on every AI request, so the app init path uses
    /// this method during signal assembly — once per launch.
    static func startupWarning(recordingTo telemetrySink: TelemetrySink) -> String? {
        let rawString = (try? secureStore.load(baseURLKey))
            ?? ProcessInfo.processInfo.environment["VOLUMEARC_OPENAI_BASE_URL"]
            ?? Bundle.main.object(forInfoDictionaryKey: "VolumeArcOpenAIBaseURL") as? String

        if validatedRelayURL(from: rawString, telemetrySink: telemetrySink) == nil {
            return "AI relay URL invalid or missing; cloud AI and live voice are disabled on this build."
        }
        return nil
    }

    /// Emit a validation failure without including the raw URL value —
    /// a misconfigured pipeline could stuff a token or other credential
    /// into the URL, and we don't want that in the telemetry buffer.
    private static func emit(failure rule: String, sink: TelemetrySink?) {
        guard let sink else { return }
        sink.record(
            TelemetryEvent(
                category: telemetryCategory,
                name: "relay_url_rejected",
                severity: .error,
                message: "AI relay URL rejected: \(rule). Cloud AI disabled; falling back to local heuristic coach.",
                metadata: ["rule": rule]
            )
        )
    }
}
