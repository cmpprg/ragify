# frozen_string_literal: true

module Ragify
  # Searcher handles semantic search queries
  # Will be implemented in Day 5
  class Searcher
    def initialize(store, embedder, config)
      @store = store
      @embedder = embedder
      @config = config
    end

    def search(query, limit: nil, type: nil, path_filter: nil)
      # TODO: Implement in Day 5
      # - Generate query embedding
      # - Perform vector similarity search
      # - Apply filters (type, path)
      # - Implement hybrid search (semantic + keyword)
      # - Rank and format results
      raise NotImplementedError, "Searcher will be implemented in Day 5"
    end

    def format_results(results)
      # TODO: Implement in Day 5
      # - Format search results for display
      # - Show file path, line numbers, code snippets
      # - Add syntax highlighting
      raise NotImplementedError, "Searcher will be implemented in Day 5"
    end
  end
end
