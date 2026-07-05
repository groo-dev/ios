#!/usr/bin/env ruby
# Adds GrooTests (unit) + GrooUITests (UI) targets with synchronized folders,
# and registers both as testables in the shared Groo scheme.
# Idempotent: aborts if GrooTests already exists.
require 'xcodeproj'

project_path = File.expand_path('../Groo.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

app_target = project.targets.find { |t| t.name == 'Groo' }
abort 'ERROR: Groo target not found' unless app_target
abort 'GrooTests target already exists — nothing to do' if project.targets.any? { |t| t.name == 'GrooTests' }

deployment = app_target.build_configurations.first
                       .resolve_build_setting('IPHONEOS_DEPLOYMENT_TARGET') || '26.2'

unit_target = project.new_target(:unit_test_bundle, 'GrooTests', :ios, deployment)
unit_target.add_dependency(app_target)
unit_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.groo.ios.tests'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/Groo.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Groo'
  config.build_settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
end

ui_target = project.new_target(:ui_test_bundle, 'GrooUITests', :ios, deployment)
ui_target.add_dependency(app_target)
ui_target.build_configurations.each do |config|
  config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'dev.groo.ios.uitests'
  config.build_settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  config.build_settings['TEST_TARGET_NAME'] = 'Groo'
  config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  config.build_settings['SWIFT_VERSION'] = '5.0'
  config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
end

# Synchronized folders (objectVersion 77): files on disk under these paths
# are automatically part of the target — no per-file registration.
{ 'GrooTests' => unit_target, 'GrooUITests' => ui_target }.each do |folder, target|
  sync_group = project.new(Xcodeproj::Project::Object::PBXFileSystemSynchronizedRootGroup)
  sync_group.path = folder
  sync_group.source_tree = '<group>'
  project.main_group << sync_group
  target.file_system_synchronized_groups << sync_group
end

project.save

scheme_path = Xcodeproj::XCScheme.shared_data_dir(project_path) + 'Groo.xcscheme'
scheme = Xcodeproj::XCScheme.new(scheme_path)
scheme.add_test_target(unit_target)
scheme.add_test_target(ui_target)
scheme.save!

puts 'OK: added GrooTests + GrooUITests and registered them in the Groo scheme'
