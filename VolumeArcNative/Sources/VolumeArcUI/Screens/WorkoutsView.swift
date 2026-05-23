#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Workouts tab — active session screen with set logging, rest timer, coach cue.
public struct WorkoutsView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @EnvironmentObject private var toastPresenter: VAToastPresenter
    @State private var restEndsAt: Date = .now.addingTimeInterval(90)
    @State private var restActive: Bool = false
    @State private var summary: CompletedSessionSnapshot?

    public init(model: WorkoutDashboardModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.xl) {
                workoutsHeader
                if model.isSessionActive {
                    activeSessionHeader
                    activeExerciseCard
                    activeActions
                    setLogCard
                    if restActive {
                        restTimerCard
                    } else {
                        coachCueCard
                    }
                    upNextCard
                } else {
                    idleState
                }
            }
            .padding(VA.Space.lg)
            .padding(.bottom, VA.Space.xxl)
        }
        .accessibilityIdentifier("workouts.root")
        .background(VA.Colors.surfaceGrouped)
        .navigationTitle(model.isSessionActive
                         ? String(localized: "Session", comment: "Workouts tab title during an active session")
                         : String(localized: "Workouts", comment: "Workouts tab title when idle"))
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $summary) { snapshot in
            SessionSummaryView(
                sets: snapshot.sets,
                totalVolume: snapshot.totalVolume,
                duration: snapshot.duration,
                averageRPE: snapshot.averageRPE,
                primaryLift: snapshot.primaryLift
            ) {
                summary = nil
            }
        }
    }

    /// Captured snapshot of the session state at completion time.
    /// Held locally so the summary sheet can display metrics even after
    /// the model has cleared its `isSessionActive` state.
    struct CompletedSessionSnapshot: Identifiable {
        let id = UUID()
        let sets: Int
        let totalVolume: Double
        let duration: Int
        let averageRPE: Double
        let primaryLift: String
    }

    // MARK: - Header

    private var workoutsHeader: some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(model.isSessionActive
                 ? String(localized: "In progress", comment: "Workouts active session header eyebrow")
                 : String(localized: "Your library", comment: "Workouts library header eyebrow"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
            Text(model.isSessionActive ? activeWorkoutTitle : String(localized: "Workouts", comment: "Workouts header title"))
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
        }
        .padding(.top, VA.Space.sm)
    }

    // MARK: - Active session

    private var activeSessionHeader: some View {
        HStack(alignment: .center, spacing: VA.Space.md) {
            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                Text(String(localized: "LIVE SESSION", comment: "Label above the active session card"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(0.6)
                Text(activeWorkoutTitle)
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                let loggedSets = model.loggedSetCountThisSession
                let setsLoggedText = loggedSets == 1
                    ? String(localized: "1 set logged", comment: "Active session subtitle, singular")
                    : String(localized: "\(loggedSets) sets logged", comment: "Active session subtitle, zero or plural")
                Text(setsLoggedText)
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
            }
            Spacer(minLength: VA.Space.sm)
            ZStack {
                VAProgressRing(progress: setProgress, lineWidth: 4)
                    .frame(width: 44, height: 44)
                Text("\(min(model.loggedSetCountThisSession, targetSetCount))/\(targetSetCount)")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .monospacedDigit()
            }
            .accessibilityLabel(String(
                localized: "Session progress \(min(model.loggedSetCountThisSession, targetSetCount)) of \(targetSetCount) sets",
                comment: "VoiceOver label for active session set progress"
            ))
        }
        .padding(VA.Space.lg)
        .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
        .accessibilityIdentifier("workouts.activeSession")
    }

    @ViewBuilder
    private var activeExerciseCard: some View {
        if let autopilot = model.autopilot {
            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    HStack(alignment: .center, spacing: VA.Space.md) {
                        WorkoutIllustrationTile(systemImage: "figure.strengthtraining.traditional", size: 88, accent: VA.Colors.primary)
                        VStack(alignment: .leading, spacing: VA.Space.xs) {
                            Text(String(
                                localized: "SET \(currentSetNumber) OF \(targetSetCount)",
                                comment: "Active workout current set counter"
                            ))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(0.8)
                            Text(autopilot.nextExerciseName)
                                .font(VA.Typography.title2)
                                .foregroundStyle(VA.Colors.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            HStack(alignment: .firstTextBaseline, spacing: VA.Space.sm) {
                                Text("\(Int(autopilot.nextTarget.weight))")
                                    .font(VA.Typography.display)
                                    .foregroundStyle(VA.Colors.textPrimary)
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.72)
                                Text("\(autopilot.nextTarget.unit) x \(autopilot.nextTarget.repRange.lowerBound)")
                                    .font(VA.Typography.footnote)
                                    .foregroundStyle(VA.Colors.textSecondary)
                            }
                        }
                    }

                    HStack(spacing: VA.Space.xs) {
                        WorkoutChip(text: String(
                            localized: "RPE \(String(format: "%.1f", autopilot.nextTarget.targetRPE)) target",
                            comment: "Active workout target RPE chip"
                        ), tone: .primary)
                        WorkoutChip(text: String(localized: "90s rest", comment: "Active workout rest chip"), tone: .neutral)
                    }

                    VAButton(
                        String(localized: "Log Set", comment: "Button to record the current set"),
                        icon: "checkmark",
                        style: .primary,
                        accessibilityHint: String(localized: "Records this set and starts the rest timer",
                                                  comment: "Log Set button VoiceOver hint"),
                        accessibilityIdentifier: "workouts.logSet"
                    ) {
                        logSet()
                    }
                }
            }
        } else {
            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    WorkoutIllustrationTile(systemImage: "figure.strengthtraining.traditional", size: 88, accent: VA.Colors.primary)
                    Text(String(localized: "Session ready", comment: "Fallback active workout title"))
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(String(
                        localized: "Your next target will appear after the dashboard refreshes.",
                        comment: "Fallback active workout message when no recommendation is loaded"
                    ))
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                }
            }
        }
    }

    private var activeActions: some View {
        HStack(spacing: VA.Space.md) {
            if !restActive {
                VAButton(
                    String(localized: "Start Rest", comment: "Button to start rest timer"),
                    icon: "timer",
                    style: .secondary,
                    accessibilityIdentifier: "workouts.startRest"
                ) {
                    restEndsAt = .now.addingTimeInterval(90)
                    restActive = true
                    VAHaptics.tap()
                }
            }
            VAButton(
                String(localized: "Complete Workout", comment: "Button to finish the current workout session"),
                icon: "flag.checkered",
                style: .secondary,
                accessibilityIdentifier: "workouts.completeWorkout"
            ) {
                completeWorkout()
            }
        }
    }

    private var setLogCard: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            HStack {
                Text(String(localized: "SET LOG", comment: "Active workout set log section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.6)
                Spacer()
                Text(String(localized: "RPE", comment: "Active workout set log rpe column label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
            }
            .padding(.horizontal, VA.Space.xs)

            VACard(style: .flat) {
                VStack(spacing: 0) {
                    ForEach(1...targetSetCount, id: \.self) { setNumber in
                        SetLogRow(
                            setNumber: setNumber,
                            isDone: setNumber <= model.loggedSetCountThisSession,
                            target: compactTarget,
                            rpe: model.autopilot?.nextTarget.targetRPE ?? 7.5
                        )
                        if setNumber != targetSetCount {
                            Divider().padding(.leading, 42)
                        }
                    }
                }
            }
        }
    }

    private var restTimerCard: some View {
        VACard(style: .glass) {
            VStack(spacing: VA.Space.md) {
                Text(String(localized: "RESTING", comment: "Label above the active rest timer"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(0.8)
                RestTimerDisplay(
                    endsAt: restEndsAt,
                    active: restActive,
                    onComplete: {
                        restActive = false
                        VAHaptics.restComplete()
                    }
                )
                VAButton(
                    String(localized: "Skip Rest", comment: "Button to skip active rest timer"),
                    icon: "forward.fill",
                    style: .secondary
                ) {
                    restActive = false
                    VAHaptics.tap()
                }
            }
        }
    }

    @ViewBuilder
    private var coachCueCard: some View {
        if let cue = model.autopilot?.bestCue {
            HStack(alignment: .top, spacing: VA.Space.md) {
                Image(systemName: "quote.opening")
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.primary)
                    .frame(width: 30, height: 30)
                    .background(VA.Colors.primary.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text(String(localized: "Coach cue", comment: "Active workout coach cue label"))
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                    Text(cue)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textPrimary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(VA.Space.lg)
            .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
        }
    }

    private var upNextCard: some View {
        VACard(style: .flat) {
            HStack(alignment: .center, spacing: VA.Space.md) {
                WorkoutIllustrationTile(systemImage: "dumbbell", size: 48, accent: VA.Colors.textSecondary)
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(String(localized: "UP NEXT", comment: "Active workout up next label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.6)
                    Text(nextExercisePreview)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(nextExerciseTargetPreview)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textTertiary)
            }
        }
    }

    // MARK: - Idle state

    private var idleState: some View {
        VStack(alignment: .leading, spacing: VA.Space.xl) {
            programsLibraryLink
            WorkoutIdleLibrary(
                featuredTitle: model.nextWorkout?.title ?? String(
                    localized: "Strength Session",
                    comment: "Featured workout fallback title"
                ),
                featuredFocus: model.autopilot?.nextExerciseName ?? String(
                    localized: "Chest · Shoulders · Triceps",
                    comment: "Featured workout focus"
                ),
                startWorkout: startWorkout
            )
        }
        .accessibilityIdentifier("workouts.emptyState")
    }

    private var programsLibraryLink: some View {
        NavigationLink {
            ProgramsLibraryView(model: model)
        } label: {
            VACard(style: .accent) {
                HStack(alignment: .center, spacing: VA.Space.md) {
                    WorkoutIllustrationTile(systemImage: "books.vertical.fill", size: 58, accent: VA.Colors.primary)
                    VStack(alignment: .leading, spacing: VA.Space.xs) {
                        Text(String(localized: "Programs", comment: "Workouts programs library CTA title"))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(programsLibrarySubtitle)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: VA.Space.sm)
                    Image(systemName: "chevron.right")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textTertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("workouts.programsLibrary")
    }

    // MARK: - Actions

    private func startWorkout() {
        Task {
            VAHaptics.sessionStart()
            await model.startWorkoutSession()
        }
    }

    private func logSet() {
        Task {
            VAHaptics.setLogged()
            await model.logRecommendedSet()
            restEndsAt = .now.addingTimeInterval(90)
            restActive = true
            toastPresenter.show(VAToast(
                kind: .success,
                title: String(localized: "Set logged", comment: "Toast after logging a set"),
                message: String(localized: "Starting your 90-second rest.", comment: "Toast detail")
            ))
        }
    }

    private func completeWorkout() {
        Task {
            VAHaptics.workoutComplete()

            let capturedSets = model.loggedSetCountThisSession
            let capturedRPE = model.autopilot?.nextTarget.targetRPE ?? 7.5
            let capturedLift = model.autopilot?.nextExerciseName ?? String(
                localized: "your workout",
                comment: "Fallback phrase for the primary lift when none is identified"
            )

            let completedSession = await model.completeWorkoutSession()
            restActive = false

            summary = CompletedSessionSnapshot(
                sets: completedSession?.completedSetCount ?? max(1, capturedSets),
                totalVolume: max(completedSession?.totalVolumeLoad ?? 0, 1),
                duration: max(completedSession?.durationMinutes ?? 0, 1),
                averageRPE: completedSession?.averageRPE ?? capturedRPE,
                primaryLift: capturedLift
            )
        }
    }

    // MARK: - Derived display values

    private var activeWorkoutTitle: String {
        model.activeWorkoutTitle ?? String(localized: "Strength Session", comment: "Default active workout title")
    }

    private var targetSetCount: Int { 5 }

    private var currentSetNumber: Int {
        min(model.loggedSetCountThisSession + 1, targetSetCount)
    }

    private var setProgress: Double {
        Double(min(model.loggedSetCountThisSession, targetSetCount)) / Double(targetSetCount)
    }

    private var compactTarget: String {
        guard let target = model.autopilot?.nextTarget else {
            return String(localized: "Target pending", comment: "Fallback active workout set target")
        }
        return "\(Int(target.weight)) x \(target.repRange.lowerBound)"
    }

    private var nextExercisePreview: String {
        model.autopilot?.nextExerciseName ?? String(localized: "Accessory work", comment: "Active workout up next fallback")
    }

    private var nextExerciseTargetPreview: String {
        guard let target = model.autopilot?.nextTarget else {
            return String(localized: "3 x 10 · moderate load", comment: "Active workout up next fallback target")
        }
        return "\(target.repRange.lowerBound) x \(target.repRange.upperBound) · \(Int(target.weight)) \(target.unit)"
    }

    private var programsLibrarySubtitle: String {
        if let activeProgram = model.activeProgram {
            return String(
                localized: "\(activeProgram.programName) · Week \(activeProgram.weekNumber), Day \(activeProgram.dayNumber)",
                comment: "Workouts active program CTA subtitle"
            )
        }
        return String(
            localized: "Starting Strength, 5/3/1, PPL, Upper/Lower, and HST",
            comment: "Workouts programs library CTA subtitle"
        )
    }
}
#endif
