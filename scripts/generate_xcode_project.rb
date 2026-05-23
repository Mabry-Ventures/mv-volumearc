#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'json'
require 'pathname'
require 'xcodeproj'

# VOL-95: make `ruby scripts/generate_xcode_project.rb` byte-identical
# between runs so we stop fighting UUID churn in PR merges.
#
# The xcodeproj gem allocates random UUIDs via `SecureRandom.hex(12)` on
# every object creation. Without intervention, every regen thrashes all
# 500+ pbxproj object UUIDs (and every scheme's `BlueprintIdentifier`),
# which makes merges an O(n) game of whack-a-mole.
#
# The gem ships a built-in `predictabilize_uuids` method that rewrites
# every UUID to `Digest::MD5.hexdigest(object_graph_path)` right before
# serialization. That's already the "hash stable attributes into a
# deterministic UUID" scheme the task asks for -- the gem's version is
# battle-tested by CocoaPods, covers every object type the gem knows
# about (so we don't have to enumerate PBXSourcesBuildPhase etc.), and
# is maintained upstream.
#
# Two pieces of finesse are required to make it actually produce
# byte-identical output:
#
# 1. The gem's default MD5 output is 32 chars; real Xcode UUIDs are 24.
#    We truncate to 24 so the pbxproj looks like something Xcode could
#    have written (~96 bits of entropy, collision risk trivially zero
#    for a project with ~500 objects). This keeps diffs legible if a
#    human ever has to open the pbxproj by hand.
#
# 2. `predictabilize_uuids` computes object-graph paths using object
#    references that can themselves contain UUID strings. On the first
#    pass those references are still the original random UUIDs, so the
#    computed paths (and therefore the new UUIDs) still carry randomness.
#    A few passes re-normalize against increasingly deterministic
#    references until the project reaches a fixed point.
module Xcodeproj
  class Project
    class UUIDGenerator
      # Truncate MD5 digest to 24 chars so generated pbxproj UUIDs match
      # Xcode's own 12-byte convention. Overrides the gem default of 32.
      def uuid_for_path(path)
        Digest::MD5.hexdigest(path).upcase[0, 24]
      end
    end
  end
end

ROOT = Pathname.new(__dir__).join('..').expand_path
PACKAGE_ROOT = ROOT.join('VolumeArcNative').expand_path
PROJECT_PATH = ROOT.join('VolumeArcApple.xcodeproj')
IOS_DEPLOYMENT_TARGET = '26.0'
WATCHOS_DEPLOYMENT_TARGET = '26.0'
MARKETING_VERSION = File.read(ROOT.join('VERSION')).strip
# VOL-106: the committed pbxproj must be a pure function of the source tree
# and this script — no git-derived inputs. Before this, BUILD_NUMBER fell
# back to `git rev-list --count HEAD`, which bumps with every merge; that
# changed every XCBuildConfiguration's tree_hash, cascaded through
# predictabilize_uuids, and reshuffled ~300 lines of UUIDs on every regen
# against main. Default to '1' so `ruby scripts/generate_xcode_project.rb`
# is a true no-op. Release tooling that actually ships builds
# (`scripts/archive_for_distribution.sh`, fastlane `increment_build_number`,
# and `xcodebuild CURRENT_PROJECT_VERSION=…` at archive time) passes the
# monotonic build number explicitly and overrides the pbxproj value, so
# TestFlight/App Store uploads keep their real build numbers.
BUILD_NUMBER = ENV.fetch('BUILD_NUMBER', '1')

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)

app_group = project.main_group.new_group('App', 'App')
watch_group = project.main_group.new_group('Watch', 'Watch')
watch_widgets_group = project.main_group.new_group('WatchWidgets', 'WatchWidgets')
widgets_group = project.main_group.new_group('Widgets', 'Widgets')
tests_root_group = project.main_group.new_group('Tests', 'Tests')
tests_group = tests_root_group.new_group('VolumeArcAppTests', 'VolumeArcAppTests')
ui_tests_group = tests_root_group.new_group('VolumeArcAppUITests', 'VolumeArcAppUITests')
# VOL-99: performance regression suite group. Hosts
# `Tests/VolumeArcAppPerfTests/VolumeArcPerfTests.swift`.
perf_tests_group = tests_root_group.new_group('VolumeArcAppPerfTests', 'VolumeArcAppPerfTests')
# VOL-139: widget XCUITest group. Hosts
# `Tests/VolumeArcWidgetUITests/`. Phase A is scaffolding + a build
# / launch smoke; widget-family snapshot tests come in Phase B once
# the snapshot regression infrastructure from VOL-135 / VOL-201
# lands.
widget_ui_tests_group = tests_root_group.new_group('VolumeArcWidgetUITests', 'VolumeArcWidgetUITests')
# VOL-246: register the Xcode Cloud test plans as project file references.
# The shared scheme's <TestPlans> block is enough for
# `xcodebuild -showTestPlans`, but the App Store Connect workflow editor
# enumerates test plans from the PROJECT model — without these
# PBXFileReferences the Test Option dropdown only offers "Use Scheme
# Setting" and won't surface VOL-PR / VOL-Main per-workflow. The
# `.xctestplan` files themselves are (re)written near the end of this
# script, after `project.save`; here we only add the project references
# so they get deterministic UUIDs from `predictabilize_uuids`.
test_plans_group = project.main_group.new_group('TestPlans', 'TestPlans')
test_plan_pr_ref = test_plans_group.new_file('VOL-PR.xctestplan')
test_plan_main_ref = test_plans_group.new_file('VOL-Main.xctestplan')
# Pin the file type to what Xcode itself records for a test plan so the
# project model matches a natively-authored one (the gem leaves an
# unrecognized extension as a generic file otherwise).
[test_plan_pr_ref, test_plan_main_ref].each do |ref|
  ref.last_known_file_type = 'text'
  ref.include_in_index = '0'
end
# VOL-138: dedicated watchOS unit test group. The Watch is positioned as
# a first-class surface in `docs/PRODUCT_POSITIONING.md`, so the same
# tier of structured unit coverage applied to `VolumeArcCore` should
# apply to the watch-side connectivity, payload codec, and pending-
# queue logic. Sources live at `Tests/VolumeArcWatchTests/`.
watch_tests_group = tests_root_group.new_group('VolumeArcWatchTests', 'VolumeArcWatchTests')
shared_group = project.main_group.new_group('Shared Native Package Sources')
core_group = shared_group.new_group('VolumeArcCore', PACKAGE_ROOT.join('Sources/VolumeArcCore').relative_path_from(ROOT).to_s)
ui_group = shared_group.new_group('VolumeArcUI', PACKAGE_ROOT.join('Sources/VolumeArcUI').relative_path_from(ROOT).to_s)

core_target = project.new_target(:static_library, 'VolumeArcCore', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcCore')
core_watch_target = project.new_target(:static_library, 'VolumeArcCoreWatch', :watchos, WATCHOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcCoreWatch')
ui_target = project.new_target(:static_library, 'VolumeArcUI', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcUI')
app_target = project.new_target(:application, 'VolumeArcApp', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArc')
watch_target = project.new_target(:application, 'VolumeArcWatch', :watchos, WATCHOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcWatch')
watch_widgets_target = project.new_target(:app_extension, 'VolumeArcWatchWidgets', :watchos, WATCHOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcWatchWidgets')
widget_target = project.new_target(:app_extension, 'VolumeArcWidgets', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcWidgets')
app_tests_target = project.new_target(:unit_test_bundle, 'VolumeArcAppTests', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcAppTests')
app_ui_tests_target = project.new_target(:ui_test_bundle, 'VolumeArcAppUITests', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcAppUITests')
# VOL-99: performance regression target. Lives as a sibling of the
# smoke UI test target so it can launch `VolumeArcApp` as the host
# and use `XCTMetric`-family APIs. Tag-gated in CI via
# `.github/workflows/ci.yml` because each measured test runs several
# iterations — running on every PR would balloon CI cost.
app_perf_tests_target = project.new_target(:ui_test_bundle, 'VolumeArcAppPerfTests', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcAppPerfTests')
# VOL-139: widget XCUITest bundle. Tests live in
# `Tests/VolumeArcWidgetUITests/`. `TEST_TARGET_NAME = VolumeArcApp`
# follows the same host-application pattern as
# `VolumeArcAppUITests` so the test bundle launches the iOS app
# bundle (which embeds the `VolumeArcWidgets` extension as a
# `PlugIns/` payload). Phase A is scaffolding + a smoke test
# verifying the host app + widget extension co-launch on the
# simulator; widget-family snapshot tests come in Phase B once
# `VOL-135` / `VOL-201` snapshot infra lands.
app_widget_ui_tests_target = project.new_target(:ui_test_bundle, 'VolumeArcWidgetUITests', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcWidgetUITests')
# VOL-138: watchOS unit test bundle. Hosts `VolumeArcCoreWatch` so the
# tests can exercise the shared connectivity / payload / queue types
# compiled against the watchOS SDK rather than only the iOS SDK
# (`VolumeArcAppTests` already exercises the iOS slice via
# `VolumeArcCore`). Built and run on the watchOS simulator by
# `scripts/test_apple_targets.sh`.
app_watch_tests_target = project.new_target(:unit_test_bundle, 'VolumeArcWatchTests', :watchos, WATCHOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcWatchTests')

# xcodeproj only exposes a generic `:app_extension` helper. WidgetKit watch
# extensions need the watch-specific product type so Xcode archives them as
# watch content instead of generic extensions.
watch_widgets_target.product_type = 'com.apple.product-type.watchkit2-extension'

def configure_target(target, bundle_id: nil, extra: {})
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.3'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['MARKETING_VERSION'] = MARKETING_VERSION
    config.build_settings['CURRENT_PROJECT_VERSION'] = BUILD_NUMBER
    config.build_settings['DEVELOPMENT_TEAM'] = ENV.fetch('DEVELOPMENT_TEAM', 'A886EMZZW6')
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    # Release archives must sign so entitlements get baked into the
    # `.xcarchive` at archive time. Xcode Cloud's export step doesn't
    # reliably re-add entitlements when the archive is unsigned —
    # rc9 / Build 6 launched into a CKContainer SIGTRAP because the
    # signed `.ipa` produced from an unsigned archive was missing
    # `com.apple.developer.icloud-services`. Debug stays unsigned so
    # local sim builds and `xcodebuild test` runs don't need certs.
    # Test targets override this back to NO via their `extra:` dict
    # (xctest bundles don't need signing).
    config.build_settings['CODE_SIGNING_ALLOWED'] =
      config.name == 'Release' ? 'YES' : 'NO'
    config.build_settings['DISABLE_MANUAL_TARGET_ORDER_BUILD_WARNING'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id if bundle_id
    extra.each do |key, value|
      config.build_settings[key] = value
    end
  end
end

def assign_deterministic_uuid(object, seed)
  uuid = Digest::MD5.hexdigest(seed).upcase[0, 24]
  project = object.project
  existing = project.objects_by_uuid[uuid]
  raise "Deterministic UUID collision for #{seed}: #{uuid}" if existing && existing != object

  project.objects_by_uuid.delete(object.uuid)
  object.instance_variable_set(:@uuid, uuid)
  project.objects_by_uuid[uuid] = object
end

configure_target(core_target, extra: {
  'DEFINES_MODULE' => 'YES',
  'SKIP_INSTALL' => 'YES',
})
configure_target(core_watch_target, extra: {
  'DEFINES_MODULE' => 'YES',
  'PRODUCT_MODULE_NAME' => 'VolumeArcCore',
  'SKIP_INSTALL' => 'YES',
})
configure_target(ui_target, extra: {
  'DEFINES_MODULE' => 'YES',
  'SKIP_INSTALL' => 'YES',
})
configure_target(app_target, bundle_id: 'com.mabryventures.VolumeArc', extra: {
  'PRODUCT_NAME' => 'VolumeArc',
  # VOL-131: iPhone-only for v1.0 TestFlight. iPad support deferred
  # until VOL-158 completes its UX-audit pass against the iPad form
  # factor. The TestFlight-eligible matrix is the iPhone family (1);
  # iPad lands as a separate explicit decision once the audit signs
  # off on the experience. Snapfile + CI test matrix are already
  # iPhone-only — this change brings the entitlement / device-family
  # declaration in line with the shipped surface.
  'TARGETED_DEVICE_FAMILY' => '1',
  'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents' => 'YES',
  'INFOPLIST_KEY_NSHealthShareUsageDescription' => 'VolumeArc reads your completed workouts, heart-rate variability, and sleep from Apple Health to show your training history, calculate readiness, and let the AI coach reference your recovery trend (HRV vs baseline, sleep debt, weekly strength load).',
  'INFOPLIST_KEY_NSHealthUpdateUsageDescription' => 'VolumeArc writes completed workouts so your training history stays in sync with Apple Health.',
  'INFOPLIST_KEY_NSMicrophoneUsageDescription' => 'VolumeArc uses the microphone for voice coaching requests and voice workout logging.',
  'INFOPLIST_KEY_NSSpeechRecognitionUsageDescription' => 'VolumeArc uses speech recognition to understand live coaching requests and voice workout notes.',
  # Export-compliance declaration. Without this, every TestFlight upload
  # lands in "Missing Compliance" and stalls the Xcode Cloud post-action
  # waiting on a manual ASC answer. VolumeArc only uses HTTPS via
  # URLSession (Sentry, Gemini relay) — that's covered by Apple's
  # standard exemption, so NO is correct. Revisit if we ever ship
  # custom crypto.
  'INFOPLIST_KEY_ITSAppUsesNonExemptEncryption' => 'NO',
  # User-defined build settings declared empty so `App/Info.plist`
  # `$(SENTRY_DSN)` / `$(VOLUMEARC_AI_RELAY_URL)` substitutions
  # resolve cleanly when no env var is set (local/CI builds without
  # secrets just get empty strings, which both `resolveDSN()` and
  # `relayConfiguration()` handle as "not configured"). Xcode Cloud
  # workflows override these from the Environment Variables panel so
  # archived builds carry the production values.
  'SENTRY_DSN' => '',
  'VOLUMEARC_AI_RELAY_URL' => '',
  # VOL-196: relay signing key, same pattern as the two above. Empty
  # in local/dev builds (`AIRelayCoachProvider` factory falls back to
  # the local heuristic provider when both URL and key are empty); set
  # by `ci_scripts/ci_post_clone.sh` from VOLUMEARC_RELAY_SIGNING_KEY
  # env var at Xcode Cloud archive time. Required for release builds
  # — `scripts/validate_exported_ipa_contract.sh` fails the archive
  # if URL is present but key is missing.
  'VOLUMEARC_RELAY_SIGNING_KEY' => '',
  # VOL-55: `VolumeArcCloudKitContainer` used to live in the Info.plist
  # for runtime lookup. `INFOPLIST_KEY_*` silently drops custom
  # (non-Apple-recognized) keys, so the bundle never had it. It now
  # lives as a compile-time constant in
  # `App/VolumeArcCloudConfiguration.swift` (the value is bound to the
  # app bundle ID anyway and never varies at runtime).
  #
  # VOL-56 / VOL-56b: `BGTaskSchedulerPermittedIdentifiers`,
  # `UIBackgroundModes`, and `CFBundleURLTypes` are array/dict-array
  # types that `INFOPLIST_KEY_*` cannot express at all — Xcode silently
  # drops them regardless of syntax. We ship them via a minimal
  # checked-in `App/Info.plist` that's merged into the final bundle
  # plist by `ProcessInfoPlistFile`. `GENERATE_INFOPLIST_FILE = YES`
  # stays on so Xcode still auto-populates all the boilerplate keys
  # (CFBundleExecutable, MinimumOSVersion, UIDeviceFamily, etc.) and
  # merges the simple `INFOPLIST_KEY_*` values above.
  'INFOPLIST_FILE' => 'App/Info.plist',
})

# VOL-70: APS environment must be `production` for Release-signed IPAs or
# App Store Connect will reject uploads and silently drop remote
# notifications. Split entitlements per configuration so Debug /
# simulator builds keep `development` (required for APNs sandbox
# tokens) and Release builds ship `production`. Override after
# `configure_target` so this stays a one-line pin rather than a
# restructure of the shared helper.
app_target.build_configurations.each do |config|
  entitlements = config.name == 'Release' ? 'App/VolumeArc.Release.entitlements' : 'App/VolumeArc.Debug.entitlements'
  config.build_settings['CODE_SIGN_ENTITLEMENTS'] = entitlements
end
configure_target(watch_target, bundle_id: 'com.mabryventures.VolumeArc.watchkitapp', extra: {
  'TARGETED_DEVICE_FAMILY' => '4',
  'PRODUCT_NAME' => 'VolumeArcWatch',
  'ASSETCATALOG_COMPILER_APPICON_NAME' => 'AppIcon',
  # App Store Connect still validates the watch app's legacy
  # CFBundleIconFiles array in addition to the asset-catalog
  # CFBundleIconName. Keep those structured icon keys in a real plist;
  # INFOPLIST_KEY_* cannot express the nested dictionary/array shape.
  'INFOPLIST_FILE' => 'Watch/Info.plist',
  'INFOPLIST_KEY_WKApplication' => 'YES',
  'INFOPLIST_KEY_WKCompanionAppBundleIdentifier' => 'com.mabryventures.VolumeArc',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait',
  'INFOPLIST_KEY_NSHealthShareUsageDescription' => 'VolumeArc reads workouts, heart rate, and active energy on Apple Watch so live strength sessions save with accurate training history, heart-rate charts, and calorie totals.',
  'INFOPLIST_KEY_NSHealthUpdateUsageDescription' => 'VolumeArc writes completed watch workouts to Apple Health.',
  'CODE_SIGN_ENTITLEMENTS' => 'Watch/VolumeArcWatch.entitlements',
})
configure_target(widget_target, bundle_id: 'com.mabryventures.VolumeArc.widgets', extra: {
  'PRODUCT_NAME' => 'VolumeArcWidgets',
  # VOL-131: match the iPhone-only host app. Widget extensions
  # inherit the host's eligible-device set at install time, but
  # being explicit avoids a future App Store reviewer flagging the
  # widget for "claims iPad support but parent app doesn't."
  'TARGETED_DEVICE_FAMILY' => '1',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'OTHER_LDFLAGS' => ['$(inherited)', '-e', '_NSExtensionMain'],
  'SKIP_INSTALL' => 'YES',
  'CODE_SIGN_ENTITLEMENTS' => 'Widgets/VolumeArcWidgets.entitlements',
  # WidgetKit requires a nested NSExtension dictionary. INFOPLIST_KEY_* build
  # settings silently drop nested plist keys, so keep this in source.
  'INFOPLIST_FILE' => 'Widgets/Info.plist',
})
configure_target(watch_widgets_target, bundle_id: 'com.mabryventures.VolumeArc.watchkitapp.widgets', extra: {
  'PRODUCT_NAME' => 'VolumeArcWatchWidgets',
  'TARGETED_DEVICE_FAMILY' => '4',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'OTHER_LDFLAGS' => ['$(inherited)', '-e', '_NSExtensionMain'],
  'SKIP_INSTALL' => 'YES',
  'CODE_SIGN_ENTITLEMENTS' => 'WatchWidgets/VolumeArcWatchWidgets.entitlements',
  # Same WidgetKit nested-plist requirement as the iOS widget extension.
  'INFOPLIST_FILE' => 'WatchWidgets/Info.plist',
})
configure_target(app_tests_target, bundle_id: 'com.mabryventures.VolumeArc.tests', extra: {
  'PRODUCT_NAME' => 'VolumeArcAppTests',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGNING_ALLOWED' => 'NO',
  'CODE_SIGNING_REQUIRED' => 'NO',
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS' => 'DEBUG VOLUMEARC_WIDGET_SNAPSHOT_TESTING',
  'SKIP_INSTALL' => 'YES',
})
configure_target(app_ui_tests_target, bundle_id: 'com.mabryventures.VolumeArc.uitests', extra: {
  'PRODUCT_NAME' => 'VolumeArcAppUITests',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGNING_ALLOWED' => 'NO',
  'CODE_SIGNING_REQUIRED' => 'NO',
  'SKIP_INSTALL' => 'YES',
  'TEST_TARGET_NAME' => 'VolumeArcApp',
})
configure_target(app_perf_tests_target, bundle_id: 'com.mabryventures.VolumeArc.perftests', extra: {
  'PRODUCT_NAME' => 'VolumeArcAppPerfTests',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGNING_ALLOWED' => 'NO',
  'CODE_SIGNING_REQUIRED' => 'NO',
  'SKIP_INSTALL' => 'YES',
  'TEST_TARGET_NAME' => 'VolumeArcApp',
})
# VOL-139: widget XCUITest bundle. Hosted by VolumeArcApp so the
# iOS widget extension (`PlugIns/VolumeArcWidgets.appex`) loads with
# the host app and the test bundle can interact with the widget
# host via `WidgetCenter` / `XCUIApplication(bundleIdentifier:)`.
configure_target(app_widget_ui_tests_target, bundle_id: 'com.mabryventures.VolumeArc.widgetuitests', extra: {
  'PRODUCT_NAME' => 'VolumeArcWidgetUITests',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGNING_ALLOWED' => 'NO',
  'CODE_SIGNING_REQUIRED' => 'NO',
  'SKIP_INSTALL' => 'YES',
  'TEST_TARGET_NAME' => 'VolumeArcApp',
})
# VOL-138: watch-side unit test bundle. No `TEST_TARGET_NAME` — the
# tests link `VolumeArcCoreWatch` (a static library) directly and run
# library-level assertions, no host app required. That matches how
# `VolumeArcAppTests` exercises `VolumeArcCore` on iOS.
configure_target(app_watch_tests_target, bundle_id: 'com.mabryventures.VolumeArc.watchtests', extra: {
  'PRODUCT_NAME' => 'VolumeArcWatchTests',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGNING_ALLOWED' => 'NO',
  'CODE_SIGNING_REQUIRED' => 'NO',
  'SKIP_INSTALL' => 'YES',
})

ui_target.add_dependency(core_target)
ui_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
app_target.add_dependency(core_target)
app_target.add_dependency(ui_target)
app_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
app_target.frameworks_build_phase.add_file_reference(ui_target.product_reference, true)
watch_target.add_dependency(core_watch_target)
watch_target.frameworks_build_phase.add_file_reference(core_watch_target.product_reference, true)
watch_widgets_target.add_dependency(core_watch_target)
watch_widgets_target.frameworks_build_phase.add_file_reference(core_watch_target.product_reference, true)
widget_target.add_dependency(core_target)
widget_target.add_dependency(ui_target)
widget_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
widget_target.frameworks_build_phase.add_file_reference(ui_target.product_reference, true)
app_tests_target.add_dependency(core_target)
app_tests_target.add_dependency(ui_target)
app_tests_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
app_tests_target.frameworks_build_phase.add_file_reference(ui_target.product_reference, true)
app_ui_tests_target.add_dependency(app_target)
app_perf_tests_target.add_dependency(app_target)
app_widget_ui_tests_target.add_dependency(app_target) # VOL-139
# VOL-138: watch tests link the watch flavor of the shared core library.
app_watch_tests_target.add_dependency(core_watch_target)
app_watch_tests_target.frameworks_build_phase.add_file_reference(core_watch_target.product_reference, true)

widget_target.add_system_framework('WidgetKit')
widget_target.add_system_framework('AppIntents')
widget_target.add_system_framework('ActivityKit')
app_target.add_system_framework('AppIntents')
app_target.add_system_framework('ActivityKit')
app_target.add_system_framework('AuthenticationServices')
app_target.add_system_framework('AVFoundation')
app_target.add_system_framework('Security')
app_target.add_system_framework('Speech')
watch_target.add_system_framework('WatchKit')
watch_target.add_system_framework('SwiftUI')
watch_widgets_target.add_system_framework('WidgetKit')
watch_widgets_target.add_system_framework('SwiftUI')
app_tests_target.add_system_framework('XCTest')
app_tests_target.add_system_framework('AuthenticationServices')
app_tests_target.add_system_framework('Security')
app_tests_target.add_system_framework('AppIntents')
app_tests_target.add_system_framework('ActivityKit')
app_tests_target.add_system_framework('WidgetKit')
# VOL-142: StoreKitTest powers `SKTestSession`-based unit tests
# (`StoreKitSubscriptionRevocationTests`) for refund / family-share /
# grace-period coverage at the model level. UITest target already has
# this dependency for journey-level paywall tests.
app_tests_target.add_system_framework('StoreKitTest')
app_ui_tests_target.add_system_framework('XCTest')
app_ui_tests_target.add_system_framework('StoreKitTest')
app_perf_tests_target.add_system_framework('XCTest')
# VOL-139: widget XCUITest bundle.
app_widget_ui_tests_target.add_system_framework('XCTest')
app_widget_ui_tests_target.add_system_framework('WidgetKit')
# VOL-138: watch test bundle.
app_watch_tests_target.add_system_framework('XCTest')
app_watch_tests_target.add_system_framework('SwiftUI')

embed_watch_extensions_phase = watch_target.new_copy_files_build_phase('Embed Watch Extensions')
embed_watch_extensions_phase.symbol_dst_subfolder_spec = :plug_ins
embed_watch_widget_build_file = embed_watch_extensions_phase.add_file_reference(watch_widgets_target.product_reference, true)
embed_watch_widget_build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

embed_watch_app_phase = app_target.new_copy_files_build_phase('Embed Watch Content')
embed_watch_app_phase.symbol_dst_subfolder_spec = :products_directory
embed_watch_app_phase.dst_path = '$(CONTENTS_FOLDER_PATH)/Watch'
embed_watch_app_phase.run_only_for_deployment_postprocessing = '0'
embed_watch_app_build_file = embed_watch_app_phase.add_file_reference(watch_target.product_reference, true)
embed_watch_app_build_file.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
embed_watch_app_build_file.platform_filter = 'iphoneos'

def add_swift_sources(group, target, base_dir)
  refs = Dir[base_dir.join('**/*.swift').to_s].sort.map do |file|
    relative_to_group = Pathname.new(file).relative_path_from(base_dir).to_s
    group.find_file_by_path(relative_to_group) || group.new_file(relative_to_group)
  end
  target.add_file_references(refs)
end

def add_resource(group, target, relative_path)
  ref = group.find_file_by_path(relative_path) || group.new_file(relative_path)
  target.resources_build_phase.add_file_reference(ref, true)
end

def add_selected_swift_sources(group, target, base_dir, relative_paths)
  refs = relative_paths.map do |relative_path|
    group.find_file_by_path(relative_path) || group.new_file(relative_path)
  end
  target.add_file_references(refs)
end

add_swift_sources(core_group, core_target, PACKAGE_ROOT.join('Sources/VolumeArcCore'))
add_swift_sources(core_group, core_watch_target, PACKAGE_ROOT.join('Sources/VolumeArcCore'))
add_swift_sources(ui_group, ui_target, PACKAGE_ROOT.join('Sources/VolumeArcUI'))
add_swift_sources(app_group, app_target, ROOT.join('App'))
add_swift_sources(watch_group, watch_target, ROOT.join('Watch'))
add_swift_sources(watch_widgets_group, watch_widgets_target, ROOT.join('WatchWidgets'))
add_swift_sources(widgets_group, widget_target, ROOT.join('Widgets'))
add_swift_sources(tests_group, app_tests_target, ROOT.join('Tests/VolumeArcAppTests'))
add_swift_sources(ui_tests_group, app_ui_tests_target, ROOT.join('Tests/VolumeArcAppUITests'))
add_swift_sources(perf_tests_group, app_perf_tests_target, ROOT.join('Tests/VolumeArcAppPerfTests'))
# VOL-139: widget XCUITest sources.
add_swift_sources(widget_ui_tests_group, app_widget_ui_tests_target, ROOT.join('Tests/VolumeArcWidgetUITests'))
# VOL-138: watch-side unit tests. Sources live at
# `Tests/VolumeArcWatchTests/` so they parallel the other test bundles.
add_swift_sources(watch_tests_group, app_watch_tests_target, ROOT.join('Tests/VolumeArcWatchTests'))
# VOL-234/VOL-233: compile the standalone AOD render contract and
# WatchWorkoutModel into watch tests so the watch active-session surface can be
# verified without a host app.
add_selected_swift_sources(watch_group, app_watch_tests_target, ROOT.join('Watch'), [
  'VADesignTokens.swift',
  'WatchAlwaysOnWorkoutView.swift',
  'WatchWorkoutView.swift',
])
add_resource(ui_tests_group, app_ui_tests_target, 'VolumeArcTests.storekit')
# VOL-142: the same StoreKit configuration powers `SKTestSession`-based
# unit tests under `Tests/VolumeArcAppTests/`. Reuse the existing
# `PBXFileReference` rather than creating a second one — same file on
# disk, just present in both test bundles at build time.
storekit_resource_ref = ui_tests_group.find_file_by_path('VolumeArcTests.storekit')
app_tests_target.resources_build_phase.add_file_reference(storekit_resource_ref, true)
add_resource(app_group, app_target, 'PrivacyInfo.xcprivacy')
add_resource(watch_group, watch_target, 'PrivacyInfo.xcprivacy')
add_resource(watch_widgets_group, watch_widgets_target, 'PrivacyInfo.xcprivacy')
add_resource(widgets_group, widget_target, 'PrivacyInfo.xcprivacy')
add_resource(watch_group, watch_target, 'Assets.xcassets')

# VOL-105 Phase 2: ship the exercise-illustration asset catalog with the
# app target. The catalog provides namespacing via Contents.json so each
# entry is loadable from SwiftUI as e.g.
# `Image("ExerciseIllustrations/back-squat", bundle: .main)`. Letting
# xcodeproj infer `folder.assetcatalog` from the `.xcassets` extension
# keeps the project file deterministic — no per-imageset entries in the
# pbxproj, just one folder reference.
add_resource(app_group, app_target, 'Assets.xcassets')

# VOL-100: coach eval fixtures wired into the tests bundle so
# `CoachEvalTests` can resolve them via
# `Bundle(for:).url(forResource: "CoachEvalFixtures")`. The directory lives
# under `Tests/Evals/CoachEvalFixtures/` (outside `Tests/VolumeArcAppTests/`
# on purpose — the same JSON files are read by
# `scripts/run_coach_evals.sh` from a repo-root path, so a single on-disk
# location serves both the hermetic XCTests and the nightly relay eval).
# Added as a folder reference so the 20 JSON files copy into the tests
# bundle as a `CoachEvalFixtures/` folder rather than individually.
evals_group = tests_root_group.new_group('Evals', 'Evals')
fixtures_relative = ROOT.join('Tests/Evals/CoachEvalFixtures').relative_path_from(ROOT.join('Tests/Evals')).to_s
fixture_folder_ref = evals_group.new_reference(fixtures_relative)
fixture_folder_ref.set_last_known_file_type('folder')
app_tests_target.resources_build_phase.add_file_reference(fixture_folder_ref, true)

# VOL-246: bundle the real AppIcon.appiconset into the test bundle so
# `AppIconAssetContractTests` can resolve it via `Bundle(for:)` at run
# time. Its previous approach walked up from `#filePath` calling
# `FileManager.fileExists` on the source tree — which works locally and
# on the self-hosted runner, but FAILS on Xcode Cloud, where unit tests
# run inside the simulator sandbox and can't read the host checkout at
# `/Volumes/workspace/repository`. Wired as a FOLDER reference (not a
# `.xcassets` catalog) so the raw `Contents.json` + the two PNGs copy
# verbatim into the bundle — the test validates the actual source
# catalog (folder ref to the real files, copied at build time), not a
# drifting duplicate.
app_icon_relative = ROOT.join('App/Assets.xcassets/AppIcon.appiconset')
                        .relative_path_from(ROOT.join('Tests/VolumeArcAppTests')).to_s
app_icon_folder_ref = tests_group.new_reference(app_icon_relative)
app_icon_folder_ref.set_last_known_file_type('folder')
app_tests_target.resources_build_phase.add_file_reference(app_icon_folder_ref, true)

# VOL-135: bundle committed snapshot PNG references into VolumeArcAppTests.
# Xcode Cloud's test phase cannot rely on the source checkout being mounted
# inside the simulator sandbox, so snapshot comparisons must resolve their
# baselines from `Bundle(for:)`. The tests still record into the source tree
# when `SNAPSHOT_TESTING_RECORD=all|missing` is set; compare mode reads this
# folder reference from the built test bundle.
snapshot_references_relative = ROOT.join('Tests/VolumeArcAppTests/Snapshots/__Snapshots__')
                                   .relative_path_from(ROOT.join('Tests/VolumeArcAppTests')).to_s
snapshot_references_folder_ref = tests_group.new_reference(snapshot_references_relative)
snapshot_references_folder_ref.set_last_known_file_type('folder')
app_tests_target.resources_build_phase.add_file_reference(snapshot_references_folder_ref, true)

add_selected_swift_sources(app_group, app_tests_target, ROOT.join('App'), [
  'Intents/VolumeArcIntents.swift',
  'VolumeArcAIConfiguration.swift',
  # VOL-91: included in the test target so
  # `VolumeArcPremiumGatingTests` can exercise the premium-entitlement
  # gating directly without spinning up `VolumeArcApp`. The factory
  # closes over `VolumeArcAIConfiguration.relayConfiguration` which is
  # also in this list.
  'VolumeArcAIRuntimeFactory.swift',
  # VOL-224: `VolumeArcAppAttestCoordinatorTests` exercises the App
  # Attest coordinator + protocol mock directly. Same pattern as the
  # other App-internal types below — the App target doesn't expose a
  # Swift module testable from outside, so the source is compiled into
  # the test bundle. Pure additive; production wiring lands in Phase B.
  'VolumeArcAppAttestService.swift',
  'VolumeArcCloudConfiguration.swift',
  'VolumeArcLiveActivityController.swift',
  'VolumeArcPersistenceController.swift',
  'VolumeArcPremiumCatalog.swift',
  'VolumeArcRelaySessionProvider.swift',
  'VolumeArcSecureStore.swift',
  # VOL-72: included in the test target so
  # `VolumeArcSentryPIIScrubberTests` can unit-test the scrubber's
  # logic against real `Event`/`Breadcrumb` instances. Guarded by
  # `#if canImport(Sentry)` inside the file.
  'VolumeArcSentryPIIScrubber.swift',
  # VOL-129: same pattern as the scrubber — `VolumeArcSentryConfigurationTests`
  # asserts the release-name format from `computeReleaseName(bundle:)`
  # against synthetic bundles. The App target doesn't expose a Swift
  # module that tests can `@testable import`, so the source is compiled
  # directly into the test bundle. Guarded by `#if canImport(Sentry)`.
  'VolumeArcSentryConfiguration.swift',
  'VolumeArcWidgetController.swift',
  # VOL-136: same pattern — `HealthKitRecoveryReaderTests` injects a
  # `FakeRecoverySampleSource` through the reader's internal seam init to
  # exercise the HRV-delta / sleep-debt aggregation + the empty / partial /
  # query-failed telemetry routing without a live `HKHealthStore`. The App
  # target exposes no testable Swift module, so the source is compiled into
  # the test bundle. Guarded by `#if canImport(HealthKit)` inside the file.
  'Health/HealthKitRecoveryReader.swift',
])
add_selected_swift_sources(widgets_group, app_tests_target, ROOT.join('Widgets'), [
  'VolumeArcWidgets.swift',
])

# Sentry Swift Package dependency
# Pinned to exact version per VOL-86: crash-reporting SDK must not silently
# auto-upgrade. Dependabot (VOL-78) surfaces bumps as explicit PRs.
sentry_url = 'https://github.com/getsentry/sentry-cocoa.git'
# VOL-95: string keys (not symbols). `predictabilize_uuids` walks every
# object's tree hash and concatenates keys; on a Hash with Symbol keys
# it raises "no implicit conversion of Symbol into String" deep inside
# the gem's `tree_hash_to_path`. Stick to strings so deterministic UUID
# rewriting can traverse this attribute.
sentry_requirement = { 'kind' => 'exactVersion', 'version' => '9.13.0' }
sentry_ref = project.root_object.package_references.find { |r| r.repositoryURL == sentry_url }
unless sentry_ref
  sentry_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  sentry_ref.repositoryURL = sentry_url
  project.root_object.package_references << sentry_ref
end
sentry_ref.requirement = sentry_requirement
sentry_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
sentry_dep.package = sentry_ref
sentry_dep.product_name = 'Sentry'
app_target.package_product_dependencies << sentry_dep

# VOL-72: Sentry dependency also attached to the unit-test target so
# `VolumeArcSentryPIIScrubberTests` can instantiate `Event` /
# `Breadcrumb` for scrubber assertions. The scrubber source itself is
# compiled into both targets via `add_selected_swift_sources` and
# guarded by `#if canImport(Sentry)`.
sentry_tests_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
sentry_tests_dep.package = sentry_ref
sentry_tests_dep.product_name = 'Sentry'
app_tests_target.package_product_dependencies << sentry_tests_dep

# VOL-135 Phase 1: swift-snapshot-testing dependency for the unit-test
# target only. The library powers visual-regression coverage for VAUI
# components and screens — Phase 1 wires the dependency + ships one
# proof-of-concept snapshot test; Phase 2 expands across the full
# component matrix per VOL-135's acceptance criteria.
#
# Pinned with `upToNextMajorVersion` (not Sentry-style `exactVersion`)
# because test-only deps don't ship to users — minor bumps are
# low-risk and Dependabot still surfaces them as explicit PRs.
snapshot_url = 'https://github.com/pointfreeco/swift-snapshot-testing.git'
snapshot_requirement = {
  'kind' => 'upToNextMajorVersion',
  'minimumVersion' => '1.17.0',
}
snapshot_ref = project.root_object.package_references.find { |r| r.repositoryURL == snapshot_url }
unless snapshot_ref
  snapshot_ref = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  snapshot_ref.repositoryURL = snapshot_url
  project.root_object.package_references << snapshot_ref
end
snapshot_ref.requirement = snapshot_requirement
snapshot_tests_dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
snapshot_tests_dep.package = snapshot_ref
snapshot_tests_dep.product_name = 'SnapshotTesting'
app_tests_target.package_product_dependencies << snapshot_tests_dep

# VOL-126: re-sign embedded frameworks with the app's distribution
# identity at archive time. Without this, sentry-cocoa's SPM-managed
# dynamic framework retains its upstream signature (or no signature)
# inside `VolumeArc.app/Frameworks/Sentry.framework/Sentry`, and App
# Store Connect upload fails with:
#
#   ITMS-90035: Invalid Signature - Code failed to satisfy specified
#   code requirement(s). The file at path
#   "VolumeArc.app/Frameworks/Sentry.framework/Sentry" is not properly
#   signed. Make sure you have signed your application with a
#   distribution certificate, not an ad hoc certificate or a
#   development certificate.
#
# The script runs only when CODE_SIGN_IDENTITY is set (i.e., archive
# / device builds — never on simulator or unit-test runs where signing
# is disabled). It strips the existing signature and re-signs with the
# expanded identity so the framework matches the app's distribution
# trust chain.
resign_phase = project.new(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)
resign_phase.name = 'Re-sign embedded frameworks (VOL-126)'
resign_phase.shell_path = '/bin/bash'
resign_phase.shell_script = <<~BASH
  # VOL-126 — re-sign nested frameworks with the app's distribution cert.
  # See generator comment for ITMS-90035 context.
  set -euo pipefail

  if [ -z "${CODE_SIGN_IDENTITY:-}" ] || [ "${CODE_SIGN_IDENTITY}" = "" ]; then
    echo "VOL-126: CODE_SIGN_IDENTITY unset — skipping framework re-sign (test/sim build)"
    exit 0
  fi

  IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY}}"
  FRAMEWORKS_DIR="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
  if [ ! -d "${FRAMEWORKS_DIR}" ]; then
    echo "VOL-126: no Frameworks dir at ${FRAMEWORKS_DIR} — nothing to re-sign"
    exit 0
  fi

  shopt -s nullglob
  for fw in "${FRAMEWORKS_DIR}"/*.framework; do
    name=$(basename "$fw")
    echo "VOL-126: re-signing ${name} with ${IDENTITY}"
    /usr/bin/codesign --force \\
      --sign "${IDENTITY}" \\
      --preserve-metadata=identifier,entitlements,flags \\
      --timestamp \\
      --options=runtime \\
      "$fw"
  done
  echo "VOL-126: framework re-signing complete"
BASH
resign_phase.input_paths = []
resign_phase.output_paths = []
resign_phase.run_only_for_deployment_postprocessing = '0'
# Outputs aren't statically knowable (frameworks depend on SPM resolution),
# so opt out of dependency analysis instead of declaring fake outputs.
resign_phase.always_out_of_date = '1'
app_target.build_phases << resign_phase

project.root_object.attributes['TargetAttributes'] ||= {}
project.targets.each do |target|
  project.root_object.attributes['TargetAttributes'][target.uuid] = {
    'CreatedOnToolsVersion' => '26.4',
  }
end

# VOL-95: multiple passes are required. Pass 1 rewrites most UUIDs from
# graph-path MD5 hashes, but objects that reference other objects by UUID
# string (e.g. `PBXContainerItemProxy.remote_global_id_string`) still carry
# old random references in their tree-hash paths. Later passes run against
# the increasingly deterministic references and converge. Must run before
# `project.save` and before scheme generation so schemes pick up the final,
# deterministic target UUIDs as BlueprintIdentifier. Keep iterating to a
# fixed point so new target-dependency shapes do not silently reintroduce
# one-pass UUID drift.
12.times { project.predictabilize_uuids }

# The app/watch copy phases need explicit target dependencies so isolated
# schemes, including the tag-gated perf scheme, build the watch products before
# copying them. Adding these dependencies before `predictabilize_uuids` makes
# xcodeproj's graph-path hashing oscillate because the targets and dependency
# proxies reference each other's generated UUIDs. Add them after the rest of the
# graph reaches its deterministic fixed point, then pin the new dependency
# objects to content-derived UUIDs.
app_target.add_dependency(watch_target)
app_watch_dependency = app_target.dependency_for_target(watch_target)
assign_deterministic_uuid(app_watch_dependency, 'VolumeArcApp/PBXTargetDependency/VolumeArcWatch')
assign_deterministic_uuid(app_watch_dependency.target_proxy, 'VolumeArcApp/PBXContainerItemProxy/VolumeArcWatch')

watch_target.add_dependency(watch_widgets_target)
watch_widget_dependency = watch_target.dependency_for_target(watch_widgets_target)
assign_deterministic_uuid(watch_widget_dependency, 'VolumeArcWatch/PBXTargetDependency/VolumeArcWatchWidgets')
assign_deterministic_uuid(watch_widget_dependency.target_proxy, 'VolumeArcWatch/PBXContainerItemProxy/VolumeArcWatchWidgets')

project.save
app_scheme = Xcodeproj::XCScheme.new
app_scheme.configure_with_targets(app_target, nil, launch_target: true)

# TestFlight only attaches the watch app when the app archive scheme includes
# the watch target. Xcode-generated iOS+watch projects keep the watch target
# in the normal app build graph too; otherwise the iOS simulator app copy phase
# can run before the watchsimulator product exists.
watch_archive_entry = Xcodeproj::XCScheme::BuildAction::Entry.new(watch_target)
watch_archive_entry.build_for_testing = true
watch_archive_entry.build_for_running = true
watch_archive_entry.build_for_profiling = true
watch_archive_entry.build_for_archiving = true
watch_archive_entry.build_for_analyzing = true
app_scheme.build_action.add_entry(watch_archive_entry)
app_scheme.save_as(PROJECT_PATH, 'VolumeArcApp', true)

test_scheme = Xcodeproj::XCScheme.new
test_scheme.configure_with_targets(nil, app_tests_target)
# VOL-52: enable code coverage so `xcodebuild test -enableCodeCoverage YES`
# in `scripts/test_apple_targets.sh` produces an xcresult bundle with
# per-target coverage data. `scripts/check_coverage.sh` reads it via
# `xcrun xccov view --report --json` to enforce the 80% VolumeArcCore
# line-coverage gate.
test_scheme.test_action.code_coverage_enabled = true
test_scheme.save_as(PROJECT_PATH, 'VolumeArcAppTests', true)

ui_test_scheme = Xcodeproj::XCScheme.new
ui_test_scheme.configure_with_targets(app_target, app_ui_tests_target)
ui_test_scheme.save_as(PROJECT_PATH, 'VolumeArcAppUITests', true)

# VOL-107: activate the local StoreKit configuration for UI-test app
# launches. xcodeproj can write the scheme, but this gem version does
# not expose StoreKitConfigurationFileReference on XCScheme, so patch the
# generated XML deterministically after saving.
ui_scheme_path = PROJECT_PATH.join('xcshareddata/xcschemes/VolumeArcAppUITests.xcscheme')
ui_scheme_xml = File.read(ui_scheme_path)
app_runnable = <<~XML.chomp
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "#{app_target.uuid}"
            BuildableName = "VolumeArc.app"
            BlueprintName = "VolumeArcApp"
            ReferencedContainer = "container:VolumeArcApple.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
XML
storekit_reference = <<~XML.chomp
      <StoreKitConfigurationFileReference
         identifier = "../Tests/VolumeArcAppUITests/VolumeArcTests.storekit">
      </StoreKitConfigurationFileReference>
XML
unless ui_scheme_xml.include?('StoreKitConfigurationFileReference')
  launch_action_close = '   </LaunchAction>'
  launch_action_payload = ui_scheme_xml.include?('BuildableProductRunnable') ? storekit_reference : "#{app_runnable}\n#{storekit_reference}"
  inserted = ui_scheme_xml.sub!(launch_action_close, "#{launch_action_payload}\n#{launch_action_close}")
  unless inserted
    raise "Failed to insert StoreKitConfigurationFileReference into #{ui_scheme_path}; " \
          'VolumeArcAppUITests LaunchAction XML format may have changed.'
  end
  File.write(ui_scheme_path, ui_scheme_xml)
end

# VOL-99: dedicated perf scheme. `scripts/test_performance.sh`
# (invoked by the tag-gated `perf-regression` CI job) selects it via
# `-scheme VolumeArcAppPerfTests`. Kept separate from the smoke UI
# scheme so the perf suite's longer measured-run time is isolated from
# the PR-gating UI smoke run.
perf_test_scheme = Xcodeproj::XCScheme.new
perf_test_scheme.configure_with_targets(app_target, app_perf_tests_target)
perf_test_scheme.save_as(PROJECT_PATH, 'VolumeArcAppPerfTests', true)

# VOL-139: dedicated widget UI test scheme. Mirrors the smoke UI scheme
# but with the widget-test bundle. The host app launches and the
# widget extension is automatically embedded via the
# `Embed Foundation Extensions` build phase, so the test bundle can
# observe widget timeline reloads + (Phase B) drive the simulator
# widget gallery to snapshot each family.
widget_ui_test_scheme = Xcodeproj::XCScheme.new
widget_ui_test_scheme.configure_with_targets(app_target, app_widget_ui_tests_target)
widget_ui_test_scheme.save_as(PROJECT_PATH, 'VolumeArcWidgetUITests', true)

# VOL-138: dedicated watchOS unit test scheme. Mirrors the iOS
# `VolumeArcAppTests` scheme but with no host application (the bundle
# links VolumeArcCoreWatch directly). `code_coverage_enabled = true`
# so `scripts/check_coverage.sh` can be pointed at a watch xcresult
# bundle once a coverage gate is added (initially informational; the
# 85% target from VOL-138 acceptance criteria is a follow-on ratchet).
watch_test_scheme = Xcodeproj::XCScheme.new
watch_test_scheme.configure_with_targets(nil, app_watch_tests_target)
watch_test_scheme.test_action.code_coverage_enabled = true
watch_test_scheme.save_as(PROJECT_PATH, 'VolumeArcWatchTests', true)

# VOL-75 P2: per-target schemes so CI can pass `-scheme` (required by
# `-derivedDataPath`). Without these, `build_all_targets.sh` has to use
# `-target`, which incompatible with `-derivedDataPath` — forcing shared
# system DerivedData and the concurrent-build races documented in the
# runner hygiene umbrella.
widget_scheme = Xcodeproj::XCScheme.new
widget_scheme.configure_with_targets(widget_target, nil)
widget_scheme.save_as(PROJECT_PATH, 'VolumeArcWidgets', true)

watch_scheme = Xcodeproj::XCScheme.new
watch_scheme.configure_with_targets(watch_target, nil)
watch_scheme.save_as(PROJECT_PATH, 'VolumeArcWatch', true)

watch_widgets_scheme = Xcodeproj::XCScheme.new
watch_widgets_scheme.configure_with_targets(watch_widgets_target, nil)
watch_widgets_scheme.save_as(PROJECT_PATH, 'VolumeArcWatchWidgets', true)

# VOL-246: Xcode Cloud test plans.
#
# Xcode Cloud test workflows reference a scheme + a test plan. We attach
# two checked-in plans to the VolumeArcApp scheme:
#
#   VOL-PR.xctestplan   — whole VolumeArcAppTests (unit/integration) + a
#                          UI smoke subset + the widget smoke target.
#                          Fast pre-merge gate (~10 min target).
#   VOL-Main.xctestplan — full unit + every UI journey + widget suite.
#                          Runs post-merge as the integration backstop.
#
# These are WRITTEN by the generator (not hand-authored) so each test
# target's `identifier` stays pinned to the deterministic blueprint UUID
# this script assigns. A hand-authored plan would silently point at a
# stale UUID the next time the target graph shifts; writing them here
# guarantees they track. They are still committed + reviewable, and the
# determinism gate (`scripts/test_xcode_project_determinism.sh`) re-runs
# this generator and asserts the committed plans are byte-identical.
#
# Sharding note: this replaces the 4-way shell sharding in
# `scripts/test_apple_targets.sh` for the Xcode Cloud path. Each target
# is `parallelizable: true`, so Xcode Cloud distributes test classes
# across parallel simulator clones on its ephemeral Macs instead of the
# sequential-shard workaround the self-hosted runner needs.
#
# Perf (VolumeArcAppPerfTests) is intentionally excluded — it stays
# tag-gated via its own scheme so measured runs don't inflate test time.
# Watch unit tests (VolumeArcWatchTests, pending VOL-138 / PR #237) are
# NOT here yet: that target needs a watchOS destination, which is a
# separate test-plan entry once it lands on main.
TEST_PLANS_DIR = ROOT.join('TestPlans')
FileUtils.mkdir_p(TEST_PLANS_DIR)

def test_plan_target_ref(uuid, name)
  {
    'containerPath' => 'container:VolumeArcApple.xcodeproj',
    'identifier' => uuid,
    'name' => name,
  }
end

def deterministic_plan_guid(seed)
  hex = Digest::MD5.hexdigest(seed)
  "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}".upcase
end

def write_test_plan(path, configuration_id:, expansion_target:, test_targets:)
  plan = {
    'configurations' => [
      {
        'id' => configuration_id,
        'name' => 'Configuration 1',
        'options' => {},
      },
    ],
    'defaultOptions' => {
      'codeCoverage' => true,
      'targetForVariableExpansion' => expansion_target,
    },
    'testTargets' => test_targets,
    'version' => 1,
  }
  File.write(path, "#{JSON.pretty_generate(plan)}\n")
end

app_expansion_ref = test_plan_target_ref(app_target.uuid, 'VolumeArcApp')
app_tests_ref = test_plan_target_ref(app_tests_target.uuid, 'VolumeArcAppTests')
app_ui_tests_ref = test_plan_target_ref(app_ui_tests_target.uuid, 'VolumeArcAppUITests')
app_widget_ui_tests_ref = test_plan_target_ref(app_widget_ui_tests_target.uuid, 'VolumeArcWidgetUITests')

# VOL-PR smoke subset mirrors the `smoke` shard from the self-hosted
# `UI_SHARDS` map: the launch/navigation smoke class + the telemetry
# probe-matcher unit-style UI tests. Whole-class identifiers (no method
# suffix) keep the allowlist coarse and stable. VolumeArcWidgetUITests
# stays out of VOL-PR until its Xcode Cloud ephemeral-simulator launch
# crash is fixed; VOL-Main keeps the target as the slower backstop.
write_test_plan(
  TEST_PLANS_DIR.join('VOL-PR.xctestplan'),
  configuration_id: deterministic_plan_guid('VolumeArc/TestPlan/VOL-PR/Configuration1'),
  expansion_target: app_expansion_ref,
  test_targets: [
    { 'parallelizable' => true, 'target' => app_tests_ref },
    {
      'parallelizable' => true,
      'selectedTests' => %w[VolumeArcAppUITests VolumeArcTelemetryProbeMatcherTests],
      'target' => app_ui_tests_ref,
    },
  ],
)

write_test_plan(
  TEST_PLANS_DIR.join('VOL-Main.xctestplan'),
  configuration_id: deterministic_plan_guid('VolumeArc/TestPlan/VOL-Main/Configuration1'),
  expansion_target: app_expansion_ref,
  test_targets: [
    { 'parallelizable' => true, 'target' => app_tests_ref },
    { 'parallelizable' => true, 'target' => app_ui_tests_ref },
    { 'parallelizable' => true, 'target' => app_widget_ui_tests_ref },
  ],
)

# Attach both plans to the VolumeArcApp scheme's Test action. xcodeproj
# (this gem version) doesn't expose <TestPlans> on XCScheme, so patch the
# saved scheme XML deterministically — same approach as the StoreKit
# reference patch on the UI-test scheme above. VOL-PR is the default; the
# self-hosted `test_apple_targets.sh` keeps using the per-target
# VolumeArcAppTests / VolumeArcAppUITests schemes, so the two CI paths
# coexist during shadow.
app_scheme_path = PROJECT_PATH.join('xcshareddata/xcschemes/VolumeArcApp.xcscheme')
app_scheme_xml = File.read(app_scheme_path)
# Built line-by-line with explicit indentation (a squiggly heredoc would
# strip the leading whitespace and flatten the block against the margin).
test_plans_block = [
  '      <TestPlans>',
  '         <TestPlanReference',
  '            reference = "container:TestPlans/VOL-PR.xctestplan"',
  '            default = "YES">',
  '         </TestPlanReference>',
  '         <TestPlanReference',
  '            reference = "container:TestPlans/VOL-Main.xctestplan">',
  '         </TestPlanReference>',
  '      </TestPlans>',
].join("\n")
unless app_scheme_xml.include?('<TestPlans>')
  inserted = app_scheme_xml.sub!(/(<TestAction\b[^>]*>\n)/m) { "#{Regexp.last_match(1)}#{test_plans_block}\n" }
  unless inserted
    raise "Failed to insert <TestPlans> into #{app_scheme_path}; " \
          'VolumeArcApp TestAction XML format may have changed.'
  end
  File.write(app_scheme_path, app_scheme_xml)
end

# VOL-90: seed the workspace-level `Package.resolved` from the tracked
# root-level copy so SPM resolution is deterministic across machines.
# The `.xcworkspace/` dir is gitignored (rebuilt by xcodebuild on every
# resolve), so only the root copy survives in git. Seeding it here on a
# fresh clone means `xcodebuild -resolvePackageDependencies` reuses the
# pinned versions rather than re-resolving against the upstream indexes.
#
# CI also seeds via `.github/workflows/ci.yml` in case the generator
# ran before this was added. Validation lives in
# `scripts/validate_release_config.sh` (fails if the two copies drift).
ROOT_LOCKFILE = ROOT.join('Package.resolved')
WORKSPACE_LOCKFILE_DIR = PROJECT_PATH.join('project.xcworkspace/xcshareddata/swiftpm')
WORKSPACE_LOCKFILE = WORKSPACE_LOCKFILE_DIR.join('Package.resolved')
if ROOT_LOCKFILE.exist?
  FileUtils.mkdir_p(WORKSPACE_LOCKFILE_DIR)
  FileUtils.cp(ROOT_LOCKFILE, WORKSPACE_LOCKFILE)
  puts "Seeded #{WORKSPACE_LOCKFILE.relative_path_from(ROOT)} from root Package.resolved"
end

puts "Generated #{PROJECT_PATH}"
