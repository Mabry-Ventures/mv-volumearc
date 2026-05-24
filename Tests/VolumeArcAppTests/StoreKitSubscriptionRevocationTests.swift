// VOL-142 Phase 1: placeholder for the live StoreKit Test refund path.
//
// The revocation state machine is covered by StoreKitSubscriptionStateMachineTests.
// This live SKTestSession version is intentionally skipped until VOL-227/VOL-230
// are resolved; importing StoreKitTest while skipped triggers an Apple SDK
// deprecation warning under Xcode 26.5, so the placeholder stays dependency-free.

import XCTest

@MainActor
final class StoreKitSubscriptionRevocationTests: XCTestCase {
    func testRefundRemovesEntitlementAndRecordsTelemetry() async throws {
        throw XCTSkip(
            "VOL-227: SKTestSession refund propagation unreliable on CI."
        )
    }
}
