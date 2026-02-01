// WeeklyReviewView.swift
// BeastMode
// View for displaying AI-generated weekly workout reviews

import SwiftUI
import SwiftData

/// View for displaying the AI-powered weekly review
struct WeeklyReviewView: View {
    let weekId: String

    @State private var review: WeeklyReview?
    @State private var isLoading = false
    @State private var error: Error?

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var userId: UUID? {
        profiles.first?.id
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerView

                if isLoading {
                    LoadingReviewView()
                } else if let review {
                    reviewContent(review)
                } else if let error {
                    ErrorView(error: error) {
                        Task { await generateReview() }
                    }
                }
            }
            .padding(.vertical)
        }
        .task {
            await generateReview()
        }
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(L10n.AICoach.weeklyReview)
                    .font(.title.weight(.bold))
                Text(formatWeekId(weekId))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Mascot
            Image(systemName: "trophy.fill")
                .font(.system(size: 40))
                .foregroundStyle(.yellow.gradient)
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private func reviewContent(_ review: WeeklyReview) -> some View {
        // Stats row
        HStack(spacing: 12) {
            MiniStatCard(
                icon: "figure.strengthtraining.traditional",
                value: "\(review.workoutCount)",
                label: "Workouts"
            )

            MiniStatCard(
                icon: "scalemass.fill",
                value: formatVolume(review.totalVolume),
                label: "Volume"
            )

            MiniStatCard(
                icon: "trophy.fill",
                value: "\(review.prCount)",
                label: "PRs"
            )
        }
        .padding(.horizontal)

        // AI Review content
        VStack(alignment: .leading, spacing: 16) {
            MarkdownReviewView(content: review.content)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)

        // Generated timestamp
        Text("Generated \(review.generatedAt.formatted(.relative(presentation: .named)))")
            .font(.caption)
            .foregroundStyle(.secondary)

        // Regenerate button
        Button {
            Task { await generateReview() }
        } label: {
            Label("Regenerate", systemImage: "arrow.clockwise")
                .font(.subheadline)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    private func generateReview() async {
        guard let userId else { return }

        isLoading = true
        error = nil

        do {
            let service = WeeklyReviewService(modelContext: modelContext)
            review = try await service.generateWeeklyReview(for: weekId, userId: userId)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.0fK", volume / 1000)
        }
        return "\(Int(volume))"
    }

    private func formatWeekId(_ weekId: String) -> String {
        // Convert "2024-W5" to "Week 5, 2024"
        let parts = weekId.split(separator: "-W")
        guard parts.count == 2 else { return weekId }
        return "Week \(parts[1]), \(parts[0])"
    }
}

// MARK: - Loading View

struct LoadingReviewView: View {
    @State private var dots = ""
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            // Animated icon
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 80, height: 80)

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 36))
                    .foregroundStyle(.blue)
                    .symbolEffect(.pulse, options: .repeating)
            }

            Text(L10n.AICoach.analyzingWeek + dots)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(L10n.AICoach.mayTakeMoment)
                .font(.caption)
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .frame(height: 200)
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [self] _ in
                Task { @MainActor in
                    dots = dots.count >= 3 ? "" : dots + "."
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Mini Stat Card

struct MiniStatCard: View {
    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Color(hex: "FF6B35"))

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))

            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Markdown Review View

struct MarkdownReviewView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(parseContent(), id: \.self) { block in
                renderBlock(block)
            }
        }
    }

    private func parseContent() -> [String] {
        content.components(separatedBy: "\n\n")
            .flatMap { paragraph in
                // Split by headers
                paragraph.components(separatedBy: "\n").filter { !$0.isEmpty }
            }
    }

    @ViewBuilder
    private func renderBlock(_ block: String) -> some View {
        if block.starts(with: "**") && block.contains("**") {
            // Header with emoji
            let text = block.replacingOccurrences(of: "**", with: "")
            Text(text)
                .font(.headline)
                .padding(.top, 8)
        } else if block.starts(with: "- ") {
            // Bullet point
            HStack(alignment: .top, spacing: 8) {
                Text("•")
                    .foregroundStyle(.secondary)
                Text(String(block.dropFirst(2)))
            }
            .font(.body)
        } else if block.starts(with: "#") {
            // Markdown header
            let text = block.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
            Text(text)
                .font(.title3.weight(.semibold))
                .padding(.top, 8)
        } else {
            // Regular text
            Text(block)
                .font(.body)
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: Error
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(L10n.AICoach.couldntGenerate)
                .font(.headline)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again", action: onRetry)
                .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }
}

// MARK: - Weekly Review Card (Compact)

struct WeeklyReviewCard: View {
    let weekId: String
    @State private var showFullReview = false

    var body: some View {
        Button {
            showFullReview = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.AICoach.weeklyReview, systemImage: "brain.head.profile")
                        .font(.headline)

                    Text(L10n.AICoach.getInsights)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFullReview) {
            NavigationStack {
                WeeklyReviewView(weekId: weekId)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showFullReview = false
                            }
                        }
                    }
            }
            .presentationDetents([.large])
        }
    }
}

// MARK: - Preview

#Preview("Weekly Review") {
    WeeklyReviewView(weekId: "2024-W5")
}

#Preview("Weekly Review Card") {
    WeeklyReviewCard(weekId: "2024-W5")
        .padding()
}
