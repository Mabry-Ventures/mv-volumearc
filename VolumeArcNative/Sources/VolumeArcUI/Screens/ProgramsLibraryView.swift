#if canImport(SwiftUI)
import SwiftUI
import VolumeArcCore

public struct ProgramsLibraryView: View {
    @ObservedObject private var model: WorkoutDashboardModel
    @EnvironmentObject private var toastPresenter: VAToastPresenter
    @State private var assigningProgramID: String?

    public init(model: WorkoutDashboardModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VA.Space.lg) {
                header
                ForEach(model.trainingPrograms) { program in
                    programCard(program)
                }
            }
            .padding(VA.Space.lg)
            .padding(.bottom, VA.Space.xxl)
        }
        .background(VA.Colors.surfaceGrouped)
        .navigationTitle(String(localized: "Programs", comment: "Programs library navigation title"))
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("programsLibrary.root")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(String(localized: "Curated library", comment: "Programs library eyebrow"))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
            Text(String(localized: "Pick a plan", comment: "Programs library title"))
                .font(VA.Typography.title)
                .foregroundStyle(VA.Colors.textPrimary)
            if let activeProgram = model.activeProgram {
                Text(String(
                    localized: "Running \(activeProgram.programName), week \(activeProgram.weekNumber) day \(activeProgram.dayNumber)",
                    comment: "Programs library active program summary"
                ))
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
            }
        }
        .padding(.top, VA.Space.sm)
    }

    private func programCard(_ program: TrainingProgramDefinition) -> some View {
        let isActive = model.activeProgram?.programID == program.id
        return VACard(style: isActive ? .accent : .elevated) {
            VStack(alignment: .leading, spacing: VA.Space.md) {
                HStack(alignment: .top, spacing: VA.Space.md) {
                    WorkoutIllustrationTile(
                        systemImage: programIcon(for: program),
                        size: VA.Space.ctaIllustration,
                        accent: isActive ? VA.Colors.primary : VA.Colors.textSecondary
                    )
                    VStack(alignment: .leading, spacing: VA.Space.xs) {
                        HStack(alignment: .firstTextBaseline, spacing: VA.Space.sm) {
                            Text(program.name)
                                .font(VA.Typography.headline)
                                .foregroundStyle(VA.Colors.textPrimary)
                                .lineLimit(2)
                            if isActive {
                                WorkoutChip(
                                    text: String(localized: "Active", comment: "Active program chip"),
                                    tone: .success
                                )
                            }
                        }
                        Text(program.author)
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                    }
                    Spacer(minLength: VA.Space.sm)
                }

                Text(program.sessions.first?.prescription ?? program.advancementCriteria)
                    .font(VA.Typography.footnote)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .lineLimit(3)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: VA.Space.xs) {
                        metaChips(for: program)
                    }
                    VStack(alignment: .leading, spacing: VA.Space.xs) {
                        metaChips(for: program)
                    }
                }

                VAButton(
                    isActive
                        ? String(localized: "Running", comment: "Program card active state button")
                        : String(localized: "Run this program", comment: "Program card assignment button"),
                    icon: isActive ? "checkmark.circle.fill" : "play.fill",
                    style: isActive ? .secondary : .primary,
                    isLoading: assigningProgramID == program.id,
                    accessibilityIdentifier: "programsLibrary.run.\(program.id)"
                ) {
                    assign(program)
                }
                .disabled(isActive || assigningProgramID != nil)
            }
        }
        .accessibilityIdentifier("programsLibrary.card.\(program.id)")
    }

    @ViewBuilder
    private func metaChips(for program: TrainingProgramDefinition) -> some View {
        WorkoutChip(
            text: String(localized: "^[\(program.weeks) week](inflect: true)", comment: "Program duration chip"),
            tone: .neutral
        )
        WorkoutChip(
            text: String(
                localized: "^[\(program.sessionsPerWeek) session](inflect: true)/week",
                comment: "Program weekly frequency chip"
            ),
            tone: .neutral
        )
        WorkoutChip(text: program.difficulty.displayName, tone: .primary)
        WorkoutChip(text: program.equipmentRequirement.displayName, tone: .neutral)
    }

    private func assign(_ program: TrainingProgramDefinition) {
        assigningProgramID = program.id
        Task {
            let success = await model.assignTrainingProgram(program.id)
            assigningProgramID = nil
            if success {
                VAHaptics.setLogged()
                toastPresenter.show(VAToast(
                    kind: .success,
                    title: String(localized: "Program started", comment: "Toast after assigning program"),
                    message: String(
                        localized: "\(program.name) is now on your schedule.",
                        comment: "Toast after assigning program detail"
                    )
                ))
            } else {
                toastPresenter.show(VAToast(
                    kind: .error,
                    title: String(localized: "Could not start program", comment: "Program assignment failure toast"),
                    message: String(localized: "Try again in a moment.", comment: "Program assignment failure detail")
                ))
            }
        }
    }

    private func programIcon(for program: TrainingProgramDefinition) -> String {
        switch program.difficulty {
        case .novice: return "figure.strengthtraining.traditional"
        case .intermediate: return "dumbbell"
        case .advanced: return "chart.line.uptrend.xyaxis"
        }
    }
}

#endif
