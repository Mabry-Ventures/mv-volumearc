#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Coach tab — chat interface with the AI coach.
public struct CoachView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @ObservedObject var navigation: DashboardNavigationModel
    @State private var draftMessage: String = ""
    @State private var showPlanDraft: Bool = false
    @State private var expandedExerciseID: String?
    @State private var planDraft: CoachPlanDraft = .default
    @State private var showCoachSafetyNotice: Bool = false
    @AppStorage("volumearc.coachSafetyNoticeAccepted")
    private var hasAcceptedCoachSafetyNotice: Bool = false
    @FocusState private var inputFocused: Bool

    public init(model: WorkoutDashboardModel, navigation: DashboardNavigationModel) {
        self.model = model
        self.navigation = navigation
    }

    public var body: some View {
        VStack(spacing: 0) {
            coachHeader
            messageList
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
        .alert(
            String(localized: "AI coaching notice", comment: "Coach safety notice alert title"),
            isPresented: $showCoachSafetyNotice
        ) {
            Button(String(localized: "I Understand", comment: "Coach safety notice acknowledgement button")) {
                hasAcceptedCoachSafetyNotice = true
            }
        } message: {
            Text(String(
                localized: """
                    AI coaching uses Google Gemini. Recommendations are not \
                    medical advice — consult a physician before starting a new \
                    program or training with pain, dizziness, chest pain, or \
                    shortness of breath.
                    """,
                comment: "One-time Coach AI safety notice"
            ))
        }
        .onAppear {
            presentCoachSafetyNoticeIfNeeded()
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
            startNow: startPlanNow
        )
    }

    private var quickPromptRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: VA.Space.sm) {
                ForEach(suggestedPrompts, id: \.self) { prompt in
                    Button {
                        draftMessage = prompt
                        showPlanDraft = showPlanDraft || isPlanningPrompt(prompt)
                        inputFocused = true
                        VAHaptics.tap()
                    } label: {
                        Text(prompt)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textPrimary)
                            .lineLimit(1)
                            .padding(.horizontal, VA.Space.md)
                            .frame(height: 34)
                            .background(VA.Colors.textTertiary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, VA.Space.lg)
            .padding(.vertical, VA.Space.sm)
        }
        .background(VA.Colors.surfaceGrouped)
    }

    private var suggestedPrompts: [String] {
        [
            String(localized: "Plan tomorrow", comment: "Suggested coach prompt to co-design tomorrow's workout"),
            String(localized: "Should I push?", comment: "Suggested coach prompt about whether to push"),
            String(localized: "Form check", comment: "Suggested coach prompt for lifting form"),
            String(localized: "Substitute exercise", comment: "Suggested coach prompt for exercise substitution"),
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
                localized: "AI coaching uses Google Gemini. Recommendations are not medical advice.",
                comment: "Persistent Coach AI safety disclaimer under the composer"
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

    private func sendMessage() {
        let prompt = draftMessage
        draftMessage = ""
        showPlanDraft = showPlanDraft || isPlanningPrompt(prompt)
        dismissKeyboard()
        VAHaptics.tap()
        Task {
            await model.askCoach(prompt)
            VAHaptics.coachResponse()
        }
    }

    private func sendPlanFeedback(_ prompt: String) {
        draftMessage = prompt
        inputFocused = true
        VAHaptics.tap()
    }

    private func startPlanNow() {
        Task {
            VAHaptics.sessionStart()
            dismissKeyboard()
            await model.startWorkoutSession()
            navigation.selectedTab = .workouts
        }
    }

    private func isPlanningPrompt(_ prompt: String) -> Bool {
        let lowercasedPrompt = prompt.lowercased()
        return lowercasedPrompt.contains("plan") || lowercasedPrompt.contains("tomorrow")
    }

    private func dismissKeyboard() {
        inputFocused = false
    }

    private func presentCoachSafetyNoticeIfNeeded() {
        guard !VolumeArcRuntimeFlags.isDeterministicMode else { return }
        guard !hasAcceptedCoachSafetyNotice else { return }
        showCoachSafetyNotice = true
    }
}
#endif
