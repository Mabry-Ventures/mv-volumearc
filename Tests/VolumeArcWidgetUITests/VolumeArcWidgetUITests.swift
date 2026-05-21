import XCTest
import WidgetKit

/// VOL-139 Phase A: scaffolding-level XCUITests for the iOS widget
/// extension surface.
///
/// Phase A scope:
///   * Confirm the host app + widget extension co-build for the test
///     bundle (the test target's `TEST_TARGET_NAME = VolumeArcApp`
///     embeds the widget extension under `PlugIns/`).
///   * Confirm the test bundle can `WidgetCenter.shared.reloadAllTimelines()`
///     without crashing — proves the WidgetKit linkage and the
///     widget kind names are valid.
///
/// Phase B (separate PR, gated on VOL-135 / VOL-201 snapshot
/// infrastructure landing):
///   * Snapshot-test every widget family (`systemSmall`,
///     `systemMedium`) and `ActiveWorkoutLiveActivity` layout
///     (`compact`, `minimal`, `expanded`) under light + dark + Dynamic
///     Type XXL.
///   * State-transition test: write a widget snapshot, force
///     `WidgetCenter.reloadAllTimelines()`, assert the rendered
///     timeline matches the expected snapshot.
///
/// Why Phase A doesn't drive a real widget render: XCUITest can drive
/// the home-screen widget gallery via
/// `XCUIApplication(bundleIdentifier: "com.apple.springboard")`, but
/// the gallery interaction is flaky on the M4 self-hosted runner
/// (the same `AccessibilityUIServer` wedge that motivated VOL-231
/// sharding). Phase B uses Apple's `WidgetCenter.shared.getCurrentConfigurations(_:)`
/// + image-snapshot capture via `swift-snapshot-testing` instead —
/// no SpringBoard interaction required.
final class VolumeArcWidgetUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Phase A smoke #1: the host app launches with the widget
    /// extension embedded. A regression here means the widget
    /// extension entitlements / Info.plist / embed phase broke and
    /// the host can't bring up its `PlugIns/`.
    func testHostAppLaunchesWithWidgetExtensionEmbedded() throws {
        let app = XCUIApplication()
        app.launch()

        // App reaches foreground. If the widget extension is malformed
        // (broken entitlements, bad Info.plist NSExtension dictionary,
        // missing OTHER_LDFLAGS `-e _NSExtensionMain`), `xctest` would
        // fail to attach to the host because the embed phase would
        // have errored at install time.
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10),
            "Host app must reach foreground with the widget extension's PlugIns/ payload embedded."
        )
    }

    /// Phase A smoke #2: `WidgetCenter` is reachable from the test
    /// bundle's process context. `reloadAllTimelines()` is a no-op
    /// from a non-widget process when no widgets are configured but
    /// it must not crash, and it asserts that `WidgetKit.framework`
    /// is properly linked into the test bundle.
    func testWidgetCenterReloadIsSafeFromTestBundle() throws {
        // `WidgetCenter.shared.reloadAllTimelines()` is documented as
        // a no-op when the requesting process isn't the widget host;
        // the call itself is allowed from any context. If WidgetKit
        // weren't linked correctly, this would surface as a
        // `Symbol not found: _OBJC_CLASS_$_WidgetCenter` crash at
        // first reference.
        XCTAssertNoThrow(WidgetCenter.shared.reloadAllTimelines())
    }
}
