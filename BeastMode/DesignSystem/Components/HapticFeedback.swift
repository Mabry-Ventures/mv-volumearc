import SwiftUI
import UIKit

/// Centralized haptic feedback manager
final class HapticManager {
    static let shared = HapticManager()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let notification = UINotificationFeedbackGenerator()
    private let selection = UISelectionFeedbackGenerator()

    private init() {
        // Prepare generators for faster response
        prepareAll()
    }

    func prepareAll() {
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
        softImpact.prepare()
        rigidImpact.prepare()
        notification.prepare()
        selection.prepare()
    }

    // MARK: - Impact Feedback

    func light() {
        lightImpact.impactOccurred()
        lightImpact.prepare()
    }

    func medium() {
        mediumImpact.impactOccurred()
        mediumImpact.prepare()
    }

    func heavy() {
        heavyImpact.impactOccurred()
        heavyImpact.prepare()
    }

    func soft() {
        softImpact.impactOccurred()
        softImpact.prepare()
    }

    func rigid() {
        rigidImpact.impactOccurred()
        rigidImpact.prepare()
    }

    // MARK: - Notification Feedback

    func success() {
        notification.notificationOccurred(.success)
        notification.prepare()
    }

    func warning() {
        notification.notificationOccurred(.warning)
        notification.prepare()
    }

    func error() {
        notification.notificationOccurred(.error)
        notification.prepare()
    }

    // MARK: - Selection Feedback

    func selection() {
        self.selection.selectionChanged()
        self.selection.prepare()
    }

    // MARK: - Custom Patterns

    /// Haptic for completing a set
    func setComplete() {
        medium()
    }

    /// Haptic for hitting a PR
    func personalRecord() {
        // Double tap pattern
        heavy()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.success()
        }
    }

    /// Haptic for starting a workout
    func workoutStart() {
        rigid()
    }

    /// Haptic for ending a workout
    func workoutEnd() {
        success()
    }

    /// Haptic for rest timer ending
    func restTimerComplete() {
        // Attention-grabbing pattern
        notification.notificationOccurred(.warning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.notification.notificationOccurred(.success)
        }
    }

    /// Haptic for button tap
    func buttonTap() {
        light()
    }

    /// Haptic for toggle
    func toggle() {
        soft()
    }

    /// Haptic for slider/stepper change
    func tick() {
        selection()
    }
}

// MARK: - View Modifier

struct HapticTapModifier: ViewModifier {
    let style: HapticStyle

    enum HapticStyle {
        case light
        case medium
        case heavy
        case success
        case selection
        case setComplete
        case pr
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                TapGesture()
                    .onEnded { _ in
                        triggerHaptic()
                    }
            )
    }

    private func triggerHaptic() {
        switch style {
        case .light:
            HapticManager.shared.light()
        case .medium:
            HapticManager.shared.medium()
        case .heavy:
            HapticManager.shared.heavy()
        case .success:
            HapticManager.shared.success()
        case .selection:
            HapticManager.shared.selection()
        case .setComplete:
            HapticManager.shared.setComplete()
        case .pr:
            HapticManager.shared.personalRecord()
        }
    }
}

extension View {
    /// Add haptic feedback to a view on tap
    func haptic(_ style: HapticTapModifier.HapticStyle = .light) -> some View {
        modifier(HapticTapModifier(style: style))
    }
}

// MARK: - Haptic Button Style

struct HapticButtonStyle: ButtonStyle {
    var hapticStyle: HapticTapModifier.HapticStyle = .light

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed {
                    switch hapticStyle {
                    case .light:
                        HapticManager.shared.light()
                    case .medium:
                        HapticManager.shared.medium()
                    case .heavy:
                        HapticManager.shared.heavy()
                    case .success:
                        HapticManager.shared.success()
                    case .selection:
                        HapticManager.shared.selection()
                    case .setComplete:
                        HapticManager.shared.setComplete()
                    case .pr:
                        HapticManager.shared.personalRecord()
                    }
                }
            }
    }
}

extension ButtonStyle where Self == HapticButtonStyle {
    static var haptic: HapticButtonStyle {
        HapticButtonStyle()
    }

    static func haptic(_ style: HapticTapModifier.HapticStyle) -> HapticButtonStyle {
        HapticButtonStyle(hapticStyle: style)
    }
}
