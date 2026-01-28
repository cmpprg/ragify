# Ragify

**Local-first RAG system for Ruby codebases using AI embeddings**

Ragify makes your Ruby codebase semantically searchable. Index your code once, then ask natural language questions to find relevant code snippets instantly.

```bash
# Index your codebase
ragify index

# Search semantically
ragify search "how do we handle user authentication?"

# Get relevant code snippets with context
```

## Features

- 🔍 **Semantic Search**: Ask questions in natural language, get relevant code
- 🏠 **Local-First**: All processing happens locally using Ollama
- 🚀 **Fast**: SQLite vector database for efficient similarity search
- 🔒 **Private**: Your code never leaves your machine
- 🎯 **Context-Aware**: Preserves class/module context in results

## Status

**Current Version**: 0.1.0 (Day 1 - MVP in progress)

- ✅ Day 1: Foundation & Project Setup
- ⏳ Day 2: Code Parsing & Chunking (next)
- ⏳ Day 3: Ollama Integration & Embeddings
- ⏳ Day 4: SQLite Vector Storage
- ⏳ Day 5: Search Functionality
- ⏳ Day 6: CLI Polish & Testing
- ⏳ Day 7: Documentation & Release

## Prerequisites

Before using Ragify, you need:

1. **Ruby 3.0+**
   ```bash
   ruby --version  # Should be 3.0 or higher
   ```

2. **Ollama** (for local embeddings)
   ```bash
   # Install Ollama
   # macOS:
   brew install ollama
   
   # Linux:
   curl -fsSL https://ollama.com/install.sh | sh
   
   # Or download from: https://ollama.com/download
   ```

3. **Start Ollama and pull the embedding model**
   ```bash
   # Start Ollama server
   ollama serve
   
   # In another terminal, pull the model
   ollama pull nomic-embed-text
   ```

## Installation

```bash
# Clone the repository
git clone https://github.com/ryanmcgarvey/ragify.git
cd ragify

# Install dependencies
bundle install

# Make the CLI executable
chmod +x exe/ragify

# Install the gem locally
bundle exec rake install
```

## Quick Start

```bash
# 1. Initialize Ragify in your Ruby project
cd /path/to/your/ruby/project
ragify init

# 2. Index your codebase (Day 2+)
ragify index

# 3. Search for code (Day 5+)
ragify search "user authentication"
ragify search "database queries"
ragify search "api endpoints"
```

## Day 1 Completion ✓

The following Day 1 tasks are complete:

- ✅ Gem structure created with Bundler
- ✅ `exe/ragify` executable setup
- ✅ Core dependencies added to gemspec
- ✅ Basic CLI structure with Thor
  - `ragify init` - Initialize Ragify
  - `ragify index` - Index files (discovers files)
  - `ragify search` - Search (stub)
  - `ragify status` - Show status (stub)
  - `ragify version` - Show version
- ✅ File discovery implemented
  - Recursive Ruby file discovery
  - Ignore patterns (.ragifyignore)
  - Binary file detection
- ✅ Basic file reading and validation
  - Encoding error handling
  - Empty file detection
- ✅ Project structure created
  - `lib/ragify/cli.rb` - Thor CLI
  - `lib/ragify/config.rb` - Configuration management
  - `lib/ragify/indexer.rb` - File discovery & validation
  - `lib/ragify/chunker.rb` - (stub for Day 2)
  - `lib/ragify/embedder.rb` - (stub for Day 3)
  - `lib/ragify/store.rb` - (stub for Day 4)
  - `lib/ragify/searcher.rb` - (stub for Day 5)

### Testing Day 1

```bash
# Test the CLI
./exe/ragify --version

# Initialize in a test project
cd ~/your-test-project
./exe/ragify init

# Test file discovery with verbose output
./exe/ragify index --verbose
```

Expected output:
```
Found 42 Ruby files
  Found: app/controllers/users_controller.rb
  Found: app/models/user.rb
  Found: lib/authentication.rb
  ...

Ready to index 42 files
```

## Configuration

After running `ragify init`, you'll have a `.ragify/config.yml` file:

```yaml
# Ollama server URL
ollama_url: http://localhost:11434

# Embedding model to use
model: nomic-embed-text

# Maximum lines per code chunk
chunk_size_limit: 1000

# Default number of search results
search_result_limit: 5

# Ignore patterns
ignore_patterns:
  - spec/**/*
  - test/**/*
  - vendor/**/*
```

## Architecture

```
┌─────────────────┐
│   Ragify CLI    │  (Thor-based CLI)
└────────┬────────┘
         │
    ┌────┴────┐
    │         │
┌───▼────┐ ┌─▼────────┐
│Indexer │ │Searcher  │
└───┬────┘ └─┬────────┘
    │        │
┌───▼────┐ ┌▼─────────┐
│Chunker │ │Embedder  │  → Ollama (nomic-embed-text)
└───┬────┘ └─┬────────┘
    │        │
    └───┬────┘
        │
   ┌────▼────┐
   │  Store  │  → SQLite + Vector Extension
   └─────────┘
```

## Why These Technologies?

- **Ollama + nomic-embed-text**: Best local embedding model for code
  - 768 dimensions (good balance)
  - 8K context window (handles large methods)
  - Fast and accurate for technical content
  
- **SQLite**: Simple, portable, no server needed
  - Vector extension for similarity search
  - Single file database
  
- **Parser gem**: Robust Ruby AST parsing
  - Handles modern Ruby syntax
  - Extracts semantic structure

## Development

```bash
# Run tests
bundle exec rspec

# Run linter
bundle exec rubocop

# Run tests and linting
bundle exec rake

# Install locally for testing
bundle exec rake install

# Build gem
bundle exec rake build
```

## Roadmap

See [ragify_roadmap.md](ragify_roadmap.md) for the complete 7-day development plan.

### Next Steps (Day 2)

- Implement Ruby code parsing with Parser gem
- Build intelligent chunking system
- Extract classes, modules, methods with metadata
- Create structured chunk data format

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ryanmcgarvey/ragify.

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).

## Acknowledgments

- Built with [Ollama](https://ollama.com) for local AI embeddings
- Uses [nomic-embed-text](https://huggingface.co/nomic-ai/nomic-embed-text-v1) for code embeddings
- Inspired by the need for better code search in large Ruby projects