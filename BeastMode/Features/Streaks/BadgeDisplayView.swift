// BadgeDisplayView.swift
// BeastMode
// Display components for the badge system

import SwiftUI
import SwiftData

/// Grid display of all badges
struct BadgeCollectionView: View {
    @Query private var streaks: [UserStreak]

    private var earnedBadgeIds: Set<String> {
        Set(streaks.first?.earnedBadges ?? [])
    }

    private var earnedDates: [String: Date] {
        streaks.first?.badgeEarnedDates ?? [:]
    }

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Badge.allCases) { badge in
                    BadgeCell(
                        badge: badge,
                        isEarned: earnedBadgeIds.contains(badge.rawValue),
                        earnedDate: earnedDates[badge.rawValue]
                    )
                }
            }
            .padding()
        }
        .navigationTitle("Badges")
    }
}

// MARK: - Badge Cell

struct BadgeCell: View {
    let badge: Badge
    let isEarned: Bool
    let earnedDate: Date?

    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    // Background
                    Circle()
                        .fill(
                            isEarned
                                ? badge.color.gradient
                                : Color.gray.opacity(0.2).gradient
                        )
                        .frame(width: 64, height: 64)

                    // Icon
                    Image(systemName: badge.icon)
                        .font(.title2)
                        .foregroundStyle(isEarned ? .white : .gray)

                    // Lock overlay if not earned
                    if !isEarned {
                        Circle()
                            .fill(.black.opacity(0.3))
                            .frame(width: 64, height: 64)

                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }

                Text(badge.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isEarned ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showDetail) {
            BadgeDetailView(badge: badge, isEarned: isEarned, earnedDate: earnedDate)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Badge Detail View

struct BadgeDetailView: View {
    let badge: Badge
    let isEarned: Bool
    let earnedDate: Date?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Badge icon
            ZStack {
                // Glow effect for earned badges
                if isEarned {
                    Circle()
                        .fill(badge.color.opacity(0.3))
                        .frame(width: 140, height: 140)
                        .blur(radius: 20)
                }

                Circle()
                    .fill(
                        isEarned
                            ? badge.color.gradient
                            : Color.gray.opacity(0.2).gradient
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: badge.icon)
                    .font(.system(size: 44))
                    .foregroundStyle(isEarned ? .white : .gray)
            }

            // Badge name
            Text(badge.name)
                .font(.title.weight(.bold))

            // Description
            Text(badge.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Earned date or progress
            if isEarned, let date = earnedDate {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Earned \(date.formatted(.dateTime.month().day().year()))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else if let threshold = badge.threshold {
                Text("Requirement: \(threshold)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .padding(.top)
    }
}

// MARK: - Badge Earned Popup

struct BadgeEarnedPopup: View {
    let badge: Badge
    let onDismiss: () -> Void

    @State private var showContent = false
    @State private var confettiTrigger = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                Text("NEW BADGE!")
                    .font(.caption.weight(.black))
                    .foregroundStyle(.yellow)
                    .tracking(4)

                ZStack {
                    // Animated glow
                    Circle()
                        .fill(badge.color.opacity(0.4))
                        .frame(width: 130, height: 130)
                        .blur(radius: 25)

                    Circle()
                        .fill(badge.color.gradient)
                        .frame(width: 100, height: 100)

                    Image(systemName: badge.icon)
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }

                Text(badge.name)
                    .font(.title.weight(.bold))
                    .foregroundStyle(.white)

                Text(badge.description)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)

                Button {
                    onDismiss()
                } label: {
                    Text("Awesome!")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 12)
                        .background(
                            Capsule()
                                .fill(.white)
                        )
                }
                .padding(.top)
            }
            .padding(32)
            .scaleEffect(showContent ? 1 : 0.5)
            .opacity(showContent ? 1 : 0)
        }
        .onAppear {
            // Haptic
            #if os(iOS)
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            #endif

            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                showContent = true
            }
        }
    }
}

// MARK: - Recent Badges View

struct RecentBadgesView: View {
    @Query private var streaks: [UserStreak]

    private var recentBadges: [(Badge, Date)] {
        guard let streak = streaks.first else { return [] }

        return streak.badgeEarnedDates
            .compactMap { id, date -> (Badge, Date)? in
                guard let badge = Badge(rawValue: id) else { return nil }
                return (badge, date)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(5)
            .map { ($0.0, $0.1) }
    }

    var body: some View {
        if !recentBadges.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Recent Badges")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(recentBadges, id: \.0.id) { badge, date in
                            VStack(spacing: 6) {
                                Circle()
                                    .fill(badge.color.gradient)
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Image(systemName: badge.icon)
                                            .foregroundStyle(.white)
                                    )

                                Text(badge.name)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(width: 70)
                        }
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - Previews

#Preview("Badge Collection") {
    NavigationStack {
        BadgeCollectionView()
    }
}

#Preview("Badge Detail") {
    BadgeDetailView(badge: .weekWarrior, isEarned: true, earnedDate: .now)
}

#Preview("Badge Earned") {
    BadgeEarnedPopup(badge: .monthlyBeast, onDismiss: {})
}
