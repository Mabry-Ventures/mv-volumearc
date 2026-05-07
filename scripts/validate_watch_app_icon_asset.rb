#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'

root = File.expand_path('..', __dir__)
icon_dir = ARGV.fetch(0, File.join(root, 'Watch/Assets.xcassets/AppIcon.appiconset'))
contents_path = File.join(icon_dir, 'Contents.json')

def abort_with(message)
  abort("FAIL: #{message}")
end

def png_info(path)
  data = File.binread(path, 26)
  abort_with("#{path} is not a PNG") unless data.start_with?("\x89PNG\r\n\x1A\n".b)

  width, height = data.byteslice(16, 8).unpack('N2')
  color_type = data.byteslice(25, 1).unpack1('C')
  { width: width, height: height, has_alpha: [4, 6].include?(color_type) }
end

def points_to_pixels(size, scale)
  width_points, height_points = size.split('x').map { |value| Rational(value) }
  scale_factor = Integer(scale.delete_suffix('x'))
  [(width_points * scale_factor).to_i, (height_points * scale_factor).to_i]
end

required_icons = [
  { filename: 'AppIcon.png', idiom: 'watch-marketing', size: '1024x1024', scale: '1x' },
  { filename: 'AppIcon-24x24@2x.png', idiom: 'watch', role: 'notificationCenter', subtype: '38mm', size: '24x24', scale: '2x' },
  { filename: 'AppIcon-27.5x27.5@2x.png', idiom: 'watch', role: 'notificationCenter', subtype: '42mm', size: '27.5x27.5', scale: '2x' },
  { filename: 'AppIcon-29x29@2x.png', idiom: 'watch', role: 'companionSettings', size: '29x29', scale: '2x' },
  { filename: 'AppIcon-29x29@3x.png', idiom: 'watch', role: 'companionSettings', size: '29x29', scale: '3x' },
  { filename: 'AppIcon-40x40@2x.png', idiom: 'watch', role: 'appLauncher', subtype: '38mm', size: '40x40', scale: '2x' },
  { filename: 'AppIcon-44x44@2x.png', idiom: 'watch', role: 'appLauncher', subtype: '40mm', size: '44x44', scale: '2x' },
  { filename: 'AppIcon-50x50@2x.png', idiom: 'watch', role: 'appLauncher', subtype: '44mm', size: '50x50', scale: '2x' },
  { filename: 'AppIcon-86x86@2x.png', idiom: 'watch', role: 'quickLook', subtype: '38mm', size: '86x86', scale: '2x' },
  { filename: 'AppIcon-98x98@2x.png', idiom: 'watch', role: 'quickLook', subtype: '42mm', size: '98x98', scale: '2x' },
  { filename: 'AppIcon-108x108@2x.png', idiom: 'watch', role: 'quickLook', subtype: '44mm', size: '108x108', scale: '2x' }
].freeze

abort_with("Missing watch AppIcon Contents.json at #{contents_path}") unless File.file?(contents_path)

contents = JSON.parse(File.read(contents_path))
images = contents.fetch('images') { abort_with("#{contents_path} is missing images") }
abort_with("#{contents_path} images must be an array") unless images.is_a?(Array)

images.each do |image|
  next if %w[watch watch-marketing].include?(image['idiom'])

  abort_with("Watch AppIcon entry #{image.inspect} must use idiom=watch or idiom=watch-marketing")
end

required_icons.each do |expected|
  entry = images.find do |candidate|
    expected.all? { |key, value| candidate[key.to_s] == value }
  end
  abort_with("Watch AppIcon missing #{expected}") if entry.nil?

  path = File.join(icon_dir, expected.fetch(:filename))
  abort_with("Watch AppIcon references missing file #{path}") unless File.file?(path)

  expected_width, expected_height = points_to_pixels(expected.fetch(:size), expected.fetch(:scale))
  info = png_info(path)
  if info[:width] != expected_width || info[:height] != expected_height
    abort_with("#{path} must be #{expected_width}x#{expected_height}px, got #{info[:width]}x#{info[:height]}px")
  end
  abort_with("#{path} must not contain an alpha channel") if info[:has_alpha]
end

puts 'Watch AppIcon asset catalog includes explicit watchOS roles, sizes, PNG dimensions, and marketing icon.'
