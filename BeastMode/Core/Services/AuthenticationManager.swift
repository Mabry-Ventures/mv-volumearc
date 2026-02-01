// AuthenticationManager.swift
// BeastMode
// Handles Sign in with Apple authentication and user session management

import SwiftUI
import AuthenticationServices
import os

// MARK: - Authentication State

enum AuthenticationState: Equatable {
    case unknown
    case unauthenticated
    case authenticated(userId: String)
    case error(String)

    static func == (lhs: AuthenticationState, rhs: AuthenticationState) -> Bool {
        switch (lhs, rhs) {
        case (.unknown, .unknown),
             (.unauthenticated, .unauthenticated):
            return true
        case (.authenticated(let lhsId), .authenticated(let rhsId)):
            return lhsId == rhsId
        case (.error(let lhsError), .error(let rhsError)):
            return lhsError == rhsError
        default:
            return false
        }
    }
}

// MARK: - Authentication Error

enum AuthenticationError: LocalizedError {
    case signInFailed(underlying: Error?)
    case credentialRevoked
    case tokenRefreshFailed
    case keychainError(String)
    case invalidState

    var errorDescription: String? {
        switch self {
        case .signInFailed(let error):
            if let error = error {
                return "Sign in failed: \(error.localizedDescription)"
            }
            return "Sign in failed"
        case .credentialRevoked:
            return "Your sign in credentials have been revoked"
        case .tokenRefreshFailed:
            return "Failed to refresh authentication"
        case .keychainError(let message):
            return "Keychain error: \(message)"
        case .invalidState:
            return "Invalid authentication state"
        }
    }
}

// MARK: - User Credentials

struct UserCredentials: Codable {
    let userId: String
    let email: String?
    let fullName: PersonNameComponents?
    let identityToken: Data?
    let authorizationCode: Data?
    let lastAuthenticated: Date

    var displayName: String {
        if let fullName = fullName {
            return PersonNameComponentsFormatter.localizedString(from: fullName, style: .default)
        }
        return email ?? "User"
    }
}

// MARK: - Authentication Manager

@MainActor
class AuthenticationManager: NSObject, ObservableObject {
    @Published private(set) var state: AuthenticationState = .unknown
    @Published private(set) var currentUser: UserCredentials?
    @Published var showSignInSheet = false

    private let keychainService = KeychainService.shared

    private static let userIdKey = "com.beastmode.apple.userId"
    private static let credentialsKey = "com.beastmode.apple.credentials"

    override init() {
        super.init()
        Task {
            await checkExistingCredentials()
        }
    }

    // MARK: - Public Methods

    /// Check for existing credentials and validate them
    func checkExistingCredentials() async {
        Logger.authentication.info("Checking existing credentials")

        guard let userId = keychainService.getString(forKey: Self.userIdKey) else {
            Logger.authentication.info("No existing credentials found")
            state = .unauthenticated
            return
        }

        // Verify credential state with Apple
        let provider = ASAuthorizationAppleIDProvider()

        do {
            let credentialState = try await provider.credentialState(forUserID: userId)

            switch credentialState {
            case .authorized:
                Logger.authentication.info("Existing credentials are valid")
                state = .authenticated(userId: userId)

                // Load cached credentials
                if let credentialsData = keychainService.getData(forKey: Self.credentialsKey),
                   let credentials = try? JSONDecoder().decode(UserCredentials.self, from: credentialsData) {
                    currentUser = credentials
                }

            case .revoked:
                Logger.authentication.warning("Credentials have been revoked")
                await signOut()
                state = .error(AuthenticationError.credentialRevoked.localizedDescription)

            case .notFound:
                Logger.authentication.info("Credentials not found")
                await signOut()

            case .transferred:
                Logger.authentication.info("Credentials transferred to new device")
                state = .unauthenticated

            @unknown default:
                Logger.authentication.warning("Unknown credential state")
                state = .unauthenticated
            }
        } catch {
            Logger.authentication.error("Failed to check credential state: \(error.localizedDescription)")
            state = .unauthenticated
        }
    }

    /// Initiate Sign in with Apple flow
    func signIn() {
        Logger.authentication.info("Initiating Sign in with Apple")

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// Sign out the current user
    func signOut() async {
        Logger.authentication.info("Signing out user")

        // Clear keychain
        keychainService.delete(forKey: Self.userIdKey)
        keychainService.delete(forKey: Self.credentialsKey)

        currentUser = nil
        state = .unauthenticated
    }

    /// Check if user is authenticated
    var isAuthenticated: Bool {
        if case .authenticated = state {
            return true
        }
        return false
    }

    /// Handle successful authentication from external source (e.g., SignInWithAppleButton)
    /// This method properly encapsulates state management
    func handleSuccessfulAuthentication(credential: ASAuthorizationAppleIDCredential) {
        let userId = credential.user
        Logger.authentication.info("Processing external authentication")

        // Create credentials object
        let credentials = UserCredentials(
            userId: userId,
            email: credential.email,
            fullName: credential.fullName,
            identityToken: credential.identityToken,
            authorizationCode: credential.authorizationCode,
            lastAuthenticated: Date()
        )

        // Store in keychain
        keychainService.setString(userId, forKey: Self.userIdKey)

        if let credentialsData = try? JSONEncoder().encode(credentials) {
            keychainService.setData(credentialsData, forKey: Self.credentialsKey)
        }

        currentUser = credentials
        state = .authenticated(userId: userId)

        // Record successful sign in
        CrashReporter.shared.setUserIdentifier(userId)
    }

    // MARK: - Private Methods

    private func handleAuthorization(_ authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Logger.authentication.error("Invalid credential type")
            state = .error("Invalid credential type")
            return
        }

        let userId = appleIDCredential.user
        Logger.authentication.info("Successfully authenticated user")

        // Create credentials object
        let credentials = UserCredentials(
            userId: userId,
            email: appleIDCredential.email,
            fullName: appleIDCredential.fullName,
            identityToken: appleIDCredential.identityToken,
            authorizationCode: appleIDCredential.authorizationCode,
            lastAuthenticated: Date()
        )

        // Store in keychain
        keychainService.setString(userId, forKey: Self.userIdKey)

        if let credentialsData = try? JSONEncoder().encode(credentials) {
            keychainService.setData(credentialsData, forKey: Self.credentialsKey)
        }

        currentUser = credentials
        state = .authenticated(userId: userId)

        // Record successful sign in
        CrashReporter.shared.setUserIdentifier(userId)
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            handleAuthorization(authorization)
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        Task { @MainActor in
            Logger.authentication.error("Sign in failed: \(error.localizedDescription)")

            if let authError = error as? ASAuthorizationError {
                switch authError.code {
                case .canceled:
                    // User cancelled, don't show error
                    Logger.authentication.info("User cancelled sign in")
                case .failed:
                    state = .error("Sign in failed. Please try again.")
                case .invalidResponse:
                    state = .error("Invalid response from Apple. Please try again.")
                case .notHandled:
                    state = .error("Sign in request was not handled.")
                case .notInteractive:
                    state = .error("Sign in requires user interaction.")
                case .unknown:
                    state = .error("An unknown error occurred.")
                @unknown default:
                    state = .error("Sign in failed: \(error.localizedDescription)")
                }
            } else {
                state = .error("Sign in failed: \(error.localizedDescription)")
            }

            CrashReporter.shared.recordError(error, context: "Sign in with Apple")
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Get the key window from the active scene
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return UIWindow()
        }
        return window
    }
}

// MARK: - Sign In With Apple Button View

struct SignInWithAppleButton: View {
    @EnvironmentObject var authManager: AuthenticationManager
    let onCompletion: ((Result<Void, Error>) -> Void)?

    init(onCompletion: ((Result<Void, Error>) -> Void)? = nil) {
        self.onCompletion = onCompletion
    }

    var body: some View {
        SignInWithAppleButtonViewRepresentable(
            type: .signIn,
            style: .black
        ) { request in
            request.requestedScopes = [.fullName, .email]
        } onCompletion: { result in
            switch result {
            case .success(let authorization):
                if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {
                    Task { @MainActor in
                        authManager.handleSuccessfulAuthentication(credential: appleIDCredential)
                        onCompletion?(.success(()))
                    }
                }

            case .failure(let error):
                Logger.authentication.error("Sign in failed: \(error.localizedDescription)")
                onCompletion?(.failure(error))
            }
        }
        .frame(height: 50)
        .cornerRadius(10)
    }
}

// MARK: - Sign In With Apple Button Representable

struct SignInWithAppleButtonViewRepresentable: UIViewRepresentable {
    let type: ASAuthorizationAppleIDButton.ButtonType
    let style: ASAuthorizationAppleIDButton.Style
    let onRequest: (ASAuthorizationAppleIDRequest) -> Void
    let onCompletion: (Result<ASAuthorization, Error>) -> Void

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        ASAuthorizationAppleIDButton(type: type, style: style)
    }

    func updateUIView(_ uiView: ASAuthorizationAppleIDButton, context: Context) {
        uiView.removeTarget(context.coordinator, action: nil, for: .touchUpInside)
        uiView.addTarget(context.coordinator, action: #selector(Coordinator.handleTap), for: .touchUpInside)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
        let parent: SignInWithAppleButtonViewRepresentable

        init(_ parent: SignInWithAppleButtonViewRepresentable) {
            self.parent = parent
        }

        @objc func handleTap() {
            let request = ASAuthorizationAppleIDProvider().createRequest()
            parent.onRequest(request)

            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
            parent.onCompletion(.success(authorization))
        }

        func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
            parent.onCompletion(.failure(error))
        }

        func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}

// MARK: - Authentication View

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // App icon/logo
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 80))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "FF6B35"), Color(hex: "F7931A")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                VStack(spacing: 8) {
                    Text(L10n.App.name)
                        .font(.largeTitle.weight(.bold))

                    Text(L10n.Onboarding.signInDesc)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                VStack(spacing: 16) {
                    SignInWithAppleButton { result in
                        switch result {
                        case .success:
                            dismiss()
                        case .failure:
                            break
                        }
                    }
                    .padding(.horizontal, 40)

                    Button("Continue without signing in") {
                        dismiss()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                // Benefits list
                VStack(alignment: .leading, spacing: 12) {
                    BenefitRow(icon: "icloud.fill", text: "Sync data across all your devices")
                    BenefitRow(icon: "lock.shield.fill", text: "Secure backup of your workouts")
                    BenefitRow(icon: "arrow.triangle.2.circlepath", text: "Never lose your progress")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.ultraThinMaterial)
                )
                .padding(.horizontal)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color(hex: "FF6B35"))
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Color Extension (for hex support)

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

#Preview("Authentication View") {
    AuthenticationView()
        .environmentObject(AuthenticationManager())
}

#Preview("Sign In Button") {
    SignInWithAppleButton()
        .environmentObject(AuthenticationManager())
        .padding()
}
