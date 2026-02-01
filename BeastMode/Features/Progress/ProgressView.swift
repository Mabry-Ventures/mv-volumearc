import SwiftUI
import SwiftData
import Charts

/// View for tracking progress and personal records
struct ProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PersonalRecord.date, order: .reverse) private var records: [PersonalRecord]

    @State private var selectedExercise: String?
    @State private var chartTimeRange: ChartTimeRange = .threeMonths
    @State private var showingAISuggestions = false

    private var exercises: [String] {
        Array(Set(records.map(\.exerciseName))).sorted()
    }

    private var filteredRecords: [PersonalRecord] {
        guard let exercise = selectedExercise else { return records }
        return records.filter { $0.exerciseName == exercise }
    }

    private var chartRecords: [PersonalRecord] {
        let cutoffDate = chartTimeRange.cutoffDate
        return filteredRecords.filter { $0.date >= cutoffDate }
    }

    var body: some View {
        NavigationStack {
            List {
                // Chart Section
                if !chartRecords.isEmpty {
                    Section {
                        PRProgressChart(records: chartRecords)
                            .frame(height: 200)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                    }

                    // Time range picker
                    Section {
                        Picker("Time Range", selection: $chartTimeRange) {
                            ForEach(ChartTimeRange.allCases) { range in
                                Text(range.displayName).tag(range)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                    }
                }

                // AI Suggestions
                Section {
                    Button {
                        showingAISuggestions = true
                    } label: {
                        Label("Suggest Next Weights", systemImage: "sparkles")
                            .foregroundStyle(.beastPrimary)
                    }
                }

                // PR List
                Section("Personal Records") {
                    if filteredRecords.isEmpty {
                        ContentUnavailableView(
                            "No Records Yet",
                            systemImage: "star",
                            description: Text("Complete workouts to start tracking PRs")
                        )
                    } else {
                        ForEach(filteredRecords) { record in
                            PRRowView(record: record)
                        }
                        .onDelete(perform: deleteRecords)
                    }
                }
            }
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    exerciseFilterMenu
                }
            }
            .sheet(isPresented: $showingAISuggestions) {
                AISuggestionsSheet(records: filteredRecords)
            }
        }
    }

    private var exerciseFilterMenu: some View {
        Menu {
            Button {
                selectedExercise = nil
            } label: {
                HStack {
                    Text("All Exercises")
                    if selectedExercise == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Divider()

            ForEach(exercises, id: \.self) { exercise in
                Button {
                    selectedExercise = exercise
                } label: {
                    HStack {
                        Text(exercise)
                        if selectedExercise == exercise {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedExercise ?? "All")
                    .lineLimit(1)
                Image(systemName: "chevron.down")
            }
            .font(.subheadline)
        }
    }

    private func deleteRecords(at offsets: IndexSet) {
        for index in offsets {
            let record = filteredRecords[index]
            try? DataService.shared.deletePR(record)
        }
    }
}

// MARK: - Chart Time Range

enum ChartTimeRange: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"
    case allTime = "All"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var cutoffDate: Date {
        let calendar = Calendar.current
        switch self {
        case .oneMonth:
            return calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        case .threeMonths:
            return calendar.date(byAdding: .month, value: -3, to: Date()) ?? Date()
        case .sixMonths:
            return calendar.date(byAdding: .month, value: -6, to: Date()) ?? Date()
        case .oneYear:
            return calendar.date(byAdding: .year, value: -1, to: Date()) ?? Date()
        case .allTime:
            return Date.distantPast
        }
    }
}

// MARK: - PR Progress Chart

struct PRProgressChart: View {
    let records: [PersonalRecord]

    private var sortedRecords: [PersonalRecord] {
        records.sorted { $0.date < $1.date }
    }

    var body: some View {
        Chart {
            ForEach(sortedRecords) { record in
                LineMark(
                    x: .value("Date", record.date),
                    y: .value("E1RM", record.estimatedOneRepMax)
                )
                .foregroundStyle(Color.beastPrimary.gradient)
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", record.date),
                    y: .value("E1RM", record.estimatedOneRepMax)
                )
                .foregroundStyle(Color.beastPrimary)
                .symbolSize(40)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let intValue = value.as(Int.self) {
                        Text("\(intValue)")
                    }
                }
            }
        }
        .padding()
    }
}

// MARK: - PR Row View

struct PRRowView: View {
    let record: PersonalRecord

    var body: some View {
        HStack(spacing: 12) {
            // PR indicator
            Image(systemName: "star.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.exerciseName)
                    .font(.beastHeadline)

                Text(record.displayString)
                    .font(.beastBody)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(record.e1rmString)
                    .font(.beastCaption)
                    .foregroundStyle(.beastPrimary)

                Text(record.formattedDate)
                    .font(.beastCaption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - AI Suggestions Sheet

struct AISuggestionsSheet: View {
    let records: [PersonalRecord]
    @State private var suggestions: [WeightSuggestion] = []
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Analyzing your progress...")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if suggestions.isEmpty {
                        ContentUnavailableView(
                            "Need More Data",
                            systemImage: "chart.line.uptrend.xyaxis",
                            description: Text("Log more workouts to get personalized suggestions")
                        )
                    } else {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                            SuggestionCard(suggestion: suggestion)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Weight Suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadSuggestions()
            }
        }
    }

    private func loadSuggestions() async {
        guard !records.isEmpty else { return }
        isLoading = true
        do {
            suggestions = try await AICoachService.shared.suggestProgressiveOverload(records: records)
        } catch {
            print("Failed to load suggestions: \(error)")
        }
        isLoading = false
    }
}

struct SuggestionCard: View {
    let suggestion: WeightSuggestion

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: progressionIcon)
                        .foregroundStyle(progressionColor)

                    Text("\(Int(suggestion.currentWeight)) lbs")
                        .font(.beastHeadline)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    Text("\(Int(suggestion.suggestedWeight)) lbs")
                        .font(.beastHeadline)
                        .foregroundStyle(progressionColor)

                    Spacer()

                    Text("\(suggestion.targetReps) reps")
                        .font(.beastCaption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.ultraThinMaterial, in: Capsule())
                }

                Text(suggestion.reasoning)
                    .font(.beastBody)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var progressionIcon: String {
        switch suggestion.progressionType {
        case .increase: return "arrow.up.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .deload: return "arrow.down.circle.fill"
        }
    }

    private var progressionColor: Color {
        switch suggestion.progressionType {
        case .increase: return .green
        case .maintain: return .blue
        case .deload: return .orange
        }
    }
}

// MARK: - Preview

#Preview {
    ProgressView()
        .modelContainer(for: PersonalRecord.self, inMemory: true)
}
