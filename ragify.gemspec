# frozen_string_literal: true

require_relative "lib/ragify/version"

Gem::Specification.new do |spec|
  spec.name = "ragify"
  spec.version = Ragify::VERSION
  spec.authors = ["Ryan Camp"]
  spec.email = ["campryan@comcast.net"]

  spec.summary = "Local-first RAG system for Ruby codebases using AI embeddings"
  spec.description = "Ragify makes Ruby codebases semantically searchable using AI embeddings. " \
                     "Index your code with Ollama and search using natural language queries."
  spec.homepage = "https://github.com/ryanmcgarvey/ragify"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ryanmcgarvey/ragify"
  spec.metadata["changelog_uri"] = "https://github.com/ryanmcgarvey/ragify/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = ["ragify"]
  spec.require_paths = ["lib"]

  # Core dependencies
  spec.add_dependency "faraday", "~> 2.7"
  spec.add_dependency "parser", "~> 3.2"
  spec.add_dependency "sqlite3", "~> 1.6"
  spec.add_dependency "thor", "~> 1.3"

  # Optional but recommended for better UX
  spec.add_dependency "pastel", "~> 0.8"
  spec.add_dependency "tty-progressbar", "~> 0.18"
  spec.add_dependency "tty-prompt", "~> 0.23"

  # Development dependencies
  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.56"
end
