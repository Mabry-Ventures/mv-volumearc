// VOL-270: product-surface visual regression coverage for the Claude Design
// parity matrix. These snapshots render the actual SwiftUI tab surfaces with
// deterministic launch-state data, so token/card/chrome/copy drift is caught
// before the release branch can claim visual parity.

#if canImport(SnapshotTesting) && canImport(UIKit)
import SnapshotTesting
import SwiftUI
import UIKit
@_spi(Testing) import VolumeArcCore
@_spi(Testing) import VolumeArcUI
import XCTest

@MainActor
final class DashboardSurfaceSnapshotTests: XCTestCase {
    private enum Metrics {
        static let phone = CGSize(width: 393, height: 852)
    }

    private enum Surface: String, CaseIterable {
        case today
        case workoutsIdle
        case workoutsActive
        case coachPlanning
        case signals
        case profile
    }

    private static let fixedNow = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(secondsFromGMT: 0),
        year: 2026,
        month: 6,
        day: 1,
        hour: 15,
        minute: 0
    ).date!

    private var savedDeterministicMode: Bool?

    override func setUp() async throws {
        try await super.setUp()

        guard !Self.isRunningInXcodeCloudTestProducts else {
            throw XCTSkip("""
            VOL-270: Dashboard surface snapshots are enforced locally and on \
            the self-hosted runner. Xcode Cloud renders large SwiftUI tab \
            surfaces differently from the bundled reference PNGs.
            """)
        }

        savedDeterministicMode = VolumeArcRuntimeFlags.isDeterministicMode
        VolumeArcRuntimeFlags.isDeterministicMode = true
    }

    override func tearDown() async throws {
        if let savedDeterministicMode {
            VolumeArcRuntimeFlags.isDeterministicMode = savedDeterministicMode
        }
        savedDeterministicMode = nil
        try await super.tearDown()
    }

    nonisolated private static var isRunningInXcodeCloudTestProducts: Bool {
        Bundle(for: DashboardSurfaceSnapshotTests.self).bundleURL.path.contains("TestProducts.xctestproducts")
    }

    func testClaudeParityLightSurfaceSnapshots() {
        for surface in Surface.allCases {
            assertSurfaceSnapshot(surface, colorScheme: .light)
        }
    }

    func testClaudeParityDarkSurfaceSnapshots() {
        for surface in Surface.allCases {
            assertSurfaceSnapshot(surface, colorScheme: .dark)
        }
    }

    func testClaudeParityWarmBrandSurfaceSnapshots() {
        for surface in Surface.allCases {
            assertSurfaceSnapshot(
                surface,
                colorScheme: .light,
                nameSuffix: "warm",
                testName: #function
            )
        }
    }

    func testClaudeParityAccessibilityDynamicTypeSurfaceSnapshots() {
        for surface in Surface.allCases {
            assertSurfaceSnapshot(
                surface,
                colorScheme: .light,
                nameSuffix: "accessibility",
                dynamicTypeSize: .accessibility5,
                preferredContentSizeCategory: .accessibilityExtraExtraExtraLarge,
                testName: #function
            )
        }
    }

    func testClaudeParityReduceTransparencyOffSurfaceSnapshots() {
        for surface in Surface.allCases {
            assertSurfaceSnapshot(
                surface,
                colorScheme: .light,
                nameSuffix: "glass",
                reduceTransparency: false,
                testName: #function
            )
        }
    }

    func testClaudeParityDarkReduceTransparencyOffSurfaceSnapshots() {
        for surface in Surface.allCases {
            assertSurfaceSnapshot(
                surface,
                colorScheme: .dark,
                nameSuffix: "dark-glass",
                reduceTransparency: false,
                testName: #function
            )
        }
    }

    func testClaudeParityWarmReduceTransparencyOffSurfaceSnapshots() {
        for surface in Surface.allCases {
            assertSurfaceSnapshot(
                surface,
                colorScheme: .light,
                nameSuffix: "warm-glass",
                reduceTransparency: false,
                testName: #function
            )
        }
    }

    private func assertSurfaceSnapshot(
        _ surface: Surface,
        colorScheme: ColorScheme,
        nameSuffix: String? = nil,
        dynamicTypeSize: DynamicTypeSize = .large,
        preferredContentSizeCategory: UIContentSizeCategory = .large,
        reduceTransparency: Bool = true,
        testName: String = #function,
        line: UInt = #line
    ) {
        let view = surfaceView(surface)
            .dashboardSnapshotEnvironment(
                colorScheme: colorScheme,
                dynamicTypeSize: dynamicTypeSize,
                reduceTransparency: reduceTransparency
            )
            .frame(width: Metrics.phone.width, height: Metrics.phone.height)
        let resolvedNameSuffix = nameSuffix ?? (colorScheme == .dark ? "dark" : "light")

        assertVolumeArcSnapshot(
            of: view,
            as: imageSnapshot(
                colorScheme: colorScheme,
                preferredContentSizeCategory: preferredContentSizeCategory
            ),
            named: "\(surface.rawValue)-\(resolvedNameSuffix)",
            in: self,
            testName: testName,
            line: line
        )
    }

    private func surfaceView(_ surface: Surface) -> AnyView {
        let navigation = DashboardNavigationModel()
        let model = WorkoutDashboardModel(
            snapshotState: snapshotState(isSessionActive: surface == .workoutsActive)
        )

        switch surface {
        case .today:
            return AnyView(TodayView(model: model, navigation: navigation, now: { Self.fixedNow }))
        case .workoutsIdle:
            return AnyView(WorkoutsView(model: model))
        case .workoutsActive:
            return AnyView(WorkoutsView(model: model))
        case .coachPlanning:
            return AnyView(CoachView(
                model: model,
                navigation: navigation,
                showsPlanDraftForSnapshot: true
            ))
        case .signals:
            return AnyView(SignalsView(model: model, now: { Self.fixedNow }))
        case .profile:
            return AnyView(ProfileView(model: model))
        }
    }

    private func snapshotState(isSessionActive: Bool) -> WorkoutDashboardSnapshotState {
        let exercises = [
            WeeklyWorkoutExercise(
                name: "Back Squat",
                sets: 4,
                reps: 6,
                weight: 225,
                targetRPE: 8,
                restSeconds: 150
            ),
            WeeklyWorkoutExercise(
                name: "Romanian Deadlift",
                sets: 3,
                reps: 10,
                weight: 185,
                targetRPE: 7,
                restSeconds: 120
            ),
            WeeklyWorkoutExercise(
                name: "Walking Lunge",
                sets: 3,
                reps: 12,
                weight: 35,
                targetRPE: 8,
                restSeconds: 90
            ),
        ]
        let weeklyPlan = (1...7).map { day in
            WeeklyWorkout(
                dayOfWeek: day,
                title: "Lower-body hypertrophy",
                durationMinutes: 52,
                targetRPE: 8,
                exercises: exercises
            )
        }
        let autopilot = WorkoutAutopilotState(
            nextExerciseID: "back-squat",
            nextExerciseName: "Back Squat",
            nextTarget: WorkoutTarget(weight: 225, unit: "lb", repRange: 5...6, targetRPE: 8),
            bestCue: "Brace before the descent and keep the bar path stacked over midfoot.",
            recommendationReason: "Readiness is strong, but keep one rep in reserve after last week's volume.",
            suggestedAction: .hold
        )
        let recentSessions = [
            RecentSession(
                title: "Upper Strength",
                date: Self.fixedNow.addingTimeInterval(-2 * 86_400),
                durationMinutes: 58,
                exerciseIDs: ["bench-press", "barbell-row"],
                totalVolumeLoad: 18_420,
                averageRPE: 7.4,
                completedSetCount: 15
            ),
            RecentSession(
                title: "Lower Strength",
                date: Self.fixedNow.addingTimeInterval(-4 * 86_400),
                durationMinutes: 64,
                exerciseIDs: ["back-squat", "romanian-deadlift"],
                totalVolumeLoad: 22_860,
                averageRPE: 7.8,
                completedSetCount: 16
            ),
            RecentSession(
                title: "Upper Volume",
                date: Self.fixedNow.addingTimeInterval(-7 * 86_400),
                durationMinutes: 52,
                exerciseIDs: ["overhead-press", "lat-pulldown"],
                totalVolumeLoad: 16_120,
                averageRPE: 7.1,
                completedSetCount: 18
            ),
        ]

        return WorkoutDashboardSnapshotState(
            readiness: ReadinessAssessment(
                score: 86,
                brief: "Green light. Push the main lift, then keep accessories controlled.",
                factors: [
                    ReadinessAssessment.Factor(
                        name: "Sleep",
                        impact: 8,
                        detail: "7.6h average with no major debt."
                    ),
                    ReadinessAssessment.Factor(
                        name: "Training load",
                        impact: -4,
                        detail: "Lower body volume is rising this week."
                    ),
                    ReadinessAssessment.Factor(
                        name: "HRV",
                        impact: 5,
                        detail: "Above your 28-day baseline."
                    ),
                ]
            ),
            autopilot: autopilot,
            recentSessions: recentSessions,
            athlete: AthleteProfile(
                name: "Maya Rivera",
                coachingStyle: .analytical,
                privacyMode: .standard,
                advancementLevel: .advanced,
                availableEquipment: [.barbell, .dumbbell, .machine, .bodyweight],
                sessionTimeBudgetMinutes: 60,
                weeklyTrainingDays: 4,
                preferredRepRange: 5...8
            ),
            nextWorkout: weeklyPlan[0],
            weeklyPlan: weeklyPlan,
            coachMemory: CoachMemory(entries: [
                CoachMemory.Entry(
                    createdAt: Self.fixedNow.addingTimeInterval(-86_400),
                    summary: "Prefers concise load guidance and conservative jumps on squats.",
                    theme: "preference"
                ),
            ]),
            isSessionActive: isSessionActive,
            activeWorkoutID: isSessionActive ? "snapshot-active-workout" : nil,
            activeWorkoutTitle: isSessionActive ? "Lower-body hypertrophy" : nil,
            loggedSetCountThisSession: isSessionActive ? 2 : 0,
            isHealthAuthorized: true,
            recovery: RecoveryContext(
                hrvMean7Day: 61,
                hrvBaseline28Day: 57,
                hrvDeltaPercent: 7,
                sleep7DayTotalHours: 53.2,
                sleepDailyTargetHours: 7.5,
                sleepDebtHours: 0.7,
                strengthLoad7DayKJ: 4_220,
                strengthLoad7DayMinutes: 174,
                appleWorkoutEffort7DayAverage: 7.2,
                appleWatchVitalsScore: 84
            ),
            operationalSignals: [
                OperationalSignalSummary(
                    id: "snapshot-relay",
                    title: "Coach relay",
                    message: "Healthy",
                    severity: .info
                ),
            ]
        )
    }

    private func imageSnapshot<Value: View>(
        colorScheme: ColorScheme,
        preferredContentSizeCategory: UIContentSizeCategory = .large
    ) -> Snapshotting<Value, UIImage> {
        let style: UIUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        let traits = UITraitCollection { traits in
            traits.userInterfaceStyle = style
            traits.preferredContentSizeCategory = preferredContentSizeCategory
            traits.layoutDirection = .leftToRight
            traits.accessibilityContrast = .normal
            traits.displayScale = 3
            traits.displayGamut = .SRGB
            traits.legibilityWeight = .regular
            traits.userInterfaceLevel = .base
        }
        return .image(
            precision: 0.99,
            perceptualPrecision: 0.98,
            layout: .fixed(width: Metrics.phone.width, height: Metrics.phone.height),
            traits: traits
        )
    }
}

private extension View {
    func dashboardSnapshotEnvironment(
        colorScheme: ColorScheme,
        dynamicTypeSize: DynamicTypeSize,
        reduceTransparency: Bool
    ) -> some View {
        environment(\.colorScheme, colorScheme)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.layoutDirection, .leftToRight)
            .environmentObject(VAToastPresenter())
            .vaGlassReduceTransparencyOverride(reduceTransparency)
    }
}
#endif
