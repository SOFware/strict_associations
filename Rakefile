# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

task default: %i[spec standard]

require "reissue/gem"

Reissue::Task.create :reissue do |task|
  task.version_file = "lib/strict_associations/version.rb"
  task.fragment = :git
end
