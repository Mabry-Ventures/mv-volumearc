#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Coach tab — chat interface with the coach.
public struct CoachView: View { // swiftlint:disable:this type_body_length
    @ObservedObject var model: WorkoutDashboardModel
    @ObservedObject var navigation: DashboardNavigationModel
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
            fallbackNotice
            voiceNotice
            latestWorkoutHandoff
            quickPromptRail
            composer
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
                    welcomeCard
                    if showPlanDraft {
                        planningCard
                    }
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
            startNow: startPlanNow
        )
    }

    private func coachWorkoutHandoffCard(_ plan: WorkoutSessionPlan) -> some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(alignment: .center, spacing: VA.Space.md) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.primary)
                        .frame(width: 44, height: 44)
                        .background(VA.Colors.primary.opacity(0.12), in: Circle())
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
                    String(localized: "Start Workout", comment: "Coach response handoff start workout button"),
                    icon: "play.fill",
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
                    .frame(width: 34, height: 34)
                    .background(VA.Colors.primary.opacity(0.12), in: Circle())
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
                        String(localized: "Start", comment: "Pinned Coach workout handoff start button"),
                        systemImage: "play.fill"
                    )
                    .font(VA.Typography.button)
                    .foregroundStyle(VA.Colors.textOnPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, VA.Space.md)
                    .frame(minHeight: 38)
                    .background(VA.Colors.primary, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    localized: "Start recommended workout",
                    comment: "Pinned Coach workout handoff start button accessibility label"
                ))
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
                        .frame(height: 36)
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
                        .frame(width: 36, height: 36)
                        .background(VA.Colors.primary.opacity(canStartVoice ? 0.14 : 0.06), in: Circle())
                }
                .disabled(!canStartVoice)
                .buttonStyle(.plain)
                .accessibilityLabel(String(
                    localized: "Voice coach",
                    comment: "Coach composer voice button accessibility label"
                ))
                .accessibilityHint(String(
                    localized: "Sends the current dictated prompt through voice coaching.",
                    comment: "Coach composer voice button accessibility hint"
                ))
                .accessibilityIdentifier("coach.voice")

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(VA.Typography.button)
                        .foregroundStyle(canSend ? VA.Colors.textOnPrimary : VA.Colors.textTertiary)
                        .frame(width: 36, height: 36)
                        .background(canSend ? VA.Colors.primary : VA.Colors.textTertiary.opacity(0.12), in: Circle())
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
        !voicePromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.isCoachStreaming
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
        return ""
    }

    private func coachWorkoutPlan(from response: String) -> WorkoutSessionPlan? {
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
            localized: "\(plan.exercises.count) moves - \(firstExercise.name) first",
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
        draftMessage = ""
        showPlanDraft = showPlanDraft || isPlanningPrompt(prompt)
        dismissKeyboard()
        VAHaptics.tap()
        Task {
            let sent = await model.askCoachByVoice(prompt)
            if sent {
                VAHaptics.coachResponse()
            } else {
                VAHaptics.error()
            }
        }
    }

    private func startCoachRecommendedWorkout(_ plan: WorkoutSessionPlan) {
        Task {
            VAHaptics.sessionStart()
            dismissKeyboard()
            await model.startWorkoutSession(title: plan.title, plan: plan)
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

    private func startPlanNow() {
        Task {
            VAHaptics.sessionStart()
            dismissKeyboard()
            await model.startWorkoutSession(
                title: planDraft.name,
                plan: WorkoutSessionPlan(
                    title: planDraft.name,
                    durationMinutes: planDraft.durationMinutes,
                    targetRPE: planDraft.targetRPE,
                    exercises: planDraftWorkoutExercises
                )
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
