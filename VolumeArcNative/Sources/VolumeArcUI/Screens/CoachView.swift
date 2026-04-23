#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Coach tab — chat interface with the AI coach.
public struct CoachView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @ObservedObject var navigation: DashboardNavigationModel
    @State private var draftMessage: String = ""
    @FocusState private var inputFocused: Bool

    public init(model: WorkoutDashboardModel, navigation: DashboardNavigationModel) {
        self.model = model
        self.navigation = navigation
    }

    public var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            composer
        }
        .background(VA.Colors.surfaceSecondary)
        .navigationTitle(DashboardTab.coach.title)
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            if let prompt = navigation.coachPrompt, !prompt.isEmpty {
                draftMessage = prompt
                navigation.clearCoachPrompt()
            }
        }
    }

    // MARK: - Message list

    @ViewBuilder
    private var messageList: some View {
        if model.coachMessages.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: VA.Space.lg) {
                    welcomeCard
                    quickPrompts
                }
                .padding(VA.Space.lg)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: VA.Space.md) {
                        ForEach(model.coachMessages) { message in
                            VACoachBubble(
                                sender: message.sender == .user ? .user : .coach,
                                content: message.content
                            )
                            .id(message.id)
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
                        }
                    }
                    .padding(VA.Space.lg)
                }
                .onChange(of: model.coachMessages.count) { _, _ in
                    withAnimation(VAAnimation.standard) {
                        proxy.scrollTo(model.coachMessages.last?.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var welcomeCard: some View {
        VACard(style: .accent) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(spacing: VA.Space.sm) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(VA.Colors.primary)
                    Text(String(localized: "Your Coach", comment: "Coach welcome card title"))
                        .font(VA.Typography.title2)
                        .foregroundStyle(VA.Colors.textPrimary)
                }
                Text(String(
                    localized: "Ask anything about your training — load selection, form cues, recovery, or how last week looks. I'll pull from your recent sessions to give you a grounded answer.",
                    comment: "Coach welcome card description"
                ))
                    .font(VA.Typography.body)
                    .foregroundStyle(VA.Colors.textSecondary)
            }
        }
    }

    private var quickPrompts: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader(String(localized: "Try asking", comment: "Suggested prompts section header"))
            // Wrap the stacked interactive-glass rows in a `GlassEffectContainer`
            // so iOS 26's coordinated glass renderer composes them as a single
            // material treatment rather than rendering each row independently.
            quickPromptsList
        }
    }

    @ViewBuilder
    private var quickPromptsList: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: VA.Space.md) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    promptButtons
                }
            }
        } else {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                promptButtons
            }
        }
    }

    @ViewBuilder
    private var promptButtons: some View {
        ForEach(suggestedPrompts, id: \.self) { prompt in
            Button {
                draftMessage = prompt
                inputFocused = true
                VAHaptics.tap()
            } label: {
                HStack {
                    Text(prompt)
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VA.Colors.textTertiary)
                }
                .padding(VA.Space.md)
                .vaInteractiveGlassBackground(
                    in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var suggestedPrompts: [String] {
        [
            String(localized: "Am I ready to push on squats this week?", comment: "Suggested coach prompt about squat progression"),
            String(localized: "Last set felt heavy — should I hold or go up?", comment: "Suggested coach prompt about load decision"),
            String(localized: "What accessories should I add for bench?", comment: "Suggested coach prompt about accessory work"),
            String(localized: "How does my recent volume look?", comment: "Suggested coach prompt about training volume"),
        ]
    }

    // MARK: - Composer

    private var composer: some View {
        HStack(alignment: .bottom, spacing: VA.Space.sm) {
            TextField(
                String(localized: "Ask your coach", comment: "Coach composer placeholder"),
                text: $draftMessage,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(VA.Typography.body)
                .padding(VA.Space.md)
                .vaInteractiveGlassBackground(
                    in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous)
                )
                .lineLimit(1...4)
                .focused($inputFocused)

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(canSend ? VA.Colors.primary : VA.Colors.textTertiary)
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
        .padding(VA.Space.md)
        .background(VA.Colors.surfacePrimary)
    }

    private var canSend: Bool {
        !draftMessage.trimmingCharacters(in: .whitespaces).isEmpty && !model.isCoachStreaming
    }

    private func sendMessage() {
        let prompt = draftMessage
        draftMessage = ""
        VAHaptics.tap()
        Task {
            await model.askCoach(prompt)
            VAHaptics.coachResponse()
        }
    }
}
#endif
