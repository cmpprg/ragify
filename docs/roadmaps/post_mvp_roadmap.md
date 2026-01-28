# RAGIFY - Post-MVP Roadmap - Iterations 2-5

**NOTE: This document uses ASCII characters only for maximum compatibility**

**STATUS**: Planning document for post-MVP development
**PREREQUISITE**: Complete MVP (Days 1-7) before starting these iterations

## Document Overview

This roadmap covers enhancements to make Ragify a **production-ready RAG component for AI agentic systems**. The MVP provides core functionality (index, embed, search). These iterations add the features needed for real-world agent integration.

**Key Philosophy**: Each iteration delivers **complete, usable features** that add measurable value. No half-finished work.

---

## Post-MVP Progress Tracker

**Last Updated**: 2026-01-25
**Current Phase**: Planning (MVP Days 1-7 in progress)

| Iteration | Focus | Status | Est. Duration | Value Tier |
|-----------|-------|--------|---------------|------------|
| Iteration 2 | API Mode & HTTP Server | NOT STARTED | 3-4 days | CRITICAL |
| Iteration 3 | Relationship Graphs | NOT STARTED | 5-7 days | HIGH |
| Iteration 4 | Incremental Updates & Watch | NOT STARTED | 3-4 days | HIGH |
| Iteration 5 | Multi-Language Support | NOT STARTED | 7-10 days | MEDIUM |
| Backlog | Advanced Features | NOT STARTED | TBD | LOW |

**Overall Post-MVP Timeline**: 18-25 days of development

---

## Design Principles for Post-MVP

1. **Agent-First, Human-Friendly**: APIs designed for programmatic access, CLI remains useful
2. **Backward Compatible**: New features don't break existing workflows
3. **Configurable**: Everything optional via config.yml, sensible defaults
4. **Local-First**: No required cloud dependencies (but allow optional ones)
5. **Performance Conscious**: Agents query frequently, sub-100ms responses critical
6. **Observable**: Metrics, logs, health checks for production debugging

---

## Iteration 2: API Mode & HTTP Server [CRITICAL]

**Goal**: Enable AI agents to query Ragify programmatically via HTTP API
**Priority**: CRITICAL - Without this, agents can't use Ragify effectively
**Estimated Time**: 3-4 days
**Complexity**: Medium (HTTP routing, JSON serialization, authentication)

### Why This Matters:
Agents need function calls, not CLI commands. Compare:
```ruby
# Current (MVP): Agent shells out, parses stdout
result = `ragify search "authentication" --json`
data = JSON.parse(result)

# After Iteration 2: Agent makes HTTP call
response = HTTP.post("http://localhost:8080/api/search", 
  json: {query: "authentication", limit: 5})
data = response.parse
```

The API approach is:
- **Faster**: No process spawn overhead (~50ms saved per query)
- **Cleaner**: Structured JSON in/out, no stdout parsing
- **Reliable**: Proper HTTP status codes, error handling
- **Scalable**: Can run as daemon, handle concurrent requests

### Tasks:

#### Day 1: HTTP Server Foundation
- [ ] Add dependencies to gemspec:
  - [ ] `rack` (~> 3.0) - HTTP interface
  - [ ] `puma` (~> 6.0) - Web server
  - [ ] `rack-cors` (~> 2.0) - CORS support for web UIs
  - [ ] `jwt` (~> 2.7) - Token-based auth (optional)
- [ ] Create server architecture:
  ```
  lib/ragify/
    server/
      app.rb          # Rack application
      router.rb       # Route definitions
      middleware/
        auth.rb       # Optional authentication
        logging.rb    # Request/response logging
        errors.rb     # Error handling
      handlers/
        search.rb     # Search endpoint handler
        index.rb      # Indexing endpoint handler
        status.rb     # Health check handler
  ```
- [ ] Implement basic Rack app:
  ```ruby
  # lib/ragify/server/app.rb
  module Ragify
    module Server
      class App
        def call(env)
          request = Rack::Request.new(env)
          router.call(request)
        end
      end
    end
  end
  ```
- [ ] Add `ragify serve` CLI command:
  ```bash
  ragify serve --port 8080 --host localhost
  ragify serve --daemon  # Background mode
  ragify serve --config server.yml
  ```
- [ ] Basic health check endpoint:
  ```
  GET /health
  → {"status": "ok", "version": "0.2.0", "chunks": 1234}
  ```

#### Day 2: Core API Endpoints
- [ ] Implement search endpoint:
  ```
  POST /api/search
  Body: {
    "query": "user authentication",
    "limit": 10,
    "filters": {
      "type": "method",
      "file_path": "app/controllers/**"
    },
    "include_code": true,
    "min_score": 0.7
  }
  
  Response: {
    "results": [
      {
        "id": "abc123",
        "type": "method",
        "name": "authenticate_user",
        "file_path": "app/controllers/auth_controller.rb",
        "start_line": 45,
        "end_line": 58,
        "score": 0.92,
        "code": "def authenticate_user...",
        "context": "class AuthController"
      }
    ],
    "query_time_ms": 87,
    "total_results": 1
  }
  ```
- [ ] Implement index endpoint:
  ```
  POST /api/index
  Body: {
    "path": "/path/to/project",
    "force": false,
    "verbose": false
  }
  
  Response: {
    "status": "completed",
    "files_indexed": 234,
    "chunks_created": 1456,
    "embeddings_generated": 1234,
    "embeddings_cached": 222,
    "duration_ms": 45678,
    "errors": []
  }
  ```
- [ ] Implement status endpoint:
  ```
  GET /api/status
  
  Response: {
    "database": {
      "path": ".ragify/ragify.db",
      "size_mb": 12.3,
      "chunks": 1234,
      "files": 89,
      "last_indexed": "2026-01-25T14:30:00Z"
    },
    "embedder": {
      "status": "connected",
      "model": "nomic-embed-text",
      "cache_hits": 842,
      "cache_misses": 134
    },
    "server": {
      "version": "0.2.0",
      "uptime_seconds": 3456,
      "requests_total": 789
    }
  }
  ```
- [ ] Add error handling:
  ```ruby
  # Custom error responses
  rescue_from Ragify::OllamaError do |e|
    json_error(503, "Embedding service unavailable", e.message)
  end
  
  rescue_from SQLite3::Exception do |e|
    json_error(500, "Database error", e.message)
  end
  ```

#### Day 3: Authentication & Security
- [ ] Implement optional API key authentication:
  ```yaml
  # .ragify/server.yml
  server:
    port: 8080
    host: localhost
    auth:
      enabled: true
      type: api_key  # or jwt, basic
      api_keys:
        - name: "agent-1"
          key: "ragify_sk_abc123..."
          permissions: ["read", "write"]
  ```
- [ ] Add authentication middleware:
  ```ruby
  # X-API-Key header validation
  def authenticate_request(request)
    api_key = request.env['HTTP_X_API_KEY']
    return unauthorized unless valid_api_key?(api_key)
  end
  ```
- [ ] Add rate limiting (basic):
  ```ruby
  # Simple in-memory rate limiter
  # 100 requests/minute per API key
  def check_rate_limit(api_key)
    count = @rate_limiter.increment(api_key)
    return too_many_requests if count > 100
  end
  ```
- [ ] Add CORS configuration:
  ```ruby
  use Rack::Cors do
    allow do
      origins '*'  # or specific domains
      resource '/api/*',
        methods: [:get, :post, :put, :delete],
        headers: :any
    end
  end
  ```

#### Day 4: Testing & Documentation
- [ ] Write comprehensive API tests:
  ```ruby
  # spec/server/search_spec.rb
  describe "POST /api/search" do
    it "returns search results" do
      post "/api/search", {query: "auth"}.to_json
      expect(last_response.status).to eq(200)
      expect(json_body["results"]).to be_an(Array)
    end
    
    it "validates required parameters" do
      post "/api/search", {}.to_json
      expect(last_response.status).to eq(400)
      expect(json_body["error"]).to include("query required")
    end
    
    it "respects rate limits" do
      101.times { post "/api/search", {query: "test"}.to_json }
      expect(last_response.status).to eq(429)
    end
  end
  ```
- [ ] Write integration tests:
  ```ruby
  # Full e2e test: start server, make requests, verify
  describe "Server Integration" do
    before(:all) do
      @server = start_test_server(port: 9999)
      index_sample_project
    end
    
    it "handles concurrent requests" do
      threads = 10.times.map do
        Thread.new { HTTP.post("localhost:9999/api/search", ...) }
      end
      
      results = threads.map(&:value)
      expect(results).to all(be_successful)
    end
  end
  ```
- [ ] Create API documentation:
  ```markdown
  # API_REFERENCE.md
  
  ## Authentication
  Include API key in header: `X-API-Key: ragify_sk_...`
  
  ## Endpoints
  
  ### POST /api/search
  Search codebase semantically.
  
  **Request:**
  - `query` (required): Natural language search query
  - `limit` (optional): Max results, default 10
  - `filters` (optional): Filter criteria
  
  **Response:**
  - `results`: Array of matching code chunks
  - `query_time_ms`: Search duration
  
  **Example:**
  ```bash
  curl -X POST http://localhost:8080/api/search \
    -H "X-API-Key: ragify_sk_abc123" \
    -H "Content-Type: application/json" \
    -d '{"query": "authentication", "limit": 5}'
  ```
- [ ] Add OpenAPI/Swagger spec (optional):
  ```yaml
  # openapi.yml
  openapi: 3.0.0
  info:
    title: Ragify API
    version: 0.2.0
  paths:
    /api/search:
      post:
        summary: Search codebase
        requestBody:
          content:
            application/json:
              schema:
                type: object
                properties:
                  query:
                    type: string
  ```

### End of Iteration 2 Deliverables:
- [ ] Working HTTP API server
- [ ] Search, index, status endpoints
- [ ] Optional authentication
- [ ] Rate limiting
- [ ] Comprehensive tests
- [ ] API documentation
- [ ] `ragify serve` command

### Success Criteria:
- [ ] Agent can start server with `ragify serve`
- [ ] Agent can search via HTTP in <100ms
- [ ] Server handles 100+ concurrent requests
- [ ] API documented with examples
- [ ] All endpoints have >90% test coverage

### Configuration Example:
```yaml
# .ragify/config.yml (extended)
server:
  port: 8080
  host: localhost
  daemon: false
  workers: 4
  auth:
    enabled: false
    type: api_key
  rate_limit:
    enabled: true
    requests_per_minute: 100
  cors:
    enabled: true
    origins: ["*"]
  logging:
    level: info
    format: json
```

---

## Iteration 3: Relationship Graphs [HIGH VALUE]

**Goal**: Extract and query code relationships (calls, imports, inheritance)
**Priority**: HIGH - Dramatically improves RAG quality for agents
**Estimated Time**: 5-7 days
**Complexity**: High (AST traversal, graph storage, query optimization)

### Why This Matters:
Vector search alone misses critical context. Example:

**Without relationships:**
```
Agent: "Where is authenticate_user called?"
RAG: Returns the method definition (keyword match)
Agent: Has to guess where it's used
```

**With relationships:**
```
Agent: "Where is authenticate_user called?"
RAG: Returns 5 controllers that call it + usage context
Agent: Can reason about authentication flow
```

Relationships enable:
- Call graph traversal ("what calls this?")
- Dependency analysis ("what does this import?")
- Impact analysis ("what breaks if I change this?")
- Test discovery ("what tests cover this code?")

### Tasks:

#### Day 1: Database Schema & Migration
- [ ] Create migration system:
  ```ruby
  # lib/ragify/migrations/002_add_relationships.rb
  class AddRelationships < Ragify::Migration
    def up
      create_table :relationships do |t|
        t.text :from_chunk_id, null: false
        t.text :to_chunk_id        # NULL if external reference
        t.text :to_identifier, null: false  # "User#authenticate", "ActiveRecord::Base"
        t.text :relationship_type, null: false  # "calls", "requires", "inherits"
        t.json :metadata           # {line: 45, context: "..."}
        t.datetime :created_at
      end
      
      add_index :relationships, :from_chunk_id
      add_index :relationships, :to_chunk_id
      add_index :relationships, :to_identifier
      add_index :relationships, :relationship_type
      add_foreign_key :relationships, :chunks, column: :from_chunk_id
    end
    
    def down
      drop_table :relationships
    end
  end
  ```
- [ ] Implement migration runner:
  ```ruby
  # lib/ragify/migrator.rb
  class Migrator
    def migrate
      current = get_schema_version
      pending = migrations.select { |m| m.version > current }
      
      pending.each do |migration|
        migration.up
        update_schema_version(migration.version)
      end
    end
    
    def rollback(steps = 1)
      # Rollback last N migrations
    end
  end
  ```
- [ ] Add `ragify db:migrate` command:
  ```bash
  ragify db:migrate        # Run pending migrations
  ragify db:rollback       # Rollback last migration
  ragify db:version        # Show current schema version
  ragify db:reset          # Drop and recreate (dev only)
  ```
- [ ] Update schema version tracking:
  ```sql
  CREATE TABLE schema_migrations (
    version INTEGER PRIMARY KEY,
    applied_at DATETIME DEFAULT CURRENT_TIMESTAMP
  );
  ```

#### Day 2-3: Relationship Extraction
- [ ] Extend chunker to extract relationships:
  ```ruby
  # lib/ragify/chunker.rb (extended)
  def extract_relationships(node, chunk_id, context)
    relationships = []
    
    # Method calls
    if node.type == :send
      receiver = extract_receiver(node)
      method_name = node.children[1]
      
      relationships << {
        from_chunk_id: chunk_id,
        to_identifier: "#{receiver}##{method_name}",
        relationship_type: "calls",
        metadata: {
          line: node.loc.line,
          receiver: receiver,
          method: method_name
        }
      }
    end
    
    # Constant references
    if node.type == :const
      const_name = fully_qualified_const_name(node, context)
      
      relationships << {
        from_chunk_id: chunk_id,
        to_identifier: const_name,
        relationship_type: "references",
        metadata: {line: node.loc.line}
      }
    end
    
    # Requires/imports
    if node.type == :send && node.children[1] == :require
      gem_name = node.children[2].children[0]
      
      relationships << {
        from_chunk_id: chunk_id,
        to_identifier: "gem:#{gem_name}",
        relationship_type: "requires",
        metadata: {
          line: node.loc.line,
          gem: gem_name
        }
      }
    end
    
    # Class inheritance
    if node.type == :class && node.children[1]
      parent = extract_name(node.children[1])
      
      relationships << {
        from_chunk_id: chunk_id,
        to_identifier: parent,
        relationship_type: "inherits",
        metadata: {line: node.loc.line}
      }
    end
    
    # Module includes
    if node.type == :send && [:include, :extend, :prepend].include?(node.children[1])
      module_name = extract_name(node.children[2])
      
      relationships << {
        from_chunk_id: chunk_id,
        to_identifier: module_name,
        relationship_type: node.children[1].to_s,  # "include", "extend"
        metadata: {line: node.loc.line}
      }
    end
    
    # Recurse into child nodes
    node.children.each do |child|
      next unless child.is_a?(Parser::AST::Node)
      relationships.concat(extract_relationships(child, chunk_id, context))
    end
    
    relationships
  end
  ```
- [ ] Implement helper methods:
  ```ruby
  def extract_receiver(send_node)
    receiver = send_node.children[0]
    return "self" unless receiver
    
    case receiver.type
    when :const
      extract_name(receiver)
    when :send
      # Chained calls: User.find().update()
      extract_receiver(receiver) + "#" + receiver.children[1].to_s
    when :lvar, :ivar, :cvar
      receiver.children[0].to_s
    else
      "unknown"
    end
  end
  
  def fully_qualified_const_name(const_node, context)
    parts = []
    node = const_node
    
    while node.type == :const
      parts.unshift(node.children[1])
      node = node.children[0]
      break unless node
    end
    
    # Prepend context if relative constant
    if context && !absolute_const?(const_node)
      parts.unshift(context)
    end
    
    parts.join("::")
  end
  ```
- [ ] Update indexer to store relationships:
  ```ruby
  # lib/ragify/indexer.rb (extended)
  def index_file(file_path)
    chunks = chunker.process(file_path)
    relationships = []
    
    chunks.each do |chunk|
      relationships.concat(chunk[:relationships] || [])
    end
    
    store.save_chunks(chunks)
    store.save_relationships(relationships)
  end
  ```
- [ ] Add relationship deduplication:
  ```ruby
  # Store only unique relationships
  def deduplicate_relationships(relationships)
    relationships.uniq do |rel|
      [
        rel[:from_chunk_id],
        rel[:to_identifier],
        rel[:relationship_type]
      ]
    end
  end
  ```

#### Day 4: Relationship Queries
- [ ] Implement relationship finder:
  ```ruby
  # lib/ragify/relationship_finder.rb
  class RelationshipFinder
    def find_callers(method_identifier)
      # Find all chunks that call this method
      db.execute(<<-SQL, method_identifier)
        SELECT c.* 
        FROM chunks c
        JOIN relationships r ON r.from_chunk_id = c.id
        WHERE r.to_identifier = ?
          AND r.relationship_type = 'calls'
      SQL
    end
    
    def find_callees(chunk_id)
      # Find all methods this chunk calls
      db.execute(<<-SQL, chunk_id)
        SELECT r.to_identifier, r.metadata
        FROM relationships r
        WHERE r.from_chunk_id = ?
          AND r.relationship_type = 'calls'
        ORDER BY r.to_identifier
      SQL
    end
    
    def find_dependencies(chunk_id)
      # Find all requires/imports
      db.execute(<<-SQL, chunk_id)
        SELECT r.to_identifier, r.metadata
        FROM relationships r
        WHERE r.from_chunk_id = ?
          AND r.relationship_type = 'requires'
      SQL
    end
    
    def find_descendants(class_name)
      # Find all classes that inherit from this class
      db.execute(<<-SQL, class_name)
        SELECT c.*
        FROM chunks c
        JOIN relationships r ON r.from_chunk_id = c.id
        WHERE r.to_identifier = ?
          AND r.relationship_type = 'inherits'
      SQL
    end
    
    def find_related_tests(chunk_id)
      # Find tests that reference this chunk's identifier
      chunk = db.get_chunk(chunk_id)
      identifier = "#{chunk.context}##{chunk.name}"
      
      db.execute(<<-SQL, "%#{identifier}%")
        SELECT c.*
        FROM chunks c
        WHERE c.file_path LIKE '%_spec.rb'
          AND c.code LIKE ?
      SQL
    end
  end
  ```
- [ ] Add graph traversal:
  ```ruby
  def traverse_call_graph(start_chunk_id, depth: 3)
    # BFS to find all transitive callers
    visited = Set.new
    queue = [[start_chunk_id, 0]]
    results = []
    
    while !queue.empty?
      chunk_id, current_depth = queue.shift
      next if visited.include?(chunk_id)
      next if current_depth > depth
      
      visited.add(chunk_id)
      results << {chunk_id: chunk_id, depth: current_depth}
      
      callers = find_callers_by_chunk(chunk_id)
      callers.each do |caller|
        queue << [caller.id, current_depth + 1]
      end
    end
    
    results
  end
  ```

#### Day 5: API Integration
- [ ] Add relationship endpoints:
  ```
  GET /api/relationships/callers/:identifier
  → Returns all chunks that call this method/class
  
  GET /api/relationships/callees/:chunk_id
  → Returns all methods this chunk calls
  
  GET /api/relationships/dependencies/:chunk_id
  → Returns all requires/imports
  
  GET /api/relationships/descendants/:class_name
  → Returns all classes that inherit from this class
  
  GET /api/relationships/graph/:chunk_id?depth=3
  → Returns call graph traversal results
  ```
- [ ] Example API response:
  ```json
  GET /api/relationships/callers/User%23authenticate
  
  {
    "identifier": "User#authenticate",
    "relationship_type": "calls",
    "callers": [
      {
        "chunk_id": "abc123",
        "type": "method",
        "name": "login",
        "file_path": "app/controllers/sessions_controller.rb",
        "context": "SessionsController",
        "line": 45,
        "code_snippet": "user.authenticate(params[:password])"
      },
      {
        "chunk_id": "def456",
        "type": "method",
        "name": "verify_credentials",
        "file_path": "app/services/auth_service.rb",
        "context": "AuthService",
        "line": 23,
        "code_snippet": "@user.authenticate(token)"
      }
    ],
    "total": 2
  }
  ```
- [ ] Add CLI commands:
  ```bash
  ragify relationships callers "User#authenticate"
  ragify relationships callees abc123
  ragify relationships graph abc123 --depth 3
  ```

#### Day 6-7: Testing & Optimization
- [ ] Write relationship extraction tests
- [ ] Write relationship query tests
- [ ] Add performance benchmarks
- [ ] Optimize queries with indexes

### End of Iteration 3 Deliverables:
- [ ] Relationship extraction during indexing
- [ ] Relationship storage in SQLite
- [ ] Relationship finder with graph traversal
- [ ] API endpoints for relationship queries
- [ ] CLI commands for relationships
- [ ] Comprehensive tests
- [ ] Performance benchmarks

### Success Criteria:
- [ ] Extracts 90%+ of method calls, requires, inheritance
- [ ] Relationship queries return results in <10ms
- [ ] Graph traversal handles 1000+ node graphs
- [ ] API documented with examples
- [ ] Test coverage >85% for relationship code

---

## Iteration 4: Incremental Updates & Watch Mode [HIGH VALUE]

**Goal**: Only re-index changed files, add watch mode for development
**Priority**: HIGH - Dramatically improves re-indexing speed
**Estimated Time**: 3-4 days
**Complexity**: Medium (file hashing, change detection, file watching)

### Why This Matters:
Full re-indexing is slow. Incremental updates provide 20x speedup on typical changes.

### Tasks:

#### Day 1: File-Level Change Detection
- [ ] Add file hash tracking
- [ ] Implement hash calculation
- [ ] Update indexer to check hashes
- [ ] Add `--force` flag to bypass cache

#### Day 2: Watch Mode Implementation
- [ ] Add file watching dependency (Listen gem)
- [ ] Implement file watcher
- [ ] Add `ragify watch` CLI command
- [ ] Add watch mode to server
- [ ] Implement graceful shutdown

#### Day 3: Batch Operations & Optimization
- [ ] Implement debouncing
- [ ] Add batch indexing
- [ ] Add progress indicators

#### Day 4: Testing & Documentation
- [ ] Write change detection tests
- [ ] Write watch mode tests
- [ ] Document incremental indexing

### End of Iteration 4 Deliverables:
- [ ] File-level change detection
- [ ] Incremental indexing
- [ ] Watch mode with auto-indexing
- [ ] `ragify watch` command
- [ ] Comprehensive tests

### Success Criteria:
- [ ] Re-indexing 5/100 changed files takes <15 seconds (20x faster)
- [ ] Watch mode detects changes within 3 seconds
- [ ] No memory leaks in long-running watch mode
- [ ] Test coverage >85%

---

## Iteration 5: Multi-Language Support [MEDIUM VALUE]

**Goal**: Support Python, JavaScript, TypeScript using tree-sitter
**Priority**: MEDIUM - Valuable for polyglot codebases
**Estimated Time**: 7-10 days
**Complexity**: High (new parsers, language-specific chunking, testing)

### Tasks:

#### Day 1-2: Tree-Sitter Integration
- [ ] Add tree-sitter dependency
- [ ] Create parser abstraction
- [ ] Implement tree-sitter Ruby parser
- [ ] Create parser registry

#### Day 3-4: Python Support
- [ ] Implement Python parser
- [ ] Add Python-specific relationship extraction
- [ ] Write Python parser tests

#### Day 5-6: JavaScript/TypeScript Support
- [ ] Implement JavaScript parser
- [ ] Add TypeScript-specific handling
- [ ] Write JS/TS parser tests

#### Day 7-8: Configuration & Detection
- [ ] Add language configuration
- [ ] Implement language detection
- [ ] Update file discovery

#### Day 9-10: Testing & Documentation
- [ ] Write cross-language tests
- [ ] Create language comparison docs
- [ ] Add migration guide from Parser gem

### End of Iteration 5 Deliverables:
- [ ] Tree-sitter integration
- [ ] Python, JavaScript, TypeScript support
- [ ] Parser abstraction and registry
- [ ] Comprehensive tests for each language
- [ ] Multi-language documentation

### Success Criteria:
- [ ] Successfully indexes Python, JavaScript, TypeScript projects
- [ ] Extracts 85%+ of classes/functions across languages
- [ ] Parsing speed within 2x of Ruby Parser gem
- [ ] Test coverage >80% for each parser

---

## Backlog: Future Enhancements

Lower priority features for specific use cases:
- Performance & scalability
- Advanced search
- Code intelligence
- Developer experience
- Integrations
- Advanced RAG features
- Enterprise features
- Alternative embedding providers

---

## Implementation Strategy

### Iteration Sequencing:
1. **Iteration 2 first** (API mode) - Highest ROI
2. **Iteration 3 or 4 next** - Choose based on priorities
3. **Iteration 5 last** - Multi-language support

### Testing Strategy:
- Unit tests: >85% coverage per iteration
- Integration tests: End-to-end scenarios
- Performance tests: Benchmarks for critical paths
- Regression tests: Ensure backward compatibility

---

**END OF POST-MVP ROADMAP**

Last Updated: 2026-01-25
Version: 1.0 (Post-MVP Planning)
Prerequisite: Complete MVP (Days 1-7)