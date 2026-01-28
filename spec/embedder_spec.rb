# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragify::Embedder do
  let(:config) do
    Ragify::Config.new({
                         "ollama_url" => "http://localhost:11434",
                         "model" => "nomic-embed-text"
                       })
  end
  let(:embedder) { described_class.new(config) }

  describe "#initialize" do
    it "sets configuration correctly" do
      expect(embedder.config).to eq(config)
      expect(embedder.ollama_url).to eq("http://localhost:11434")
      expect(embedder.model).to eq("nomic-embed-text")
      expect(embedder.cache).to eq({})
    end
  end

  describe "#prepare_chunk_text" do
    it "formats a simple method chunk" do
      chunk = {
        type: "method",
        name: "authenticate",
        context: "class User",
        comments: "# Authenticate the user",
        code: "def authenticate(password)\n  verify(password)\nend"
      }

      text = embedder.prepare_chunk_text(chunk)

      expect(text).to include("In class User,")
      expect(text).to include("method authenticate:")
      expect(text).to include("# Authenticate the user")
      expect(text).to include("def authenticate(password)")
    end

    it "formats a class chunk without context" do
      chunk = {
        type: "class",
        name: "User",
        context: "",
        comments: "# User model",
        code: "class User\nend"
      }

      text = embedder.prepare_chunk_text(chunk)

      expect(text).not_to include("In ")
      expect(text).to include("class User:")
      expect(text).to include("# User model")
    end

    it "formats a chunk without comments" do
      chunk = {
        type: "method",
        name: "simple",
        context: "class Example",
        comments: "",
        code: "def simple\n  puts 'hello'\nend"
      }

      text = embedder.prepare_chunk_text(chunk)

      expect(text).to include("method simple:")
      expect(text).to include("def simple")
    end

    it "formats nested context correctly" do
      chunk = {
        type: "method",
        name: "reply",
        context: "module Blog > class Post > class Comment",
        comments: "",
        code: "def reply\n  # code\nend"
      }

      text = embedder.prepare_chunk_text(chunk)

      expect(text).to include("In module Blog > class Post > class Comment,")
    end
  end

  describe "#cache_stats" do
    it "returns cache statistics" do
      stats = embedder.cache_stats

      expect(stats).to have_key(:size)
      expect(stats).to have_key(:memory_kb)
      expect(stats[:size]).to eq(0)
    end

    it "updates after caching embeddings" do
      # Manually add to cache for testing
      embedder.cache["test_key"] = [0.1] * 768

      stats = embedder.cache_stats
      expect(stats[:size]).to eq(1)
    end
  end

  describe "#clear_cache" do
    it "clears the cache" do
      embedder.cache["test"] = [0.1] * 768
      expect(embedder.cache.size).to eq(1)

      embedder.clear_cache

      expect(embedder.cache.size).to eq(0)
    end
  end

  describe "#embed" do
    it "raises error for nil text" do
      expect { embedder.embed(nil) }.to raise_error(ArgumentError, /cannot be nil/)
    end

    it "raises error for empty text" do
      expect { embedder.embed("") }.to raise_error(ArgumentError, /cannot be nil/)
      expect { embedder.embed("   ") }.to raise_error(ArgumentError, /cannot be nil/)
    end
  end

  describe "#embed_batch" do
    it "raises error for non-array input" do
      expect { embedder.embed_batch("not an array") }.to raise_error(ArgumentError, /must be an array/)
    end

    it "returns empty array for empty input" do
      expect(embedder.embed_batch([])).to eq([])
    end
  end

  describe "error handling" do
    describe "OllamaError" do
      it "is a StandardError" do
        expect(Ragify::OllamaError.new).to be_a(StandardError)
      end
    end

    describe "OllamaConnectionError" do
      it "is an OllamaError" do
        expect(Ragify::OllamaConnectionError.new).to be_a(Ragify::OllamaError)
      end
    end

    describe "OllamaTimeoutError" do
      it "is an OllamaError" do
        expect(Ragify::OllamaTimeoutError.new).to be_a(Ragify::OllamaError)
      end
    end
  end

  # Integration tests (only run if Ollama is available)
  context "with Ollama running", :ollama_required do
    before do
      skip "Ollama not available" unless embedder.ollama_available?
      skip "Model not available" unless embedder.model_available?
    end

    describe "#embed" do
      it "generates embeddings for simple text" do
        text = "def hello\n  puts 'world'\nend"
        embedding = embedder.embed(text)

        expect(embedding).to be_an(Array)
        expect(embedding.length).to eq(768)
        expect(embedding).to all(be_a(Numeric))
      end

      it "uses cache for identical text" do
        text = "def test\nend"

        # First call - generates embedding
        embedding1 = embedder.embed(text)

        # Second call - uses cache
        embedding2 = embedder.embed(text)

        expect(embedding2).to eq(embedding1)
        expect(embedder.cache_stats[:size]).to eq(1)
      end

      it "generates different embeddings for different text" do
        text1 = "def foo\nend"
        text2 = "def bar\nend"

        embedding1 = embedder.embed(text1)
        embedding2 = embedder.embed(text2)

        expect(embedding1).not_to eq(embedding2)
      end
    end

    describe "#embed_batch" do
      it "generates embeddings for multiple texts" do
        texts = [
          "def method1\nend",
          "def method2\nend",
          "def method3\nend"
        ]

        embeddings = embedder.embed_batch(texts)

        expect(embeddings.length).to eq(3)
        expect(embeddings).to all(be_an(Array))
        expect(embeddings).to all(satisfy { |e| e.length == 768 })
      end

      it "respects batch size" do
        texts = (1..10).map { |i| "def method#{i}\nend" }

        # With batch size of 3, should process in chunks
        embeddings = embedder.embed_batch(texts, batch_size: 3)

        expect(embeddings.length).to eq(10)
      end
    end

    describe "#ollama_available?" do
      it "returns true when Ollama is running" do
        expect(embedder.ollama_available?).to be true
      end
    end

    describe "#model_available?" do
      it "returns true for nomic-embed-text" do
        expect(embedder.model_available?).to be true
      end
    end
  end
end
