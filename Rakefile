# frozen_string_literal: true

require "bundler/gem_tasks"
task default: [:test]

task :test do
  exec RbConfig.ruby, "-Ilib", "test/run_tests.rb"
end
