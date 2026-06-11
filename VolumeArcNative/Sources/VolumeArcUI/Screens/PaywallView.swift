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
                premiumOutcomeBand
                premiumProofBand
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
        VStack(spacing: VA.Space.lg) {
            premiumHeroPreview

            VStack(spacing: VA.Space.sm) {
                Text(String(localized: "VolumeArc Premium", comment: "Paywall hero title"))
                    .font(VA.Typography.title)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .multilineTextAlignment(.center)

                // VOL-198: hero description must describe ONLY what
                // Premium actually unlocks. CloudKit sync, Foundation
                // Models, and Live Activities are free per
                // `docs/PLATFORM.md` (VOL-91); promising them as Premium
                // value is paid-subscription misrepresentation.
                // VOL-279 (repositioning): premium is programming depth,
                // never generic AI access.
                Text(String(
                    localized: """
                        Upgrade the programming depth: progression read from your full \
                        lift history, sharper between-set calls, and voice when typing \
                        breaks focus.
                        """,
                    comment: "Paywall hero description — Premium unlocks (Pro coach + live voice)"
                ))
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var premiumHeroPreview: some View {
        ZStack(alignment: .bottomLeading) {
            VA.Gradients.sunriseHero
            Circle()
                .fill(VA.Colors.textOnPrimary.opacity(0.16))
                .frame(width: 190, height: 190)
                .offset(x: 220, y: -94)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(spacing: VA.Space.sm) {
                    heroBadge(
                        String(localized: "Coach Pro", comment: "Paywall hero badge"),
                        icon: "brain.head.profile"
                    )
                    heroBadge(
                        String(localized: "Voice ready", comment: "Paywall hero badge"),
                        icon: "waveform.and.mic"
                    )
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: VA.Space.sm) {
                    Text(String(localized: "Next best move", comment: "Paywall hero preview card label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.78))
                    Text(String(
                        localized: "Keep the first set light, then build only if it moves clean.",
                        comment: "Paywall hero preview coach recommendation"
                    ))
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textOnPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(String(
                        localized: "If anything feels sharp, stop and switch the lift.",
                        comment: "Paywall hero preview safety cue"
                    ))
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(VA.Space.lg)
                .background(VA.Colors.primaryDeep.opacity(0.34), in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous)
                        .stroke(VA.Colors.textOnPrimary.opacity(0.22), lineWidth: 1)
                }

                HStack(spacing: VA.Space.sm) {
                    heroMetric(
                        value: String(localized: "Full", comment: "Paywall hero preview metric value"),
                        label: String(localized: "history", comment: "Paywall hero preview metric label")
                    )
                    heroMetric(
                        value: String(localized: "Live", comment: "Paywall hero preview metric value"),
                        label: String(localized: "voice", comment: "Paywall hero preview metric label")
                    )
                    heroMetric(
                        value: String(localized: "Pivot", comment: "Paywall hero preview metric value"),
                        label: String(localized: "calls", comment: "Paywall hero preview metric label")
                    )
                }
            }
            .padding(VA.Space.lg)
        }
        .frame(maxWidth: .infinity, minHeight: 236)
        .clipShape(RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous))
        .vaShadow(.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "Premium preview showing Coach Pro, voice coaching, and between-set guidance.",
            comment: "Paywall hero preview accessibility label"
        ))
    }

    private var premiumOutcomeBand: some View {
        HStack(spacing: VA.Space.sm) {
            PaywallOutcomePill(
                value: String(localized: "Full", comment: "Paywall outcome value"),
                label: String(localized: "history read", comment: "Paywall outcome label")
            )
            PaywallOutcomePill(
                value: String(localized: "Voice", comment: "Paywall outcome value"),
                label: String(localized: "between sets", comment: "Paywall outcome label")
            )
            PaywallOutcomePill(
                value: String(localized: "Low", comment: "Paywall outcome value"),
                label: String(localized: "pressure", comment: "Paywall outcome label")
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(String(
            localized: "Premium includes full-history coaching, voice between sets, and low-pressure guidance.",
            comment: "Paywall outcome band accessibility label"
        ))
    }

    private func heroBadge(_ title: String, icon: String) -> some View {
        HStack(spacing: VA.Space.xs) {
            Image(systemName: icon)
                .font(VA.Typography.caption)
            Text(title)
                .font(VA.Typography.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(VA.Colors.primaryDeep)
        .padding(.horizontal, VA.Space.sm)
        .frame(height: 30)
        .background(VA.Colors.textOnPrimary.opacity(0.94), in: Capsule())
    }

    private func heroMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.textOnPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(label)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textOnPrimary.opacity(0.76))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VA.Space.sm)
        .background(VA.Colors.textOnPrimary.opacity(0.14), in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
    }

    private var premiumProofBand: some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.lg) {
                Text(String(
                    localized: "Built for lifters who want a coach in the session, not another passive tracker.",
                    comment: "Paywall premium proof headline"
                ))
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: VA.Space.md) {
                    PaywallProofRow(
                        icon: "list.bullet.clipboard.fill",
                        title: String(localized: "Remembers your training", comment: "Paywall proof row title"),
                        detail: String(localized: "Coach Pro reads your full lift history before it prescribes.", comment: "Paywall proof row detail")
                    )
                    PaywallProofRow(
                        icon: "waveform.and.mic",
                        title: String(localized: "Works when your hands are full", comment: "Paywall proof row title"),
                        detail: String(localized: "Ask for cues or pivots between sets without typing.", comment: "Paywall proof row detail")
                    )
                    PaywallProofRow(
                        icon: "shield.lefthalf.filled",
                        title: String(localized: "Keeps pressure low", comment: "Paywall proof row title"),
                        detail: String(localized: "Recovery-first guidance when today is not the day to push.", comment: "Paywall proof row detail")
                    )
                }
            }
        }
    }

    // MARK: - Feature comparison

    private var featureComparison: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "WHAT'S INCLUDED", comment: "Paywall feature list section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)

                ForEach(premiumFeatures) { feature in
                    HStack(alignment: .top, spacing: VA.Space.md) {
                        Image(systemName: feature.icon)
                            .font(VA.Typography.title2)
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
            // VOL-247 (copy pass): user-facing title drops "Gemini" — the
            // routing is still Gemini Pro and is documented in PLATFORM.md
            // but the model name doesn't belong on the paywall surface.
            // Description: replaced "reasoning-grade coaching prescriptions"
            // jargon with coach-voice language.
            PremiumFeature(
                icon: "brain.head.profile",
                title: String(
                    localized: "Coach Pro",
                    comment: "Premium feature name — pro coach tier"
                ),
                description: String(
                    localized: """
                        Reads your full training history before prescribing, so \
                        progression builds on what you've actually lifted — not just \
                        your last set.
                        """,
                    comment: "Premium feature description — pro coach tier"
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
        if subscriptionStore.productDisplays.isEmpty {
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
                ForEach(subscriptionStore.productDisplays) { plan in
                    planRow(plan)
                }
            }
        }
    }

    private func planRow(_ plan: StoreKitSubscriptionProductDisplay) -> some View {
        let isSelected = selectedProductID == plan.id
        let isYearly = plan.id.contains("yearly")

        return Button {
            selectedProductID = plan.id
            VAHaptics.selection()
        } label: {
            HStack(spacing: VA.Space.md) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(VA.Typography.title2)
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
                                .font(VA.Typography.caption)
                                .foregroundStyle(VA.Colors.textOnPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(VA.Colors.success)
                                .clipShape(Capsule())
                        }
                    }
                    Text(isYearly
                         ? String(localized: "\(plan.displayPrice) / year", comment: "Yearly plan price line")
                         : String(localized: "\(plan.displayPrice) / month", comment: "Monthly plan price line"))
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
        .accessibilityIdentifier("paywall.plan.\(plan.id)")
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

private struct PaywallProofRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: VA.Space.md) {
            Image(systemName: icon)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.primary)
                .frame(width: 34, height: 34)
                .background(VA.Colors.primary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                Text(title)
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                Text(detail)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PaywallOutcomePill: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(value)
                .font(VA.Typography.headline)
                .foregroundStyle(VA.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(label)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VA.Space.md)
        .background(VA.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                .stroke(VA.Colors.primary.opacity(0.18), lineWidth: 1)
        }
    }
}
#endif
