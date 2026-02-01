# Ragify

A local-first RAG (Retrieval-Augmented Generation) system that makes Ruby codebases semantically searchable using AI embeddings.

Ask natural language questions about your code and get relevant snippets instantly—all running locally on your machine.

```bash
# Index your codebase
ragify index

# Search with natural language
ragify search "how do we handle user authentication?"

# Get relevant code with context
```

## Features

- **Semantic Search** — Ask questions in natural language, find code by meaning, not just keywords
- **Local-First** — All processing happens locally using Ollama. Your code never leaves your machine
- **Fast** — SQLite with FTS5 full-text search and vector similarity for efficient retrieval
- **Context-Aware** — Results include class/module context, line numbers, and visibility
- **Flexible** — Hybrid search combining semantic and keyword matching for best results
- **Privacy-Focused** — No external API calls, no data collection, completely offline

## Requirements

### Ruby

- Ruby 3.0 or higher

```bash
ruby --version  # Should be 3.0+
```

### Ollama (for semantic search)

Ollama provides local AI embeddings. Without Ollama, Ragify falls back to text-only search.

**macOS:**
```bash
brew install ollama
```

**Linux:**
```bash
curl -fsSL https://ollama.com/install.sh | sh
```

**Or download from:** https://ollama.com/download

**Start Ollama and pull the embedding model:**
```bash
# Start the Ollama server (run in background or separate terminal)
ollama serve

# Pull the recommended embedding model (~274MB)
ollama pull nomic-embed-text

# Verify installation
ollama list  # Should show nomic-embed-text
```

### SQLite

SQLite 3.35+ is required (included with most systems). The sqlite3 gem handles the database layer.

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/ryanmcgarvey/ragify.git
cd ragify

# Install dependencies
bundle install

# Install the gem locally
bundle exec rake install

# If using asdf
asdf reshim ruby

# If using rbenv
rbenv rehash

# Verify installation
ragify --version
```

### From RubyGems (coming soon)

```bash
gem install ragify
```

## Quick Start

```bash
# 1. Navigate to your Ruby project
cd /path/to/your/ruby/project

# 2. Initialize Ragify (creates .ragify directory and config)
ragify init

# 3. Index your codebase
ragify index

# 4. Search!
ragify search "authentication"
ragify search "how do users log in"
ragify search "database queries"
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `ragify init` | Initialize Ragify in the current directory |
| `ragify index` | Index all Ruby files in the project |
| `ragify search QUERY` | Search for code matching the query |
| `ragify status` | Show index statistics and status |
| `ragify reindex` | Clear and rebuild the entire index |
| `ragify clear` | Delete all indexed data |
| `ragify version` | Show version information |

### Searching

#### Basic Search

```bash
# Hybrid search (default) - combines semantic + keyword matching
ragify search "user authentication"

# Text-only search (no Ollama required)
ragify search "authenticate" --text

# Semantic-only search (requires Ollama)
ragify search "how does login work" --semantic
```

#### Filtering Results

```bash
# Limit number of results
ragify search "user" --limit 10
ragify search "user" -l 10

# Filter by chunk type
ragify search "validate" --type method
ragify search "User" --type class
ragify search "Auth" --type module
ragify search "MAX" --type constant

# Filter by file path
ragify search "create" --path controllers
ragify search "query" --path models

# Minimum similarity score (0.0-1.0)
ragify search "auth" --min-score 0.5

# Combine filters
ragify search "validate" --type method --path models --limit 5
```

#### Output Formats

```bash
# Colorized output (default)
ragify search "user"

# Plain text (no colors)
ragify search "user" --format plain

# JSON (for scripting)
ragify search "user" --format json
```

#### Tuning Hybrid Search

The `--vector-weight` flag controls the balance between semantic and keyword search:

```bash
# Default: 70% semantic, 30% text
ragify search "authentication"

# More semantic (for natural language queries)
ragify search "how do users log in" --vector-weight 0.9

# More text-based (for exact method names)
ragify search "find_by_email" --vector-weight 0.3

# Balanced
ragify search "password" -w 0.5
```

### Indexing

```bash
# Index current directory
ragify index

# Index a specific path
ragify index --path /path/to/project

# Verbose output (see every file and chunk)
ragify index --verbose

# Quiet mode (minimal output, for scripts)
ragify index --quiet

# Strict mode (fail on first error, for CI/CD)
ragify index --strict

# Skip prompts (for automation)
ragify index --yes

# Skip embedding generation
ragify index --no-embeddings
```

### Initialization

```bash
# Initialize with defaults
ragify init

# Force re-initialization
ragify init --force

# Quiet mode
ragify init --quiet
```

## Configuration

Ragify stores its configuration in `.ragify/config.yml`:

```yaml
# Ragify Configuration

# Ollama server URL
ollama_url: http://localhost:11434

# Embedding model to use
# Recommended: nomic-embed-text (768 dimensions, 8K context)
# Alternatives: snowflake-arctic-embed, all-minilm, mxbai-embed-large
model: nomic-embed-text

# Maximum lines per code chunk
chunk_size_limit: 1000

# Default number of search results
search_result_limit: 5

# Additional ignore patterns (beyond .ragifyignore)
ignore_patterns:
  - spec/**/*
  - test/**/*
  - vendor/**/*
  - node_modules/**/*
  - db/schema.rb
```

### Ignore Patterns

Create a `.ragifyignore` file to exclude files from indexing (similar to `.gitignore`):

```gitignore
# Test files
spec/**/*
test/**/*

# Generated files
db/schema.rb

# Dependencies
vendor/**/*
node_modules/**/*

# Build artifacts
pkg/**/*
tmp/**/*

# Documentation
doc/**/*
```

Default ignore patterns (always applied):
- `.git/**/*`
- `.ragify/**/*`
- `vendor/**/*`
- `node_modules/**/*`
- `tmp/**/*`
- `log/**/*`
- `coverage/**/*`
- `.bundle/**/*`

## How It Works

### Architecture

```
┌─────────────────┐
│      CLI        │  ← Thor-based command interface
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼────┐ ┌──▼───────┐
│Indexer │ │Searcher  │
└───┬────┘ └──┬───────┘
    │         │
┌───▼────┐ ┌──▼───────┐
│Chunker │ │Embedder  │  → Ollama (nomic-embed-text)
└───┬────┘ └──┬───────┘
    │         │
    └────┬────┘
         │
    ┌────▼────┐
    │  Store  │  → SQLite + FTS5
    └─────────┘
```

### Indexing Pipeline

1. **Discovery** — Find all `.rb` files, respecting ignore patterns
2. **Parsing** — Parse Ruby files into AST using the Parser gem
3. **Chunking** — Extract classes, modules, methods, and constants with context
4. **Embedding** — Generate vector embeddings using Ollama
5. **Storage** — Store chunks and embeddings in SQLite

### Search Pipeline

1. **Query Embedding** — Convert search query to vector (for semantic search)
2. **Hybrid Search** — Combine vector similarity with FTS5 text matching
3. **Filtering** — Apply type, path, and score filters
4. **Ranking** — Sort by combined relevance score
5. **Formatting** — Display results with code snippets and context

### Chunk Types

Ragify extracts these semantic chunks from your code:

| Type | Description | Example |
|------|-------------|---------|
| `class` | Class definitions | `class User < ApplicationRecord` |
| `module` | Module definitions | `module Authentication` |
| `method` | Instance and class methods | `def authenticate(password)` |
| `constant` | Constant assignments | `MAX_RETRIES = 3` |

Each chunk includes:
- Full source code
- File path and line numbers
- Context (parent class/module)
- Comments/docstrings
- Metadata (visibility, parameters, etc.)

## Troubleshooting

### "Ollama not running"

```bash
# Start Ollama server
ollama serve

# Or run in background
ollama serve &
```

### "Model not found"

```bash
# Pull the embedding model
ollama pull nomic-embed-text

# Verify it's available
ollama list
```

### "No Ruby files found"

- Check that you're in a directory with `.rb` files
- Review your `.ragifyignore` patterns
- Run `ragify index --verbose` to see what's being discovered

### "Semantic search unavailable"

Ragify automatically falls back to text-only search when Ollama isn't available. For best results:

1. Install Ollama
2. Run `ollama serve`
3. Run `ragify index` to generate embeddings

### "Permission denied" or file errors

```bash
# Ensure the gem is properly installed
bundle exec rake install

# Reshim if using version managers
asdf reshim ruby   # asdf
rbenv rehash       # rbenv
```

### Search returns no results

- Try different keywords
- Remove filters (`--type`, `--path`, `--min-score`)
- Use `--text` flag for keyword-only search
- Check `ragify status` to verify files are indexed

### Large codebase performance

For very large codebases (500+ files):

- Indexing may take several minutes (embedding generation is the bottleneck)
- Consider using `--no-embeddings` for quick text-only indexing
- Use `.ragifyignore` to exclude unnecessary files

## Development

```bash
# Run tests
bundle exec rspec

# Run tests with Ollama integration tests
bundle exec rspec --tag ollama_required

# Run linter
bundle exec rubocop

# Run tests and linting
bundle exec rake

# Install locally for testing
bundle exec rake install

# Interactive console
bin/console
```

### Project Structure

```
ragify/
├── exe/ragify           # CLI executable
├── lib/
│   ├── ragify.rb        # Main module
│   └── ragify/
│       ├── chunker.rb   # Ruby code parsing & chunking
│       ├── cli.rb       # Thor CLI commands
│       ├── config.rb    # Configuration management
│       ├── embedder.rb  # Ollama embedding generation
│       ├── indexer.rb   # File discovery
│       ├── searcher.rb  # Search implementation
│       ├── store.rb     # SQLite storage
│       └── version.rb   # Version constant
├── spec/                # RSpec tests
└── demos/               # Demo scripts
```

## Why These Technologies?

- **Ollama + nomic-embed-text** — Best local embedding model for code. 768 dimensions, 8K context window, fast and accurate for technical content.

- **SQLite + FTS5** — Simple, portable, no server needed. Single file database with built-in full-text search.

- **Parser gem** — Robust Ruby AST parsing. Handles modern Ruby syntax and extracts semantic structure.

## Limitations

- **Ruby only** — Currently only parses Ruby files. Multi-language support planned for future versions.
- **Full reindex** — No incremental updates yet. File changes require reindexing.
- **Memory usage** — Embedding cache is kept in memory during indexing.

## Roadmap

See [ragify_roadmap.md](ragify_roadmap.md) for the development plan and future enhancements:

- Incremental updates (file change detection)
- Watch mode for development
- Multi-language support (JavaScript, Python, Go)
- Web UI and VS Code extension
- API server mode

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ryanmcgarvey/ragify.

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Acknowledgments

- Built with [Ollama](https://ollama.com) for local AI embeddings
- Uses [nomic-embed-text](https://huggingface.co/nomic-ai/nomic-embed-text-v1) model
- Inspired by the need for better code search in large Ruby projects