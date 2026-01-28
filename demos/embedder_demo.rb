#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing Ragify's Day 3 embedder capabilities
# Run this to see how the embedder generates vector embeddings

require_relative "../lib/ragify"

puts "=" * 80
puts "Ragify Day 3 - Embedder Demonstration"
puts "=" * 80
puts

# Initialize config and embedder
config = Ragify::Config.new
embedder = Ragify::Embedder.new(config)

# Check Ollama availability
puts "Checking Ollama..."
if embedder.ollama_available?
  puts "✓ Ollama is running at #{embedder.ollama_url}"

  if embedder.model_available?
    puts "✓ Model '#{embedder.model}' is available"
  else
    puts "✗ Model '#{embedder.model}' not found"
    puts "  Run: ollama pull #{embedder.model}"
    exit 1
  end
else
  puts "✗ Ollama is not running"
  puts "  Install from: https://ollama.com"
  puts "  Then run: ollama serve"
  exit 1
end

puts

# Sample chunks from Day 2 chunker
sample_chunks = [
  {
    type: "method",
    name: "authenticate",
    context: "class User",
    comments: "# Authenticate the user with password\n# @param password [String] The password to check\n# @return [Boolean] Whether authentication succeeded",
    code: "def authenticate(password)\n  BCrypt::Password.new(@password_digest) == password\nend"
  },
  {
    type: "class",
    name: "User",
    context: "",
    comments: "# User model with authentication",
    code: "class User < ApplicationRecord\n  # User constants\n  ADMIN_ROLE = \"admin\"\nend"
  },
  {
    type: "method",
    name: "find_by_email",
    context: "class User",
    comments: "# Class method to find user by email",
    code: "def self.find_by_email(email)\n  User.where(email: email).first\nend"
  }
]

puts "Preparing chunks for embedding..."
puts "-" * 80

# Prepare and show formatted text
prepared_texts = sample_chunks.map do |chunk|
  text = embedder.prepare_chunk_text(chunk)
  puts "\nChunk: #{chunk[:type]} #{chunk[:name]}"
  puts "Formatted text:"
  puts text.lines.first(3).map { |l| "  #{l}" }.join
  puts "  ..." if text.lines.count > 3
  text
end

puts
puts "-" * 80
puts

# Generate embeddings
puts "Generating embeddings..."
puts

begin
  embeddings = embedder.embed_batch(
    prepared_texts,
    batch_size: 5,
    show_progress: true
  )

  puts
  puts "✓ Generated #{embeddings.length} embeddings"
  puts

  # Show embedding details
  embeddings.each_with_index do |embedding, i|
    chunk = sample_chunks[i]
    puts "Embedding #{i + 1} (#{chunk[:type]} #{chunk[:name]}):"
    puts "  Dimensions: #{embedding.length}"
    puts "  First 5 values: #{embedding.first(5).map { |v| format("%.4f", v) }.join(", ")}"
    puts "  Min: #{format("%.4f", embedding.min)}, Max: #{format("%.4f", embedding.max)}"
    puts
  end

  # Cache statistics
  stats = embedder.cache_stats
  puts "-" * 80
  puts "Cache Statistics:"
  puts "  Cached embeddings: #{stats[:size]}"
  puts "  Memory usage: ~#{stats[:memory_kb]} KB"
  puts

  # Test cache hit
  puts "Testing cache (re-embedding first chunk)..."
  cached_embedding = embedder.embed(prepared_texts[0])
  if cached_embedding == embeddings[0]
    puts "✓ Cache hit! Retrieved from cache without API call"
  else
    puts "✗ Cache miss - this shouldn't happen"
  end

  puts
  puts "=" * 80
  puts "Demonstration Complete!"
  puts
  puts "Key takeaways:"
  puts "  • Embeddings are 768-dimensional vectors (nomic-embed-text)"
  puts "  • Each chunk gets a unique embedding based on code + context"
  puts "  • Caching prevents duplicate API calls"
  puts "  • Batch processing with progress tracking"
  puts "  • Ready for Day 4: Store these embeddings in SQLite!"
  puts "=" * 80
rescue Ragify::OllamaConnectionError => e
  puts "✗ Connection Error: #{e.message}"
  puts
  puts "Make sure Ollama is running:"
  puts "  ollama serve"
  exit 1
rescue Ragify::OllamaError => e
  puts "✗ Ollama Error: #{e.message}"
  exit 1
rescue StandardError => e
  puts "✗ Error: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end
