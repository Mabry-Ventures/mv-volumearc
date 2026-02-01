// ExerciseDetailAnalyticsView.swift
// BeastMode
// Detailed analytics view for a single exercise

import SwiftUI
import Charts

/// Detailed analytics sheet for a single exercise
struct ExerciseDetailAnalyticsView: View {
    let analytics: ExerciseAnalytics

    @State private var chartType: ChartType = .oneRepMax
    @State private var suggestion: WeightSuggestion?
    @State private var isLoadingSuggestion = false

    enum ChartType: String, CaseIterable {
        case oneRepMax = "Est. 1RM"
        case volume = "Volume"
        case weight = "Weight"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header stats
                    headerStatsView

                    // Trend indicator
                    trendIndicatorView

                    // Chart type picker
                    chartTypePicker

                    // Main chart
                    mainChartView

                    // AI Suggestion
                    WeightSuggestionCard(
                        exercise: analytics,
                        suggestion: $suggestion,
                        isLoading: $isLoadingSuggestion
                    )
                    .padding(.horizontal)

                    // Volume trend
                    VolumeTrendCard(trend: analytics.volumeTrend)
                        .padding(.horizontal)

                    // Recent sets
                    RecentSetsSection(dataPoints: analytics.dataPoints)
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle(analytics.exerciseName)
            .navigationBarTitleDisplayMode(.large)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Subviews

    private var headerStatsView: some View {
        HStack(spacing: 12) {
            StatBox(
                title: "Best E1RM",
                value: "\(Int(analytics.estimatedOneRepMax ?? 0))",
                unit: "lbs"
            )

            StatBox(
                title: "Total Sets",
                value: "\(analytics.totalSets)",
                unit: "sets"
            )

            StatBox(
                title: "Frequency",
                value: String(format: "%.1f", analytics.frequencyPerWeek),
                unit: "/week"
            )
        }
        .padding(.horizontal)
    }

    private var trendIndicatorView: some View {
        HStack {
            Image(systemName: analytics.trend.icon)
                .font(.title)
                .foregroundStyle(analytics.trend.color)

            VStack(alignment: .leading) {
                Text(trendTitle)
                    .font(.headline)
                Text(analytics.trend.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .padding(.horizontal)
    }

    private var chartTypePicker: some View {
        Picker("Chart", selection: $chartType) {
            ForEach(ChartType.allCases, id: \.self) { type in
                Text(type.rawValue).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
    }

    private var mainChartView: some View {
        ExerciseProgressChart(
            dataPoints: analytics.dataPoints,
            chartType: chartType
        )
        .frame(height: 250)
        .padding(.horizontal)
    }

    private var trendTitle: String {
        switch analytics.trend {
        case .increasing: return "You're Getting Stronger! 💪"
        case .plateau: return "Time to Mix It Up"
        case .decreasing: return "Let's Turn This Around"
        case .insufficient: return "Keep Logging"
        }
    }
}

// MARK: - Stat Box

struct AnalyticsStatBox: View {
    let title: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Exercise Progress Chart

struct ExerciseProgressChart: View {
    let dataPoints: [AnalyticsDataPoint]
    let chartType: ExerciseDetailAnalyticsView.ChartType

    @State private var selectedPoint: AnalyticsDataPoint?

    var body: some View {
        Chart {
            ForEach(dataPoints) { point in
                // Line
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", yValue(for: point))
                )
                .foregroundStyle(Color(hex: "FF6B35").gradient)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                // Points
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Value", yValue(for: point))
                )
                .foregroundStyle(Color(hex: "FF6B35"))
                .symbolSize(selectedPoint?.id == point.id ? 100 : 30)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedPoint = dataPoints.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    })
                                }
                            }
                            .onEnded { _ in
                                selectedPoint = nil
                            }
                    )
            }
        }
        .overlay(alignment: .top) {
            if let point = selectedPoint {
                VStack(spacing: 2) {
                    Text(point.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.caption2)
                    Text("\(Int(yValue(for: point))) \(unitLabel)")
                        .font(.caption.weight(.bold))
                }
                .padding(6)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func yValue(for point: AnalyticsDataPoint) -> Double {
        switch chartType {
        case .oneRepMax: return point.estimatedOneRepMax
        case .volume: return point.volume
        case .weight: return point.weight
        }
    }

    private var unitLabel: String {
        switch chartType {
        case .oneRepMax: return "lbs"
        case .volume: return "lbs"
        case .weight: return "lbs"
        }
    }
}

// MARK: - Volume Trend Card

struct VolumeTrendCard: View {
    let trend: VolumeTrend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Analytics.weeklyVolume)
                .font(.headline)

            HStack(alignment: .bottom, spacing: 16) {
                VStack(alignment: .leading) {
                    Text(L10n.Streak.thisWeek)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(trend.currentWeekVolume)) lbs")
                        .font(.title2.weight(.bold))
                }

                VStack(alignment: .leading) {
                    Text("vs Last Week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        Image(systemName: trend.isProgressing ? "arrow.up" : "arrow.down")
                        Text(trend.changeDescription)
                    }
                    .font(.headline)
                    .foregroundStyle(trend.isProgressing ? .green : .orange)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(L10n.Analytics.average)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(trend.averageVolume)) lbs")
                        .font(.subheadline)
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

// MARK: - Recent Sets Section

struct RecentSetsSection: View {
    let dataPoints: [AnalyticsDataPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.Analytics.recentSets)
                .font(.headline)

            ForEach(Array(dataPoints.suffix(5).reversed().enumerated()), id: \.element.id) { index, point in
                HStack {
                    Text(point.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    Text("\(Int(point.weight)) × \(point.reps)")
                        .font(.headline)

                    Spacer()

                    Text(L10n.Analytics.e1rm(Int(point.estimatedOneRepMax)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)

                if index < 4 {
                    Divider()
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

// MARK: - Weight Suggestion Card

struct WeightSuggestionCard: View {
    let exercise: ExerciseAnalytics
    @Binding var suggestion: WeightSuggestion?
    @Binding var isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                Text(L10n.AICoach.aiSuggestion)
                    .font(.headline)
                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if let suggestion {
                suggestionContent(suggestion)
            } else {
                Button {
                    Task { await loadSuggestion() }
                } label: {
                    Label("Get AI Suggestion", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }

    @ViewBuilder
    private func suggestionContent(_ suggestion: WeightSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Suggested weight/reps
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text(L10n.AICoach.nextSession)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(Int(suggestion.suggestedWeight)) lbs × \(suggestion.suggestedReps)")
                        .font(.title2.weight(.bold))
                }

                Spacer()

                // Confidence badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(suggestion.confidence.color)
                        .frame(width: 8, height: 8)
                    Text(suggestion.confidence.rawValue.capitalized)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(suggestion.confidence.color.opacity(0.2), in: Capsule())
            }

            // Reasoning
            Text(suggestion.reasoning)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Alternative approach if plateau
            if let alternative = suggestion.alternativeApproach {
                Divider()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "lightbulb.fill")
                        .foregroundStyle(.yellow)
                    Text(alternative)
                        .font(.subheadline)
                }
            }
        }
    }

    private func loadSuggestion() async {
        isLoading = true

        // Simulate AI suggestion (in real app, call AICoachService)
        try? await Task.sleep(for: .seconds(1))

        let lastWeight = exercise.dataPoints.last?.weight ?? 135
        let lastReps = exercise.dataPoints.last?.reps ?? 8

        // Simple progression logic
        var suggestedWeight = lastWeight
        var suggestedReps = lastReps

        switch exercise.trend {
        case .increasing:
            // If progressing well and hitting 8+ reps, increase weight
            if lastReps >= 8 {
                suggestedWeight = lastWeight * 1.05  // 5% increase
                suggestedReps = 6
            } else {
                suggestedReps = min(lastReps + 1, 12)
            }
        case .plateau:
            // Suggest rep change or deload
            suggestedWeight = lastWeight
            suggestedReps = lastReps >= 10 ? 6 : lastReps + 2
        case .decreasing:
            // Reduce weight slightly, focus on form
            suggestedWeight = lastWeight * 0.95
            suggestedReps = 8
        case .insufficient:
            suggestedWeight = lastWeight
            suggestedReps = lastReps
        }

        suggestion = WeightSuggestion(
            exerciseName: exercise.exerciseName,
            suggestedWeight: suggestedWeight,
            suggestedReps: suggestedReps,
            confidence: exercise.dataPoints.count >= 10 ? .high : (exercise.dataPoints.count >= 5 ? .medium : .low),
            reasoning: generateReasoning(for: exercise.trend),
            alternativeApproach: exercise.trend == .plateau(weeks: 0) ? "Try drop sets or pause reps to break through the plateau" : nil
        )

        isLoading = false
    }

    private func generateReasoning(for trend: ProgressTrend) -> String {
        switch trend {
        case .increasing:
            return "You've been consistently progressing. Time to add some weight and chase new PRs!"
        case .plateau:
            return "You've been at similar weights for a while. Consider changing rep ranges or adding intensity techniques."
        case .decreasing:
            return "Recent performance has dipped slightly. Focus on recovery and form before pushing heavier."
        case .insufficient:
            return "Keep logging more sets to get personalized recommendations."
        }
    }
}

// MARK: - Preview

#Preview {
    let mockDataPoints = (0..<20).map { i in
        AnalyticsDataPoint(
            date: Calendar.current.date(byAdding: .day, value: -20 + i, to: .now)!,
            weight: 185 + Double(i) * 2,
            reps: 8 - (i % 3),
            estimatedOneRepMax: 220 + Double(i) * 2.5,
            volume: (185 + Double(i) * 2) * Double(8 - (i % 3)),
            weekId: "2024-W\(4 + i / 7)"
        )
    }

    let mockAnalytics = ExerciseAnalytics(
        exerciseName: "Barbell Bench Press",
        dataPoints: mockDataPoints,
        trend: .increasing(percentage: 8.5),
        estimatedOneRepMax: 245,
        volumeTrend: VolumeTrend(
            currentWeekVolume: 5400,
            previousWeekVolume: 4800,
            averageVolume: 5000
        ),
        frequencyPerWeek: 2.3,
        lastPerformed: .now,
        totalSets: 45,
        totalReps: 320,
        totalVolume: 62000
    )

    return ExerciseDetailAnalyticsView(analytics: mockAnalytics)
}
