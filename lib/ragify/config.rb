# frozen_string_literal: true

require "yaml"
require "json"

module Ragify
  class Config
    DEFAULT_CONFIG = {
      "ollama_url" => "http://localhost:11434",
      "model" => "nomic-embed-text",
      "chunk_size_limit" => 1000,
      "search_result_limit" => 5,
      "ignore_patterns" => [
        "spec/**/*",
        "test/**/*",
        "vendor/**/*",
        "node_modules/**/*",
        "db/schema.rb"
      ]
    }.freeze

    attr_reader :ollama_url, :model, :chunk_size_limit, :search_result_limit, :ignore_patterns

    def initialize(config_hash = {})
      merged = DEFAULT_CONFIG.merge(config_hash)
      @ollama_url = merged["ollama_url"]
      @model = merged["model"]
      @chunk_size_limit = merged["chunk_size_limit"]
      @search_result_limit = merged["search_result_limit"]
      @ignore_patterns = merged["ignore_patterns"]
    end

    def self.create_default
      config_content = <<~YAML
        # Ragify Configuration

        # Ollama server URL
        ollama_url: http://localhost:11434

        # Embedding model to use
        # Recommended: nomic-embed-text (768 dimensions, 8K context)
        # Alternatives: snowflake-arctic-embed, all-minilm, mxbai-embed-large
        model: nomic-embed-text

        # Maximum lines per code chunk
        chunk_size_limit: 1000

        # Default number of search results
        search_result_limit: 5

        # Additional ignore patterns (beyond .ragifyignore)
        ignore_patterns:
          - spec/**/*
          - test/**/*
          - vendor/**/*
          - node_modules/**/*
          - db/schema.rb
      YAML

      File.write(".ragify/config.yml", config_content)
    end

    def self.load
      config_path = ".ragify/config.yml"

      return new(DEFAULT_CONFIG) unless File.exist?(config_path)

      config_hash = YAML.load_file(config_path)
      new(config_hash)
    rescue StandardError => e
      warn "Warning: Could not load config (#{e.message}), using defaults"
      new(DEFAULT_CONFIG)
    end

    def to_h
      {
        "ollama_url" => @ollama_url,
        "model" => @model,
        "chunk_size_limit" => @chunk_size_limit,
        "search_result_limit" => @search_result_limit,
        "ignore_patterns" => @ignore_patterns
      }
    end
  end
end
