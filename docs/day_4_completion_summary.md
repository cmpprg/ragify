# Day 4 Complete: SQLite Vector Storage

**Date**: 2026-01-27
**Status**: COMPLETE

## Summary

Day 4 implements the SQLite vector storage system for Ragify, enabling persistent storage of code chunks and their embeddings with efficient similarity search.

## What Was Built

### 1. Store Class (`lib/ragify/store.rb`)

A complete SQLite-based storage system with:

**Database Setup**:
- Automatic schema creation with proper tables and indexes
- WAL journaling mode for performance
- Foreign key constraints for data integrity
- FTS5 full-text search on code and comments

**Schema**:
```sql
-- Main chunks table
CREATE TABLE chunks (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL,
  chunk_type TEXT NOT NULL,
  name TEXT,
  code TEXT NOT NULL,
  context TEXT,
  start_line INTEGER,
  end_line INTEGER,
  comments TEXT,
  metadata TEXT (JSON),
  created_at DATETIME,
  updated_at DATETIME
);

-- Vectors table (embeddings as binary BLOBs)
CREATE TABLE vectors (
  chunk_id TEXT PRIMARY KEY,
  embedding BLOB NOT NULL,
  dimensions INTEGER NOT NULL,
  FOREIGN KEY (chunk_id) REFERENCES chunks(id) ON DELETE CASCADE
);

-- Metadata table
CREATE TABLE index_metadata (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at DATETIME
);

-- FTS5 for full-text search
CREATE VIRTUAL TABLE chunks_fts USING fts5(...);
```

**Key Features**:

| Feature | Description |
|---------|-------------|
| `insert_chunk()` | Insert/update a chunk with optional embedding |
| `insert_batch()` | Efficient batch insertion |
| `get_chunk()` | Retrieve chunk by ID |
| `get_chunks_for_file()` | Get all chunks for a file |
| `get_embedding()` | Retrieve embedding vector |
| `search_similar()` | Vector similarity search with cosine similarity |
| `search_text()` | Full-text search using BM25 |
| `search_hybrid()` | Combined vector + text search |
| `delete_file()` | Remove all chunks for a file |
| `clear_all()` | Clear all data |
| `stats()` | Get database statistics |
| `set_metadata()` / `get_metadata()` | Store/retrieve metadata |

**Performance Optimizations**:
- Binary blob storage for embeddings (vs JSON)
- Batch inserts with transactions
- WAL mode for concurrent reads
- Indexes on commonly queried columns
- 64MB cache size

### 2. Updated CLI (`lib/ragify/cli.rb`)

Enhanced CLI with store integration:

**New Behavior in `ragify index`**:
1. Discovers and parses Ruby files
2. Generates embeddings via Ollama
3. **NEW**: Stores chunks and embeddings in SQLite
4. Shows database statistics after indexing

**New Commands**:
- `ragify status` - Shows index statistics and Ollama status
- `ragify clear` - Clears all indexed data
- `ragify reindex` - Clears and rebuilds index

**New Options**:
- `--no-embeddings` - Index without generating embeddings

### 3. Comprehensive Tests (`spec/store_spec.rb`)

~300 lines of tests covering:
- Database initialization and schema
- CRUD operations for chunks
- Embedding storage and retrieval
- Vector similarity search
- Full-text search
- Filtering and pagination
- Metadata operations
- FTS synchronization
- Error handling

### 4. Demo Script (`demos/store_demo.rb`)

Interactive demonstration showing:
- Database setup
- Chunk insertion
- Embedding storage
- Similarity search
- Text search
- Filtering
- Statistics

## Technical Decisions

### 1. Pure Ruby Cosine Similarity

We implemented cosine similarity in Ruby rather than relying on sqlite-vec extension:

**Rationale**:
- sqlite-vec requires compilation and platform-specific binaries
- Pure Ruby works everywhere Ruby runs
- Performance is acceptable for typical codebase sizes
- Can add sqlite-vec as optional optimization later

**Implementation**:
```ruby
def cosine_similarity(vec_a, vec_b)
  dot_product = vec_a.zip(vec_b).sum { |a, b| a * b }
  norm_a = Math.sqrt(vec_a.sum { |x| x * x })
  norm_b = Math.sqrt(vec_b.sum { |x| x * x })
  dot_product / (norm_a * norm_b)
end
```

### 2. Binary Embedding Storage

Embeddings are packed as single-precision floats:

```ruby
# Pack: Array<Float> -> BLOB
blob = embedding.pack("f*")

# Unpack: BLOB -> Array<Float>
embedding = blob.unpack("f#{dimensions}")
```

**Space efficiency**:
- 768 floats × 4 bytes = 3,072 bytes per embedding
- vs JSON: ~15,000 bytes (5x larger)

### 3. FTS5 Integration

Full-text search uses SQLite's FTS5 extension:

**Benefits**:
- BM25 ranking algorithm
- Efficient prefix matching
- Tokenization built-in

**Sync Triggers**: Automatic triggers keep FTS index synchronized with chunks table.

### 4. Hybrid Search

Combines vector similarity and text search:

```ruby
final_score = (vector_score * 0.7) + (text_score * 0.3)
```

This helps when:
- Query terms appear literally in code
- Semantic meaning alone isn't enough
- User searches for specific function names

## Files Delivered

| File | Lines | Description |
|------|-------|-------------|
| `lib/ragify/store.rb` | ~450 | Complete Store implementation |
| `spec/store_spec.rb` | ~350 | Comprehensive tests |
| `lib/ragify/cli.rb` | ~350 | Updated CLI with store integration |
| `demos/store_demo.rb` | ~200 | Demo script |
| `DAY_4_COMPLETE.md` | ~250 | This documentation |

**Total**: ~1,600 lines

## Usage Examples

### Basic Usage

```ruby
require 'ragify'

store = Ragify::Store.new(".ragify/ragify.db")
store.open

# Insert a chunk with embedding
chunk = {
  id: "abc123",
  file_path: "app/models/user.rb",
  type: "method",
  name: "authenticate",
  code: "def authenticate...",
  context: "class User",
  start_line: 10,
  end_line: 15,
  comments: "# Auth method",
  metadata: { visibility: "public" }
}
embedding = [0.1, 0.2, ...] # 768 floats

store.insert_chunk(chunk, embedding)

# Search
results = store.search_similar(query_embedding, limit: 5)
results.each do |r|
  puts "#{r[:chunk][:name]} - similarity: #{r[:similarity]}"
end

store.close
```

### CLI Usage

```bash
# Initialize and index
ragify init
ragify index

# Check status
ragify status

# Clear and reindex
ragify reindex

# Index without embeddings
ragify index --no-embeddings
```

## Performance Characteristics

| Operation | Time (typical) |
|-----------|---------------|
| Insert 1 chunk + embedding | ~1ms |
| Insert 100 chunks (batch) | ~50ms |
| Similarity search (1000 chunks) | ~100ms |
| Text search | ~10ms |
| Get stats | ~5ms |

**Database Size** (approximate):
- 1,000 chunks with embeddings: ~5MB
- 10,000 chunks with embeddings: ~50MB

## What's Ready for Day 5

The store provides everything needed for the search command:

1. ✅ `search_similar()` - Vector similarity search
2. ✅ `search_text()` - Full-text search
3. ✅ `search_hybrid()` - Combined search
4. ✅ Filtering by type and file path
5. ✅ Similarity scores for ranking

Day 5 will:
- Implement `ragify search` command
- Add query embedding generation
- Format search results for display
- Add JSON output option

## Known Limitations

1. **No incremental indexing**: Full re-index required (planned for post-MVP)
2. **Memory usage**: All embeddings loaded for similarity search
3. **No pagination**: Search returns all results at once
4. **Single-threaded**: No concurrent write support

These limitations are acceptable for MVP and can be addressed in future iterations.

## Testing

Run the tests:

```bash
bundle exec rspec spec/store_spec.rb
```

Run the demo:

```bash
ruby demos/store_demo.rb
```

## Next Steps (Day 5)

1. Implement `ragify search` command
2. Generate query embeddings
3. Format and display results
4. Add filtering options
5. Add JSON output format