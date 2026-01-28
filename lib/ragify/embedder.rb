# frozen_string_literal: true

require "faraday"
require "digest"

module Ragify
  # Embedder generates vector embeddings using Ollama
  # Handles batching, caching, retries, and error handling
  class Embedder
    # Ollama API endpoints
    GENERATE_ENDPOINT = "/api/embeddings"
    TAGS_ENDPOINT = "/api/tags"

    # Configuration
    DEFAULT_BATCH_SIZE = 5
    MAX_RETRIES = 3
    RETRY_DELAY = 1 # seconds

    attr_reader :config, :ollama_url, :model, :cache

    def initialize(config)
      @config = config
      @ollama_url = config.ollama_url
      @model = config.model
      @cache = {} # Simple in-memory cache: hash => embedding
      @connection = build_connection
    end

    # Generate embedding for a single text
    # @param text [String] Text to embed
    # @return [Array<Float>] Vector embedding (768 dimensions for nomic-embed-text)
    def embed(text)
      raise ArgumentError, "Text cannot be nil or empty" if text.nil? || text.strip.empty?

      # Check cache first
      cache_key = cache_key_for(text)
      return cache[cache_key] if cache.key?(cache_key)

      # Generate embedding
      embedding = generate_embedding(text)

      # Cache result
      cache[cache_key] = embedding

      embedding
    end

    # Generate embeddings for multiple texts (batched)
    # @param texts [Array<String>] Array of texts to embed
    # @param batch_size [Integer] Number of texts per batch
    # @param show_progress [Boolean] Whether to show progress bar
    # @return [Array<Array<Float>>] Array of embeddings
    def embed_batch(texts, batch_size: DEFAULT_BATCH_SIZE, show_progress: false)
      raise ArgumentError, "Texts must be an array" unless texts.is_a?(Array)
      return [] if texts.empty?

      embeddings = []
      total = texts.length

      # Setup progress bar if requested
      progress_bar = nil
      if show_progress
        require "tty-progressbar"
        progress_bar = TTY::ProgressBar.new(
          "Generating embeddings [:bar] :current/:total (:percent)",
          total: total,
          width: 40
        )
      end

      # Process in batches
      texts.each_slice(batch_size) do |batch|
        batch_embeddings = batch.map do |text|
          embedding = embed(text)
          progress_bar&.advance
          embedding
        end

        embeddings.concat(batch_embeddings)

        # Small delay between batches to avoid overwhelming Ollama
        sleep(0.1) if batch_size > 1
      end

      embeddings
    end

    # Prepare chunk for embedding by combining code, context, and comments
    # Format: "In {context}, {type} {name}: {comments}\n{code}"
    # @param chunk [Hash] Chunk hash from Chunker
    # @return [String] Formatted text for embedding
    def prepare_chunk_text(chunk)
      parts = []

      # Add context if present
      parts << "In #{chunk[:context]}," unless chunk[:context].empty?

      # Add type and name
      parts << "#{chunk[:type]} #{chunk[:name]}:"

      # Add comments/docstring if present
      parts << chunk[:comments] unless chunk[:comments].empty?

      # Add the actual code
      parts << chunk[:code]

      parts.join("\n")
    end

    # Check if Ollama is running and accessible
    # @return [Boolean] True if Ollama is available
    def ollama_available?
      response = @connection.get(TAGS_ENDPOINT)
      response.status == 200
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError
      false
    end

    # Verify that the configured model is available
    # @return [Boolean] True if model is available
    def model_available?
      response = @connection.get(TAGS_ENDPOINT)
      return false unless response.status == 200

      # response.body is already parsed by Faraday's json middleware
      models = response.body["models"] || []
      models.any? { |m| m["name"].include?(model) }
    rescue Faraday::ConnectionFailed, Faraday::TimeoutError
      false
    end

    # Get statistics about the cache
    # @return [Hash] Cache statistics
    def cache_stats
      {
        size: cache.size,
        memory_kb: (cache.to_s.bytesize / 1024.0).round(2)
      }
    end

    # Clear the embedding cache
    def clear_cache
      @cache = {}
    end

    private

    # Build Faraday connection
    def build_connection
      Faraday.new(url: ollama_url) do |conn|
        conn.request :json
        conn.response :json
        conn.adapter Faraday.default_adapter
        conn.options.timeout = 30 # 30 second timeout
        conn.options.open_timeout = 5 # 5 second connection timeout
      end
    end

    # Generate embedding with retry logic
    def generate_embedding(text, attempt = 1)
      response = @connection.post(GENERATE_ENDPOINT) do |req|
        req.body = {
          model: model,
          prompt: text
        }
      end

      raise OllamaError, "Ollama returned status #{response.status}: #{response.body}" unless response.status == 200

      embedding = response.body["embedding"]
      validate_embedding(embedding)
      embedding
    rescue Faraday::ConnectionFailed
      raise OllamaConnectionError, "Could not connect to Ollama at #{ollama_url}. Is Ollama running?"
    rescue Faraday::TimeoutError
      raise OllamaTimeoutError, "Ollama request timed out after #{MAX_RETRIES} attempts" unless attempt < MAX_RETRIES

      sleep(RETRY_DELAY * attempt)
      generate_embedding(text, attempt + 1)
    rescue StandardError => e
      raise OllamaError, "Failed to generate embedding: #{e.message}" unless attempt < MAX_RETRIES

      sleep(RETRY_DELAY * attempt)
      generate_embedding(text, attempt + 1)
    end

    # Validate embedding dimensions
    def validate_embedding(embedding)
      raise OllamaError, "Invalid embedding format" unless embedding.is_a?(Array) && !embedding.empty?

      # nomic-embed-text should return 768 dimensions
      expected_dims = 768
      return if embedding.length == expected_dims

      warn "Warning: Expected #{expected_dims} dimensions, got #{embedding.length}"
    end

    # Generate cache key for text
    def cache_key_for(text)
      Digest::SHA256.hexdigest(text)
    end
  end

  # Custom errors for better error handling
  class OllamaError < StandardError; end
  class OllamaConnectionError < OllamaError; end
  class OllamaTimeoutError < OllamaError; end
end
