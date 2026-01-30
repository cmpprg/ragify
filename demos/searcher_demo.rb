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

sample_chunks.each_with_index do |chunk, _i|
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

# =============================================================================
# BASIC SEARCHES
# =============================================================================

puts "-" * 80
puts "1. BASIC TEXT SEARCH"
puts "   CLI: ragify search 'authenticate' --text"
puts "-" * 80
puts

results = searcher.search("authenticate", mode: :text, limit: 3)
puts searcher.format_results(results, format: :plain)

# =============================================================================
# LIMIT FLAG (-l, --limit)
# =============================================================================

puts "-" * 80
puts "2. LIMIT RESULTS (-l, --limit)"
puts "   CLI: ragify search 'user' --limit 2"
puts "-" * 80
puts

results = searcher.search("user", mode: :text, limit: 2)
puts searcher.format_results(results, format: :plain)

# =============================================================================
# TYPE FILTER (-t, --type)
# =============================================================================

puts "-" * 80
puts "3. FILTER BY TYPE (-t, --type)"
puts "   CLI: ragify search 'user' --type class"
puts "   Valid types: method, class, module, constant"
puts "-" * 80
puts

results = searcher.search("user", mode: :text, type: "class", limit: 3)
puts searcher.format_results(results, format: :plain)

puts "-" * 80
puts "   CLI: ragify search 'user' --type method"
puts "-" * 80
puts

results = searcher.search("user", mode: :text, type: "method", limit: 3)
puts searcher.format_results(results, format: :plain)

# =============================================================================
# PATH FILTER (-p, --path)
# =============================================================================

puts "-" * 80
puts "4. FILTER BY PATH (-p, --path)"
puts "   CLI: ragify search 'create' --path controllers"
puts "-" * 80
puts

results = searcher.search("create", mode: :text, path_filter: "controller", limit: 3)
puts searcher.format_results(results, format: :plain)

puts "-" * 80
puts "   CLI: ragify search 'find' --path models"
puts "-" * 80
puts

results = searcher.search("find", mode: :text, path_filter: "models", limit: 3)
puts searcher.format_results(results, format: :plain)

# =============================================================================
# MIN SCORE FILTER (-m, --min-score)
# =============================================================================

puts "-" * 80
puts "5. MINIMUM SCORE FILTER (-m, --min-score)"
puts "   CLI: ragify search 'user' --min-score 0.3"
puts "   Only returns results with score >= threshold"
puts "-" * 80
puts

results = searcher.search("user", mode: :text, min_score: 0.3, limit: 5)
if results.empty?
  puts "   No results above score threshold 0.3"
else
  puts searcher.format_results(results, format: :plain)
end
puts

# =============================================================================
# OUTPUT FORMATS (-f, --format)
# =============================================================================

puts "-" * 80
puts "6. OUTPUT FORMATS (-f, --format)"
puts "-" * 80
puts

puts "   6a. Plain text format (--format plain)"
puts "   CLI: ragify search 'publish' --format plain"
puts
results = searcher.search("publish", mode: :text, limit: 1)
puts searcher.format_results(results, format: :plain)

puts "   6b. JSON format (--format json)"
puts "   CLI: ragify search 'publish' --format json"
puts
results = searcher.search("publish", mode: :text, limit: 2)
puts searcher.format_results(results, format: :json)
puts

puts "   6c. Colorized format (--format colorized) [default]"
puts "   CLI: ragify search 'publish'"
puts
results = searcher.search("publish", mode: :text, limit: 1)
puts searcher.format_results(results, format: :colorized)

# =============================================================================
# COMBINED FILTERS
# =============================================================================

puts "-" * 80
puts "7. COMBINED FILTERS"
puts "   CLI: ragify search 'user' --type method --path models --limit 3"
puts "-" * 80
puts

results = searcher.search("user", mode: :text, type: "method", path_filter: "models", limit: 3)
puts searcher.format_results(results, format: :plain)

# =============================================================================
# SEARCH MODES (--text, --semantic, default hybrid)
# =============================================================================

puts "-" * 80
puts "8. SEARCH MODES"
puts "-" * 80
puts

puts "   8a. Text-only search (--text)"
puts "   CLI: ragify search 'authenticate' --text"
puts "   Uses SQLite FTS5 full-text search (no Ollama required)"
puts
results = searcher.search("authenticate", mode: :text, limit: 2)
puts searcher.format_results(results, format: :plain)

if ollama_available
  puts "   8b. Semantic-only search (--semantic)"
  puts "   CLI: ragify search 'password verification' --semantic"
  puts "   Uses Ollama embeddings for meaning-based search"
  puts
  results = searcher.search("password verification", mode: :semantic, limit: 2)
  puts searcher.format_results(results, format: :plain)

  puts "   8c. Hybrid search [default]"
  puts "   CLI: ragify search 'how do users log in'"
  puts "   Combines semantic (70%) + text (30%) for best results"
  puts
  results = searcher.search("how do users log in", mode: :hybrid, limit: 2)
  puts searcher.format_results(results, format: :plain)
else
  puts "   8b. Semantic-only search (--semantic)"
  puts "   SKIPPED: Ollama not available"
  puts
  puts "   8c. Hybrid search [default]"
  puts "   SKIPPED: Ollama not available (would fall back to text search)"
  puts
end

# =============================================================================
# VECTOR WEIGHT (-w, --vector-weight)
# =============================================================================

puts "-" * 80
puts "9. VECTOR WEIGHT FOR HYBRID SEARCH (-w, --vector-weight)"
puts "   Adjusts balance between semantic and text search"
puts "   Default: 0.7 (70% semantic, 30% text)"
puts "-" * 80
puts

if ollama_available
  puts "   9a. Default weight (0.7 = 70% semantic, 30% text)"
  puts "   CLI: ragify search 'authentication'"
  puts
  results = searcher.search("authentication", mode: :hybrid, vector_weight: 0.7, limit: 2)
  puts searcher.format_results(results, format: :plain)

  puts "   9b. High semantic weight (0.9 = 90% semantic, 10% text)"
  puts "   CLI: ragify search 'authentication' --vector-weight 0.9"
  puts "   Best for natural language queries"
  puts
  results = searcher.search("how does login work", mode: :hybrid, vector_weight: 0.9, limit: 2)
  puts searcher.format_results(results, format: :plain)

  puts "   9c. Balanced weight (0.5 = 50% semantic, 50% text)"
  puts "   CLI: ragify search 'authentication' -w 0.5"
  puts
  results = searcher.search("authentication", mode: :hybrid, vector_weight: 0.5, limit: 2)
  puts searcher.format_results(results, format: :plain)

  puts "   9d. High text weight (0.3 = 30% semantic, 70% text)"
  puts "   CLI: ragify search 'find_by_email' --vector-weight 0.3"
  puts "   Best for exact method/class name searches"
  puts
  results = searcher.search("find_by_email", mode: :hybrid, vector_weight: 0.3, limit: 2)
  puts searcher.format_results(results, format: :plain)
else
  puts "   SKIPPED: Ollama not available"
  puts "   Vector weight only applies to hybrid search mode"
  puts
  puts "   To enable:"
  puts "     1. Install Ollama: https://ollama.com"
  puts "     2. Start Ollama: ollama serve"
  puts "     3. Pull model: ollama pull nomic-embed-text"
  puts
end

# =============================================================================
# COMPLETE EXAMPLES
# =============================================================================

puts "-" * 80
puts "10. COMPLETE EXAMPLES WITH ALL FLAGS"
puts "-" * 80
puts

puts "   Example 1: Find authentication methods in models"
puts "   CLI: ragify search 'auth' --type method --path models --limit 5 --format json"
puts
results = searcher.search("auth", mode: :text, type: "method", path_filter: "models", limit: 3)
puts searcher.format_results(results, format: :json)
puts

if ollama_available
  puts "   Example 2: Natural language query with custom vector weight"
  puts "   CLI: ragify search 'how to check admin permissions' -w 0.8 -l 3"
  puts
  results = searcher.search("how to check admin permissions", mode: :hybrid, vector_weight: 0.8, limit: 3)
  puts searcher.format_results(results, format: :plain)
end

# Cleanup
store.close
FileUtils.rm_rf(demo_dir)

puts "=" * 80
puts "Demonstration Complete!"
puts "=" * 80
puts
puts "ALL AVAILABLE FLAGS:"
puts
puts "  -l, --limit N          Number of results (default: 5)"
puts "  -t, --type TYPE        Filter by type: method, class, module, constant"
puts "  -p, --path PATTERN     Filter by file path pattern"
puts "  -m, --min-score N      Minimum similarity score (0.0-1.0)"
puts "  -w, --vector-weight N  Vector weight for hybrid search (0.0-1.0, default: 0.7)"
puts "  -f, --format FORMAT    Output format: colorized, plain, json"
puts "      --semantic         Use semantic search only (requires Ollama)"
puts "      --text             Use text search only (no Ollama required)"
puts
puts "QUICK START:"
puts
puts "  cd /path/to/your/ruby/project"
puts "  ragify init"
puts "  ragify index"
puts
puts "EXAMPLE COMMANDS:"
puts
puts "  # Basic search"
puts "  ragify search 'authentication'"
puts
puts "  # Filter by type"
puts "  ragify search 'user' --type method"
puts "  ragify search 'model' --type class"
puts
puts "  # Filter by path"
puts "  ragify search 'create' --path controllers"
puts
puts "  # Combine filters"
puts "  ragify search 'validate' --type method --path models --limit 10"
puts
puts "  # Output formats"
puts "  ragify search 'api' --format json"
puts "  ragify search 'api' --format plain"
puts
puts "  # Search modes"
puts "  ragify search 'how does login work'       # hybrid (default)"
puts "  ragify search 'password check' --semantic # semantic only"
puts "  ragify search 'authenticate' --text       # text only"
puts
puts "  # Custom vector weight (hybrid mode)"
puts "  ragify search 'user login' -w 0.9         # 90% semantic"
puts "  ragify search 'find_by_email' -w 0.3      # 30% semantic"
puts
puts "=" * 80
