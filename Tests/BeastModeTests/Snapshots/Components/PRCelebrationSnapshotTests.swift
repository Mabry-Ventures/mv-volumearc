// PRCelebrationSnapshotTests.swift
// BeastModeTests
// Snapshot tests for PR celebration components

import Testing
import SwiftUI
@testable import BeastMode

@Suite("PR Celebration Snapshots")
struct PRCelebrationSnapshotTests {

    // MARK: - PR Badge Snapshots

    @Test("PR badge first time - light mode")
    @MainActor
    func prBadgeFirstTimeLight() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            PRBadgeView(prType: .firstTime, exerciseName: "Bench Press")
        }

        assertSnapshot(matching: view, named: "pr_badge_first_time_light")
    }

    @Test("PR badge first time - dark mode")
    @MainActor
    func prBadgeFirstTimeDark() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .dark
        ) {
            PRBadgeView(prType: .firstTime, exerciseName: "Bench Press")
        }

        assertSnapshot(matching: view, named: "pr_badge_first_time_dark")
    }

    @Test("PR badge E1RM improvement - light mode")
    @MainActor
    func prBadgeE1RMLight() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            PRBadgeView(prType: .estimatedMax(improvement: 5.2), exerciseName: "Squats")
        }

        assertSnapshot(matching: view, named: "pr_badge_e1rm_light")
    }

    @Test("PR badge heaviest weight - light mode")
    @MainActor
    func prBadgeHeaviestWeightLight() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            PRBadgeView(prType: .heaviestWeight(weight: 315), exerciseName: "Deadlift")
        }

        assertSnapshot(matching: view, named: "pr_badge_heaviest_light")
    }

    @Test("PR badge rep record - light mode")
    @MainActor
    func prBadgeRepRecordLight() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            PRBadgeView(prType: .repRecord(atWeight: 225, reps: 12), exerciseName: "Bench Press")
        }

        assertSnapshot(matching: view, named: "pr_badge_rep_record_light")
    }

    // MARK: - PR Celebration Full Screen

    @Test("PR celebration modal - light mode")
    @MainActor
    func prCelebrationModalLight() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light
        ) {
            PRCelebrationView(
                exerciseName: "Barbell Bench Press",
                weight: 225,
                reps: 5,
                prType: .estimatedMax(improvement: 6.3),
                onDismiss: {}
            )
        }

        assertSnapshot(matching: view, named: "pr_celebration_modal_light")
    }

    @Test("PR celebration modal - dark mode")
    @MainActor
    func prCelebrationModalDark() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .dark
        ) {
            PRCelebrationView(
                exerciseName: "Barbell Bench Press",
                weight: 225,
                reps: 5,
                prType: .estimatedMax(improvement: 6.3),
                onDismiss: {}
            )
        }

        assertSnapshot(matching: view, named: "pr_celebration_modal_dark")
    }

    // MARK: - Accessibility Snapshots

    @Test("PR badge with accessibility text size")
    @MainActor
    func prBadgeAccessibility() {
        let view = SnapshotWrapper(
            device: .iPhone15Pro,
            colorScheme: .light,
            dynamicTypeSize: .accessibility1
        ) {
            PRBadgeView(prType: .firstTime, exerciseName: "Bench Press")
        }

        assertSnapshot(matching: view, named: "pr_badge_accessibility")
    }

    // MARK: - Device Variants

    @Test("PR celebration on iPhone SE")
    @MainActor
    func prCelebrationiPhoneSE() {
        let view = SnapshotWrapper(
            device: .iPhoneSE,
            colorScheme: .light
        ) {
            PRCelebrationView(
                exerciseName: "Squats",
                weight: 315,
                reps: 3,
                prType: .heaviestWeight(weight: 315),
                onDismiss: {}
            )
        }

        assertSnapshot(matching: view, named: "pr_celebration_iphone_se")
    }
}

// MARK: - Stub Views for Snapshot Testing

/// Stub PR Badge View for snapshot testing
struct PRBadgeView: View {
    let prType: PRType
    let exerciseName: String

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(badgeColor.opacity(0.2))
                    .frame(width: 44, height: 44)

                Image(systemName: badgeIcon)
                    .font(.title2)
                    .foregroundStyle(badgeColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(badgeTitle)
                    .font(.headline)
                    .foregroundStyle(badgeColor)

                Text(exerciseName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let detail = badgeDetail {
                Text(detail)
                    .font(.title3.bold())
                    .foregroundStyle(badgeColor)
            }
        }
        .padding()
        .background(badgeColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var badgeColor: Color {
        switch prType {
        case .firstTime: return .blue
        case .estimatedMax: return .orange
        case .heaviestWeight: return .purple
        case .repRecord: return .green
        }
    }

    private var badgeIcon: String {
        switch prType {
        case .firstTime: return "star.fill"
        case .estimatedMax: return "chart.line.uptrend.xyaxis"
        case .heaviestWeight: return "scalemass.fill"
        case .repRecord: return "repeat"
        }
    }

    private var badgeTitle: String {
        switch prType {
        case .firstTime: return "First Time!"
        case .estimatedMax: return "New E1RM!"
        case .heaviestWeight: return "Heaviest Weight!"
        case .repRecord: return "Rep Record!"
        }
    }

    private var badgeDetail: String? {
        switch prType {
        case .firstTime: return nil
        case .estimatedMax(let improvement): return "+\(String(format: "%.1f", improvement))%"
        case .heaviestWeight(let weight): return "\(Int(weight)) lbs"
        case .repRecord(_, let reps): return "\(reps) reps"
        }
    }
}

/// Stub PR Celebration View for snapshot testing
struct PRCelebrationView: View {
    let exerciseName: String
    let weight: Double
    let reps: Int
    let prType: PRType
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Trophy icon
            ZStack {
                Circle()
                    .fill(.yellow.opacity(0.2))
                    .frame(width: 120, height: 120)

                Image(systemName: "trophy.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.yellow)
            }

            // Title
            Text("Personal Record!")
                .font(.largeTitle.bold())

            // Exercise info
            VStack(spacing: 8) {
                Text(exerciseName)
                    .font(.title2)

                Text("\(Int(weight)) lbs × \(reps) reps")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // PR type badge
            PRBadgeView(prType: prType, exerciseName: exerciseName)
                .padding(.horizontal)

            Spacer()

            // Dismiss button
            Button("Continue") {
                onDismiss()
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.blue)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .padding()
    }
}
