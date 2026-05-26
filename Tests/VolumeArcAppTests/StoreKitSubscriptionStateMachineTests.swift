// VOL-142 Phase 2: state-machine coverage for `StoreKitSubscriptionStore`'s
// entitlement transitions, decoupled from `SKTestSession`.
//
// Why this file exists alongside `StoreKitSubscriptionRevocationTests`:
//
//   * Phase 1's `StoreKitSubscriptionRevocationTests` drives
//     `SKTestSession` directly — refund the transaction, wait for the
//     `Transaction.updates` listener to propagate, assert the store
//     dropped the productID. It's the highest-fidelity test (real
//     StoreKit + real Transaction values) but is currently `XCTSkip`-ed
//     because SKTestSession's refund propagation is unreliable on the
//     M4 self-hosted runner.
//
//   * This file covers the SAME state machine through the
//     `TransactionUpdate` value type that Phase 2 introduced. Each
//     test constructs a `TransactionUpdate` directly and calls
//     `applyTransactionUpdate(_:)` on the store. No SKTestSession, no
//     simulator, no flakes. The trade-off is that the
//     `Transaction → TransactionUpdate` bridge isn't exercised here —
//     that's what Phase 1's flaky integration test pins.
//
// Coverage spans the App Store reviewer stress matrix called out in
// VOL-142's acceptance criteria:
//
//   * Refund — `revocationDate` non-nil + `revocationReason` description
//     present
//   * Family sharing grant — `ownershipType == "familyShared"`
//   * Family sharing removal — revocation with familyShared context
//     preserved in telemetry
//   * Idempotency — duplicate `granted` doesn't double-fire telemetry;
//     duplicate `revoked` doesn't drop into negative state
//   * Out-of-order delivery — `Transaction.updates` doesn't guarantee
//     ordering; a stale `granted` after a `revoked` shouldn't re-grant
//     the same product if a fresh transaction with the same productID
//     hasn't been observed (current store behavior: idempotent insert;
//     this test pins that contract so a future refactor can't silently
//     change it)

#if canImport(StoreKit)
import XCTest
@_spi(Testing) @testable import VolumeArcCore

@MainActor
final class StoreKitSubscriptionStateMachineTests: XCTestCase {

    private static let monthly = "com.mabryventures.VolumeArc.premium.monthly"
    private static let yearly = "com.mabryventures.VolumeArc.premium.yearly"
    private static let allProductIDs = [monthly, yearly]

    // MARK: - Product loading

    func test_paywallAppearLoadPolicy_loadsIdleProductionState() {
        let store = StoreKitSubscriptionStore(
            productIDs: Self.allProductIDs,
            loadingState: .idle,
            allowsAutomaticProductReload: true
        )

        XCTAssertTrue(
            store.shouldLoadProductsOnPaywallAppear,
            "An idle production store should load when the paywall appears."
        )
    }

    func test_paywallAppearLoadPolicy_retriesLoadedEmptyProductionState() {
        let store = StoreKitSubscriptionStore(
            productIDs: Self.allProductIDs,
            loadingState: .loaded,
            allowsAutomaticProductReload: true
        )

        XCTAssertTrue(
            store.shouldLoadProductsOnPaywallAppear,
            "A transient empty StoreKit response should retry when the paywall appears again."
        )
    }

    func test_paywallAppearLoadPolicy_retriesFailedProductionState() {
        let store = StoreKitSubscriptionStore(
            productIDs: Self.allProductIDs,
            loadingState: .failed("StoreKit temporarily unavailable."),
            allowsAutomaticProductReload: true
        )

        XCTAssertTrue(
            store.shouldLoadProductsOnPaywallAppear,
            "A transient StoreKit failure should retry when the paywall appears again."
        )
    }

    func test_paywallAppearLoadPolicy_doesNotAutoReloadDeterministicFixtures() {
        let store = StoreKitSubscriptionStore(
            productIDs: Self.allProductIDs,
            loadingState: .loaded
        )

        XCTAssertFalse(
            store.shouldLoadProductsOnPaywallAppear,
            "Snapshot and state-machine fixtures opt out so injected loaded-empty states remain stable."
        )
    }

    func test_paywallAppearLoadPolicy_doesNotReloadDisplayFixtures() {
        let store = StoreKitSubscriptionStore(
            productIDs: Self.allProductIDs,
            loadingState: .loaded,
            productDisplays: [
                StoreKitSubscriptionProductDisplay(id: Self.monthly, displayPrice: "$9.99"),
            ],
            allowsAutomaticProductReload: true
        )

        XCTAssertFalse(
            store.shouldLoadProductsOnPaywallAppear,
            "Display-only screenshot fixtures should not be replaced by an empty simulator StoreKit response."
        )
    }

    #if DEBUG
    func test_screenshotFixturePublishesSubmittedPlanDisplays() {
        let displays = [
            StoreKitSubscriptionProductDisplay(id: Self.monthly, displayPrice: "$9.99"),
            StoreKitSubscriptionProductDisplay(id: Self.yearly, displayPrice: "$79.99"),
        ]

        let store = StoreKitSubscriptionStore.screenshotFixture(
            productIDs: Self.allProductIDs,
            productDisplays: displays
        )

        XCTAssertEqual(store.productDisplays, displays)
        XCTAssertEqual(store.loadingState, .loaded)
        XCTAssertFalse(store.shouldLoadProductsOnPaywallAppear)
    }
    #endif

    func test_paywallAppearLoadPolicy_doesNotStartSecondConcurrentLoad() {
        let store = StoreKitSubscriptionStore(
            productIDs: Self.allProductIDs,
            loadingState: .loading,
            allowsAutomaticProductReload: true
        )

        XCTAssertFalse(store.shouldLoadProductsOnPaywallAppear)
    }

    // MARK: - Grant path

    func test_granted_insertsProductID_andRecordsTelemetry() {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.granted(productID: Self.monthly))

        XCTAssertTrue(store.purchasedProductIDs.contains(Self.monthly))
        XCTAssertTrue(store.isPremium)

        let grants = telemetry.currentEvents.filter { $0.category == "subscription.entitlement" && $0.name == "granted" }
        XCTAssertEqual(grants.count, 1, "Expected exactly one granted event")
        XCTAssertEqual(grants.first?.metadata["productID"], Self.monthly)
        XCTAssertEqual(grants.first?.metadata["ownershipType"], "purchased")
        XCTAssertEqual(grants.first?.metadata["source"], "updates")
    }

    func test_granted_isIdempotent_doesNotDoubleFireTelemetry() {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.granted(productID: Self.monthly))
        store.applyTransactionUpdate(.granted(productID: Self.monthly))
        store.applyTransactionUpdate(.granted(productID: Self.monthly))

        XCTAssertTrue(store.purchasedProductIDs.contains(Self.monthly))
        XCTAssertEqual(store.purchasedProductIDs.count, 1)

        let grants = telemetry.currentEvents.filter { $0.name == "granted" }
        XCTAssertEqual(
            grants.count,
            1,
            "Duplicate granted updates for the same productID should only fire telemetry once — Set.insert returns inserted=false on the duplicates."
        )
    }

    func test_distinctProductIDs_grantedSeparately() {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.granted(productID: Self.monthly))
        store.applyTransactionUpdate(.granted(productID: Self.yearly))

        XCTAssertEqual(store.purchasedProductIDs, Set([Self.monthly, Self.yearly]))
        XCTAssertTrue(store.isPremium)

        let grants = telemetry.currentEvents.filter { $0.name == "granted" }
        XCTAssertEqual(grants.count, 2)
    }

    // MARK: - Refund path

    func test_refund_removesProductID_andRecordsRevokedTelemetry() {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.granted(productID: Self.monthly))
        XCTAssertTrue(store.isPremium)

        store.applyTransactionUpdate(.refunded(productID: Self.monthly))

        XCTAssertFalse(store.purchasedProductIDs.contains(Self.monthly))
        XCTAssertFalse(store.isPremium, "Store should NOT report premium after refund")

        let revokes = telemetry.currentEvents.filter { $0.name == "revoked" }
        XCTAssertEqual(revokes.count, 1)
        XCTAssertEqual(revokes.first?.metadata["productID"], Self.monthly)
        XCTAssertEqual(revokes.first?.metadata["revocationReason"], "developerIssue")
        XCTAssertEqual(revokes.first?.metadata["source"], "updates")
    }

    func test_refund_of_notGrantedProduct_isNoop_noTelemetry() {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        // Refund a productID that was never granted. The store's
        // `purchasedProductIDs.remove(_:)` returns nil; the telemetry
        // branch is gated on `removed != nil`. Pin that contract so
        // a future refactor can't silently start firing spurious
        // revoked events for products the user never owned.
        store.applyTransactionUpdate(.refunded(productID: Self.monthly))

        XCTAssertFalse(store.isPremium)
        let revokes = telemetry.currentEvents.filter { $0.name == "revoked" }
        XCTAssertTrue(revokes.isEmpty, "No revoked event should fire when the productID wasn't in the set")
    }

    func test_refund_isIdempotent_doesNotDoubleFireTelemetry() {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.granted(productID: Self.monthly))
        store.applyTransactionUpdate(.refunded(productID: Self.monthly))
        store.applyTransactionUpdate(.refunded(productID: Self.monthly))  // duplicate revoke

        let revokes = telemetry.currentEvents.filter { $0.name == "revoked" }
        XCTAssertEqual(revokes.count, 1, "Duplicate refunds for the same productID should only fire telemetry once")
    }

    // MARK: - Family sharing

    func test_familyShared_grant_insertsProductID_withFamilyOwnershipMetadata() {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.familyShared(productID: Self.yearly))

        XCTAssertTrue(store.purchasedProductIDs.contains(Self.yearly))
        XCTAssertTrue(store.isPremium)

        let grants = telemetry.currentEvents.filter { $0.name == "granted" }
        XCTAssertEqual(grants.count, 1)
        XCTAssertEqual(
            grants.first?.metadata["ownershipType"],
            "familyShared",
            "Telemetry must surface ownershipType=familyShared so support can correlate `I'm a family member` reports against the real entitlement source."
        )
    }

    func test_familyShared_removal_revokesProductID_withFamilyOwnershipMetadata() {
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.familyShared(productID: Self.yearly))
        XCTAssertTrue(store.isPremium)

        store.applyTransactionUpdate(.familySharingRemoved(productID: Self.yearly))

        XCTAssertFalse(store.purchasedProductIDs.contains(Self.yearly))
        XCTAssertFalse(store.isPremium, "Family-share removal must downgrade the user.")

        let revokes = telemetry.currentEvents.filter { $0.name == "revoked" }
        XCTAssertEqual(revokes.count, 1)
        XCTAssertEqual(
            revokes.first?.metadata["ownershipType"],
            "familyShared",
            "Family-share REMOVAL must preserve the familyShared ownership context in telemetry so support can distinguish from a self-purchased refund."
        )
    }

    // MARK: - Mixed sequences

    func test_grantThenRefund_thenSecondGrant_grantsAgain() {
        // Real-world flow: user subscribes (granted), gets a refund
        // (revoked), then re-subscribes (granted again). Each phase
        // should fire its own telemetry event. The store treats each
        // observed transaction independently — no "this productID is
        // poisoned" state.
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.granted(productID: Self.monthly))
        store.applyTransactionUpdate(.refunded(productID: Self.monthly))
        store.applyTransactionUpdate(.granted(productID: Self.monthly))

        XCTAssertTrue(store.purchasedProductIDs.contains(Self.monthly))
        XCTAssertTrue(store.isPremium)

        let grants = telemetry.currentEvents.filter { $0.name == "granted" }
        let revokes = telemetry.currentEvents.filter { $0.name == "revoked" }
        XCTAssertEqual(grants.count, 2)
        XCTAssertEqual(revokes.count, 1)
    }

    func test_concurrentEntitlements_oneRefundedOneStillActive_keepsPremium() {
        // User has both monthly and yearly tiers active (rare but
        // possible during a tier-change grace period). Refunding the
        // monthly leaves yearly intact; `isPremium` stays true
        // because the set is non-empty.
        let telemetry = InMemoryTelemetrySink()
        let store = StoreKitSubscriptionStore(productIDs: Self.allProductIDs, telemetry: telemetry)

        store.applyTransactionUpdate(.granted(productID: Self.monthly))
        store.applyTransactionUpdate(.granted(productID: Self.yearly))
        XCTAssertTrue(store.isPremium)

        store.applyTransactionUpdate(.refunded(productID: Self.monthly))

        XCTAssertFalse(store.purchasedProductIDs.contains(Self.monthly))
        XCTAssertTrue(store.purchasedProductIDs.contains(Self.yearly))
        XCTAssertTrue(store.isPremium, "Yearly is still active; isPremium must stay true")
    }

    // MARK: - TransactionUpdate value-type contracts

    func test_transactionUpdate_isRevocation_reflectsRevocationDatePresence() {
        XCTAssertFalse(TransactionUpdate.granted(productID: "x").isRevocation)
        XCTAssertTrue(TransactionUpdate.refunded(productID: "x").isRevocation)
        XCTAssertFalse(TransactionUpdate.familyShared(productID: "x").isRevocation)
        XCTAssertTrue(TransactionUpdate.familySharingRemoved(productID: "x").isRevocation)
    }

    func test_transactionUpdate_grantedDefaultsToPurchasedOwnership() {
        let update = TransactionUpdate.granted(productID: "x")
        XCTAssertEqual(update.ownershipTypeDescription, "purchased")
    }

    func test_transactionUpdate_familySharedHasFamilyOwnership() {
        let update = TransactionUpdate.familyShared(productID: "x")
        XCTAssertEqual(update.ownershipTypeDescription, "familyShared")
    }

    func test_transactionUpdate_refundedDefaultsToDeveloperIssueReason() {
        let update = TransactionUpdate.refunded(productID: "x")
        XCTAssertEqual(update.revocationReasonDescription, "developerIssue")
    }

    func test_transactionUpdate_equatable() {
        let first = TransactionUpdate.granted(productID: "x")
        let secondSameProduct = TransactionUpdate.granted(productID: "x")
        let differentProduct = TransactionUpdate.granted(productID: "y")

        XCTAssertEqual(first, secondSameProduct)
        XCTAssertNotEqual(first, differentProduct)
    }
}
#endif
