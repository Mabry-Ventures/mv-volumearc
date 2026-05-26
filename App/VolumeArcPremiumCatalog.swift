import Foundation

import VolumeArcCore

enum VolumeArcPremiumCatalog {
    static let subscriptionProductIDs = [
        "com.mabryventures.VolumeArc.premium.monthly",
        "com.mabryventures.VolumeArc.premium.yearly",
    ]

    #if DEBUG && canImport(StoreKit)
    static let screenshotProductDisplays = [
        StoreKitSubscriptionProductDisplay(
            id: "com.mabryventures.VolumeArc.premium.monthly",
            displayPrice: String(
                localized: "$9.99",
                comment: "Deterministic screenshot fixture monthly price"
            )
        ),
        StoreKitSubscriptionProductDisplay(
            id: "com.mabryventures.VolumeArc.premium.yearly",
            displayPrice: String(
                localized: "$79.99",
                comment: "Deterministic screenshot fixture yearly price"
            )
        ),
    ]
    #endif
}
