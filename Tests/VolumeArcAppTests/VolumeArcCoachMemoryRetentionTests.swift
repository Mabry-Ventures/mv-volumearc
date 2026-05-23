#if canImport(SwiftData)
import XCTest
import SwiftData
import VolumeArcCore

/// VOL-79: retention policy tests for `SwiftDataCoachMemoryRepository`.
///
/// Policy: retain at most 50 rows AND at most 30 days of history,
/// whichever is smaller. Pruning happens on every `append(...)` and
/// unconditionally on `pruneLegacyRows()` (called once at launch).
@MainActor
final class VolumeArcCoachMemoryRetentionTests: XCTestCase {
    private var container: ModelContainer!
    private var outboundQueue: SwiftDataOutboundSyncQueue!
    private var telemetrySink: MockTelemetrySink!
    private var repository: SwiftDataCoachMemoryRepository!

    /// Mirrors the `private static let maxRows = 50` on the repository.
    /// Kept here as a separate constant so an accidental policy change
    /// surfaces as a test failure rather than a silent pass.
    private let maxRows = 50
    /// Mirrors `private static let retentionDays = 30` on the repository.
    private let retentionDays = 30

    override func setUp() async throws {
        container = try Self.makeContainer()
        outboundQueue = SwiftDataOutboundSyncQueue(container: container)
        telemetrySink = MockTelemetrySink()
        repository = SwiftDataCoachMemoryRepository(
            container: container,
            outboundQueue: outboundQueue,
            telemetrySink: telemetrySink
        )
    }

    override func tearDown() async throws {
        container = nil
        outboundQueue = nil
        telemetrySink = nil
        repository = nil
    }

    // MARK: - Mixed TTL + size cap

    /// 100 rows with varied timestamps. After `append(...)`, only rows
    /// within the last 30 days AND only the most recent `maxRows`
    /// should remain.
    func testAppendPrunesMixOfStaleAndOverflowRows() throws {
        // 60 rows over the last 30 days (stamped every ~half-day so they
        // are all within the TTL) and 40 rows older than 30 days.
        let now = Date()
        var seededDates: [Date] = []
        for halfDay in 0..<60 {
            seededDates.append(now.addingTimeInterval(-Double(halfDay) * 43_200))
        }
        for day in 0..<40 {
            // 31..70 days ago — all outside the 30-day TTL.
            seededDates.append(now.addingTimeInterval(-Double(31 + day) * 86_400))
        }
        try seedRecords(at: seededDates)

        try repository.append(content: "brand-new turn", theme: "debug")

        let remaining = try fetchAllSortedNewestFirst()
        // The append added 1 row. maxRows=50. TTL=30 days.
        // Only rows within the TTL stay, and at most `maxRows` of them.
        XCTAssertEqual(remaining.count, maxRows, "Size cap should clamp to 50 after the append")

        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        for record in remaining {
            XCTAssertGreaterThanOrEqual(
                record.createdAt,
                cutoff,
                "All retained rows must be within the 30-day TTL"
            )
        }

        // The newly appended record must still be present.
        XCTAssertTrue(
            remaining.contains(where: { $0.content == "brand-new turn" }),
            "The row just appended must survive the sweep"
        )
    }

    // MARK: - Size cap dominates

    /// 100 rows all within the last 7 days. After `append(...)` the
    /// size cap should drive the trim — exactly `maxRows` rows remain.
    func testAppendSizeCapTrimsToMaxRowsWhenAllWithinTTL() throws {
        let now = Date()
        var seededDates: [Date] = []
        for minute in 0..<100 {
            // 0 to ~100 minutes ago — all well within 30 days.
            seededDates.append(now.addingTimeInterval(-Double(minute) * 60))
        }
        try seedRecords(at: seededDates)

        try repository.append(content: "another recent turn", theme: "recent")

        let remaining = try fetchAllSortedNewestFirst()
        XCTAssertEqual(
            remaining.count,
            maxRows,
            "Size cap must trim to exactly \(maxRows) when all 101 rows are within the TTL"
        )

        // The appended row is the newest and must survive.
        XCTAssertEqual(
            remaining.first?.content,
            "another recent turn",
            "The newly appended row is the newest and must be retained"
        )
    }

    // MARK: - TTL dominates

    /// 100 rows all older than 60 days. After `append(...)` every seeded
    /// row must be pruned — only the new row remains.
    func testAppendTTLPrunesAllStaleRowsLeavingOnlyTheNewOne() throws {
        let now = Date()
        var seededDates: [Date] = []
        for day in 0..<100 {
            // 61 to 160 days ago — all outside the 30-day TTL.
            seededDates.append(now.addingTimeInterval(-Double(61 + day) * 86_400))
        }
        try seedRecords(at: seededDates)

        try repository.append(content: "only survivor", theme: "ttl")

        let remaining = try fetchAllSortedNewestFirst()
        XCTAssertEqual(
            remaining.count,
            1,
            "TTL must prune all 100 stale rows, leaving only the appended row"
        )
        XCTAssertEqual(remaining.first?.content, "only survivor")
    }

    // MARK: - pruneLegacyRows()

    /// Launch-time housekeeping: `pruneLegacyRows()` must enforce the
    /// same policy without needing an append first.
    func testPruneLegacyRowsTrimsOnExistingInstalls() throws {
        let now = Date()
        var seededDates: [Date] = []
        // 70 rows within last 30 days (all under the TTL).
        for hour in 0..<70 {
            seededDates.append(now.addingTimeInterval(-Double(hour) * 3_600))
        }
        // 30 rows older than 30 days.
        for day in 0..<30 {
            seededDates.append(now.addingTimeInterval(-Double(31 + day) * 86_400))
        }
        try seedRecords(at: seededDates)

        try repository.pruneLegacyRows()

        let remaining = try fetchAllSortedNewestFirst()
        XCTAssertEqual(
            remaining.count,
            maxRows,
            "pruneLegacyRows should clamp to \(maxRows) when more than that many rows are within the TTL"
        )
    }

    // MARK: - Telemetry

    /// Confirm the `coach.memory.pruned` telemetry event fires with a
    /// `removedCount` matching the number of deleted rows. No scaffolding
    /// beyond injecting the mock sink.
    func testPruneEmitsTelemetryWithRemovedCount() throws {
        let now = Date()
        // Seed 60 hourly rows within the last 30 days + 10 rows older
        // than 30 days. After `append(...)` we have 61 rows within the
        // TTL (60 + the appended one) and 10 stale rows. Size cap trims
        // 61 → 50, so 11 within-TTL rows are dropped plus all 10 stale
        // rows = 21 removed total.
        var seededDates: [Date] = []
        for hour in 0..<60 {
            seededDates.append(now.addingTimeInterval(-Double(hour) * 3_600))
        }
        for day in 0..<10 {
            seededDates.append(now.addingTimeInterval(-Double(31 + day) * 86_400))
        }
        try seedRecords(at: seededDates)

        try repository.append(content: "telemetry turn", theme: "telemetry")

        let pruneEvents = telemetrySink.recordedEvents.filter {
            $0.name == "coach.memory.pruned"
        }
        XCTAssertEqual(pruneEvents.count, 1, "Exactly one prune event should fire per append that deletes rows")
        let event = try XCTUnwrap(pruneEvents.first)
        XCTAssertEqual(event.severity, .info)
        XCTAssertEqual(event.metadata["removedCount"], "21")
    }

    // MARK: - Helpers

    /// Seed `CoachMemoryRecord`s directly into the container at the given
    /// timestamps. Bypasses the repository's `append` so we can stamp
    /// `createdAt` ourselves for deterministic TTL/size-cap coverage.
    private func seedRecords(at dates: [Date]) throws {
        let context = ModelContext(container)
        for date in dates {
            context.insert(CoachMemoryRecord(
                identifier: UUID().uuidString,
                content: "seed @ \(date.timeIntervalSince1970)",
                theme: "",
                createdAt: date
            ))
        }
        try context.save()
    }

    private func fetchAllSortedNewestFirst() throws -> [CoachMemoryRecord] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<CoachMemoryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(VolumeArcSchemaV5.models)
        let config = ModelConfiguration(
            "CoachMemoryRetentionTest-\(UUID().uuidString)",
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
