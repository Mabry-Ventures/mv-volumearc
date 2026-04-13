#!/usr/bin/env ruby
# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require 'xcodeproj'

ROOT = Pathname.new(__dir__).join('..').expand_path
PACKAGE_ROOT = ROOT.join('../VolumeArcNative').expand_path
PROJECT_PATH = ROOT.join('VolumeArcApple.xcodeproj')
IOS_DEPLOYMENT_TARGET = '26.0'
WATCHOS_DEPLOYMENT_TARGET = '26.4'

FileUtils.rm_rf(PROJECT_PATH)
project = Xcodeproj::Project.new(PROJECT_PATH)

app_group = project.main_group.new_group('App', 'App')
watch_group = project.main_group.new_group('Watch', 'Watch')
widgets_group = project.main_group.new_group('Widgets', 'Widgets')
tests_group = project.main_group.new_group('Tests', 'Tests')
shared_group = project.main_group.new_group('Shared Native Package Sources')
core_group = shared_group.new_group('VolumeArcCore', PACKAGE_ROOT.join('Sources/VolumeArcCore').relative_path_from(ROOT).to_s)
ui_group = shared_group.new_group('VolumeArcUI', PACKAGE_ROOT.join('Sources/VolumeArcUI').relative_path_from(ROOT).to_s)

core_target = project.new_target(:static_library, 'VolumeArcCore', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcCore')
ui_target = project.new_target(:static_library, 'VolumeArcUI', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcUI')
app_target = project.new_target(:application, 'VolumeArcApp', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArc')
watch_target = project.new_target(:application, 'VolumeArcWatch', :watchos, WATCHOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcWatch')
widget_target = project.new_target(:app_extension, 'VolumeArcWidgets', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcWidgets')
app_tests_target = project.new_target(:unit_test_bundle, 'VolumeArcAppTests', :ios, IOS_DEPLOYMENT_TARGET, nil, :swift, 'VolumeArcAppTests')

def configure_target(target, bundle_id: nil, extra: {})
  target.build_configurations.each do |config|
    config.build_settings['SWIFT_VERSION'] = '6.0'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
    config.build_settings['DEVELOPMENT_TEAM'] = ''
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
  'INFOPLIST_KEY_CFBundleURLTypes' => '[{"CFBundleURLName":"com.mabryventures.VolumeArc","CFBundleURLSchemes":["volumearc"]}]',
  'INFOPLIST_KEY_NSHealthShareUsageDescription' => 'VolumeArc reads your workout and recovery data to personalize progression, readiness, and session planning.',
  'INFOPLIST_KEY_NSHealthUpdateUsageDescription' => 'VolumeArc writes completed workouts so your training history stays in sync with Apple Health.',
  'INFOPLIST_KEY_NSMicrophoneUsageDescription' => 'VolumeArc uses the microphone for live duplex coaching and voice workout logging.',
  'INFOPLIST_KEY_NSSpeechRecognitionUsageDescription' => 'VolumeArc uses speech recognition to understand live coaching requests and voice workout notes.',
  'INFOPLIST_KEY_VolumeArcCloudKitContainer' => 'iCloud.com.mabryventures.VolumeArc',
  'INFOPLIST_KEY_VolumeArcOpenAIBaseURL' => '',
  'CODE_SIGN_ENTITLEMENTS' => 'App/VolumeArc.entitlements',
})
configure_target(watch_target, bundle_id: 'com.mabryventures.VolumeArc.watchkitapp', extra: {
  'TARGETED_DEVICE_FAMILY' => '4',
  'PRODUCT_NAME' => 'VolumeArcWatch',
  'INFOPLIST_KEY_WKApplication' => 'YES',
  'INFOPLIST_KEY_WKCompanionAppBundleIdentifier' => 'com.mabryventures.VolumeArc',
  'INFOPLIST_KEY_UISupportedInterfaceOrientations' => 'UIInterfaceOrientationPortrait',
  'INFOPLIST_KEY_NSHealthShareUsageDescription' => 'VolumeArc uses HealthKit on Apple Watch to run live workout sessions and keep your training history accurate.',
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
configure_target(app_tests_target, bundle_id: 'com.mabryventures.VolumeArc.tests', extra: {
  'PRODUCT_NAME' => 'VolumeArcAppTests',
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
watch_target.add_dependency(core_target)
watch_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
widget_target.add_dependency(core_target)
widget_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
app_tests_target.add_dependency(core_target)
app_tests_target.add_dependency(ui_target)
app_tests_target.frameworks_build_phase.add_file_reference(core_target.product_reference, true)
app_tests_target.frameworks_build_phase.add_file_reference(ui_target.product_reference, true)

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
app_tests_target.add_system_framework('XCTest')
app_tests_target.add_system_framework('AuthenticationServices')
app_tests_target.add_system_framework('Security')
app_tests_target.add_system_framework('AppIntents')
app_tests_target.add_system_framework('ActivityKit')

def add_swift_sources(group, target, base_dir)
  refs = Dir[base_dir.join('**/*.swift').to_s].sort.map do |file|
    relative_to_group = Pathname.new(file).relative_path_from(base_dir).to_s
    group.find_file_by_path(relative_to_group) || group.new_file(relative_to_group)
  end
  target.add_file_references(refs)
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
add_swift_sources(widgets_group, widget_target, ROOT.join('Widgets'))
add_swift_sources(tests_group, app_tests_target, ROOT.join('Tests'))
add_selected_swift_sources(app_group, app_tests_target, ROOT.join('App'), [
  'Intents/VolumeArcIntents.swift',
  'VolumeArcCloudConfiguration.swift',
  'VolumeArcLiveActivityController.swift',
  'VolumeArcPremiumCatalog.swift',
  'VolumeArcSecureStore.swift',
  'VolumeArcWidgetController.swift',
])

project.root_object.attributes['TargetAttributes'] ||= {}
project.targets.each do |target|
  project.root_object.attributes['TargetAttributes'][target.uuid] = {
    'CreatedOnToolsVersion' => '26.4',
  }
end

project.save
app_scheme = Xcodeproj::XCScheme.new
app_scheme.configure_with_targets(app_target, nil, launch_target: true)
app_scheme.save_as(PROJECT_PATH, 'VolumeArcApp', true)

test_scheme = Xcodeproj::XCScheme.new
test_scheme.configure_with_targets(nil, app_tests_target)
test_scheme.save_as(PROJECT_PATH, 'VolumeArcAppTests', true)
puts "Generated #{PROJECT_PATH}"
