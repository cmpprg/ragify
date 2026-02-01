# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "rubocop/rake_task"

RuboCop::RakeTask.new

# Disable rdoc/ri generation during gem install
Rake::Task[:install].clear
task :install do
  sh "mkdir -p pkg"
  sh "gem build ragify.gemspec"
  sh "mv ragify-*.gem pkg/"
  sh "gem install pkg/ragify-*.gem --no-document --local"
end

task default: %i[spec rubocop]
