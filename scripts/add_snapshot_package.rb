#!/usr/bin/env ruby
# Adds pointfree swift-snapshot-testing as a remote SPM package and wires the
# SnapshotTesting product into the GrooTests target ONLY (packageReferences on
# the project + XCSwiftPackageProductDependency + Frameworks-phase build file,
# mirroring how web3swift/Adhan/GrooAuth are wired). Idempotent.
require 'xcodeproj'

project_path = File.expand_path('../Groo.xcodeproj', __dir__)
project = Xcodeproj::Project.open(project_path)

test_target = project.targets.find { |t| t.name == 'GrooTests' }
abort 'ERROR: GrooTests target not found' unless test_target

if test_target.package_product_dependencies.any? { |d| d.product_name == 'SnapshotTesting' }
  abort 'SnapshotTesting already wired into GrooTests — nothing to do'
end

pkg = project.root_object.package_references.find do |ref|
  ref.respond_to?(:repositoryURL) && ref.repositoryURL.to_s.include?('swift-snapshot-testing')
end
unless pkg
  pkg = project.new(Xcodeproj::Project::Object::XCRemoteSwiftPackageReference)
  pkg.repositoryURL = 'https://github.com/pointfreeco/swift-snapshot-testing'
  pkg.requirement = { 'kind' => 'upToNextMajorVersion', 'minimumVersion' => '1.17.0' }
  project.root_object.package_references << pkg
end

dep = project.new(Xcodeproj::Project::Object::XCSwiftPackageProductDependency)
dep.package = pkg
dep.product_name = 'SnapshotTesting'
test_target.package_product_dependencies << dep

build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
build_file.product_ref = dep
test_target.frameworks_build_phase.files << build_file

project.save
puts 'OK: SnapshotTesting (swift-snapshot-testing >= 1.17.0) wired into GrooTests'
