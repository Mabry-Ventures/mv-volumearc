#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'fileutils'
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
# 2. `predictabilize_uuids` computes object-graph paths using
#    `remote_global_id_string` fields, which reference other objects by
#    UUID. On the first pass those references are still the original
#    random UUIDs, so the computed paths (and therefore the new UUIDs)
#    still carry randomness. A second pass re-normalizes with the now
#    deterministic references, converging to a fixed point. We hardcode
#    two passes rather than looping because the first-pass/second-pass
#    invariant is easy to reason about and the cost is negligible.
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
WATCHOS_DEPLOYMENT_TARGET = '26.4'
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
shared_group = project.main_group.new_group('Shared Native Package Sources')
core_group = shared_group.new_group('VolumeArcCore', PACKAGE_ROOT.join('Sources/VolumeArcCore').relative_path_from(ROOT).to_s)
ui_group = shared_group.new_group('VolumeArcUI', PACKAGE_ROOT.join('Sources/VolumeArcUI').relative_path_from(ROOT).to_s)

core_target = project.new_target(:static_library, 'VolumeArcCore', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcCore')
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

def configure_target(target, bundle_id: nil, extra: {})
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.3'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['MARKETING_VERSION'] = MARKETING_VERSION
    config.build_settings['CURRENT_PROJECT_VERSION'] = BUILD_NUMBER
    config.build_settings['DEVELOPMENT_TEAM'] = ENV.fetch('DEVELOPMENT_TEAM', '')
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    config.build_settings['DISABLE_MANUAL_TARGET_ORDER_BUILD_WARNING'] = 'YES'
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = bundle_id if bundle_id
    extra.each do |key, value|
      config.build_settings[key] = value
    end
  end
end

configure_target(core_target, extra: {
  'DEFINES_MODULE' => 'YES',
  'SKIP_INSTALL' => 'YES',
})
configure_target(ui_target, extra: {
  'DEFINES_MODULE' => 'YES',
  'SKIP_INSTALL' => 'YES',
})
configure_target(app_target, bundle_id: 'com.mabryventures.VolumeArc', extra: {
  'PRODUCT_NAME' => 'VolumeArc',
  'TARGETED_DEVICE_FAMILY' => '1,2',
  'INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents' => 'YES',
  'INFOPLIST_KEY_NSHealthShareUsageDescription' => 'VolumeArc reads your completed workouts from Apple Health to show your training history and calculate readiness.',
  'INFOPLIST_KEY_NSHealthUpdateUsageDescription' => 'VolumeArc writes completed workouts so your training history stays in sync with Apple Health.',
  'INFOPLIST_KEY_NSMicrophoneUsageDescription' => 'VolumeArc uses the microphone for voice coaching requests and voice workout logging.',
  'INFOPLIST_KEY_NSSpeechRecognitionUsageDescription' => 'VolumeArc uses speech recognition to understand live coaching requests and voice workout notes.',
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
  'INFOPLIST_KEY_WKApplication' => 'YES',
  'INFOPLIST_KEY_WKCompanionAppBundleIdentifier' => 'com.mabryventures.VolumeArc',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait',
  'INFOPLIST_KEY_NSHealthShareUsageDescription' => 'VolumeArc reads workouts, heart rate, and active energy on Apple Watch so live strength sessions save with accurate training history, heart-rate charts, and calorie totals.',
  'INFOPLIST_KEY_NSHealthUpdateUsageDescription' => 'VolumeArc writes completed watch workouts to Apple Health.',
  'CODE_SIGN_ENTITLEMENTS' => 'Watch/VolumeArcWatch.entitlements',
})
configure_target(widget_target, bundle_id: 'com.mabryventures.VolumeArc.widgets', extra: {
  'PRODUCT_NAME' => 'VolumeArcWidgets',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'SKIP_INSTALL' => 'YES',
  'CODE_SIGN_ENTITLEMENTS' => 'Widgets/VolumeArcWidgets.entitlements',
  'INFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier' => 'com.apple.widgetkit-extension',
  'INFOPLIST_KEY_NSExtension_NSExtensionPrincipalClass' => '$(PRODUCT_MODULE_NAME).VolumeArcWidgets',
})
configure_target(watch_widgets_target, bundle_id: 'com.mabryventures.VolumeArc.watchkitapp.widgets', extra: {
  'PRODUCT_NAME' => 'VolumeArcWatchWidgets',
  'TARGETED_DEVICE_FAMILY' => '4',
  'APPLICATION_EXTENSION_API_ONLY' => 'YES',
  'SKIP_INSTALL' => 'YES',
  'CODE_SIGN_ENTITLEMENTS' => 'WatchWidgets/VolumeArcWatchWidgets.entitlements',
  'INFOPLIST_KEY_NSExtension_NSExtensionPointIdentifier' => 'com.apple.widgetkit-extension',
})
configure_target(app_tests_target, bundle_id: 'com.mabryventures.VolumeArc.tests', extra: {
  'PRODUCT_NAME' => 'VolumeArcAppTests',
  'GENERATE_INFOPLIST_FILE' => 'YES',
  'CODE_SIGNING_ALLOWED' => 'NO',
  'CODE_SIGNING_REQUIRED' => 'NO',
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

ui_target.add_dependency(core_target)
ui_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
app_target.add_dependency(core_target)
app_target.add_dependency(ui_target)
app_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
app_target.frameworks_build_phase.add_file_reference(ui_target.product_reference, true)
watch_target.add_dependency(core_target)
watch_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
watch_widgets_target.add_dependency(core_target)
watch_widgets_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
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
app_ui_tests_target.add_system_framework('XCTest')
app_ui_tests_target.add_system_framework('StoreKitTest')
app_perf_tests_target.add_system_framework('XCTest')

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
add_swift_sources(ui_group, ui_target, PACKAGE_ROOT.join('Sources/VolumeArcUI'))
add_swift_sources(app_group, app_target, ROOT.join('App'))
add_swift_sources(watch_group, watch_target, ROOT.join('Watch'))
add_swift_sources(watch_widgets_group, watch_widgets_target, ROOT.join('WatchWidgets'))
add_swift_sources(widgets_group, widget_target, ROOT.join('Widgets'))
add_swift_sources(tests_group, app_tests_target, ROOT.join('Tests/VolumeArcAppTests'))
add_swift_sources(ui_tests_group, app_ui_tests_target, ROOT.join('Tests/VolumeArcAppUITests'))
add_swift_sources(perf_tests_group, app_perf_tests_target, ROOT.join('Tests/VolumeArcAppPerfTests'))
add_resource(ui_tests_group, app_ui_tests_target, 'VolumeArcTests.storekit')
add_resource(app_group, app_target, 'PrivacyInfo.xcprivacy')
add_resource(watch_group, watch_target, 'PrivacyInfo.xcprivacy')
add_resource(watch_widgets_group, watch_widgets_target, 'PrivacyInfo.xcprivacy')
add_resource(widgets_group, widget_target, 'PrivacyInfo.xcprivacy')

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

add_selected_swift_sources(app_group, app_tests_target, ROOT.join('App'), [
  'Intents/VolumeArcIntents.swift',
  'VolumeArcAIConfiguration.swift',
  # VOL-91: included in the test target so
  # `VolumeArcPremiumGatingTests` can exercise the premium-entitlement
  # gating directly without spinning up `VolumeArcApp`. The factory
  # closes over `VolumeArcAIConfiguration.relayConfiguration` which is
  # also in this list.
  'VolumeArcAIRuntimeFactory.swift',
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
  'VolumeArcWidgetController.swift',
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
sentry_requirement = { 'kind' => 'exactVersion', 'version' => '8.58.1' }
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

project.root_object.attributes['TargetAttributes'] ||= {}
project.targets.each do |target|
  project.root_object.attributes['TargetAttributes'][target.uuid] = {
    'CreatedOnToolsVersion' => '26.4',
  }
end

# VOL-95: two passes are required. Pass 1 rewrites most UUIDs from
# graph-path MD5 hashes, but objects that reference other objects by
# UUID string (e.g. `PBXContainerItemProxy.remote_global_id_string`)
# still carry the old random references in their tree-hash paths. Pass
# 2 runs against the now-deterministic references and converges. Must
# run before `project.save` and before scheme generation so schemes
# pick up the final, deterministic target UUIDs as BlueprintIdentifier.
project.predictabilize_uuids
project.predictabilize_uuids

project.save
app_scheme = Xcodeproj::XCScheme.new
app_scheme.configure_with_targets(app_target, nil, launch_target: true)
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
  inserted = ui_scheme_xml.sub!(
    "      allowLocationSimulation = \"YES\">\n   </LaunchAction>",
    "      allowLocationSimulation = \"YES\">\n#{app_runnable}\n#{storekit_reference}\n   </LaunchAction>"
  )
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
