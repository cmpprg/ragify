# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe Ragify::Searcher do
  let(:temp_dir) { Dir.mktmpdir }
  let(:db_path) { File.join(temp_dir, ".ragify", "ragify.db") }
  let(:store) { Ragify::Store.new(db_path) }
  let(:config) do
    Ragify::Config.new({
                         "ollama_url" => "http://localhost:11434",
                         "model" => "nomic-embed-text",
                         "search_result_limit" => 5
                       })
  end
  let(:embedder) { Ragify::Embedder.new(config) }
  let(:searcher) { described_class.new(store, embedder, config) }

  # Sample chunks for testing
  let(:chunk1) do
    {
      id: "chunk_auth_001",
      file_path: "app/models/user.rb",
      type: "method",
      name: "authenticate",
      code: "def authenticate(password)\n  BCrypt::Password.new(password_digest) == password\nend",
      context: "class User",
      start_line: 10,
      end_line: 12,
      comments: "# Authenticate user with password",
      metadata: { visibility: "public" }
    }
  end

  let(:chunk2) do
    {
      id: "chunk_user_002",
      file_path: "app/models/user.rb",
      type: "class",
      name: "User",
      code: "class User < ApplicationRecord\n  has_secure_password\nend",
      context: "",
      start_line: 1,
      end_line: 20,
      comments: "# User model with authentication",
      metadata: { parent_class: "ApplicationRecord" }
    }
  end

  let(:chunk3) do
    {
      id: "chunk_post_003",
      file_path: "app/models/post.rb",
      type: "method",
      name: "publish",
      code: "def publish\n  update(published: true)\nend",
      context: "class Post",
      start_line: 15,
      end_line: 17,
      comments: "# Publish the post",
      metadata: { visibility: "public" }
    }
  end

  let(:chunk4) do
    {
      id: "chunk_admin_004",
      file_path: "app/models/user.rb",
      type: "method",
      name: "admin?",
      code: "def admin?\n  role == 'admin'\nend",
      context: "class User",
      start_line: 25,
      end_line: 27,
      comments: "# Check if user is admin",
      metadata: { visibility: "public" }
    }
  end

  # Helper to generate normalized fake embeddings
  def generate_embedding(seed)
    srand(seed)
    vec = Array.new(768) { rand(-1.0..1.0) }
    magnitude = Math.sqrt(vec.map { |x| x * x }.sum)
    vec.map { |x| x / magnitude }
  end

  before do
    store.open

    # Insert test chunks with embeddings
    store.insert_chunk(chunk1, generate_embedding(1001))
    store.insert_chunk(chunk2, generate_embedding(1002))
    store.insert_chunk(chunk3, generate_embedding(1003))
    store.insert_chunk(chunk4, generate_embedding(1004))
  end

  after do
    store.close
    FileUtils.rm_rf(temp_dir)
  end

  describe "#initialize" do
    it "sets store, embedder, and config" do
      expect(searcher.store).to eq(store)
      expect(searcher.embedder).to eq(embedder)
      expect(searcher.config).to eq(config)
    end
  end

  describe "#search" do
    context "argument validation" do
      it "raises error for nil query" do
        expect { searcher.search(nil) }.to raise_error(ArgumentError, /cannot be empty/)
      end

      it "raises error for empty query" do
        expect { searcher.search("") }.to raise_error(ArgumentError, /cannot be empty/)
        expect { searcher.search("   ") }.to raise_error(ArgumentError, /cannot be empty/)
      end

      it "raises error for unknown search mode" do
        expect { searcher.search("test", mode: :unknown) }.to raise_error(ArgumentError, /Unknown search mode/)
      end
    end

    context "text search mode" do
      it "returns results matching query" do
        results = searcher.search("authenticate", mode: :text)

        expect(results).to be_an(Array)
        expect(results).not_to be_empty
        expect(results.first[:chunk][:name]).to eq("authenticate")
      end

      it "respects limit parameter" do
        results = searcher.search("user", mode: :text, limit: 2)

        expect(results.length).to be <= 2
      end

      it "filters by type" do
        results = searcher.search("user", mode: :text, type: "class")

        results.each do |result|
          expect(result[:chunk][:type]).to eq("class")
        end
      end

      it "filters by path" do
        results = searcher.search("publish", mode: :text, path_filter: "post")

        results.each do |result|
          expect(result[:chunk][:file_path]).to include("post")
        end
      end

      it "applies minimum score filter" do
        results = searcher.search("user", mode: :text, min_score: 0.9)

        results.each do |result|
          expect(result[:score]).to be >= 0.9
        end
      end

      it "returns empty array when no matches" do
        results = searcher.search("nonexistent_xyz_123", mode: :text)

        expect(results).to eq([])
      end

      it "includes search_type in results" do
        results = searcher.search("authenticate", mode: :text)

        expect(results.first[:search_type]).to eq(:text)
      end
    end

    context "with default limit from config" do
      it "uses config search_result_limit when limit not specified" do
        # Config has search_result_limit: 5
        results = searcher.search("user", mode: :text)

        expect(results.length).to be <= 5
      end
    end

    context "with custom vector_weight" do
      it "accepts vector_weight parameter" do
        # Should not raise error
        results = searcher.search("user", mode: :text, vector_weight: 0.5)
        expect(results).to be_an(Array)
      end

      it "uses default vector_weight when not specified" do
        # Default is 0.7 - this just verifies no error
        results = searcher.search("user", mode: :text)
        expect(results).to be_an(Array)
      end
    end
  end

  describe "#semantic_available?" do
    context "without embedder" do
      let(:searcher_no_embedder) { described_class.new(store, nil, config) }

      it "returns false when embedder is nil" do
        expect(searcher_no_embedder.semantic_available?).to be false
      end
    end

    # Integration test for actual Ollama availability
    context "with embedder", :ollama_required do
      it "returns true when Ollama is running and model available" do
        skip "Ollama not available" unless embedder.ollama_available?
        skip "Model not available" unless embedder.model_available?

        expect(searcher.semantic_available?).to be true
      end
    end
  end

  describe "#format_results" do
    let(:sample_results) do
      [
        {
          chunk: chunk1,
          score: 0.85,
          search_type: :text
        },
        {
          chunk: chunk3,
          score: 0.65,
          search_type: :text
        }
      ]
    end

    context "with empty results" do
      it "returns empty string" do
        output = searcher.format_results([])
        expect(output).to eq("")
      end
    end

    context "with plain format" do
      it "formats results as plain text" do
        output = searcher.format_results(sample_results, format: :plain)

        expect(output).to include("1. authenticate (method)")
        expect(output).to include("File: app/models/user.rb:10-12")
        expect(output).to include("Score: 0.8500")
        expect(output).to include("def authenticate(password)")
      end

      it "includes context when present" do
        output = searcher.format_results(sample_results, format: :plain)

        expect(output).to include("Context: class User")
      end

      it "includes rank numbers" do
        output = searcher.format_results(sample_results, format: :plain)

        expect(output).to include("1.")
        expect(output).to include("2.")
      end
    end

    context "with json format" do
      it "returns valid JSON" do
        output = searcher.format_results(sample_results, format: :json)

        parsed = JSON.parse(output)
        expect(parsed).to be_an(Array)
        expect(parsed.length).to eq(2)
      end

      it "includes required fields" do
        output = searcher.format_results(sample_results, format: :json)

        parsed = JSON.parse(output)
        first = parsed.first

        expect(first).to include(
          "file_path" => "app/models/user.rb",
          "type" => "method",
          "name" => "authenticate"
        )
        expect(first["score"]).to eq(0.85)
        expect(first["start_line"]).to eq(10)
        expect(first["end_line"]).to eq(12)
      end
    end

    context "with colorized format" do
      it "returns formatted output" do
        output = searcher.format_results(sample_results, format: :colorized)

        # Check content is present (colors are ANSI codes)
        expect(output).to include("authenticate")
        expect(output).to include("method")
        expect(output).to include("app/models/user.rb")
      end
    end

    context "with long code" do
      it "truncates code to 10 lines" do
        long_code = (1..20).map { |i| "  line #{i}" }.join("\n")
        chunk_with_long_code = chunk1.merge(code: long_code)
        results = [{ chunk: chunk_with_long_code, score: 0.9, search_type: :text }]

        output = searcher.format_results(results, format: :plain)

        expect(output).to include("line 1")
        expect(output).to include("line 10")
        expect(output).to include("10 more lines")
        expect(output).not_to include("line 15")
      end
    end
  end

  describe "result normalization" do
    context "text search results" do
      it "normalizes BM25 scores to positive values" do
        results = searcher.search("authenticate", mode: :text)

        results.each do |result|
          expect(result[:score]).to be >= 0
          expect(result[:score]).to be <= 1
        end
      end
    end
  end

  describe "filter combinations" do
    it "applies multiple filters together" do
      results = searcher.search("user", mode: :text, type: "method", path_filter: "user.rb")

      results.each do |result|
        expect(result[:chunk][:type]).to eq("method")
        expect(result[:chunk][:file_path]).to include("user.rb")
      end
    end
  end

  # Integration tests requiring Ollama
  describe "semantic search", :ollama_required do
    before do
      skip "Ollama not available" unless embedder.ollama_available?
      skip "Model not available" unless embedder.model_available?
    end

    it "performs semantic search" do
      results = searcher.search("password verification", mode: :semantic)

      expect(results).to be_an(Array)
      # Should find authenticate method as most relevant
      names = results.map { |r| r[:chunk][:name] }
      expect(names).to include("authenticate")
    end

    it "includes similarity score" do
      results = searcher.search("user login", mode: :semantic)

      results.each do |result|
        expect(result[:score]).to be_a(Numeric)
        expect(result[:score]).to be_between(-1.0, 1.0)
      end
    end
  end

  describe "hybrid search", :ollama_required do
    before do
      skip "Ollama not available" unless embedder.ollama_available?
      skip "Model not available" unless embedder.model_available?
    end

    it "combines semantic and text search" do
      results = searcher.search("authenticate", mode: :hybrid)

      expect(results).to be_an(Array)
      expect(results).not_to be_empty
      # With real embeddings, authenticate should be in results
      names = results.map { |r| r[:chunk][:name] }
      expect(names).to include("authenticate")
    end

    it "includes sub-scores when available" do
      results = searcher.search("user authentication", mode: :hybrid)

      # Hybrid results should have vector_score and text_score
      result = results.first
      expect(result).to have_key(:vector_score)
      expect(result).to have_key(:text_score)
    end

    it "accepts custom vector_weight" do
      # More weight on text search (0.3 vector, 0.7 text)
      results = searcher.search("authenticate", mode: :hybrid, vector_weight: 0.3)

      expect(results).to be_an(Array)
      expect(results).not_to be_empty
    end
  end

  describe "fallback behavior" do
    context "when semantic unavailable for hybrid search" do
      let(:searcher_no_ollama) do
        # Create embedder that will report unavailable
        mock_embedder = instance_double(Ragify::Embedder)
        allow(mock_embedder).to receive(:ollama_available?).and_return(false)
        allow(mock_embedder).to receive(:model_available?).and_return(false)

        described_class.new(store, mock_embedder, config)
      end

      it "falls back to text search" do
        results = searcher_no_ollama.search("authenticate", mode: :hybrid)

        # Should still return results via text search
        expect(results).not_to be_empty
        expect(results.first[:search_type]).to eq(:text)
      end
    end

    context "when semantic explicitly requested but unavailable" do
      let(:searcher_no_ollama) do
        mock_embedder = instance_double(Ragify::Embedder)
        allow(mock_embedder).to receive(:ollama_available?).and_return(false)
        allow(mock_embedder).to receive(:model_available?).and_return(false)

        described_class.new(store, mock_embedder, config)
      end

      it "raises SearchError" do
        expect do
          searcher_no_ollama.search("test", mode: :semantic)
        end.to raise_error(Ragify::SearchError, /unavailable/)
      end
    end
  end
end

RSpec.describe Ragify::SearchError do
  it "is a StandardError" do
    expect(described_class.new).to be_a(StandardError)
  end

  it "accepts a message" do
    error = described_class.new("test message")
    expect(error.message).to eq("test message")
  end
end
