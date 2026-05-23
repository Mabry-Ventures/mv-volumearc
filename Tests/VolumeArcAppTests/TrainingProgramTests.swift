#if canImport(SwiftData)
import SwiftData
import XCTest
import VolumeArcCore

final class TrainingProgramTests: XCTestCase {
    func testCuratedCatalogIncludesLaunchPrograms() {
        let programs = TrainingProgramCatalog.curated
        XCTAssertEqual(programs.count, 6)
        XCTAssertEqual(programs.map(\.id), [
            "starting-strength",
            "stronglifts-5x5",
            "531-bbb",
            "ppl-6-day",
            "upper-lower-4-day",
            "hst",
        ])
        XCTAssertEqual(TrainingProgramCatalog.fiveThreeOneBBB.sessionsPerWeek, 4)
        XCTAssertEqual(TrainingProgramCatalog.pushPullLegs6Day.difficulty, .intermediate)
        XCTAssertEqual(TrainingProgramCatalog.hypertrophySpecificTraining.equipmentRequirement, .fullGym)
    }

    func testCatalogLookupAndDisplayLabelsAreStable() {
        XCTAssertEqual(TrainingProgramCatalog.program(id: "ppl-6-day")?.name, "PPL 6-day")
        XCTAssertNil(TrainingProgramCatalog.program(id: "not-a-real-program"))

        XCTAssertEqual(TrainingProgramDifficulty.allCases.map(\.displayName), [
            "Novice",
            "Intermediate",
            "Advanced",
        ])
        XCTAssertEqual(TrainingProgramEquipmentRequirement.allCases.map(\.displayName), [
            "Barbell",
            "Barbell + bodyweight",
            "Full gym",
        ])
    }

    func testProgramWithoutSessionsHasNoScheduledContext() {
        let program = TrainingProgramDefinition(
            id: "empty",
            name: "Empty Program",
            author: "VolumeArc",
            weeks: 4,
            advancementCriteria: "Add sessions before assignment.",
            difficulty: .novice,
            equipmentRequirement: .barbell,
            sessions: []
        )

        XCTAssertEqual(program.weeklyWorkouts().count, 0)
        XCTAssertNil(program.scheduledSession(assignedAt: Self.date(year: 2026, month: 5, day: 23)))
    }

    func testWeeklyScheduleShiftsFirstSessionToAssignmentDay() {
        let calendar = Self.utcCalendar
        let saturday = Self.date(year: 2026, month: 5, day: 23)
        let schedule = TrainingProgramCatalog.startingStrength.weeklyWorkouts(
            startingOn: saturday,
            calendar: calendar
        )

        XCTAssertEqual(schedule.count, 3)
        XCTAssertEqual(schedule.first(where: { $0.dayOfWeek == 6 })?.title, "Starting Strength A")
        XCTAssertEqual(schedule.first(where: { $0.dayOfWeek == 1 })?.title, "Starting Strength B")
        XCTAssertEqual(schedule.first(where: { $0.dayOfWeek == 3 })?.title, "Starting Strength A")
    }

    func testScheduledSessionReportsWeekAndProgramDay() throws {
        let calendar = Self.utcCalendar
        let assignedAt = Self.date(year: 2026, month: 5, day: 18)
        let targetDate = Self.date(year: 2026, month: 6, day: 3)

        let context = try XCTUnwrap(TrainingProgramCatalog.fiveThreeOneBBB.scheduledSession(
            on: targetDate,
            assignedAt: assignedAt,
            calendar: calendar
        ))

        XCTAssertEqual(context.programName, "5/3/1 BBB")
        XCTAssertEqual(context.weekNumber, 3)
        XCTAssertEqual(context.dayNumber, 3)
        XCTAssertEqual(context.sessionTitle, "5/3/1 Bench")
        XCTAssertTrue(context.promptFragment.contains("Today's prescription"))
        XCTAssertTrue(context.promptFragment.contains("Week 3 / 16"))
    }

    @MainActor
    func testRepositoryHydratesCatalogAndAssignsProgramToTrainingPlan() throws {
        let calendar = Self.utcCalendar
        let startDate = Self.date(year: 2026, month: 5, day: 23)
        let container = try Self.makeContainer()
        let planRepository = SwiftDataTrainingPlanRepository(container: container)
        let repository = SwiftDataTrainingProgramRepository(
            container: container,
            trainingPlanRepository: planRepository
        )

        let programs = try repository.loadPrograms()
        XCTAssertEqual(programs.count, 6)

        let assigned = try repository.assignProgram(
            catalogIdentifier: "stronglifts-5x5",
            startDate: startDate,
            calendar: calendar
        )
        XCTAssertEqual(assigned.programID, "stronglifts-5x5")
        XCTAssertEqual(assigned.sessionTitle, "StrongLifts A")

        let active = try XCTUnwrap(repository.activeProgramContext(on: startDate, calendar: calendar))
        XCTAssertEqual(active.programName, "StrongLifts 5x5")

        let activeProgram = try XCTUnwrap(repository.activeProgram())
        XCTAssertEqual(activeProgram.id, "stronglifts-5x5")

        let weeklyPlan = try planRepository.weeklyWorkouts()
        XCTAssertEqual(weeklyPlan.count, 3)
        XCTAssertEqual(weeklyPlan.first(where: { $0.dayOfWeek == 6 })?.title, "StrongLifts A")
    }

    @MainActor
    func testRepositorySupportsCreateUpdateDelete() throws {
        let container = try Self.makeContainer()
        let repository = SwiftDataTrainingProgramRepository(container: container)

        let original = TrainingProgramDefinition(
            id: "custom-test",
            name: "Custom Test",
            author: "VolumeArc",
            weeks: 4,
            advancementCriteria: "Add reps first.",
            difficulty: .novice,
            equipmentRequirement: .barbellAndBodyweight,
            sessions: [
                TrainingProgramSessionTemplate(
                    id: "custom-test-a",
                    dayOfWeek: 1,
                    title: "Custom A",
                    focus: "Full body",
                    exerciseNames: ["Back Squat", "Bench Press"],
                    prescription: "Squat 3x5, bench 3x5"
                ),
            ]
        )

        try repository.createProgram(original)
        XCTAssertTrue(try repository.loadPrograms().contains { $0.id == "custom-test" })

        let updated = TrainingProgramDefinition(
            id: "custom-test",
            name: "Custom Test Updated",
            author: "VolumeArc",
            weeks: 6,
            advancementCriteria: "Add load when all reps are clean.",
            difficulty: .intermediate,
            equipmentRequirement: .barbell,
            sessions: original.sessions
        )
        try repository.updateProgram(updated)

        let reloaded = try XCTUnwrap(try repository.loadPrograms().first { $0.id == "custom-test" })
        XCTAssertEqual(reloaded.name, "Custom Test Updated")
        XCTAssertEqual(reloaded.weeks, 6)

        try repository.deleteProgram(identifier: "custom-test")
        XCTAssertFalse(try repository.loadPrograms().contains { $0.id == "custom-test" })
    }

    func testCoachContextIncludesActiveProgramFragment() {
        let program = ActiveTrainingProgramContext(
            programID: "531-bbb",
            programName: "5/3/1 BBB",
            author: "Jim Wendler",
            weekNumber: 3,
            totalWeeks: 16,
            dayNumber: 2,
            sessionsPerWeek: 4,
            sessionTitle: "5/3/1 Deadlift",
            sessionFocus: "Deadlift plus posterior chain",
            prescription: "5/3/1 deadlift, 5x10 deadlift at BBB load",
            advancementCriteria: "Advance training maxes after each wave."
        )
        let context = CoachContext(
            athleteName: "Sam",
            advancementLevel: "intermediate",
            readinessScore: 82,
            readinessBrief: "Ready to train.",
            nextExercise: "Deadlift",
            nextTarget: "315lb x 5",
            recentSessionCount: 3,
            averageRPE: 7.4,
            program: program
        )

        let block = context.asPromptBlock(privacyMode: .standard)
        XCTAssertTrue(block.contains("## Active program"))
        XCTAssertTrue(block.contains("Week 3 / 16, Day 2 / 4"))
        XCTAssertTrue(block.contains("Today's prescription: 5/3/1 deadlift"))
    }

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static func date(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = utcCalendar
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        // Force unwrap is safe for fixed Gregorian fixture dates.
        // swiftlint:disable:next force_unwrapping
        return components.date!
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(VolumeArcSchemaV5.models)
        let config = ModelConfiguration(
            "TrainingProgramTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: VolumeArcSchemaMigrationPlan.self,
            configurations: [config]
        )
    }
}
#endif
