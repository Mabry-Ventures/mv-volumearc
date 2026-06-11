#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Coach tab — chat interface with the coach.
public struct CoachView: View { // swiftlint:disable:this type_body_length
    @ObservedObject var model: WorkoutDashboardModel
    @ObservedObject var navigation: DashboardNavigationModel
    @EnvironmentObject private var toastPresenter: VAToastPresenter
    @State private var draftMessage: String = ""
    @State private var showPlanDraft: Bool = false
    @State private var expandedExerciseID: String?
    @State private var planDraft: CoachPlanDraft = .default
    @FocusState private var inputFocused: Bool

    public init(model: WorkoutDashboardModel, navigation: DashboardNavigationModel) {
        self.model = model
        self.navigation = navigation
    }

    @_spi(Testing) public init(
        model: WorkoutDashboardModel,
        navigation: DashboardNavigationModel,
        showsPlanDraftForSnapshot: Bool
    ) {
        self.model = model
        self.navigation = navigation
        self._showPlanDraft = State(initialValue: showsPlanDraftForSnapshot)
    }

    public var body: some View {
        VStack(spacing: 0) {
            coachHeader
            messageList
        }
        // Bottom controls ride a safe-area inset, not VStack siblings, so
        // the message list is inset by the stack's measured height: draft
        // content can always scroll clear of the rail/composer (PR #363:
        // as siblings, straddling rows fed center-taps to the rail chips).
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Opaque backdrop: scroll content slides underneath, and the
            // notice tints are translucent washes over this surface.
            VStack(spacing: 0) {
                fallbackNotice
                voiceNotice
                latestWorkoutHandoff
                quickPromptRail
                composer
            }
            .background(VA.Colors.surfaceGrouped)
        }
        .background(VA.Colors.surfaceGrouped)
        .navigationTitle(DashboardTab.coach.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    dismissKeyboard()
                } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel(String(
                    localized: "Dismiss keyboard",
                    comment: "Coach composer keyboard toolbar dismiss button"
                ))
                .accessibilityIdentifier("coach.keyboardDismiss")
            }
        }
        .onAppear {
            if let prompt = navigation.coachPrompt, !prompt.isEmpty {
                draftMessage = prompt
                showPlanDraft = isPlanningPrompt(prompt)
                navigation.clearCoachPrompt()
            }
        }
    }

    // MARK: - Header

    private var coachHeader: some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(DashboardTab.coach.title)
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
            Text(coachContextLine)
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, VA.Space.lg)
        .padding(.top, VA.Space.sm)
        .padding(.bottom, VA.Space.md)
        .background(VA.Colors.surfaceGrouped)
    }

    // MARK: - Message list

    @ViewBuilder
    private var messageList: some View {
        if model.coachMessages.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.lg) {
                    // The draft leads when present: the athlete just asked
                    // to plan, so the actionable card belongs above the
                    // welcome copy and its exercise rows start in-viewport
                    // (PR #363: below the welcome card, the VOL-275 footer
                    // buried row 0 under the composer for good).
                    if showPlanDraft {
                        planningCard
                    }
                    welcomeCard
                }
                .padding(VA.Space.lg)
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissKeyboard()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: VA.Space.md) {
                        if showPlanDraft {
                            planningCard
                        }
                        ForEach(Array(model.coachMessages.enumerated()), id: \.element.id) { offset, message in
                            VACoachBubble(
                                sender: message.sender == .user ? .user : .coach,
                                content: message.content
                            )
                            .id(message.id)
                            // VOL-99: tag the first coach reply bubble
                            // ONLY once its content is non-empty so
                            // `testCoachFirstTokenLatency` can measure
                            // first-token latency via XCUITest
                            // `waitForExistence`. The bubble is
                            // pre-inserted with empty content when
                            // streaming starts, so gating the ID on
                            // "coach && !empty" produces a clean rising
                            // edge at first token.
                            .accessibilityIdentifier(
                                message.sender == .coach
                                    && offset == 1
                                    && !message.content.isEmpty
                                    ? "coach.firstResponse"
                                    : "coach.message.\(offset)"
                            )
                            if message.sender == .coach,
                               !model.isCoachStreaming,
                               message.id != latestCoachWorkoutPlanMessageID,
                               let plan = coachWorkoutPlan(from: message.content) {
                                coachWorkoutHandoffCard(plan)
                            }
                        }
                        if model.isCoachStreaming {
                            VACoachBubble(
                                sender: .coach,
                                content: String(
                                    localized: "Thinking…",
                                    comment: "Placeholder shown in the coach bubble while streaming a response"
                                ),
                                isStreaming: true
                            )
                            .accessibilityIdentifier("coach.streamingIndicator")
                        }
                    }
                    .padding(VA.Space.lg)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissKeyboard()
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: model.coachMessages.count) { _, _ in
                    withAnimation(VAAnimation.standard) {
                        proxy.scrollTo(model.coachMessages.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeCard: some View {
        VACard(style: .elevated) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(alignment: .top, spacing: VA.Space.md) {
                    Image(systemName: "waveform.and.mic")
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: 44, height: 44)
                        .background(VA.Colors.primary.opacity(0.12), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: VA.Space.xs) {
                        Text(String(localized: "Your Coach", comment: "Coach welcome card title"))
                            .font(VA.Typography.title2)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(String(
                            localized: """
                                Ask anything about your training — load selection, form cues, \
                                recovery, or tomorrow's plan. I’ll ground the answer in your \
                                recent sessions and readiness.
                                """,
                            comment: "Coach welcome card description"
                        ))
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var planningCard: some View {
        CoachPlanningCard(
            plan: $planDraft,
            expandedExerciseID: $expandedExerciseID,
            sendPlanFeedback: sendPlanFeedback(_:),
            schedulePlan: schedulePlanDraft,
            startNow: startPlanNow,
            saveTemplate: savePlanDraftAsTemplate
        )
    }

    private func coachWorkoutHandoffCard(_ plan: WorkoutSessionPlan) -> some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(alignment: .center, spacing: VA.Space.md) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: VA.Space.avatar, height: VA.Space.avatar)
                        .background(VA.Colors.primary.opacity(VA.Opacity.subtleFill), in: Circle())
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: VA.Space.xs) {
                        Text(String(localized: "Start this workout", comment: "Coach workout handoff card title"))
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text(coachWorkoutPlanSummary(plan))
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: VA.Space.sm)
                }

                VAButton(
                    model.isSessionActive
                        ? String(localized: "Open Active Workout", comment: "Coach handoff button when a workout is already active")
                        : String(localized: "Start Workout", comment: "Coach response handoff start workout button"),
                    icon: model.isSessionActive ? "arrow.forward.circle.fill" : "play.fill",
                    style: .primary,
                    accessibilityIdentifier: "coach.startRecommendedWorkout"
                ) {
                    startCoachRecommendedWorkout(plan)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.workoutHandoff")
    }

    @ViewBuilder
    private var latestWorkoutHandoff: some View {
        if let plan = latestCoachWorkoutPlan {
            HStack(alignment: .center, spacing: VA.Space.md) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(VA.Typography.headline)
                    .foregroundStyle(VA.Colors.primary)
                    .frame(width: VA.Space.xxl, height: VA.Space.xxl)
                    .background(VA.Colors.primary.opacity(VA.Opacity.subtleFill), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(String(localized: "Workout ready", comment: "Pinned Coach workout handoff title"))
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(coachWorkoutPlanSummary(plan))
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }

                Spacer(minLength: VA.Space.sm)

                Button {
                    startCoachRecommendedWorkout(plan)
                } label: {
                    Label(
                        model.isSessionActive
                            ? String(localized: "Open", comment: "Pinned Coach workout handoff open active workout button")
                            : String(localized: "Start", comment: "Pinned Coach workout handoff start button"),
                        systemImage: model.isSessionActive ? "arrow.forward.circle.fill" : "play.fill"
                    )
                    .font(VA.Typography.button)
                    .foregroundStyle(VA.Colors.textOnPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, VA.Space.md)
                    .frame(minHeight: VA.Space.cameraChromeControl)
                    .background(VA.Colors.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    model.isSessionActive
                        ? String(
                            localized: "Open active workout",
                            comment: "Pinned Coach workout handoff open button accessibility label"
                        )
                        : String(
                            localized: "Start recommended workout",
                            comment: "Pinned Coach workout handoff start button accessibility label"
                        )
                )
                .accessibilityIdentifier("coach.startRecommendedWorkout.pinned")
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.sm)
            .background(VA.Colors.surfacePrimary)
            .overlay(alignment: .top) {
                Divider().background(VA.Colors.textTertiary.opacity(VA.Opacity.subtleSeparator))
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coach.workoutHandoff.pinned")
        }
    }

    private var quickPromptRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VA.Space.sm) {
                ForEach(suggestedPrompts) { suggestion in
                    Button {
                        draftMessage = suggestion.title
                        showPlanDraft = showPlanDraft || isPlanningPrompt(suggestion.title)
                        inputFocused = true
                        VAHaptics.tap()
                    } label: {
                        Label {
                            Text(suggestion.title)
                        .font(VA.Typography.footnote)
                        .lineLimit(1)
                        } icon: {
                            Image(systemName: suggestion.systemImage)
                                .font(VA.Typography.caption)
                                .accessibilityHidden(true)
                        }
                        .foregroundStyle(VA.Colors.textOnPrimary)
                        .padding(.horizontal, VA.Space.md)
                        .frame(height: VA.Space.xxl)
                        .background(VA.Colors.primary, in: Capsule())
                        .overlay {
                            Capsule()
                                .stroke(VA.Colors.textOnPrimary.opacity(0.28), lineWidth: 1)
                        }
                        .vaShadow(.sm)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(
                        localized: "Suggested prompt: \(suggestion.title)",
                        comment: "VoiceOver label for a Coach suggested prompt chip"
                    ))
                    .accessibilityIdentifier("coach.suggestion.\(suggestion.id)")
                }
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.sm)
        }
        .background(VA.Colors.surfaceGrouped)
    }

    @ViewBuilder
    private var fallbackNotice: some View {
        if let notice = model.coachFallbackNotice {
            HStack(alignment: .firstTextBaseline, spacing: VA.Space.sm) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(VA.Colors.warning)
                    .accessibilityHidden(true)
                Text(notice)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VA.Colors.warning.opacity(0.12))
            .accessibilityIdentifier("coach.fallbackBanner")
        }
    }

    @ViewBuilder
    private var voiceNotice: some View {
        if let notice = model.voiceNotice {
            HStack(alignment: .firstTextBaseline, spacing: VA.Space.sm) {
                Image(systemName: "mic.slash")
                    .foregroundStyle(VA.Colors.warning)
                    .accessibilityHidden(true)
                Text(notice)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VA.Colors.warning.opacity(0.12))
            .accessibilityIdentifier("coach.voiceNotice")
        }
    }

    private var suggestedPrompts: [SuggestedCoachPrompt] {
        [
            SuggestedCoachPrompt(
                id: "planTomorrow",
                title: String(localized: "Plan tomorrow", comment: "Suggested coach prompt to co-design tomorrow's workout"),
                systemImage: "calendar.badge.plus"
            ),
            SuggestedCoachPrompt(
                id: "restOrTrain",
                title: String(localized: "Rest or train?", comment: "Suggested coach prompt about whether to rest or train"),
                systemImage: "heart.text.square.fill"
            ),
            SuggestedCoachPrompt(
                id: "formCheck",
                title: String(localized: "Form check", comment: "Suggested coach prompt for lifting form"),
                systemImage: "figure.strengthtraining.traditional"
            ),
            SuggestedCoachPrompt(
                id: "substituteExercise",
                title: String(localized: "Substitute exercise", comment: "Suggested coach prompt for exercise substitution"),
                systemImage: "arrow.triangle.2.circlepath"
            ),
        ]
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            HStack(alignment: .bottom, spacing: VA.Space.sm) {
                TextField(
                    String(localized: "Ask the coach", comment: "Coach composer placeholder"),
                    text: $draftMessage,
                    axis: .vertical
                )
                    .textFieldStyle(.plain)
                    .font(VA.Typography.body)
                    .padding(.horizontal, VA.Space.md)
                    .padding(.vertical, VA.Space.sm)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    // VOL-99: perf test types into this field before timing
                    // the first-token latency; identifier lets XCUITest find
                    // it in the composer HStack.
                    .accessibilityIdentifier("coach.input")

                Button {
                    sendVoiceMessage()
                } label: {
                    Image(systemName: model.isVoiceTurnActive ? "waveform" : "mic.fill")
                        .font(VA.Typography.button)
                        .foregroundStyle(canStartVoice ? VA.Colors.primary : VA.Colors.textTertiary)
                        .frame(width: VA.Space.xxl, height: VA.Space.xxl)
                        .background(
                            VA.Colors.primary.opacity(
                                canStartVoice ? VA.Opacity.iconPanelAccent : VA.Opacity.subtleSeparator
                            ),
                            in: Circle()
                        )
                }
                .disabled(!canStartVoice)
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    localized: "Voice coach",
                    comment: "Coach composer voice button accessibility label"
                ))
                .accessibilityHint(String(
                    localized: "Starts a quick voice coach check or sends the current prompt.",
                    comment: "Coach composer voice button accessibility hint"
                ))
                .accessibilityIdentifier("coach.voice")

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(VA.Typography.button)
                        .foregroundStyle(canSend ? VA.Colors.textOnPrimary : VA.Colors.textTertiary)
                        .frame(width: VA.Space.xxl, height: VA.Space.xxl)
                        .background(
                            canSend ? VA.Colors.primary : VA.Colors.textTertiary.opacity(VA.Opacity.subtleFill),
                            in: Circle()
                        )
                }
                .disabled(!canSend)
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Send", comment: "Coach composer send button accessibility label"))
                // VOL-99: perf test taps this to dispatch the coach request
                // and start the first-token latency measurement.
                .accessibilityIdentifier("coach.send")
            }
            .padding(.leading, VA.Space.md)
            .padding(.trailing, VA.Space.xs)
            .padding(.vertical, VA.Space.xs)
            .vaGlassBackground(in: Capsule())

            Text(String(
                localized: "Some answers may use secure cloud processing. Recommendations are not medical advice.",
                comment: "Persistent Coach safety disclaimer under the composer"
            ))
            .font(VA.Typography.caption)
            .foregroundStyle(VA.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("coach.safetyDisclaimer")
        }
        .padding(.horizontal, VA.Space.lg)
        .padding(.bottom, VA.Space.lg)
        .background(VA.Colors.surfaceGrouped)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.composer")
    }

    // MARK: - Derived values

    private var coachContextLine: String {
        let workout = model.nextWorkout?.title ?? String(localized: "Next workout", comment: "Coach header fallback workout")
        let exercise = model.autopilot?.nextExerciseName ?? String(localized: "Targets pending", comment: "Coach header fallback exercise")
        return String(
            localized: "Readiness \(model.readiness.score) · \(workout) · \(exercise)",
            comment: "Coach header context line"
        )
    }

    private var canSend: Bool {
        !draftMessage.trimmingCharacters(in: .whitespaces).isEmpty && !model.isCoachStreaming
    }

    private var canStartVoice: Bool {
        !model.isCoachStreaming
            && !model.isVoiceTurnActive
    }

    private var voicePromptText: String {
        let typedPrompt = draftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedPrompt.isEmpty {
            return typedPrompt
        }
        if VolumeArcRuntimeFlags.isDeterministicMode,
           let fixture = VolumeArcRuntimeFlags.voicePromptTranscriptFixture {
            return fixture
        }
        return String(
            localized: "Give me a quick coach check for this session.",
            comment: "Default voice coach prompt used when the composer is empty"
        )
    }

    private func coachWorkoutPlan(from response: String) -> WorkoutSessionPlan? {
        // VOL-284: pure extraction only — this runs per message per render
        // (transcript loop + pinned handoff), so it must stay cheap. The
        // inline preview surfaces only the move count and first lift, never
        // load figures, and every coach-sourced schedule re-clamps at the
        // `scheduleWorkoutPlan` backstop, so deferring the clamp to
        // scheduling loses nothing and keeps repository work off the
        // render path (the round-3 UI hangs came from clamping here).
        CoachWorkoutPlanExtractor.plan(
            from: response,
            title: String(localized: "Coach Workout", comment: "Title for a coach response converted into a workout")
        )
    }

    private var latestCoachWorkoutPlan: WorkoutSessionPlan? {
        latestCoachWorkoutPlanPair?.plan
    }

    private var latestCoachWorkoutPlanMessageID: UUID? {
        latestCoachWorkoutPlanPair?.messageID
    }

    private var latestCoachWorkoutPlanPair: (messageID: UUID, plan: WorkoutSessionPlan)? {
        guard !model.isCoachStreaming else { return nil }
        for message in model.coachMessages.reversed() where message.sender == .coach {
            if let plan = coachWorkoutPlan(from: message.content) {
                return (message.id, plan)
            }
        }
        return nil
    }

    private func coachWorkoutPlanSummary(_ plan: WorkoutSessionPlan) -> String {
        guard let firstExercise = plan.exercises.first else {
            return String(localized: "Ready to review in Workouts.", comment: "Coach workout handoff empty summary")
        }
        return String(
            localized: "^[\(plan.exercises.count) move](inflect: true) - \(firstExercise.name) first",
            comment: "Coach workout handoff summary with exercise count and first lift"
        )
    }

    private func sendMessage() {
        let prompt = draftMessage
        draftMessage = ""
        showPlanDraft = showPlanDraft || isPlanningPrompt(prompt)
        VAHaptics.tap()
        Task {
            await model.askCoach(prompt)
            VAHaptics.coachResponse()
        }
    }

    private func sendVoiceMessage() {
        let prompt = voicePromptText
        let previousDraft = draftMessage
        showPlanDraft = showPlanDraft || isPlanningPrompt(prompt)
        dismissKeyboard()
        VAHaptics.tap()
        Task {
            let sent = await model.askCoachByVoice(prompt)
            if sent {
                draftMessage = ""
                VAHaptics.coachResponse()
            } else {
                draftMessage = previousDraft
                VAHaptics.error()
            }
        }
    }

    private func startCoachRecommendedWorkout(_ plan: WorkoutSessionPlan) {
        Task {
            VAHaptics.sessionStart()
            dismissKeyboard()
            guard !model.isSessionActive else {
                navigation.selectedTab = .workouts
                return
            }
            await model.startWorkoutSession(title: plan.title, plan: plan, source: .coach)
            navigation.selectedTab = .workouts
        }
    }

    private func sendPlanFeedback(_ prompt: String) {
        draftMessage = prompt
        inputFocused = true
        VAHaptics.tap()
    }

    private func schedulePlanDraft() {
        let title = planDraft.name
        let exercises = planDraftWorkoutExercises
        Task {
            let scheduled = await model.scheduleCoDesignedWorkoutForTomorrow(
                title: title,
                durationMinutes: planDraft.durationMinutes,
                targetRPE: planDraft.targetRPE,
                exercises: exercises
            )
            if scheduled {
                VAHaptics.setLogged()
                dismissKeyboard()
                navigation.selectedTab = .workouts
            } else {
                VAHaptics.error()
            }
        }
    }

    /// VOL-275: persist the co-designed draft as a reusable template.
    /// The model re-clamps coach-derived numbers before saving.
    private func savePlanDraftAsTemplate() {
        Task {
            VAHaptics.tap()
            dismissKeyboard()
            let saved = await model.saveCoachTemplate(
                named: planDraft.name,
                plan: WorkoutSessionPlan(
                    title: planDraft.name,
                    durationMinutes: planDraft.durationMinutes,
                    targetRPE: planDraft.targetRPE,
                    exercises: planDraftWorkoutExercises
                )
            )
            toastPresenter.show(VAToast(
                kind: saved ? .success : .error,
                title: saved
                    ? String(localized: "Template saved", comment: "Toast title after saving a co-designed template")
                    : String(localized: "Couldn't save template", comment: "Toast title when saving a template fails"),
                message: saved
                    ? String(localized: "Find it in Workouts under Templates.", comment: "Toast body after saving a co-designed template")
                    : String(localized: "Try again in a moment.", comment: "Toast body when saving a template fails")
            ))
        }
    }

    private func startPlanNow() {
        Task {
            VAHaptics.sessionStart()
            dismissKeyboard()
            // The co-design draft can carry coach-refined numbers, so the
            // start path re-clamps like the schedule path (VOL-284).
            await model.startWorkoutSession(
                title: planDraft.name,
                plan: WorkoutSessionPlan(
                    title: planDraft.name,
                    durationMinutes: planDraft.durationMinutes,
                    targetRPE: planDraft.targetRPE,
                    exercises: planDraftWorkoutExercises
                ),
                source: .coach
            )
            navigation.selectedTab = .workouts
        }
    }

    private var planDraftWorkoutExercises: [WeeklyWorkoutExercise] {
        planDraft.exercises.map { exercise in
            WeeklyWorkoutExercise(
                name: exercise.name,
                sets: exercise.sets,
                reps: exercise.reps,
                weight: exercise.weight,
                targetRPE: exercise.rpe,
                restSeconds: exercise.restSeconds
            )
        }
    }

    private func isPlanningPrompt(_ prompt: String) -> Bool {
        let lowercasedPrompt = prompt.lowercased()
        return lowercasedPrompt.contains("plan") || lowercasedPrompt.contains("tomorrow")
    }

    private func dismissKeyboard() {
        inputFocused = false
    }
}

private struct SuggestedCoachPrompt: Identifiable {
    let id: String
    let title: String
    let systemImage: String
}

#endif
