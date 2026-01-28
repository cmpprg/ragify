# Ragify CLI Demo - Expected Output

This document shows what you'll see when running `ragify index` in different scenarios.

---

## Scenario 1: Perfect Success ✓

**Command:** `ragify index`

**Setup:** 4 valid Ruby files, no errors

**Output:**
```
Indexing project: /path/to/ragify_cli_demo

Discovering Ruby files...
Found 4 Ruby files

Parsing and chunking files...
[████████████████████████████████████████] 4/4 100% 

✓ Successfully processed: 4 files → 15 chunks

Chunks extracted:
  Classes: 4
  Modules: 1
  Methods: 10
  Constants: 2

  Total chunks: 15

Next: Embeddings (Day 3) and Storage (Day 4)
```

**Result:** ✓ Clean success, no errors, ready for embedding

---

## Scenario 2: Some Errors (Default Mode)

**Command:** `ragify index`

**Setup:** 4 good files + 2 broken files (33% failure)

**Output:**
```
Indexing project: /path/to/ragify_cli_demo

Discovering Ruby files...
Found 6 Ruby files

Parsing and chunking files...
[████████████████████████████████████████] 6/6 100% 

✓ Successfully processed: 4 files → 15 chunks
⚠️  Skipped 2 file(s) with errors:

  app/controllers/broken_controller.rb:5
    Syntax error: unexpected end-of-input, expecting `end`
    
  lib/old_legacy.rb:4
    Syntax error: invalid multibyte char (UTF-8)

────────────────────────────────────────────────────────────
These files were NOT indexed and won't be searchable.

Continue with embedding 15 chunks? (Y/n) █
```

**If you press Enter (Yes - default):**
```
Chunks extracted:
  Classes: 4
  Modules: 1
  Methods: 10
  Constants: 2

  Total chunks: 15

Next: Embeddings (Day 3) and Storage (Day 4)
```

**If you type 'n':**
```
Indexing cancelled.
Fix the errors above and run: ragify index
```

**Result:** User makes informed decision whether to continue

---

## Scenario 3: Verbose Mode

**Command:** `ragify index --verbose`

**Setup:** Same as scenario 2 (4 good + 2 broken)

**Output:**
```
Indexing project: /path/to/ragify_cli_demo

Discovering Ruby files...
Found 6 Ruby files

Files to index:
  - app/models/user.rb
  - app/models/post.rb
  - app/controllers/users_controller.rb
  - app/controllers/broken_controller.rb
  - lib/authentication.rb
  - lib/old_legacy.rb

Parsing and chunking files...

  app/models/user.rb: 6 chunks
    - class: User
    - constant: ADMIN (class User)
    - constant: USER (class User)
    - method: initialize (class User)
    - method: authenticate (class User)
    - method: validate_email (class User)

  app/models/post.rb: 3 chunks
    - class: Post
    - method: publish (class Post)
    - method: recent (class Post)

  app/controllers/users_controller.rb: 5 chunks
    - class: UsersController
    - method: index (class UsersController)
    - method: show (class UsersController)
    - method: authenticate_user (class UsersController)

✗ app/controllers/broken_controller.rb:5

  lib/authentication.rb: 3 chunks
    - module: Authentication
    - method: hash_password (module Authentication)
    - method: verify_password (module Authentication)

✗ lib/old_legacy.rb:4

[████████████████████████████████████████] 6/6 100% 

✓ Successfully processed: 4 files → 15 chunks
⚠️  Skipped 2 file(s) with errors:

  app/controllers/broken_controller.rb:5
    Syntax error: unexpected end-of-input, expecting `end`
    
  lib/old_legacy.rb:4
    Syntax error: invalid multibyte char (UTF-8)

────────────────────────────────────────────────────────────
These files were NOT indexed and won't be searchable.

Continue with embedding 15 chunks? (Y/n) █
```

**Result:** Detailed view of every file and chunk processed

---

## Scenario 4: Strict Mode (CI/CD)

**Command:** `ragify index --strict`

**Setup:** 4 good files + 2 broken files

**Output:**
```
Indexing project: /path/to/ragify_cli_demo

Discovering Ruby files...
Found 6 Ruby files

Parsing and chunking files...
[████████████████████] 4/6 67% 

Error in app/controllers/broken_controller.rb:5
  unexpected end-of-input, expecting `end`

Exiting due to --strict flag
```

**Exit code:** `1`

**Result:** ✗ Fails immediately on first error, no prompt, non-zero exit

**Use case:** CI/CD pipelines that require 100% parseable code

---

## Scenario 5: Force Mode (--yes)

**Command:** `ragify index --yes`

**Setup:** 4 good files + 2 broken files

**Output:**
```
Indexing project: /path/to/ragify_cli_demo

Discovering Ruby files...
Found 6 Ruby files

Parsing and chunking files...
[████████████████████████████████████████] 6/6 100% 

✓ Successfully processed: 4 files → 15 chunks
⚠️  Skipped 2 file(s) with errors:

  app/controllers/broken_controller.rb:5
    Syntax error: unexpected end-of-input, expecting `end`
    
  lib/old_legacy.rb:4
    Syntax error: invalid multibyte char (UTF-8)

────────────────────────────────────────────────────────────
These files were NOT indexed and won't be searchable.

Chunks extracted:
  Classes: 4
  Modules: 1
  Methods: 10
  Constants: 2

  Total chunks: 15

Next: Embeddings (Day 3) and Storage (Day 4)
```

**Result:** Shows errors but continues automatically (no prompt)

**Use case:** Automation, cron jobs, scripts where interaction isn't possible

---

## Scenario 6: Mass Failure (>20%)

**Command:** `ragify index`

**Setup:** 3 good files + 7 broken files (70% failure rate)

**Output:**
```
Indexing project: /path/to/ragify_cli_demo

Discovering Ruby files...
Found 10 Ruby files

Parsing and chunking files...
[████████████████████████████████████████] 10/10 100% 

✓ Successfully processed: 3 files → 10 chunks
⚠️  Skipped 7 file(s) with errors:

  app/controllers/broken_controller.rb:5
    Syntax error: unexpected end-of-input, expecting `end`
    
  lib/old_legacy.rb:4
    Syntax error: invalid multibyte char (UTF-8)
    
  lib/broken_1.rb:3
    Syntax error: unexpected end-of-input, expecting `end`
    
  lib/broken_2.rb:3
    Syntax error: unexpected end-of-input, expecting `end`
    
  lib/broken_3.rb:3
    Syntax error: unexpected end-of-input, expecting `end`
    
  lib/broken_4.rb:3
    Syntax error: unexpected end-of-input, expecting `end`
    
  lib/broken_5.rb:3
    Syntax error: unexpected end-of-input, expecting `end`

────────────────────────────────────────────────────────────
These files were NOT indexed and won't be searchable.

❌ Failed to parse 7/10 files (>20%)
This likely indicates a configuration problem.
Check your Ruby version and Parser gem compatibility.
```

**Exit code:** `1`

**Result:** Auto-fails when too many files fail (doesn't prompt)

**Reason:** High failure rate suggests wrong Parser version or Ruby version mismatch

---

## Comparison Table

| Scenario | Files Fail | Prompt? | Exit Code | Use Case |
|----------|-----------|---------|-----------|----------|
| Perfect Success | 0 | No | 0 | Happy path |
| Default Mode | Some | Yes | 0 (if continue) | Local development |
| Verbose Mode | Some | Yes | 0 (if continue) | Debugging |
| Strict Mode | Any | No | 1 | CI/CD |
| Force Mode | Some | No | 0 | Automation |
| Mass Failure | >20% | No | 1 | Config problem |

---

## Flag Reference

```bash
# Default: Continue with prompt on errors
ragify index

# Strict: Fail on first error (CI/CD)
ragify index --strict

# Force: No prompts, continue automatically
ragify index --yes

# Verbose: See every file and chunk
ragify index --verbose

# Combine flags
ragify index --verbose --yes
ragify index --verbose --strict
```

---

## Testing the Demo

### Option 1: Run Interactive Demo

```bash
chmod +x demo_cli_interactive.sh
./demo_cli_interactive.sh

# Then choose scenarios from menu:
# 1) Perfect Success
# 2) Some Errors (Default)
# 3) Verbose Mode
# 4) Strict Mode
# 5) Force Mode
# 6) Mass Failure
# 7) Run All Scenarios
```

### Option 2: Manual Testing

```bash
# Create test directory
mkdir test_ragify && cd test_ragify

# Initialize
ragify init

# Create a good file
cat > good.rb << 'EOF'
class GoodClass
  def method
    puts "works"
  end
end
EOF

# Create a broken file
cat > broken.rb << 'EOF'
class BrokenClass
  def method
    # missing end
EOF

# Test default mode
ragify index

# Test strict mode
ragify index --strict

# Test force mode
ragify index --yes

# Test verbose mode
ragify index --verbose
```

---

## What to Look For

### ✓ Good Signs

- Progress bar completes to 100%
- Clear separation of success/failure counts
- Errors show file path and line number
- Error messages are actionable
- Chunks are categorized (classes, modules, methods)
- Total chunk count shown

### ⚠️ Warning Signs

- No prompt when errors exist (in default mode)
- Unclear error messages
- Can't tell which files failed
- No chunk breakdown by type
- Exit code not appropriate for mode

### ✗ Bad Signs

- Creates error chunks in output
- Continues silently with errors (should prompt)
- Doesn't show what's missing
- Unclear consequences of continuing
- Non-zero exit on success

---

## Common Questions

### Q: Why does it still process all files even with errors?

**A:** So you see ALL errors at once, not one-by-one. Fix everything, then re-index once.

### Q: What happens to the broken files?

**A:** They're skipped. No chunks created. Not searchable. You must fix and re-index.

### Q: Can I index anyway and fix later?

**A:** Yes! Press Enter at the prompt. The working files will be indexed and searchable.

### Q: What if I'm in a script and can't respond to prompts?

**A:** Use `--yes` flag: `ragify index --yes`

### Q: What if I need strict parsing for CI/CD?

**A:** Use `--strict` flag: `ragify index --strict`

### Q: Why does >20% failure auto-fail?

**A:** Suggests wrong Ruby/Parser version. Better to fail fast than index garbage.

---

## Success Criteria

After running these scenarios, you should understand:

✓ How error reporting works (batch, detailed)
✓ When prompts appear (default mode, errors exist)
✓ How to skip prompts (--yes, --strict)
✓ When auto-fail occurs (>20% failures)
✓ What verbose mode shows (every file/chunk)
✓ Exit codes for different scenarios
✓ Which mode for which use case

**Next:** Ready for Day 3 (Ollama embeddings)!