import SwiftUI
import SwiftData

/// AI Coach chat interface
struct AICoachView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \DailyLog.date, order: .reverse) private var recentLogs: [DailyLog]

    @State private var messages: [CoachMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            // Welcome message
                            if messages.isEmpty {
                                welcomeView
                            }

                            // Quick actions
                            quickActionsView

                            // Messages
                            ForEach(messages) { message in
                                MessageBubble(message: message)
                            }

                            if isLoading {
                                HStack {
                                    ProgressView()
                                    Text("Thinking...")
                                        .foregroundStyle(.secondary)
                                }
                                .padding()
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(messages.last?.id, anchor: .bottom)
                        }
                    }
                }

                Divider()

                // Input area
                inputArea
            }
            .navigationTitle("AI Coach")
            .background {
                LinearGradient.beastBackgroundGradient
                    .ignoresSafeArea()
            }
        }
    }

    private var welcomeView: some View {
        VStack(spacing: 16) {
            AnimatedBeastMascot(mood: .idle, size: 80)

            Text("Hey! I'm your Beast Mode coach.")
                .font(.beastHeadline)

            Text("Ask me anything about your workouts, form, or training strategy.")
                .font(.beastBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }

    private var quickActionsView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                QuickActionChip(title: "Form Check", icon: "figure.stand") {
                    sendMessage("Give me a quick form check for my main lifts")
                }

                QuickActionChip(title: "Weekly Review", icon: "calendar") {
                    requestWeeklyReview()
                }

                QuickActionChip(title: "What Today?", icon: "questionmark") {
                    sendMessage("What should I focus on in today's workout?")
                }

                QuickActionChip(title: "Recovery Tips", icon: "bed.double") {
                    sendMessage("Give me some recovery tips for after strength training")
                }
            }
        }
        .padding(.bottom, 8)
    }

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Ask your coach...", text: $inputText, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .glassBackground(cornerRadius: 20)

            Button {
                sendMessage(inputText)
                inputText = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
                    .foregroundStyle(.beastPrimary)
            }
            .disabled(inputText.isEmpty || isLoading)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func sendMessage(_ text: String) {
        guard !text.isEmpty else { return }

        let userMessage = CoachMessage(role: .user, content: text)
        messages.append(userMessage)

        isLoading = true

        Task {
            do {
                let context = recentLogs.prefix(7).map { log in
                    "\(log.weekday.fullName): \(log.sortedExerciseLogs.map(\.exerciseName).joined(separator: ", "))"
                }.joined(separator: "\n")

                let response = try await AICoachService.shared.askCoach(
                    question: text,
                    context: context.isEmpty ? nil : context
                )

                let coachMessage = CoachMessage(role: .coach, content: response)

                await MainActor.run {
                    messages.append(coachMessage)
                    isLoading = false
                }
            } catch {
                let errorMessage = CoachMessage(
                    role: .coach,
                    content: "Sorry, I couldn't process that request. Please try again."
                )

                await MainActor.run {
                    messages.append(errorMessage)
                    isLoading = false
                }
            }
        }
    }

    private func requestWeeklyReview() {
        let userMessage = CoachMessage(role: .user, content: "Give me a weekly review of my workouts")
        messages.append(userMessage)

        isLoading = true

        Task {
            do {
                let logs = Array(recentLogs.prefix(7))
                let review = try await AICoachService.shared.generateWeeklyReview(logs: logs)

                let coachMessage = CoachMessage(role: .coach, content: review.rawText)

                await MainActor.run {
                    messages.append(coachMessage)
                    isLoading = false
                }
            } catch {
                let errorMessage = CoachMessage(
                    role: .coach,
                    content: "I need more workout data to give you a review. Keep logging your sessions!"
                )

                await MainActor.run {
                    messages.append(errorMessage)
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Coach Message

struct CoachMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let content: String
    let timestamp = Date()

    enum MessageRole {
        case user
        case coach
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: CoachMessage

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                if message.role == .coach {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                        Text("Coach")
                            .font(.beastCaption)
                    }
                    .foregroundStyle(.beastPrimary)
                }

                Text(message.content)
                    .font(.beastBody)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background {
                        if message.role == .user {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.beastPrimary)
                        } else {
                            RoundedRectangle(cornerRadius: 18)
                                .fill(.ultraThinMaterial)
                        }
                    }
                    .foregroundStyle(message.role == .user ? .white : .primary)
            }

            if message.role == .coach {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Quick Action Chip

struct QuickActionChip: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.beastCaption)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassBackground(cornerRadius: .infinity)
        }
        .buttonStyle(GlassButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    AICoachView()
        .modelContainer(for: DailyLog.self, inMemory: true)
}
