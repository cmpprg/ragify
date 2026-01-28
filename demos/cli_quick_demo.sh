#!/usr/bin/env bash
# Quick CLI Demo for Ragify - Runs Immediately
# Shows the default behavior with some errors

set -e

DEMO_DIR="ragify_quick_demo"
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "================================================================================"
echo "                  Ragify CLI - Quick Demo"
echo "================================================================================"
echo ""
echo "This demo shows ragify index with some errors (default behavior)."
echo ""

# Cleanup
cleanup() {
    if [ -d "$DEMO_DIR" ]; then
        rm -rf "$DEMO_DIR"
    fi
}

trap cleanup EXIT

# Setup
echo -e "${CYAN}Setting up demo files...${NC}"
cleanup
mkdir -p "$DEMO_DIR"/{app/models,app/controllers,lib}
cd "$DEMO_DIR"

# Initialize ragify
ragify init --force > /dev/null 2>&1 || {
    echo "Error: ragify not found. Install it first:"
    echo "  bundle exec rake install"
    echo "  asdf reshim ruby"
    exit 1
}

# Create good files
echo -e "${CYAN}Creating 6 valid Ruby files...${NC}"

cat > app/models/user.rb << 'EOF'
class User < ApplicationRecord
  ADMIN = "admin"
  USER = "user"
  
  def initialize(name, email)
    @name = name
    @email = email
  end
  
  def authenticate(password)
    verify_password(password)
  end
  
  private
  
  def verify_password(password)
    BCrypt::Password.new(@password_digest) == password
  end
end
EOF

cat > app/models/post.rb << 'EOF'
class Post < ApplicationRecord
  belongs_to :user
  
  def publish
    update(published: true, published_at: Time.now)
  end
  
  def self.recent(limit = 10)
    order(created_at: :desc).limit(limit)
  end
  
  def preview
    body.truncate(100)
  end
end
EOF

cat > app/models/comment.rb << 'EOF'
class Comment < ApplicationRecord
  belongs_to :post
  belongs_to :user
  
  validates :body, presence: true
  
  def author_name
    user.name
  end
end
EOF

cat > app/controllers/posts_controller.rb << 'EOF'
class PostsController < ApplicationController
  before_action :find_post, only: [:show, :edit, :update]
  
  def index
    @posts = Post.recent(20)
  end
  
  def show
    # @post set by before_action
  end
  
  def create
    @post = Post.new(post_params)
    @post.save!
  end
  
  private
  
  def find_post
    @post = Post.find(params[:id])
  end
  
  def post_params
    params.require(:post).permit(:title, :body)
  end
end
EOF

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

cat > lib/mailer_helper.rb << 'EOF'
module MailerHelper
  def format_email(user)
    "#{user.name} <#{user.email}>"
  end
  
  def send_notification(user, message)
    UserMailer.notification(user, message).deliver_later
  end
end
EOF

# Create broken file
echo -e "${CYAN}Creating 1 broken file (syntax error)...${NC}"

cat > lib/broken.rb << 'EOF'
class BrokenClass
  def process
    puts "This string is not closed
  end
end
EOF

echo -e "${GREEN}✓ Setup complete${NC}"
echo ""
echo "Files created:"
echo "  ✓ app/models/user.rb (valid)"
echo "  ✓ app/models/post.rb (valid)"
echo "  ✓ app/models/comment.rb (valid)"
echo "  ✓ app/controllers/posts_controller.rb (valid)"
echo "  ✓ lib/authentication.rb (valid)"
echo "  ✓ lib/mailer_helper.rb (valid)"
echo "  ✗ lib/broken.rb (syntax error)"
echo ""
echo "================================================================================"
echo ""
echo -e "${BLUE}Running: ragify index${NC}"
echo ""
echo "You should see:"
echo "  1. All 7 files processed"
echo "  2. 6 files succeed, 1 fails (14% - below 20% threshold)"
echo "  3. Error details shown"
echo "  4. Prompt asking if you want to continue"
echo "  5. Default is 'Yes' - just press Enter"
echo ""
echo "================================================================================"
echo ""

# Run ragify index
ragify index

echo ""
echo "================================================================================"
echo -e "${GREEN}Demo Complete!${NC}"
echo ""
echo "What happened:"
echo "  • Processed all 7 files (6 good + 1 broken)"
echo "  • Extracted chunks from 6 good files"
echo "  • Showed 1 file with syntax error (14% failure rate)"
echo "  • Prompted you to decide whether to continue"
echo ""
echo "Try these variations:"
echo "  ragify index --verbose      # See every chunk extracted"
echo "  ragify index --strict       # Would have failed immediately"
echo "  ragify index --yes          # Would skip prompt"
echo ""
echo "================================================================================"

cd ..
cleanup