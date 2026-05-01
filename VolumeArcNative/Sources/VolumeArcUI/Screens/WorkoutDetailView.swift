#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// Detail view pushed from TodayView's next workout card.
/// Uses `.navigationTransition(.zoom(...))` to hero-animate from the card.
struct WorkoutDetailView: View {
    let title: String
    let exerciseName: String
    let target: String
    let cue: String
    let reason: String
    let heroNamespace: Namespace.ID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VA.Space.lg) {
                header
                targetCard
                cueCard
                reasonCard
                Spacer(minLength: VA.Space.xxl)
            }
            .padding(VA.Space.lg)
        }
        .background(VA.Colors.surfaceGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(String(localized: "FOCUS", comment: "Workout detail header label for the main lift"))
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.5)
            Text(exerciseName)
                .font(VA.Typography.display)
                .foregroundStyle(VA.Colors.textPrimary)
        }
    }

    private var targetCard: some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "TARGET", comment: "Workout detail target card label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(0.5)
                Text(target)
                    .font(VA.Typography.title2)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    private var cueCard: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                HStack(spacing: VA.Space.xs) {
                    Image(systemName: "quote.opening")
                        .foregroundStyle(VA.Colors.primary)
                    Text(String(localized: "CUE", comment: "Workout detail coach cue card label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                }
                Text(cue)
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .italic()
            }
        }
    }

    private var reasonCard: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "WHY THIS PROGRESSION", comment: "Workout detail reasoning card label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.5)
                Text(reason)
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textPrimary)
            }
        }
    }
}
#endif
