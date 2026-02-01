// OnboardingManager.swift
// BeastMode
// Manages onboarding state and permission requests

import SwiftUI
import UserNotifications
import HealthKit
import os

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case features
    case healthKit
    case notifications
    case signIn
    case complete

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .features: return "Features"
        case .healthKit: return "Health Data"
        case .notifications: return "Notifications"
        case .signIn: return "Account"
        case .complete: return "Ready"
        }
    }

    var isPermissionStep: Bool {
        switch self {
        case .healthKit, .notifications, .signIn:
            return true
        default:
            return false
        }
    }
}

// MARK: - Permission Status

enum PermissionStatus {
    case notDetermined
    case authorized
    case denied
    case restricted

    var isGranted: Bool {
        self == .authorized
    }
}

// MARK: - Onboarding Manager

@MainActor
class OnboardingManager: ObservableObject {
    // MARK: - Published Properties

    @Published var currentStep: OnboardingStep = .welcome
    @Published var isOnboardingComplete: Bool = false
    @Published var healthKitStatus: PermissionStatus = .notDetermined
    @Published var notificationStatus: PermissionStatus = .notDetermined
    @Published var isRequestingPermission: Bool = false

    // MARK: - Private Properties

    private let userDefaults = UserDefaults.standard
    private static let onboardingCompleteKey = "com.beastmode.onboardingComplete"
    private static let onboardingVersionKey = "com.beastmode.onboardingVersion"
    private static let currentOnboardingVersion = 1

    private let healthStore = HKHealthStore()

    // MARK: - Initialization

    init() {
        loadOnboardingState()
        Task {
            await checkCurrentPermissions()
        }
    }

    // MARK: - Public Methods

    /// Move to the next onboarding step
    func nextStep() {
        guard let nextIndex = OnboardingStep.allCases.firstIndex(where: { $0.rawValue == currentStep.rawValue + 1 }) else {
            completeOnboarding()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = OnboardingStep.allCases[nextIndex]
        }

        // Auto-complete if on the complete step
        if currentStep == .complete {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.completeOnboarding()
            }
        }
    }

    /// Move to the previous step
    func previousStep() {
        guard let prevIndex = OnboardingStep.allCases.firstIndex(where: { $0.rawValue == currentStep.rawValue - 1 }),
              prevIndex >= 0 else {
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = OnboardingStep.allCases[prevIndex]
        }
    }

    /// Skip to the end of onboarding
    func skipOnboarding() {
        completeOnboarding()
    }

    /// Complete the onboarding process
    func completeOnboarding() {
        Logger.app.info("Onboarding completed")

        userDefaults.set(true, forKey: Self.onboardingCompleteKey)
        userDefaults.set(Self.currentOnboardingVersion, forKey: Self.onboardingVersionKey)

        withAnimation(.easeInOut(duration: 0.3)) {
            isOnboardingComplete = true
        }
    }

    /// Reset onboarding (for testing)
    func resetOnboarding() {
        Logger.app.info("Resetting onboarding state")

        userDefaults.removeObject(forKey: Self.onboardingCompleteKey)
        userDefaults.removeObject(forKey: Self.onboardingVersionKey)

        currentStep = .welcome
        isOnboardingComplete = false
    }

    // MARK: - HealthKit Permission

    /// Request HealthKit authorization
    func requestHealthKitPermission() async {
        guard HKHealthStore.isHealthDataAvailable() else {
            Logger.healthKit.warning("HealthKit not available on this device")
            healthKitStatus = .restricted
            return
        }

        isRequestingPermission = true

        let typesToRead: Set<HKSampleType> = [
            HKQuantityType.quantityType(forIdentifier: .bodyMass)!,
            HKWorkoutType.workoutType()
        ]

        do {
            try await healthStore.requestAuthorization(toShare: [], read: typesToRead)

            // Check actual status after request
            let bodyMassStatus = healthStore.authorizationStatus(for: HKQuantityType.quantityType(forIdentifier: .bodyMass)!)

            switch bodyMassStatus {
            case .sharingAuthorized:
                healthKitStatus = .authorized
                Logger.healthKit.info("HealthKit authorization granted")
            case .sharingDenied:
                healthKitStatus = .denied
                Logger.healthKit.info("HealthKit authorization denied")
            case .notDetermined:
                healthKitStatus = .notDetermined
            @unknown default:
                healthKitStatus = .notDetermined
            }

        } catch {
            Logger.healthKit.error("HealthKit authorization error: \(error.localizedDescription)")
            healthKitStatus = .denied
            CrashReporter.shared.recordError(error, context: "HealthKit authorization")
        }

        isRequestingPermission = false
    }

    // MARK: - Notification Permission

    /// Request notification authorization
    func requestNotificationPermission() async {
        isRequestingPermission = true

        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])

            if granted {
                notificationStatus = .authorized
                Logger.app.info("Notification authorization granted")

                // Register for remote notifications
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                notificationStatus = .denied
                Logger.app.info("Notification authorization denied")
            }

        } catch {
            Logger.app.error("Notification authorization error: \(error.localizedDescription)")
            notificationStatus = .denied
            CrashReporter.shared.recordError(error, context: "Notification authorization")
        }

        isRequestingPermission = false
    }

    // MARK: - Private Methods

    private func loadOnboardingState() {
        let hasCompleted = userDefaults.bool(forKey: Self.onboardingCompleteKey)
        let savedVersion = userDefaults.integer(forKey: Self.onboardingVersionKey)

        // Show onboarding if never completed or if version has changed
        if hasCompleted && savedVersion >= Self.currentOnboardingVersion {
            isOnboardingComplete = true
        } else {
            isOnboardingComplete = false
        }

        Logger.app.info("Onboarding state loaded: complete=\(self.isOnboardingComplete)")
    }

    private func checkCurrentPermissions() async {
        // Check HealthKit
        if HKHealthStore.isHealthDataAvailable() {
            let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
            let status = healthStore.authorizationStatus(for: bodyMassType)

            switch status {
            case .sharingAuthorized:
                healthKitStatus = .authorized
            case .sharingDenied:
                healthKitStatus = .denied
            case .notDetermined:
                healthKitStatus = .notDetermined
            @unknown default:
                healthKitStatus = .notDetermined
            }
        } else {
            healthKitStatus = .restricted
        }

        // Check Notifications
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            notificationStatus = .authorized
        case .denied:
            notificationStatus = .denied
        case .notDetermined:
            notificationStatus = .notDetermined
        case .ephemeral:
            notificationStatus = .authorized
        @unknown default:
            notificationStatus = .notDetermined
        }
    }

    // MARK: - Computed Properties

    /// Check if user can proceed to next step
    var canProceed: Bool {
        switch currentStep {
        case .healthKit:
            return healthKitStatus != .notDetermined || isRequestingPermission == false
        case .notifications:
            return notificationStatus != .notDetermined || isRequestingPermission == false
        default:
            return true
        }
    }

    /// Progress through onboarding (0.0 to 1.0)
    var progress: Double {
        Double(currentStep.rawValue) / Double(OnboardingStep.allCases.count - 1)
    }
}
