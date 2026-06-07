#if canImport(SwiftUI)
import SwiftUI

struct CoachPlanDraft: Equatable {
    var name: String
    var rationale: String
    var durationMinutes: Int
    var targetRPE: Int
    var equipment: [String]
    var muscles: [String]
    var exercises: [CoachPlanExercise]

    static let `default` = CoachPlanDraft(
        name: String(localized: "Lower-body hypertrophy", comment: "Default co-designed workout name"),
        rationale: String(
            localized: """
                Recovery is solid and legs are six days back. Quad volume has been light, \
                so this keeps the main lifts while leaving room for clean accessory work.
                """,
            comment: "Default co-designed workout rationale"
        ),
        durationMinutes: 52,
        targetRPE: 8,
        equipment: [
            String(localized: "Barbell", comment: "Workout equipment chip"),
            String(localized: "Dumbbells", comment: "Workout equipment chip"),
            String(localized: "Bench", comment: "Workout equipment chip"),
        ],
        muscles: [
            String(localized: "Quads", comment: "Workout muscle target chip"),
            String(localized: "Hamstrings", comment: "Workout muscle target chip"),
            String(localized: "Glutes", comment: "Workout muscle target chip"),
            String(localized: "Calves", comment: "Workout muscle target chip"),
        ],
        exercises: [
            CoachPlanExercise(
                name: String(localized: "Back Squat", comment: "Co-designed workout exercise"),
                sets: 4,
                reps: 6,
                weight: 225,
                rpe: 8,
                restSeconds: 150,
                alternatives: [
                    String(localized: "Front Squat", comment: "Exercise swap alternative"),
                    String(localized: "Bulgarian Split Squat", comment: "Exercise swap alternative"),
                ]
            ),
            CoachPlanExercise(
                name: String(localized: "Romanian Deadlift", comment: "Co-designed workout exercise"),
                sets: 3,
                reps: 10,
                weight: 185,
                rpe: 7,
                restSeconds: 120,
                alternatives: [
                    String(localized: "Single-leg RDL", comment: "Exercise swap alternative"),
                    String(localized: "Good Morning", comment: "Exercise swap alternative"),
                ]
            ),
            CoachPlanExercise(
                name: String(localized: "Walking Lunge", comment: "Co-designed workout exercise"),
                sets: 3,
                reps: 12,
                weight: 35,
                rpe: 8,
                restSeconds: 90,
                alternatives: [
                    String(localized: "Reverse Lunge", comment: "Exercise swap alternative"),
                    String(localized: "Step-up", comment: "Exercise swap alternative"),
                ]
            ),
            CoachPlanExercise(
                name: String(localized: "Hip Thrust", comment: "Co-designed workout exercise"),
                sets: 3,
                reps: 10,
                weight: 185,
                rpe: 8,
                restSeconds: 90,
                alternatives: [
                    String(localized: "Glute Bridge", comment: "Exercise swap alternative"),
                    String(localized: "Cable Pull-through", comment: "Exercise swap alternative"),
                ]
            ),
        ]
    )
}

struct CoachPlanExercise: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var sets: Int
    var reps: Int
    var weight: Int
    var rpe: Int
    var restSeconds: Int
    var alternatives: [String]
}

struct CoachPlanningCard: View {
    @Binding var plan: CoachPlanDraft
    @Binding var expandedExerciseID: String?
    let sendPlanFeedback: (String) -> Void
    let schedulePlan: () -> Void
    let startNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.lg) {
            summary
            actionGrid
            targetChips
            exerciseList
            footerActions
        }
        .padding(VA.Space.lg)
        .vaGlassBackground(in: RoundedRectangle(cornerRadius: VA.Radius.xl, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.planDraft")
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            Text(String(localized: "PLANNING · TOMORROW", comment: "Co-design card eyebrow"))
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.primary)
                .tracking(0.6)
            Text(plan.name)
                .font(VA.Typography.title2)
                .foregroundStyle(VA.Colors.textPrimary)
            Text(plan.rationale)
                .font(VA.Typography.footnote)
                .foregroundStyle(VA.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: VA.Space.sm) {
                CoachPlanStat(label: String(localized: "Duration", comment: "Plan stat label"), value: "\(plan.durationMinutes)m")
                CoachPlanStat(label: String(localized: "RPE", comment: "Plan stat label"), value: "\(plan.targetRPE)")
                CoachPlanStat(label: String(localized: "Moves", comment: "Plan stat label"), value: "\(plan.exercises.count)")
            }
        }
    }

    private var targetChips: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            chipRow(title: String(localized: "Targets", comment: "Co-design target chip row"), values: plan.muscles, tone: .primary)
            chipRow(title: String(localized: "Equipment", comment: "Co-design equipment chip row"), values: plan.equipment, tone: .neutral)
        }
    }

    private func chipRow(title: String, values: [String], tone: WorkoutChip.Tone) -> some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(title.uppercased())
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.6)
            FlowLayout(spacing: VA.Space.xs) {
                ForEach(values, id: \.self) { value in
                    WorkoutChip(text: value, tone: tone)
                }
            }
        }
    }

    private var exerciseList: some View {
        VStack(alignment: .leading, spacing: VA.Space.sm) {
            HStack {
                Text(String(localized: "EXERCISES", comment: "Co-design exercises section label"))
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
                    .tracking(0.6)
                Spacer()
                Text("\(plan.exercises.count)")
                    .font(VA.Typography.caption)
                    .foregroundStyle(VA.Colors.textSecondary)
            }

            VStack(spacing: VA.Space.sm) {
                ForEach(Array(plan.exercises.enumerated()), id: \.element.id) { index, exercise in
                    CoachPlanExerciseRow(
                        exerciseIndex: index,
                        exercise: exercise,
                        isExpanded: expandedExerciseID == exercise.id.uuidString,
                        canMoveUp: index > 0,
                        canMoveDown: index < plan.exercises.count - 1,
                        toggleExpanded: { toggleExpanded(exercise) },
                        update: { updateExercise(exercise.id, $0) },
                        remove: { removeExercise(exercise.id) },
                        move: { moveExercise(exercise.id, direction: $0) },
                        swap: { swapExercise(exercise.id) }
                    )
                }
            }
        }
    }

    private var actionGrid: some View {
        VAButton(
            String(localized: "Refine plan", comment: "Co-design refine plan action"),
            icon: "slider.horizontal.3",
            style: .secondary,
            accessibilityIdentifier: "coach.plan.refine"
        ) {
            sendPlanFeedback(String(localized: "Refine this plan around my recovery and equipment", comment: "Coach plan feedback prompt"))
        }
    }

    private var footerActions: some View {
        VStack(spacing: VA.Space.sm) {
            VAButton(
                String(localized: "Schedule", comment: "Co-design schedule footer action"),
                icon: "calendar",
                style: .secondary,
                accessibilityIdentifier: "coach.plan.schedule.footer"
            ) {
                schedulePlan()
            }
            VAButton(
                String(localized: "Start now", comment: "Co-design start now footer action"),
                icon: "arrow.right",
                style: .primary,
                accessibilityIdentifier: "coach.plan.startNow.footer"
            ) {
                startNow()
            }
        }
        .padding(.top, VA.Space.xs)
    }

    private func toggleExpanded(_ exercise: CoachPlanExercise) {
        expandedExerciseID = expandedExerciseID == exercise.id.uuidString ? nil : exercise.id.uuidString
    }

    private func updateExercise(_ id: UUID, _ update: (inout CoachPlanExercise) -> Void) {
        guard let index = plan.exercises.firstIndex(where: { $0.id == id }) else { return }
        update(&plan.exercises[index])
    }

    private func removeExercise(_ id: UUID) {
        plan.exercises.removeAll { $0.id == id }
    }

    private func moveExercise(_ id: UUID, direction: Int) {
        guard let index = plan.exercises.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + direction
        guard plan.exercises.indices.contains(newIndex) else { return }
        plan.exercises.swapAt(index, newIndex)
    }

    private func swapExercise(_ id: UUID) {
        updateExercise(id) { exercise in
            guard let next = exercise.alternatives.first else { return }
            exercise.alternatives = Array(exercise.alternatives.dropFirst()) + [exercise.name]
            exercise.name = next
        }
    }
}

private struct CoachPlanStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xxs) {
            Text(label.uppercased())
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.6)
            Text(value)
                .font(VA.Typography.monoDigit)
                .foregroundStyle(VA.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VA.Space.sm)
        .background(VA.Colors.textTertiary.opacity(0.10), in: RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous))
    }
}

private struct CoachPlanExerciseRow: View {
    let exerciseIndex: Int
    let exercise: CoachPlanExercise
    let isExpanded: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let toggleExpanded: () -> Void
    let update: ((inout CoachPlanExercise) -> Void) -> Void
    let remove: () -> Void
    let move: (Int) -> Void
    let swap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggleExpanded) {
                HStack(spacing: VA.Space.md) {
                    WorkoutIllustrationTile(systemImage: "figure.strengthtraining.traditional", size: 48, accent: VA.Colors.primary)
                    VStack(alignment: .leading, spacing: VA.Space.xxs) {
                        Text(exercise.name)
                            .font(VA.Typography.headline)
                            .foregroundStyle(VA.Colors.textPrimary)
                        Text("\(exercise.sets) x \(exercise.reps) · \(exercise.weight) lb · RPE \(exercise.rpe)")
                            .font(VA.Typography.footnote)
                            .foregroundStyle(VA.Colors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(VA.Typography.caption)
                        .foregroundStyle(VA.Colors.textTertiary)
                        .rotationEffect(isExpanded ? .degrees(90) : .zero)
                }
                .padding(VA.Space.md)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("coach.plan.exercise.\(exerciseIndex).toggle")

            if isExpanded {
                expandedEditor
                    .padding(.horizontal, VA.Space.md)
                    .padding(.bottom, VA.Space.md)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(VA.Colors.surfacePrimary, in: RoundedRectangle(cornerRadius: VA.Radius.md, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.plan.exercise.\(exerciseIndex)")
    }

    private var expandedEditor: some View {
        VStack(spacing: VA.Space.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: VA.Space.sm) { stepControls }
                VStack(spacing: VA.Space.sm) { stepControls }
            }
            FlowLayout(spacing: VA.Space.xs) {
                CoachPlanRowAction(
                    title: String(localized: "Swap", comment: "Co-design exercise row action"),
                    icon: "arrow.triangle.2.circlepath",
                    accessibilityIdentifier: "coach.plan.exercise.\(exerciseIndex).swap",
                    action: swap
                )
                CoachPlanRowAction(
                    title: String(localized: "Move up", comment: "Co-design exercise row action"),
                    icon: "arrow.up",
                    accessibilityIdentifier: "coach.plan.exercise.\(exerciseIndex).moveUp",
                    isDisabled: !canMoveUp
                ) {
                    move(-1)
                }
                CoachPlanRowAction(
                    title: String(localized: "Move down", comment: "Co-design exercise row action"),
                    icon: "arrow.down",
                    accessibilityIdentifier: "coach.plan.exercise.\(exerciseIndex).moveDown",
                    isDisabled: !canMoveDown
                ) {
                    move(1)
                }
                CoachPlanRowAction(
                    title: String(localized: "Remove", comment: "Co-design exercise row action"),
                    icon: "trash",
                    accessibilityIdentifier: "coach.plan.exercise.\(exerciseIndex).remove",
                    isDestructive: true,
                    action: remove
                )
            }
        }
    }

    @ViewBuilder
    private var stepControls: some View {
        CoachStepperControl(
            label: String(localized: "Sets", comment: "Co-design stepper label"),
            value: exercise.sets,
            range: 1...10,
            accessibilityPrefix: "coach.plan.exercise.\(exerciseIndex).sets"
        ) { newValue in
            update { $0.sets = newValue }
        }
        CoachStepperControl(
            label: String(localized: "Reps", comment: "Co-design stepper label"),
            value: exercise.reps,
            range: 1...30,
            accessibilityPrefix: "coach.plan.exercise.\(exerciseIndex).reps"
        ) { newValue in
            update { $0.reps = newValue }
        }
        CoachStepperControl(
            label: String(localized: "lb", comment: "Co-design stepper label"),
            value: exercise.weight,
            range: 0...500,
            step: 5,
            accessibilityPrefix: "coach.plan.exercise.\(exerciseIndex).weight"
        ) { newValue in
            update { $0.weight = newValue }
        }
    }
}

private struct CoachStepperControl: View {
    let label: String
    let value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var accessibilityPrefix: String
    let onChange: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: VA.Space.xs) {
            Text(label.uppercased())
                .font(VA.Typography.caption)
                .foregroundStyle(VA.Colors.textSecondary)
                .tracking(0.6)
            HStack(spacing: VA.Space.xs) {
                Button { onChange(max(range.lowerBound, value - step)) } label: {
                    Image(systemName: "minus")
                        .font(VA.Typography.caption)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(String(localized: "Decrease \(label)", comment: "Plan stepper decrement button"))
                .accessibilityIdentifier("\(accessibilityPrefix).decrement")
                Text("\(value)")
                    .font(VA.Typography.monoDigit)
                    .foregroundStyle(VA.Colors.textPrimary)
                    .frame(minWidth: 34)
                    .accessibilityIdentifier("\(accessibilityPrefix).value")
                Button { onChange(min(range.upperBound, value + step)) } label: {
                    Image(systemName: "plus")
                        .font(VA.Typography.caption)
                        .frame(width: 28, height: 28)
                }
                .accessibilityLabel(String(localized: "Increase \(label)", comment: "Plan stepper increment button"))
                .accessibilityIdentifier("\(accessibilityPrefix).increment")
            }
            .foregroundStyle(VA.Colors.textPrimary)
            .background(VA.Colors.textTertiary.opacity(0.10), in: RoundedRectangle(cornerRadius: VA.Radius.sm, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CoachPlanRowAction: View {
    let title: String
    let icon: String
    let accessibilityIdentifier: String
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(VA.Typography.caption)
                .foregroundStyle(isDestructive ? VA.Colors.error : VA.Colors.textPrimary)
                .padding(.horizontal, VA.Space.sm)
                .frame(height: 30)
                .background(background, in: Capsule())
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.42 : 1)
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var background: Color {
        isDestructive ? VA.Colors.error.opacity(0.14) : VA.Colors.textTertiary.opacity(0.12)
    }
}

struct FlowLayout<Content: View>: View {
    let spacing: CGFloat
    let content: () -> Content

    init(spacing: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content() }
            VStack(alignment: .leading, spacing: spacing) { content() }
        }
    }
}
#endif
