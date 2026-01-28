# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Ragify::Store do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, ".ragify", "ragify.db") }
  let(:store) { described_class.new(db_path) }

  # Sample chunk data
  let(:sample_chunk) do
    {
      id: "abc123def456",
      file_path: "app/models/user.rb",
      type: "method",
      name: "authenticate",
      code: "def authenticate(password)\n  verify(password)\nend",
      context: "class User",
      start_line: 10,
      end_line: 12,
      comments: "# Authenticate the user",
      metadata: { visibility: "public", class_method: false }
    }
  end

  # Sample embedding (768 dimensions for nomic-embed-text)
  let(:sample_embedding) { Array.new(768) { rand(-1.0..1.0) } }

  # Another sample chunk for testing multiple chunks
  let(:another_chunk) do
    {
      id: "xyz789abc123",
      file_path: "app/models/user.rb",
      type: "class",
      name: "User",
      code: "class User < ApplicationRecord\nend",
      context: "",
      start_line: 1,
      end_line: 5,
      comments: "# User model",
      metadata: { parent_class: "ApplicationRecord" }
    }
  end

  let(:another_embedding) { Array.new(768) { rand(-1.0..1.0) } }

  after do
    store.close if store.open?
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "sets the database path" do
      expect(store.db_path).to eq(db_path)
    end

    it "starts with closed connection" do
      expect(store.open?).to be false
    end
  end

  describe "#open" do
    it "creates database directory if it doesn't exist" do
      store.open
      expect(File.directory?(File.dirname(db_path))).to be true
    end

    it "creates the database file" do
      store.open
      expect(File.exist?(db_path)).to be true
    end

    it "sets up the schema" do
      store.open
      tables = store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |row| row["name"] }
      expect(tables).to include("chunks", "vectors", "index_metadata")
    end

    it "creates indexes" do
      store.open
      indexes = store.db.execute("SELECT name FROM sqlite_master WHERE type='index'").map { |row| row["name"] }
      expect(indexes).to include("idx_chunks_file_path", "idx_chunks_chunk_type", "idx_chunks_name")
    end

    it "creates FTS table" do
      store.open
      tables = store.db.execute("SELECT name FROM sqlite_master WHERE type='table'").map { |row| row["name"] }
      expect(tables).to include("chunks_fts")
    end

    it "returns true on success" do
      expect(store.open).to be true
    end

    it "marks store as open" do
      store.open
      expect(store.open?).to be true
    end
  end

  describe "#close" do
    it "closes the database connection" do
      store.open
      store.close
      expect(store.open?).to be false
    end
  end

  describe "#insert_chunk" do
    before { store.open }

    it "inserts a chunk without embedding" do
      id = store.insert_chunk(sample_chunk)
      expect(id).to eq(sample_chunk[:id])
      expect(store.chunk_exists?(sample_chunk[:id])).to be true
    end

    it "inserts a chunk with embedding" do
      store.insert_chunk(sample_chunk, sample_embedding)
      expect(store.chunk_exists?(sample_chunk[:id])).to be true
      expect(store.embedding_exists?(sample_chunk[:id])).to be true
    end

    it "updates existing chunk on conflict" do
      store.insert_chunk(sample_chunk)

      updated_chunk = sample_chunk.merge(name: "updated_name")
      store.insert_chunk(updated_chunk)

      retrieved = store.get_chunk(sample_chunk[:id])
      expect(retrieved[:name]).to eq("updated_name")
    end

    it "stores metadata as JSON" do
      store.insert_chunk(sample_chunk)
      retrieved = store.get_chunk(sample_chunk[:id])
      expect(retrieved[:metadata]).to eq(sample_chunk[:metadata])
    end
  end

  describe "#insert_batch" do
    before { store.open }

    it "inserts multiple chunks with embeddings" do
      chunks_with_embeddings = [
        [sample_chunk, sample_embedding],
        [another_chunk, another_embedding]
      ]

      count = store.insert_batch(chunks_with_embeddings)

      expect(count).to eq(2)
      expect(store.chunk_exists?(sample_chunk[:id])).to be true
      expect(store.chunk_exists?(another_chunk[:id])).to be true
    end

    it "updates last_indexed_at metadata" do
      store.insert_batch([[sample_chunk, sample_embedding]])

      last_indexed = store.get_metadata("last_indexed_at")
      expect(last_indexed).not_to be_nil
    end
  end

  describe "#get_chunk" do
    before { store.open }

    it "retrieves an existing chunk" do
      store.insert_chunk(sample_chunk)
      retrieved = store.get_chunk(sample_chunk[:id])

      expect(retrieved[:id]).to eq(sample_chunk[:id])
      expect(retrieved[:name]).to eq(sample_chunk[:name])
      expect(retrieved[:code]).to eq(sample_chunk[:code])
      expect(retrieved[:type]).to eq(sample_chunk[:type])
    end

    it "returns nil for non-existent chunk" do
      result = store.get_chunk("nonexistent")
      expect(result).to be_nil
    end
  end

  describe "#get_chunks_for_file" do
    before { store.open }

    it "retrieves all chunks for a file" do
      store.insert_chunk(sample_chunk)
      store.insert_chunk(another_chunk)

      chunks = store.get_chunks_for_file("app/models/user.rb")

      expect(chunks.length).to eq(2)
      expect(chunks.map { |c| c[:id] }).to include(sample_chunk[:id], another_chunk[:id])
    end

    it "orders by start_line" do
      store.insert_chunk(sample_chunk) # start_line: 10
      store.insert_chunk(another_chunk) # start_line: 1

      chunks = store.get_chunks_for_file("app/models/user.rb")

      expect(chunks.first[:id]).to eq(another_chunk[:id])
    end

    it "returns empty array for unknown file" do
      chunks = store.get_chunks_for_file("unknown.rb")
      expect(chunks).to eq([])
    end
  end

  describe "#get_embedding" do
    before { store.open }

    it "retrieves embedding for a chunk" do
      store.insert_chunk(sample_chunk, sample_embedding)

      retrieved = store.get_embedding(sample_chunk[:id])

      expect(retrieved).to be_an(Array)
      expect(retrieved.length).to eq(768)
      # Check first few values are close (floating point)
      sample_embedding.first(5).each_with_index do |val, i|
        expect(retrieved[i]).to be_within(0.0001).of(val)
      end
    end

    it "returns nil for chunk without embedding" do
      store.insert_chunk(sample_chunk)
      result = store.get_embedding(sample_chunk[:id])
      expect(result).to be_nil
    end
  end

  describe "#search_similar" do
    before do
      store.open

      # Create chunks with known embeddings for testing
      @chunk1 = sample_chunk.dup
      @chunk1[:id] = "chunk1"
      @embedding1 = normalize_vector([1.0, 0.0, 0.0] + [0.0] * 765)

      @chunk2 = sample_chunk.dup
      @chunk2[:id] = "chunk2"
      @chunk2[:name] = "method2"
      @embedding2 = normalize_vector([0.9, 0.1, 0.0] + [0.0] * 765) # Similar to chunk1

      @chunk3 = sample_chunk.dup
      @chunk3[:id] = "chunk3"
      @chunk3[:name] = "method3"
      @embedding3 = normalize_vector([0.0, 1.0, 0.0] + [0.0] * 765) # Different direction

      store.insert_chunk(@chunk1, @embedding1)
      store.insert_chunk(@chunk2, @embedding2)
      store.insert_chunk(@chunk3, @embedding3)
    end

    def normalize_vector(vec)
      magnitude = Math.sqrt(vec.map { |x| x * x }.sum)
      vec.map { |x| x / magnitude }
    end

    it "returns chunks sorted by similarity" do
      query = normalize_vector([1.0, 0.0, 0.0] + [0.0] * 765)
      results = store.search_similar(query, limit: 3)

      expect(results.length).to eq(3)
      # chunk1 should be most similar (identical direction)
      expect(results[0][:chunk][:id]).to eq("chunk1")
      # chunk2 should be second (similar direction)
      expect(results[1][:chunk][:id]).to eq("chunk2")
    end

    it "respects limit parameter" do
      query = normalize_vector([1.0, 0.0, 0.0] + [0.0] * 765)
      results = store.search_similar(query, limit: 1)

      expect(results.length).to eq(1)
    end

    it "includes similarity scores" do
      query = normalize_vector([1.0, 0.0, 0.0] + [0.0] * 765)
      results = store.search_similar(query, limit: 3)

      results.each do |result|
        expect(result[:similarity]).to be_a(Numeric)
        expect(result[:similarity]).to be_between(-1.0, 1.0)
      end
    end

    it "filters by chunk type" do
      # Add a class chunk
      class_chunk = another_chunk.dup
      class_chunk[:id] = "class_chunk"
      store.insert_chunk(class_chunk, @embedding1)

      query = normalize_vector([1.0, 0.0, 0.0] + [0.0] * 765)
      results = store.search_similar(query, limit: 10, filters: { type: "class" })

      expect(results.length).to eq(1)
      expect(results[0][:chunk][:type]).to eq("class")
    end
  end

  describe "#search_text" do
    before do
      store.open
      store.insert_chunk(sample_chunk) # "authenticate"
      store.insert_chunk(another_chunk) # "User"
    end

    it "finds chunks matching text query" do
      results = store.search_text("authenticate")

      expect(results.length).to eq(1)
      expect(results[0][:chunk][:name]).to eq("authenticate")
    end

    it "returns empty array for no matches" do
      results = store.search_text("nonexistent_query_xyz")
      expect(results).to eq([])
    end

    it "includes BM25 rank" do
      results = store.search_text("authenticate")

      expect(results[0][:rank]).to be_a(Numeric)
    end
  end

  describe "#delete_file" do
    before do
      store.open
      store.insert_chunk(sample_chunk, sample_embedding)
      store.insert_chunk(another_chunk, another_embedding)
    end

    it "deletes all chunks for a file" do
      count = store.delete_file("app/models/user.rb")

      expect(count).to eq(2)
      expect(store.get_chunks_for_file("app/models/user.rb")).to be_empty
    end

    it "cascades to delete embeddings" do
      store.delete_file("app/models/user.rb")

      expect(store.embedding_exists?(sample_chunk[:id])).to be false
      expect(store.embedding_exists?(another_chunk[:id])).to be false
    end
  end

  describe "#clear_all" do
    before do
      store.open
      store.insert_chunk(sample_chunk, sample_embedding)
      store.insert_chunk(another_chunk, another_embedding)
    end

    it "removes all chunks and vectors" do
      store.clear_all

      expect(store.stats[:total_chunks]).to eq(0)
      expect(store.stats[:total_vectors]).to eq(0)
    end

    it "preserves schema version" do
      store.clear_all

      version = store.get_metadata("schema_version")
      expect(version).not_to be_nil
    end
  end

  describe "#stats" do
    before { store.open }

    context "with empty database" do
      it "returns zero counts" do
        stats = store.stats

        expect(stats[:total_chunks]).to eq(0)
        expect(stats[:total_vectors]).to eq(0)
        expect(stats[:total_files]).to eq(0)
      end
    end

    context "with data" do
      before do
        store.insert_chunk(sample_chunk, sample_embedding)
        store.insert_chunk(another_chunk, another_embedding)
      end

      it "returns correct counts" do
        stats = store.stats

        expect(stats[:total_chunks]).to eq(2)
        expect(stats[:total_vectors]).to eq(2)
        expect(stats[:total_files]).to eq(1)
      end

      it "groups chunks by type" do
        stats = store.stats

        expect(stats[:chunks_by_type]).to include(
          "method" => 1,
          "class" => 1
        )
      end

      it "includes database size" do
        stats = store.stats

        expect(stats[:database_size_bytes]).to be > 0
        expect(stats[:database_size_mb]).to be_a(Numeric)
      end

      it "includes schema version" do
        stats = store.stats

        expect(stats[:schema_version]).to eq(Ragify::Store::SCHEMA_VERSION)
      end
    end
  end

  describe "#set_metadata and #get_metadata" do
    before { store.open }

    it "stores and retrieves metadata" do
      store.set_metadata("test_key", "test_value")

      result = store.get_metadata("test_key")
      expect(result).to eq("test_value")
    end

    it "updates existing metadata" do
      store.set_metadata("key", "value1")
      store.set_metadata("key", "value2")

      result = store.get_metadata("key")
      expect(result).to eq("value2")
    end

    it "returns nil for unknown keys" do
      result = store.get_metadata("unknown_key")
      expect(result).to be_nil
    end
  end

  describe "#indexed_files" do
    before do
      store.open

      chunk1 = sample_chunk.dup
      chunk1[:file_path] = "file1.rb"
      store.insert_chunk(chunk1)

      chunk2 = sample_chunk.dup
      chunk2[:id] = "another_id"
      chunk2[:file_path] = "file2.rb"
      store.insert_chunk(chunk2)
    end

    it "returns list of indexed files" do
      files = store.indexed_files

      expect(files).to include("file1.rb", "file2.rb")
      expect(files.length).to eq(2)
    end

    it "returns sorted list" do
      files = store.indexed_files

      expect(files).to eq(files.sort)
    end
  end

  describe "FTS synchronization" do
    before { store.open }

    it "updates FTS on insert" do
      store.insert_chunk(sample_chunk)

      results = store.search_text("authenticate")
      expect(results.length).to eq(1)
    end

    it "updates FTS on delete" do
      store.insert_chunk(sample_chunk)
      store.delete_file(sample_chunk[:file_path])

      results = store.search_text("authenticate")
      expect(results).to be_empty
    end

    it "updates FTS on update" do
      store.insert_chunk(sample_chunk)

      updated = sample_chunk.merge(name: "new_method_name")
      store.insert_chunk(updated)

      old_results = store.search_text("authenticate")
      new_results = store.search_text("new_method_name")

      # Both should find the chunk (code still contains authenticate)
      expect(old_results.length).to eq(1)
      expect(new_results.length).to eq(1)
    end
  end

  describe "error handling" do
    it "auto-opens database when needed" do
      # Don't call open explicitly
      store.insert_chunk(sample_chunk)

      expect(store.open?).to be true
      expect(store.chunk_exists?(sample_chunk[:id])).to be true
    end
  end
end
