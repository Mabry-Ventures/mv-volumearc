#if canImport(UIKit) && !os(watchOS)
import UIKit

/// Centralized haptic feedback for VolumeArc iOS.
/// Every user action that deserves tactile confirmation should call through here.
///
/// Marked `@MainActor` because UIKit's feedback generators
/// (`UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`,
/// `UISelectionFeedbackGenerator`) became MainActor-isolated as of iOS 17. Under
/// Swift 6 strict concurrency, calling them from a non-MainActor context
/// produces 25 "Call to main actor-isolated instance method ... in a synchronous
/// nonisolated context" errors. Every caller is a SwiftUI view body or modifier
/// closure (already @MainActor-isolated), so this annotation costs nothing at
/// the call sites.
@MainActor
public enum VAHaptics {
    /// Workout session started — firm commitment signal.
    public static func sessionStart() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// Workout session ended — closure signal.
    public static func sessionEnd() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Set logged successfully.
    public static func setLogged() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Rest timer completed — go signal.
    public static func restComplete() {
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            generator.impactOccurred()
        }
    }

    /// User made a decision (up/hold/down).
    public static func decisionMade() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Workout completed — celebration signal.
    public static func workoutComplete() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        }
    }

    /// Error or failure.
    public static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    /// Warning (non-blocking).
    public static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// Coach response received.
    public static func coachResponse() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Tab switch, picker selection, toggle.
    public static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// Button press (subtle).
    public static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}
#elseif os(watchOS)
import WatchKit

/// Centralized haptic feedback for VolumeArc watchOS.
public enum VAHaptics {
    public static func sessionStart() { WKInterfaceDevice.current().play(.start) }
    public static func sessionEnd() { WKInterfaceDevice.current().play(.stop) }
    public static func setLogged() { WKInterfaceDevice.current().play(.success) }
    public static func restComplete() { WKInterfaceDevice.current().play(.notification) }
    public static func decisionMade() { WKInterfaceDevice.current().play(.click) }
    public static func workoutComplete() { WKInterfaceDevice.current().play(.success) }
    public static func error() { WKInterfaceDevice.current().play(.failure) }
    public static func warning() { WKInterfaceDevice.current().play(.retry) }
    public static func coachResponse() { WKInterfaceDevice.current().play(.directionUp) }
    public static func selection() { WKInterfaceDevice.current().play(.click) }
    public static func tap() { WKInterfaceDevice.current().play(.click) }
}
#else
/// No-op haptics for platforms without haptic hardware.
public enum VAHaptics {
    public static func sessionStart() {}
    public static func sessionEnd() {}
    public static func setLogged() {}
    public static func restComplete() {}
    public static func decisionMade() {}
    public static func workoutComplete() {}
    public static func error() {}
    public static func warning() {}
    public static func coachResponse() {}
    public static func selection() {}
    public static func tap() {}
}
#endif
