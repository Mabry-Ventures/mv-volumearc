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

#if canImport(StoreKit)
import StoreKit

/// Observable StoreKit 2 subscription store.
/// Loads products on init, exposes purchase status as @Published state,
/// and listens for transaction updates.
@MainActor
public final class StoreKitSubscriptionStore: ObservableObject, PremiumEntitlementProviding {
    public let productIDs: [String]

    @Published public private(set) var products: [Product] = []
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
    private let telemetry: (any TelemetrySink)?

    public init(productIDs: [String], telemetry: (any TelemetrySink)? = nil) {
        self.productIDs = productIDs
        self.telemetry = telemetry
        updateListenerTask = listenForTransactions()
        Task { await loadProducts() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    /// Whether the user has an active premium entitlement.
    public var isPremium: Bool {
        !purchasedProductIDs.isEmpty
    }

    /// Load products from the App Store.
    public func loadProducts() async {
        loadingState = .loading
        do {
            let fetched = try await Product.products(for: productIDs)
            self.products = fetched.sorted { lhs, rhs in
                lhs.price < rhs.price
            }
            loadingState = .loaded
            await refreshEntitlements()
        } catch {
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

    /// VOL-142: handle a verified transaction from any source (initial
    /// purchase, `Transaction.updates` listener, restore). Splits the
    /// previously-inlined "insert into purchasedProductIDs" so the
    /// revocation case is enforced everywhere — `Transaction.updates`
    /// is the primary delivery channel for refunds and family-share
    /// revocations, and the prior code only INSERTED, leaving a
    /// refunded user marked premium until the next refresh.
    fileprivate func applyTransactionUpdate(_ transaction: Transaction) {
        if transaction.revocationDate != nil {
            let removed = purchasedProductIDs.remove(transaction.productID) != nil
            if removed {
                telemetry?.record(TelemetryEvent(
                    category: "subscription.entitlement",
                    name: "revoked",
                    severity: .warning,
                    message: "Entitlement revoked via Transaction.updates (refund or family-share removal).",
                    metadata: [
                        "productID": transaction.productID,
                        "reason": String(describing: transaction.revocationReason),
                        "source": "updates",
                    ]
                ))
            }
        } else {
            let inserted = purchasedProductIDs.insert(transaction.productID).inserted
            if inserted {
                telemetry?.record(TelemetryEvent(
                    category: "subscription.entitlement",
                    name: "granted",
                    severity: .info,
                    message: "Entitlement granted via Transaction.updates.",
                    metadata: [
                        "productID": transaction.productID,
                        "ownershipType": String(describing: transaction.ownershipType),
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
