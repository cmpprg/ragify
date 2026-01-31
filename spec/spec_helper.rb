# frozen_string_literal: true

require "ragify"
require "tmpdir"
require "fileutils"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Exclude integration and ollama_required tests by default
  # Run with: rspec --tag integration
  # Run with: rspec --tag ollama_required
  # Run all:  rspec --tag integration --tag ollama_required
  config.filter_run_excluding integration: true
  config.filter_run_excluding ollama_required: true

  # Allow running only specific tags with :focus
  config.filter_run_when_matching :focus

  # Print slowest examples when PROFILE=1
  config.profile_examples = 3 if ENV["PROFILE"]

  # Randomize test order
  config.order = :random
  Kernel.srand config.seed
end
