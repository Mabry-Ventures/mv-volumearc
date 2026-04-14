# Testing

## Test architecture

```
Tests/VolumeArcAppTests/
├── TestSupport/            # Mocks, fixtures, helpers
│   ├── Mocks.swift         # MockAICoachProvider, MockCloudSyncTransport, etc.
│   └── Fixtures.swift      # TestFixtures for LiveActivityState, WatchPayload, etc.
├── VolumeArcAppConfigurationTests.swift    # Config constants, intent smoke tests
├── VolumeArcPersistenceTests.swift         # Bootstrap status, telemetry events
├── VolumeArcRelaySessionTests.swift        # Token expiration, error handling
└── VolumeArcMigrationTests.swift           # SwiftData schema migration
```

## Running tests

```bash
./scripts/test_apple_targets.sh
```

Or via Xcode: ⌘U with `VolumeArcAppTests` scheme selected.

## Writing unit tests

Unit tests should:

- Test **real** production code, not surrogate copies
- Use mocks from `TestSupport/Mocks.swift` for protocol boundaries
- Use fixture builders from `TestSupport/Fixtures.swift` for test data
- Name test methods `test<Behavior>` (e.g., `testPersistenceFallbackChain`)
- Use `XCTAssert` helpers, not raw `assert`
- Be deterministic — no random values, no real network calls, no real filesystem (use temp dirs)

## Writing XCUITests (VOL-42)

UI tests live in a separate target `VolumeArcUITests` (planned). They should:

- Test critical user journeys end-to-end
- Use `XCUIApplication` with launch arguments to seed test state
- Take screenshots on failure for debugging
- Complete in under 3 minutes total

## Coverage expectations

| Layer | Coverage target |
|-------|-----------------|
| `VolumeArcCore` business logic | 80%+ |
| `VolumeArcCore` data models | 60%+ |
| Host app wiring | 40%+ (exercised by UI tests) |
| UI views | 30%+ (via XCUITests) |

Measure with `xcodebuild -enableCodeCoverage YES`.

## Flaky test policy

Flaky tests are worse than no tests — they erode trust in the suite. If a test flakes:

1. Immediately mark it as `XCTSkip` with a TODO and ticket reference
2. Open a P1 ticket to fix or delete it
3. Do not merge code that leaves flaky tests behind

## Test naming

```swift
func testPersistenceFallsBackToInMemoryWhenLocalFails() { ... }
func testRelaySessionExpiresTokensWithin60SecondsOfDeadline() { ... }
func testProgressionEngineAddsWeightWhenUpperRepBoundHit() { ... }
```

Be specific. A test name should describe both the condition and the expected behavior.
