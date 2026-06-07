// VOL-199: relay → local fallback wrapper.
//
// The 2026-05-18 audit (F-H-002) found that `docs/USER_JOURNEYS.md`
// and `docs/INCIDENTS.md` promise local heuristic fallback when the
// relay returns 5xx / 401 / times out / is offline. The implemented
// behavior was different: `AIRelayCoachProvider.streamCoachResponse`
// throws on auth / HTTP / SSE errors, the dashboard converts that to
// a generic user-visible error message, and the local
// `LocalHeuristicAICoachProvider` never runs.
//
// This wrapper closes the gap. `FallbackCoachProvider(primary:fallback:)`
// runs `primary` first; on any `AIRuntimeIntegrationError` that
// represents transient infrastructure failure (relay unreachable,
// network-layer error, auth failure, transient 5xx), it transparently
// switches to `fallback` for that single request. Errors that are NOT
// fallback-eligible (a deliberate 400 from the relay because the
// prompt body was malformed, for example) propagate unchanged so the
// caller still sees a real error.
//
// Telemetry: `coach.fallback_used` event records each invocation,
// keyed by the reason. Lets operators watch fallback rates as a
// proxy for relay health AND lets product see how often the local
// path is on stage.

import Foundation

public extension Notification.Name {
    static let coachFallbackUsed = Notification.Name("VolumeArcCoachFallbackUsed")
}

public enum CoachFallbackNotificationUserInfoKey {
    public static let reason = "reason"
    public static let path = "path"
}

public protocol AIRelaySessionRefreshing: Sendable {
    func refreshAfterUnauthorized() async
}

public struct RelayUnauthorizedRetryCoachProvider: AICoachProvider {
    private let primary: AICoachProvider
    private let sessionRefresher: AIRelaySessionRefreshing
    private let telemetrySink: (any TelemetrySink)?

    public init(
        primary: AICoachProvider,
        sessionRefresher: AIRelaySessionRefreshing,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.primary = primary
        self.sessionRefresher = sessionRefresher
        self.telemetrySink = telemetrySink
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        do {
            return try await primary.coachResponse(for: prompt, context: context)
        } catch {
            guard Self.isUnauthorized(error) else { throw error }
            await refreshSession(path: "non_streaming")
            return try await primary.coachResponse(for: prompt, context: context)
        }
    }

    public func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var didRetry = false
                while true {
                    var yieldedAnything = false
                    do {
                        for try await chunk in primary.streamCoachResponse(for: prompt, context: context) {
                            yieldedAnything = true
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                        return
                    } catch {
                        guard !didRetry,
                              !yieldedAnything,
                              Self.isUnauthorized(error) else {
                            continuation.finish(throwing: error)
                            return
                        }
                        didRetry = true
                        await refreshSession(path: "streaming")
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func isUnauthorized(_ error: Error) -> Bool {
        if case AIRuntimeIntegrationError.relayRequestFailed(let statusCode, _) = error {
            return statusCode == 401
        }
        return false
    }

    private func refreshSession(path: String) async {
        await sessionRefresher.refreshAfterUnauthorized()
        telemetrySink?.record(TelemetryEvent(
            category: "relay",
            name: "session_refreshed",
            severity: .info,
            message: "Relay session refreshed after unauthorized response.",
            metadata: ["path": path]
        ))
    }
}

public struct FallbackCoachProvider: AICoachProvider {
    private let primary: AICoachProvider
    private let fallback: AICoachProvider
    private let telemetrySink: (any TelemetrySink)?

    public init(
        primary: AICoachProvider,
        fallback: AICoachProvider,
        telemetrySink: (any TelemetrySink)? = nil
    ) {
        self.primary = primary
        self.fallback = fallback
        self.telemetrySink = telemetrySink
    }

    public func coachResponse(for prompt: String, context: String) async throws -> String {
        do {
            return try await primary.coachResponse(for: prompt, context: context)
        } catch {
            guard let reason = Self.fallbackReason(for: error) else {
                throw error
            }
            emitFallbackTelemetry(reason: reason, path: "non_streaming")
            return try await fallback.coachResponse(for: prompt, context: context)
        }
    }

    public func streamCoachResponse(
        for prompt: String,
        context: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                // Try the primary stream first. If it throws before
                // yielding ANY chunk and the error is fallback-
                // eligible, transparently switch to the fallback's
                // stream. If it has already yielded chunks (we got a
                // partial response and then the relay dropped), bail
                // with the partial — surfacing fallback content
                // mid-stream would confuse the UI and the user.
                var yieldedAnything = false
                do {
                    for try await chunk in primary.streamCoachResponse(for: prompt, context: context) {
                        yieldedAnything = true
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    if !yieldedAnything, let reason = Self.fallbackReason(for: error) {
                        emitFallbackTelemetry(reason: reason, path: "streaming")
                        do {
                            for try await chunk in fallback.streamCoachResponse(for: prompt, context: context) {
                                continuation.yield(chunk)
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Internals

    /// Classify an error as fallback-eligible. Returns a stable string
    /// identifier for telemetry, or `nil` if the caller should see the
    /// original error.
    ///
    /// Eligible:
    /// - `relayUnavailable` (config missing, network down)
    /// - `relayRequestFailed` with 5xx (transient server error)
    /// - `relayRequestFailed` with 401 (auth — rare but legitimately
    ///   transient when the signing-key bootstrap path is misconfigured;
    ///   VOL-196 fixed the most common cause)
    /// - `URLError` (network-layer issues: DNS, connection refused,
    ///   TLS handshake, timeout)
    ///
    /// NOT eligible (errors that indicate a deliberate server response):
    /// - `relayRequestFailed` with 400 (malformed body — fallback
    ///   would just hide the bug)
    /// - `relayRequestFailed` with 403 (forbidden — likely a policy /
    ///   safety filter; the user should see that, not silently get a
    ///   local response)
    /// - `relayRequestFailed` with 429 (rate-limited — the local
    ///   provider can't actually serve at that scale; let it fail)
    /// - Any non-AI error (encoding, programming bugs).
    static func fallbackReason(for error: Error) -> String? {
        if let aiError = error as? AIRuntimeIntegrationError {
            switch aiError {
            case .relayUnavailable:
                return "relay_unavailable"
            case .invalidHTTPResponse:
                return "relay_invalid_response"
            case let .relayRequestFailed(statusCode, _):
                switch statusCode {
                case 500...599:
                    return "relay_5xx"
                case 401:
                    return "relay_401"
                default:
                    return nil
                }
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut,
                 .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
                 .secureConnectionFailed:
                return "network_\(urlError.code.rawValue)"
            default:
                return nil
            }
        }
        return nil
    }

    private func emitFallbackTelemetry(reason: String, path: String) {
        telemetrySink?.record(TelemetryEvent(
            category: "coach",
            name: "fallback_used",
            severity: .warning,
            message: "Coach request fell back from relay to local provider.",
            metadata: [
                "reason": reason,
                "path": path
            ]
        ))
        NotificationCenter.default.post(
            name: .coachFallbackUsed,
            object: nil,
            userInfo: [
                CoachFallbackNotificationUserInfoKey.reason: reason,
                CoachFallbackNotificationUserInfoKey.path: path
            ]
        )
    }
}
