# Ragify Day 1 - Quick Start Guide

## 🎉 Day 1 Complete!

All Day 1 tasks from the roadmap have been completed successfully. Here's how to get started with your new Ragify implementation.

---

## 📦 What You Received

A complete Day 1 implementation with:

```
ragify/
├── exe/
│   └── ragify                 # Main CLI executable
├── lib/
│   ├── ragify.rb             # Main module
│   └── ragify/
│       ├── cli.rb            # ✅ Thor CLI (complete)
│       ├── config.rb         # ✅ Configuration (complete)
│       ├── indexer.rb        # ✅ File discovery (complete)
│       ├── chunker.rb        # 📝 Stub (Day 2)
│       ├── embedder.rb       # 📝 Stub (Day 3)
│       ├── store.rb          # 📝 Stub (Day 4)
│       └── searcher.rb       # 📝 Stub (Day 5)
├── spec/
│   └── ragify_spec.rb        # Comprehensive tests
├── ragify.gemspec            # Updated with dependencies
├── README.md                 # Full documentation
└── DAY_1_COMPLETE.md         # Completion summary
```

---

## 🚀 Installation Steps

### 1. Copy Files to Your Ragify Project

If you already have a ragify gem directory from `bundle gem ragify`:

```bash
# Navigate to your ragify directory
cd /path/to/ragify

# Copy the new files (they will replace placeholders)
cp -r /path/to/download/ragify/* .

# Make the executable runnable
chmod +x exe/ragify
```

If you're starting fresh:

```bash
# Copy the entire directory
cp -r /path/to/download/ragify /path/to/your/projects/

cd ragify
```

### 2. Install Dependencies

```bash
# Install all gems
bundle install
```

This will install:
- sqlite3 (database)
- parser (Ruby AST parsing)
- thor (CLI framework)
- faraday (HTTP client)
- tty-progressbar, tty-prompt, pastel (UX)

### 3. Install Ollama (if not already installed)

```bash
# macOS
brew install ollama

# Linux
curl -fsSL https://ollama.com/install.sh | sh

# Or download from: https://ollama.com/download
```

### 4. Start Ollama and Pull Model

```bash
# Start Ollama server (in one terminal)
ollama serve

# In another terminal, pull the embedding model
ollama pull nomic-embed-text
```

### 5. Install Ragify Gem Locally

```bash
# From the ragify directory
bundle exec rake install
```

This makes `ragify` available system-wide for testing.

---

## ✅ Verify Installation

```bash
# Check version
ragify version
# Output: Ragify version 0.1.0

# Get help
ragify help
```

---

## 🎯 Test Day 1 Functionality

### Test 1: Initialize in a Sample Project

```bash
# Navigate to any Ruby project
cd ~/your-ruby-project

# Initialize Ragify
ragify init
```

Expected output:
```
Initializing Ragify...
✓ Created .ragify directory
✓ Created default configuration
✓ Created .ragifyignore file

Checking dependencies...
✓ Ollama is running
✓ nomic-embed-text model is available

✓ Ragify initialized successfully!

Next steps:
  1. Run: ragify index
  2. Run: ragify search "your query"
```

### Test 2: Discover Files

```bash
# Discover Ruby files (quiet mode)
ragify index

# Discover with detailed output
ragify index --verbose
```

Expected output:
```
Indexing project: /path/to/project
Found 42 Ruby files

Ready to index 42 files
```

With `--verbose`, you'll see each file discovered:
```
Discovering Ruby files in /path/to/project...
  Found: app/controllers/users_controller.rb
  Found: app/models/user.rb
  Found: lib/authentication.rb
  ...
```

### Test 3: Check Configuration

```bash
# After init, check the config file
cat .ragify/config.yml
```

You should see:
```yaml
ollama_url: http://localhost:11434
model: nomic-embed-text
chunk_size_limit: 1000
search_result_limit: 5
ignore_patterns:
  - spec/**/*
  - test/**/*
  ...
```

---

## 🧪 Run Tests

```bash
# From the ragify directory
cd /path/to/ragify

# Run all tests
bundle exec rspec

# Run with detailed output
bundle exec rspec --format documentation

# Run rubocop (code style)
bundle exec rubocop
```

All tests should pass! ✅

---

## 📁 File Ignore Patterns

Ragify automatically ignores:

**Default patterns**:
- .git/
- .ragify/
- vendor/
- node_modules/
- tmp/
- log/
- coverage/

**Configurable patterns** (.ragifyignore):
- spec/
- test/
- db/schema.rb
- (add your own)

**Config file patterns** (.ragify/config.yml):
- Additional patterns in ignore_patterns array

---

## 🎨 CLI Features

### Available Commands

```bash
# Show version
ragify version

# Initialize project
ragify init [--force]

# Index files
ragify index [PATH] [--verbose]

# Search (Day 5)
ragify search QUERY [--limit N] [--type TYPE] [--path PATTERN]

# Show status (Day 6)
ragify status

# Reindex (Day 6)
ragify reindex [--force]

# Help
ragify help [COMMAND]
```

### Color Output

The CLI uses colored output:
- 🔵 Cyan - Info messages
- 🟢 Green - Success
- 🟡 Yellow - Warnings
- 🔴 Red - Errors

---

## 🐛 Troubleshooting

### "Ollama not running"

```bash
# Start Ollama
ollama serve

# Verify it's running
curl http://localhost:11434/api/tags
```

### "nomic-embed-text model not found"

```bash
# Pull the model
ollama pull nomic-embed-text

# Verify it's installed
ollama list
```

### "No Ruby files found"

Check your .ragifyignore patterns. You might be ignoring too much!

```bash
# Test with verbose to see what's happening
ragify index --verbose
```

### Encoding errors

The indexer handles most encoding issues gracefully, but if you see problems:

1. Check file encoding: `file --mime your_file.rb`
2. Convert to UTF-8 if needed
3. Report the issue (this shouldn't happen!)

---

## 📊 What's Working vs. What's Coming

### ✅ Working Now (Day 1)

- File discovery
- Ignore patterns
- Configuration
- CLI framework
- Error handling
- Ollama connectivity check

### 📝 Coming Soon

- **Day 2**: Code parsing and chunking
- **Day 3**: Embedding generation
- **Day 4**: Vector storage
- **Day 5**: Semantic search
- **Day 6**: Polish and testing
- **Day 7**: Documentation and release

---

## 🎯 Example Workflow

Here's what a typical workflow looks like:

```bash
# 1. Navigate to your Ruby project
cd ~/my-rails-app

# 2. Initialize Ragify
ragify init
# Creates .ragify/, config, and .ragifyignore

# 3. Customize ignore patterns (optional)
echo "tmp/**/*" >> .ragifyignore

# 4. Discover files
ragify index --verbose
# Found 234 Ruby files

# 5. Wait for Days 2-5 implementation...
# Then you'll be able to:
ragify search "user authentication"
ragify search "database queries"
```

---

## 📚 Next Steps

1. **Review the code**:
   - Check out `lib/ragify/cli.rb` for CLI implementation
   - Look at `lib/ragify/indexer.rb` for file discovery
   - Understand `lib/ragify/config.rb` for configuration

2. **Test on real projects**:
   - Initialize in a Rails app
   - Initialize in a gem
   - Test ignore patterns work correctly

3. **Prepare for Day 2**:
   - Read about the Parser gem
   - Think about how to chunk code semantically
   - Consider edge cases (large files, nested modules)

4. **Give feedback**:
   - Does file discovery work well?
   - Are the ignore patterns comprehensive?
   - Is the CLI UX good?

---

## 💡 Tips

1. **Use verbose mode** when debugging:
   ```bash
   ragify index --verbose
   ```

2. **Check Ollama first**:
   ```bash
   ragify init  # This checks Ollama automatically
   ```

3. **Customize ignore patterns** for your project:
   ```bash
   # Add to .ragifyignore
   coverage/**/*
   docs/**/*
   ```

4. **Test incrementally**:
   - Start with `ragify init`
   - Then `ragify index --verbose`
   - Check the output makes sense

---

## 🎉 Congratulations!

You have a working Day 1 implementation of Ragify!

- ✅ File discovery works
- ✅ Configuration system is solid
- ✅ CLI is functional and user-friendly
- ✅ Ready for Day 2 implementation

**Next**: Move on to Day 2 to implement code parsing and chunking! 🚀

---

## 📞 Support

If you encounter any issues:

1. Check this guide first
2. Review DAY_1_COMPLETE.md for implementation details
3. Check the README.md for comprehensive documentation
4. Review the roadmap (ragify_roadmap.md) for context

Happy coding! 🎉