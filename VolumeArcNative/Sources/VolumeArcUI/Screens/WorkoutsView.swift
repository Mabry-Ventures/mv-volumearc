#if canImport(SwiftUI)
// swiftlint:disable file_length
// Active-session orchestration remains in one view until the workout engine
// supports exercise-level routing as first-class state.
import SwiftUI
import VolumeArcCore

// The Workouts tab: active session screen with set logging, rest timer, coach cue.
// swiftlint:disable:next type_body_length
public struct WorkoutsView: View {
    @ObservedObject var model: WorkoutDashboardModel
    private let navigation: DashboardNavigationModel?
    @EnvironmentObject private var toastPresenter: VAToastPresenter
    @AppStorage("volumearc.sessionProfiles.active")
    private var activeSessionProfileName = WorkoutSessionProfile.defaultProfile.rawValue
    @AppStorage("volumearc.sessionProfiles.legDayRule")
    private var isLegDayRuleEnabled = false
    @AppStorage("volumearc.sessionProfiles.shortSessionRule")
    private var isShortSessionRuleEnabled = false
    @State private var restEndsAt: Date = .now.addingTimeInterval(90)
    @State private var restActive: Bool = false
    @State private var summary: CompletedSessionSnapshot?
    @State private var formCheckPayload: FormCheckCapturePayload?
    @State private var pendingDeleteSession: RecentSession?
    @State private var pendingDiscardSession = false
    @State private var targetWeightOverride: Double?
    @State private var targetRepsOverride: Int?
    @State private var targetRPEOverride: Double?
    @State private var replacementExercise: ExerciseDefinition?
    @State private var isShowingExerciseGuide = false
    @State private var isShowingWorkoutBuilder = false
    @State private var builderDraft = WorkoutBuilderDraft()

    public init(model: WorkoutDashboardModel, navigation: DashboardNavigationModel? = nil) {
        self.model = model
        self.navigation = navigation
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.xl) {
                workoutsHeader
                if model.isSessionActive {
                    activeSessionHeader
                    activeExerciseCard
                    activeActions
                    activeExerciseListCard
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
        .fullScreenCover(item: $formCheckPayload) { payload in
            FormCheckCaptureView(
                exercise: payload.exercise,
                exerciseName: payload.exerciseName
            ) { analysis in
                completeFormCheck(analysis)
            }
        }
        .confirmationDialog(
            String(localized: "Exit this workout?", comment: "Active workout discard confirmation title"),
            isPresented: $pendingDiscardSession,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "Discard Session", comment: "Active workout discard confirmation destructive button"),
                role: .destructive
            ) {
                discardWorkout()
            }
            Button(String(localized: "Keep Training", comment: "Active workout discard confirmation cancel button"), role: .cancel) {}
        } message: {
            Text(String(
                localized: "This exits the live workout without saving it as completed history.",
                comment: "Active workout discard confirmation explanatory copy"
            ))
        }
        .confirmationDialog(
            String(localized: "Delete this session?", comment: "Workout history delete confirmation title"),
            isPresented: isConfirmingSessionDelete,
            titleVisibility: .visible
        ) {
            Button(
                String(localized: "Delete Session", comment: "Workout history destructive delete confirmation button"),
                role: .destructive
            ) {
                guard let session = pendingDeleteSession else { return }
                pendingDeleteSession = nil
                deleteSession(session)
            }
            Button(String(localized: "Cancel", comment: "Cancel workout history deletion"), role: .cancel) {
                pendingDeleteSession = nil
            }
        } message: {
            Text(String(
                localized: "This removes the session from VolumeArc history and syncs the delete to your private iCloud data.",
                comment: "Workout history delete confirmation explanatory copy"
            ))
        }
        .sheet(isPresented: $isShowingExerciseGuide) {
            ActiveExerciseGuideView(
                exercise: currentExerciseDefinition,
                fallbackExerciseName: currentExerciseName,
                fallbackCue: model.autopilot?.bestCue
            )
        }
        .sheet(isPresented: $isShowingWorkoutBuilder) {
            WorkoutBuilderSheet(
                draft: $builderDraft,
                templateForProfile: starterPlan(for:),
                onStart: startBuilderWorkout,
                onSchedule: scheduleBuilderWorkout,
                onAskCoachReview: askCoachToReviewBuilderWorkout
            )
        }
        .onChange(of: model.autopilot?.nextExerciseID) { _, _ in
            resetLiveWorkoutOverrides()
        }
        .onChange(of: model.activeSessionExerciseIndex) { _, _ in
            resetLiveWorkoutOverrides()
        }
        .onChange(of: model.isSessionActive) { _, isActive in
            if !isActive {
                resetLiveWorkoutOverrides()
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

    struct FormCheckCapturePayload: Identifiable {
        let id = UUID()
        let exercise: FormCheckExercise
        let exerciseName: String
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
        VStack(alignment: .leading, spacing: VA.Space.md) {
            HStack(alignment: .center, spacing: VA.Space.md) {
                let currentSetCount = min(model.loggedSetCountThisSession, sessionTargetSetCount)
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(String(localized: "LIVE SESSION", comment: "Label above the active session card"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.primary)
                        .tracking(0.6)
                    Text(activeWorkoutTitle)
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    let loggedSets = model.loggedSetCountThisSession
                    let setsLoggedText = String(
                        localized: "^[\(loggedSets) set](inflect: true) logged",
                        comment: "Active session subtitle with logged set count"
                    )
                    Text(setsLoggedText)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer(minLength: VA.Space.sm)
                ZStack {
                    VAProgressRing(progress: setProgress, lineWidth: 4)
                        .frame(width: 44, height: 44)
                    Text("\(currentSetCount)/\(sessionTargetSetCount)")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textPrimary)
                        .monospacedDigit()
                }
                .accessibilityLabel(String(
                    localized: "Session progress \(currentSetCount) of ^[\(sessionTargetSetCount) set](inflect: true)",
                    comment: "VoiceOver label for active session set progress"
                ))
                Button {
                    pendingDiscardSession = true
                    VAHaptics.tap()
                } label: {
                    Label(
                        String(localized: "Exit Session", comment: "Active workout header exit button"),
                        systemImage: "xmark"
                    )
                    .labelStyle(.iconOnly)
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(VA.Colors.textTertiary.opacity(0.14), in: Circle())
                    .accessibilityIdentifier("workouts.exitSession.header")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Exit Session", comment: "Active workout header exit button"))
                .accessibilityIdentifier("workouts.exitSession.header")
            }
            Button {
                completeWorkout()
            } label: {
                Label(
                    String(localized: "Complete Workout", comment: "Active workout header complete button"),
                    systemImage: "flag.checkered"
                )
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, VA.Space.sm)
                .background(VA.Colors.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                        .stroke(VA.Colors.primary.opacity(0.22), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("workouts.completeWorkout.header")
        }
        .padding(VA.Space.lg)
        .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workouts.activeSession")
    }

    @ViewBuilder
    private var activeExerciseCard: some View {
        if hasActiveExercise {
            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    HStack(alignment: .center, spacing: VA.Space.md) {
                        WorkoutIllustrationTile(
                            systemImage: replacementExercise == nil
                                ? "figure.strengthtraining.traditional"
                                : "arrow.triangle.2.circlepath",
                            size: 88,
                            accent: replacementExercise == nil ? VA.Colors.primary : VA.Colors.secondary
                        )
                        VStack(alignment: .leading, spacing: VA.Space.xs) {
                            Text(String(
                                localized: "SET \(currentSetNumber) OF \(currentExerciseSetCount)",
                                comment: "Active workout current set counter"
                            ))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(0.8)
                            Text(currentExerciseName)
                                .font(VA.Typography.title2)
                                .foregroundStyle(VA.Colors.textPrimary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.82)

                            HStack(alignment: .firstTextBaseline, spacing: VA.Space.sm) {
                                Text("\(Int(activeTargetWeight))")
                                    .font(VA.Typography.display)
                                    .foregroundStyle(VA.Colors.textPrimary)
                                    .monospacedDigit()
                                    .minimumScaleFactor(0.72)
                                Text("\(activeTargetUnit) x \(activeTargetReps)")
                                    .font(VA.Typography.footnote)
                                    .foregroundStyle(VA.Colors.textSecondary)
                            }
                        }
                    }

                    HStack(spacing: VA.Space.xs) {
                        WorkoutChip(text: String(
                            localized: "RPE \(String(format: "%.1f", activeTargetRPE)) target",
                            comment: "Active workout target RPE chip"
                        ), tone: .primary)
                        WorkoutChip(text: restChipText, tone: .neutral)
                    }

                    liveTargetEditor
                    livePivotActions
                    activeExercisePrimaryActions
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

    private var activeExercisePrimaryActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: VA.Space.sm) {
                logSetButton
                inlineCompleteWorkoutButton
            }
            VStack(spacing: VA.Space.sm) {
                logSetButton
                inlineCompleteWorkoutButton
            }
        }
    }

    private var logSetButton: some View {
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

    private var inlineCompleteWorkoutButton: some View {
        Button {
            completeWorkout()
        } label: {
            Label(
                String(localized: "Complete", comment: "Compact inline active workout completion button"),
                systemImage: "flag.checkered"
            )
            .font(VA.Typography.button)
            .foregroundStyle(VA.Colors.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .padding(.horizontal, VA.Space.md)
            .background(
                VA.Colors.textTertiary.opacity(0.12),
                in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                    .stroke(VA.Colors.textTertiary.opacity(0.20), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Complete Workout", comment: "Inline active workout completion accessibility label"))
        .accessibilityIdentifier("workouts.completeWorkout")
    }

    private var liveTargetEditor: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(String(localized: "ADJUST SET", comment: "Active workout target editor section label"))
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.6)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VA.Space.sm) { targetControls }
                VStack(spacing: VA.Space.sm) { targetControls }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workouts.targetEditor")
    }

    @ViewBuilder
    private var targetControls: some View {
        LiveWorkoutStepper(
            label: String(localized: "lb", comment: "Active workout weight stepper label"),
            value: Int(activeTargetWeight),
            range: 0...700,
            step: 5,
            accessibilityPrefix: "workouts.target.weight"
        ) { newValue in
            targetWeightOverride = Double(newValue)
            VAHaptics.selection()
        }
        LiveWorkoutStepper(
            label: String(localized: "Reps", comment: "Active workout reps stepper label"),
            value: activeTargetReps,
            range: 1...50,
            accessibilityPrefix: "workouts.target.reps"
        ) { newValue in
            targetRepsOverride = newValue
            VAHaptics.selection()
        }
        LiveWorkoutStepper(
            label: String(localized: "RPE", comment: "Active workout RPE stepper label"),
            value: Int(activeTargetRPE.rounded()),
            range: 1...10,
            accessibilityPrefix: "workouts.target.rpe"
        ) { newValue in
            targetRPEOverride = Double(newValue)
            VAHaptics.selection()
        }
    }

    private var livePivotActions: some View {
        FlowLayout(spacing: VA.Space.xs) {
            LiveWorkoutActionChip(
                title: String(localized: "Equipment busy", comment: "Active workout equipment busy action"),
                icon: "arrow.triangle.2.circlepath",
                accessibilityIdentifier: "workouts.equipmentBusy",
                action: chooseEquipmentBusyReplacement
            )
            LiveWorkoutActionChip(
                title: String(localized: "Skip exercise", comment: "Active workout skip exercise action"),
                icon: "forward.fill",
                accessibilityIdentifier: "workouts.skipExercise",
                action: skipCurrentExercise
            )
            LiveWorkoutActionChip(
                title: String(localized: "View diagram", comment: "Active workout view exercise diagram action"),
                icon: "rectangle.on.rectangle",
                accessibilityIdentifier: "workouts.exerciseGuide"
            ) {
                isShowingExerciseGuide = true
                VAHaptics.tap()
            }
        }
    }

    private var activeExerciseListCard: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack {
                    Text(String(localized: "WORKOUT MAP", comment: "Active workout full exercise list label"))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.6)
                    Spacer()
                    Text(String(
                        localized: "\(activeWorkoutExerciseNames.count) moves",
                        comment: "Active workout exercise list count"
                    ))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                }

                VStack(spacing: VA.Space.sm) {
                    ForEach(Array(activeWorkoutExerciseNames.enumerated()), id: \.offset) { index, name in
                        let isCurrent = isCurrentExercise(index: index, name: name)
                        if model.activeSessionPlan != nil {
                            Button {
                                selectActiveExercise(at: index)
                            } label: {
                                ActiveWorkoutMapRow(
                                    index: index,
                                    name: name,
                                    isCurrent: isCurrent,
                                    isSelectable: !isCurrent
                                )
                                .accessibilityIdentifier("workouts.exerciseList.\(index)")
                            }
                            .buttonStyle(.plain)
                            .disabled(isCurrent)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(activeWorkoutMapAccessibilityLabel(
                                name: name,
                                isCurrent: isCurrent
                            ))
                            .accessibilityIdentifier("workouts.exerciseList.\(index)")
                        } else {
                            ActiveWorkoutMapRow(
                                index: index,
                                name: name,
                                isCurrent: isCurrent,
                                isSelectable: false
                            )
                            .accessibilityIdentifier("workouts.exerciseList.\(index)")
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("workouts.exerciseList")
    }

    private var activeActions: some View {
        VStack(spacing: VA.Space.md) {
            HStack(spacing: VA.Space.md) {
                if !restActive {
                    VAButton(
                        String(localized: "Start Rest", comment: "Button to start rest timer"),
                        icon: "timer",
                        style: .secondary,
                        accessibilityIdentifier: "workouts.startRest"
                    ) {
                        startRestTimer()
                        VAHaptics.tap()
                    }
                }
            }
            VAButton(
                String(localized: "Exit Session", comment: "Button to exit the current workout without completing"),
                icon: "xmark",
                style: .destructive,
                accessibilityIdentifier: "workouts.exitSession"
            ) {
                pendingDiscardSession = true
                VAHaptics.tap()
            }
            if formCheckExercise != nil {
                VAButton(
                    String(localized: "Form Check", comment: "Button to start Vision form check"),
                    icon: "camera.viewfinder",
                    style: .primary,
                    accessibilityIdentifier: "workouts.formCheck"
                ) {
                    VAHaptics.tap()
                    openFormCheck()
                }
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
                    ForEach(1...currentExerciseSetCount, id: \.self) { setNumber in
                        SetLogRow(
                            setNumber: setNumber,
                            isDone: setNumber <= currentExerciseLoggedSetCount,
                            target: compactTarget,
                            rpe: activeTargetRPE
                        )
                        if setNumber != currentExerciseSetCount {
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
                    totalDuration: restDuration,
                    onComplete: {
                        restActive = false
                        model.recordRestTimerExpired(duration: restDuration)
                        VAHaptics.restComplete()
                        toastPresenter.show(VAToast(
                            kind: .success,
                            title: String(localized: "Rest complete", comment: "Toast title when rest timer expires"),
                            message: String(localized: "Take your next set when ready.", comment: "Toast body when rest timer expires")
                        ))
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
            if let todayWorkout {
                scheduledTodayCard(todayWorkout)
            }
            WorkoutBuilderCard(
                profileSummary: resolvedSessionProfileDisplayName,
                startManual: openManualWorkoutBuilder,
                askCoach: openCoachWorkoutBuilder
            )
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
            .accessibilityIdentifier("workouts.emptyState")
            if let tomorrowWorkout {
                scheduledTomorrowCard(tomorrowWorkout)
            }
            programsLibraryLink
            if !model.recentSessions.isEmpty {
                recentSessionsHistory
            }
        }
    }

    private func scheduledTodayCard(_ workout: WeeklyWorkout) -> some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(alignment: .top, spacing: VA.Space.md) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: 46, height: 46)
                        .background(VA.Colors.primary.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(String(localized: "SCHEDULED TODAY", comment: "Workouts scheduled today card eyebrow"))
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.primary)
                            .tracking(0.6)
                        Text(workout.title)
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                        Text(scheduledWorkoutSubtitle(workout))
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                    }
                    Spacer(minLength: VA.Space.sm)
                }

                VAButton(
                    String(localized: "Start Scheduled Workout", comment: "Workouts scheduled today start action"),
                    icon: "play.fill",
                    style: .primary,
                    accessibilityIdentifier: "workouts.scheduledToday.start"
                ) {
                    startScheduledWorkout(workout)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workouts.scheduledToday")
    }

    private func scheduledTomorrowCard(_ workout: WeeklyWorkout) -> some View {
        HStack(alignment: .center, spacing: VA.Space.md) {
            Image(systemName: "calendar.badge.clock")
                .font(VA.Typography.title2)
                .foregroundStyle(VA.Colors.primary)
                .frame(width: 46, height: 46)
                .background(VA.Colors.primary.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: VA.Space.xxs) {
                Text(String(localized: "SCHEDULED · TOMORROW", comment: "Workouts scheduled tomorrow card eyebrow"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.primary)
                    .tracking(0.6)
                Text(workout.title)
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(scheduledWorkoutSubtitle(workout))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
            }
            Spacer(minLength: VA.Space.sm)
        }
        .padding(VA.Space.lg)
        .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.lg, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workouts.scheduledTomorrow")
    }

    private func scheduledWorkoutSubtitle(_ workout: WeeklyWorkout) -> String {
        guard let firstExercise = workout.exercises.first else {
            return String(
                localized: "Ready in your weekly plan.",
                comment: "Workouts scheduled tomorrow card subtitle"
            )
        }
        return String(
            localized: "^[\(workout.exercises.count) move](inflect: true) - \(firstExercise.name) first",
            comment: "Workouts scheduled tomorrow card subtitle with co-designed exercise preview"
        )
    }

    private var programsLibraryLink: some View {
        NavigationLink {
            ProgramsLibraryView(model: model)
        } label: {
            VACard(style: .accent) {
                HStack(alignment: .center, spacing: VA.Space.md) {
                    WorkoutIllustrationTile(
                        systemImage: "books.vertical.fill",
                        size: VA.Space.ctaIllustration,
                        accent: VA.Colors.primary
                    )
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

    private var recentSessionsHistory: some View {
        WorkoutHistorySection(
            sessions: model.recentSessions,
            onOpen: { session in
                model.recordWorkoutDetailOpened(session: session)
            },
            onDelete: { session in
                pendingDeleteSession = session
            }
        )
    }

    // MARK: - Actions

    private func startWorkout() {
        startWorkout(title: nil)
    }

    private func startWorkout(title: String?, plan: WorkoutSessionPlan? = nil) {
        Task {
            VAHaptics.sessionStart()
            await model.startWorkoutSession(title: title, plan: plan)
        }
    }

    private func startScheduledWorkout(_ workout: WeeklyWorkout) {
        let plan = workout.exercises.isEmpty ? nil : WorkoutSessionPlan(workout: workout)
        startWorkout(title: workout.title, plan: plan)
    }

    private func openManualWorkoutBuilder() {
        builderDraft = WorkoutBuilderDraft(plan: manualStarterPlan, profile: resolvedSessionProfile)
        isShowingWorkoutBuilder = true
        VAHaptics.tap()
    }

    private func startBuilderWorkout(_ draft: WorkoutBuilderDraft) {
        activeSessionProfileName = draft.profile.rawValue
        isShowingWorkoutBuilder = false
        startWorkout(title: draft.title, plan: draft.plan)
    }

    private func scheduleBuilderWorkout(_ draft: WorkoutBuilderDraft, target: WorkoutBuilderScheduleTarget) {
        activeSessionProfileName = draft.profile.rawValue
        Task {
            let scheduled = await model.scheduleWorkoutPlan(
                draft.plan,
                on: target.date,
                source: "workouts_builder"
            )
            toastPresenter.show(VAToast(
                kind: scheduled ? .success : .error,
                title: scheduled
                    ? String(localized: "Workout scheduled", comment: "Toast title after scheduling builder workout")
                    : String(localized: "Could not schedule workout", comment: "Toast title after schedule builder failure"),
                message: scheduled
                    ? target.successMessage
                    : String(localized: "Try again after the training plan finishes syncing.", comment: "Toast body after schedule builder failure")
            ))
            if scheduled {
                isShowingWorkoutBuilder = false
            }
        }
    }

    private func askCoachToReviewBuilderWorkout(_ draft: WorkoutBuilderDraft) {
        activeSessionProfileName = draft.profile.rawValue
        isShowingWorkoutBuilder = false
        navigation?.openCoach(prompt: draft.coachReviewPrompt(readinessScore: model.readiness.score))
    }

    private func openCoachWorkoutBuilder() {
        VAHaptics.tap()
        let prompt = String(
            localized: """
                Build me a safe strength workout for today using my readiness, available equipment, \
                session time, and my \(resolvedSessionProfileDisplayName) session profile. Make it one \
                I can schedule or start.
                """,
            comment: "Workouts coach builder prompt"
        )
        navigation?.openCoach(prompt: prompt)
    }

    private func logSet() {
        Task {
            VAHaptics.setLogged()
            await model.logRecommendedSet(
                weightOverride: activeTargetWeight,
                repsOverride: activeTargetReps,
                rpeOverride: activeTargetRPE,
                exerciseIDOverride: currentExerciseDefinition?.id,
                exerciseNameOverride: currentExerciseName
            )
            startRestTimer()
            toastPresenter.show(VAToast(
                kind: .success,
                title: String(localized: "Set logged", comment: "Toast after logging a set"),
                message: restStartedToastMessage
            ))
        }
    }

    private func discardWorkout() {
        Task {
            let discarded = await model.discardActiveWorkoutSession()
            restActive = false
            replacementExercise = nil
            toastPresenter.show(VAToast(
                kind: discarded ? .info : .error,
                title: discarded
                    ? String(localized: "Session exited", comment: "Toast title after discarding active workout")
                    : String(localized: "Could not exit session", comment: "Toast title when active workout discard fails"),
                message: discarded
                    ? String(localized: "Nothing was saved as a completed workout.", comment: "Toast body after discarding workout")
                    : String(localized: "Try completing or deleting the session from history.", comment: "Toast body when discard fails")
            ))
        }
    }

    private func chooseEquipmentBusyReplacement() {
        if model.activeSessionPlan != nil,
           let pivot = model.deferActiveSessionExercise() {
            resetLiveWorkoutOverrides()
            restActive = false
            VAHaptics.selection()
            toastPresenter.show(VAToast(
                kind: .info,
                title: String(localized: "Next lift loaded", comment: "Toast title after deferring busy equipment"),
                message: String(
                    localized: "Moved \(pivot.deferredExercise) later and loaded \(pivot.nextExercise).",
                    comment: "Toast body after deferring busy equipment"
                )
            ))
            return
        }

        guard let currentExerciseDefinition else {
            toastPresenter.show(VAToast(
                kind: .warning,
                title: String(localized: "No replacement found", comment: "Toast title when equipment-busy replacement fails"),
                message: String(localized: "Ask the coach for a swap with your available equipment.", comment: "Toast body when replacement fails")
            ))
            return
        }

        let alternatives = VolumeArcExerciseCatalog.alternatives(
            for: currentExerciseDefinition,
            availableEquipment: model.athlete.availableEquipment
        )
        guard let replacement = alternatives.first else {
            toastPresenter.show(VAToast(
                kind: .warning,
                title: String(localized: "No same-pattern swap", comment: "Toast title when no same-pattern swap exists"),
                message: String(localized: "Skip it for now or ask the coach for a manual replacement.", comment: "Toast body when no swap exists")
            ))
            return
        }

        let replacementTarget = WeeklyWorkoutExercise(
            name: replacement.name,
            sets: max(1, currentExerciseSetCount),
            reps: replacement.defaultRepRange.lowerBound,
            weight: Int(activeTargetWeight),
            targetRPE: Int(min(activeTargetRPE, replacement.defaultRPE).rounded()),
            restSeconds: restDurationSeconds
        )
        if model.activeSessionPlan != nil {
            model.replaceActiveSessionExercise(with: replacementTarget)
            replacementExercise = nil
        } else {
            replacementExercise = replacement
        }
        targetRepsOverride = replacement.defaultRepRange.lowerBound
        targetRPEOverride = min(activeTargetRPE, replacement.defaultRPE)
        VAHaptics.selection()
        toastPresenter.show(VAToast(
            kind: .info,
            title: String(localized: "Pivot loaded", comment: "Toast title after choosing equipment-busy replacement"),
            message: String(localized: "\(replacement.name) keeps the same movement pattern.", comment: "Toast body after replacement")
        ))
    }

    private func skipCurrentExercise() {
        if model.activeSessionPlan != nil {
            model.skipActiveSessionExercise()
            resetLiveWorkoutOverrides()
            VAHaptics.selection()
            toastPresenter.show(VAToast(
                kind: .info,
                title: String(localized: "Exercise skipped", comment: "Toast title after skipping exercise"),
                message: String(localized: "Moved to the next planned lift.", comment: "Toast body after skipping exercise")
            ))
        } else {
            chooseEquipmentBusyReplacement()
        }
    }

    private func selectActiveExercise(at index: Int) {
        guard let exercise = model.activeSessionPlan?.exercise(at: index),
              index != model.activeSessionExerciseIndex
        else { return }

        model.moveActiveSession(toExerciseAt: index)
        resetLiveWorkoutOverrides()
        restActive = false
        VAHaptics.selection()
        toastPresenter.show(VAToast(
            kind: .info,
            title: String(localized: "Exercise loaded", comment: "Toast title after selecting active workout map exercise"),
            message: String(
                localized: "\(exercise.name) is now the active lift.",
                comment: "Toast body after selecting active workout map exercise"
            )
        ))
    }

    private func resetLiveWorkoutOverrides() {
        targetWeightOverride = nil
        targetRepsOverride = nil
        targetRPEOverride = nil
        replacementExercise = nil
    }

    private func startRestTimer() {
        restEndsAt = .now.addingTimeInterval(restDuration)
        restActive = true
    }

    private func completeWorkout() {
        Task {
            VAHaptics.workoutComplete()

            let capturedSets = model.loggedSetCountThisSession
            let capturedRPE = activeTargetRPE
            let capturedLift = currentExerciseName.isEmpty ? String(
                localized: "your workout",
                comment: "Fallback phrase for the primary lift when none is identified"
            ) : currentExerciseName

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

    private var isConfirmingSessionDelete: Binding<Bool> {
        Binding(
            get: { pendingDeleteSession != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeleteSession = nil
                }
            }
        )
    }

    private func deleteSession(_ session: RecentSession) {
        Task {
            let didDelete = await model.deleteWorkoutSession(session)
            toastPresenter.show(VAToast(
                kind: didDelete ? .success : .error,
                title: didDelete
                    ? String(localized: "Session deleted", comment: "Toast title after deleting a workout session")
                    : String(localized: "Could not delete session", comment: "Toast title when workout delete fails"),
                message: didDelete
                    ? String(localized: "Your history has been updated.", comment: "Toast body after deleting a workout session")
                    : String(localized: "Try again from Workouts history.", comment: "Toast body when workout delete fails")
            ))
        }
    }

    private func completeFormCheck(_ analysis: FormCheckAnalysis) {
        model.recordFormCheckAnalysis(analysis)
        toastPresenter.show(VAToast(
            kind: toastKind(for: analysis.verdict),
            title: String(localized: "Form check saved", comment: "Toast after form check capture"),
            message: analysis.summaryLine
        ))
    }

    private func openFormCheck() {
        guard let exercise = formCheckExercise else { return }
        formCheckPayload = FormCheckCapturePayload(
            exercise: exercise,
            exerciseName: currentExerciseName.isEmpty ? LocalizedLabels.formCheckExerciseDisplayName(exercise) : currentExerciseName
        )
    }

    private func toastKind(for verdict: FormCheckVerdict) -> VAToast.Kind {
        switch verdict {
        case .solid:
            return .success
        case .review:
            return .warning
        case .inconclusive:
            return .info
        }
    }

    // MARK: - Derived display values

    private var activeWorkoutTitle: String {
        model.activeWorkoutTitle ?? String(localized: "Strength Session", comment: "Default active workout title")
    }

    private var hasActiveExercise: Bool {
        model.activeSessionExercise != nil || model.autopilot != nil || replacementExercise != nil
    }

    private var currentExerciseSetCount: Int {
        max(1, model.activeSessionExerciseSetCount > 0 ? model.activeSessionExerciseSetCount : 5)
    }

    private var currentExerciseLoggedSetCount: Int {
        model.activeSessionPlan == nil
            ? min(model.loggedSetCountThisSession, currentExerciseSetCount)
            : min(model.loggedSetCountForActiveExercise, currentExerciseSetCount)
    }

    private var sessionTargetSetCount: Int {
        max(1, model.activeSessionTotalSetCount > 0 ? model.activeSessionTotalSetCount : currentExerciseSetCount)
    }

    private var restDuration: TimeInterval {
        VolumeArcRuntimeFlags.restTimerDurationOverride
            ?? TimeInterval(model.activeSessionExercise?.restSeconds ?? 90)
    }

    private var restDurationSeconds: Int {
        max(1, Int(restDuration.rounded()))
    }

    private var restChipText: String {
        String(localized: "\(restDurationSeconds)s rest", comment: "Active workout rest chip")
    }

    private var restStartedToastMessage: String {
        String(
            localized: "Starting your ^[\(restDurationSeconds) second](inflect: true) rest.",
            comment: "Toast detail after logging a set and starting rest"
        )
    }

    private var currentSetNumber: Int {
        min(currentExerciseLoggedSetCount + 1, currentExerciseSetCount)
    }

    private var setProgress: Double {
        Double(min(model.loggedSetCountThisSession, sessionTargetSetCount)) / Double(sessionTargetSetCount)
    }

    private var compactTarget: String {
        "\(Int(activeTargetWeight)) x \(activeTargetReps)"
    }

    private var currentExerciseName: String {
        replacementExercise?.name
            ?? model.activeSessionExercise?.name
            ?? model.autopilot?.nextExerciseName
            ?? String(localized: "Current exercise", comment: "Fallback active workout current exercise name")
    }

    private var currentExerciseDefinition: ExerciseDefinition? {
        if let replacementExercise {
            return replacementExercise
        }
        if let plannedExercise = model.activeSessionExercise,
           let exercise = exerciseDefinition(named: plannedExercise.name) {
            return exercise
        }
        guard let autopilot = model.autopilot else { return nil }
        return VolumeArcExerciseCatalog.exercise(withID: autopilot.nextExerciseID)
    }

    private var activeTargetWeight: Double {
        targetWeightOverride ?? model.activeSessionExercise.map { Double($0.weight) } ?? model.autopilot?.nextTarget.weight ?? 0
    }

    private var activeTargetReps: Int {
        targetRepsOverride ?? model.activeSessionExercise?.reps ?? model.autopilot?.nextTarget.repRange.lowerBound ?? 1
    }

    private var activeTargetRPE: Double {
        targetRPEOverride ?? model.activeSessionExercise.map { Double($0.targetRPE) } ?? model.autopilot?.nextTarget.targetRPE ?? 7.0
    }

    private var activeTargetUnit: String {
        model.autopilot?.nextTarget.unit ?? String(localized: "lb", comment: "Default strength training load unit")
    }

    private var activeWorkoutExerciseNames: [String] {
        if let plan = model.activeSessionPlan, !plan.exercises.isEmpty {
            return plan.exercises.map(\.name)
        }
        var names: [String] = []
        if let replacementExercise {
            names.append(replacementExercise.name)
        } else if let autopilot = model.autopilot {
            names.append(autopilot.nextExerciseName)
        }
        if let nextWorkout = model.nextWorkout {
            names.append(contentsOf: nextWorkout.exercises.map(\.name))
        }
        names.append(nextExercisePreview)
        return names.reduce(into: []) { unique, name in
            guard !unique.contains(name) else { return }
            unique.append(name)
        }
    }

    private var formCheckExercise: FormCheckExercise? {
        return FormCheckExercise.infer(
            exerciseID: currentExerciseDefinition?.id ?? model.autopilot?.nextExerciseID ?? "",
            name: currentExerciseName
        )
    }

    private var nextExercisePreview: String {
        if let next = model.nextActiveSessionExercise {
            return next.name
        }
        if model.activeSessionPlan != nil {
            return String(localized: "Finish strong", comment: "Active workout final up-next fallback")
        }
        return replacementExercise == nil
            ? model.autopilot?.nextExerciseName
                ?? String(localized: "Accessory work", comment: "Active workout up next fallback")
            : model.autopilot?.nextExerciseName
                ?? String(localized: "Return to planned work", comment: "Active workout up next after replacement fallback")
    }

    private var nextExerciseTargetPreview: String {
        if let next = model.nextActiveSessionExercise {
            return "\(next.reps) reps - \(next.weight) \(activeTargetUnit)"
        }
        return "\(activeTargetReps) reps - \(Int(activeTargetWeight)) \(activeTargetUnit)"
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

    private var tomorrowWorkout: WeeklyWorkout? {
        guard !model.weeklyPlan.isEmpty else { return nil }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        let tomorrowWeekday = WeeklyWorkout.trainingWeekday(for: tomorrow)
        return model.weeklyPlan.first { $0.dayOfWeek == tomorrowWeekday }
    }

    private var todayWorkout: WeeklyWorkout? {
        guard !model.weeklyPlan.isEmpty else { return nil }
        let todayWeekday = WeeklyWorkout.trainingWeekday(for: .now)
        return model.weeklyPlan.first { $0.dayOfWeek == todayWeekday }
    }

    private var manualStarterPlan: WorkoutSessionPlan {
        starterPlan(for: resolvedSessionProfile)
    }

    private func starterPlan(for profile: WorkoutSessionProfile) -> WorkoutSessionPlan {
        switch profile {
        case .legDay:
            return legDayStarterPlan
        case .upperStrength:
            return upperStrengthStarterPlan
        case .shortSession:
            return shortSessionStarterPlan
        case .defaultProfile:
            return defaultStarterPlan
        }
    }

    private var resolvedSessionProfile: WorkoutSessionProfile {
        WorkoutSessionProfilePreferences(
            selectedProfile: WorkoutSessionProfile.parse(activeSessionProfileName),
            legDayRuleEnabled: isLegDayRuleEnabled,
            shortSessionRuleEnabled: isShortSessionRuleEnabled
        )
        .resolvedProfile(sessionMinutes: model.athlete.sessionTimeBudgetMinutes)
    }

    private var resolvedSessionProfileDisplayName: String {
        resolvedSessionProfile.displayName
    }

    private var defaultStarterPlan: WorkoutSessionPlan {
        let target = model.autopilot?.nextTarget
        let primaryName = model.autopilot?.nextExerciseName ?? String(
            localized: "Back Squat",
            comment: "Manual starter workout primary exercise"
        )
        let primaryWeight = Int(target?.weight ?? 135)
        let primaryReps = target?.repRange.lowerBound ?? 6
        let primaryRPE = Int((target?.targetRPE ?? 7).rounded())
        return WorkoutSessionPlan(
            title: String(localized: "Custom Workout", comment: "Manual starter workout title"),
            durationMinutes: model.athlete.sessionTimeBudgetMinutes,
            targetRPE: primaryRPE,
            exercises: [
                WeeklyWorkoutExercise(
                    name: primaryName,
                    sets: 4,
                    reps: primaryReps,
                    weight: primaryWeight,
                    targetRPE: primaryRPE,
                    restSeconds: restDurationSeconds
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Romanian Deadlift", comment: "Manual starter workout exercise"),
                    sets: 3,
                    reps: 8,
                    weight: max(45, primaryWeight - 40),
                    targetRPE: max(6, primaryRPE - 1),
                    restSeconds: 120
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Walking Lunge", comment: "Manual starter workout exercise"),
                    sets: 3,
                    reps: 10,
                    weight: 35,
                    targetRPE: max(6, primaryRPE - 1),
                    restSeconds: 90
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Plank", comment: "Manual starter workout exercise"),
                    sets: 3,
                    reps: 30,
                    weight: 0,
                    targetRPE: 6,
                    restSeconds: 60
                ),
            ]
        )
    }

    private var legDayStarterPlan: WorkoutSessionPlan {
        let target = model.autopilot?.nextTarget
        let primaryWeight = Int(target?.weight ?? 185)
        let primaryRPE = Int((target?.targetRPE ?? 7).rounded())
        return WorkoutSessionPlan(
            title: String(localized: "Leg Day", comment: "Leg Day session profile workout title"),
            durationMinutes: model.athlete.sessionTimeBudgetMinutes,
            targetRPE: primaryRPE,
            exercises: [
                WeeklyWorkoutExercise(
                    name: String(localized: "Back Squat", comment: "Leg Day starter exercise"),
                    sets: 4,
                    reps: 6,
                    weight: primaryWeight,
                    targetRPE: primaryRPE,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Romanian Deadlift", comment: "Leg Day starter exercise"),
                    sets: 3,
                    reps: 8,
                    weight: max(45, primaryWeight - 40),
                    targetRPE: max(6, primaryRPE - 1),
                    restSeconds: 120
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Walking Lunge", comment: "Leg Day starter exercise"),
                    sets: 3,
                    reps: 10,
                    weight: 35,
                    targetRPE: max(6, primaryRPE - 1),
                    restSeconds: 90
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Standing Calf Raise", comment: "Leg Day starter exercise"),
                    sets: 3,
                    reps: 12,
                    weight: 95,
                    targetRPE: 7,
                    restSeconds: 75
                ),
            ]
        )
    }

    private var upperStrengthStarterPlan: WorkoutSessionPlan {
        let target = model.autopilot?.nextTarget
        let primaryWeight = Int(target?.weight ?? 135)
        let primaryRPE = Int((target?.targetRPE ?? 7).rounded())
        return WorkoutSessionPlan(
            title: String(localized: "Upper Strength", comment: "Upper Strength session profile workout title"),
            durationMinutes: model.athlete.sessionTimeBudgetMinutes,
            targetRPE: primaryRPE,
            exercises: [
                WeeklyWorkoutExercise(
                    name: String(localized: "Bench Press", comment: "Upper Strength starter exercise"),
                    sets: 4,
                    reps: 5,
                    weight: primaryWeight,
                    targetRPE: primaryRPE,
                    restSeconds: 150
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Barbell Row", comment: "Upper Strength starter exercise"),
                    sets: 4,
                    reps: 6,
                    weight: max(45, primaryWeight - 20),
                    targetRPE: max(6, primaryRPE - 1),
                    restSeconds: 120
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Overhead Press", comment: "Upper Strength starter exercise"),
                    sets: 3,
                    reps: 6,
                    weight: max(45, primaryWeight - 60),
                    targetRPE: 7,
                    restSeconds: 120
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Lat Pulldown", comment: "Upper Strength starter exercise"),
                    sets: 3,
                    reps: 10,
                    weight: 90,
                    targetRPE: 7,
                    restSeconds: 90
                ),
            ]
        )
    }

    private var shortSessionStarterPlan: WorkoutSessionPlan {
        let target = model.autopilot?.nextTarget
        let primaryName = model.autopilot?.nextExerciseName ?? String(
            localized: "Goblet Squat",
            comment: "Short Session starter primary exercise"
        )
        let primaryWeight = Int(target?.weight ?? 45)
        return WorkoutSessionPlan(
            title: String(localized: "Short Session", comment: "Short Session profile workout title"),
            durationMinutes: min(model.athlete.sessionTimeBudgetMinutes, 35),
            targetRPE: 6,
            exercises: [
                WeeklyWorkoutExercise(
                    name: primaryName,
                    sets: 3,
                    reps: 8,
                    weight: primaryWeight,
                    targetRPE: 6,
                    restSeconds: 75
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Dumbbell Row", comment: "Short Session starter exercise"),
                    sets: 3,
                    reps: 10,
                    weight: 35,
                    targetRPE: 6,
                    restSeconds: 75
                ),
                WeeklyWorkoutExercise(
                    name: String(localized: "Plank", comment: "Short Session starter exercise"),
                    sets: 2,
                    reps: 30,
                    weight: 0,
                    targetRPE: 6,
                    restSeconds: 60
                ),
            ]
        )
    }

    private func exerciseDefinition(named name: String) -> ExerciseDefinition? {
        let normalized = normalizedExerciseName(name)
        return VolumeArcExerciseCatalog.all.first { exercise in
            normalizedExerciseName(exercise.name) == normalized
                || exercise.aliases.contains(where: { normalizedExerciseName($0) == normalized })
        }
    }

    private func normalizedExerciseName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }

    private func isCurrentExercise(index: Int, name: String) -> Bool {
        if model.activeSessionPlan != nil {
            return index == model.activeSessionExerciseIndex
        }
        return name == currentExerciseName
    }

    private func activeWorkoutMapAccessibilityLabel(name: String, isCurrent: Bool) -> String {
        if isCurrent {
            return String(
                localized: "\(name), current exercise",
                comment: "VoiceOver label for the current exercise in the active workout map"
            )
        }
        return String(
            localized: "Load \(name)",
            comment: "VoiceOver label for loading an exercise from the active workout map"
        )
    }
}

private enum WorkoutBuilderScheduleTarget: String, CaseIterable, Identifiable {
    case today
    case tomorrow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today:
            return String(localized: "Today", comment: "Workout builder schedule target today")
        case .tomorrow:
            return String(localized: "Tomorrow", comment: "Workout builder schedule target tomorrow")
        }
    }

    var actionTitle: String {
        switch self {
        case .today:
            return String(localized: "Schedule Today", comment: "Workout builder schedule today button")
        case .tomorrow:
            return String(localized: "Schedule Tomorrow", comment: "Workout builder schedule tomorrow button")
        }
    }

    var date: Date {
        switch self {
        case .today:
            return .now
        case .tomorrow:
            return Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        }
    }

    var successMessage: String {
        switch self {
        case .today:
            return String(localized: "It is now first in Workouts.", comment: "Toast body after scheduling builder workout today")
        case .tomorrow:
            return String(localized: "It is now in this week's plan.", comment: "Toast body after scheduling builder workout tomorrow")
        }
    }
}

private struct WorkoutBuilderDraft: Equatable {
    var title: String
    var profile: WorkoutSessionProfile
    var durationMinutes: Int
    var targetRPE: Int
    var exercises: [WorkoutBuilderExerciseDraft]

    init(
        title: String = String(localized: "Custom Workout", comment: "Workout builder default title"),
        profile: WorkoutSessionProfile = .defaultProfile,
        durationMinutes: Int = 45,
        targetRPE: Int = 7,
        exercises: [WorkoutBuilderExerciseDraft] = [WorkoutBuilderExerciseDraft.defaultRow]
    ) {
        self.title = title
        self.profile = profile
        self.durationMinutes = durationMinutes
        self.targetRPE = targetRPE
        self.exercises = exercises
    }

    init(plan: WorkoutSessionPlan, profile: WorkoutSessionProfile) {
        self.init(
            title: plan.title,
            profile: profile,
            durationMinutes: plan.durationMinutes ?? 45,
            targetRPE: plan.targetRPE ?? 7,
            exercises: plan.exercises.isEmpty
                ? [WorkoutBuilderExerciseDraft.defaultRow]
                : plan.exercises.map(WorkoutBuilderExerciseDraft.init(exercise:))
        )
    }

    var plan: WorkoutSessionPlan {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanExercises = exercises.compactMap(\.exercise)
        return WorkoutSessionPlan(
            title: cleanTitle.isEmpty
                ? String(localized: "Custom Workout", comment: "Workout builder fallback plan title")
                : cleanTitle,
            durationMinutes: max(10, min(durationMinutes, 180)),
            targetRPE: max(1, min(targetRPE, 10)),
            exercises: cleanExercises.isEmpty
                ? [WorkoutBuilderExerciseDraft.defaultRow].compactMap(\.exercise)
                : cleanExercises
        )
    }

    mutating func applyTemplate(_ plan: WorkoutSessionPlan, profile: WorkoutSessionProfile) {
        self = WorkoutBuilderDraft(plan: plan, profile: profile)
    }

    func coachReviewPrompt(readinessScore: Int) -> String {
        let exerciseLines = plan.exercises.map { exercise in
            "- \(exercise.name): \(exercise.sets) sets of \(exercise.reps) reps, " +
                "\(exercise.weight) lb, RPE \(exercise.targetRPE), rest \(exercise.restSeconds)s"
        }
        .joined(separator: "\n")

        return String(
            localized: """
            Review this workout draft for safety, flow, and effectiveness before I start it.

            Profile: \(profile.displayName)
            Readiness: \(readinessScore)/100
            Duration: \(plan.durationMinutes ?? durationMinutes) minutes
            Target RPE: \(plan.targetRPE ?? targetRPE)

            Draft:
            \(exerciseLines)

            Give specific changes if needed. If it is ready, return a concise startable plan using exercise lines with sets and reps.
            """,
            comment: "Prompt sent from the manual workout builder for coach review"
        )
    }
}

private struct WorkoutBuilderExerciseDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var sets: Int
    var reps: Int
    var weight: Int
    var targetRPE: Int
    var restSeconds: Int

    init(
        id: UUID = UUID(),
        name: String,
        sets: Int,
        reps: Int,
        weight: Int,
        targetRPE: Int,
        restSeconds: Int
    ) {
        self.id = id
        self.name = name
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.targetRPE = targetRPE
        self.restSeconds = restSeconds
    }

    init(exercise: WeeklyWorkoutExercise) {
        self.init(
            name: exercise.name,
            sets: exercise.sets,
            reps: exercise.reps,
            weight: exercise.weight,
            targetRPE: exercise.targetRPE,
            restSeconds: exercise.restSeconds
        )
    }

    static var defaultRow: WorkoutBuilderExerciseDraft {
        WorkoutBuilderExerciseDraft(
            name: String(localized: "Back Squat", comment: "Workout builder default exercise"),
            sets: 4,
            reps: 6,
            weight: 135,
            targetRPE: 7,
            restSeconds: 150
        )
    }

    var exercise: WeeklyWorkoutExercise? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return nil }
        return WeeklyWorkoutExercise(
            name: String(cleanName.prefix(60)),
            sets: max(1, min(sets, 10)),
            reps: max(1, min(reps, 60)),
            weight: max(0, min(weight, 900)),
            targetRPE: max(1, min(targetRPE, 10)),
            restSeconds: max(15, min(restSeconds, 600))
        )
    }
}

private struct WorkoutBuilderSheet: View {
    @Binding var draft: WorkoutBuilderDraft
    let templateForProfile: (WorkoutSessionProfile) -> WorkoutSessionPlan
    let onStart: (WorkoutBuilderDraft) -> Void
    let onSchedule: (WorkoutBuilderDraft, WorkoutBuilderScheduleTarget) -> Void
    let onAskCoachReview: (WorkoutBuilderDraft) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var scheduleTarget: WorkoutBuilderScheduleTarget = .today

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.xl) {
                    overviewCard
                    exerciseEditor
                    actionCard
                }
                .padding(VA.Space.lg)
                .padding(.bottom, VA.Space.xxl)
            }
            .background(VA.Colors.surfaceGrouped)
            .navigationTitle(String(localized: "Workout Builder", comment: "Workout builder sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", comment: "Dismiss workout builder")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("workouts.builder.sheet")
    }

    private var overviewCard: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "SESSION", comment: "Workout builder overview section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.6)

                TextField(
                    String(localized: "Workout name", comment: "Workout builder title field placeholder"),
                    text: $draft.title
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("workouts.builder.title")

                Picker(String(localized: "Session Profile", comment: "Workout builder profile picker"), selection: $draft.profile) {
                    ForEach(WorkoutSessionProfile.allCases, id: \.self) { profile in
                        Text(profile.displayName).tag(profile)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("workouts.builder.profile")

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VA.Space.md) {
                        durationStepper
                        rpeStepper
                    }
                    VStack(spacing: VA.Space.md) {
                        durationStepper
                        rpeStepper
                    }
                }

                VAButton(
                    String(localized: "Load Profile Template", comment: "Workout builder load profile template button"),
                    icon: "arrow.clockwise",
                    style: .secondary,
                    accessibilityIdentifier: "workouts.builder.loadProfile"
                ) {
                    draft.applyTemplate(templateForProfile(draft.profile), profile: draft.profile)
                    VAHaptics.selection()
                }
            }
        }
    }

    private var durationStepper: some View {
        Stepper(value: $draft.durationMinutes, in: 10...180, step: 5) {
            Text(String(
                localized: "\(draft.durationMinutes) min",
                comment: "Workout builder duration stepper value"
            ))
            .font(VA.Typography.footnote)
            .foregroundStyle(VA.Colors.textPrimary)
        }
    }

    private var rpeStepper: some View {
        Stepper(value: $draft.targetRPE, in: 1...10) {
            Text(String(
                localized: "RPE \(draft.targetRPE)",
                comment: "Workout builder target RPE stepper value"
            ))
            .font(VA.Typography.footnote)
            .foregroundStyle(VA.Colors.textPrimary)
        }
    }

    private var exerciseEditor: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader(
                String(localized: "Exercises", comment: "Workout builder exercises section title"),
                subtitle: String(
                    localized: "Edit, reorder, add, or remove movements before starting.",
                    comment: "Workout builder exercises section subtitle"
                )
            )

            ForEach($draft.exercises) { $exercise in
                WorkoutBuilderExerciseRow(
                    exercise: $exercise,
                    canDelete: draft.exercises.count > 1,
                    canMoveUp: draft.exercises.first?.id != exercise.id,
                    canMoveDown: draft.exercises.last?.id != exercise.id,
                    onMoveUp: { moveExercise(id: exercise.id, direction: -1) },
                    onMoveDown: { moveExercise(id: exercise.id, direction: 1) },
                    onDelete: { deleteExercise(id: exercise.id) }
                )
            }

            quickAddMenu
        }
    }

    private var quickAddMenu: some View {
        Menu {
            ForEach(Self.quickAddExercises, id: \.name) { exercise in
                Button(exercise.name) {
                    draft.exercises.append(WorkoutBuilderExerciseDraft(exercise: exercise))
                    VAHaptics.selection()
                }
            }
            Button(String(localized: "Blank row", comment: "Workout builder add blank exercise row")) {
                draft.exercises.append(WorkoutBuilderExerciseDraft.defaultRow)
                VAHaptics.selection()
            }
        } label: {
            Label(
                String(localized: "Add Exercise", comment: "Workout builder add exercise menu"),
                systemImage: "plus"
            )
            .font(VA.Typography.footnote)
            .foregroundStyle(VA.Colors.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(VA.Colors.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: VA.Radius.md))
        }
        .accessibilityIdentifier("workouts.builder.addExercise")
    }

    private var actionCard: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                Picker(String(localized: "Schedule", comment: "Workout builder schedule picker"), selection: $scheduleTarget) {
                    ForEach(WorkoutBuilderScheduleTarget.allCases) { target in
                        Text(target.title).tag(target)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("workouts.builder.scheduleTarget")

                VAButton(
                    String(localized: "Start Workout", comment: "Workout builder start action"),
                    icon: "play.fill",
                    style: .primary,
                    accessibilityIdentifier: "workouts.builder.start"
                ) {
                    onStart(draft)
                    dismiss()
                }
                VAButton(
                    scheduleTarget.actionTitle,
                    icon: "calendar.badge.plus",
                    style: .secondary,
                    accessibilityIdentifier: "workouts.builder.schedule"
                ) {
                    onSchedule(draft, scheduleTarget)
                }
                VAButton(
                    String(localized: "Ask Coach to Review", comment: "Workout builder coach review action"),
                    icon: "brain.head.profile",
                    style: .secondary,
                    accessibilityIdentifier: "workouts.builder.review"
                ) {
                    onAskCoachReview(draft)
                    dismiss()
                }
            }
        }
    }

    private func moveExercise(id: UUID, direction: Int) {
        guard let index = draft.exercises.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + direction
        guard draft.exercises.indices.contains(newIndex) else { return }
        draft.exercises.swapAt(index, newIndex)
        VAHaptics.selection()
    }

    private func deleteExercise(id: UUID) {
        guard draft.exercises.count > 1 else { return }
        draft.exercises.removeAll { $0.id == id }
        VAHaptics.selection()
    }

    private static let quickAddExercises: [WeeklyWorkoutExercise] = [
        WeeklyWorkoutExercise(name: "Bench Press", sets: 4, reps: 5, weight: 135, targetRPE: 7, restSeconds: 150),
        WeeklyWorkoutExercise(name: "Barbell Row", sets: 4, reps: 6, weight: 115, targetRPE: 7, restSeconds: 120),
        WeeklyWorkoutExercise(name: "Romanian Deadlift", sets: 3, reps: 8, weight: 135, targetRPE: 7, restSeconds: 120),
        WeeklyWorkoutExercise(name: "Lat Pulldown", sets: 3, reps: 10, weight: 90, targetRPE: 7, restSeconds: 90),
        WeeklyWorkoutExercise(name: "Plank", sets: 3, reps: 30, weight: 0, targetRPE: 6, restSeconds: 60),
    ]
}

private struct WorkoutBuilderExerciseRow: View {
    @Binding var exercise: WorkoutBuilderExerciseDraft
    let canDelete: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(spacing: VA.Space.sm) {
                    TextField(
                        String(localized: "Exercise", comment: "Workout builder exercise name placeholder"),
                        text: $exercise.name
                    )
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("workouts.builder.exercise.name")

                    Menu {
                        Button(String(localized: "Move Up", comment: "Workout builder move exercise up"), action: onMoveUp)
                            .disabled(!canMoveUp)
                        Button(String(localized: "Move Down", comment: "Workout builder move exercise down"), action: onMoveDown)
                            .disabled(!canMoveDown)
                        Button(
                            String(localized: "Delete Exercise", comment: "Workout builder delete exercise"),
                            role: .destructive,
                            action: onDelete
                        )
                        .disabled(!canDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(String(localized: "Exercise actions", comment: "Workout builder exercise actions menu"))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VA.Space.sm) { controls }
                    VStack(spacing: VA.Space.sm) { controls }
                }
            }
        }
    }

    @ViewBuilder
    private var controls: some View {
        builderStepper(
            label: String(localized: "Sets", comment: "Workout builder sets stepper"),
            value: $exercise.sets,
            range: 1...10
        )
        builderStepper(
            label: String(localized: "Reps", comment: "Workout builder reps stepper"),
            value: $exercise.reps,
            range: 1...60
        )
        builderStepper(
            label: String(localized: "lb", comment: "Workout builder weight stepper"),
            value: $exercise.weight,
            range: 0...900,
            step: 5
        )
        builderStepper(
            label: String(localized: "RPE", comment: "Workout builder exercise RPE stepper"),
            value: $exercise.targetRPE,
            range: 1...10
        )
        builderStepper(
            label: String(localized: "Rest", comment: "Workout builder rest stepper"),
            value: $exercise.restSeconds,
            range: 15...600,
            step: 15
        )
    }

    private func builderStepper(
        label: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1
    ) -> some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(label.uppercased())
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.6)
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)")
                    .font(VA.Typography.monoDigit)
                    .foregroundStyle(VA.Colors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveWorkoutStepper: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    let accessibilityPrefix: String
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(label.uppercased())
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.6)
            HStack(spacing: VA.Space.xs) {
                Button {
                    onChange(max(range.lowerBound, value - step))
                } label: {
                    Image(systemName: "minus")
                        .font(VA.Typography.caption)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(String(localized: "Decrease \(label)", comment: "Live workout stepper decrement"))
                .accessibilityIdentifier("\(accessibilityPrefix).decrement")

                Text("\(value)")
                    .font(VA.Typography.monoDigit)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .frame(minWidth: 40)
                    .accessibilityIdentifier("\(accessibilityPrefix).value")

                Button {
                    onChange(min(range.upperBound, value + step))
                } label: {
                    Image(systemName: "plus")
                        .font(VA.Typography.caption)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel(String(localized: "Increase \(label)", comment: "Live workout stepper increment"))
                .accessibilityIdentifier("\(accessibilityPrefix).increment")
            }
            .foregroundStyle(VA.Colors.textPrimary)
            .background(VA.Colors.textTertiary.opacity(0.10), in: RoundedRectangle(cornerRadius: VA.Radius.sm))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActiveWorkoutMapRow: View {
    let index: Int
    let name: String
    let isCurrent: Bool
    let isSelectable: Bool

    var body: some View {
        HStack(spacing: VA.Space.sm) {
            Text("\(index + 1)")
                .font(VA.Typography.caption)
                .foregroundStyle(isCurrent ? VA.Colors.textOnPrimary : VA.Colors.textSecondary)
                .frame(width: 24, height: 24)
                .background(
                    isCurrent
                        ? VA.Colors.primary
                        : VA.Colors.textTertiary.opacity(0.18),
                    in: Circle()
                )
            Text(name)
                .font(VA.Typography.footnote)
                .foregroundStyle(isCurrent ? VA.Colors.textPrimary : VA.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
            Spacer()
            if isCurrent {
                WorkoutChip(
                    text: String(localized: "Now", comment: "Active workout current exercise chip"),
                    tone: .primary
                )
            } else if isSelectable {
                Label(
                    String(localized: "Load", comment: "Active workout map load exercise chip"),
                    systemImage: "arrow.right.circle"
                )
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.primary)
            }
        }
        .padding(.vertical, VA.Space.xs)
        .padding(.horizontal, VA.Space.xs)
        .background(
            isCurrent
                ? VA.Colors.primary.opacity(0.08)
                : VA.Colors.textTertiary.opacity(isSelectable ? 0.08 : 0),
            in: RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}

private struct LiveWorkoutActionChip: View {
    let title: String
    let icon: String
    let accessibilityIdentifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textPrimary)
                .padding(.horizontal, VA.Space.sm)
                .frame(height: 32)
                .background(VA.Colors.primary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct ActiveExerciseGuideView: View {
    let exercise: ExerciseDefinition?
    let fallbackExerciseName: String
    let fallbackCue: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.xl) {
                    illustration
                    cueSection
                    formCheckContext
                }
                .padding(VA.Space.lg)
                .padding(.bottom, VA.Space.xxl)
            }
            .background(VA.Colors.surfaceGrouped)
            .navigationTitle(exercise?.name ?? fallbackExerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "Done", comment: "Dismiss active exercise guide")) {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .accessibilityIdentifier("workouts.exerciseGuide.sheet")
    }

    @ViewBuilder
    private var illustration: some View {
        if let exercise {
            VACard(style: .flat) {
                Image(exercise.illustrationAssetName, bundle: .main)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: VA.Space.exerciseIllustrationMinHeight)
                    .clipShape(RoundedRectangle(cornerRadius: VA.Radius.md))
                    .accessibilityLabel(String(
                        localized: "\(exercise.name) exercise illustration",
                        comment: "Accessibility label for active workout exercise illustration"
                    ))
            }
        }
    }

    private var cueSection: some View {
        VACard(style: .glass) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                Text(String(localized: "CUES", comment: "Active exercise guide cues section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.6)
                ForEach(cues, id: \.self) { cue in
                    HStack(alignment: .top, spacing: VA.Space.sm) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.primary)
                            .accessibilityHidden(true)
                        Text(cue)
                            .font(VA.Typography.body)
                            .foregroundStyle(VA.Colors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var formCheckContext: some View {
        VACard(style: .flat) {
            VStack(alignment: .leading, spacing: VA.Space.sm) {
                Text(String(localized: "FORM CHECK REFERENCE", comment: "Active exercise guide form check section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.6)
                Text(String(
                    localized: """
                    Form Check uses on-device camera landmarks, lift-specific movement heuristics, and the exercise catalog cues above. \
                    If the camera cannot see enough of the rep, VolumeArc marks the result inconclusive instead of guessing.
                    """,
                    comment: "Explanation of active workout Form Check reference logic"
                ))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var cues: [String] {
        let catalogCues = exercise?.cues ?? []
        if !catalogCues.isEmpty { return Array(catalogCues.prefix(4)) }
        if let fallbackCue, !fallbackCue.isEmpty { return [fallbackCue] }
        return [
            String(localized: "Use a load you can control without pain.", comment: "Fallback active exercise guide cue"),
            String(localized: "Stop the set if the movement changes or symptoms show up.", comment: "Fallback active exercise guide cue"),
        ]
    }
}
#endif
