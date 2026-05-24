#if canImport(SwiftUI) && canImport(StoreKit)
import SwiftUI
import StoreKit
import VolumeArcCore

/// VolumeArc Premium paywall.
/// Presents two plans (monthly / yearly) with feature comparison, purchase flow,
/// and restore button. Dismisses automatically on successful purchase.
public struct PaywallView: View {
    @ObservedObject var subscriptionStore: StoreKitSubscriptionStore
    @Binding var isPresented: Bool

    @State private var selectedProductID: String?
    @State private var isPurchasing = false

    public init(subscriptionStore: StoreKitSubscriptionStore, isPresented: Binding<Bool>) {
        self.subscriptionStore = subscriptionStore
        self._isPresented = isPresented
    }

    public var body: some View {
        NavigationStack {
            paywallContent
                .navigationTitle(String(localized: "Premium", comment: "Paywall navigation title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(String(localized: "Close", comment: "Paywall dismiss button")) {
                            VAHaptics.tap()
                            isPresented = false
                        }
                        .tint(VA.Colors.primary)
                        .accessibilityIdentifier("paywall.close")
                    }
                }
                .task {
                    if subscriptionStore.shouldLoadProductsOnPaywallAppear {
                        await subscriptionStore.loadProducts()
                    }
                }
                .onChange(of: subscriptionStore.isPremium) { _, newValue in
                    if newValue { isPresented = false }
                }
        }
    }

    @_spi(Testing) public var snapshotContent: some View {
        paywallContent
    }

    @_spi(Testing) public var snapshotPlanStateContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VA.Space.xl) {
                plans
                actionButtons
            }
            .padding(VA.Space.lg)
        }
        .background(paywallBackground)
    }

    private var paywallContent: some View {
        ScrollView {
            // VOL-93: eager VStack (not LazyVStack) so the XCUITest
            // journey suite can locate the legal footer + Restore
            // Purchases button even when they're below the fold. The
            // paywall has a fixed, known-small set of children (hero,
            // feature comparison, plans, action buttons, legal), so
            // the eager-render cost is negligible — LazyVStack's
            // memory/scroll-perf win is marginal at 5 elements.
            VStack(alignment: .leading, spacing: VA.Space.xl) {
                hero
                featureComparison
                plans
                actionButtons
                legalLinks
            }
            .padding(VA.Space.lg)
        }
        .background(paywallBackground)
        .accessibilityIdentifier("paywall.root")
    }

    private var paywallBackground: some View {
        LinearGradient(
            colors: [
                VA.Colors.primary.opacity(VA.Opacity.paywallBackgroundStart),
                VA.Colors.surfaceSecondary
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: VA.Space.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(VA.Colors.primary)
                .vaAppear()

            Text(String(localized: "VolumeArc Premium", comment: "Paywall hero title"))
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
                .multilineTextAlignment(.center)

            // VOL-198: hero description must describe ONLY what Premium
            // actually unlocks. CloudKit sync, Foundation Models, and
            // Live Activities are free per `docs/PLATFORM.md` (VOL-91);
            // promising them as Premium value is paid-subscription
            // misrepresentation and an App Review risk.
            Text(String(
                localized: "Unlock the Gemini Pro coach and live voice coaching — the full AI prescription your training deserves.",
                comment: "Paywall hero description"
            ))
                .font(VA.Typography.body)
                .foregroundStyle(VA.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Feature comparison

    private var featureComparison: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "WHAT'S INCLUDED", comment: "Paywall feature list section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)

                ForEach(premiumFeatures) { feature in
                    HStack(alignment: .top, spacing: VA.Space.md) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(VA.Colors.primary)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(feature.title)
                                .font(VA.Typography.headline)
                                .foregroundStyle(VA.Colors.textPrimary)
                            Text(feature.description)
                                .font(VA.Typography.footnote)
                                .foregroundStyle(VA.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    // VOL-198: visibility raised from `private` to module-internal so
    // `VolumeArcPaywallFeatureContractTests` (in `VolumeArcAppTests`)
    // can assert the paywall feature list matches the PLATFORM.md
    // Premium definition. Not part of the public surface.
    struct PremiumFeature: Identifiable {
        let icon: String
        let title: String
        let description: String
        var id: String { title }
    }

    // VOL-198: paywall features must match the Premium definition in
    // `docs/PLATFORM.md` (VOL-91) — Gemini Pro coach tier + live voice
    // coaching. CloudKit sync / Foundation Models / Live Activities
    // are free for all users and were misadvertised here as paid value;
    // App Review treats that as paid-feature misrepresentation. Priority
    // support and "Advanced Signals" were never implemented features.
    // The constant is exposed `internal` (not private) so a contract
    // test in `VolumeArcAppTests` can assert it stays aligned with the
    // entitlement matrix at `VolumeArcAIRuntimeFactory`.
    static var premiumFeatures: [PremiumFeature] {
        [
            PremiumFeature(
                icon: "brain.head.profile",
                title: String(localized: "AI Coach — Gemini Pro tier", comment: "Premium feature name — AI coach Pro tier"),
                description: String(
                    localized: "Reasoning-grade coaching prescriptions. Pro reads more of your history and writes a deeper plan.",
                    comment: "Premium feature description — AI coach Pro tier"
                )
            ),
            PremiumFeature(
                icon: "waveform.and.mic",
                title: String(localized: "Live Voice Coaching", comment: "Premium feature name — voice coach"),
                description: String(
                    localized: "Talk to your coach hands-free between sets.",
                    comment: "Premium feature description — voice coach"
                )
            ),
        ]
    }

    private var premiumFeatures: [PremiumFeature] { Self.premiumFeatures }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        if subscriptionStore.products.isEmpty {
            if case .loading = subscriptionStore.loadingState {
                VALoadingState(message: String(
                    localized: "Loading plans…",
                    comment: "Paywall loading state message"
                ))
                .frame(minHeight: 120)
            } else if case let .failed(reason) = subscriptionStore.loadingState {
                VAErrorState(
                    title: String(localized: "Couldn't load plans", comment: "Paywall error title when StoreKit fails"),
                    message: reason,
                    retry: {
                        Task { await subscriptionStore.loadProducts() }
                    }
                )
            } else {
                VACard(style: .flat) {
                    Text(String(
                        localized: "No plans available right now. Try again later.",
                        comment: "Paywall empty-state message when no products are returned"
                    ))
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                }
            }
        } else {
            VStack(spacing: VA.Space.md) {
                ForEach(subscriptionStore.products, id: \.id) { product in
                    planRow(product)
                }
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let isSelected = selectedProductID == product.id
        let isYearly = product.id.contains("yearly")

        return Button {
            selectedProductID = product.id
            VAHaptics.selection()
        } label: {
            HStack(spacing: VA.Space.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? VA.Colors.primary : VA.Colors.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(isYearly
                             ? String(localized: "Yearly", comment: "Paywall yearly plan label")
                             : String(localized: "Monthly", comment: "Paywall monthly plan label"))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        if isYearly {
                            Text(String(localized: "SAVE", comment: "Paywall savings badge on the yearly plan"))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(VA.Colors.success)
                                .clipShape(Capsule())
                        }
                    }
                    Text(isYearly
                         ? String(localized: "\(product.displayPrice) / year", comment: "Yearly plan price line")
                         : String(localized: "\(product.displayPrice) / month", comment: "Monthly plan price line"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(VA.Space.lg)
            .modifier(PaywallPlanCardBackgroundModifier(isSelected: isSelected))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                        .stroke(VA.Colors.primary, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("paywall.plan.\(product.id)")
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: VA.Space.md) {
            VAButton(
                isPurchasing
                    ? String(localized: "Processing…", comment: "Paywall primary button while a purchase is in flight")
                    : String(localized: "Start Premium", comment: "Paywall primary call-to-action"),
                icon: "sparkles",
                style: .primary,
                isLoading: isPurchasing
            ) {
                Task { await startPurchase() }
            }
            .disabled(selectedProductID == nil || isPurchasing)
            .accessibilityIdentifier("paywall.purchase")

            Button(String(localized: "Restore Purchases", comment: "Paywall restore purchases button")) {
                Task {
                    VAHaptics.tap()
                    await subscriptionStore.restorePurchases()
                }
            }
            .font(VA.Typography.button)
            .foregroundStyle(VA.Colors.primary)
            // VOL-93: stable identifier for the XCUITest journey suite so
            // `testRestorePurchasesFlow` can locate and tap the button
            // without relying on a localized title.
            .accessibilityIdentifier("paywall.restore")

            if let error = subscriptionStore.lastPurchaseError {
                Text(error)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.error)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func startPurchase() async {
        guard let productID = selectedProductID,
              let product = subscriptionStore.products.first(where: { $0.id == productID })
        else { return }

        isPurchasing = true
        VAHaptics.tap()
        let success = await subscriptionStore.purchase(product)
        isPurchasing = false

        if success {
            VAHaptics.workoutComplete()
        } else {
            VAHaptics.error()
        }
    }

    // MARK: - Legal

    private var legalLinks: some View {
        VStack(spacing: VA.Space.xs) {
            // App Store Review Guideline 3.1.2 disclosure — auto-renewal, billing,
            // cancellation, and where to manage the subscription.
            Text(String(
                localized: """
                    Payment will be charged to your Apple ID account at confirmation of purchase. \
                    Subscriptions automatically renew unless auto-renew is turned off at least 24 hours \
                    before the end of the current period. Your account will be charged for renewal \
                    within 24 hours prior to the end of the current period. You can manage and cancel \
                    your subscriptions by going to Settings → Apple ID → Subscriptions after purchase.
                """,
                comment: "App Store Guideline 3.1.2 required auto-renew disclosure on the paywall"
            ))
            .font(VA.Typography.caption)
            .foregroundStyle(VA.Colors.textTertiary)
            .multilineTextAlignment(.center)

            HStack(spacing: VA.Space.md) {
                Link(
                    String(localized: "Terms of Service", comment: "Paywall footer link label"),
                    destination: LegalLinks.termsOfService
                )
                .accessibilityLabel(Text(String(
                    localized: "Terms of Service",
                    comment: "Accessibility label for paywall Terms of Service link"
                )))
                .accessibilityHint(Text(String(
                    localized: "Opens the Terms of Service in your browser",
                    comment: "Accessibility hint for paywall Terms of Service link"
                )))
                .accessibilityIdentifier("paywall.legal.terms")

                Text("•")

                Link(
                    String(localized: "Privacy Policy", comment: "Paywall footer link label"),
                    destination: LegalLinks.privacyPolicy
                )
                .accessibilityLabel(Text(String(
                    localized: "Privacy Policy",
                    comment: "Accessibility label for paywall Privacy Policy link"
                )))
                .accessibilityHint(Text(String(
                    localized: "Opens the Privacy Policy in your browser",
                    comment: "Accessibility hint for paywall Privacy Policy link"
                )))
                .accessibilityIdentifier("paywall.legal.privacy")
            }
            .font(VA.Typography.caption)
            .foregroundStyle(VA.Colors.primary)
        }
        .padding(.top, VA.Space.md)
    }
}

/// Selected plans show the brand-tinted overlay; unselected plans use real
/// iOS 26 Liquid Glass via `vaGlassBackground`. Lifted into a dedicated
/// `ViewModifier` so the call site in `PaywallView` stays declarative.
private struct PaywallPlanCardBackgroundModifier: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        if isSelected {
            content
                .background(VA.Colors.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        } else {
            content
                .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        }
    }
}
#endif
