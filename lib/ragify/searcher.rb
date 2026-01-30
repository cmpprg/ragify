# frozen_string_literal: true

module Ragify
  # Searcher handles semantic and hybrid search queries
  # Combines vector similarity search with full-text search for best results
  class Searcher
    # Default search configuration
    DEFAULT_LIMIT = 5
    DEFAULT_VECTOR_WEIGHT = 0.7 # 70% semantic, 30% keyword for hybrid

    attr_reader :store, :embedder, :config

    def initialize(store, embedder, config)
      @store = store
      @embedder = embedder
      @config = config
    end

    # Perform a search query
    # @param query [String] Natural language search query
    # @param limit [Integer] Maximum number of results
    # @param type [String, nil] Filter by chunk type (method, class, module, constant)
    # @param path_filter [String, nil] Filter by file path pattern
    # @param min_score [Float, nil] Minimum similarity score (0.0-1.0)
    # @param mode [Symbol] Search mode (:hybrid, :semantic, :text)
    # @return [Array<Hash>] Search results with scores and metadata
    def search(query, limit: nil, type: nil, path_filter: nil, min_score: nil, mode: :hybrid)
      raise ArgumentError, "Query cannot be empty" if query.nil? || query.strip.empty?

      limit ||= config.search_result_limit || DEFAULT_LIMIT
      results = []

      case mode
      when :hybrid
        results = hybrid_search(query, limit, type, path_filter)
      when :semantic
        results = semantic_search(query, limit, type, path_filter)
      when :text
        results = text_search(query, limit, type, path_filter)
      else
        raise ArgumentError, "Unknown search mode: #{mode}"
      end

      # Apply minimum score filter if specified
      results = results.select { |r| r[:score] >= min_score } if min_score

      # Ensure we don't exceed limit after filtering
      results.first(limit)
    end

    # Check if semantic search is available (Ollama running)
    # @return [Boolean]
    def semantic_available?
      return false unless embedder

      embedder.ollama_available? && embedder.model_available?
    end

    # Format search results for display
    # @param results [Array<Hash>] Search results
    # @param format [Symbol] Output format (:colorized, :plain, :json)
    # @return [String] Formatted output
    def format_results(results, format: :colorized)
      return "" if results.empty?

      case format
      when :json
        format_json(results)
      when :plain
        format_plain(results)
      when :colorized
        format_colorized(results)
      else
        format_plain(results)
      end
    end

    private

    # Perform hybrid search (semantic + text)
    def hybrid_search(query, limit, type, path_filter)
      # Check if semantic search is available
      unless semantic_available?
        # Fall back to text-only search
        return text_search(query, limit, type, path_filter)
      end

      # Generate query embedding
      query_embedding = generate_query_embedding(query)
      return text_search(query, limit, type, path_filter) unless query_embedding

      # Build filters
      filters = build_filters(type, path_filter)

      # Perform hybrid search
      results = store.search_hybrid(
        query_embedding,
        query,
        limit: limit,
        vector_weight: DEFAULT_VECTOR_WEIGHT
      )

      # Apply filters (store.search_hybrid doesn't support filters directly)
      results = apply_filters(results, filters)

      normalize_results(results, :hybrid)
    end

    # Perform semantic-only search
    def semantic_search(query, limit, type, path_filter)
      unless semantic_available?
        raise SearchError, "Semantic search unavailable. Ollama not running or model not found."
      end

      query_embedding = generate_query_embedding(query)
      raise SearchError, "Failed to generate query embedding" unless query_embedding

      filters = build_filters(type, path_filter)

      results = store.search_similar(query_embedding, limit: limit * 2, filters: filters)
      results = results.first(limit)

      normalize_results(results, :semantic)
    end

    # Perform text-only search
    def text_search(query, limit, type, path_filter)
      results = store.search_text(query, limit: limit * 2)

      # Apply filters manually since FTS doesn't support them
      filters = build_filters(type, path_filter)
      results = apply_filters(results, filters)
      results = results.first(limit)

      normalize_results(results, :text)
    end

    # Generate embedding for the search query
    def generate_query_embedding(query)
      # Prepare query text similar to how chunks are prepared
      # but simpler since it's just a query
      embedder.embed(query)
    rescue OllamaError => e
      warn "Warning: Could not generate query embedding: #{e.message}"
      nil
    end

    # Build filters hash from parameters
    def build_filters(type, path_filter)
      filters = {}
      filters[:type] = type if type
      filters[:file_path] = path_filter if path_filter
      filters
    end

    # Apply filters to results (for methods that don't support inline filtering)
    def apply_filters(results, filters)
      return results if filters.empty?

      results.select do |result|
        chunk = result[:chunk]
        matches = true

        matches &&= chunk[:type] == filters[:type] if filters[:type]

        matches &&= chunk[:file_path]&.include?(filters[:file_path]) if filters[:file_path]

        matches
      end
    end

    # Normalize results to a consistent format
    def normalize_results(results, search_type)
      results.map do |result|
        {
          chunk: result[:chunk],
          score: extract_score(result, search_type),
          search_type: search_type,
          # Include sub-scores if available (for hybrid)
          vector_score: result[:vector_score],
          text_score: result[:text_score]
        }
      end
    end

    # Extract the primary score from a result
    def extract_score(result, search_type)
      case search_type
      when :hybrid
        result[:score] || 0.0
      when :semantic
        result[:similarity] || result[:score] || 0.0
      when :text
        # BM25 returns negative scores, normalize to 0-1 range
        # Lower (more negative) is better, so we invert
        rank = result[:rank] || 0.0
        rank.negative? ? (1.0 / (1.0 + rank.abs)) : 0.5
      else
        result[:score] || 0.0
      end
    end

    # Format results as JSON
    def format_json(results)
      require "json"

      output = results.map do |result|
        {
          file_path: result[:chunk][:file_path],
          type: result[:chunk][:type],
          name: result[:chunk][:name],
          context: result[:chunk][:context],
          start_line: result[:chunk][:start_line],
          end_line: result[:chunk][:end_line],
          score: result[:score].round(4),
          code: result[:chunk][:code]
        }
      end

      JSON.pretty_generate(output)
    end

    # Format results as plain text
    def format_plain(results)
      lines = []

      results.each_with_index do |result, index|
        chunk = result[:chunk]
        score = result[:score]

        lines << "#{index + 1}. #{chunk[:name]} (#{chunk[:type]})"
        lines << "   File: #{chunk[:file_path]}:#{chunk[:start_line]}-#{chunk[:end_line]}"
        lines << "   Score: #{format("%.4f", score)}"
        lines << "   Context: #{chunk[:context]}" unless chunk[:context].to_s.empty?
        lines << ""
        lines << "   Code:"
        lines << format_code_snippet(chunk[:code], "   ")
        lines << ""
        lines << "-" * 60
        lines << ""
      end

      lines.join("\n")
    end

    # Format results with terminal colors
    def format_colorized(results)
      require "pastel"
      pastel = Pastel.new

      lines = []

      results.each_with_index do |result, index|
        chunk = result[:chunk]
        score = result[:score]

        # Header with rank and name
        type_color = type_to_color(chunk[:type])
        lines << pastel.bold("#{index + 1}. #{chunk[:name]}") +
                 " " +
                 pastel.send(type_color, "(#{chunk[:type]})")

        # File location
        lines << pastel.dim("   #{chunk[:file_path]}") +
                 pastel.cyan(":#{chunk[:start_line]}-#{chunk[:end_line]}")

        # Score with color based on value
        score_color = score_to_color(score)
        lines << "   Score: " + pastel.send(score_color, format("%.4f", score))

        # Context if present
        lines << "   Context: " + pastel.yellow(chunk[:context]) unless chunk[:context].to_s.empty?

        # Code snippet
        lines << ""
        lines << pastel.dim("   Code:")
        lines << format_code_snippet(chunk[:code], "   ", pastel)
        lines << ""
        lines << pastel.dim("-" * 60)
        lines << ""
      end

      lines.join("\n")
    end

    # Format a code snippet with optional indentation
    def format_code_snippet(code, indent = "", pastel = nil)
      return "" if code.nil? || code.empty?

      lines = code.lines
      max_lines = 10 # Show first 10 lines max

      formatted_lines = lines.first(max_lines).map do |line|
        "#{indent}  #{line.rstrip}"
      end

      if lines.length > max_lines
        truncated_msg = "... (#{lines.length - max_lines} more lines)"
        formatted_lines << if pastel
                             "#{indent}  #{pastel.dim(truncated_msg)}"
                           else
                             "#{indent}  #{truncated_msg}"
                           end
      end

      formatted_lines.join("\n")
    end

    # Map chunk type to terminal color
    def type_to_color(type)
      case type
      when "class" then :blue
      when "module" then :magenta
      when "method" then :green
      when "constant" then :yellow
      else :white
      end
    end

    # Map score to terminal color
    def score_to_color(score)
      if score >= 0.8
        :green
      elsif score >= 0.5
        :yellow
      else
        :red
      end
    end
  end

  # Custom error for search-related issues
  class SearchError < StandardError; end
end
