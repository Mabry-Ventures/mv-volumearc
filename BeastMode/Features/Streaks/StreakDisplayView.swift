// StreakDisplayView.swift
// BeastMode
// Display component for workout streaks

import SwiftUI
import SwiftData

/// Compact streak display card for the home screen
struct StreakDisplayView: View {
    @Query private var streaks: [UserStreak]

    private var currentStreak: UserStreak? {
        streaks.first
    }

    var body: some View {
        GlassCard {
            HStack(spacing: 20) {
                // Streak flame
                StreakFlameView(
                    streak: currentStreak?.currentStreak ?? 0,
                    isActive: isStreakActive
                )

                Divider()
                    .frame(height: 60)
                    .accessibilityHidden(true)

                // Weekly progress
                WeeklyProgressView(
                    current: currentStreak?.currentWeekCount ?? 0,
                    goal: currentStreak?.weeklyGoal ?? 4
                )

                Spacer()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Streak summary")
    }

    private var isStreakActive: Bool {
        guard let lastDate = currentStreak?.lastWorkoutDate else { return false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let lastDay = calendar.startOfDay(for: lastDate)
        let daysDiff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? 0
        return daysDiff <= 1
    }
}

// MARK: - Streak Flame View

struct StreakFlameView: View {
    let streak: Int
    let isActive: Bool

    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isActive
                                ? [.orange, .red]
                                : [.gray.opacity(0.3), .gray.opacity(0.2)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 56, height: 56)

                // Flame icon
                Image(systemName: "flame.fill")
                    .font(.title)
                    .foregroundStyle(isActive ? .white : .gray)
                    .scaleEffect(isAnimating ? 1.1 : 1.0)
                    .animation(
                        isActive
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: isAnimating
                    )
            }

            Text("\(streak)")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(isActive ? .primary : .secondary)
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            Text(L10n.Streak.dayStreak)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            if isActive {
                isAnimating = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(streak) day streak")
        .accessibilityValue(isActive ? "Active" : "Inactive")
    }
}

// MARK: - Weekly Progress View

struct WeeklyProgressView: View {
    let current: Int
    let goal: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Streak.thisWeek)
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 6) {
                ForEach(0..<goal, id: \.self) { index in
                    Circle()
                        .fill(index < current ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                }
            }

            Text(L10n.Streak.workoutsOfGoal)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly progress")
        .accessibilityValue("\(current) of \(goal) workouts completed this week")
    }
}

// MARK: - Full Streak Stats View

struct StreakStatsView: View {
    @Query private var streaks: [UserStreak]

    private var streak: UserStreak? {
        streaks.first
    }

    var body: some View {
        VStack(spacing: 16) {
            // Main streak display
            HStack(spacing: 32) {
                StatBox(
                    title: "Current",
                    value: "\(streak?.currentStreak ?? 0)",
                    subtitle: "days",
                    icon: "flame.fill",
                    color: .orange
                )

                StatBox(
                    title: "Longest",
                    value: "\(streak?.longestStreak ?? 0)",
                    subtitle: "days",
                    icon: "trophy.fill",
                    color: .yellow
                )

                StatBox(
                    title: "Total",
                    value: "\(streak?.totalWorkouts ?? 0)",
                    subtitle: "workouts",
                    icon: "figure.strengthtraining.traditional",
                    color: .blue
                )
            }

            // Volume stat
            if let volume = streak?.totalVolumeLifted, volume > 0 {
                HStack {
                    Image(systemName: "scalemass.fill")
                        .foregroundStyle(.purple)

                    Text("Total Volume Lifted:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(formatVolume(volume))
                        .font(.subheadline.weight(.semibold))

                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.purple.opacity(0.1))
                )
            }
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM lbs", volume / 1_000_000)
        } else if volume >= 1000 {
            return String(format: "%.1fK lbs", volume / 1000)
        } else {
            return "\(Int(volume)) lbs"
        }
    }
}

// MARK: - Stat Box

struct StatBox: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            VStack(spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(color.opacity(0.1))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value) \(subtitle)")
    }
}

// MARK: - Glass Card Container

struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )
            )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        StreakDisplayView()
        StreakStatsView()
    }
    .padding()
    .background(Color.black)
}
