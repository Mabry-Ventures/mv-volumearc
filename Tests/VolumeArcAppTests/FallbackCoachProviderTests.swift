// VOL-199: tests for `FallbackCoachProvider` error classification +
// the fallback wiring itself. The classification is the meat of the
// behavior — every error-type → fallback-eligibility decision is
// asserted here so a future refactor of the rule set can't silently
// regress to "every error becomes a fallback" or "no error ever
// fallbacks." The wiring tests use fake providers (success / throw)
// to confirm the wrapper actually delegates correctly.

import XCTest
@testable import VolumeArcCore

final class FallbackCoachProviderTests: XCTestCase {

    // MARK: - Classification: fallback-eligible

    func testRelayUnavailableIsFallbackEligible() {
        XCTAssertEqual(
            FallbackCoachProvider.fallbackReason(
                for: AIRuntimeIntegrationError.relayUnavailable(reason: "no config")
            ),
            "relay_unavailable"
        )
    }

    func testInvalidHTTPResponseIsFallbackEligible() {
        XCTAssertEqual(
            FallbackCoachProvider.fallbackReason(for: AIRuntimeIntegrationError.invalidHTTPResponse),
            "relay_invalid_response"
        )
    }

    func testRelay500IsFallbackEligible() {
        XCTAssertEqual(
            FallbackCoachProvider.fallbackReason(
                for: AIRuntimeIntegrationError.relayRequestFailed(statusCode: 500, message: "boom")
            ),
            "relay_5xx"
        )
    }

    func testRelay503IsFallbackEligible() {
        XCTAssertEqual(
            FallbackCoachProvider.fallbackReason(
                for: AIRuntimeIntegrationError.relayRequestFailed(statusCode: 503, message: "unavailable")
            ),
            "relay_5xx"
        )
    }

    func testRelay401IsFallbackEligible() {
        XCTAssertEqual(
            FallbackCoachProvider.fallbackReason(
                for: AIRuntimeIntegrationError.relayRequestFailed(statusCode: 401, message: "unauthorized")
            ),
            "relay_401"
        )
    }

    func testNetworkErrorsAreFallbackEligible() {
        let codes: [URLError.Code] = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .secureConnectionFailed,
        ]
        for code in codes {
            let reason = FallbackCoachProvider.fallbackReason(for: URLError(code))
            XCTAssertNotNil(reason, "URLError \(code) should be fallback-eligible")
            XCTAssertTrue(
                reason?.hasPrefix("network_") == true,
                "URLError reasons should start with 'network_', got: \(reason ?? "nil")"
            )
        }
    }

    // MARK: - Classification: NOT fallback-eligible

    func testRelay400IsNotFallbackEligible() {
        // 400 is a deliberate server response (malformed body); fallback
        // would just hide the bug.
        XCTAssertNil(
            FallbackCoachProvider.fallbackReason(
                for: AIRuntimeIntegrationError.relayRequestFailed(statusCode: 400, message: "bad request")
            )
        )
    }

    func testRelay403IsNotFallbackEligible() {
        // 403 is a policy/safety filter result — the user should see it,
        // not silently get a local response.
        XCTAssertNil(
            FallbackCoachProvider.fallbackReason(
                for: AIRuntimeIntegrationError.relayRequestFailed(statusCode: 403, message: "forbidden")
            )
        )
    }

    func testRelay429IsNotFallbackEligible() {
        // 429 is rate-limited; the local provider can't serve at that
        // scale, so propagating the error is more honest than masking.
        XCTAssertNil(
            FallbackCoachProvider.fallbackReason(
                for: AIRuntimeIntegrationError.relayRequestFailed(statusCode: 429, message: "rate limited")
            )
        )
    }

    func testNonAIErrorIsNotFallbackEligible() {
        struct Sentinel: Error {}
        XCTAssertNil(FallbackCoachProvider.fallbackReason(for: Sentinel()))
    }

    // MARK: - Wiring

    func testSuccessfulPrimaryDoesNotInvokeFallback() async throws {
        let primary = StubProvider(response: "primary-ok")
        let fallback = StubProvider(response: "fallback-ok")
        let wrapper = FallbackCoachProvider(primary: primary, fallback: fallback)
        let result = try await wrapper.coachResponse(for: "q", context: "ctx")
        XCTAssertEqual(result, "primary-ok")
    }

    func testTransientPrimaryFailureFallsThroughToFallback() async throws {
        let primary = StubProvider(throwing: AIRuntimeIntegrationError.relayUnavailable(reason: "no config"))
        let fallback = StubProvider(response: "fallback-saved-the-day")
        let wrapper = FallbackCoachProvider(primary: primary, fallback: fallback)
        let result = try await wrapper.coachResponse(for: "q", context: "ctx")
        XCTAssertEqual(result, "fallback-saved-the-day")
    }

    func testNonFallbackEligibleErrorPropagates() async {
        let primary = StubProvider(throwing: AIRuntimeIntegrationError.relayRequestFailed(statusCode: 400, message: "bad"))
        let fallback = StubProvider(response: "should-not-be-used")
        let wrapper = FallbackCoachProvider(primary: primary, fallback: fallback)
        do {
            _ = try await wrapper.coachResponse(for: "q", context: "ctx")
            XCTFail("Expected the 400 error to propagate")
        } catch let error as AIRuntimeIntegrationError {
            if case let .relayRequestFailed(code, _) = error {
                XCTAssertEqual(code, 400)
            } else {
                XCTFail("Got unexpected AIRuntimeIntegrationError: \(error)")
            }
        } catch {
            XCTFail("Got unexpected error type: \(error)")
        }
    }
}

/// Minimal `AICoachProvider` stub for the wiring tests. Either returns
/// a canned response or throws a canned error.
private struct StubProvider: AICoachProvider {
    let response: String?
    let error: Error?

    init(response: String) {
        self.response = response
        self.error = nil
    }

    init(throwing error: Error) {
        self.response = nil
        self.error = error
    }

    func coachResponse(for prompt: String, context: String) async throws -> String {
        if let error { throw error }
        return response ?? ""
    }
}
