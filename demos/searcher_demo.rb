#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing Ragify's Day 5 search capabilities
# Run this to see how semantic and hybrid search works

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "ragify"
require "fileutils"
require "tmpdir"

puts "=" * 80
puts "Ragify Day 5 - Search Functionality Demonstration"
puts "=" * 80
puts

# Create a temporary directory for the demo
demo_dir = File.join(Dir.tmpdir, "ragify_search_demo_#{Time.now.to_i}")
FileUtils.mkdir_p(demo_dir)
db_path = File.join(demo_dir, ".ragify", "ragify.db")

puts "Creating demo database at: #{db_path}"
puts

# Initialize components
config = Ragify::Config.new
store = Ragify::Store.new(db_path)
store.open

# Sample chunks simulating a real Ruby project
sample_chunks = [
  {
    id: "user_class_001",
    file_path: "app/models/user.rb",
    type: "class",
    name: "User",
    code: "class User < ApplicationRecord\n  has_secure_password\n  has_many :posts\n  validates :email, presence: true, uniqueness: true\nend",
    context: "",
    start_line: 1,
    end_line: 5,
    comments: "# User model with authentication and posts association",
    metadata: { parent_class: "ApplicationRecord" }
  },
  {
    id: "authenticate_001",
    file_path: "app/models/user.rb",
    type: "method",
    name: "authenticate",
    code: "def authenticate(password)\n  return false if locked?\n  BCrypt::Password.new(password_digest) == password\nend",
    context: "class User",
    start_line: 10,
    end_line: 13,
    comments: "# Authenticate user with password\n# Returns false if account is locked",
    metadata: { visibility: "public", class_method: false }
  },
  {
    id: "admin_check_001",
    file_path: "app/models/user.rb",
    type: "method",
    name: "admin?",
    code: "def admin?\n  role == 'admin' || superuser?\nend",
    context: "class User",
    start_line: 20,
    end_line: 22,
    comments: "# Check if user has admin privileges",
    metadata: { visibility: "public", class_method: false }
  },
  {
    id: "find_by_email_001",
    file_path: "app/models/user.rb",
    type: "method",
    name: "find_by_email",
    code: "def self.find_by_email(email)\n  where(email: email.downcase.strip).first\nend",
    context: "class User",
    start_line: 25,
    end_line: 27,
    comments: "# Find user by email address (case-insensitive)",
    metadata: { visibility: "public", class_method: true }
  },
  {
    id: "post_class_001",
    file_path: "app/models/post.rb",
    type: "class",
    name: "Post",
    code: "class Post < ApplicationRecord\n  belongs_to :user\n  has_many :comments\n  validates :title, :body, presence: true\nend",
    context: "",
    start_line: 1,
    end_line: 5,
    comments: "# Blog post model",
    metadata: { parent_class: "ApplicationRecord" }
  },
  {
    id: "publish_001",
    file_path: "app/models/post.rb",
    type: "method",
    name: "publish!",
    code: "def publish!\n  update!(\n    published: true,\n    published_at: Time.current\n  )\n  notify_subscribers\nend",
    context: "class Post",
    start_line: 10,
    end_line: 16,
    comments: "# Publish the post and notify subscribers",
    metadata: { visibility: "public", class_method: false }
  },
  {
    id: "recent_posts_001",
    file_path: "app/models/post.rb",
    type: "method",
    name: "recent",
    code: "def self.recent(limit = 10)\n  where(published: true)\n    .order(published_at: :desc)\n    .limit(limit)\nend",
    context: "class Post",
    start_line: 20,
    end_line: 24,
    comments: "# Get recent published posts",
    metadata: { visibility: "public", class_method: true }
  },
  {
    id: "sessions_controller_001",
    file_path: "app/controllers/sessions_controller.rb",
    type: "class",
    name: "SessionsController",
    code: "class SessionsController < ApplicationController\n  skip_before_action :require_login, only: [:new, :create]\nend",
    context: "",
    start_line: 1,
    end_line: 3,
    comments: "# Controller for user sessions (login/logout)",
    metadata: { parent_class: "ApplicationController" }
  },
  {
    id: "login_create_001",
    file_path: "app/controllers/sessions_controller.rb",
    type: "method",
    name: "create",
    code: "def create\n  user = User.find_by_email(params[:email])\n  if user&.authenticate(params[:password])\n    session[:user_id] = user.id\n    redirect_to dashboard_path\n  else\n    flash.now[:error] = 'Invalid credentials'\n    render :new\n  end\nend",
    context: "class SessionsController",
    start_line: 10,
    end_line: 19,
    comments: "# Handle login form submission",
    metadata: { visibility: "public", class_method: false }
  },
  {
    id: "api_auth_001",
    file_path: "app/controllers/api/v1/base_controller.rb",
    type: "method",
    name: "authenticate_api_request",
    code: "def authenticate_api_request\n  token = request.headers['Authorization']&.split(' ')&.last\n  @current_user = User.find_by_api_token(token)\n  render_unauthorized unless @current_user\nend",
    context: "class Api::V1::BaseController",
    start_line: 15,
    end_line: 19,
    comments: "# Authenticate API requests via Bearer token",
    metadata: { visibility: "private", class_method: false }
  }
]

# Generate fake embeddings for demo
def generate_embedding(seed)
  srand(seed)
  vec = Array.new(768) { rand(-1.0..1.0) }
  magnitude = Math.sqrt(vec.map { |x| x * x }.sum)
  vec.map { |x| x / magnitude }
end

puts "-" * 80
puts "Inserting sample chunks (simulating indexed codebase)..."
puts "-" * 80
puts

sample_chunks.each_with_index do |chunk, i|
  embedding = generate_embedding(chunk[:id].hash)
  store.insert_chunk(chunk, embedding)
  puts "  ✓ #{chunk[:type]}: #{chunk[:name]} (#{chunk[:file_path]})"
end

puts
puts "✓ Inserted #{sample_chunks.length} chunks with embeddings"
puts

# Initialize embedder and searcher
embedder = Ragify::Embedder.new(config)
searcher = Ragify::Searcher.new(store, embedder, config)

# Check if Ollama is available
ollama_available = searcher.semantic_available?

puts "-" * 80
puts "Search Capabilities:"
puts "-" * 80
if ollama_available
  puts "  ✓ Semantic search: available (Ollama running)"
  puts "  ✓ Hybrid search: available"
  puts "  ✓ Text search: available"
else
  puts "  ✗ Semantic search: unavailable (Ollama not running)"
  puts "  ✗ Hybrid search: will fall back to text search"
  puts "  ✓ Text search: available"
end
puts

# Demo searches
puts "=" * 80
puts "Search Demonstrations"
puts "=" * 80
puts

# Search 1: Text search for "authenticate"
puts "-" * 80
puts "Search 1: Text search for 'authenticate'"
puts "-" * 80
puts

results = searcher.search("authenticate", mode: :text, limit: 3)
puts searcher.format_results(results, format: :plain)

# Search 2: Filter by type
puts "-" * 80
puts "Search 2: Search for 'user' filtered to classes only"
puts "-" * 80
puts

results = searcher.search("user", mode: :text, type: "class", limit: 3)
puts searcher.format_results(results, format: :plain)

# Search 3: Filter by path
puts "-" * 80
puts "Search 3: Search for 'create' in controllers"
puts "-" * 80
puts

results = searcher.search("create", mode: :text, path_filter: "controller", limit: 3)
puts searcher.format_results(results, format: :plain)

# Search 4: JSON output
puts "-" * 80
puts "Search 4: JSON output format"
puts "-" * 80
puts

results = searcher.search("publish", mode: :text, limit: 2)
puts searcher.format_results(results, format: :json)
puts

# Search 5: Semantic/Hybrid search (if available)
if ollama_available
  puts "-" * 80
  puts "Search 5: Hybrid search for 'how do users log in'"
  puts "-" * 80
  puts

  results = searcher.search("how do users log in", mode: :hybrid, limit: 3)
  puts searcher.format_results(results, format: :plain)

  puts "-" * 80
  puts "Search 6: Semantic search for 'password verification'"
  puts "-" * 80
  puts

  results = searcher.search("password verification", mode: :semantic, limit: 3)
  puts searcher.format_results(results, format: :plain)
else
  puts "-" * 80
  puts "Search 5 & 6: Skipped (Ollama not available)"
  puts "-" * 80
  puts
  puts "To enable semantic search:"
  puts "  1. Install Ollama: https://ollama.com"
  puts "  2. Start Ollama: ollama serve"
  puts "  3. Pull model: ollama pull nomic-embed-text"
  puts
end

# Cleanup
store.close
FileUtils.rm_rf(demo_dir)

puts "=" * 80
puts "Demonstration Complete!"
puts "=" * 80
puts
puts "Key features demonstrated:"
puts "  • Text search with BM25 ranking"
puts "  • Filtering by chunk type (class, method, module)"
puts "  • Filtering by file path pattern"
puts "  • Multiple output formats (plain, colorized, JSON)"
if ollama_available
  puts "  • Semantic search using Ollama embeddings"
  puts "  • Hybrid search combining semantic + text"
end
puts
puts "Try it on your own project:"
puts "  cd /path/to/your/ruby/project"
puts "  ragify init"
puts "  ragify index"
puts "  ragify search 'authentication'"
puts "  ragify search 'database queries' --type method"
puts "  ragify search 'api' --path controllers --format json"
puts "=" * 80
