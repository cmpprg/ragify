# frozen_string_literal: true

require "sqlite3"
require "json"
require "time"

module Ragify
  # Store manages SQLite database with vector storage
  # Handles chunks and embeddings storage, retrieval, and similarity search
  #
  # Schema:
  # - chunks: stores code chunks with metadata
  # - vectors: stores embedding vectors as BLOBs
  # - index_metadata: stores indexing metadata (timestamps, stats)
  #
  # Vector search uses cosine similarity computed in Ruby
  # (sqlite-vec extension support can be added in future iterations)
  class Store
    # Database version for migrations
    SCHEMA_VERSION = 1

    # Batch size for bulk inserts
    BATCH_SIZE = 100

    attr_reader :db_path, :db

    def initialize(db_path = ".ragify/ragify.db")
      @db_path = db_path
      @db = nil
    end

    # Open database connection and ensure schema exists
    # @return [Boolean] true if successful
    def open
      ensure_directory_exists
      @db = SQLite3::Database.new(db_path)
      @db.results_as_hash = true

      # Enable foreign keys
      @db.execute("PRAGMA foreign_keys = ON")

      # Performance optimizations
      @db.execute("PRAGMA journal_mode = WAL")
      @db.execute("PRAGMA synchronous = NORMAL")
      @db.execute("PRAGMA cache_size = -64000") # 64MB cache

      setup_schema
      true
    end

    # Close database connection
    def close
      @db&.close
      @db = nil
    end

    # Check if database is open
    def open?
      !@db.nil?
    end

    # Ensure database is open, opening if necessary
    def ensure_open
      open unless open?
    end

    # Setup database schema (creates tables if not exist)
    def setup_schema
      ensure_open

      @db.execute_batch(<<~SQL)
        -- Main chunks table
        CREATE TABLE IF NOT EXISTS chunks (
          id TEXT PRIMARY KEY,
          file_path TEXT NOT NULL,
          chunk_type TEXT NOT NULL,
          name TEXT,
          code TEXT NOT NULL,
          context TEXT,
          start_line INTEGER,
          end_line INTEGER,
          comments TEXT,
          metadata TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        -- Vectors table (embeddings stored as packed floats)
        CREATE TABLE IF NOT EXISTS vectors (
          chunk_id TEXT PRIMARY KEY,
          embedding BLOB NOT NULL,
          dimensions INTEGER NOT NULL,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
        );

        -- Metadata table for index state
        CREATE TABLE IF NOT EXISTS index_metadata (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        );

        -- Indexes for efficient queries
        CREATE INDEX IF NOT EXISTS idx_chunks_file_path ON chunks(file_path);
        CREATE INDEX IF NOT EXISTS idx_chunks_chunk_type ON chunks(chunk_type);
        CREATE INDEX IF NOT EXISTS idx_chunks_name ON chunks(name);
        CREATE INDEX IF NOT EXISTS idx_chunks_context ON chunks(context);

        -- Full-text search on code and comments (internal content FTS5)
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
          chunk_id,
          name,
          code,
          comments,
          context
        );
      SQL

      # Set schema version
      set_metadata("schema_version", SCHEMA_VERSION.to_s)
    end

    # Insert or update a chunk with its embedding
    # @param chunk [Hash] Chunk data from Chunker
    # @param embedding [Array<Float>] Vector embedding (768 dimensions for nomic-embed-text)
    # @return [String] Chunk ID
    def insert_chunk(chunk, embedding = nil)
      ensure_open

      # Check if we're already in a transaction
      in_transaction = begin
        @db.transaction_active?
      rescue NoMethodError
        false
      end

      if in_transaction
        # Already in a transaction, just do the work
        insert_chunk_internal(chunk, embedding)
      else
        # Start our own transaction
        @db.transaction do
          insert_chunk_internal(chunk, embedding)
        end
      end

      chunk[:id]
    end

    # Insert multiple chunks with embeddings in a batch
    # @param chunks_with_embeddings [Array<Array>] Array of [chunk, embedding] pairs
    # @return [Integer] Number of chunks inserted
    def insert_batch(chunks_with_embeddings)
      ensure_open
      count = 0

      chunks_with_embeddings.each_slice(BATCH_SIZE) do |batch|
        @db.transaction do
          batch.each do |chunk, embedding|
            insert_chunk_internal(chunk, embedding)
            count += 1
          end
        end
      end

      # Update last indexed timestamp
      set_metadata("last_indexed_at", Time.now.utc.iso8601)

      count
    end

    # Insert or update an embedding for a chunk
    # @param chunk_id [String] Chunk ID
    # @param embedding [Array<Float>] Vector embedding
    def insert_embedding(chunk_id, embedding)
      ensure_open

      # Pack floats as binary (more efficient than JSON)
      blob = pack_embedding(embedding)

      @db.execute(<<~SQL, [chunk_id, blob, embedding.length])
        INSERT OR REPLACE INTO vectors (chunk_id, embedding, dimensions)
        VALUES (?, ?, ?)
      SQL
    end

    # Get a chunk by ID
    # @param chunk_id [String] Chunk ID
    # @return [Hash, nil] Chunk data or nil if not found
    def get_chunk(chunk_id)
      ensure_open

      row = @db.get_first_row(<<~SQL, [chunk_id])
        SELECT * FROM chunks WHERE id = ?
      SQL

      return nil unless row

      parse_chunk_row(row)
    end

    # Get all chunks for a file
    # @param file_path [String] File path
    # @return [Array<Hash>] Array of chunks
    def get_chunks_for_file(file_path)
      ensure_open

      rows = @db.execute(<<~SQL, [file_path])
        SELECT * FROM chunks WHERE file_path = ? ORDER BY start_line
      SQL

      rows.map { |row| parse_chunk_row(row) }
    end

    # Get embedding for a chunk
    # @param chunk_id [String] Chunk ID
    # @return [Array<Float>, nil] Embedding or nil
    def get_embedding(chunk_id)
      ensure_open

      row = @db.get_first_row(<<~SQL, [chunk_id])
        SELECT embedding, dimensions FROM vectors WHERE chunk_id = ?
      SQL

      return nil unless row

      unpack_embedding(row["embedding"], row["dimensions"])
    end

    # Search for similar chunks using cosine similarity
    # @param query_embedding [Array<Float>] Query vector
    # @param limit [Integer] Maximum results to return
    # @param filters [Hash] Optional filters (type, file_path pattern)
    # @return [Array<Hash>] Results with similarity scores
    def search_similar(query_embedding, limit: 5, filters: {})
      ensure_open

      # Get all chunks with embeddings
      query = build_search_query(filters)
      rows = @db.execute(query[:sql], query[:params])

      # Calculate cosine similarity for each
      results = rows.map do |row|
        embedding = unpack_embedding(row["embedding"], row["dimensions"])
        similarity = cosine_similarity(query_embedding, embedding)

        {
          chunk: parse_chunk_row(row),
          similarity: similarity,
          score: similarity # Alias for compatibility
        }
      end

      # Sort by similarity (descending) and limit
      results
        .sort_by { |r| -r[:similarity] }
        .first(limit)
    end

    # Full-text search on code and comments
    # @param query [String] Search query
    # @param limit [Integer] Maximum results
    # @return [Array<Hash>] Matching chunks with BM25 scores
    def search_text(query, limit: 10)
      ensure_open

      rows = @db.execute(<<~SQL, [query, limit])
        SELECT c.*, bm25(chunks_fts) as rank
        FROM chunks_fts fts
        JOIN chunks c ON fts.chunk_id = c.id
        WHERE chunks_fts MATCH ?
        ORDER BY rank
        LIMIT ?
      SQL

      rows.map do |row|
        {
          chunk: parse_chunk_row(row),
          rank: row["rank"]
        }
      end
    end

    # Hybrid search combining vector similarity and text search
    # @param query_embedding [Array<Float>] Query vector
    # @param text_query [String] Text query
    # @param limit [Integer] Maximum results
    # @param vector_weight [Float] Weight for vector similarity (0-1)
    # @return [Array<Hash>] Combined results
    def search_hybrid(query_embedding, text_query, limit: 5, vector_weight: 0.7)
      ensure_open

      # Get vector search results
      vector_results = search_similar(query_embedding, limit: limit * 2)

      # Get text search results
      text_results = search_text(text_query, limit: limit * 2)

      # Combine and normalize scores
      combined = {}

      # Add vector results
      vector_max = vector_results.map { |r| r[:similarity] }.max || 1.0
      vector_results.each do |result|
        chunk_id = result[:chunk][:id]
        normalized_score = result[:similarity] / vector_max
        combined[chunk_id] = {
          chunk: result[:chunk],
          vector_score: normalized_score,
          text_score: 0.0
        }
      end

      # Add text results
      text_min = text_results.map { |r| r[:rank] }.min || -1.0
      text_results.each do |result|
        chunk_id = result[:chunk][:id]
        # BM25 returns negative scores, lower is better
        normalized_score = text_min.zero? ? 1.0 : (text_min / result[:rank])

        if combined[chunk_id]
          combined[chunk_id][:text_score] = normalized_score
        else
          combined[chunk_id] = {
            chunk: result[:chunk],
            vector_score: 0.0,
            text_score: normalized_score
          }
        end
      end

      # Calculate final scores
      combined.values.map do |item|
        final_score = (item[:vector_score] * vector_weight) +
                      (item[:text_score] * (1 - vector_weight))
        {
          chunk: item[:chunk],
          score: final_score,
          vector_score: item[:vector_score],
          text_score: item[:text_score]
        }
      end.sort_by { |r| -r[:score] }.first(limit)
    end

    # Delete all chunks for a file
    # @param file_path [String] File path
    # @return [Integer] Number of chunks deleted
    def delete_file(file_path)
      ensure_open

      # Count chunks before deleting
      count = @db.get_first_value(
        "SELECT COUNT(*) FROM chunks WHERE file_path = ?",
        [file_path]
      )

      @db.transaction do
        # Get chunk IDs for this file
        chunk_ids = @db.execute(
          "SELECT id FROM chunks WHERE file_path = ?",
          [file_path]
        ).map { |row| row["id"] }

        # Delete from FTS
        chunk_ids.each do |chunk_id|
          @db.execute("DELETE FROM chunks_fts WHERE chunk_id = ?", [chunk_id])
        end

        # Delete from chunks (vectors cascade automatically)
        @db.execute("DELETE FROM chunks WHERE file_path = ?", [file_path])
      end

      count
    end

    # Clear all data from the database
    def clear_all
      ensure_open

      @db.transaction do
        @db.execute("DELETE FROM vectors")
        @db.execute("DELETE FROM chunks_fts")
        @db.execute("DELETE FROM chunks")
        @db.execute("DELETE FROM index_metadata WHERE key != 'schema_version'")
      end
    end

    # Get database statistics
    # @return [Hash] Statistics about the stored data
    def stats
      ensure_open

      chunk_count = @db.get_first_value("SELECT COUNT(*) FROM chunks")
      vector_count = @db.get_first_value("SELECT COUNT(*) FROM vectors")
      file_count = @db.get_first_value("SELECT COUNT(DISTINCT file_path) FROM chunks")

      type_counts = {}
      @db.execute("SELECT chunk_type, COUNT(*) as count FROM chunks GROUP BY chunk_type").each do |row|
        type_counts[row["chunk_type"]] = row["count"]
      end

      last_indexed = get_metadata("last_indexed_at")
      db_size = File.size?(db_path) || 0

      {
        total_chunks: chunk_count,
        total_vectors: vector_count,
        total_files: file_count,
        chunks_by_type: type_counts,
        last_indexed_at: last_indexed,
        database_size_bytes: db_size,
        database_size_mb: (db_size / 1024.0 / 1024.0).round(2),
        schema_version: get_metadata("schema_version")&.to_i || SCHEMA_VERSION
      }
    end

    # Set a metadata value
    # @param key [String] Metadata key
    # @param value [String] Metadata value
    def set_metadata(key, value)
      ensure_open

      @db.execute(<<~SQL, [key, value, Time.now.utc.iso8601])
        INSERT OR REPLACE INTO index_metadata (key, value, updated_at)
        VALUES (?, ?, ?)
      SQL
    end

    # Get a metadata value
    # @param key [String] Metadata key
    # @return [String, nil] Metadata value
    def get_metadata(key)
      ensure_open

      @db.get_first_value(<<~SQL, [key])
        SELECT value FROM index_metadata WHERE key = ?
      SQL
    end

    # Check if a chunk exists
    # @param chunk_id [String] Chunk ID
    # @return [Boolean]
    def chunk_exists?(chunk_id)
      ensure_open

      count = @db.get_first_value(<<~SQL, [chunk_id])
        SELECT COUNT(*) FROM chunks WHERE id = ?
      SQL

      count.positive?
    end

    # Check if an embedding exists for a chunk
    # @param chunk_id [String] Chunk ID
    # @return [Boolean]
    def embedding_exists?(chunk_id)
      ensure_open

      count = @db.get_first_value(<<~SQL, [chunk_id])
        SELECT COUNT(*) FROM vectors WHERE chunk_id = ?
      SQL

      count.positive?
    end

    # Get all file paths that have been indexed
    # @return [Array<String>] List of file paths
    def indexed_files
      ensure_open

      @db.execute(<<~SQL).map { |row| row["file_path"] }
        SELECT DISTINCT file_path FROM chunks ORDER BY file_path
      SQL
    end

    private

    # Ensure the database directory exists
    def ensure_directory_exists
      dir = File.dirname(db_path)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    end

    # Pack an embedding array into a binary blob
    # Uses single-precision floats (4 bytes each)
    def pack_embedding(embedding)
      embedding.pack("f*")
    end

    # Unpack a binary blob into an embedding array
    def unpack_embedding(blob, dimensions)
      blob.unpack("f#{dimensions}")
    end

    # Calculate cosine similarity between two vectors
    # Returns value between -1 and 1 (1 = identical, 0 = orthogonal, -1 = opposite)
    def cosine_similarity(vec_a, vec_b)
      return 0.0 if vec_a.nil? || vec_b.nil?
      return 0.0 if vec_a.length != vec_b.length

      dot_product = 0.0
      norm_a = 0.0
      norm_b = 0.0

      vec_a.length.times do |i|
        dot_product += vec_a[i] * vec_b[i]
        norm_a += vec_a[i] * vec_a[i]
        norm_b += vec_b[i] * vec_b[i]
      end

      norm_a = Math.sqrt(norm_a)
      norm_b = Math.sqrt(norm_b)

      return 0.0 if norm_a.zero? || norm_b.zero?

      dot_product / (norm_a * norm_b)
    end

    # Build the search query with optional filters
    def build_search_query(filters)
      conditions = []
      params = []

      if filters[:type]
        conditions << "c.chunk_type = ?"
        params << filters[:type]
      end

      if filters[:file_path]
        conditions << "c.file_path LIKE ?"
        params << "%#{filters[:file_path]}%"
      end

      where_clause = conditions.empty? ? "" : "WHERE #{conditions.join(" AND ")}"

      {
        sql: <<~SQL,
          SELECT c.*, v.embedding, v.dimensions
          FROM chunks c
          JOIN vectors v ON c.id = v.chunk_id
          #{where_clause}
        SQL
        params: params
      }
    end

    # Parse a chunk row from the database
    def parse_chunk_row(row)
      metadata = row["metadata"] ? JSON.parse(row["metadata"]) : {}
      # Convert string keys to symbols for metadata
      metadata = metadata.transform_keys(&:to_sym) if metadata.is_a?(Hash)

      {
        id: row["id"],
        file_path: row["file_path"],
        type: row["chunk_type"],
        name: row["name"],
        code: row["code"],
        context: row["context"] || "",
        start_line: row["start_line"],
        end_line: row["end_line"],
        comments: row["comments"] || "",
        metadata: metadata,
        created_at: row["created_at"],
        updated_at: row["updated_at"]
      }
    end

    # Internal method for inserting a chunk (no transaction handling)
    def insert_chunk_internal(chunk, embedding)
      # First delete any existing FTS entry for this chunk
      @db.execute("DELETE FROM chunks_fts WHERE chunk_id = ?", [chunk[:id]])

      # Insert or replace chunk
      params = [
        chunk[:id],
        chunk[:file_path],
        chunk[:type],
        chunk[:name],
        chunk[:code],
        chunk[:context],
        chunk[:start_line],
        chunk[:end_line],
        chunk[:comments],
        chunk[:metadata].to_json,
        Time.now.utc.iso8601
      ]

      @db.execute(<<~SQL, params)
        INSERT OR REPLACE INTO chunks
          (id, file_path, chunk_type, name, code, context, start_line, end_line, comments, metadata, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      SQL

      # Insert into FTS table
      fts_params = [
        chunk[:id],
        chunk[:name],
        chunk[:code],
        chunk[:comments],
        chunk[:context]
      ]
      @db.execute(<<~SQL, fts_params)
        INSERT INTO chunks_fts (chunk_id, name, code, comments, context)
        VALUES (?, ?, ?, ?, ?)
      SQL

      # Insert embedding if provided
      return unless embedding && !embedding.empty?

      insert_embedding(chunk[:id], embedding)
    end
  end

  # Error class for store-related errors
  class StoreError < StandardError; end
end
