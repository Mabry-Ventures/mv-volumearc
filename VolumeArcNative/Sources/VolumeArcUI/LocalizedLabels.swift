#if canImport(SwiftUI)
import Foundation
import VolumeArcCore

/// Localized display labels for `VolumeArcCore` enums that the UI renders.
///
/// These live in `VolumeArcUI` rather than `VolumeArcCore` so that the core
/// module stays free of `String(localized:)` calls (it's compiled into the
/// watchOS and widget extension targets where some localization APIs aren't
/// available). They live in a single file so translators see all enum-derived
/// labels in one place.

public extension AdvancementLevel {
    /// Localized display name (e.g., "Beginner", "Intermediate", "Advanced").
    var displayName: String {
        switch self {
        case .beginner:
            return String(localized: "Beginner", comment: "Advancement level — beginner")
        case .intermediate:
            return String(localized: "Intermediate", comment: "Advancement level — intermediate")
        case .advanced:
            return String(localized: "Advanced", comment: "Advancement level — advanced")
        }
    }

    /// Localized "X lifter" phrase. Whole phrase is localized per case so that
    /// translators can reorder words and respect noun gender agreement.
    var lifterPhrase: String {
        switch self {
        case .beginner:
            return String(localized: "Beginner lifter", comment: "Profile subtitle for a beginner lifter")
        case .intermediate:
            return String(localized: "Intermediate lifter", comment: "Profile subtitle for an intermediate lifter")
        case .advanced:
            return String(localized: "Advanced lifter", comment: "Profile subtitle for an advanced lifter")
        }
    }
}

public extension CoachingStyle {
    /// Localized display name.
    var displayName: String {
        switch self {
        case .motivational:
            return String(localized: "Motivational", comment: "Coaching style — motivational")
        case .analytical:
            return String(localized: "Analytical", comment: "Coaching style — analytical")
        case .minimal:
            return String(localized: "Minimal", comment: "Coaching style — minimal")
        }
    }

    /// Localized one-line description used in onboarding and settings rows.
    var displayDescription: String {
        switch self {
        case .motivational:
            return String(
                localized: "High energy, keeps you pushing through",
                comment: "Coaching style description — motivational"
            )
        case .analytical:
            return String(
                localized: "Data-driven, explains the why behind every call",
                comment: "Coaching style description — analytical"
            )
        case .minimal:
            return String(
                localized: "Short and direct, only when it matters",
                comment: "Coaching style description — minimal"
            )
        }
    }
}

public extension Equipment {
    /// Localized display name.
    var displayName: String {
        switch self {
        case .barbell:
            return String(localized: "Barbell", comment: "Equipment type — barbell")
        case .dumbbell:
            return String(localized: "Dumbbell", comment: "Equipment type — dumbbell")
        case .machine:
            return String(localized: "Machine", comment: "Equipment type — machine")
        case .bodyweight:
            return String(localized: "Bodyweight", comment: "Equipment type — bodyweight")
        case .cable:
            return String(localized: "Cable", comment: "Equipment type — cable")
        case .kettlebell:
            return String(localized: "Kettlebell", comment: "Equipment type — kettlebell")
        case .band:
            return String(localized: "Resistance band", comment: "Equipment type — band")
        }
    }
}

public extension PrivacyMode {
    /// Localized display name.
    var displayName: String {
        switch self {
        case .standard:
            return String(localized: "Standard", comment: "Privacy mode — standard")
        case .strict:
            return String(localized: "Strict", comment: "Privacy mode — strict")
        }
    }

    /// Localized one-line description shown as a footer in Edit Profile.
    var footerDescription: String {
        switch self {
        case .standard:
            return String(
                localized: "Your name and training history are included in coach prompts for personalized responses.",
                comment: "Privacy mode footer — standard"
            )
        case .strict:
            return String(
                localized: "Strict mode strips your name and anonymizes history before cloud coach requests.",
                comment: "Privacy mode footer — strict"
            )
        }
    }
}

/// VOL-176: chip labels for the Feedback sheet's category picker. The
/// `FeedbackBundle.Category` enum lives in `VolumeArcCore` (free of
/// localization APIs by design); the UI maps each case to a `String(localized:)`
/// here so translators see every enum-derived label in one file.
public enum LocalizedLabels {
    public static func formCheckExerciseDisplayName(_ exercise: FormCheckExercise) -> String {
        exercise.displayName
    }

    public static func feedbackCategoryDisplayName(_ category: FeedbackBundle.Category) -> String {
        switch category {
        case .bug:
            return String(localized: "Bug", comment: "Feedback category — something is broken")
        case .idea:
            return String(localized: "Idea", comment: "Feedback category — feature request or suggestion")
        case .coachQuality:
            return String(localized: "Coach quality", comment: "Feedback category — coach response quality")
        case .other:
            return String(localized: "Other", comment: "Feedback category — anything that doesn't fit the named buckets")
        }
    }
}
#endif
