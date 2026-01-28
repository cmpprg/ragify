# frozen_string_literal: true

require "pathname"

module Ragify
  class Indexer
    DEFAULT_IGNORE_PATTERNS = [
      ".git/**/*",
      ".ragify/**/*",
      "vendor/**/*",
      "node_modules/**/*",
      "tmp/**/*",
      "log/**/*",
      "coverage/**/*",
      ".bundle/**/*"
    ].freeze

    attr_reader :root_path, :config, :verbose

    def initialize(root_path, config, verbose: false)
      @root_path = Pathname.new(root_path).expand_path
      @config = config
      @verbose = verbose
      @ignore_patterns = load_ignore_patterns
    end

    def discover_files
      log "Discovering Ruby files in #{root_path}..."

      ruby_files = []

      Find.find(root_path) do |path|
        # Skip if matches ignore patterns
        if should_ignore?(path)
          Find.prune if File.directory?(path)
          next
        end

        # Only process .rb files
        next unless File.file?(path) && path.end_with?(".rb")

        # Skip if file is binary or unreadable
        next if binary_file?(path)

        ruby_files << path
        log "  Found: #{relative_path(path)}"
      end

      log "Discovered #{ruby_files.length} Ruby files"
      ruby_files.sort
    end

    def read_file(file_path)
      content = File.read(file_path, encoding: "UTF-8")
      log "  Read #{content.lines.count} lines from #{relative_path(file_path)}"
      content
    rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
      # Try with binary encoding and force UTF-8
      content = File.read(file_path, encoding: "BINARY").force_encoding("UTF-8")
      unless content.valid_encoding?
        log "  Skipping #{relative_path(file_path)} - encoding errors"
        return nil
      end
      content
    rescue StandardError => e
      log "  Error reading #{relative_path(file_path)}: #{e.message}"
      nil
    end

    def validate_ruby_file(file_path)
      content = read_file(file_path)
      return false if content.nil? || content.strip.empty?

      # Check if it looks like Ruby code
      # This is a simple heuristic - we'll do full parsing in Day 2
      has_ruby_keywords = content.match?(/\b(class|module|def|require|include|extend)\b/)

      if has_ruby_keywords
        log "  ✓ Valid Ruby file: #{relative_path(file_path)}"
        true
      else
        log "  ? Questionable Ruby file (no keywords): #{relative_path(file_path)}"
        true # Still include it, let parser handle it later
      end
    end

    private

    def load_ignore_patterns
      patterns = DEFAULT_IGNORE_PATTERNS.dup

      # Load from .ragifyignore if it exists
      ragifyignore_path = root_path.join(".ragifyignore")
      if File.exist?(ragifyignore_path)
        File.readlines(ragifyignore_path).each do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          patterns << line
        end
        log "Loaded ignore patterns from .ragifyignore"
      end

      # Add patterns from config
      patterns.concat(config.ignore_patterns)

      patterns.uniq
    end

    def should_ignore?(path)
      relative = relative_path(path)

      @ignore_patterns.any? do |pattern|
        # Convert glob pattern to regex
        File.fnmatch?(pattern, relative, File::FNM_PATHNAME | File::FNM_DOTMATCH)
      end
    end

    def binary_file?(path)
      # Read first 8KB to check for null bytes
      chunk = File.read(path, 8192, encoding: "BINARY")
      chunk.include?("\x00")
    rescue StandardError
      true # If we can't read it, treat it as binary
    end

    def relative_path(path)
      Pathname.new(path).relative_path_from(root_path).to_s
    end

    def log(message)
      puts message if verbose
    end
  end
end

# Require Find for directory traversal
require "find"
