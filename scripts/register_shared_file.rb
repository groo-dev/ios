#!/usr/bin/env ruby
# Registers an existing Shared/<file> in the classic (non-synchronized) Shared
# group and adds it to the given targets' Sources phases. Shared/ is NOT a
# filesystem-synchronized group — without this, a new Shared file compiles
# into nothing. Idempotent.
# usage: ruby scripts/register_shared_file.rb <FileName.swift> <Target> [<Target>...]
require 'xcodeproj'

file_name = ARGV.shift
abort 'usage: register_shared_file.rb <FileName.swift> <Target>...' if file_name.nil? || ARGV.empty?
target_names = ARGV

abort "ERROR: Shared/#{file_name} does not exist on disk" \
  unless File.exist?(File.expand_path("../Shared/#{file_name}", __dir__))

project_path = File.expand_path('../Groo.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

shared_group = project.main_group['Shared']
abort 'ERROR: Shared group not found' unless shared_group

file_ref = shared_group.files.find { |f| f.path == file_name } || shared_group.new_reference(file_name)

target_names.each do |name|
  target = project.targets.find { |t| t.name == name }
  abort "ERROR: target #{name} not found" unless target
  if target.source_build_phase.files_references.include?(file_ref)
    puts "#{name}: already registered"
  else
    target.source_build_phase.add_file_reference(file_ref)
    puts "#{name}: added"
  end
end

project.save
puts "OK: Shared/#{file_name} registered"
