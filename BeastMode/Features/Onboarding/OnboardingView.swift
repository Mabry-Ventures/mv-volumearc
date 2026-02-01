// OnboardingView.swift
// BeastMode
// Main onboarding flow view with step-by-step introduction

import SwiftUI
import AuthenticationServices

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @StateObject private var onboardingManager = OnboardingManager()
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Background gradient
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress indicator
                OnboardingProgressBar(progress: onboardingManager.progress)
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Skip button
                if onboardingManager.currentStep != .complete {
                    HStack {
                        Spacer()
                        Button("Skip") {
                            onboardingManager.skipOnboarding()
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                }

                // Content
                TabView(selection: $onboardingManager.currentStep) {
                    WelcomeStepView(onContinue: onboardingManager.nextStep)
                        .tag(OnboardingStep.welcome)

                    FeaturesStepView(onContinue: onboardingManager.nextStep)
                        .tag(OnboardingStep.features)

                    HealthKitStepView(
                        status: onboardingManager.healthKitStatus,
                        isRequesting: onboardingManager.isRequestingPermission,
                        onRequest: {
                            Task { await onboardingManager.requestHealthKitPermission() }
                        },
                        onContinue: onboardingManager.nextStep
                    )
                    .tag(OnboardingStep.healthKit)

                    NotificationStepView(
                        status: onboardingManager.notificationStatus,
                        isRequesting: onboardingManager.isRequestingPermission,
                        onRequest: {
                            Task { await onboardingManager.requestNotificationPermission() }
                        },
                        onContinue: onboardingManager.nextStep
                    )
                    .tag(OnboardingStep.notifications)

                    BiometricStepView(
                        biometricService: onboardingManager.biometricService,
                        onContinue: onboardingManager.nextStep
                    )
                    .tag(OnboardingStep.biometric)

                    SignInStepView(
                        authManager: authManager,
                        onContinue: onboardingManager.nextStep
                    )
                    .tag(OnboardingStep.signIn)

                    CompleteStepView(
                        healthKitGranted: onboardingManager.healthKitStatus.isGranted,
                        notificationsGranted: onboardingManager.notificationStatus.isGranted,
                        biometricEnabled: onboardingManager.biometricService.isEnabled,
                        biometricType: onboardingManager.biometricService.biometricType,
                        isSignedIn: authManager.isAuthenticated,
                        onGetStarted: onboardingManager.completeOnboarding
                    )
                    .tag(OnboardingStep.complete)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: onboardingManager.currentStep)
            }
        }
        .environmentObject(onboardingManager)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "1a1a2e"),
                Color(hex: "16213e"),
                Color(hex: "0f3460")
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Progress Bar

struct OnboardingProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 4)

                // Progress
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF6B35"), Color(hex: "F7931A")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * progress, height: 4)
                    .animation(.spring(response: 0.4), value: progress)
            }
        }
        .frame(height: 4)
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let onContinue: () -> Void

    @State private var animateIcon = false
    @State private var animateText = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon with animation
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FF6B35").opacity(0.3), Color(hex: "F7931A").opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 160, height: 160)
                    .scaleEffect(animateIcon ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: true), value: animateIcon)

                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF6B35"), Color(hex: "F7931A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .onAppear { animateIcon = true }

            VStack(spacing: 16) {
                Text("Welcome to")
                    .font(.title2)
                    .foregroundStyle(.white.opacity(0.8))

                Text("Beast Mode")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Your personal strength training companion.\nTrack progress, hit PRs, and become the beast you were meant to be.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 32)
            }
            .opacity(animateText ? 1 : 0)
            .offset(y: animateText ? 0 : 20)
            .animation(.easeOut(duration: 0.6).delay(0.3), value: animateText)
            .onAppear { animateText = true }

            Spacer()

            OnboardingButton(title: "Get Started", action: onContinue)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
    }
}

// MARK: - Features Step

struct FeaturesStepView: View {
    let onContinue: () -> Void

    private let features: [(icon: String, title: String, description: String)] = [
        ("chart.line.uptrend.xyaxis", "Progressive Overload", "Track your lifts and watch your strength grow over time"),
        ("trophy.fill", "Personal Records", "Celebrate every PR with satisfying animations and badges"),
        ("brain.head.profile", "AI Coach", "Get personalized weekly reviews and training insights"),
        ("flame.fill", "Streak Tracking", "Stay motivated with workout streaks and consistency tracking"),
        ("applewatch", "Watch Support", "Quick logging and complications right on your wrist")
    ]

    var body: some View {
        VStack(spacing: 24) {
            Text("Powerful Features")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
                .padding(.top, 32)

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(features.indices, id: \.self) { index in
                        FeatureRow(
                            icon: features[index].icon,
                            title: features[index].title,
                            description: features[index].description
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
                    }
                }
                .padding(.horizontal)
            }

            Spacer()

            OnboardingButton(title: "Continue", action: onContinue)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color(hex: "FF6B35").opacity(0.2))
                    .frame(width: 50, height: 50)

                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color(hex: "FF6B35"))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - HealthKit Step

struct HealthKitStepView: View {
    let status: PermissionStatus
    let isRequesting: Bool
    let onRequest: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "heart.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 16) {
                Text("Health Data")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("Beast Mode can read your body weight from Apple Health to track your progress alongside your lifts.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 32)

                // Benefits
                VStack(alignment: .leading, spacing: 12) {
                    BenefitItem(icon: "chart.xyaxis.line", text: "See weight trends with your strength gains")
                    BenefitItem(icon: "arrow.triangle.2.circlepath", text: "Automatic sync from any health app")
                    BenefitItem(icon: "lock.shield.fill", text: "Your data stays private and secure")
                }
                .padding(.top, 8)
            }

            Spacer()

            // Status indicator
            if status != .notDetermined {
                PermissionStatusBadge(status: status)
            }

            VStack(spacing: 12) {
                if status == .notDetermined {
                    OnboardingButton(
                        title: isRequesting ? "Requesting..." : "Allow Health Access",
                        isLoading: isRequesting,
                        action: onRequest
                    )
                } else {
                    OnboardingButton(title: "Continue", action: onContinue)
                }

                if status == .notDetermined {
                    Button("Skip for Now") {
                        onContinue()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Notification Step

struct NotificationStepView: View {
    let status: PermissionStatus
    let isRequesting: Bool
    let onRequest: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.blue)
            }

            VStack(spacing: 16) {
                Text("Stay on Track")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("Get reminders to log your workouts and celebrate your achievements.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 32)

                // Benefits
                VStack(alignment: .leading, spacing: 12) {
                    BenefitItem(icon: "calendar.badge.clock", text: "Workout reminders on your schedule")
                    BenefitItem(icon: "trophy.fill", text: "PR celebrations and achievements")
                    BenefitItem(icon: "flame.fill", text: "Streak alerts to keep you motivated")
                }
                .padding(.top, 8)
            }

            Spacer()

            // Status indicator
            if status != .notDetermined {
                PermissionStatusBadge(status: status)
            }

            VStack(spacing: 12) {
                if status == .notDetermined {
                    OnboardingButton(
                        title: isRequesting ? "Requesting..." : "Enable Notifications",
                        isLoading: isRequesting,
                        action: onRequest
                    )
                } else {
                    OnboardingButton(title: "Continue", action: onContinue)
                }

                if status == .notDetermined {
                    Button("Skip for Now") {
                        onContinue()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Biometric Step

struct BiometricStepView: View {
    @ObservedObject var biometricService: BiometricAuthService
    let onContinue: () -> Void

    @State private var enableError: BiometricError?
    @State private var showError = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: biometricService.biometricType.iconName)
                    .font(.system(size: 50))
                    .foregroundStyle(.purple)
            }

            VStack(spacing: 16) {
                Text("Secure Your Data")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("Use \(biometricService.biometricType.displayName) to protect your workout data and keep your progress private.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 32)

                // Benefits
                VStack(alignment: .leading, spacing: 12) {
                    BenefitItem(icon: "lock.shield.fill", text: "Quick and secure access")
                    BenefitItem(icon: "eye.slash.fill", text: "Keep your data private")
                    BenefitItem(icon: "bolt.fill", text: "Unlock instantly with a glance")
                }
                .padding(.top, 8)
            }

            Spacer()

            // Status indicator
            if biometricService.isEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("\(biometricService.biometricType.displayName) Enabled")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .font(.subheadline)
            }

            VStack(spacing: 12) {
                if !biometricService.isAvailable || !biometricService.isEnrolled {
                    // Biometrics not available
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(biometricService.isEnrolled ? "Biometrics not available" : "No biometrics enrolled")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .font(.subheadline)

                        OnboardingButton(title: "Continue", action: onContinue)
                    }
                } else if biometricService.isEnabled {
                    OnboardingButton(title: "Continue", action: onContinue)
                } else {
                    OnboardingButton(
                        title: biometricService.isAuthenticating ? "Enabling..." : "Enable \(biometricService.biometricType.displayName)",
                        isLoading: biometricService.isAuthenticating,
                        action: {
                            Task { await enableBiometrics() }
                        }
                    )

                    Button("Skip for Now") {
                        onContinue()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
        .alert("Couldn't Enable \(biometricService.biometricType.displayName)", isPresented: $showError) {
            Button("Try Again") {
                Task { await enableBiometrics() }
            }
            Button("Skip", role: .cancel) {
                onContinue()
            }
        } message: {
            Text(enableError?.localizedDescription ?? "Please try again")
        }
    }

    private func enableBiometrics() async {
        let result = await biometricService.enableBiometrics()

        switch result {
        case .success:
            // Successfully enabled, will auto-update UI
            break
        case .failure(let error):
            if error.isRecoverable {
                enableError = error
                showError = true
            }
        }
    }
}

// MARK: - Sign In Step

struct SignInStepView: View {
    @ObservedObject var authManager: AuthenticationManager
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "icloud.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 16) {
                Text("Sync Your Data")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("Sign in with Apple to sync your workouts across all your devices and never lose your progress.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 32)

                // Benefits
                VStack(alignment: .leading, spacing: 12) {
                    BenefitItem(icon: "iphone.and.ipad", text: "Access your data on all devices")
                    BenefitItem(icon: "arrow.clockwise.icloud.fill", text: "Automatic cloud backup")
                    BenefitItem(icon: "lock.shield.fill", text: "Private and secure with Apple")
                }
                .padding(.top, 8)
            }

            Spacer()

            // Status indicator
            if authManager.isAuthenticated {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Signed in as \(authManager.currentUser?.displayName ?? "User")")
                        .foregroundStyle(.white.opacity(0.8))
                }
                .font(.subheadline)
            }

            VStack(spacing: 16) {
                if !authManager.isAuthenticated {
                    SignInWithAppleButton { result in
                        switch result {
                        case .success:
                            // Will auto-update authManager state
                            break
                        case .failure:
                            break
                        }
                    }
                    .frame(height: 50)
                    .cornerRadius(12)
                    .padding(.horizontal, 40)
                }

                OnboardingButton(
                    title: authManager.isAuthenticated ? "Continue" : "Continue without signing in",
                    style: authManager.isAuthenticated ? .primary : .secondary,
                    action: onContinue
                )
                .padding(.horizontal, 40)
            }
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Complete Step

struct CompleteStepView: View {
    let healthKitGranted: Bool
    let notificationsGranted: Bool
    let biometricEnabled: Bool
    let biometricType: BiometricType
    let isSignedIn: Bool
    let onGetStarted: () -> Void

    @State private var showCheckmark = false
    @State private var showText = false
    @State private var showButton = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Success animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.2))
                    .frame(width: 140, height: 140)
                    .scaleEffect(showCheckmark ? 1.0 : 0.5)
                    .opacity(showCheckmark ? 1.0 : 0.0)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.green)
                    .scaleEffect(showCheckmark ? 1.0 : 0.0)
                    .rotationEffect(.degrees(showCheckmark ? 0 : -90))
            }
            .animation(.spring(response: 0.6, dampingFraction: 0.7), value: showCheckmark)

            VStack(spacing: 16) {
                Text("You're All Set!")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("Beast Mode is ready to help you track your gains and crush your goals.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 32)
            }
            .opacity(showText ? 1 : 0)
            .offset(y: showText ? 0 : 20)
            .animation(.easeOut(duration: 0.4).delay(0.3), value: showText)

            // Setup summary
            VStack(spacing: 12) {
                SetupSummaryRow(
                    icon: "heart.fill",
                    title: "Health Data",
                    isEnabled: healthKitGranted
                )
                SetupSummaryRow(
                    icon: "bell.fill",
                    title: "Notifications",
                    isEnabled: notificationsGranted
                )
                SetupSummaryRow(
                    icon: biometricType.iconName,
                    title: biometricType == .none ? "App Lock" : biometricType.displayName,
                    isEnabled: biometricEnabled
                )
                SetupSummaryRow(
                    icon: "icloud.fill",
                    title: "Cloud Sync",
                    isEnabled: isSignedIn
                )
            }
            .padding(.horizontal, 40)
            .opacity(showText ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.5), value: showText)

            Spacer()

            OnboardingButton(title: "Start Training", action: onGetStarted)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 20)
                .animation(.easeOut(duration: 0.4).delay(0.7), value: showButton)
        }
        .onAppear {
            showCheckmark = true
            showText = true
            showButton = true
        }
    }
}

struct SetupSummaryRow: View {
    let icon: String
    let title: String
    let isEnabled: Bool

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(isEnabled ? .green : .white.opacity(0.4))
                .frame(width: 30)

            Text(title)
                .foregroundStyle(.white.opacity(0.8))

            Spacer()

            Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isEnabled ? .green : .white.opacity(0.4))
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
        )
    }
}

// MARK: - Supporting Views

struct BenefitItem: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color(hex: "FF6B35"))
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct PermissionStatusBadge: View {
    let status: PermissionStatus

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: status.isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
            Text(status.isGranted ? "Enabled" : "Not Enabled")
        }
        .font(.subheadline)
        .foregroundStyle(status.isGranted ? .green : .orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(status.isGranted ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
        )
    }
}

// MARK: - Onboarding Button

enum OnboardingButtonStyle {
    case primary
    case secondary
}

struct OnboardingButton: View {
    let title: String
    var isLoading: Bool = false
    var style: OnboardingButtonStyle = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }

                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundView)
            .foregroundStyle(style == .primary ? .white : .white.opacity(0.8))
            .cornerRadius(14)
        }
        .disabled(isLoading)
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .primary:
            LinearGradient(
                colors: [Color(hex: "FF6B35"), Color(hex: "F7931A")],
                startPoint: .leading,
                endPoint: .trailing
            )
        case .secondary:
            Color.white.opacity(0.15)
        }
    }
}

// MARK: - Color Extension

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview("Onboarding Flow") {
    OnboardingView()
        .environmentObject(AuthenticationManager())
}

#Preview("Welcome Step") {
    ZStack {
        Color(hex: "1a1a2e").ignoresSafeArea()
        WelcomeStepView(onContinue: {})
    }
}

#Preview("Features Step") {
    ZStack {
        Color(hex: "1a1a2e").ignoresSafeArea()
        FeaturesStepView(onContinue: {})
    }
}

#Preview("Complete Step") {
    ZStack {
        Color(hex: "1a1a2e").ignoresSafeArea()
        CompleteStepView(
            healthKitGranted: true,
            notificationsGranted: true,
            biometricEnabled: true,
            biometricType: .faceID,
            isSignedIn: false,
            onGetStarted: {}
        )
    }
}

#Preview("Biometric Step") {
    ZStack {
        Color(hex: "1a1a2e").ignoresSafeArea()
        BiometricStepView(
            biometricService: BiometricAuthService.shared,
            onContinue: {}
        )
    }
}
