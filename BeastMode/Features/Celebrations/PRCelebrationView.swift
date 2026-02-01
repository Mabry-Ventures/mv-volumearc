// PRCelebrationView.swift
// BeastMode
// Celebration view shown when user hits a personal record

import SwiftUI
import ConfettiSwiftUI

/// Full-screen celebration view for personal records
struct PRCelebrationView: View {
    let prType: PRType
    let exerciseName: String
    let onDismiss: () -> Void
    let onShare: () -> Void

    @State private var confettiCounter = 0
    @State private var showContent = false
    @State private var mascotBounce = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.85)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Radial glow effect
            RadialGradient(
                gradient: Gradient(colors: [
                    Color.yellow.opacity(glowPulse ? 0.3 : 0.15),
                    Color.clear
                ]),
                center: .center,
                startRadius: 50,
                endRadius: 300
            )
            .ignoresSafeArea()
            .animation(
                .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                value: glowPulse
            )

            // Celebration card
            VStack(spacing: 24) {
                // Animated mascot/icon
                ZStack {
                    // Glow ring
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.yellow, .orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 4
                        )
                        .frame(width: 110, height: 110)
                        .scaleEffect(mascotBounce ? 1.1 : 1.0)

                    // Icon background
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 100, height: 100)

                    // Trophy icon
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                }
                .scaleEffect(mascotBounce ? 1.15 : 1.0)
                .animation(
                    .spring(response: 0.4, dampingFraction: 0.5)
                    .repeatCount(3, autoreverses: true),
                    value: mascotBounce
                )

                // PR Type badge
                Text(prType.title)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .orange.opacity(0.5), radius: 10, x: 0, y: 0)

                // Exercise name
                Text(exerciseName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                // PR details
                Text(prType.subtitle)
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(.white.opacity(0.15))
                    )

                Spacer()
                    .frame(height: 16)

                // Action buttons
                HStack(spacing: 16) {
                    // Dismiss button
                    Button {
                        onDismiss()
                    } label: {
                        Text("Keep Grinding")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(.white.opacity(0.2))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(.white.opacity(0.3), lineWidth: 1)
                                    )
                            )
                    }
                    .accessibilityLabel("Keep Grinding")
                    .accessibilityHint("Dismiss celebration and continue workout")

                    // Share button
                    Button {
                        onShare()
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.headline)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [.yellow, Color(hex: "FFD700")],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                            )
                    }
                    .accessibilityLabel("Share")
                    .accessibilityHint("Share your personal record")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Personal record celebration for \(exerciseName). \(prType.title)")
            .accessibilityAddTraits(.isModal)
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 32)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 32)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.3), .white.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .scaleEffect(showContent ? 1 : 0.5)
            .opacity(showContent ? 1 : 0)
            .confettiCannon(
                counter: $confettiCounter,
                num: 50,
                colors: [.yellow, .orange, Color(hex: "FF6B35")],
                confettiSize: 12,
                rainHeight: 800,
                radius: 400
            )
        }
        .onAppear {
            triggerCelebration()
        }
    }

    private func triggerCelebration() {
        // Trigger haptic
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif

        // Start glow animation
        glowPulse = true

        // Animate in
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            showContent = true
        }

        // Trigger confetti
        confettiCounter += 1

        // Bounce mascot
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            mascotBounce = true
        }
    }
}

// MARK: - Celebration Coordinator

/// Coordinator to present celebrations from anywhere in the app
@MainActor
class CelebrationCoordinator: ObservableObject {
    @Published var currentCelebration: CelebrationData?
    @Published var pendingShare: ShareData?

    struct CelebrationData: Identifiable {
        let id = UUID()
        let prType: PRType
        let exerciseName: String
        let weight: Double
        let reps: Int
        let setLog: SetLog
        let streakDays: Int?
    }

    struct ShareData: Identifiable {
        let id = UUID()
        let exerciseName: String
        let weight: Double
        let reps: Int
        let prType: PRType
        let streakDays: Int?
    }

    func celebrate(pr: PRType, exercise: String, weight: Double, reps: Int, set: SetLog, streak: Int? = nil) {
        currentCelebration = CelebrationData(
            prType: pr,
            exerciseName: exercise,
            weight: weight,
            reps: reps,
            setLog: set,
            streakDays: streak
        )
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            currentCelebration = nil
        }
    }

    func initiateShare() {
        guard let celebration = currentCelebration else { return }

        pendingShare = ShareData(
            exerciseName: celebration.exerciseName,
            weight: celebration.weight,
            reps: celebration.reps,
            prType: celebration.prType,
            streakDays: celebration.streakDays
        )

        dismiss()
    }

    func dismissShare() {
        pendingShare = nil
    }
}

// MARK: - Celebration Overlay Modifier

/// View modifier to add celebration overlay capability
struct CelebrationOverlay: ViewModifier {
    @ObservedObject var coordinator: CelebrationCoordinator

    func body(content: Content) -> some View {
        ZStack {
            content

            if let celebration = coordinator.currentCelebration {
                PRCelebrationView(
                    prType: celebration.prType,
                    exerciseName: celebration.exerciseName,
                    onDismiss: { coordinator.dismiss() },
                    onShare: { coordinator.initiateShare() }
                )
                .transition(.opacity.combined(with: .scale))
                .zIndex(100)
            }
        }
        .sheet(item: $coordinator.pendingShare) { shareData in
            PRShareSheet(
                exerciseName: shareData.exerciseName,
                weight: shareData.weight,
                reps: shareData.reps,
                prType: shareData.prType,
                streakDays: shareData.streakDays
            )
        }
    }
}

extension View {
    func celebrationOverlay(coordinator: CelebrationCoordinator) -> some View {
        modifier(CelebrationOverlay(coordinator: coordinator))
    }
}

// MARK: - Preview

#Preview {
    PRCelebrationView(
        prType: .estimatedMax(improvement: 15),
        exerciseName: "Barbell Bench Press",
        onDismiss: {},
        onShare: {}
    )
}
