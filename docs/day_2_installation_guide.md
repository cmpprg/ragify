# Day 2 Implementation - Installation Guide

## Files Delivered

1. **chunker.rb** - Complete Chunker class implementation (~450 lines)
2. **chunker_spec.rb** - Comprehensive test suite (15+ test contexts)
3. **cli.rb** - Updated CLI with chunker integration
4. **demo_chunker.rb** - Demonstration script
5. **DAY_2_COMPLETE.md** - Completion summary

## Installation Steps

### 1. Copy Files to Your Ragify Project

```bash
# Navigate to your Ragify project directory
cd /path/to/ragify

# Copy the chunker implementation
cp /path/to/downloads/chunker.rb lib/ragify/

# Copy the updated CLI
cp /path/to/downloads/cli.rb lib/ragify/

# Copy the test file
cp /path/to/downloads/chunker_spec.rb spec/

# Copy the demo script (optional)
cp /path/to/downloads/demo_chunker.rb ./
chmod +x demo_chunker.rb
```

### 2. Install Dependencies

The Parser gem is already in your gemspec from Day 1, but make sure it's installed:

```bash
bundle install
```

### 3. Run Tests

```bash
# Run all tests
bundle exec rspec

# Run just the chunker tests
bundle exec rspec spec/chunker_spec.rb

# Run with documentation format to see all test descriptions
bundle exec rspec spec/chunker_spec.rb --format documentation
```

Expected output:
```
Ragify::Chunker
  #chunk_file
    with a simple class
      ✓ extracts the class and methods
      ✓ generates unique IDs for each chunk
    with a module
      ✓ extracts the module and methods
    with nested classes
      ✓ preserves nested context
    ...

Finished in 0.5 seconds (files took 0.2 seconds to load)
35 examples, 0 failures
```

### 4. Install the Gem

```bash
# Build and install the gem locally
bundle exec rake install

# If using asdf
asdf reshim ruby

# If using rbenv
rbenv rehash
```

### 5. Test the CLI

```bash
# Test the updated index command
cd ~/your-test-project
ragify index --verbose
```

Expected output:
```
Indexing project: /Users/you/your-test-project

Discovering Ruby files...
Found 42 Ruby files

Parsing and chunking files...
  app/models/user.rb: 3 chunks
    - class: User
    - method: initialize (class User)
    - method: full_name (class User)
  ...

[████████████████████████████████] 42/42 100%

✓ Indexing complete!

Statistics:
  Total files: 42
  Successfully processed: 42

Chunks extracted:
  Classes: 15
  Modules: 8
  Methods: 87
  Constants: 12

  Total chunks: 122

Next: Embeddings (Day 3) and Storage (Day 4)
```

## Running the Demo Script

The demo script shows the chunker in action on sample code:

```bash
cd /path/to/ragify
./demo_chunker.rb
```

This will parse a sample Ruby file and display all extracted chunks with their metadata.

## Verification Checklist

- [ ] All tests pass (`bundle exec rspec`)
- [ ] Chunker tests specifically pass (`bundle exec rspec spec/chunker_spec.rb`)
- [ ] Gem installs without errors (`bundle exec rake install`)
- [ ] CLI runs and shows chunks (`ragify index --verbose`)
- [ ] Demo script runs successfully (`./demo_chunker.rb`)

## Testing on Your Own Code

Try indexing a real Ruby project:

```bash
# Index a Rails app
cd ~/projects/my-rails-app
ragify init
ragify index --verbose

# Index a gem
cd ~/projects/my-gem
ragify init
ragify index --verbose
```

Look for:
- Correct file discovery
- Successful parsing of all Ruby files
- Appropriate chunk extraction (classes, modules, methods)
- Proper context preservation for nested code
- Graceful handling of any syntax errors

## Troubleshooting

### Tests Failing

If tests fail, check:
1. Parser gem is installed: `bundle list | grep parser`
2. All files are in the correct locations
3. Run `bundle install` again

### CLI Not Finding Chunker

If you get `NotImplementedError`:
1. Make sure `chunker.rb` is in `lib/ragify/`
2. Reinstall the gem: `bundle exec rake install`
3. Reshim: `asdf reshim ruby` or `rbenv rehash`

### Syntax Errors in Test Files

Make sure you copied the files correctly and they weren't corrupted during transfer.

## What's Working Now

After Day 2 implementation:

✅ File discovery (Day 1)  
✅ Configuration system (Day 1)  
✅ **Code parsing with AST** (Day 2)  
✅ **Intelligent chunking** (Day 2)  
✅ **Metadata extraction** (Day 2)  
✅ **Context preservation** (Day 2)  
✅ **Edge case handling** (Day 2)  
✅ **CLI integration** (Day 2)

## Next: Day 3

Once Day 2 is installed and working, you're ready for Day 3:
- Ollama integration
- Embedding generation
- Batch processing
- Progress tracking

## Questions?

If you encounter any issues:
1. Check that all files are in the correct locations
2. Verify dependencies are installed: `bundle install`
3. Run tests to isolate the problem
4. Check the test output for specific error messages

---

**Ready to proceed to Day 3!** 🚀