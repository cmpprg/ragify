#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing Ragify's Day 4 store capabilities
# Run this to see how the SQLite vector storage works

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ragify"
require "fileutils"
require "tmpdir"

puts "=" * 80
puts "Ragify Day 4 - SQLite Vector Storage Demonstration"
puts "=" * 80
puts

# Create a temporary directory for the demo
demo_dir = File.join(Dir.tmpdir, "ragify_store_demo_#{Time.now.to_i}")
FileUtils.mkdir_p(demo_dir)
db_path = File.join(demo_dir, ".ragify", "ragify.db")

puts "Creating demo database at: #{db_path}"
puts

# Initialize the store
store = Ragify::Store.new(db_path)

puts "Opening database and setting up schema..."
store.open
puts "✓ Database initialized"
puts

# Check stats on empty database
puts "-" * 80
puts "Empty Database Stats:"
puts "-" * 80
stats = store.stats
puts "  Total chunks: #{stats[:total_chunks]}"
puts "  Total vectors: #{stats[:total_vectors]}"
puts "  Database size: #{stats[:database_size_mb]} MB"
puts

# Sample chunks (simulating output from Day 2 chunker)
sample_chunks = [
  {
    id: "chunk_001",
    file_path: "app/models/user.rb",
    type: "class",
    name: "User",
    code: "class User < ApplicationRecord\n  has_many :posts\n  validates :email, presence: true\nend",
    context: "",
    start_line: 1,
    end_line: 4,
    comments: "# User model with authentication",
    metadata: { parent_class: "ApplicationRecord" }
  },
  {
    id: "chunk_002",
    file_path: "app/models/user.rb",
    type: "method",
    name: "authenticate",
    code: "def authenticate(password)\n  BCrypt::Password.new(password_digest) == password\nend",
    context: "class User",
    start_line: 6,
    end_line: 8,
    comments: "# Authenticate user with password",
    metadata: { visibility: "public", class_method: false }
  },
  {
    id: "chunk_003",
    file_path: "app/models/user.rb",
    type: "method",
    name: "admin?",
    code: "def admin?\n  role == 'admin'\nend",
    context: "class User",
    start_line: 10,
    end_line: 12,
    comments: "# Check if user is admin",
    metadata: { visibility: "public", class_method: false }
  },
  {
    id: "chunk_004",
    file_path: "app/controllers/users_controller.rb",
    type: "class",
    name: "UsersController",
    code: "class UsersController < ApplicationController\n  before_action :authenticate_user\nend",
    context: "",
    start_line: 1,
    end_line: 3,
    comments: "# Controller for user management",
    metadata: { parent_class: "ApplicationController" }
  },
  {
    id: "chunk_005",
    file_path: "app/controllers/users_controller.rb",
    type: "method",
    name: "index",
    code: "def index\n  @users = User.all\n  render json: @users\nend",
    context: "class UsersController",
    start_line: 5,
    end_line: 8,
    comments: "# List all users",
    metadata: { visibility: "public", class_method: false }
  }
]

# Generate fake embeddings (in real usage, these come from Ollama)
# Each embedding is 768 dimensions (nomic-embed-text)
def generate_fake_embedding(seed)
  srand(seed)
  vec = Array.new(768) { rand(-1.0..1.0) }
  # Normalize to unit length
  magnitude = Math.sqrt(vec.map { |x| x * x }.sum)
  vec.map { |x| x / magnitude }
end

puts "-" * 80
puts "Inserting Sample Chunks with Embeddings:"
puts "-" * 80
puts

# Insert chunks with embeddings
sample_chunks.each_with_index do |chunk, _i|
  embedding = generate_fake_embedding(chunk[:id].hash)
  store.insert_chunk(chunk, embedding)
  puts "  ✓ #{chunk[:type]}: #{chunk[:name]} (#{chunk[:file_path]})"
end

puts
puts "✓ Inserted #{sample_chunks.length} chunks with embeddings"
puts

# Check stats after insertion
puts "-" * 80
puts "Database Stats After Insertion:"
puts "-" * 80
stats = store.stats
puts "  Total chunks: #{stats[:total_chunks]}"
puts "  Total vectors: #{stats[:total_vectors]}"
puts "  Total files: #{stats[:total_files]}"
puts "  Chunks by type:"
stats[:chunks_by_type].each do |type, count|
  puts "    #{type}: #{count}"
end
puts "  Database size: #{stats[:database_size_mb]} MB"
puts

# Demonstrate retrieval
puts "-" * 80
puts "Retrieving Chunks:"
puts "-" * 80
puts

chunk = store.get_chunk("chunk_002")
puts "Get chunk by ID (chunk_002):"
puts "  Name: #{chunk[:name]}"
puts "  Type: #{chunk[:type]}"
puts "  Context: #{chunk[:context]}"
puts "  Lines: #{chunk[:start_line]}-#{chunk[:end_line]}"
puts

chunks = store.get_chunks_for_file("app/models/user.rb")
puts "Chunks for 'app/models/user.rb': #{chunks.length} chunks"
chunks.each do |c|
  puts "  - #{c[:type]}: #{c[:name]} (lines #{c[:start_line]}-#{c[:end_line]})"
end
puts

# Demonstrate vector similarity search
puts "-" * 80
puts "Vector Similarity Search:"
puts "-" * 80
puts

# Search with a query similar to the "authenticate" method
query_embedding = generate_fake_embedding("authenticate_query".hash)

puts "Searching for chunks similar to 'authentication' query..."
puts
results = store.search_similar(query_embedding, limit: 3)

results.each_with_index do |result, i|
  chunk = result[:chunk]
  puts "#{i + 1}. #{chunk[:name]} (#{chunk[:type]})"
  puts "   File: #{chunk[:file_path]}"
  puts "   Similarity: #{format("%.4f", result[:similarity])}"
  puts "   Code preview: #{chunk[:code].lines.first.strip}"
  puts
end

# Demonstrate text search
puts "-" * 80
puts "Full-Text Search:"
puts "-" * 80
puts

puts "Searching for 'authenticate'..."
text_results = store.search_text("authenticate")

if text_results.any?
  text_results.each do |result|
    chunk = result[:chunk]
    puts "  Found: #{chunk[:name]} (#{chunk[:type]}) - BM25 rank: #{format("%.4f", result[:rank])}"
  end
else
  puts "  No results found"
end
puts

puts "Searching for 'admin'..."
text_results = store.search_text("admin")

if text_results.any?
  text_results.each do |result|
    chunk = result[:chunk]
    puts "  Found: #{chunk[:name]} (#{chunk[:type]})"
  end
else
  puts "  No results found"
end
puts

# Demonstrate filtering
puts "-" * 80
puts "Filtered Search:"
puts "-" * 80
puts

puts "Searching for methods only..."
results = store.search_similar(query_embedding, limit: 5, filters: { type: "method" })
puts "Found #{results.length} methods:"
results.each do |result|
  puts "  - #{result[:chunk][:name]} (similarity: #{format("%.4f", result[:similarity])})"
end
puts

# Demonstrate metadata operations
puts "-" * 80
puts "Metadata Operations:"
puts "-" * 80
puts

store.set_metadata("project_name", "MyAwesomeProject")
store.set_metadata("indexed_at", Time.now.utc.iso8601)

puts "Stored metadata:"
puts "  project_name: #{store.get_metadata("project_name")}"
puts "  indexed_at: #{store.get_metadata("indexed_at")}"
puts "  last_indexed_at: #{store.get_metadata("last_indexed_at")}"
puts

# Demonstrate file deletion
puts "-" * 80
puts "File Deletion:"
puts "-" * 80
puts

puts "Deleting chunks for 'app/controllers/users_controller.rb'..."
deleted = store.delete_file("app/controllers/users_controller.rb")
puts "Deleted #{deleted} chunks"
puts

stats = store.stats
puts "Remaining chunks: #{stats[:total_chunks]}"
puts "Remaining files: #{stats[:total_files]}"
puts

# Demonstrate indexed files list
puts "-" * 80
puts "Indexed Files:"
puts "-" * 80
puts

files = store.indexed_files
puts "Currently indexed files:"
files.each do |file|
  puts "  - #{file}"
end
puts

# Close the store
store.close
puts "✓ Database closed"
puts

# Cleanup
puts "-" * 80
puts "Cleaning up demo..."
FileUtils.rm_rf(demo_dir)
puts "✓ Demo directory removed"
puts

puts "=" * 80
puts "Demonstration Complete!"
puts
puts "Key takeaways:"
puts "  • SQLite stores chunks with full metadata"
puts "  • Embeddings are stored as packed binary BLOBs (efficient)"
puts "  • Cosine similarity search implemented in Ruby"
puts "  • Full-text search via SQLite FTS5"
puts "  • Filters can be applied to searches"
puts "  • Cascading deletes keep data consistent"
puts "  • Ready for Day 5: Search command integration!"
puts "=" * 80
