# frozen_string_literal: true

require_relative "ragify/version"
require_relative "ragify/config"
require_relative "ragify/indexer"
require_relative "ragify/chunker"
require_relative "ragify/embedder"
require_relative "ragify/store"
require_relative "ragify/searcher"

module Ragify
  class Error < StandardError; end

  # Main module for Ragify - Ruby codebase RAG system
  #
  # Ragify makes Ruby codebases semantically searchable using AI embeddings.
  # It uses Ollama for local embeddings and SQLite for vector storage.
end
