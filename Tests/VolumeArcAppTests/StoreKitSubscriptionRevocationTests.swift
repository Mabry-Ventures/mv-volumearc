// VOL-142 Phase 1: unit coverage for the refund / revocation path.
//
// The bug this test pins: `StoreKitSubscriptionStore.listenForTransactions`
// previously only INSERTED productIDs from `Transaction.updates`,
// never REMOVED on revocation. A user who got refunded would stay
// marked premium until the next `refreshEntitlements()` call —
// typically the next app launch. Apple's IAP review stresses the
// refund path, so this is a guaranteed App Store-rejection trap.
//
// The fix routes every `Transaction.updates` event through
// `applyTransactionUpdate(_:)`, which checks `revocationDate` and
// either inserts (entitlement granted) or removes (refund / family-
// share revocation). Telemetry events fire on every state change.
//
// Phase 2 follow-ups (separate PRs):
//   - Family sharing: `transaction.ownershipType == .familyShared`
//   - Grace period: `subscription.renewalState == .inGracePeriod`
//   - Billing retry: retry succeeds → re-granted; fails → revoked
//   - Ask-to-buy: `.pending` → telemetry breadcrumb (this PR covers
//     the breadcrumb but doesn't drive the approve/deny side from
//     SKTestSession)

#if canImport(StoreKit) && canImport(SwiftData)
import StoreKit
import StoreKitTest
import XCTest
@testable import VolumeArcCore

@MainActor
final class StoreKitSubscriptionRevocationTests: XCTestCase {
    private var session: SKTestSession!

    private static let monthlyProductID = "com.mabryventures.VolumeArc.premium.monthly"
    private static let allProductIDs = [
        monthlyProductID,
        "com.mabryventures.VolumeArc.premium.yearly",
    ]

    override func setUp() async throws {
        // `VolumeArcTests.storekit` lives under `Tests/VolumeArcAppUITests/`
        // and is referenced by both test targets via the Xcode-project
        // generator's resource wiring (VOL-142 PR description for the
        // exact resource path). Failing to find it surfaces a clear
        // SKTestSession initialization error rather than a confusing
        // "no products loaded" downstream.
        session = try SKTestSession(configurationFileNamed: "VolumeArcTests")
        session.disableDialogs = true
        session.clearTransactions()
        session.askToBuyEnabled = false
    }

    override func tearDown() async throws {
        session?.clearTransactions()
        session = nil
    }

    /// Pin the revocation contract: a refunded transaction observed
    /// via `Transaction.updates` removes the productID from
    /// `purchasedProductIDs`. Emits a `subscription.entitlement.revoked`
    /// telemetry event with the `revocationReason` in metadata.
    ///
    /// Acceptance: prior to the fix, this test fails with
    /// `purchasedProductIDs.contains(monthlyProductID) == true` after
    /// refund (the listener only inserted, never removed).
    func testRefundRemovesEntitlementAndRecordsTelemetry() async throws {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(
            productIDs: Self.allProductIDs,
            telemetry: telemetry
        )

        // Wait for product load + initial entitlement refresh to settle.
        // The store's init kicks off `loadProducts` async; a short wait
        // is plenty under SKTestSession's deterministic timing.
        try await waitFor({ store.loadingState == .loaded }, timeout: 5)

        // Purchase the monthly product.
        let monthly = try XCTUnwrap(
            store.products.first { $0.id == Self.monthlyProductID },
            "Monthly product must load from VolumeArcTests.storekit"
        )
        let purchased = await store.purchase(monthly)
        XCTAssertTrue(purchased, "Initial purchase should succeed under SKTestSession")
        XCTAssertTrue(store.isPremium, "Store should report premium after purchase")
        XCTAssertTrue(
            store.purchasedProductIDs.contains(Self.monthlyProductID),
            "Monthly product ID should be in purchasedProductIDs after purchase"
        )

        // Refund the purchase via SKTestSession. The session synthesizes
        // a `Transaction.updates` event with a non-nil revocationDate,
        // which the store's listener must catch and remove from the
        // purchased set.
        //
        // VOL-142 (Codex on PR #158): `SKTestSession.allTransactions()`
        // is an `async` method in Xcode 26's StoreKitTest, NOT a
        // synchronous property as an earlier version of this test
        // assumed. The Build & Test failure on the fixup SHA bottomed
        // out in:
        //   error: function 'transactions' was used as a property; add () to call it
        // — the compiler was inferring `allTransactions` (without `()`)
        // as a function reference. The right form is to await the
        // call, then `.first` on the returned `[SKTestTransaction]`.
        let allTxns = await session.allTransactions()
        let transaction = try XCTUnwrap(
            allTxns.first { $0.productID == Self.monthlyProductID },
            "SKTestSession should have a transaction for the monthly product"
        )
        try await session.refundTransaction(identifier: UInt(transaction.identifier))

        // The revocation propagates through the detached transaction
        // listener Task — give it a beat to fire. The store mutates on
        // MainActor so the assertion can run synchronously after the
        // wait condition resolves.
        try await waitFor(
            { !store.purchasedProductIDs.contains(Self.monthlyProductID) },
            timeout: 5,
            failureMessage: "Refund should remove productID from purchasedProductIDs"
        )

        XCTAssertFalse(store.isPremium, "Store should NOT report premium after refund")

        // Telemetry: at least one `revoked` event should have fired,
        // with the productID in metadata. The `granted` event from the
        // initial purchase should also be present.
        let events = telemetry.currentEvents
        XCTAssertTrue(
            events.contains { $0.category == "subscription.entitlement" && $0.name == "granted" },
            "Initial purchase should record a `subscription.entitlement.granted` event"
        )
        XCTAssertTrue(
            events.contains { event in
                event.category == "subscription.entitlement"
                    && event.name == "revoked"
                    && event.metadata["productID"] == Self.monthlyProductID
            },
            "Refund should record a `subscription.entitlement.revoked` event with productID"
        )
    }

    // MARK: - Helpers

    /// Poll `condition` until it returns true or `timeout` elapses.
    /// XCUITest has `waitForExistence`; XCTestCase doesn't ship an
    /// equivalent for arbitrary predicates, so we roll a small one.
    private func waitFor(
        _ condition: @escaping () async -> Bool,
        timeout: TimeInterval,
        failureMessage: String = "Condition not met within timeout",
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTFail(failureMessage, file: file, line: line)
    }
}
#endif
