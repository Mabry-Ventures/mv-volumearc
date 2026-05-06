#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'
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
assert(watch_target.dependencies.any? { |dependency| dependency.target&.name == 'VolumeArcCoreWatch' },
       'VolumeArcWatch must depend on the watchOS core target')
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
assert(watch_archive_entry.attributes['buildForArchiving'] == 'YES',
       'VolumeArcWatch must be enabled for app archives')
assert(watch_archive_entry.attributes['buildForTesting'] == 'NO' &&
       watch_archive_entry.attributes['buildForRunning'] == 'NO' &&
       watch_archive_entry.attributes['buildForProfiling'] == 'NO' &&
       watch_archive_entry.attributes['buildForAnalyzing'] == 'NO',
       'VolumeArcWatch must stay out of non-archive app scheme actions')

watch_content_phase = copy_phase!(app_target, 'Embed Watch Content')
assert(watch_content_phase.symbol_dst_subfolder_spec == :products_directory,
       'Embed Watch Content must copy from the built products directory')
assert(watch_content_phase.dst_path == '$(CONTENTS_FOLDER_PATH)/Watch',
       'Embed Watch Content must copy into the iOS app Watch folder')
assert(watch_content_phase.run_only_for_deployment_postprocessing == '1',
       'Embed Watch Content must not run for ordinary simulator builds')
watch_content_file = phase_file!(watch_content_phase, 'VolumeArcWatch.app')
assert(watch_content_file.platform_filter == 'iphoneos',
       'Embed Watch Content must only run for device/archive builds')
assert_remove_headers(watch_content_file)

watch_extensions_phase = copy_phase!(watch_target, 'Embed Watch Extensions')
assert(watch_extensions_phase.symbol_dst_subfolder_spec == :plug_ins,
       'Embed Watch Extensions must copy watch extensions into PlugIns')
assert_remove_headers(phase_file!(watch_extensions_phase, 'VolumeArcWatchWidgets.appex'))

puts 'Watch app embedding is wired correctly.'
