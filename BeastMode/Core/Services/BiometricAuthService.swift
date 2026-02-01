// BiometricAuthService.swift
// BeastMode
// Biometric authentication service for Face ID and Touch ID

import LocalAuthentication
import SwiftUI
import os

// MARK: - Biometric Type

enum BiometricType: String {
    case none
    case touchID
    case faceID
    case opticID  // Vision Pro

    var displayName: String {
        switch self {
        case .none: return "None"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "lock.fill"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}

// MARK: - Biometric Error

enum BiometricError: Error, LocalizedError {
    case notAvailable
    case notEnrolled
    case authenticationFailed
    case userCancelled
    case systemCancelled
    case passcodeNotSet
    case biometryLockout
    case invalidContext
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device"
        case .notEnrolled:
            return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
        case .authenticationFailed:
            return "Authentication failed. Please try again."
        case .userCancelled:
            return "Authentication was cancelled"
        case .systemCancelled:
            return "Authentication was cancelled by the system"
        case .passcodeNotSet:
            return "Please set a device passcode to use biometric authentication"
        case .biometryLockout:
            return "Biometric authentication is locked. Please use your passcode."
        case .invalidContext:
            return "Authentication context is invalid"
        case .unknown(let error):
            return "Authentication error: \(error.localizedDescription)"
        }
    }

    var isRecoverable: Bool {
        switch self {
        case .authenticationFailed, .userCancelled:
            return true
        default:
            return false
        }
    }
}

// MARK: - Biometric Auth Service

@MainActor
class BiometricAuthService: ObservableObject {
    static let shared = BiometricAuthService()

    // MARK: - Published Properties

    @Published private(set) var biometricType: BiometricType = .none
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isEnrolled: Bool = false
    @Published var isEnabled: Bool = false {
        didSet {
            saveBiometricPreference()
        }
    }
    @Published var requireAuthOnLaunch: Bool = false {
        didSet {
            saveBiometricPreference()
        }
    }
    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var isAuthenticating: Bool = false

    // MARK: - Private Properties

    private let userDefaults = UserDefaults.standard
    private static let biometricEnabledKey = "com.beastmode.biometric.enabled"
    private static let requireAuthOnLaunchKey = "com.beastmode.biometric.requireOnLaunch"

    // MARK: - Initialization

    private init() {
        loadBiometricPreference()
        checkBiometricAvailability()
    }

    // MARK: - Public Methods

    /// Check what biometric type is available
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?

        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            isAvailable = true
            isEnrolled = true

            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            case .opticID:
                biometricType = .opticID
            case .none:
                biometricType = .none
            @unknown default:
                biometricType = .none
            }

            Logger.authentication.info("Biometric available: \(self.biometricType.displayName)")
        } else {
            isAvailable = false

            if let error = error {
                switch error.code {
                case LAError.biometryNotEnrolled.rawValue:
                    isEnrolled = false
                    // Still set the type even if not enrolled
                    switch context.biometryType {
                    case .faceID:
                        biometricType = .faceID
                    case .touchID:
                        biometricType = .touchID
                    case .opticID:
                        biometricType = .opticID
                    default:
                        biometricType = .none
                    }
                case LAError.biometryNotAvailable.rawValue:
                    biometricType = .none
                default:
                    biometricType = .none
                }

                Logger.authentication.info("Biometric not available: \(error.localizedDescription)")
            }
        }
    }

    /// Authenticate using biometrics
    func authenticate(reason: String = "Unlock Beast Mode") async -> Result<Void, BiometricError> {
        guard isAvailable else {
            return .failure(.notAvailable)
        }

        guard isEnrolled else {
            return .failure(.notEnrolled)
        }

        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()
        context.localizedCancelTitle = "Use Passcode"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                isAuthenticated = true
                Logger.authentication.info("Biometric authentication successful")
                return .success(())
            } else {
                Logger.authentication.warning("Biometric authentication returned false")
                return .failure(.authenticationFailed)
            }

        } catch let error as LAError {
            Logger.authentication.error("Biometric authentication error: \(error.localizedDescription)")
            return .failure(mapLAError(error))

        } catch {
            Logger.authentication.error("Biometric authentication unknown error: \(error.localizedDescription)")
            return .failure(.unknown(error))
        }
    }

    /// Authenticate with passcode fallback
    func authenticateWithPasscodeFallback(reason: String = "Unlock Beast Mode") async -> Result<Void, BiometricError> {
        isAuthenticating = true
        defer { isAuthenticating = false }

        let context = LAContext()

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,  // Includes passcode fallback
                localizedReason: reason
            )

            if success {
                isAuthenticated = true
                Logger.authentication.info("Authentication successful (with passcode fallback)")
                return .success(())
            } else {
                return .failure(.authenticationFailed)
            }

        } catch let error as LAError {
            Logger.authentication.error("Authentication error: \(error.localizedDescription)")
            return .failure(mapLAError(error))

        } catch {
            return .failure(.unknown(error))
        }
    }

    /// Reset authentication state (for app lock)
    func resetAuthenticationState() {
        isAuthenticated = false
        Logger.authentication.info("Authentication state reset")
    }

    /// Enable biometric authentication
    func enableBiometrics() async -> Result<Void, BiometricError> {
        // First, verify biometrics work
        let result = await authenticate(reason: "Enable \(biometricType.displayName) for Beast Mode")

        switch result {
        case .success:
            isEnabled = true
            Logger.authentication.info("Biometric authentication enabled")
            return .success(())
        case .failure(let error):
            Logger.authentication.error("Failed to enable biometrics: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    /// Disable biometric authentication
    func disableBiometrics() {
        isEnabled = false
        requireAuthOnLaunch = false
        Logger.authentication.info("Biometric authentication disabled")
    }

    // MARK: - Private Methods

    private func mapLAError(_ error: LAError) -> BiometricError {
        switch error.code {
        case .authenticationFailed:
            return .authenticationFailed
        case .userCancel:
            return .userCancelled
        case .systemCancel:
            return .systemCancelled
        case .passcodeNotSet:
            return .passcodeNotSet
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .biometryLockout:
            return .biometryLockout
        case .invalidContext:
            return .invalidContext
        default:
            return .unknown(error)
        }
    }

    private func loadBiometricPreference() {
        isEnabled = userDefaults.bool(forKey: Self.biometricEnabledKey)
        requireAuthOnLaunch = userDefaults.bool(forKey: Self.requireAuthOnLaunchKey)
    }

    private func saveBiometricPreference() {
        userDefaults.set(isEnabled, forKey: Self.biometricEnabledKey)
        userDefaults.set(requireAuthOnLaunch, forKey: Self.requireAuthOnLaunchKey)
    }
}

// MARK: - App Lock View

struct AppLockView: View {
    @ObservedObject var biometricService: BiometricAuthService
    @State private var error: BiometricError?
    @State private var showError = false

    let onUnlock: () -> Void

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [Color(hex: "1a1a2e"), Color(hex: "16213e")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon
                ZStack {
                    Circle()
                        .fill(Color(hex: "FF6B35").opacity(0.2))
                        .frame(width: 120, height: 120)

                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 50))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "FF6B35"), Color(hex: "F7931A")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Beast Mode")
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text("Locked")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))

                Spacer()

                // Unlock button
                VStack(spacing: 16) {
                    Button {
                        Task {
                            await authenticate()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            if biometricService.isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: biometricService.biometricType.iconName)
                                    .font(.title2)
                            }

                            Text("Unlock with \(biometricService.biometricType.displayName)")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "FF6B35"), Color(hex: "F7931A")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .foregroundStyle(.white)
                        .cornerRadius(14)
                    }
                    .disabled(biometricService.isAuthenticating)

                    Button("Use Passcode") {
                        Task {
                            await authenticateWithPasscode()
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
        .alert("Authentication Failed", isPresented: $showError) {
            Button("Try Again") {
                Task { await authenticate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(error?.localizedDescription ?? "Please try again")
        }
        .onAppear {
            Task {
                await authenticate()
            }
        }
    }

    private func authenticate() async {
        let result = await biometricService.authenticate()

        switch result {
        case .success:
            onUnlock()
        case .failure(let err):
            if err.isRecoverable {
                error = err
                showError = true
            }
        }
    }

    private func authenticateWithPasscode() async {
        let result = await biometricService.authenticateWithPasscodeFallback()

        switch result {
        case .success:
            onUnlock()
        case .failure(let err):
            error = err
            showError = true
        }
    }
}

// MARK: - Biometric Settings View

struct BiometricSettingsView: View {
    @ObservedObject var biometricService: BiometricAuthService
    @State private var showEnableError = false
    @State private var enableError: BiometricError?

    var body: some View {
        List {
            if biometricService.isAvailable && biometricService.isEnrolled {
                Section {
                    Toggle(isOn: Binding(
                        get: { biometricService.isEnabled },
                        set: { newValue in
                            if newValue {
                                Task { await enableBiometrics() }
                            } else {
                                biometricService.disableBiometrics()
                            }
                        }
                    )) {
                        Label {
                            Text("Use \(biometricService.biometricType.displayName)")
                        } icon: {
                            Image(systemName: biometricService.biometricType.iconName)
                                .foregroundStyle(Color(hex: "FF6B35"))
                        }
                    }

                    if biometricService.isEnabled {
                        Toggle(isOn: $biometricService.requireAuthOnLaunch) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Require on App Launch")
                                    Text("Ask for \(biometricService.biometricType.displayName) when opening the app")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(Color(hex: "FF6B35"))
                            }
                        }
                    }
                } header: {
                    Text("Security")
                } footer: {
                    Text("Protect your workout data with \(biometricService.biometricType.displayName).")
                }
            } else {
                Section {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        if !biometricService.isEnrolled {
                            Text("No \(biometricService.biometricType.displayName) enrolled. Set up in Settings.")
                        } else {
                            Text("Biometric authentication not available on this device.")
                        }
                    }
                    .font(.subheadline)
                } header: {
                    Text("Security")
                }
            }
        }
        .navigationTitle("Security")
        .alert("Couldn't Enable \(biometricService.biometricType.displayName)", isPresented: $showEnableError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(enableError?.localizedDescription ?? "Please try again")
        }
    }

    private func enableBiometrics() async {
        let result = await biometricService.enableBiometrics()

        if case .failure(let error) = result {
            enableError = error
            showEnableError = true
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

// MARK: - Previews

#Preview("App Lock") {
    AppLockView(biometricService: BiometricAuthService.shared) {
        print("Unlocked")
    }
}

#Preview("Biometric Settings") {
    NavigationStack {
        BiometricSettingsView(biometricService: BiometricAuthService.shared)
    }
}
