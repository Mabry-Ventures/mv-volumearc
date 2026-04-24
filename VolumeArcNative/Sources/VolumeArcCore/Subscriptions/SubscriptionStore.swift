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

    public init(productIDs: [String]) {
        self.productIDs = productIDs
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
                    purchasedProductIDs.insert(transaction.productID)
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
                active.insert(transaction.productID)
            }
        }
        purchasedProductIDs = active
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

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case let .verified(transaction) = result {
                    await MainActor.run {
                        self?.purchasedProductIDs.insert(transaction.productID)
                    }
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

    public init(productIDs: [String]) {
        self.productIDs = productIDs
    }
}
#endif
