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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: VA.Space.xl) {
                    hero
                    featureComparison
                    plans
                    actionButtons
                    legalLinks
                }
                .padding(VA.Space.lg)
            }
            .background(
                LinearGradient(
                    colors: [
                        VA.Colors.primary.opacity(0.18),
                        VA.Colors.surfaceSecondary
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
            .navigationTitle("Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        VAHaptics.tap()
                        isPresented = false
                    }
                }
            }
            .task {
                if subscriptionStore.products.isEmpty {
                    await subscriptionStore.loadProducts()
                }
            }
            .onChange(of: subscriptionStore.isPremium) { _, newValue in
                if newValue { isPresented = false }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: VA.Space.md) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(VA.Colors.primary)
                .vaAppear()

            Text("VolumeArc Premium")
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
                .multilineTextAlignment(.center)

            Text("Unlock live voice coaching, CloudKit sync across all your devices, and advanced training signals.")
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
                Text("WHAT'S INCLUDED")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)

                ForEach(premiumFeatures, id: \.title) { feature in
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

    private var premiumFeatures: [(icon: String, title: String, description: String)] {
        [
            ("waveform.and.mic", "Live Voice Coaching", "Talk to your coach hands-free between sets."),
            ("icloud.fill", "Cloud Sync", "Your training history on every device, always in sync."),
            ("chart.line.uptrend.xyaxis", "Advanced Signals", "Readiness breakdown, volume trends, progression curves."),
            ("brain", "Foundation Models", "On-device AI coaching with full privacy."),
            ("star.circle.fill", "Priority Support", "First in line when you need help."),
        ]
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        if subscriptionStore.products.isEmpty {
            if case .loading = subscriptionStore.loadingState {
                VALoadingState(message: "Loading plans…")
                    .frame(minHeight: 120)
            } else if case let .failed(reason) = subscriptionStore.loadingState {
                VAErrorState(
                    title: "Couldn't load plans",
                    message: reason,
                    retry: {
                        Task { await subscriptionStore.loadProducts() }
                    }
                )
            } else {
                VACard(style: .flat) {
                    Text("No plans available right now. Try again later.")
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
                        Text(isYearly ? "Yearly" : "Monthly")
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        if isYearly {
                            Text("SAVE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(VA.Colors.success)
                                .clipShape(Capsule())
                        }
                    }
                    Text(product.displayPrice + (isYearly ? " / year" : " / month"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
            }
            .padding(VA.Space.lg)
            .background {
                if isSelected {
                    VA.Colors.primary.opacity(0.08)
                } else {
                    Rectangle().fill(.regularMaterial)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                        .stroke(VA.Colors.primary, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action buttons

    private var actionButtons: some View {
        VStack(spacing: VA.Space.md) {
            VAButton(
                isPurchasing ? "Processing…" : "Start Premium",
                icon: "sparkles",
                style: .primary,
                isLoading: isPurchasing
            ) {
                Task { await startPurchase() }
            }
            .disabled(selectedProductID == nil || isPurchasing)

            Button("Restore Purchases") {
                Task {
                    VAHaptics.tap()
                    await subscriptionStore.restorePurchases()
                }
            }
            .font(VA.Typography.button)
            .foregroundStyle(VA.Colors.primary)

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
            Text("Subscriptions auto-renew unless cancelled at least 24 hours before the period ends. Manage in Settings → Apple ID → Subscriptions.")
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textTertiary)
                .multilineTextAlignment(.center)

            HStack(spacing: VA.Space.md) {
                Text("Terms of Service")
                Text("•")
                Text("Privacy Policy")
            }
            .font(VA.Typography.caption)
            .foregroundStyle(VA.Colors.textSecondary)
        }
        .padding(.top, VA.Space.md)
    }
}
#endif
