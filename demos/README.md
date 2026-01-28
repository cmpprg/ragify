# Ragify CLI Demos - README

This package contains **two types of demos** to help you understand how `ragify index` works.

---

## Quick Start (5 seconds)

**Want to see it NOW?**

```bash
chmod +x demo_cli_quick.sh
./demo_cli_quick.sh
```

This runs immediately and shows the most common scenario: indexing with some errors.

---

## Demo Files Overview

### 1. Executable Demos (Run These)

#### `demo_cli_quick.sh` - Fast Demo
- **Time:** ~30 seconds
- **What it shows:** Default behavior with errors and prompting
- **Setup:** Creates 3 good files + 1 broken file
- **Best for:** "Just show me how it works!"

#### `demo_cli_interactive.sh` - Full Demo
- **Time:** 5-10 minutes (you control the pace)
- **What it shows:** All 6 scenarios with interactive menu
- **Best for:** Understanding all modes and edge cases

### 2. Reference Documents (Read These)

#### `CLI_DEMO_EXPECTED_OUTPUT.md` - Expected Output
- Shows exactly what output looks like for each scenario
- Comparison table of all modes
- Common questions answered
- **Best for:** Understanding before running, or reviewing after

---

## Which Demo Should I Use?

### Use `demo_cli_quick.sh` if:
- ✓ You want to see it work RIGHT NOW
- ✓ You're new to Ragify
- ✓ You just want the default behavior
- ✓ You have 30 seconds

### Use `demo_cli_interactive.sh` if:
- ✓ You want to understand all the modes
- ✓ You're testing for CI/CD integration
- ✓ You want to see edge cases
- ✓ You have 5-10 minutes

### Read `CLI_DEMO_EXPECTED_OUTPUT.md` if:
- ✓ You can't run the demos (no ragify installed yet)
- ✓ You want to know what to expect
- ✓ You're writing documentation
- ✓ You're debugging unexpected output

---

## Prerequisites

Both demos require `ragify` to be installed:

```bash
# From your ragify project directory
bundle install
bundle exec rake install
asdf reshim ruby  # if using asdf
rbenv rehash      # if using rbenv

# Verify it works
ragify --version
```

---

## Quick Demo Details

**What `demo_cli_quick.sh` does:**

1. Creates a temp directory `ragify_quick_demo`
2. Initializes ragify
3. Creates 3 valid Ruby files (User, Post, Controller)
4. Creates 1 broken file (missing `end`)
5. Runs `ragify index`
6. Shows you the error and prompts
7. Cleans up

**Expected output:**
- 3/4 files succeed
- ~15 chunks extracted
- 1 error shown with line number
- Prompt: "Continue with embedding 15 chunks? (Y/n)"

---

## Interactive Demo Details

**What `demo_cli_interactive.sh` does:**

Shows 6 scenarios via menu:

1. **Perfect Success** - All files parse cleanly
2. **Some Errors** - Default mode with prompt
3. **Verbose Mode** - See every chunk extracted
4. **Strict Mode** - Fail on first error (CI/CD)
5. **Force Mode** - No prompts (automation)
6. **Mass Failure** - >20% fail rate auto-abort

**Menu:**
```
Choose a scenario to run:

  1) Perfect Success
  2) Some Errors (Default)
  3) Verbose Mode
  4) Strict Mode
  5) Force Mode
  6) Mass Failure
  7) Run All Scenarios
  q) Quit

Enter choice [1-7, q]:
```

Each scenario:
- Explains what it demonstrates
- Creates appropriate test files
- Runs the ragify command
- Shows what to notice
- Returns to menu

---

## Running the Demos

### Quick Demo

```bash
chmod +x demo_cli_quick.sh
./demo_cli_quick.sh

# Follow the prompts
# Takes ~30 seconds
```

### Interactive Demo

```bash
chmod +x demo_cli_interactive.sh
./demo_cli_interactive.sh

# Choose scenarios from menu
# Press 'q' to quit
```

---

## What You'll Learn

After running the demos, you'll understand:

✓ **Default behavior** - Shows errors, prompts to continue
✓ **Error reporting** - Detailed, batched, actionable
✓ **Prompting** - When it prompts, what the default is
✓ **Strict mode** - For CI/CD, fails immediately
✓ **Force mode** - For automation, no prompts
✓ **Verbose mode** - See every file and chunk
✓ **Auto-fail** - When >20% fail, suggests config issue
✓ **Exit codes** - 0 for success, 1 for failure

---

## Example Workflows

### Local Development Workflow

```bash
# Edit some code...
vim app/models/user.rb

# Index it (might have temp errors mid-edit)
ragify index
# See errors, decide to continue anyway
# Press Enter

# Later, fix the errors and re-index
ragify index
# Clean success!
```

### CI/CD Workflow

```bash
# In your CI script
ragify index --strict

if [ $? -eq 0 ]; then
  echo "All files parsed successfully"
  # Continue to embedding/testing
else
  echo "Parsing failed - fix syntax errors"
  exit 1
fi
```

### Automation Workflow

```bash
# Cron job that indexes nightly
0 2 * * * cd /app && ragify index --yes >> /var/log/ragify.log 2>&1
```

---

## Troubleshooting

### "ragify: command not found"

```bash
# Install it
cd /path/to/ragify
bundle exec rake install

# Reshim
asdf reshim ruby    # if using asdf
rbenv rehash        # if using rbenv

# Test
ragify --version
```

### "Permission denied"

```bash
chmod +x demo_cli_quick.sh
chmod +x demo_cli_interactive.sh
```

### Demo creates files in wrong place

Demos create temporary directories that are cleaned up automatically:
- `ragify_quick_demo` - Quick demo
- `ragify_cli_demo` - Interactive demo

Both are deleted when demo completes.

---

## Cleanup

Demos clean up after themselves, but if something goes wrong:

```bash
rm -rf ragify_quick_demo
rm -rf ragify_cli_demo
```

---

## Next Steps

After understanding the CLI:

1. **Install in your project:**
   ```bash
   cd ~/your-ruby-project
   ragify init
   ```

2. **Index your code:**
   ```bash
   ragify index
   ```

3. **Fix any errors** and re-index

4. **Move to Day 3:** Ollama embeddings

---

## Files in This Package

```
CLI Demos/
├── demo_cli_quick.sh              # Quick demo (30 sec)
├── demo_cli_interactive.sh        # Interactive menu demo
├── CLI_DEMO_EXPECTED_OUTPUT.md    # Expected output reference
└── README.md                      # This file
```

---

## Questions?

**Q: Do I need to run both demos?**
A: No. Quick demo is enough for most people.

**Q: Can I run the demos multiple times?**
A: Yes! They clean up after themselves.

**Q: Will this affect my project?**
A: No. Demos create isolated temp directories.

**Q: What if I just want to see the output?**
A: Read `CLI_DEMO_EXPECTED_OUTPUT.md` - it shows everything.

**Q: Can I modify the demos?**
A: Absolutely! They're bash scripts. Edit and experiment.

---

**Enjoy the demos!** 🚀

Once you understand the CLI, you're ready for Day 3 (Ollama embeddings).