import XCTest
import VolumeArcCore

/// VOL-286 / PR #363 review (Codex P2): the refresher only writes the
/// cache when /v1/config carries an EXPLICIT flag — a 200 that omits it
/// (relay rollback, schema mismatch) must never clear an active kill
/// switch mid-incident.
final class RemoteCoachKillSwitchRefresherTests: XCTestCase {
    override func setUp() {
        super.setUp()
        RemoteCoachKillSwitchStore.reset()
        StubConfigURLProtocol.responseBody = "{}"
    }

    override func tearDown() {
        RemoteCoachKillSwitchStore.reset()
        super.tearDown()
    }

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubConfigURLProtocol.self]
        return URLSession(configuration: config)
    }

    func testOmittedFlagLeavesActiveKillSwitchUntouched() async {
        RemoteCoachKillSwitchStore.update(foundationModelCoachKilled: true)
        StubConfigURLProtocol.responseBody = "{\"unrelated\":true}"

        await RemoteCoachKillSwitchRefresher.refresh(
            relayBaseURL: URL(string: "https://relay.test")!,
            session: makeSession()
        )

        XCTAssertTrue(RemoteCoachKillSwitchStore.isFoundationModelCoachKilled,
                      "A 200 without the flag must not clear an active kill switch")
    }

    func testExplicitFalseClearsKillSwitch() async {
        RemoteCoachKillSwitchStore.update(foundationModelCoachKilled: true)
        StubConfigURLProtocol.responseBody = "{\"fmCoachDisabled\":false}"

        await RemoteCoachKillSwitchRefresher.refresh(
            relayBaseURL: URL(string: "https://relay.test")!,
            session: makeSession()
        )

        XCTAssertFalse(RemoteCoachKillSwitchStore.isFoundationModelCoachKilled)
    }

    func testExplicitTrueArmsKillSwitch() async {
        StubConfigURLProtocol.responseBody = "{\"fmCoachDisabled\":true}"

        await RemoteCoachKillSwitchRefresher.refresh(
            relayBaseURL: URL(string: "https://relay.test")!,
            session: makeSession()
        )

        XCTAssertTrue(RemoteCoachKillSwitchStore.isFoundationModelCoachKilled)
    }
}

private class StubConfigURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody = "{}"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
