import XCTest

/// Minimal fastlane-compatible snapshot helpers.
///
/// Fastlane's screenshot collector reads named XCTest screenshot
/// attachments from the `.xcresult` bundle. Keeping the helper local
/// avoids vendoring generated code while preserving the familiar
/// `setupSnapshot(app)` / `snapshot("name")` call sites from fastlane.
func setupSnapshot(_ app: XCUIApplication) {
    app.launchArguments += [
        "-FASTLANE_SNAPSHOT", "1",
        "-SkipOnboarding", "1",
        "-SeedFixtures", "1",
    ]
}

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
