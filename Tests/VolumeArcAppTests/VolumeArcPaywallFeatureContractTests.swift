// VOL-198: contract test that pins the paywall feature list to the
// PLATFORM.md Premium definition (VOL-91). If a future PR adds a
// feature to the paywall without also updating PLATFORM.md (or vice
// versa), this test must fail loudly. App Store Review treats
// promising features the user didn't actually buy as misrepresentation
// under Guideline 3.1.2.
//
// The Premium definition that this test enforces:
// > **Premium unlocks (VOL-91):**
// > - AI coach tier (Gemini Pro)
// > - Live voice coaching
// > **Not gated (free for all):** CloudKit sync, Foundation Models,
// > Live Activities.

import XCTest
@testable import VolumeArcUI

final class VolumeArcPaywallFeatureContractTests: XCTestCase {
    /// The Premium feature list rendered on the paywall must contain
    /// exactly these two items, in this order. If the product team
    /// wants to change the Premium scope, that change goes through
    /// `docs/PLATFORM.md`'s "Premium unlocks (VOL-91)" section AND
    /// this test in the same PR, so the entitlement matrix, the
    /// paywall, the marketing pricing page, and the contract test
    /// stay locked together.
    func testPaywallFeatureListMatchesPlatformDocPremiumDefinition() {
        let titles = PaywallView.premiumFeatures.map(\.title)
        XCTAssertEqual(
            titles,
            [
                "AI Coach — Gemini Pro tier",
                "Live Voice Coaching",
            ],
            """
            The paywall feature list drifted from docs/PLATFORM.md's \
            "Premium unlocks (VOL-91)" definition. If you intentionally \
            changed Premium scope, update both PLATFORM.md and this \
            expected array in the same PR. If you didn't intend to \
            change it, revert the paywall change.

            Background: VOL-198 audit finding established that Cloud \
            Sync, Foundation Models, Advanced Signals, and Priority \
            Support are NOT Premium features (some are free, some are \
            unimplemented). Promising them on the paywall is paid- \
            feature misrepresentation under App Review Guideline 3.1.2.
            """
        )
    }

    /// Defense-in-depth: ensure no Premium feature accidentally
    /// re-introduces one of the previously-misrepresented items.
    func testPaywallFeatureListExcludesPreviouslyMisrepresentedItems() {
        let titles = PaywallView.premiumFeatures.map(\.title)
        let forbiddenTitles: [String] = [
            "Cloud Sync",
            "Advanced Signals",
            "Foundation Models",
            "Priority Support",
        ]
        for forbidden in forbiddenTitles {
            XCTAssertFalse(
                titles.contains(forbidden),
                "Paywall must not advertise '\(forbidden)' as a Premium feature — see VOL-198 audit and docs/PLATFORM.md Premium definition."
            )
        }
    }
}
