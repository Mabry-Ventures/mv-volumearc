// BodyWeightChartView.swift
// BeastMode
// Chart view for displaying body weight history from HealthKit

import SwiftUI
import Charts

/// Chart displaying body weight history with trend analysis
struct BodyWeightChartView: View {
    let entries: [BodyWeightEntry]
    let timeRange: ChartTimeRange

    @State private var selectedEntry: BodyWeightEntry?

    private var filteredEntries: [BodyWeightEntry] {
        let cutoff = timeRange.startDate
        return entries.filter { $0.date >= cutoff }
    }

    private var weightRange: ClosedRange<Double> {
        guard let min = filteredEntries.map(\.weight).min(),
              let max = filteredEntries.map(\.weight).max() else {
            return 150...200
        }
        let padding = max(5, (max - min) * 0.15)
        return (min - padding)...(max + padding)
    }

    private var trend: WeightTrend {
        guard filteredEntries.count >= 2 else { return .stable }
        let thirdCount = max(1, filteredEntries.count / 3)
        let first = Array(filteredEntries.prefix(thirdCount)).map(\.weight).average
        let last = Array(filteredEntries.suffix(thirdCount)).map(\.weight).average
        let diff = last - first

        if diff > 2 { return .gaining(diff) }
        if diff < -2 { return .losing(abs(diff)) }
        return .stable
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with trend
            headerView

            // Chart
            if filteredEntries.isEmpty {
                emptyStateView
            } else {
                chartView
            }

            // Selected entry detail
            if let selected = selectedEntry {
                selectedEntryView(selected)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
        )
    }

    // MARK: - Subviews

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(L10n.Health.bodyWeight)
                    .font(.headline)

                if let latest = filteredEntries.last {
                    Text("\(String(format: "%.1f", latest.weight)) lbs")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                }
            }

            Spacer()

            TrendBadge(trend: trend)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "scalemass")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text(L10n.Health.noWeightData)
                .font(.headline)

            Text(L10n.Health.connectToHealth)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
    }

    private var chartView: some View {
        Chart {
            ForEach(filteredEntries) { entry in
                // Area fill
                AreaMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weight)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .blue.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                // Line
                LineMark(
                    x: .value("Date", entry.date),
                    y: .value("Weight", entry.weight)
                )
                .foregroundStyle(Color.blue.gradient)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5))

                // Selected point
                if let selected = selectedEntry, selected.id == entry.id {
                    PointMark(
                        x: .value("Date", entry.date),
                        y: .value("Weight", entry.weight)
                    )
                    .foregroundStyle(.blue)
                    .symbolSize(100)
                }
            }
        }
        .chartYScale(domain: weightRange)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel(format: timeRange.dateFormat)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let weight = value.as(Double.self) {
                        Text("\(Int(weight))")
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x
                                if let date: Date = proxy.value(atX: x) {
                                    selectedEntry = filteredEntries.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    })
                                }
                            }
                            .onEnded { _ in
                                selectedEntry = nil
                            }
                    )
            }
        }
        .frame(height: 200)
    }

    private func selectedEntryView(_ entry: BodyWeightEntry) -> some View {
        HStack {
            Text(entry.date.formatted(.dateTime.month().day().year()))
            Spacer()
            Text("\(String(format: "%.1f", entry.weight)) lbs")
                .fontWeight(.semibold)
            Text("• \(entry.source)")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .transition(.opacity)
    }
}

// MARK: - Trend Badge

struct TrendBadge: View {
    let trend: WeightTrend

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: trend.icon)
            Text(trend.text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(trend.color.opacity(0.2), in: Capsule())
        .foregroundStyle(trend.color)
    }
}

// MARK: - Body Weight Card (Compact)

struct BodyWeightCardView: View {
    let latestWeight: BodyWeightEntry?
    let trend: WeightTrend
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Label(L10n.Health.bodyWeight, systemImage: "scalemass.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let latest = latestWeight {
                        Text("\(String(format: "%.1f", latest.weight)) lbs")
                            .font(.title2.weight(.bold))

                        Text(latest.date.formatted(.relative(presentation: .named)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(L10n.Common.noData)
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    TrendBadge(trend: trend)

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Body Weight Settings

struct BodyWeightSettingsView: View {
    @State private var isAuthorized = false
    @State private var isLoading = true
    @State private var error: Error?

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Apple Health", systemImage: "heart.fill")
                        .foregroundStyle(.red)

                    Spacer()

                    if isLoading {
                        ProgressView()
                    } else if isAuthorized {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    } else {
                        Button("Connect") {
                            Task { await requestAuthorization() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text(L10n.Health.dataSource)
            } footer: {
                Text(L10n.Health.dataSourceDescription)
            }

            if let error {
                Section {
                    Text(error.localizedDescription)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(L10n.Health.bodyWeight)
        .task {
            await checkAuthorization()
        }
    }

    private func checkAuthorization() async {
        isLoading = true
        let service = HealthKitService()
        isAuthorized = await service.isBodyWeightAuthorized
        isLoading = false
    }

    private func requestAuthorization() async {
        let service = HealthKitService()
        do {
            try await service.requestAuthorization()
            isAuthorized = true
        } catch {
            self.error = error
        }
    }
}

// MARK: - Preview

#Preview("Body Weight Chart") {
    BodyWeightChartView(
        entries: MockHealthKitService.generateMockBodyWeightEntries(
            count: 30,
            startingWeight: 180,
            trend: .gaining(5)
        ),
        timeRange: .oneMonth
    )
    .padding()
}

#Preview("Body Weight Card") {
    BodyWeightCardView(
        latestWeight: BodyWeightEntry(date: .now, weight: 182.5, source: "Apple Watch"),
        trend: .gaining(2.5),
        onTap: {}
    )
    .padding()
}
