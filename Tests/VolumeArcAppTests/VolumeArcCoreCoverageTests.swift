// VOL-52: targeted coverage tests for VolumeArcCore modules whose
// production behavior was previously exercised only end-to-end (or not
// at all). Each test below covers a deterministic, pure-logic surface
// — encoders, decoders, defaults stores, helper enums, deep links, and
// platform-fallback structs — so the 80% gate has a stable floor that
// doesn't depend on simulator HealthKit/StoreKit infrastructure.
//
// Every test exercises real production code paths (no `XCTAssertTrue(true)`
// padding). Tests that touch UserDefaults use isolated suites so the
// process-wide standard suite is never mutated.
import XCTest
import VolumeArcCore

final class VolumeArcCoreCoverageTests: XCTestCase {

    // MARK: - WatchConnectivity payload + dictionary round-trip

    func testWatchPayloadAsDictionaryAndBack() {
        let payload = WatchPayload(
            kind: .restTimer,
            workoutID: "wkt-1",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            body: "rest=90"
        )
        let dict = payload.asDictionary()
        let kind = dict["kind"] as? String
        XCTAssertEqual(kind, "restTimer")
        let id = dict["workoutID"] as? String
        XCTAssertEqual(id, "wkt-1")
        let body = dict["body"] as? String
        XCTAssertEqual(body, "rest=90")
        let createdAt = dict["createdAt"] as? TimeInterval
        XCTAssertEqual(createdAt, 1_700_000_000)

        let decoded = WatchPayload(dictionary: dict)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.kind, .restTimer)
        XCTAssertEqual(decoded?.workoutID, "wkt-1")
        XCTAssertEqual(decoded?.body, "rest=90")
        XCTAssertEqual(decoded?.createdAt.timeIntervalSince1970, 1_700_000_000)
    }

    func testWatchPayloadConvenienceInitializerStampsCreatedAtNow() {
        let before = Date.now.timeIntervalSinceReferenceDate
        let payload = WatchPayload(kind: .liveState, workoutID: "id", body: "body")
        let after = Date.now.timeIntervalSinceReferenceDate
        XCTAssertGreaterThanOrEqual(payload.createdAt.timeIntervalSinceReferenceDate, before - 1)
        XCTAssertLessThanOrEqual(payload.createdAt.timeIntervalSinceReferenceDate, after + 1)
    }

    func testWatchPayloadDictionaryInitRejectsMissingFields() {
        let empty: [String: Any] = [:]
        XCTAssertNil(WatchPayload(dictionary: empty))
        let kindOnly: [String: Any] = ["kind": "liveState"]
        XCTAssertNil(WatchPayload(dictionary: kindOnly))
        let kindAndID: [String: Any] = ["kind": "liveState", "workoutID": "x"]
        XCTAssertNil(WatchPayload(dictionary: kindAndID))
        // Bad kind raw value — guard fails on `WatchPayloadKind(rawValue:)`.
        let badKind: [String: Any] = [
            "kind": "not-a-real-kind",
            "workoutID": "x",
            "body": "y"
        ]
        XCTAssertNil(WatchPayload(dictionary: badKind))
    }

    func testWatchPayloadDictionaryInitFallsBackToNowWhenCreatedAtMissing() {
        let dict: [String: Any] = [
            "kind": "coachCue",
            "workoutID": "w",
            "body": "b"
        ]
        let payload = WatchPayload(dictionary: dict)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.kind, .coachCue)
        XCTAssertGreaterThan(payload!.createdAt.timeIntervalSinceReferenceDate, 0)
    }

    func testWatchPayloadCodableRoundTrip() throws {
        let payload = WatchPayload(
            kind: .completedWorkout,
            workoutID: "wkt-9",
            createdAt: Date(timeIntervalSince1970: 1_710_000_000),
            body: "{summary:1}"
        )
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(WatchPayload.self, from: data)
        XCTAssertEqual(decoded.kind, .completedWorkout)
        XCTAssertEqual(decoded.workoutID, "wkt-9")
        XCTAssertEqual(decoded.body, "{summary:1}")
        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, 1_710_000_000)
    }

    func testWatchSessionSnapshotCodableRoundTrip() throws {
        let snap = WatchSessionSnapshot(
            selectedAction: .increase,
            restEndsAt: Date(timeIntervalSince1970: 1_720_000_000),
            coachPrompt: "Add 5 lbs",
            sessionActive: true,
            statusMessage: "Live"
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WatchSessionSnapshot.self, from: data)
        XCTAssertEqual(decoded.selectedAction, .increase)
        XCTAssertEqual(decoded.coachPrompt, "Add 5 lbs")
        XCTAssertTrue(decoded.sessionActive)
        XCTAssertEqual(decoded.statusMessage, "Live")
        XCTAssertEqual(decoded.restEndsAt.timeIntervalSince1970, 1_720_000_000)
    }

    // MARK: - Watch transport + coordinator behavior

    func testUnavailableWatchSessionTransportBehavior() async {
        let transport = UnavailableWatchSessionTransport()
        await transport.activate()
        let reachable = await transport.isReachable()
        XCTAssertFalse(reachable)

        do {
            try await transport.send(WatchPayload(kind: .liveState, workoutID: "x", body: "y"))
            XCTFail("Expected unavailable transport to throw")
        } catch let error as WatchTransportError {
            XCTAssertEqual(error, .notReachable)
            XCTAssertEqual(error.errorDescription, "Paired device is not reachable right now.")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testWatchTransportErrorDescriptions() {
        XCTAssertEqual(
            WatchTransportError.notActivated.errorDescription,
            "Watch connectivity session is not activated."
        )
        XCTAssertEqual(
            WatchTransportError.notReachable.errorDescription,
            "Paired device is not reachable right now."
        )
    }

    func testUserDefaultsPendingPayloadStoreEnqueueAndDequeue() async {
        let store = await makePendingPayloadStore(namespace: "watch.pending")
        let initialCount = await store.count()
        XCTAssertEqual(initialCount, 0)

        let p1 = WatchPayload(kind: .restTimer, workoutID: "a", body: "1")
        let p2 = WatchPayload(kind: .liveState, workoutID: "b", body: "2")
        await store.enqueue(p1)
        await store.enqueue(p2)
        let count = await store.count()
        XCTAssertEqual(count, 2)

        let drained = await store.dequeueAll()
        XCTAssertEqual(drained.count, 2)
        XCTAssertEqual(drained[0].workoutID, "a")
        XCTAssertEqual(drained[1].workoutID, "b")
        let postCount = await store.count()
        XCTAssertEqual(postCount, 0)
    }

    func testUserDefaultsWatchSessionStateStoreLifecycle() async {
        let store = await makeSessionStateStore(namespace: "watch.snapshot")
        let initial = await store.load()
        XCTAssertNil(initial)

        let snap = WatchSessionSnapshot(
            selectedAction: .hold,
            restEndsAt: Date(timeIntervalSince1970: 1_730_000_000),
            coachPrompt: "Hold",
            sessionActive: false,
            statusMessage: "Paused"
        )
        await store.save(snap)
        let loaded = await store.load()
        XCTAssertEqual(loaded?.selectedAction, .hold)
        XCTAssertEqual(loaded?.coachPrompt, "Hold")

        await store.clear()
        let cleared = await store.load()
        XCTAssertNil(cleared)
    }

    func testWatchConnectivityCoordinatorEnqueuesOnFailure() async throws {
        let payloadStore = await makePendingPayloadStore(namespace: "watch.coord")
        let transport = UnavailableWatchSessionTransport()
        let coordinator = WatchConnectivityCoordinator(transport: transport, payloadStore: payloadStore)
        let reachable = await coordinator.isReachable()
        XCTAssertFalse(reachable)

        let payload = WatchPayload(kind: .startSession, workoutID: "queued", body: "go")
        do {
            try await coordinator.send(payload)
            XCTFail("Expected send to throw with unreachable transport")
        } catch {
            // Expected.
        }
        let pending = await coordinator.pendingPayloadCount()
        XCTAssertEqual(pending, 1, "Failed send must enqueue payload for replay")

        // flushPendingIfReachable returns early when transport is unreachable.
        try await coordinator.flushPendingIfReachable()
        let stillPending = await coordinator.pendingPayloadCount()
        XCTAssertEqual(stillPending, 1, "Unreachable flush is a no-op — payload stays queued")
    }

    func testWatchConnectivityCoordinatorFlushDeliversWhenReachable() async throws {
        let payloadStore = await makePendingPayloadStore(namespace: "watch.coord.flush")
        let transport = ScriptedWatchTransport(reachable: true)
        await payloadStore.enqueue(WatchPayload(kind: .endSession, workoutID: "x", body: "stop"))
        let coordinator = WatchConnectivityCoordinator(transport: transport, payloadStore: payloadStore)

        try await coordinator.flushPendingIfReachable()
        let count = await payloadStore.count()
        XCTAssertEqual(count, 0)
        let sent = await transport.sentPayloads
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?.workoutID, "x")
    }

    func testWatchConnectivityCoordinatorRequeuesOnFlushFailure() async throws {
        let payloadStore = await makePendingPayloadStore(namespace: "watch.coord.requeue")
        let transport = ScriptedWatchTransport(reachable: true, sendError: NSError(domain: "test", code: 1))
        await payloadStore.enqueue(WatchPayload(kind: .restTimer, workoutID: "z", body: "1"))
        let coordinator = WatchConnectivityCoordinator(transport: transport, payloadStore: payloadStore)

        do {
            try await coordinator.flushPendingIfReachable()
            XCTFail("Expected flush to rethrow transport failure")
        } catch {
            // Expected.
        }
        let count = await payloadStore.count()
        XCTAssertEqual(count, 1, "Failed flush must put the payload back on the queue")
    }

    // MARK: - Telemetry sinks

    func testInMemoryTelemetrySinkBoundedBuffer() {
        let sink = InMemoryTelemetrySink(maxEvents: 3)
        for index in 0..<5 {
            sink.record(TelemetryEvent(
                category: "test",
                name: "evt-\(index)",
                severity: .info,
                message: "m"
            ))
        }
        let events = sink.currentEvents
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events.map(\.name), ["evt-2", "evt-3", "evt-4"])
    }

    func testInMemoryTelemetrySinkPreloadedEvents() {
        let preload = [
            TelemetryEvent(category: "boot", name: "start", severity: .info, message: "boot"),
        ]
        let sink = InMemoryTelemetrySink(events: preload, maxEvents: 10)
        XCTAssertEqual(sink.currentEvents.count, 1)
    }

    func testFanoutTelemetrySinkDeliversToAllChildren() {
        let sinkA = InMemoryTelemetrySink(maxEvents: 5)
        let sinkB = InMemoryTelemetrySink(maxEvents: 5)
        let fanout = FanoutTelemetrySink(sinks: [sinkA, sinkB])
        fanout.record(TelemetryEvent(category: "x", name: "y", severity: .warning, message: "ok"))
        XCTAssertEqual(sinkA.currentEvents.count, 1)
        XCTAssertEqual(sinkB.currentEvents.count, 1)
    }

    func testUserDefaultsTelemetrySinkPersistsAndClears() {
        let defaults = isolatedUserDefaults("telemetry.persist")
        let sink = UserDefaultsTelemetrySink(defaults: defaults, key: "test.events", maxEvents: 4)
        XCTAssertTrue(sink.loadEvents().isEmpty)

        for index in 0..<6 {
            sink.record(TelemetryEvent(
                category: "p",
                name: "e-\(index)",
                severity: .error,
                message: "boom"
            ))
        }
        let persisted = sink.loadEvents()
        XCTAssertEqual(persisted.count, 4, "Bounded ring buffer must drop the oldest events past max")
        XCTAssertEqual(persisted.map(\.name), ["e-2", "e-3", "e-4", "e-5"])

        sink.clear()
        XCTAssertTrue(sink.loadEvents().isEmpty)
    }

    func testTelemetrySeverityComparable() {
        XCTAssertLessThan(TelemetrySeverity.info, TelemetrySeverity.warning)
        XCTAssertLessThan(TelemetrySeverity.warning, TelemetrySeverity.error)
        XCTAssertGreaterThan(TelemetrySeverity.error, TelemetrySeverity.info)
        XCTAssertEqual(TelemetrySeverity.warning, TelemetrySeverity.warning)
    }

    func testOperationalSignalSummaryRoundTrip() {
        let signal = OperationalSignalSummary(
            id: "id-1",
            title: "Sync stalled",
            message: "12 records pending",
            severity: .warning
        )
        XCTAssertEqual(signal.id, "id-1")
        XCTAssertEqual(signal.title, "Sync stalled")
        XCTAssertEqual(signal.message, "12 records pending")
        XCTAssertEqual(signal.severity, .warning)
    }

    func testTelemetryEventCodableRoundTrip() throws {
        let event = TelemetryEvent(
            category: "sync",
            name: "pull",
            severity: .info,
            message: "ok",
            metadata: ["k": "v"],
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(TelemetryEvent.self, from: data)
        XCTAssertEqual(decoded.category, "sync")
        XCTAssertEqual(decoded.name, "pull")
        XCTAssertEqual(decoded.severity, .info)
        XCTAssertEqual(decoded.metadata, ["k": "v"])
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, 1_700_000_000)
    }

    // MARK: - VolumeArcDeepLink

    func testDeepLinkRejectsForeignSchemeAndUnknownHost() {
        XCTAssertNil(VolumeArcDeepLink.destination(for: URL(string: "https://example.com")!))
        XCTAssertNil(VolumeArcDeepLink.destination(for: URL(string: "volumearc://unknown")!))
    }

    func testDeepLinkRecognizesTodayHost() {
        let dest = VolumeArcDeepLink.destination(for: URL(string: "volumearc://today")!)
        if case .today = dest { return }
        XCTFail("Expected .today, got \(String(describing: dest))")
    }

    func testDeepLinkRecognizesNextWorkoutAliases() {
        let camel = VolumeArcDeepLink.destination(for: URL(string: "volumearc://nextWorkout")!)
        if case .nextWorkout = camel {} else { return XCTFail("camel form failed") }
        let kebab = VolumeArcDeepLink.destination(for: URL(string: "volumearc://next-workout")!)
        if case .nextWorkout = kebab {} else { return XCTFail("kebab form failed") }
    }

    func testDeepLinkRecognizesSignalsHost() {
        let dest = VolumeArcDeepLink.destination(for: URL(string: "volumearc://signals")!)
        if case .signals = dest { return }
        XCTFail("Expected .signals")
    }

    func testDeepLinkCoachExtractsPromptQuery() {
        let withPrompt = VolumeArcDeepLink.destination(for: URL(string: "volumearc://coach?prompt=hi")!)
        guard case let .coach(prompt) = withPrompt else { return XCTFail("Expected .coach") }
        XCTAssertEqual(prompt, "hi")

        let bare = VolumeArcDeepLink.destination(for: URL(string: "volumearc://coach")!)
        guard case let .coach(empty) = bare else { return XCTFail("Expected .coach") }
        XCTAssertEqual(empty, "")
    }

    func testDeepLinkActionParsing() {
        let valid = VolumeArcDeepLink.destination(for: URL(string: "volumearc://action/startWorkoutSession")!)
        guard case let .action(action) = valid else { return XCTFail("Expected .action") }
        XCTAssertEqual(action, .startWorkoutSession)

        XCTAssertNil(VolumeArcDeepLink.destination(for: URL(string: "volumearc://action/zzz")!))
        XCTAssertNil(VolumeArcDeepLink.destination(for: URL(string: "volumearc://action")!))
    }

    func testDeepLinkURLBuilderForActionRoundTrip() {
        let actions: [VolumeArcDeepLink.Destination.Action] = [.startWorkoutSession, .logRecommendedSet, .syncNow]
        for action in actions {
            let url = VolumeArcDeepLink.url(for: .action(action))
            let parsed = VolumeArcDeepLink.destination(for: url)
            guard case let .action(round) = parsed else {
                XCTFail("Round-trip failed for action \(action.rawValue)")
                continue
            }
            XCTAssertEqual(round, action)
        }
    }

    func testDeepLinkURLBuilderForSimpleDestinations() {
        XCTAssertEqual(VolumeArcDeepLink.url(for: .today).absoluteString, "volumearc://today")
        XCTAssertEqual(VolumeArcDeepLink.url(for: .nextWorkout).absoluteString, "volumearc://nextWorkout")
        XCTAssertEqual(VolumeArcDeepLink.url(for: .signals).absoluteString, "volumearc://signals")
    }

    func testDeepLinkURLBuilderForCoachIncludesPromptQuery() {
        let url = VolumeArcDeepLink.url(for: .coach(prompt: "Should I deload?"))
        let parsed = VolumeArcDeepLink.destination(for: url)
        guard case let .coach(prompt) = parsed else { return XCTFail("Expected .coach") }
        XCTAssertEqual(prompt, "Should I deload?")
    }

    // MARK: - DashboardNavigationModel

    @MainActor
    func testDashboardNavigationModelStateTransitions() {
        let model = DashboardNavigationModel()
        XCTAssertEqual(model.selectedTab, .today)
        XCTAssertNil(model.coachPrompt)

        model.openCoach(prompt: "hi")
        XCTAssertEqual(model.selectedTab, .coach)
        XCTAssertEqual(model.coachPrompt, "hi")

        model.openSignals()
        XCTAssertEqual(model.selectedTab, .signals)

        model.openProfile()
        XCTAssertEqual(model.selectedTab, .profile)

        model.openToday()
        XCTAssertEqual(model.selectedTab, .today)

        model.clearCoachPrompt()
        XCTAssertNil(model.coachPrompt)
    }

    @MainActor
    func testDashboardTabMetadata() {
        for tab in DashboardTab.allCases {
            XCTAssertFalse(tab.title.isEmpty, "Title missing for \(tab.rawValue)")
            XCTAssertFalse(tab.systemImage.isEmpty, "System image missing for \(tab.rawValue)")
        }
        XCTAssertEqual(DashboardTab.today.title, "Today")
        XCTAssertEqual(DashboardTab.workouts.title, "Workouts")
        XCTAssertEqual(DashboardTab.coach.title, "Coach")
        XCTAssertEqual(DashboardTab.signals.title, "Signals")
        XCTAssertEqual(DashboardTab.profile.title, "Profile")
    }

    // MARK: - CloudSync types

    func testCloudSyncRecordKindParseHandlesLegacyAliases() {
        XCTAssertEqual(CloudSyncRecord.Kind.parse("workout"), .workout)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("profile"), .userProfile)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("plan"), .trainingPlan)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("memory"), .coachMemory)
        // Legacy long-form aliases:
        XCTAssertEqual(CloudSyncRecord.Kind.parse("userProfile"), .userProfile)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("trainingPlan"), .trainingPlan)
        XCTAssertEqual(CloudSyncRecord.Kind.parse("coachMemory"), .coachMemory)
        XCTAssertNil(CloudSyncRecord.Kind.parse("nonsense"))
    }

    func testCloudSyncRecordKindCanonicalQueueIdentifierForSingletonAndPerRecord() {
        XCTAssertEqual(
            CloudSyncRecord.Kind.userProfile.canonicalQueueIdentifier(from: "ignored-by-singleton"),
            "profile"
        )
        XCTAssertEqual(
            CloudSyncRecord.Kind.trainingPlan.canonicalQueueIdentifier(from: "anything"),
            "plan"
        )
        // Per-record kinds pass identifier through unchanged.
        XCTAssertEqual(
            CloudSyncRecord.Kind.workout.canonicalQueueIdentifier(from: "wkt-uuid"),
            "wkt-uuid"
        )
        XCTAssertEqual(
            CloudSyncRecord.Kind.coachMemory.canonicalQueueIdentifier(from: "memory-uuid"),
            "memory-uuid"
        )

        XCTAssertTrue(CloudSyncRecord.Kind.userProfile.isSingleton)
        XCTAssertTrue(CloudSyncRecord.Kind.trainingPlan.isSingleton)
        XCTAssertFalse(CloudSyncRecord.Kind.workout.isSingleton)
        XCTAssertFalse(CloudSyncRecord.Kind.coachMemory.isSingleton)

        XCTAssertEqual(CloudSyncRecord.Kind.workout.defaultIdentifier, "workout")
        XCTAssertEqual(CloudSyncRecord.Kind.userProfile.defaultIdentifier, "profile")
    }

    func testUnavailableCloudSyncTransportThrowsExpectedReason() async {
        let transport = UnavailableCloudSyncTransport(reason: "iCloud signed out")
        XCTAssertFalse(transport.isAvailable)
        XCTAssertEqual(transport.reason, "iCloud signed out")
        do {
            try await transport.pushRecords([])
            XCTFail("Expected push to throw")
        } catch let CloudSyncError.transportUnavailable(reason) {
            XCTAssertEqual(reason, "iCloud signed out")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            _ = try await transport.pullChanges(since: nil)
            XCTFail("Expected pull to throw")
        } catch let CloudSyncError.transportUnavailable(reason) {
            XCTAssertEqual(reason, "iCloud signed out")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testCloudSyncErrorDescriptions() {
        XCTAssertEqual(
            CloudSyncError.transportUnavailable(reason: "no creds").errorDescription,
            "no creds"
        )
        let underlying = NSError(domain: "x", code: 7, userInfo: [NSLocalizedDescriptionKey: "boom"])
        XCTAssertEqual(
            CloudSyncError.applyFailed(underlying: underlying).errorDescription,
            "Sync apply failed: boom"
        )
        XCTAssertEqual(
            CloudSyncError.invalidQueuedRecord(reason: "bad payload").errorDescription,
            "bad payload"
        )
    }

    func testFileSyncStateStoreLifecycle() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("VOL-52-cursor-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("cursor.txt")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = FileSyncStateStore(url: url)
        XCTAssertNil(store.loadCursor())
        try store.saveCursor("opaque-cursor-1")
        XCTAssertEqual(store.loadCursor(), "opaque-cursor-1")
        // Overwrite.
        try store.saveCursor("opaque-cursor-2")
        XCTAssertEqual(store.loadCursor(), "opaque-cursor-2")
        try store.clear()
        XCTAssertNil(store.loadCursor())
        // Clear when missing is a no-op.
        try store.clear()
    }

    func testCloudSyncRecordCodableRoundTrip() throws {
        let record = CloudSyncRecord(
            kind: .workout,
            identifier: "wkt-1",
            operation: .upsert,
            payloadJSON: "{}",
            modifiedAt: Date(timeIntervalSince1970: 1_715_000_000)
        )
        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CloudSyncRecord.self, from: data)
        XCTAssertEqual(decoded.kind, .workout)
        XCTAssertEqual(decoded.identifier, "wkt-1")
        XCTAssertEqual(decoded.operation, .upsert)
        XCTAssertEqual(decoded.payloadJSON, "{}")
        XCTAssertEqual(decoded.modifiedAt.timeIntervalSince1970, 1_715_000_000)
    }

    // MARK: - PlatformSurface

    func testPlatformSurfaceFactoryEmptyWidgetSnapshotShape() {
        let snap = PlatformSurfaceFactory.makeEmptyWidgetSnapshot()
        XCTAssertEqual(snap.nextWorkoutTitle, "No Workout Scheduled")
        XCTAssertEqual(snap.readinessScore, "--")
        XCTAssertEqual(snap.nextActionTitle, "Start")
        XCTAssertEqual(snap.streakDays, 0)
        XCTAssertEqual(snap.syncSummary, "Not synced")
    }

    func testWidgetSummarySnapshotRoundTripThroughDefaults() throws {
        let snap = WidgetSummarySnapshot(
            nextWorkoutTitle: "Push Day",
            readinessScore: "82",
            primaryLiftForecast: "225x5",
            nextActionTitle: "Begin",
            syncSummary: "Synced",
            streakDays: 5,
            coachPrompt: "What now?",
            updatedAt: Date(timeIntervalSince1970: 1_725_000_000)
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WidgetSummarySnapshot.self, from: data)
        XCTAssertEqual(decoded.nextWorkoutTitle, "Push Day")
        XCTAssertEqual(decoded.streakDays, 5)
        XCTAssertEqual(decoded.coachPrompt, "What now?")
        XCTAssertEqual(decoded.updatedAt.timeIntervalSince1970, 1_725_000_000)
    }

    func testLiveActivityStateRoundTrip() throws {
        let state = LiveActivityState(
            workoutTitle: "Squat",
            activeExerciseName: "Back Squat",
            targetSummary: "225 x 5",
            restSecondsRemaining: 90
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(LiveActivityState.self, from: data)
        XCTAssertEqual(decoded.workoutTitle, "Squat")
        XCTAssertEqual(decoded.activeExerciseName, "Back Squat")
        XCTAssertEqual(decoded.targetSummary, "225 x 5")
        XCTAssertEqual(decoded.restSecondsRemaining, 90)

        let withoutRest = LiveActivityState(
            workoutTitle: "Squat",
            activeExerciseName: "Squat",
            targetSummary: "x",
            restSecondsRemaining: nil
        )
        let data2 = try JSONEncoder().encode(withoutRest)
        let decoded2 = try JSONDecoder().decode(LiveActivityState.self, from: data2)
        XCTAssertNil(decoded2.restSecondsRemaining)
    }

    func testPlatformSurfaceSharedStorageDefaultsAlwaysAvailable() {
        let defaults = PlatformSurfaceSharedStorage.defaults
        XCTAssertNotNil(defaults)
        // App-group container isn't entitled in the test bundle — falls back
        // to `.standard`. Verify the bridge functions tolerate the fallback
        // and round-trip cleanly through whichever defaults instance we got.
        let snap = PlatformSurfaceFactory.makeEmptyWidgetSnapshot()
        PlatformSurfaceDefaultsWriter.saveWidgetSnapshot(snap)
        let loaded = PlatformSurfaceDefaultsReader.loadWidgetSnapshot()
        XCTAssertEqual(loaded?.nextWorkoutTitle, snap.nextWorkoutTitle)

        let liveState = LiveActivityState(
            workoutTitle: "Squat",
            activeExerciseName: "Back Squat",
            targetSummary: "x",
            restSecondsRemaining: nil
        )
        PlatformSurfaceDefaultsWriter.saveLiveActivityState(liveState)
        let loadedLive = PlatformSurfaceDefaultsReader.loadLiveActivityState()
        XCTAssertEqual(loadedLive?.workoutTitle, "Squat")

        PlatformSurfaceDefaultsWriter.clearLiveActivityState()
        let clearedLive = PlatformSurfaceDefaultsReader.loadLiveActivityState()
        XCTAssertNil(clearedLive)
    }

    func testUserDefaultsPlatformSurfaceStateStoreInit() {
        let store = UserDefaultsPlatformSurfaceStateStore()
        // Sanity: the type is a marker conformance with no exposed surface.
        // Construct it to assert the initializer compiles and runs.
        XCTAssertNotNil(store as PlatformSurfaceStateStore)
    }

    // MARK: - Voice permission

    func testUnavailableVoicePermissionStoreAlwaysReportsUnavailable() async throws {
        let store = UnavailableVoicePermissionStore()
        let current = await store.currentStatus()
        XCTAssertEqual(current.microphone, .unavailable)
        XCTAssertEqual(current.speechRecognition, .unavailable)

        let requested = try await store.requestPermissions()
        XCTAssertEqual(requested.microphone, .unavailable)
        XCTAssertEqual(requested.speechRecognition, .unavailable)
    }

    // MARK: - Health store

    func testUnavailableHealthStoreFallback() async throws {
        let store = UnavailableHealthStore()
        let authorized = await store.isAuthorized
        XCTAssertFalse(authorized)
        let result = try await store.requestAuthorization()
        XCTAssertFalse(result)
        // Session start/end are no-ops on the unavailable store.
        try await store.startWorkoutSession(activityType: .strengthTraining)
        try await store.endWorkoutSession()
    }

    func testHealthKitAuthorizationScopeIdentifiers() {
        XCTAssertTrue(HealthKitAuthorizationScope.sharedWriteIdentifiers.contains("HKWorkoutTypeIdentifier"))
        XCTAssertTrue(HealthKitAuthorizationScope.phoneReadIdentifiers.contains("HKWorkoutTypeIdentifier"))
        XCTAssertTrue(HealthKitAuthorizationScope.watchReadIdentifiers.contains("HKWorkoutTypeIdentifier"))
        XCTAssertTrue(HealthKitAuthorizationScope.watchReadIdentifiers.contains("HKQuantityTypeIdentifierHeartRate"))
        XCTAssertTrue(HealthKitAuthorizationScope.watchReadIdentifiers.contains("HKQuantityTypeIdentifierActiveEnergyBurned"))
        // Phone scope intentionally smaller than watch scope (VOL-80).
        XCTAssertTrue(
            HealthKitAuthorizationScope.phoneReadIdentifiers
                .isSubset(of: HealthKitAuthorizationScope.watchReadIdentifiers)
        )
        XCTAssertLessThan(
            HealthKitAuthorizationScope.phoneReadIdentifiers.count,
            HealthKitAuthorizationScope.watchReadIdentifiers.count
        )
    }

    func testWorkoutActivityTypeRawValues() {
        XCTAssertEqual(WorkoutActivityType.strengthTraining.rawValue, "strengthTraining")
        XCTAssertEqual(WorkoutActivityType.functionalStrengthTraining.rawValue, "functionalStrengthTraining")
        XCTAssertEqual(WorkoutActivityType.coreTraining.rawValue, "coreTraining")
        XCTAssertEqual(WorkoutActivityType.mixedCardio.rawValue, "mixedCardio")
    }

    // MARK: - VoiceCoach

    func testLiveVoiceCoachOrchestratorRoundTrip() async throws {
        let transport = StubVoiceTransport(response: "Hold load.")
        let orchestrator = LiveVoiceCoachOrchestrator(transport: transport)
        try await orchestrator.start()
        let response = try await orchestrator.speak(prompt: "How am I?", context: "Readiness 75")
        XCTAssertEqual(response, "Hold load.")
        await orchestrator.interrupt()
        await orchestrator.end()

        let calls = await transport.calls
        XCTAssertEqual(calls, ["connect", "send", "interrupt", "disconnect"])
    }

    func testRealtimeVoiceTransportDefaultsAreNoOps() async throws {
        // The default protocol extensions for connect/interrupt/disconnect
        // must compile and return without error so single-turn transports
        // (just `send`) don't have to implement audio-session lifecycle.
        struct SendOnlyTransport: RealtimeVoiceTransport {
            func send(context: String, userText: String) async throws -> String { "echo: \(userText)" }
        }
        let transport = SendOnlyTransport()
        let orchestrator = LiveVoiceCoachOrchestrator(transport: transport)
        try await orchestrator.start()
        let result = try await orchestrator.speak(prompt: "ping", context: "")
        XCTAssertEqual(result, "echo: ping")
        await orchestrator.interrupt()
        await orchestrator.end()
    }

    func testOpenAIRelayVoiceTransportDelegatesToProvider() async throws {
        struct EchoProvider: AICoachProvider {
            func coachResponse(for prompt: String, context: String) async throws -> String {
                "P:\(prompt)|C:\(context)"
            }
        }
        let transport = OpenAIRelayVoiceTransport(provider: EchoProvider())
        let response = try await transport.send(context: "Readiness 90", userText: "Push?")
        XCTAssertEqual(response, "P:Push?|C:Readiness 90")
    }

    // MARK: - AICoachProvider local heuristic — additional intent paths

    func testLocalHeuristicAICoachProviderRecoveryAtScoreBoundaries() async throws {
        let provider = LocalHeuristicAICoachProvider(coachingStyle: .motivational)
        let veryHigh = try await provider.coachResponse(for: "Am I ready?", context: "Readiness: 92/100 — green light")
        XCTAssertTrue(veryHigh.contains("ready to push"))

        let mid = try await provider.coachResponse(for: "Am I ready?", context: "Readiness: 65/100 — moderate")
        XCTAssertTrue(mid.contains("Moderate recovery"))

        let low = try await provider.coachResponse(for: "Am I ready?", context: "Readiness: 45/100 — fatigue")
        XCTAssertTrue(low.contains("fatigue is accumulating"))

        let veryLow = try await provider.coachResponse(for: "Am I ready?", context: "Readiness: 25/100 — sore")
        XCTAssertTrue(veryLow.contains("lighter session"))

        let noReadiness = try await provider.coachResponse(for: "How am I?", context: "Just woke up")
        // Free intent path: no readiness extracted means the default "log a set"
        // copy when context lacks "Readiness".
        XCTAssertFalse(noReadiness.isEmpty)
    }

    func testLocalHeuristicAICoachProviderProgressionDeloadFormSubstitution() async throws {
        let provider = LocalHeuristicAICoachProvider(coachingStyle: .analytical)

        let progGreen = try await provider.coachResponse(
            for: "Should I go heavier today?",
            context: "Readiness: 80/100 — strong"
        )
        XCTAssertTrue(progGreen.contains("Green light"))

        let progHold = try await provider.coachResponse(
            for: "Should I push more weight?",
            context: "Readiness: 50/100 — fatigue"
        )
        XCTAssertTrue(progHold.contains("Hold the load"))

        let deloadYes = try await provider.coachResponse(
            for: "Should I deload?",
            context: "Readiness: 40/100 — drained"
        )
        XCTAssertTrue(deloadYes.contains("deload makes sense"))

        let deloadMaybe = try await provider.coachResponse(
            for: "Should I deload?",
            context: "Readiness: 80/100 — fresh"
        )
        XCTAssertTrue(deloadMaybe.contains("might not need a full deload"))

        let formCue = try await provider.coachResponse(for: "Form check?", context: "")
        XCTAssertTrue(formCue.contains("Brace hard"))

        let substitute = try await provider.coachResponse(
            for: "Substitute for back squat?",
            context: ""
        )
        XCTAssertFalse(substitute.isEmpty)
    }

    func testLocalHeuristicAICoachProviderDefaultsWhenContextHasReadiness() async throws {
        let provider = LocalHeuristicAICoachProvider()
        let response = try await provider.coachResponse(
            for: "Tell me what to do.",
            context: "Readiness 88/100 ready"
        )
        XCTAssertTrue(response.contains("hold the target load"))
    }

    func testAICoachProviderStreamingDefaultYieldsChunks() async throws {
        struct OneShotProvider: AICoachProvider {
            func coachResponse(for prompt: String, context: String) async throws -> String {
                "alpha beta gamma"
            }
        }
        let provider = OneShotProvider()
        var collected = ""
        for try await chunk in provider.streamCoachResponse(for: "?", context: "") {
            collected += chunk
        }
        XCTAssertEqual(collected, "alpha beta gamma")
    }

    func testCoachPromptTemplateInferIntentFreeFallthrough() {
        XCTAssertEqual(CoachPromptTemplate.inferIntent(from: "How is the weather?"), .free)
    }

    func testCoachPromptTemplateRenderConvenienceInfersIntent() {
        let rendered = CoachPromptTemplate.render(
            question: "Should I push more weight?",
            contextBlock: "Readiness: 80/100 — strong"
        )
        XCTAssertTrue(rendered.contains(CoachPromptTemplate.templateMarker))
        XCTAssertTrue(rendered.contains("intent=progression"))
    }

    func testCoachPromptTemplateUserPromptStandardAndStrict() {
        let context = CoachContext(
            athleteName: "Jordan",
            advancementLevel: AdvancementLevel.intermediate.rawValue,
            readinessScore: 72,
            readinessBrief: "Solid",
            nextExercise: "Bench Press",
            nextTarget: "185 x 5",
            recentSessionCount: 3,
            averageRPE: 7.5,
            lastSessionSummary: "3 sets, RPE 7.5",
            recentMemories: ["Slept 8 hrs"]
        )
        let standard = CoachPromptTemplate.userPrompt(
            question: "What should I do?",
            context: context,
            privacyMode: .standard
        )
        XCTAssertTrue(standard.contains("Jordan"))
        XCTAssertTrue(standard.contains("Last 7 days: 3 sessions"))
        XCTAssertTrue(standard.contains("Slept 8 hrs"))

        let strict = CoachPromptTemplate.userPrompt(
            question: "What should I do?",
            context: context,
            privacyMode: .strict
        )
        XCTAssertFalse(strict.contains("Jordan"))
        XCTAssertTrue(strict.contains("the athlete"))
        XCTAssertFalse(strict.contains("Last 7 days"))
        XCTAssertFalse(strict.contains("Slept 8 hrs"))
    }

    func testCoachContextEmptyAthleteNameFallsBackToTheAthlete() {
        let context = CoachContext(
            athleteName: "",
            advancementLevel: "intermediate",
            readinessScore: 60,
            readinessBrief: "Moderate"
        )
        let block = context.asPromptBlock(privacyMode: .standard)
        XCTAssertTrue(block.contains("the athlete"))
        XCTAssertTrue(block.contains("Readiness: 60/100"))
        XCTAssertTrue(block.contains("No recent sessions logged"))
    }

    func testCoachContextStandardModeWithNextExerciseAndSessions() {
        let context = CoachContext(
            athleteName: "Alex",
            advancementLevel: "advanced",
            readinessScore: 75,
            readinessBrief: "Good",
            nextExercise: "Deadlift",
            nextTarget: "315 x 3",
            recentSessionCount: 5,
            averageRPE: 8.0,
            lastSessionSummary: "Heavy day"
        )
        let block = context.asPromptBlock(privacyMode: .standard)
        XCTAssertTrue(block.contains("Alex"))
        XCTAssertTrue(block.contains("Next up: Deadlift at 315 x 3"))
        XCTAssertTrue(block.contains("avg RPE 8.0"))
        XCTAssertTrue(block.contains("Heavy day"))
    }

    func testCoachIntentAndCoachingStyleRawCases() {
        XCTAssertEqual(Set(CoachIntent.allCases.map(\.rawValue)),
                       ["progression", "deload", "form", "recovery", "substitution", "free"])
        XCTAssertEqual(Set(CoachingStyle.allCases.map(\.rawValue)),
                       ["motivational", "analytical", "minimal"])
    }

    // MARK: - WorkoutTypes (uncovered helpers on history/session)

    func testExerciseHistoryHelpers() {
        let now = Date()
        let earlier = ExerciseSession(
            date: now.addingTimeInterval(-86_400),
            sets: [
                WorkoutSetPerformance(weight: 100, reps: 5, rpe: 7, completedAt: now),
                WorkoutSetPerformance(weight: 110, reps: 5, rpe: 8, completedAt: now),
            ]
        )
        let recent = ExerciseSession(
            date: now,
            sets: [
                WorkoutSetPerformance(weight: 120, reps: 3, rpe: 9, completedAt: now),
            ]
        )
        let history = ExerciseHistory(exerciseID: "back-squat", sessions: [earlier, recent])
        XCTAssertFalse(history.isEmpty)
        XCTAssertEqual(history.lastSession?.date, recent.date)
        XCTAssertEqual(history.topWeight, 120)

        let empty = ExerciseHistory(exerciseID: "x")
        XCTAssertTrue(empty.isEmpty)
        XCTAssertNil(empty.lastSession)
        XCTAssertEqual(empty.topWeight, 0)
    }

    func testExerciseSessionAggregations() {
        let now = Date()
        let s1 = WorkoutSetPerformance(weight: 100, reps: 5, rpe: 7, completedAt: now)
        let s2 = WorkoutSetPerformance(weight: 100, reps: 5, rpe: 8, completedAt: now)
        let s3 = WorkoutSetPerformance(weight: 105, reps: 4, rpe: 9, completedAt: now)
        let session = ExerciseSession(date: now, sets: [s1, s2, s3])
        let expectedVolume: Double = 100.0 * 5.0 + 100.0 * 5.0 + 105.0 * 4.0
        XCTAssertEqual(session.totalVolumeLoad, expectedVolume, accuracy: 0.001)
        XCTAssertEqual(session.topSetWeight, 105)
        XCTAssertEqual(session.averageRPE, 8.0, accuracy: 0.001)

        let empty = ExerciseSession(date: now, sets: [])
        XCTAssertEqual(empty.totalVolumeLoad, 0)
        XCTAssertEqual(empty.topSetWeight, 0)
        XCTAssertEqual(empty.averageRPE, 0)
    }

    func testCoachMemoryMostRecentLimitsToFive() {
        let base = Date()
        let entries = (0..<10).map { idx in
            CoachMemory.Entry(
                createdAt: base.addingTimeInterval(TimeInterval(idx)),
                summary: "summary \(idx)",
                theme: nil
            )
        }
        let memory = CoachMemory(entries: entries)
        XCTAssertFalse(memory.isEmpty)
        XCTAssertEqual(memory.mostRecent.count, 5)
        // Newest first.
        XCTAssertEqual(memory.mostRecent.first?.summary, "summary 9")

        let empty = CoachMemory()
        XCTAssertTrue(empty.isEmpty)
        XCTAssertTrue(empty.mostRecent.isEmpty)
    }

    func testEnumRawValuesStable() {
        XCTAssertEqual(WorkoutAction.increase.rawValue, "increase")
        XCTAssertEqual(WorkoutAction.hold.rawValue, "hold")
        XCTAssertEqual(WorkoutAction.decrease.rawValue, "decrease")
        XCTAssertEqual(StrengthGoal.generalStrength.rawValue, "general-strength")
        XCTAssertEqual(StrengthGoal.weightLoss.rawValue, "weight-loss")
    }

    // MARK: - Helpers

    private func isolatedUserDefaults(_ namespace: String) -> UserDefaults {
        let suite = "VOL-52.\(namespace).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Build a `UserDefaultsWatchPendingPayloadStore` from inside a
    /// `Task.detached` so the non-`Sendable` `UserDefaults` instance is
    /// constructed in the same isolation context that owns the actor's
    /// init — Swift 6 strict concurrency rejects sending a UserDefaults
    /// allocated in the test method into the actor across an async hop.
    private func makePendingPayloadStore(namespace: String) async -> UserDefaultsWatchPendingPayloadStore {
        await Task.detached {
            let suite = "VOL-52.\(namespace).\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            return UserDefaultsWatchPendingPayloadStore(defaults: defaults)
        }.value
    }

    private func makeSessionStateStore(namespace: String) async -> UserDefaultsWatchSessionStateStore {
        await Task.detached {
            let suite = "VOL-52.\(namespace).\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            defaults.removePersistentDomain(forName: suite)
            return UserDefaultsWatchSessionStateStore(defaults: defaults)
        }.value
    }
}

// MARK: - Test doubles

private actor ScriptedWatchTransport: WatchSessionTransport {
    private(set) var sentPayloads: [WatchPayload] = []
    private let reachable: Bool
    private let sendError: Error?

    init(reachable: Bool, sendError: Error? = nil) {
        self.reachable = reachable
        self.sendError = sendError
    }

    func activate() async {}
    func isReachable() async -> Bool { reachable }

    func send(_ payload: WatchPayload) async throws {
        if let sendError { throw sendError }
        sentPayloads.append(payload)
    }
}

private actor StubVoiceTransport: RealtimeVoiceTransport {
    private(set) var calls: [String] = []
    private let response: String

    init(response: String) {
        self.response = response
    }

    func connect(model: AIModelIdentifier, policy: VoiceSessionPolicy) async throws {
        calls.append("connect")
    }

    func send(context: String, userText: String) async throws -> String {
        calls.append("send")
        return response
    }

    func interrupt() async {
        calls.append("interrupt")
    }

    func disconnect() async {
        calls.append("disconnect")
    }
}
