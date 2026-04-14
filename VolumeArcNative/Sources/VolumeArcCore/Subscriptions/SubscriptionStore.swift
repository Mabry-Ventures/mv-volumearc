import Foundation

#if canImport(StoreKit)
public struct StoreKitSubscriptionStore: Sendable {
    public let productIDs: [String]

    public init(productIDs: [String]) {
        self.productIDs = productIDs
    }
}
#endif
