import Foundation

/// Read-only view of the caller's premium-entitlement state. The factory
/// uses this to decide which AI tier / transport to install at launch —
/// intentionally scoped to a single `Bool` so tests can pass a simple
/// mock without depending on StoreKit.
///
/// VOL-91: `StoreKitSubscriptionStore` is the production conformer; tests
/// substitute an in-memory implementation. Isolated to `@MainActor`
/// because `StoreKitSubscriptionStore.isPremium` is published state —
/// the factory reads this at launch from `VolumeArcApp.init`, which is
/// itself main-actor-bound, so the isolation lines up without forcing
/// callers into a background hop.
@MainActor
public protocol PremiumEntitlementProviding: AnyObject {
    /// `true` when the user has an active premium entitlement.
    var isPremium: Bool { get }
}

/// VOL-142 Phase 2: testable shape of a StoreKit transaction update.
///
/// `StoreKit.Transaction` is an opaque system value type — there's no
/// public initializer, so tests can't construct one directly. The Phase
/// 1 SKTestSession integration test (`StoreKitSubscriptionRevocationTests.testRefundRemovesEntitlementAndRecordsTelemetry`)
/// proved that `SKTestSession.refundTransaction` propagation is flaky on
/// the M4 self-hosted runner — the test is currently `XCTSkip`-ped.
///
/// `TransactionUpdate` is the value-type slice of `Transaction` that
/// `StoreKitSubscriptionStore.applyTransactionUpdate(_:)` actually
/// reads. Tests construct it directly; production code bridges via
/// `init(from: Transaction)`. State-machine assertions for refund /
/// family-share / grace-period / billing-retry / ask-to-buy live at
/// this layer instead of trying to drive a flaky SKTestSession.
///
/// Sendable + Equatable so test fixtures stay clean.
public struct TransactionUpdate: Sendable, Equatable {
    public let productID: String
    /// Non-nil ⇒ the transaction was revoked (refund, family-share
    /// removal, developer-issued grant rescinded, etc.). The store
    /// treats any non-nil value as "remove from entitlements."
    public let revocationDate: Date?
    /// Best-effort textual description of `Transaction.revocationReason`.
    /// Stored as a string instead of the StoreKit enum so the value
    /// type is StoreKit-free and the test target doesn't need to
    /// `import StoreKit` (StoreKit's `RevocationReason` is opaque +
    /// platform-gated).
    public let revocationReasonDescription: String?
    /// Textual description of `Transaction.ownershipType` — typically
    /// "purchased" or "familyShared". Same StoreKit-free rationale as
    /// `revocationReasonDescription`.
    public let ownershipTypeDescription: String

    public init(
        productID: String,
        revocationDate: Date? = nil,
        revocationReasonDescription: String? = nil,
        ownershipTypeDescription: String = "purchased"
    ) {
        self.productID = productID
        self.revocationDate = revocationDate
        self.revocationReasonDescription = revocationReasonDescription
        self.ownershipTypeDescription = ownershipTypeDescription
    }

    /// Whether the update represents a revocation. `Transaction.currentEntitlements`
    /// omits revoked transactions, but `Transaction.updates` delivers
    /// them with a non-nil `revocationDate` — that's the path tests
    /// pin.
    public var isRevocation: Bool { revocationDate != nil }

    // MARK: - Convenience constructors (test ergonomics)

    /// Construct a grant update — entitlement should be inserted.
    public static func granted(
        productID: String,
        ownershipType: String = "purchased"
    ) -> TransactionUpdate {
        TransactionUpdate(
            productID: productID,
            revocationDate: nil,
            revocationReasonDescription: nil,
            ownershipTypeDescription: ownershipType
        )
    }

    /// Construct a refund update — entitlement should be removed,
    /// telemetry should fire with `revocationReason` = "developerIssue".
    public static func refunded(
        productID: String,
        at date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        reason: String = "developerIssue"
    ) -> TransactionUpdate {
        TransactionUpdate(
            productID: productID,
            revocationDate: date,
            revocationReasonDescription: reason,
            ownershipTypeDescription: "purchased"
        )
    }

    /// Construct a family-share grant — `ownershipType == "familyShared"`.
    /// Entitlement should be inserted; tests assert the ownership type
    /// rides into the telemetry metadata so support can correlate
    /// "I was a family member" reports.
    public static func familyShared(productID: String) -> TransactionUpdate {
        TransactionUpdate(
            productID: productID,
            revocationDate: nil,
            revocationReasonDescription: nil,
            ownershipTypeDescription: "familyShared"
        )
    }

    /// Construct a family-share removal — non-nil revocation with the
    /// `familyShared` ownership context preserved so telemetry can
    /// distinguish from a refund.
    public static func familySharingRemoved(
        productID: String,
        at date: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> TransactionUpdate {
        TransactionUpdate(
            productID: productID,
            revocationDate: date,
            revocationReasonDescription: "developerIssue",
            ownershipTypeDescription: "familyShared"
        )
    }
}

#if canImport(StoreKit)
import StoreKit

public struct StoreKitSubscriptionProductDisplay: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayPrice: String

    public init(id: String, displayPrice: String) {
        self.id = id
        self.displayPrice = displayPrice
    }
}

extension TransactionUpdate {
    /// Bridge from the real `StoreKit.Transaction`. Production code
    /// uses this when wiring `Transaction.updates` into the store;
    /// tests bypass it entirely by constructing `TransactionUpdate`
    /// values directly.
    public init(from transaction: Transaction) {
        self.init(
            productID: transaction.productID,
            revocationDate: transaction.revocationDate,
            revocationReasonDescription: transaction.revocationReason.map { String(describing: $0) },
            ownershipTypeDescription: String(describing: transaction.ownershipType)
        )
    }
}

/// Observable StoreKit 2 subscription store.
/// Loads products on init, exposes purchase status as @Published state,
/// and listens for transaction updates.
@MainActor
public final class StoreKitSubscriptionStore: ObservableObject, PremiumEntitlementProviding {
    public let productIDs: [String]

    @Published public private(set) var products: [Product] = []
    @Published public private(set) var productDisplays: [StoreKitSubscriptionProductDisplay] = []
    @Published public private(set) var purchasedProductIDs: Set<String> = []
    @Published public private(set) var loadingState: LoadingState = .idle
    @Published public var lastPurchaseError: String?

    public enum LoadingState: Equatable, Sendable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    private var updateListenerTask: Task<Void, Never>?
    private let allowsAutomaticProductReload: Bool
    private let telemetry: (any TelemetrySink)?

    public init(productIDs: [String], telemetry: (any TelemetrySink)? = nil) {
        self.productIDs = productIDs
        self.allowsAutomaticProductReload = true
        self.telemetry = telemetry
        updateListenerTask = listenForTransactions()
        Task { await loadProducts() }
    }

    @_spi(Testing)
    public init(
        productIDs: [String],
        loadingState: LoadingState,
        productDisplays: [StoreKitSubscriptionProductDisplay] = [],
        lastPurchaseError: String? = nil,
        allowsAutomaticProductReload: Bool = false,
        telemetry: (any TelemetrySink)? = nil
    ) {
        self.productIDs = productIDs
        self.allowsAutomaticProductReload = allowsAutomaticProductReload
        self.telemetry = telemetry
        self.loadingState = loadingState
        self.productDisplays = productDisplays
        self.lastPurchaseError = lastPurchaseError
        updateListenerTask = nil
    }

    #if DEBUG
    public static func screenshotFixture(
        productIDs: [String],
        productDisplays: [StoreKitSubscriptionProductDisplay],
        purchasedProductIDs: Set<String> = [],
        telemetry: (any TelemetrySink)? = nil
    ) -> StoreKitSubscriptionStore {
        let store = StoreKitSubscriptionStore(
            productIDs: productIDs,
            loadingState: .loaded,
            productDisplays: productDisplays,
            allowsAutomaticProductReload: false,
            telemetry: telemetry
        )
        store.purchasedProductIDs = purchasedProductIDs
        return store
    }
    #endif

    deinit {
        updateListenerTask?.cancel()
    }

    /// Whether the user has an active premium entitlement.
    public var isPremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    /// Whether a paywall presentation should kick off product loading.
    public var shouldLoadProductsOnPaywallAppear: Bool {
        guard allowsAutomaticProductReload, products.isEmpty, productDisplays.isEmpty else { return false }
        switch loadingState {
        case .idle, .loaded, .failed:
            return true
        case .loading:
            return false
        }
    }

    /// Load products from the App Store.
    public func loadProducts() async {
        loadingState = .loading
        do {
            let fetched = try await Product.products(for: productIDs)
            let sortedProducts = fetched.sorted { lhs, rhs in
                lhs.price < rhs.price
            }
            self.products = sortedProducts
            self.productDisplays = sortedProducts.map { product in
                StoreKitSubscriptionProductDisplay(
                    id: product.id,
                    displayPrice: product.displayPrice
                )
            }
            loadingState = .loaded
            await refreshEntitlements()
        } catch {
            productDisplays = []
            loadingState = .failed(error.localizedDescription)
        }
    }

    /// Attempt to purchase the given product.
    public func purchase(_ product: Product) async -> Bool {
        lastPurchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case let .success(verification):
                if case let .verified(transaction) = verification {
                    applyTransactionUpdate(transaction)
                    await transaction.finish()
                    return true
                } else {
                    lastPurchaseError = "Purchase could not be verified."
                    return false
                }
            case .userCancelled:
                return false
            case .pending:
                lastPurchaseError = "Purchase pending approval."
                // VOL-142: ask-to-buy / Strong Customer Authentication
                // pending state. Emit a telemetry breadcrumb so support
                // can correlate "user says they paid but they're not
                // premium" reports against the actual pending state.
                telemetry?.record(TelemetryEvent(
                    category: "subscription.entitlement",
                    name: "purchase_pending",
                    severity: .info,
                    message: "Purchase awaiting approval (ask-to-buy / SCA).",
                    metadata: ["productID": product.id]
                ))
                return false
            @unknown default:
                return false
            }
        } catch {
            lastPurchaseError = error.localizedDescription
            return false
        }
    }

    /// Re-check current entitlements against the App Store receipt.
    public func refreshEntitlements() async {
        var active: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case let .verified(transaction) = result {
                // VOL-142: `Transaction.currentEntitlements` already
                // omits revoked transactions, but be defensive in case
                // a future StoreKit revision changes the contract — a
                // verified transaction with a `revocationDate` is
                // explicitly NOT a current entitlement.
                if transaction.revocationDate == nil {
                    active.insert(transaction.productID)
                }
            }
        }

        // VOL-142: compare before/after for telemetry transitions. The
        // diff lets us emit a single event per state change instead of
        // logging on every refresh.
        let removed = purchasedProductIDs.subtracting(active)
        let added = active.subtracting(purchasedProductIDs)

        purchasedProductIDs = active

        for productID in added {
            telemetry?.record(TelemetryEvent(
                category: "subscription.entitlement",
                name: "granted",
                severity: .info,
                message: "Entitlement granted via refreshEntitlements.",
                metadata: ["productID": productID, "source": "refresh"]
            ))
        }
        for productID in removed {
            telemetry?.record(TelemetryEvent(
                category: "subscription.entitlement",
                name: "revoked",
                severity: .warning,
                message: "Entitlement revoked via refreshEntitlements (refund or expiration).",
                metadata: ["productID": productID, "source": "refresh"]
            ))
        }
    }

    /// Restore purchases explicitly (calls AppStore.sync).
    public func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastPurchaseError = error.localizedDescription
        }
    }

    /// VOL-142 Phase 1: bridge from `StoreKit.Transaction` to the
    /// testable value type below. The production `Transaction.updates`
    /// listener delivers `Transaction` values; tests construct
    /// `TransactionUpdate` directly via the static convenience
    /// constructors. Both call paths funnel through
    /// `applyTransactionUpdate(_ update: TransactionUpdate)` so the
    /// state-machine logic is exercised identically in both worlds.
    fileprivate func applyTransactionUpdate(_ transaction: Transaction) {
        applyTransactionUpdate(TransactionUpdate(from: transaction))
    }

    /// VOL-142 Phase 2: the actual state-machine + telemetry path.
    /// Pure value-type input → testable from outside without
    /// `SKTestSession`. The previously-inline "insert into
    /// purchasedProductIDs" path was split here so the revocation
    /// case is enforced everywhere — `Transaction.updates` is the
    /// primary delivery channel for refunds + family-share
    /// revocations + developer-issued rescinds, and the pre-Phase-1
    /// code only INSERTED, leaving a refunded user marked premium
    /// until the next `refreshEntitlements` call. `internal`
    /// visibility (not `fileprivate`) so `@testable import VolumeArcCore`
    /// can reach it.
    internal func applyTransactionUpdate(_ update: TransactionUpdate) {
        if update.isRevocation {
            let removed = purchasedProductIDs.remove(update.productID) != nil
            if removed {
                telemetry?.record(TelemetryEvent(
                    category: "subscription.entitlement",
                    name: "revoked",
                    severity: .warning,
                    message: "Entitlement revoked via Transaction.updates (refund or family-share removal).",
                    metadata: [
                        "productID": update.productID,
                        "revocationReason": update.revocationReasonDescription ?? "unknown",
                        "ownershipType": update.ownershipTypeDescription,
                        "source": "updates",
                    ]
                ))
            }
        } else {
            let inserted = purchasedProductIDs.insert(update.productID).inserted
            if inserted {
                telemetry?.record(TelemetryEvent(
                    category: "subscription.entitlement",
                    name: "granted",
                    severity: .info,
                    message: "Entitlement granted via Transaction.updates.",
                    metadata: [
                        "productID": update.productID,
                        "ownershipType": update.ownershipTypeDescription,
                        "source": "updates",
                    ]
                ))
            }
        }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    // VOL-142: route through applyTransactionUpdate so
                    // the revocation case is enforced. The prior code
                    // only inserted, leaving a refunded user marked
                    // premium until the next refreshEntitlements call —
                    // Apple reviewers stress this path.
                    await self?.applyTransactionUpdate(transaction)
                    await transaction.finish()
                }
            }
        }
    }
}
#else
@MainActor
public final class StoreKitSubscriptionStore: PremiumEntitlementProviding {
    public let productIDs: [String]
    public var isPremium: Bool { false }

    public init(productIDs: [String], telemetry: (any TelemetrySink)? = nil) {
        self.productIDs = productIDs
        _ = telemetry  // unused on non-StoreKit platforms; signature parity for callers
    }
}
#endif
