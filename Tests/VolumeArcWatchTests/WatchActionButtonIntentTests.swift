import AppIntents
import XCTest
@testable import VolumeArcCore

final class WatchActionButtonIntentTests: XCTestCase {
    override func tearDown() async throws {
        await WatchActionButtonRuntime.shared.resetForTesting()
        try await super.tearDown()
    }

    func test_startActionButtonIntentQueuesCommandAndRecordsTelemetry() async throws {
        let store = IntentTestActionButtonCommandStore()
        let telemetry = InMemoryTelemetrySink()
        await WatchActionButtonRuntime.shared.configureForTesting(
            commandStore: store,
            telemetrySink: telemetry
        )

        _ = try await VolumeArcStartActionButtonWorkoutIntent().perform()

        let records = await store.drain()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.command, .startActiveWorkout)
        XCTAssertEqual(record.actionName, VolumeArcActionButtonActionName.startActiveWorkout)

        let event = try XCTUnwrap(telemetry.currentEvents.last)
        XCTAssertEqual(event.category, "watch.action_button")
        XCTAssertEqual(event.name, "fired")
        XCTAssertEqual(event.metadata["action"], VolumeArcActionButtonActionName.startActiveWorkout)
    }

    func test_logNextSetActionButtonIntentQueuesCommandAndRecordsTelemetry() async throws {
        let store = IntentTestActionButtonCommandStore()
        let telemetry = InMemoryTelemetrySink()
        await WatchActionButtonRuntime.shared.configureForTesting(
            commandStore: store,
            telemetrySink: telemetry
        )

        _ = try await VolumeArcLogNextSetActionButtonIntent().perform()

        let records = await store.drain()
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(record.command, .logNextSet)
        XCTAssertEqual(record.actionName, VolumeArcActionButtonActionName.logNextSet)

        let event = try XCTUnwrap(telemetry.currentEvents.last)
        XCTAssertEqual(event.category, "watch.action_button")
        XCTAssertEqual(event.name, "fired")
        XCTAssertEqual(event.metadata["action"], VolumeArcActionButtonActionName.logNextSet)
    }

    func test_startIntentExposesSuggestedStrengthWorkout() {
        let suggested = VolumeArcStartActionButtonWorkoutIntent.suggestedWorkouts

        XCTAssertEqual(suggested.count, 1)
        XCTAssertEqual(suggested.first?.workoutStyle, .strength)
    }

    func test_actionButtonBindingHintIsLimitedToUltraModels() {
        XCTAssertTrue(
            WatchActionButtonAvailability.isLikelyUltra(
                model: "Apple Watch Ultra",
                localizedModel: "Apple Watch Ultra 2"
            )
        )
        XCTAssertFalse(
            WatchActionButtonAvailability.isLikelyUltra(
                model: "Apple Watch Series 10",
                localizedModel: "Apple Watch"
            )
        )
    }
}

private actor IntentTestActionButtonCommandStore: WatchActionButtonCommandStoring {
    private var records: [WatchActionButtonCommandRecord] = []

    func enqueue(_ record: WatchActionButtonCommandRecord) async {
        records.append(record)
    }

    func drain() async -> [WatchActionButtonCommandRecord] {
        defer { records.removeAll() }
        return records
    }
}
