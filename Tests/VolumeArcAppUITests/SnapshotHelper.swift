import XCTest

/// Minimal fastlane-compatible snapshot helpers.
///
/// Fastlane's screenshot collector reads named XCTest screenshot
/// attachments from the `.xcresult` bundle. Keeping the helper local
/// avoids vendoring generated code while preserving the familiar
/// `setupSnapshot(app)` / `snapshot("name")` call sites from fastlane.
@MainActor
func setupSnapshot(_ app: XCUIApplication) {
    app.launchArguments += [
        "-FASTLANE_SNAPSHOT", "YES",
        "-SkipOnboarding", "1",
        "-SeedFixtures", "1",
    ]
    app.launchArguments += snapshotLaunchArguments()
}

@MainActor
func snapshot(
    _ name: String,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "Screenshot-\(name)"
    attachment.lifetime = .keepAlways
    XCTContext.runActivity(named: "snapshot: \(name)") { activity in
        activity.add(attachment)
    }
}

private func snapshotLaunchArguments() -> [String] {
    guard let cacheDirectory = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    ).first else {
        return []
    }

    let argumentsFile = cacheDirectory.appendingPathComponent("snapshot-launch_arguments.txt")
    guard let contents = try? String(contentsOf: argumentsFile, encoding: .utf8) else {
        return []
    }

    return contents
        .components(separatedBy: .whitespacesAndNewlines)
        .filter { !$0.isEmpty }
}
