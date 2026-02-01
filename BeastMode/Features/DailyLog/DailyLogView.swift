import SwiftUI
import SwiftData

/// Main view for logging daily workouts
struct DailyLogView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState

    @State private var selectedDate = Date()
    @State private var dailyLog: DailyLog?
    @State private var showingDatePicker = false
    @State private var showingRestTimer = false
    @State private var showingAddExercise = false
    @State private var showingWorkoutComplete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Date selector
                    dateSelector

                    // Workout status card
                    if let log = dailyLog {
                        workoutStatusCard(log)

                        // Exercise logs
                        ForEach(log.sortedExerciseLogs) { exerciseLog in
                            ExerciseLogCard(exerciseLog: exerciseLog)
                        }

                        // Add exercise button
                        addExerciseButton
                    }
                }
                .padding()
            }
            .background {
                LinearGradient.beastBackgroundGradient
                    .ignoresSafeArea()
            }
            .navigationTitle("Today's Workout")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingRestTimer = true
                    } label: {
                        Image(systemName: "timer")
                    }
                }
            }
            .onAppear {
                loadDailyLog()
            }
            .onChange(of: selectedDate) { _, _ in
                loadDailyLog()
            }
            .sheet(isPresented: $showingDatePicker) {
                DatePickerSheet(selectedDate: $selectedDate)
                    .presentationDetents([.height(400)])
            }
            .sheet(isPresented: $showingRestTimer) {
                RestTimerSheet(duration: appState.defaultRestTimer)
                    .presentationDetents([.height(350)])
            }
            .sheet(isPresented: $showingAddExercise) {
                AddExerciseSheet { name, type in
                    addExercise(name: name, type: type)
                }
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingWorkoutComplete) {
                WorkoutCompleteSheet(dailyLog: dailyLog)
                    .presentationDetents([.medium])
            }
        }
    }

    // MARK: - Date Selector

    private var dateSelector: some View {
        HStack {
            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3)
            }

            Spacer()

            Button {
                showingDatePicker = true
            } label: {
                VStack(spacing: 2) {
                    Text(DateUtilities.relativeDescription(for: selectedDate))
                        .font(.beastHeadline)

                    Text(selectedDate.mediumDateString)
                        .font(.beastCaption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3)
            }
            .disabled(Calendar.current.isDateInToday(selectedDate))
        }
        .padding(.horizontal)
    }

    // MARK: - Workout Status Card

    @ViewBuilder
    private func workoutStatusCard(_ log: DailyLog) -> some View {
        GlassCard {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.weekday.fullName)
                            .font(.beastCaption)
                            .foregroundStyle(.secondary)

                        if log.isComplete {
                            Label("Completed", systemImage: "checkmark.circle.fill")
                                .font(.beastHeadline)
                                .foregroundStyle(.green)
                        } else if log.isInProgress {
                            Label("In Progress", systemImage: "figure.run")
                                .font(.beastHeadline)
                                .foregroundStyle(.beastPrimary)
                        } else {
                            Text("Ready to Start")
                                .font(.beastHeadline)
                        }
                    }

                    Spacer()

                    if let mood = log.mood {
                        Text(mood.emoji)
                            .font(.largeTitle)
                    }
                }

                // Stats row
                HStack(spacing: 20) {
                    statItem(
                        value: "\(log.exerciseLogs.count)",
                        label: "Exercises"
                    )

                    statItem(
                        value: "\(log.completedSetsCount)",
                        label: "Sets"
                    )

                    if log.totalVolume > 0 {
                        statItem(
                            value: formatVolume(log.totalVolume),
                            label: "Volume"
                        )
                    }

                    if let duration = log.formattedDuration {
                        statItem(
                            value: duration,
                            label: "Duration"
                        )
                    }
                }

                // Action buttons
                HStack(spacing: 12) {
                    if !log.isComplete {
                        if log.isInProgress {
                            TintedGlassButton("End Workout", icon: "checkmark", tint: .green) {
                                endWorkout()
                            }
                        } else {
                            TintedGlassButton("Start Workout", icon: "play.fill") {
                                startWorkout()
                            }
                        }
                    } else {
                        GlassButton("View Summary", icon: "chart.bar.fill") {
                            showingWorkoutComplete = true
                        }
                    }
                }
            }
        }
    }

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.beastNumber(20))
            Text(label)
                .font(.beastCaption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var addExerciseButton: some View {
        Button {
            showingAddExercise = true
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add Exercise")
            }
            .font(.beastHeadline)
            .foregroundStyle(.beastPrimary)
            .frame(maxWidth: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.beastPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 2, dash: [8]))
            }
        }
    }

    // MARK: - Actions

    private func loadDailyLog() {
        do {
            dailyLog = try DataService.shared.getDailyLog(for: selectedDate)
        } catch {
            print("Failed to load daily log: \(error)")
        }
    }

    private func startWorkout() {
        dailyLog?.startedAt = Date()
        appState.startWorkout()
        try? DataService.shared.save()
        HapticManager.shared.workoutStart()

        // Track analytics
        let focusArea = dailyLog?.weekday.fullName ?? "Unknown"
        AnalyticsService.shared.track(.workoutStarted(focusArea: focusArea))
    }

    private func endWorkout() {
        guard let log = dailyLog else { return }
        log.completedAt = Date()
        if let startedAt = log.startedAt {
            log.totalDuration = Date().timeIntervalSince(startedAt)
        }
        appState.endWorkout()
        try? DataService.shared.save()
        HapticManager.shared.workoutEnd()
        showingWorkoutComplete = true

        // Track analytics
        AnalyticsService.shared.trackWorkoutComplete(
            focusArea: log.weekday.fullName,
            duration: log.totalDuration ?? 0,
            exerciseCount: log.exerciseLogs.count,
            setCount: log.completedSetsCount
        )
    }

    private func addExercise(name: String, type: ExerciseType) {
        guard let log = dailyLog else { return }
        _ = try? DataService.shared.addExerciseLog(to: log, exerciseName: name, exerciseType: type)
        HapticManager.shared.light()

        // Track analytics
        AnalyticsService.shared.track(.exerciseAdded(exerciseName: name, exerciseType: type.rawValue))
    }

    private func formatVolume(_ volume: Double) -> String {
        if volume >= 1000 {
            return String(format: "%.1fk", volume / 1000)
        }
        return "\(Int(volume))"
    }
}

// MARK: - Exercise Log Card

struct ExerciseLogCard: View {
    @Bindable var exerciseLog: ExerciseLog
    @State private var showingFormCheck = false
    @State private var showingAlternatives = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                HStack {
                    Image(systemName: exerciseLog.exerciseType.icon)
                        .foregroundStyle(.beastPrimary)

                    Text(exerciseLog.exerciseName)
                        .font(.beastHeadline)

                    Spacer()

                    if exerciseLog.hasPR {
                        Label("PR", systemImage: "star.fill")
                            .font(.beastCaption)
                            .foregroundStyle(.orange)
                    }

                    Menu {
                        Button("Form Check", systemImage: "figure.stand") {
                            showingFormCheck = true
                        }
                        Button("Alternatives", systemImage: "arrow.triangle.2.circlepath") {
                            showingAlternatives = true
                        }
                        Divider()
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deleteExercise()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                // Sets
                ForEach(exerciseLog.sortedSets) { setLog in
                    SetInputView(set: setLog, exerciseType: exerciseLog.exerciseType)
                }

                // Add set button
                Button {
                    addSet()
                } label: {
                    HStack {
                        Image(systemName: "plus")
                        Text("Add Set")
                    }
                    .font(.beastCaption)
                    .foregroundStyle(.beastPrimary)
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showingFormCheck) {
            FormCheckSheet(exerciseName: exerciseLog.exerciseName)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingAlternatives) {
            AlternativesSheet(exerciseName: exerciseLog.exerciseName)
                .presentationDetents([.medium])
        }
    }

    private func addSet() {
        _ = try? DataService.shared.addSet(to: exerciseLog)
        HapticManager.shared.light()
    }

    private func deleteExercise() {
        try? DataService.shared.deleteExerciseLog(exerciseLog)
    }
}

// MARK: - Set Input View

struct SetInputView: View {
    @Bindable var set: SetLog
    let exerciseType: ExerciseType
    @State private var showWeightPicker = false

    var body: some View {
        HStack(spacing: 12) {
            // Set number badge
            Text("\(set.setNumber)")
                .font(.beastCaption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(.ultraThinMaterial, in: Circle())

            if exerciseType == .strength {
                // Weight input
                Button {
                    showWeightPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text(set.weight.map { "\(Int($0))" } ?? "--")
                            .font(.beastNumber(18))
                        Text("lbs")
                            .font(.beastCaption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 70)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .glassBackground(cornerRadius: 12)
                }
                .buttonStyle(.plain)

                // Reps input
                HStack(spacing: 8) {
                    Button {
                        decrementReps()
                    } label: {
                        Image(systemName: "minus")
                            .font(.caption)
                    }
                    .disabled((set.reps ?? 0) <= 0)

                    Text("\(set.reps ?? 0)")
                        .font(.beastNumber(18))
                        .frame(minWidth: 30)

                    Button {
                        incrementReps()
                    } label: {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .glassBackground(cornerRadius: 12)

                Text("reps")
                    .font(.beastCaption)
                    .foregroundStyle(.secondary)
            } else if exerciseType == .timed {
                // Duration input
                Text(set.duration.map { DateUtilities.formatDuration($0) } ?? "--:--")
                    .font(.beastNumber(18))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .glassBackground(cornerRadius: 12)
            }

            Spacer()

            // PR indicator
            if set.isPR {
                Image(systemName: "star.fill")
                    .foregroundStyle(.orange)
            }

            // Completion checkmark
            Button {
                toggleCompletion()
            } label: {
                Image(systemName: set.completedAt != nil ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.completedAt != nil ? .green : .secondary)
            }
        }
        .sheet(isPresented: $showWeightPicker) {
            WeightPickerSheet(weight: Binding(
                get: { set.weight ?? 0 },
                set: { set.weight = $0 }
            ))
            .presentationDetents([.height(300)])
        }
    }

    private func incrementReps() {
        set.reps = (set.reps ?? 0) + 1
        HapticManager.shared.tick()
        saveSet()
    }

    private func decrementReps() {
        guard let reps = set.reps, reps > 0 else { return }
        set.reps = reps - 1
        HapticManager.shared.tick()
        saveSet()
    }

    private func toggleCompletion() {
        if set.completedAt == nil {
            set.completedAt = Date()
            HapticManager.shared.setComplete()

            // Check for PR
            if let exerciseLog = set.exerciseLog {
                _ = try? DataService.shared.checkAndSavePR(setLog: set, exerciseName: exerciseLog.exerciseName)
                if set.isPR {
                    HapticManager.shared.personalRecord()

                    // Track PR analytics
                    if let weight = set.weight, let reps = set.reps {
                        AnalyticsService.shared.trackPR(
                            exerciseName: exerciseLog.exerciseName,
                            weight: weight,
                            reps: reps
                        )
                    }
                }

                // Track set logged
                AnalyticsService.shared.track(.setLogged(
                    exerciseName: exerciseLog.exerciseName,
                    isWarmup: set.isWarmup
                ))
            }
        } else {
            set.completedAt = nil
            set.isPR = false
        }
        saveSet()
    }

    private func saveSet() {
        try? DataService.shared.updateSet(set)
    }
}

// MARK: - Supporting Sheets

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Select Date",
                selection: $selectedDate,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Today") {
                        selectedDate = Date()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct RestTimerSheet: View {
    let duration: TimeInterval
    @State private var timeRemaining: TimeInterval
    @State private var isRunning = false
    @Environment(\.dismiss) private var dismiss

    init(duration: TimeInterval) {
        self.duration = duration
        self._timeRemaining = State(initialValue: duration)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Timer display
                ZStack {
                    Circle()
                        .stroke(Color.beastPrimary.opacity(0.2), lineWidth: 12)

                    Circle()
                        .trim(from: 0, to: timeRemaining / duration)
                        .stroke(Color.beastPrimary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: timeRemaining)

                    VStack(spacing: 4) {
                        Text(DateUtilities.formatDuration(timeRemaining))
                            .font(.beastTimer(48))

                        Text("REST")
                            .font(.beastCaption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 180, height: 180)

                // Controls
                HStack(spacing: 24) {
                    Button {
                        timeRemaining = max(0, timeRemaining - 15)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.largeTitle)
                    }

                    Button {
                        isRunning.toggle()
                    } label: {
                        Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 60))
                    }

                    Button {
                        timeRemaining = min(duration + 60, timeRemaining + 15)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.largeTitle)
                    }
                }
                .foregroundStyle(.beastPrimary)
            }
            .padding()
            .navigationTitle("Rest Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            guard isRunning, timeRemaining > 0 else { return }
            timeRemaining -= 1

            if timeRemaining == 10 {
                HapticManager.shared.warning()
            } else if timeRemaining == 0 {
                HapticManager.shared.restTimerComplete()
                isRunning = false
            }
        }
    }
}

struct WeightPickerSheet: View {
    @Binding var weight: Double
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("\(Int(weight)) lbs")
                    .font(.beastLargeNumber)

                Slider(value: $weight, in: 0...500, step: 2.5)
                    .padding(.horizontal)

                HStack(spacing: 16) {
                    ForEach([-10.0, -5.0, -2.5, 2.5, 5.0, 10.0], id: \.self) { increment in
                        Button {
                            weight = max(0, weight + increment)
                            HapticManager.shared.tick()
                        } label: {
                            Text(increment > 0 ? "+\(increment.formatted())" : "\(increment.formatted())")
                                .font(.beastCaption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
            }
            .padding()
            .navigationTitle("Weight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct AddExerciseSheet: View {
    let onAdd: (String, ExerciseType) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var exerciseName = ""
    @State private var exerciseType = ExerciseType.strength

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Exercise Name", text: $exerciseName)
                }

                Section {
                    Picker("Type", selection: $exerciseType) {
                        ForEach(ExerciseType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon)
                                .tag(type)
                        }
                    }
                }
            }
            .navigationTitle("Add Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(exerciseName, exerciseType)
                        dismiss()
                    }
                    .disabled(exerciseName.isEmpty)
                }
            }
        }
    }
}

struct FormCheckSheet: View {
    let exerciseName: String
    @State private var formCheck: FormCheckResponse?
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Getting form tips...")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    } else if let formCheck = formCheck {
                        Text(formCheck.rawText)
                            .font(.beastBody)
                    }
                }
                .padding()
            }
            .navigationTitle("Form Check: \(exerciseName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadFormCheck()
            }
        }
    }

    private func loadFormCheck() async {
        isLoading = true
        do {
            formCheck = try await AICoachService.shared.getFormCheck(for: exerciseName)
        } catch {
            print("Failed to load form check: \(error)")
        }
        isLoading = false
    }
}

struct AlternativesSheet: View {
    let exerciseName: String
    @State private var alternatives: [ExerciseAlternative] = []
    @State private var isLoading = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        ProgressView()
                        Text("Finding alternatives...")
                    }
                } else {
                    ForEach(alternatives) { alt in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(alt.name)
                                .font(.beastHeadline)
                            Text(alt.reason)
                                .font(.beastCaption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Alternatives")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadAlternatives()
            }
        }
    }

    private func loadAlternatives() async {
        isLoading = true
        do {
            alternatives = try await AICoachService.shared.getAlternatives(for: exerciseName)
        } catch {
            print("Failed to load alternatives: \(error)")
        }
        isLoading = false
    }
}

struct WorkoutCompleteSheet: View {
    let dailyLog: DailyLog?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                AnimatedBeastMascot(mood: .celebrating, size: 100)

                Text("Workout Complete!")
                    .font(.beastTitle)

                if let log = dailyLog {
                    VStack(spacing: 12) {
                        HStack(spacing: 30) {
                            statView(value: "\(log.exerciseLogs.count)", label: "Exercises")
                            statView(value: "\(log.completedSetsCount)", label: "Sets")
                        }

                        if log.totalVolume > 0 {
                            statView(value: "\(Int(log.totalVolume)) lbs", label: "Total Volume")
                        }

                        if let duration = log.formattedDuration {
                            statView(value: duration, label: "Duration")
                        }
                    }
                    .padding()
                    .glassBackground(cornerRadius: 16)
                }

                TintedGlassButton("Done", icon: "checkmark", tint: .green) {
                    dismiss()
                }
            }
            .padding()
            .navigationTitle("Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func statView(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.beastNumber(24))
            Text(label)
                .font(.beastCaption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview {
    DailyLogView()
        .environmentObject(AppState())
        .modelContainer(for: [DailyLog.self, ExerciseLog.self, SetLog.self], inMemory: true)
}
