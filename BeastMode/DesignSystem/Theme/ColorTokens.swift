import SwiftUI

// MARK: - Brand Colors

extension Color {
    /// Primary brand color - Deep violet
    static let beastPrimary = Color("BeastPrimary")

    /// Secondary brand color - Energetic orange
    static let beastSecondary = Color("BeastSecondary")

    /// Accent color - Electric blue
    static let beastAccent = Color("BeastAccent")

    /// Surface color (adapts to light/dark)
    static let beastSurface = Color("BeastSurface")

    /// Elevated surface color
    static let beastSurfaceElevated = Color("BeastSurfaceElevated")
}

// MARK: - Semantic Colors

extension Color {
    /// Success state color
    static let beastSuccess = Color.green

    /// Warning state color
    static let beastWarning = Color.orange

    /// Error state color
    static let beastError = Color.red

    /// Info state color
    static let beastInfo = Color.blue
}

// MARK: - Workout Day Colors

extension Color {
    /// Color for Push day
    static let pushDay = Color.red.opacity(0.8)

    /// Color for Pull day
    static let pullDay = Color.blue.opacity(0.8)

    /// Color for Legs day
    static let legsDay = Color.green.opacity(0.8)

    /// Color for Core day
    static let coreDay = Color.orange.opacity(0.8)

    /// Color for Rest day
    static let restDay = Color.gray.opacity(0.6)

    /// Get color for a focus area
    static func forFocusArea(_ focus: String) -> Color {
        let lowercased = focus.lowercased()
        if lowercased.contains("push") {
            return .pushDay
        } else if lowercased.contains("pull") {
            return .pullDay
        } else if lowercased.contains("leg") {
            return .legsDay
        } else if lowercased.contains("core") {
            return .coreDay
        } else if lowercased.contains("rest") {
            return .restDay
        }
        return .beastPrimary
    }
}

// MARK: - RPE Colors

extension Color {
    /// Get color for RPE (Rate of Perceived Exertion) value
    static func forRPE(_ rpe: Int) -> Color {
        switch rpe {
        case 1...4:
            return .green
        case 5...6:
            return .yellow
        case 7...8:
            return .orange
        case 9...10:
            return .red
        default:
            return .gray
        }
    }
}

// MARK: - Gradient Definitions

extension LinearGradient {
    /// Primary brand gradient
    static let beastGradient = LinearGradient(
        colors: [.beastPrimary, .beastSecondary],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle background gradient
    static let beastBackgroundGradient = LinearGradient(
        colors: [
            .beastPrimary.opacity(0.1),
            .beastSecondary.opacity(0.1)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Success gradient
    static let successGradient = LinearGradient(
        colors: [.green, .green.opacity(0.8)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Glass border gradient
    static let glassBorder = LinearGradient(
        colors: [
            .white.opacity(0.3),
            .white.opacity(0.1),
            .clear
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Color Asset Definitions
/*
 Add these colors to Assets.xcassets:

 BeastPrimary:
   - Any: #65558F
   - Dark: #D0BCFE

 BeastSecondary:
   - Any: #FF6B35
   - Dark: #FF8A5B

 BeastAccent:
   - Any: #00D4FF
   - Dark: #4DE5FF

 BeastSurface:
   - Any: #FEF7FF
   - Dark: #141218

 BeastSurfaceElevated:
   - Any: #ECE6F0
   - Dark: #2B2930
 */

// MARK: - Fallback Colors (for when assets aren't available)

extension Color {
    /// Fallback primary color
    static var beastPrimaryFallback: Color {
        Color(red: 0.396, green: 0.333, blue: 0.561) // #65558F
    }

    /// Fallback secondary color
    static var beastSecondaryFallback: Color {
        Color(red: 1.0, green: 0.420, blue: 0.208) // #FF6B35
    }

    /// Fallback accent color
    static var beastAccentFallback: Color {
        Color(red: 0.0, green: 0.831, blue: 1.0) // #00D4FF
    }
}
