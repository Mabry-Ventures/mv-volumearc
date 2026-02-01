// AnalyticsDashboardView.swift
// BeastMode
// Main dashboard for viewing progressive overload analytics

import SwiftUI
import Charts
import os

/// Main analytics dashboard showing progress across all exercises
struct AnalyticsDashboardView: View {
    @State private var overview: AnalyticsOverview?
    @State private var selectedExercise: ExerciseAnalytics?
    @State private var timeRange: ChartTimeRange = .threeMonths
    @State private var isLoading = true
    @State private var bodyWeightEntries: [BodyWeightEntry] = []

    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    private var userId: UUID? {
        profiles.first?.id
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    // Time range picker
                    timeRangePicker

                    if isLoading {
                        loadingView
                    } else if let overview {
                        // Body weight section
                        if !bodyWeightEntries.isEmpty {
                            BodyWeightChartView(
                                entries: bodyWeightEntries,
                                timeRange: timeRange
                            )
                            .padding(.horizontal)
                        }

                        // Summary cards
                        SummaryCardsView(overview: overview)

                        // Progress breakdown
                        ProgressBreakdownView(overview: overview)
                            .padding(.horizontal)

                        // Exercise trends list
                        ExerciseTrendsListView(
                            exercises: overview.exercises,
                            onSelect: { selectedExercise = $0 }
                        )
                    } else {
                        emptyStateView
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle(L10n.Analytics.title)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        BodyWeightSettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(item: $selectedExercise) { exercise in
                ExerciseDetailAnalyticsView(analytics: exercise)
            }
        }
        .task(id: timeRange) {
            await loadAnalytics()
        }
    }

    // MARK: - Subviews

    private var timeRangePicker: some View {
        Picker("Time Range", selection: $timeRange) {
            ForEach(ChartTimeRange.allCases) { range in
                Text(range.rawValue).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(L10n.Analytics.analyzingProgress)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label(L10n.Analytics.noDataYet, systemImage: "chart.line.uptrend.xyaxis")
        } description: {
            Text(L10n.Analytics.completeWorkoutsToSee)
        }
    }

    // MARK: - Data Loading

    private func loadAnalytics() async {
        guard let userId else { return }

        isLoading = true

        // Load analytics and body weight concurrently for better performance
        async let analyticsTask: AnalyticsOverview? = {
            let analyticsService = AnalyticsService(modelContext: modelContext)
            return try? await analyticsService.generateOverview(for: userId, timeRange: timeRange)
        }()

        async let bodyWeightTask: [BodyWeightEntry] = loadBodyWeightDataAsync()

        // Wait for both to complete
        let (analyticsResult, bodyWeightResult) = await (analyticsTask, bodyWeightTask)

        overview = analyticsResult
        bodyWeightEntries = bodyWeightResult

        isLoading = false
    }

    private func loadBodyWeightDataAsync() async -> [BodyWeightEntry] {
        let healthKitService = HealthKitService()

        // Check if HealthKit is available
        guard await healthKitService.isHealthKitAvailable else {
            Logger.healthKit.info("HealthKit not available on this device")
            return []
        }

        // Request authorization if needed
        do {
            try await healthKitService.requestAuthorization()

            // Only fetch if we have authorization
            if await healthKitService.isBodyWeightAuthorized {
                let entries = (try? await healthKitService.fetchBodyWeightHistory(from: timeRange.startDate)) ?? []
                Logger.healthKit.debug("Loaded \(entries.count) body weight entries")
                return entries
            } else {
                Logger.healthKit.info("Body weight access not authorized")
                return []
            }
        } catch {
            Logger.healthKit.error("Failed to authorize HealthKit: \(error.localizedDescription)")
            return []
        }
    }

}

// MARK: - Summary Cards

struct SummaryCardsView: View {
    let overview: AnalyticsOverview

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                SummaryCard(
                    title: L10n.Analytics.workouts,
                    value: "\(overview.totalWorkouts)",
                    subtitle: L10n.Analytics.weekAvg,
                    icon: "figure.strengthtraining.traditional",
                    color: .blue
                )

                SummaryCard(
                    title: L10n.Analytics.totalVolume,
                    value: formatVolume(overview.totalVolume),
                    subtitle: L10n.Analytics.weightTimesReps,
                    icon: "scalemass.fill",
                    color: .purple
                )

                SummaryCard(
                    title: L10n.Analytics.progressing,
                    value: "\(overview.progressingExercises.count)",
                    subtitle: L10n.Analytics.exercisesImproving,
                    icon: "arrow.up.right",
                    color: .green
                )

                SummaryCard(
                    title: L10n.Analytics.plateaus,
                    value: "\(overview.plateauExercises.count)",
                    subtitle: L10n.Analytics.needAttention,
                    icon: "arrow.right",
                    color: .orange
                )
            }
            .padding(.horizontal)
        }
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.0fK", volume / 1_000)
        }
        return "\(Int(volume))"
    }
}

struct SummaryCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility1)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(value), \(subtitle)")
    }
}

// MARK: - Progress Breakdown

struct ProgressBreakdownView: View {
    let overview: AnalyticsOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Analytics.progressBreakdown)
                .font(.headline)

            // Progress bar
            GeometryReader { geo in
                HStack(spacing: 2) {
                    if overview.progressingExercises.count > 0 {
                        Rectangle()
                            .fill(Color.green)
                            .frame(width: barWidth(for: overview.progressingExercises.count, in: geo.size.width))
                    }

                    if overview.plateauExercises.count > 0 {
                        Rectangle()
                            .fill(Color.orange)
                            .frame(width: barWidth(for: overview.plateauExercises.count, in: geo.size.width))
                    }

                    if overview.decliningExercises.count > 0 {
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: barWidth(for: overview.decliningExercises.count, in: geo.size.width))
                    }

                    if overview.insufficientDataExercises.count > 0 {
                        Rectangle()
                            .fill(Color.gray.opacity(0.5))
                            .frame(width: barWidth(for: overview.insufficientDataExercises.count, in: geo.size.width))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 12)

            // Legend
            HStack(spacing: 16) {
                LegendItem(color: .green, label: L10n.Analytics.progressing, count: overview.progressingExercises.count)
                LegendItem(color: .orange, label: L10n.Analytics.plateau, count: overview.plateauExercises.count)
                LegendItem(color: .red, label: L10n.Analytics.declining, count: overview.decliningExercises.count)
            }
            .font(.caption)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    private func barWidth(for count: Int, in totalWidth: CGFloat) -> CGFloat {
        let total = overview.exercises.count
        guard total > 0 else { return 0 }
        return (CGFloat(count) / CGFloat(total)) * totalWidth
    }
}

struct LegendItem: View {
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text("\(label) (\(count))")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) exercises \(label.lowercased())")
    }
}

// MARK: - Exercise Trends List

struct ExerciseTrendsListView: View {
    let exercises: [ExerciseAnalytics]
    let onSelect: (ExerciseAnalytics) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Analytics.exerciseTrends)
                .font(.headline)
                .padding(.horizontal)

            if exercises.isEmpty {
                Text(L10n.Analytics.noExercisesTracked)
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                ForEach(exercises) { exercise in
                    Button {
                        onSelect(exercise)
                    } label: {
                        ExerciseTrendRow(analytics: exercise)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
    }
}

struct ExerciseTrendRow: View {
    let analytics: ExerciseAnalytics

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(analytics.exerciseName)
                    .font(.headline)

                if let e1rm = analytics.estimatedOneRepMax {
                    Text(L10n.Analytics.e1rm(Int(e1rm)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Mini sparkline
            if analytics.dataPoints.count >= 2 {
                MiniSparkline(dataPoints: analytics.dataPoints)
                    .frame(width: 60, height: 30)
                    .accessibilityHidden(true)
            }

            // Trend badge
            Image(systemName: analytics.trend.icon)
                .foregroundStyle(analytics.trend.color)
                .font(.title3)
                .accessibilityHidden(true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exerciseAccessibilityLabel)
        .accessibilityHint("Double tap to view detailed analytics")
    }

    private var exerciseAccessibilityLabel: String {
        var label = analytics.exerciseName
        if let e1rm = analytics.estimatedOneRepMax {
            label += ", estimated one rep max \(Int(e1rm)) pounds"
        }
        label += ", trend: \(analytics.trend.accessibilityDescription)"
        return label
    }
}

struct MiniSparkline: View {
    let dataPoints: [AnalyticsDataPoint]

    var body: some View {
        Chart {
            ForEach(dataPoints.suffix(10)) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("E1RM", point.estimatedOneRepMax)
                )
                .foregroundStyle(Color(hex: "FF6B35").gradient)
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

// MARK: - Preview

#Preview {
    AnalyticsDashboardView()
}
