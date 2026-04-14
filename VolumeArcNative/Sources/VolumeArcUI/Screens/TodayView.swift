#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

/// The Today tab — hero card with next workout, readiness, quick actions, and recent sessions.
public struct TodayView: View {
    @ObservedObject var model: WorkoutDashboardModel
    @ObservedObject var navigation: DashboardNavigationModel

    public init(model: WorkoutDashboardModel, navigation: DashboardNavigationModel) {
        self.model = model
        self.navigation = navigation
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.lg) {
                greeting
                readinessCard
                nextWorkoutCard
                quickActionsRow
                recentSessionsSection
                if !model.operationalSignals.isEmpty {
                    signalsSection
                }
            }
            .padding(VA.Space.lg)
        }
        .background(VA.Colors.surfaceSecondary)
        .navigationTitle(DashboardTab.today.title)
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await model.refresh() }
    }

    // MARK: - Greeting

    private var greeting: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(greetingText)
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(model.athlete.name.isEmpty ? "Welcome back" : "Welcome back, \(firstName)")
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
        }
    }

    private var firstName: String {
        model.athlete.name.split(separator: " ").first.map(String.init) ?? model.athlete.name
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 4..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default: return "Hey there"
        }
    }

    // MARK: - Readiness card

    private var readinessCard: some View {
        VACard(style: .accent) {
            HStack(alignment: .center, spacing: VA.Space.lg) {
                ZStack {
                    VAProgressRing(progress: Double(model.readiness.score) / 100, lineWidth: 10)
                        .frame(width: 88, height: 88)
                    VStack(spacing: 0) {
                        Text("\(model.readiness.score)")
                            .font(VA.Typography.display)
                            .foregroundStyle(VA.Colors.textPrimary)
                            .contentTransition(.numericText())
                        Text("READY")
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(1)
                    }
                }
                .accessibilityLabel("Readiness score \(model.readiness.score) out of 100")

                VStack(alignment: .leading, spacing: VA.Space.xs) {
                    Text("READINESS")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .tracking(0.5)
                    Text(model.readiness.brief)
                        .font(VA.Typography.body)
                        .foregroundStyle(VA.Colors.textPrimary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Next workout card

    @ViewBuilder
    private var nextWorkoutCard: some View {
        if let autopilot = model.autopilot {
            VACard(style: .elevated) {
                VStack(alignment: .leading, spacing: VA.Space.md) {
                    HStack {
                        VStack(alignment: .leading, spacing: VA.Space.xxs) {
                            Text("NEXT WORKOUT")
                                .font(VA.Typography.caption)
                                .foregroundStyle(VA.Colors.textSecondary)
                                .tracking(0.5)
                            Text(model.nextWorkout?.title ?? "Strength Session")
                                .font(VA.Typography.title2)
                                .foregroundStyle(VA.Colors.textPrimary)
                        }
                        Spacer()
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(VA.Colors.primary)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: VA.Space.sm) {
                        Text("Starting lift")
                            .font(VA.Typography.caption)
                            .foregroundStyle(VA.Colors.textSecondary)
                            .tracking(0.5)
                        Text(autopilot.nextExerciseName)
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text("\(Int(autopilot.nextTarget.weight))\(autopilot.nextTarget.unit) × \(autopilot.nextTarget.repRange.lowerBound)-\(autopilot.nextTarget.repRange.upperBound) @ RPE \(String(format: "%.1f", autopilot.nextTarget.targetRPE))")
                            .font(VA.Typography.monoDigit)
                            .foregroundStyle(VA.Colors.primary)
                    }

                    Text(autopilot.recommendationReason)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                        .padding(.top, VA.Space.xs)
                }
            }
        } else {
            VACard(style: .flat) {
                VAEmptyState(
                    icon: "sparkles",
                    title: "No workout queued",
                    message: "Complete onboarding to get your first recommendation.",
                    action: (label: "Get Started", handler: { navigation.openProfile() })
                )
                .frame(minHeight: 180)
            }
        }
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: VA.Space.md) {
            VAButton(
                model.isSessionActive ? "Continue Session" : "Start Workout",
                icon: "play.fill",
                style: .primary
            ) {
                Task {
                    VAHaptics.sessionStart()
                    if !model.isSessionActive {
                        await model.startWorkoutSession()
                    }
                }
            }

            VAButton("Ask Coach", icon: "waveform", style: .secondary) {
                VAHaptics.tap()
                navigation.openCoach(prompt: "What should I focus on today?")
            }
        }
    }

    // MARK: - Recent sessions

    private var recentSessionsSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader("Recent Sessions", subtitle: "\(model.recentSessions.count) this week")
            if model.recentSessions.isEmpty {
                VACard(style: .flat) {
                    Text("No sessions logged yet. Start your first workout to see your history here.")
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
            } else {
                ForEach(Array(model.recentSessions.prefix(3).enumerated()), id: \.offset) { _, session in
                    sessionRow(session)
                }
            }
        }
    }

    private func sessionRow(_ session: RecentSession) -> some View {
        VACard(style: .flat) {
            HStack(spacing: VA.Space.md) {
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(session.date.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(VA.Typography.headline)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text("\(session.completedSetCount) sets • \(session.durationMinutes)min • RPE \(String(format: "%.1f", session.averageRPE))")
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
                VAMetricDisplay(
                    label: "Load",
                    value: "\(Int(session.totalVolumeLoad))",
                    unit: "lb",
                    style: .compact
                )
            }
        }
    }

    // MARK: - Signals

    private var signalsSection: some View {
        VStack(alignment: .leading, spacing: VA.Space.md) {
            VASectionHeader("System status")
            ForEach(model.operationalSignals, id: \.id) { signal in
                signalRow(signal)
            }
        }
    }

    private func signalRow(_ signal: OperationalSignalSummary) -> some View {
        VACard(style: .flat) {
            HStack(spacing: VA.Space.md) {
                Image(systemName: signalIcon(signal.severity))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(signalColor(signal.severity))
                VStack(alignment: .leading, spacing: VA.Space.xxs) {
                    Text(signal.title)
                        .font(VA.Typography.footnote)
                        .foregroundStyle(VA.Colors.textPrimary)
                    Text(signal.message)
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textSecondary)
                }
                Spacer()
            }
        }
    }

    private func signalIcon(_ severity: TelemetrySeverity) -> String {
        switch severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private func signalColor(_ severity: TelemetrySeverity) -> Color {
        switch severity {
        case .info: return VA.Colors.info
        case .warning: return VA.Colors.warning
        case .error: return VA.Colors.error
        }
    }
}
#endif
