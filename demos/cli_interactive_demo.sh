#!/usr/bin/env bash
# Interactive CLI Demo for Ragify
# This script creates test scenarios and shows how ragify index behaves

set -e

DEMO_DIR="ragify_cli_demo"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "================================================================================"
echo "                    Ragify CLI Interactive Demo"
echo "================================================================================"
echo ""
echo "This demo will create test scenarios and show ragify index in action."
echo ""

# Cleanup function
cleanup() {
    if [ -d "$DEMO_DIR" ]; then
        rm -rf "$DEMO_DIR"
        echo "Cleaned up demo directory"
    fi
}

# Setup demo directory
setup_demo_dir() {
    echo -e "${CYAN}Setting up demo directory...${NC}"
    cleanup
    mkdir -p "$DEMO_DIR"/{app/models,app/controllers,lib,vendor,spec}
    cd "$DEMO_DIR"
    
    # Initialize ragify
    ragify init --force 2>/dev/null || {
        echo -e "${RED}Error: ragify not found. Please install it first:${NC}"
        echo "  bundle exec rake install"
        echo "  asdf reshim ruby  # if using asdf"
        exit 1
    }
    
    echo -e "${GREEN}✓ Demo directory created${NC}"
    echo ""
}

# Create good files
create_good_files() {
    echo -e "${CYAN}Creating valid Ruby files...${NC}"
    
    # User model
    cat > app/models/user.rb << 'EOF'
# User model with authentication
class User < ApplicationRecord
  # Role constants
  ADMIN = "admin"
  USER = "user"
  
  def initialize(name, email)
    @name = name
    @email = email
  end
  
  # Authenticate user
  def authenticate(password)
    BCrypt::Password.new(@password_digest) == password
  end
  
  private
  
  def validate_email
    @email.match?(/\A[\w+\-.]+@[a-z\d\-.]+\.[a-z]+\z/i)
  end
end
EOF

    # Post model
    cat > app/models/post.rb << 'EOF'
class Post < ApplicationRecord
  belongs_to :user
  
  def publish
    update(published: true)
  end
  
  def self.recent(limit = 10)
    order(created_at: :desc).limit(limit)
  end
end
EOF

    # Controller
    cat > app/controllers/users_controller.rb << 'EOF'
# Users controller
class UsersController < ApplicationController
  before_action :authenticate_user
  
  def index
    @users = User.all
  end
  
  def show
    @user = User.find(params[:id])
  end
  
  private
  
  def authenticate_user
    redirect_to login_path unless current_user
  end
end
EOF

    # Library module
    cat > lib/authentication.rb << 'EOF'
module Authentication
  def self.hash_password(password)
    BCrypt::Password.create(password)
  end
  
  def self.verify_password(password, hash)
    BCrypt::Password.new(hash) == password
  end
end
EOF

    echo -e "${GREEN}✓ Created 4 valid Ruby files${NC}"
    echo ""
}

# Create broken files
create_broken_files() {
    echo -e "${CYAN}Creating files with syntax errors...${NC}"
    
    # Broken controller (missing end)
    cat > app/controllers/broken_controller.rb << 'EOF'
class BrokenController < ApplicationController
  def index
    @items = Item.all
    render "Unclosed string
  end
end
EOF

    # File with syntax error  
    cat > lib/old_legacy.rb << 'EOF'
class Legacy
  def process
    puts "Another unterminated string
  end
end
EOF
    
    echo -e "${GREEN}✓ Created 2 broken files${NC}"
    echo ""
}

# Scenario 1: Perfect success
scenario_perfect() {
    echo "================================================================================"
    echo "                         SCENARIO 1: Perfect Success"
    echo "================================================================================"
    echo ""
    echo "All files parse correctly. No errors."
    echo ""
    echo -e "${YELLOW}Press Enter to run: ragify index${NC}"
    read
    
    setup_demo_dir
    create_good_files
    
    echo -e "${BLUE}Running: ragify index${NC}"
    echo ""
    ragify index
    
    echo ""
    echo -e "${GREEN}✓ Success! All files indexed cleanly.${NC}"
    echo ""
    cd ..
    cleanup
}

# Scenario 2: Some errors (default mode with prompt)
scenario_with_errors() {
    echo "================================================================================"
    echo "                   SCENARIO 2: Some Errors (Default Mode)"
    echo "================================================================================"
    echo ""
    echo "Most files are good, but 2 have syntax errors."
    echo "You'll see the errors and be prompted to continue."
    echo ""
    echo -e "${YELLOW}Press Enter to run: ragify index${NC}"
    read
    
    setup_demo_dir
    create_good_files
    create_broken_files
    
    echo -e "${BLUE}Running: ragify index${NC}"
    echo ""
    
    # This will prompt the user
    ragify index || true
    
    echo ""
    echo -e "${CYAN}Notice:${NC}"
    echo "  • Processed all files despite errors"
    echo "  • Showed detailed error information"
    echo "  • Prompted you to continue"
    echo "  • Default was 'Yes' (just press Enter)"
    echo ""
    cd ..
    cleanup
}

# Scenario 3: Verbose mode
scenario_verbose() {
    echo "================================================================================"
    echo "                      SCENARIO 3: Verbose Mode"
    echo "================================================================================"
    echo ""
    echo "Same as scenario 2, but with --verbose flag."
    echo "You'll see each file being processed and every chunk extracted."
    echo ""
    echo -e "${YELLOW}Press Enter to run: ragify index --verbose${NC}"
    read
    
    setup_demo_dir
    create_good_files
    create_broken_files
    
    echo -e "${BLUE}Running: ragify index --verbose${NC}"
    echo ""
    ragify index --verbose || true
    
    echo ""
    echo -e "${CYAN}Notice:${NC}"
    echo "  • Shows each file being processed"
    echo "  • Lists every chunk extracted"
    echo "  • Shows chunk types and context"
    echo "  • Useful for debugging"
    echo ""
    cd ..
    cleanup
}

# Scenario 4: Strict mode (CI/CD)
scenario_strict() {
    echo "================================================================================"
    echo "                    SCENARIO 4: Strict Mode (--strict)"
    echo "================================================================================"
    echo ""
    echo "Simulates CI/CD environment. Fails immediately on first error."
    echo "No prompt. Exit code 1."
    echo ""
    echo -e "${YELLOW}Press Enter to run: ragify index --strict${NC}"
    read
    
    setup_demo_dir
    create_good_files
    create_broken_files
    
    echo -e "${BLUE}Running: ragify index --strict${NC}"
    echo ""
    
    if ragify index --strict; then
        echo -e "${GREEN}All files passed${NC}"
    else
        EXIT_CODE=$?
        echo ""
        echo -e "${RED}✗ Failed with exit code: $EXIT_CODE${NC}"
        echo ""
        echo -e "${CYAN}Notice:${NC}"
        echo "  • Stopped on first error"
        echo "  • No prompt"
        echo "  • Non-zero exit code (for CI/CD)"
        echo "  • Perfect for automated testing"
    fi
    
    echo ""
    cd ..
    cleanup
}

# Scenario 5: Force mode (--yes)
scenario_force() {
    echo "================================================================================"
    echo "                     SCENARIO 5: Force Mode (--yes)"
    echo "================================================================================"
    echo ""
    echo "Continues automatically without prompting."
    echo "Good for automation/scripts."
    echo ""
    echo -e "${YELLOW}Press Enter to run: ragify index --yes${NC}"
    read
    
    setup_demo_dir
    create_good_files
    create_broken_files
    
    echo -e "${BLUE}Running: ragify index --yes${NC}"
    echo ""
    ragify index --yes
    
    echo ""
    echo -e "${CYAN}Notice:${NC}"
    echo "  • Shows errors but doesn't prompt"
    echo "  • Continues automatically"
    echo "  • Good for cron jobs, scripts"
    echo "  • Still shows what failed"
    echo ""
    cd ..
    cleanup
}

# Scenario 6: Too many failures
scenario_mass_failure() {
    echo "================================================================================"
    echo "                   SCENARIO 6: Mass Failure (>20%)"
    echo "================================================================================"
    echo ""
    echo "When >20% of files fail, ragify assumes something is wrong"
    echo "and exits automatically (likely wrong Ruby/Parser version)."
    echo ""
    echo -e "${YELLOW}Press Enter to create scenario${NC}"
    read
    
    setup_demo_dir
    
    # Create 10 files: 3 good, 7 broken (70% failure)
    create_good_files
    
    echo -e "${CYAN}Creating many broken files...${NC}"
    for i in {1..7}; do
        cat > "lib/broken_${i}.rb" << 'EOF'
class Broken
  def method
    puts "Unclosed string
  end
end
EOF
    done
    
    echo -e "${GREEN}✓ Created 7 more broken files (70% will fail)${NC}"
    echo ""
    echo -e "${BLUE}Running: ragify index${NC}"
    echo ""
    
    if ragify index; then
        echo -e "${GREEN}Somehow passed${NC}"
    else
        EXIT_CODE=$?
        echo ""
        echo -e "${RED}✗ Auto-failed due to high failure rate${NC}"
        echo ""
        echo -e "${CYAN}Notice:${NC}"
        echo "  • Detected >20% failure rate"
        echo "  • Automatically exited"
        echo "  • Suggests checking Ruby/Parser version"
        echo "  • Prevents wasting time on bad configuration"
    fi
    
    echo ""
    cd ..
    cleanup
}

# Main menu
show_menu() {
    echo ""
    echo "================================================================================"
    echo "                             Demo Scenarios"
    echo "================================================================================"
    echo ""
    echo "Choose a scenario to run:"
    echo ""
    echo "  1) Perfect Success - All files parse correctly"
    echo "  2) Some Errors (Default) - Shows prompt, you decide"
    echo "  3) Verbose Mode - See every chunk extracted"
    echo "  4) Strict Mode - Fail on first error (CI/CD)"
    echo "  5) Force Mode - No prompts (automation)"
    echo "  6) Mass Failure - >20% fail, auto-abort"
    echo "  7) Run All Scenarios"
    echo "  q) Quit"
    echo ""
    echo -n "Enter choice [1-7, q]: "
}

# Run all scenarios
run_all() {
    scenario_perfect
    echo -e "${YELLOW}Press Enter to continue to next scenario...${NC}"
    read
    
    scenario_with_errors
    echo -e "${YELLOW}Press Enter to continue to next scenario...${NC}"
    read
    
    scenario_verbose
    echo -e "${YELLOW}Press Enter to continue to next scenario...${NC}"
    read
    
    scenario_strict
    echo -e "${YELLOW}Press Enter to continue to next scenario...${NC}"
    read
    
    scenario_force
    echo -e "${YELLOW}Press Enter to continue to next scenario...${NC}"
    read
    
    scenario_mass_failure
    
    echo ""
    echo -e "${GREEN}✓ All scenarios complete!${NC}"
}

# Main loop
main() {
    trap cleanup EXIT
    
    while true; do
        show_menu
        read choice
        
        case $choice in
            1) scenario_perfect ;;
            2) scenario_with_errors ;;
            3) scenario_verbose ;;
            4) scenario_strict ;;
            5) scenario_force ;;
            6) scenario_mass_failure ;;
            7) run_all ;;
            q|Q) 
                echo ""
                echo "Thanks for trying the demo!"
                cleanup
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please enter 1-7 or q.${NC}"
                ;;
        esac
        
        echo ""
        echo -e "${YELLOW}Press Enter to return to menu...${NC}"
        read
    done
}

# Run main
main