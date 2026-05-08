#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'
require 'cfpropertylist'
require 'rexml/document'

root = File.expand_path('..', __dir__)
project = Xcodeproj::Project.open(File.join(root, 'VolumeArcApple.xcodeproj'))

def target!(project, name)
  project.targets.find { |target| target.name == name } || abort("FAIL: Missing target #{name}")
end

def copy_phase!(target, name)
  target.copy_files_build_phases.find { |phase| phase.name == name } ||
    abort("FAIL: #{target.name} missing copy-files phase #{name.inspect}")
end

def assert(condition, message)
  abort("FAIL: #{message}") unless condition
end

def phase_file!(phase, product_path)
  phase.files.find { |file| file.file_ref&.path == product_path } ||
    abort("FAIL: #{phase.name} does not copy #{product_path}")
end

def assert_remove_headers(build_file)
  attributes = build_file.settings&.fetch('ATTRIBUTES', [])
  assert(attributes.include?('RemoveHeadersOnCopy'),
         "#{build_file.display_name} must remove headers on copy")
end

def array_build_setting(value)
  Array(value).flat_map { |entry| entry.to_s.split(/\s+/) }
end

def resource_phase_file?(target, product_path)
  target.resources_build_phase.files.any? { |file| file.file_ref&.path == product_path }
end

def plist!(path)
  CFPropertyList.native_types(CFPropertyList::List.new(file: path).value)
rescue StandardError => e
  abort("FAIL: Could not read plist #{path}: #{e.message}")
end

app_target = target!(project, 'VolumeArcApp')
core_watch_target = target!(project, 'VolumeArcCoreWatch')
watch_target = target!(project, 'VolumeArcWatch')
watch_widgets_target = target!(project, 'VolumeArcWatchWidgets')

assert(core_watch_target.build_configurations.all? { |config| config.build_settings['SDKROOT'] == 'watchos' },
       'VolumeArcCoreWatch must build VolumeArcCore sources for watchOS')
assert(core_watch_target.build_configurations.all? { |config| config.build_settings['PRODUCT_MODULE_NAME'] == 'VolumeArcCore' },
       'VolumeArcCoreWatch must preserve the VolumeArcCore module name')
assert(watch_widgets_target.product_type == 'com.apple.product-type.watchkit2-extension',
       'VolumeArcWatchWidgets must use the watch extension product type')
assert(watch_widgets_target.build_configurations.all? { |config| config.build_settings['INFOPLIST_FILE'] == 'WatchWidgets/Info.plist' },
       'VolumeArcWatchWidgets must use the explicit WidgetKit Info.plist')
assert(watch_widgets_target.build_configurations.all? { |config|
  array_build_setting(config.build_settings['OTHER_LDFLAGS']).include?('_NSExtensionMain')
}, 'VolumeArcWatchWidgets must link with _NSExtensionMain as the extension entry point')
assert(watch_target.build_configurations.all? { |config| config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] == 'AppIcon' },
       'VolumeArcWatch must compile the AppIcon asset catalog')
assert(watch_target.build_configurations.all? { |config| config.build_settings['INFOPLIST_FILE'] == 'Watch/Info.plist' },
       'VolumeArcWatch must use the explicit watch Info.plist')
assert(resource_phase_file?(watch_target, 'Assets.xcassets'),
       'VolumeArcWatch must include its watchOS asset catalog')
assert(watch_target.dependencies.any? { |dependency| dependency.target&.name == 'VolumeArcCoreWatch' },
       'VolumeArcWatch must depend on the watchOS core target')
assert(watch_target.dependencies.any? { |dependency| dependency.target&.name == 'VolumeArcWatchWidgets' },
       'VolumeArcWatch must depend on its widget extension before embedding the appex')
assert(watch_widgets_target.dependencies.any? { |dependency| dependency.target&.name == 'VolumeArcCoreWatch' },
       'VolumeArcWatchWidgets must depend on the watchOS core target')

scheme_path = File.join(root, 'VolumeArcApple.xcodeproj/xcshareddata/xcschemes/VolumeArcApp.xcscheme')
scheme = REXML::Document.new(File.read(scheme_path))
watch_archive_entries = []
REXML::XPath.each(scheme, '//BuildActionEntry') do |entry|
  reference = REXML::XPath.first(entry, 'BuildableReference')
  next unless reference&.attributes&.[]('BlueprintName') == 'VolumeArcWatch'

  watch_archive_entries << entry
end
assert(watch_archive_entries.length == 1,
       'VolumeArcApp scheme must include VolumeArcWatch exactly once')
watch_archive_entry = watch_archive_entries.first
%w[
  buildForTesting
  buildForRunning
  buildForProfiling
  buildForArchiving
  buildForAnalyzing
].each do |attribute|
  assert(watch_archive_entry.attributes[attribute] == 'YES',
         "VolumeArcWatch must be enabled for app scheme #{attribute}")
end

watch_content_phase = copy_phase!(app_target, 'Embed Watch Content')
assert(watch_content_phase.symbol_dst_subfolder_spec == :products_directory,
       'Embed Watch Content must copy from the built products directory')
assert(watch_content_phase.dst_path == '$(CONTENTS_FOLDER_PATH)/Watch',
       'Embed Watch Content must copy into the iOS app Watch folder')
assert(watch_content_phase.run_only_for_deployment_postprocessing == '0',
       'Embed Watch Content must match Xcode-generated watch app embedding phases')
watch_content_file = phase_file!(watch_content_phase, 'VolumeArcWatch.app')
assert(watch_content_file.platform_filter == 'iphoneos',
       'Embed Watch Content must only run for device/archive builds')
assert_remove_headers(watch_content_file)

watch_extensions_phase = copy_phase!(watch_target, 'Embed Watch Extensions')
assert(watch_extensions_phase.symbol_dst_subfolder_spec == :plug_ins,
       'Embed Watch Extensions must copy watch extensions into PlugIns')
assert_remove_headers(phase_file!(watch_extensions_phase, 'VolumeArcWatchWidgets.appex'))

watch_widget_plist = plist!(File.join(root, 'WatchWidgets/Info.plist'))
assert(watch_widget_plist['CFBundleDisplayName'] == 'VolumeArc',
       'WatchWidgets/Info.plist must declare CFBundleDisplayName for App Store Connect')
assert(watch_widget_plist.dig('NSExtension', 'NSExtensionPointIdentifier') == 'com.apple.widgetkit-extension',
       'WatchWidgets/Info.plist must declare the WidgetKit extension point')

watch_plist = plist!(File.join(root, 'Watch/Info.plist'))
assert(watch_plist.dig('CFBundleIcons', 'CFBundlePrimaryIcon', 'CFBundleIconName') == 'AppIcon',
       'Watch/Info.plist must declare CFBundleIconName=AppIcon')
assert(watch_plist.dig('CFBundleIcons', 'CFBundlePrimaryIcon', 'CFBundleIconFiles')&.include?('AppIcon'),
       'Watch/Info.plist must declare CFBundleIconFiles for App Store Connect')

puts 'Watch app embedding is wired correctly.'
