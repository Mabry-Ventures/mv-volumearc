import XCTest
import VolumeArcCore

/// VOL-100. Prompt-quality regression guard for the AI coach.
///
/// Loads every fixture under `Tests/Evals/CoachEvalFixtures/*.json`, feeds
/// each through `CoachPromptTemplate.render(...)`, and asserts template-layer
/// invariants that any regression in the prompt-assembly pipeline will break:
///
/// - Template marker present (provider bypass check).
/// - Intent envelope matches the fixture intent.
/// - System prompt is present and its persona line matches the declared style.
/// - Context block is preserved verbatim inside the rendered prompt.
/// - The athlete's question is embedded verbatim.
///
/// These tests are deliberately hermetic — no network, no model call. The
/// response-quality assertions live in `scripts/run_coach_evals.sh`, which
/// hits the real relay and is run nightly / on-demand so XCTest stays fast
/// and deterministic.
///
/// Fixtures are resolved two ways: first as a bundle resource (the Xcode
/// project generator wires `Tests/Evals/CoachEvalFixtures/` in as a tests-
/// target resource group); if that fails (Swift Package Manager test runs,
/// stripped binaries), the loader falls back to `#filePath`-anchored lookup
/// so the tests keep working regardless of how they're invoked.
final class CoachEvalTests: XCTestCase {

    // MARK: - Top-level sweep

    /// Single sweep that verifies every fixture on disk renders cleanly
    /// through the template and carries the expected structural invariants.
    /// Each fixture's failure messages are prefixed with `[id]` so a
    /// failure points at the offending fixture without needing the
    /// `XCTContext.runActivity` wrapper (which is main-actor-isolated and
    /// doesn't compose with Swift 6 strict concurrency inside a sync test).
    func testAllFixturesRenderWithLoadBearingInvariants() throws {
        let fixtures = try CoachEvalFixture.loadAll()
        XCTAssertGreaterThanOrEqual(
            fixtures.count,
            20,
            "Expected at least 20 coach eval fixtures on disk — found \(fixtures.count). Has the fixture bundle been wired into the tests target?"
        )

        // IDs must be unique — the shell script and docs key off them.
        let ids = fixtures.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "Fixture IDs must be unique: \(ids)")

        for fixture in fixtures {
            assertTemplateLayerInvariants(for: fixture)
        }
    }

    /// Axis-coverage guard: ensures the suite keeps covering each
    /// readiness / intent / history / style bucket. If a future edit trims
    /// fixtures below the coverage minimum, this test fails loudly so the
    /// harness isn't quietly whittled down to a few happy paths.
    func testFixtureMatrixCoversEveryAxis() throws {
        let fixtures = try CoachEvalFixture.loadAll()

        let intents = Set(fixtures.map(\.intent))
        XCTAssertEqual(
            intents,
            Set(CoachIntent.allCases.map(\.rawValue)),
            "Every CoachIntent must appear in the fixture matrix at least once; missing: \(Set(CoachIntent.allCases.map(\.rawValue)).subtracting(intents))"
        )

        let styles = Set(fixtures.map(\.style))
        XCTAssertEqual(
            styles,
            Set(CoachingStyle.allCases.map(\.rawValue)),
            "Every CoachingStyle must appear in the fixture matrix at least once; missing: \(Set(CoachingStyle.allCases.map(\.rawValue)).subtracting(styles))"
        )

        // Readiness buckets the product surfaces in the UI — keep the
        // matrix anchored to the same cut points so evals match what users
        // actually see.
        let readinessScores = Set(fixtures.compactMap(\.readinessScore))
        for expected in [45, 60, 72, 82, 88] {
            XCTAssertTrue(
                readinessScores.contains(expected),
                "Readiness bucket \(expected) missing from fixtures — add a fixture covering this score"
            )
        }

        // Session-history tiers: the product differentiates between cold
        // start (0), single session (1), and established history (5+). Keep
        // at least one fixture per tier.
        let sessionCounts = fixtures.compactMap(\.recentSessionCount)
        XCTAssertTrue(sessionCounts.contains(0), "At least one fixture must cover empty session history (cold start)")
        XCTAssertTrue(sessionCounts.contains(1), "At least one fixture must cover a single recent session")
        XCTAssertTrue(sessionCounts.contains(where: { $0 >= 5 }), "At least one fixture must cover established history (>= 5 sessions)")
    }

    /// Stability guard: fixture IDs are the tracking key across the docs
    /// table, the shell script output, and the XCTest logs. A rename that
    /// drops the kebab-case convention or sneaks in a space breaks all
    /// three at once.
    func testFixtureIDsAreStableAndHashable() throws {
        let fixtures = try CoachEvalFixture.loadAll()
        for fixture in fixtures {
            XCTAssertFalse(fixture.id.isEmpty, "Fixture ID cannot be empty")
            XCTAssertFalse(fixture.id.contains(" "), "Fixture ID must be kebab-case (no spaces): \(fixture.id)")
            XCTAssertEqual(
                fixture.id.lowercased(),
                fixture.id,
                "Fixture ID must be lowercase kebab-case: \(fixture.id)"
            )
        }
    }

    // MARK: - Per-fixture invariant check

    private func assertTemplateLayerInvariants(for fixture: CoachEvalFixture) {
        guard let intent = CoachIntent(rawValue: fixture.intent) else {
            XCTFail("Fixture \(fixture.id): unknown intent '\(fixture.intent)'")
            return
        }
        guard let style = CoachingStyle(rawValue: fixture.style) else {
            XCTFail("Fixture \(fixture.id): unknown style '\(fixture.style)'")
            return
        }

        let rendered = CoachPromptTemplate.render(
            intent: intent,
            contextBlock: fixture.contextBlock,
            question: fixture.question,
            style: style
        )

        // 1. Template marker — catches any regression that concatenates
        //    context + question by hand and bypasses the template.
        XCTAssertTrue(
            rendered.contains(CoachPromptTemplate.templateMarker),
            "[\(fixture.id)] rendered prompt missing template marker '\(CoachPromptTemplate.templateMarker)' — template bypass regression"
        )

        // 2. Intent envelope — the rendered prompt must declare the intent
        //    in the header line so downstream (relay logs, on-device dispatch)
        //    can route on it.
        XCTAssertTrue(
            rendered.contains("intent=\(fixture.intent)"),
            "[\(fixture.id)] rendered prompt missing 'intent=\(fixture.intent)' envelope"
        )
        XCTAssertTrue(
            rendered.contains("style=\(fixture.style)"),
            "[\(fixture.id)] rendered prompt missing 'style=\(fixture.style)' in header"
        )

        // 3. System prompt is present and matches the style's persona
        //    tone. The persona is the one line that's style-dependent in
        //    the system prompt, so we assert on its shape.
        XCTAssertTrue(
            rendered.contains("VolumeArc's strength coach"),
            "[\(fixture.id)] rendered prompt missing system prompt preamble"
        )
        let personaExpectation = Self.personaExpectation(for: style)
        XCTAssertTrue(
            rendered.contains(personaExpectation),
            "[\(fixture.id)] rendered prompt must carry the \(fixture.style)-style persona; expected fragment '\(personaExpectation)' not found"
        )

        // 4. Context block is preserved verbatim. Model responses may
        //    vary, but the INPUT the model sees is deterministic.
        let trimmedContext = fixture.contextBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(
            rendered.contains(trimmedContext),
            "[\(fixture.id)] rendered prompt must embed the fixture contextBlock verbatim"
        )

        // 5. Athlete question embedded verbatim.
        XCTAssertTrue(
            rendered.contains(fixture.question.trimmingCharacters(in: .whitespacesAndNewlines)),
            "[\(fixture.id)] rendered prompt must embed the athlete question verbatim"
        )

        // 6. Per-intent envelope must match the declared intent. This is
        //    the shape assertion that distinguishes a progression prompt
        //    from a deload prompt from a form prompt.
        let envelopeFragment = Self.intentEnvelopeFragment(for: intent)
        XCTAssertTrue(
            rendered.contains(envelopeFragment),
            "[\(fixture.id)] rendered prompt must include the \(fixture.intent)-intent envelope; expected fragment '\(envelopeFragment)' not found"
        )

        // 7. Determinism — rendering twice with the same inputs produces
        //    byte-identical output. The shell script relies on this when
        //    comparing logged prompts across runs.
        let second = CoachPromptTemplate.render(
            intent: intent,
            contextBlock: fixture.contextBlock,
            question: fixture.question,
            style: style
        )
        XCTAssertEqual(rendered, second, "[\(fixture.id)] renderer must be deterministic for identical inputs")
    }

    // MARK: - Expectation tables

    /// A small, stable fragment that appears in the persona line for each
    /// coaching style. These are the load-bearing words — if the
    /// `personaForStyle` copy is overhauled, the test flags it so the eval
    /// suite doesn't silently drift.
    private static func personaExpectation(for style: CoachingStyle) -> String {
        switch style {
        case .motivational: return "High-energy"
        case .analytical: return "Data-driven"
        case .minimal: return "Short and direct"
        }
    }

    /// A keyword from each intent's envelope. Paired with the fragments
    /// baked into `CoachPromptTemplate.intentEnvelope(_:)` — if either side
    /// moves, the assertion fails and the author notices.
    private static func intentEnvelopeFragment(for intent: CoachIntent) -> String {
        switch intent {
        case .progression: return "pushing load or volume"
        case .deload: return "considering a deload"
        case .form: return "asking about technique"
        case .recovery: return "asking about readiness or recovery"
        case .substitution: return "wants an exercise substitution"
        case .planning: return "asking for a training plan or schedule"
        case .free: return "Open question"
        }
    }
}

// MARK: - Fixture model & loader

/// On-disk representation of a single coach eval fixture. Mirrors the JSON
/// shape under `Tests/Evals/CoachEvalFixtures/*.json`. Fields marked
/// optional are derived for the axis-coverage check and aren't load-bearing
/// for template-layer assertions.
struct CoachEvalFixture: Decodable, Sendable {
    let id: String
    let intent: String
    let question: String
    let contextBlock: String
    let style: String
    let expectedAssertions: ExpectedAssertions
    let notes: String?

    struct ExpectedAssertions: Decodable, Sendable {
        let maxSentences: Int?
        let mustContainNumericContext: Bool?
        let mustMentionReadinessOrRPE: Bool?
        let mustNotMention: [String]?
        let maxEnumeratedPlanDays: Int?
        let toneHint: String?
        let mustAnchorOnNextExercise: Bool?
        let mustFlagPainSignal: Bool?
    }

    /// Derived: readiness score parsed out of the contextBlock for the
    /// axis-coverage assertion. Returns nil if the block doesn't carry a
    /// "Readiness: NN/100" line.
    var readinessScore: Int? {
        guard let range = contextBlock.range(of: "Readiness: ") else { return nil }
        let remainder = contextBlock[range.upperBound...]
        guard let slashRange = remainder.range(of: "/") else { return nil }
        return Int(String(remainder[remainder.startIndex..<slashRange.lowerBound]))
    }

    /// Derived: recent session count from the contextBlock. 0 when the
    /// block says "No recent sessions logged".
    var recentSessionCount: Int? {
        if contextBlock.contains("No recent sessions logged") { return 0 }
        guard let range = contextBlock.range(of: "Last 7 days: ") else { return nil }
        let remainder = contextBlock[range.upperBound...]
        guard let spaceRange = remainder.range(of: " ") else { return nil }
        return Int(String(remainder[remainder.startIndex..<spaceRange.lowerBound]))
    }

    /// Locate the fixture directory on disk. Tries the tests-bundle first
    /// (the Xcode-generated project wires fixtures in as resources), then
    /// falls back to `#filePath` resolution so Swift Package Manager / plain
    /// xcodebuild invocations still work.
    static func fixtureDirectory(file: StaticString = #filePath) -> URL? {
        // 1. Bundle resource lookup — the Xcode project generator copies
        //    fixtures under `CoachEvalFixtures/` inside the tests bundle.
        let bundle = Bundle(for: CoachEvalTests.self)
        if let bundleURL = bundle.url(forResource: "CoachEvalFixtures", withExtension: nil) {
            return bundleURL
        }
        if let resources = bundle.resourceURL?.appendingPathComponent("CoachEvalFixtures"),
           FileManager.default.fileExists(atPath: resources.path) {
            return resources
        }

        // 2. Source-relative fallback — walk up from this file to the repo
        //    root (three levels: Evals → VolumeArcAppTests → Tests → repo).
        let fileURL = URL(fileURLWithPath: String(describing: file))
        let repoRoot = fileURL
            .deletingLastPathComponent() // Evals/
            .deletingLastPathComponent() // VolumeArcAppTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let candidate = repoRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("Evals")
            .appendingPathComponent("CoachEvalFixtures")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    static func loadAll(file: StaticString = #filePath) throws -> [CoachEvalFixture] {
        guard let directory = fixtureDirectory(file: file) else {
            throw NSError(
                domain: "CoachEvalTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Coach eval fixture directory not found — neither bundle resource nor source-relative path resolved"]
            )
        }
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let jsonFiles = contents.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        return try jsonFiles.map { url in
            let data = try Data(contentsOf: url)
            do {
                return try decoder.decode(CoachEvalFixture.self, from: data)
            } catch {
                throw NSError(
                    domain: "CoachEvalTests",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Failed to decode fixture at \(url.lastPathComponent): \(error)"
                    ]
                )
            }
        }
    }
}
