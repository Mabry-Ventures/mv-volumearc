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
            displayPrice: "$9.99"
        ),
        StoreKitSubscriptionProductDisplay(
            id: "com.mabryventures.VolumeArc.premium.yearly",
            displayPrice: "$79.99"
        ),
    ]
    #endif
}
