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

    func testScheduledSessionDoesNotAdvanceWeekForRestDayAfterCalendarWrap() throws {
        let calendar = Self.utcCalendar
        let assignedAt = Self.date(year: 2026, month: 5, day: 23)
        let nextDay = Self.date(year: 2026, month: 5, day: 24)

        let context = try XCTUnwrap(TrainingProgramCatalog.startingStrength.scheduledSession(
            on: nextDay,
            assignedAt: assignedAt,
            calendar: calendar
        ))

        XCTAssertEqual(context.weekNumber, 1)
        XCTAssertEqual(context.dayNumber, 2)
        XCTAssertEqual(context.sessionTitle, "Starting Strength B")
    }

    func testScheduledSessionAdvancesWeekWhenNextSessionWrapsToFirstProgramDay() throws {
        let calendar = Self.utcCalendar
        let assignedAt = Self.date(year: 2026, month: 5, day: 23)
        let fridayBeforeNextWeek = Self.date(year: 2026, month: 5, day: 29)

        let context = try XCTUnwrap(TrainingProgramCatalog.startingStrength.scheduledSession(
            on: fridayBeforeNextWeek,
            assignedAt: assignedAt,
            calendar: calendar
        ))

        XCTAssertEqual(context.weekNumber, 2)
        XCTAssertEqual(context.dayNumber, 1)
        XCTAssertEqual(context.sessionTitle, "Starting Strength A")
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

        let context = ModelContext(container)
        context.insert(Self.trainingProgramRecord(
            from: TrainingProgramCatalog.strongLifts5x5,
            updatedAt: startDate.addingTimeInterval(60)
        ))
        try context.save()

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

        let activeRecords = try ModelContext(container).fetch(FetchDescriptor<TrainingProgramRecord>(
            predicate: #Predicate<TrainingProgramRecord> { program in
                program.isActive
            }
        ))
        XCTAssertEqual(activeRecords.count, 1)

        let nextStartDate = Self.date(year: 2026, month: 5, day: 25)
        let reassigned = try repository.assignProgram(
            catalogIdentifier: "hst",
            startDate: nextStartDate,
            calendar: calendar
        )
        XCTAssertEqual(reassigned.programID, "hst")

        let replacementPlan = try planRepository.weeklyWorkouts()
        XCTAssertEqual(replacementPlan.count, 3)
        XCTAssertTrue(replacementPlan.contains { $0.title == "HST Full Body A" })
        XCTAssertFalse(replacementPlan.contains { $0.title == "StrongLifts A" })

        let reassignedActiveRecords = try ModelContext(container).fetch(FetchDescriptor<TrainingProgramRecord>(
            predicate: #Predicate<TrainingProgramRecord> { program in
                program.isActive
            }
        ))
        XCTAssertEqual(reassignedActiveRecords.count, 1)

        let reassignedContext = try XCTUnwrap(repository.activeProgramContext(
            on: nextStartDate,
            calendar: calendar
        ))
        XCTAssertEqual(reassignedContext.programID, "hst")

        let reassignedProgram = try XCTUnwrap(repository.activeProgram())
        XCTAssertEqual(reassignedProgram.id, "hst")
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

    @MainActor
    func testDashboardLoaderMergesPersistedOverridesWithCuratedCatalog() async throws {
        let container = try Self.makeContainer()
        let repository = SwiftDataTrainingProgramRepository(container: container)
        let override = TrainingProgramDefinition(
            id: TrainingProgramCatalog.startingStrength.id,
            name: "Starting Strength Custom",
            author: TrainingProgramCatalog.startingStrength.author,
            weeks: TrainingProgramCatalog.startingStrength.weeks,
            advancementCriteria: TrainingProgramCatalog.startingStrength.advancementCriteria,
            difficulty: TrainingProgramCatalog.startingStrength.difficulty,
            equipmentRequirement: TrainingProgramCatalog.startingStrength.equipmentRequirement,
            sessions: TrainingProgramCatalog.startingStrength.sessions
        )
        try repository.updateProgram(override)
        try repository.createProgram(Self.customProgram(identifier: "custom-dashboard"))

        let snapshot = try await DashboardRefreshLoader(container: container).load(sessionFetchLimit: 5)

        XCTAssertEqual(snapshot.trainingPrograms.count, 7)
        XCTAssertEqual(snapshot.trainingPrograms.first?.id, "starting-strength")
        XCTAssertEqual(snapshot.trainingPrograms.first?.name, "Starting Strength Custom")
        XCTAssertEqual(snapshot.trainingPrograms.last?.id, "custom-dashboard")
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

    private static func customProgram(identifier: String) -> TrainingProgramDefinition {
        TrainingProgramDefinition(
            id: identifier,
            name: "Custom Test",
            author: "VolumeArc",
            weeks: 4,
            advancementCriteria: "Add reps first.",
            difficulty: .novice,
            equipmentRequirement: .barbellAndBodyweight,
            sessions: [
                TrainingProgramSessionTemplate(
                    id: "\(identifier)-a",
                    dayOfWeek: 1,
                    title: "Custom A",
                    focus: "Full body",
                    exerciseNames: ["Back Squat", "Bench Press"],
                    prescription: "Squat 3x5, bench 3x5"
                ),
            ]
        )
    }

    private static func trainingProgramRecord(
        from definition: TrainingProgramDefinition,
        updatedAt: Date
    ) -> TrainingProgramRecord {
        guard let sessionsJSON = SyncPayloadCodec.encode(definition.sessions) else {
            XCTFail("Expected training program sessions to encode")
            return TrainingProgramRecord()
        }
        return TrainingProgramRecord(
            identifier: definition.id,
            catalogIdentifier: definition.id,
            name: definition.name,
            author: definition.author,
            weeks: definition.weeks,
            sessionsPerWeek: definition.sessionsPerWeek,
            advancementCriteria: definition.advancementCriteria,
            difficultyTier: definition.difficulty.rawValue,
            equipmentRequirement: definition.equipmentRequirement.rawValue,
            sessionsJSON: sessionsJSON,
            updatedAt: updatedAt
        )
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
