import Foundation
import XCTest

/// VOL-169: XCUITest-hosted bridge for the nightly exploratory UAT agent.
///
/// The normal PR/UI shards compile this class but skip it unless
/// `UAT_AGENT_ENABLED=1` is present. Nightly CI opts in, passes
/// story prompts, and lets the model choose bounded UI actions from
/// screenshots plus the accessibility tree. The transcript is written
/// both to an optional output path and to the xcodebuild log markers so
/// the workflow can publish an artifact even if the xcresult parser is
/// unavailable.
@MainActor
final class VolumeArcExploratoryUATAgentTests: XCTestCase {
    private let environment = ProcessInfo.processInfo.environment
    private var report = UATAgentReport(
        generatedAt: ISO8601DateFormatter().string(from: Date()),
        model: "",
        stories: [],
        summary: .empty
    )

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        let app = XCUIApplication()
        VolumeArcAppUITestSupport.defensiveTerminate(app)
    }

    func testNightlyExploratoryStories() async throws {
        guard environment["UAT_AGENT_ENABLED"] == "1" else {
            throw XCTSkip("VOL-169 exploratory UAT agent is nightly-only.")
        }
        guard let apiKey = environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
            throw XCTSkip("OPENAI_API_KEY is required for the VOL-169 nightly UAT agent.")
        }

        let model = environment["UAT_AGENT_MODEL"].flatMap { $0.isEmpty ? nil : $0 } ?? "gpt-5.5"
        let maxSteps = Int(environment["UAT_AGENT_MAX_STEPS"] ?? "") ?? 5
        let client = OpenAIUATDecisionClient(apiKey: apiKey, model: model)
        let stories = try UATStory.load(from: environment)

        report.model = model
        for story in stories {
            let storyReport = await run(
                story: story,
                client: client,
                maxSteps: maxSteps
            )
            report.stories.append(storyReport)
        }
        report.summary = UATAgentSummary(stories: report.stories)
        emit(report: report)
    }

    private func run(
        story: UATStory,
        client: OpenAIUATDecisionClient,
        maxSteps: Int
    ) async -> UATStoryReport {
        let app = VolumeArcAppUITestSupport.makeSeededApp(extra: story.launchArguments)
        app.launch()

        var steps: [UATStepReport] = []
        guard app.wait(for: .runningForeground, timeout: 25) else {
            return UATStoryReport(
                id: story.id,
                prompt: story.prompt,
                launchArguments: story.launchArguments,
                steps: [
                    UATStepReport(
                        index: 0,
                        action: "launch",
                        target: nil,
                        rationale: "App did not reach foreground.",
                        anomaly: .high("App failed to launch into foreground within 25s."),
                        execution: "failed",
                        screenshotAttachment: nil
                    ),
                ],
                completed: false
            )
        }

        for index in 1...maxSteps {
            let screenshot = XCUIScreen.main.screenshot()
            let attachmentName = "\(story.id).step-\(index).png"
            attach(screenshot: screenshot, named: attachmentName)

            let screenTree = app.debugDescription
            do {
                let decision = try await client.nextDecision(
                    story: story,
                    stepIndex: index,
                    priorSteps: steps,
                    accessibilityTree: screenTree,
                    screenshotPNG: screenshot.pngRepresentation
                )
                let execution = execute(decision: decision, in: app)
                steps.append(
                    UATStepReport(
                        index: index,
                        action: decision.action,
                        target: decision.target?.description,
                        rationale: decision.rationale ?? "",
                        anomaly: decision.anomaly ?? .none,
                        execution: execution,
                        screenshotAttachment: attachmentName
                    )
                )

                if decision.action == "finish" || decision.done == true {
                    break
                }
            } catch {
                steps.append(
                    UATStepReport(
                        index: index,
                        action: "model_error",
                        target: nil,
                        rationale: error.localizedDescription,
                        anomaly: .high("Agent decision failed: \(error.localizedDescription)"),
                        execution: "failed",
                        screenshotAttachment: attachmentName
                    )
                )
                break
            }
        }

        app.terminate()
        return UATStoryReport(
            id: story.id,
            prompt: story.prompt,
            launchArguments: story.launchArguments,
            steps: steps,
            completed: steps.last?.action == "finish" || steps.count >= maxSteps
        )
    }

    private func execute(decision: UATAgentDecision, in app: XCUIApplication) -> String {
        switch decision.action {
        case "tap":
            return executeTap(target: decision.target, in: app)

        case "typeText":
            return executeTypeText(decision: decision, in: app)

        case "swipe":
            return executeSwipe(direction: decision.direction, in: app)

        case "wait":
            Thread.sleep(forTimeInterval: max(1, min(decision.seconds ?? 1, 5)))
            return "waited"

        case "finish":
            return "finished"

        default:
            return "unsupported_action_\(decision.action)"
        }
    }

    private func executeTap(target: UATAgentTarget?, in app: XCUIApplication) -> String {
        guard let element = resolveElement(target, in: app) else {
            return "target_missing"
        }
        if !element.isHittable {
            app.swipeUp()
        }
        guard element.waitForExistence(timeout: 3), element.isHittable else {
            return "target_not_hittable"
        }
        element.tap()
        return "tapped"
    }

    private func executeTypeText(decision: UATAgentDecision, in app: XCUIApplication) -> String {
        guard let element = textElement(for: decision.target, in: app) else {
            return "text_target_missing"
        }
        guard element.waitForExistence(timeout: 3) else {
            return "text_target_missing"
        }
        element.tap()
        element.typeText(decision.text ?? "")
        return "typed"
    }

    private func textElement(
        for target: UATAgentTarget?,
        in app: XCUIApplication
    ) -> XCUIElement? {
        if let element = resolveElement(target, in: app), element.exists {
            return element
        }
        if app.textFields.firstMatch.exists {
            return app.textFields.firstMatch
        }
        if app.textViews.firstMatch.exists {
            return app.textViews.firstMatch
        }
        return nil
    }

    private func executeSwipe(direction: String?, in app: XCUIApplication) -> String {
        switch direction {
        case "down":
            app.swipeDown()
        case "left":
            app.swipeLeft()
        case "right":
            app.swipeRight()
        default:
            app.swipeUp()
        }
        return "swiped_\(direction ?? "up")"
    }

    private func resolveElement(
        _ target: UATAgentTarget?,
        in app: XCUIApplication
    ) -> XCUIElement? {
        guard let target else { return nil }

        if let identifier = target.identifier, !identifier.isEmpty {
            let element = app.descendants(matching: .any)
                .matching(identifier: identifier)
                .firstMatch
            if element.exists { return element }
        }

        if let label = target.label, !label.isEmpty {
            let exact = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label))
                .firstMatch
            if exact.exists { return exact }

            let contains = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS[c] %@", label))
                .firstMatch
            if contains.exists { return contains }
        }

        return nil
    }

    private func attach(screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func emit(report: UATAgentReport) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report),
              let json = String(data: data, encoding: .utf8) else {
            XCTFail("Failed to encode VOL-169 UAT agent report.")
            return
        }

        if let outputPath = environment["UAT_AGENT_OUTPUT_PATH"], !outputPath.isEmpty {
            try? data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }

        print("UAT_AGENT_REPORT_JSON_BEGIN")
        print(json)
        print("UAT_AGENT_REPORT_JSON_END")

        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "uat-agent-report.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private struct UATStory: Codable {
    let id: String
    let prompt: String
    let launchArguments: [String]

    static func load(from environment: [String: String]) throws -> [UATStory] {
        if let raw = environment["UAT_AGENT_STORY"], !raw.isEmpty {
            return [
                UATStory(id: "manual-story", prompt: raw, launchArguments: []),
            ]
        }

        if let json = environment["UAT_AGENT_STORIES_JSON"], !json.isEmpty {
            let data = Data(json.utf8)
            return try JSONDecoder().decode([UATStory].self, from: data)
        }

        return defaultStories
    }

    private static let defaultStories: [UATStory] = [
        UATStory(
            id: "profile-privacy-diagnostics",
            prompt: "Explore Profile privacy and diagnostics. Look for a privacy mismatch, "
                + "a broken row, or feedback/support state that would confuse a launch user.",
            launchArguments: ["-OpenProfileOnLaunch", "1"]
        ),
        UATStory(
            id: "today-recovery-contradiction",
            prompt: "Start on Today and inspect readiness, recovery, next workout, and recent "
                + "sessions. Report contradictory or stale training guidance.",
            launchArguments: []
        ),
        UATStory(
            id: "coach-recovery-question",
            prompt: "Ask Coach for advice after a hard session and decide whether the response "
                + "uses readiness and recovery context well enough for a tired lifter.",
            launchArguments: ["-OpenCoachOnLaunch", "1"]
        ),
        UATStory(
            id: "workouts-history-breakage",
            prompt: "Explore Workouts history and detail surfaces. Try to find a dead end, "
                + "unresponsive scroll, or session detail that loses context.",
            launchArguments: ["-OpenWorkoutsOnLaunch", "1"]
        ),
        UATStory(
            id: "signals-comparison-confusion",
            prompt: "Use Signals to compare readiness, volume, and frequency. Look for labels "
                + "or empty states that make the trend hard to interpret.",
            launchArguments: ["-OpenSignalsOnLaunch", "1"]
        ),
    ]
}

private struct OpenAIUATDecisionClient: Sendable {
    private let apiKey: String
    private let model: String
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!

    init(apiKey: String, model: String) {
        self.apiKey = apiKey
        self.model = model
    }

    func nextDecision(
        story: UATStory,
        stepIndex: Int,
        priorSteps: [UATStepReport],
        accessibilityTree: String,
        screenshotPNG: Data
    ) async throws -> UATAgentDecision {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: payload(
                story: story,
                stepIndex: stepIndex,
                priorSteps: priorSteps,
                accessibilityTree: accessibilityTree,
                screenshotPNG: screenshotPNG
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UATAgentError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw UATAgentError.apiFailure(http.statusCode, body)
        }

        let output = try JSONDecoder().decode(ResponsesAPIResponse.self, from: data)
        let text = output.combinedText
        guard let jsonData = text.firstJSONObjectData() else {
            throw UATAgentError.invalidJSON(text)
        }
        return try JSONDecoder().decode(UATAgentDecision.self, from: jsonData)
    }

    private func payload(
        story: UATStory,
        stepIndex: Int,
        priorSteps: [UATStepReport],
        accessibilityTree: String,
        screenshotPNG: Data
    ) -> [String: Any] {
        let priorSummary = priorSteps
            .map { "\($0.index). \($0.action): \($0.execution) - \($0.rationale)" }
            .joined(separator: "\n")
        let tree = String(accessibilityTree.prefix(30_000))
        let state = """
        Story id: \(story.id)
        Story goal: \(story.prompt)
        Step: \(stepIndex)
        Prior steps:
        \(priorSummary.isEmpty ? "None yet." : priorSummary)

        Accessibility tree:
        \(tree)
        """

        return [
            "model": model,
            "store": false,
            "reasoning": ["effort": "low"],
            "text": ["verbosity": "low"],
            "instructions": Self.instructions,
            "input": [
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": state],
                        [
                            "type": "input_image",
                            "image_url": "data:image/png;base64,\(screenshotPNG.base64EncodedString())",
                            "detail": "low",
                        ],
                    ],
                ],
            ],
        ]
    }

    private static let instructions = """
    You are VolumeArc's exploratory UAT agent. Use the screenshot and
    accessibility tree to choose one safe, bounded iOS UI action.

    Return only one JSON object with these keys:
    action: one of "tap", "typeText", "swipe", "wait", "finish".
    target: optional object with identifier and/or label.
    text: optional string for typeText.
    direction: optional "up", "down", "left", or "right" for swipe.
    seconds: optional number from 1 to 5 for wait.
    rationale: short reason for the action or finding.
    anomaly: object with severity ("none", "low", "medium", "high")
      and summary.
    done: true only when the story has enough evidence to stop.

    Prefer accessibility identifiers over labels. Do not use destructive
    actions, purchases, deletion, sign-out, external links, or system
    permission prompts. Finish when you have a meaningful anomaly report
    or when more actions are unlikely to add signal.
    """
}

private struct ResponsesAPIResponse: Decodable {
    struct OutputItem: Decodable {
        struct Content: Decodable {
            let text: String?
        }

        let content: [Content]?
    }

    let outputText: String?
    let output: [OutputItem]?

    enum CodingKeys: String, CodingKey {
        case outputText = "output_text"
        case output
    }

    var combinedText: String {
        if let outputText, !outputText.isEmpty { return outputText }
        return output?
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n") ?? ""
    }
}

private struct UATAgentDecision: Decodable {
    let action: String
    let target: UATAgentTarget?
    let text: String?
    let direction: String?
    let seconds: TimeInterval?
    let rationale: String?
    let anomaly: UATAgentAnomaly?
    let done: Bool?
}

private struct UATAgentTarget: Codable {
    let identifier: String?
    let label: String?

    var description: String {
        [
            identifier.map { "identifier=\($0)" },
            label.map { "label=\($0)" },
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }
}

private struct UATAgentAnomaly: Codable {
    let severity: String
    let summary: String

    init(severity: String, summary: String) {
        self.severity = severity
        self.summary = summary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        severity = try container.decodeIfPresent(String.self, forKey: .severity) ?? "none"
        summary = try container.decodeIfPresent(String.self, forKey: .summary) ?? ""
    }

    static let none = UATAgentAnomaly(severity: "none", summary: "")

    static func high(_ summary: String) -> UATAgentAnomaly {
        UATAgentAnomaly(severity: "high", summary: summary)
    }
}

private struct UATStepReport: Codable {
    let index: Int
    let action: String
    let target: String?
    let rationale: String
    let anomaly: UATAgentAnomaly
    let execution: String
    let screenshotAttachment: String?
}

private struct UATStoryReport: Codable {
    let id: String
    let prompt: String
    let launchArguments: [String]
    let steps: [UATStepReport]
    let completed: Bool
}

private struct UATAgentSummary: Codable {
    let totalStories: Int
    let highAnomalies: Int
    let mediumAnomalies: Int
    let lowAnomalies: Int

    static let empty = UATAgentSummary(stories: [])

    init(stories: [UATStoryReport]) {
        totalStories = stories.count
        let severities = stories.flatMap(\.steps).map(\.anomaly.severity)
        highAnomalies = severities.filter { $0 == "high" }.count
        mediumAnomalies = severities.filter { $0 == "medium" }.count
        lowAnomalies = severities.filter { $0 == "low" }.count
    }
}

private struct UATAgentReport: Codable {
    let generatedAt: String
    var model: String
    var stories: [UATStoryReport]
    var summary: UATAgentSummary
}

private enum UATAgentError: Error, LocalizedError {
    case invalidResponse
    case apiFailure(Int, String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenAI response was not an HTTP response."
        case .apiFailure(let status, let body):
            return "OpenAI response failed with HTTP \(status): \(body.prefix(500))"
        case .invalidJSON(let text):
            return "Agent response did not contain a JSON object: \(text.prefix(500))"
        }
    }
}

private extension String {
    func firstJSONObjectData() -> Data? {
        guard let start = firstIndex(of: "{"),
              let end = lastIndex(of: "}") else {
            return nil
        }
        let slice = self[start...end]
        return String(slice).data(using: .utf8)
    }
}
