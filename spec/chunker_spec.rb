# frozen_string_literal: true

require "spec_helper"

RSpec.describe Ragify::Chunker do
  let(:config) { Ragify::Config.new }
  let(:chunker) { described_class.new(config) }

  describe "#chunk_file" do
    context "with a simple class" do
      let(:content) do
        <<~RUBY
          # A simple user class
          class User
            def initialize(name)
              @name = name
            end

            def greet
              "Hello, \#{@name}!"
            end
          end
        RUBY
      end

      it "extracts the class and methods" do
        chunks = chunker.chunk_file("user.rb", content)

        expect(chunks.length).to eq(3) # class + 2 methods

        # Check class chunk
        class_chunk = chunks.find { |c| c[:type] == "class" }
        expect(class_chunk).not_to be_nil
        expect(class_chunk[:name]).to eq("User")
        expect(class_chunk[:start_line]).to eq(2)
        expect(class_chunk[:comments]).to include("A simple user class")

        # Check method chunks
        init_method = chunks.find { |c| c[:name] == "initialize" }
        expect(init_method).not_to be_nil
        expect(init_method[:type]).to eq("method")
        expect(init_method[:context]).to eq("class User")
        expect(init_method[:metadata][:parameters]).to eq(["name"])

        greet_method = chunks.find { |c| c[:name] == "greet" }
        expect(greet_method).not_to be_nil
        expect(greet_method[:context]).to eq("class User")
      end

      it "generates unique IDs for each chunk" do
        chunks = chunker.chunk_file("user.rb", content)
        ids = chunks.map { |c| c[:id] }
        expect(ids.uniq.length).to eq(chunks.length)
      end
    end

    context "with a module" do
      let(:content) do
        <<~RUBY
          module Authentication
            def self.verify(token)
              token == "secret"
            end

            def login
              puts "Logging in"
            end
          end
        RUBY
      end

      it "extracts the module and methods" do
        chunks = chunker.chunk_file("auth.rb", content)

        module_chunk = chunks.find { |c| c[:type] == "module" }
        expect(module_chunk).not_to be_nil
        expect(module_chunk[:name]).to eq("Authentication")

        verify_method = chunks.find { |c| c[:name] == "verify" }
        expect(verify_method).not_to be_nil
        expect(verify_method[:metadata][:class_method]).to be true

        login_method = chunks.find { |c| c[:name] == "login" }
        expect(login_method).not_to be_nil
        expect(login_method[:metadata][:class_method]).to be false
      end
    end

    context "with nested classes" do
      let(:content) do
        <<~RUBY
          module Blog
            class Post
              class Comment
                def reply
                  puts "Replying"
                end
              end

              def publish
                puts "Publishing"
              end
            end
          end
        RUBY
      end

      it "preserves nested context" do
        chunks = chunker.chunk_file("blog.rb", content)

        reply_method = chunks.find { |c| c[:name] == "reply" }
        expect(reply_method).not_to be_nil
        expect(reply_method[:context]).to eq("module Blog > class Post > class Comment")

        publish_method = chunks.find { |c| c[:name] == "publish" }
        expect(publish_method).not_to be_nil
        expect(publish_method[:context]).to eq("module Blog > class Post")
      end
    end

    context "with constants" do
      let(:content) do
        <<~RUBY
          class Config
            VERSION = "1.0.0"
            DEFAULT_TIMEOUT = 30
          end
        RUBY
      end

      it "extracts constants" do
        chunks = chunker.chunk_file("config.rb", content)

        version_const = chunks.find { |c| c[:name] == "VERSION" }
        expect(version_const).not_to be_nil
        expect(version_const[:type]).to eq("constant")

        timeout_const = chunks.find { |c| c[:name] == "DEFAULT_TIMEOUT" }
        expect(timeout_const).not_to be_nil
      end
    end

    context "with method visibility" do
      let(:content) do
        <<~RUBY
          class SecureClass
            def public_method
              puts "Public"
            end

            private

            def private_method
              puts "Private"
            end

            protected

            def protected_method
              puts "Protected"
            end
          end
        RUBY
      end

      it "detects method visibility" do
        chunks = chunker.chunk_file("secure.rb", content)

        public_method = chunks.find { |c| c[:name] == "public_method" }
        expect(public_method[:metadata][:visibility]).to eq("public")

        private_method = chunks.find { |c| c[:name] == "private_method" }
        expect(private_method[:metadata][:visibility]).to eq("private")

        protected_method = chunks.find { |c| c[:name] == "protected_method" }
        expect(protected_method[:metadata][:visibility]).to eq("protected")
      end
    end

    context "with class inheritance" do
      let(:content) do
        <<~RUBY
          class AdminUser < User
            def admin?
              true
            end
          end
        RUBY
      end

      it "captures parent class" do
        chunks = chunker.chunk_file("admin.rb", content)

        class_chunk = chunks.find { |c| c[:type] == "class" }
        expect(class_chunk[:metadata][:parent_class]).to eq("User")
      end
    end

    context "with method parameters" do
      let(:content) do
        <<~RUBY
          class Example
            def method_with_args(a, b, c = 5, *args, key:, opt: "default", **kwargs, &block)
              # method body
            end
          end
        RUBY
      end

      it "extracts method parameters" do
        chunks = chunker.chunk_file("example.rb", content)

        method_chunk = chunks.find { |c| c[:name] == "method_with_args" }
        params = method_chunk[:metadata][:parameters]

        expect(params).to include("a")
        expect(params).to include("b")
        expect(params).to include(match(/c=/))
        expect(params).to include(match(/\*args/))
        expect(params).to include(match(/key:/))
        expect(params).to include(match(/opt:/))
        expect(params).to include(match(/\*\*kwargs/))
        expect(params).to include(match(/&block/))
      end
    end

    context "with empty file" do
      it "returns empty array for nil content" do
        chunks = chunker.chunk_file("empty.rb", nil)
        expect(chunks).to eq([])
      end

      it "returns empty array for empty string" do
        chunks = chunker.chunk_file("empty.rb", "")
        expect(chunks).to eq([])
      end

      it "returns empty array for whitespace only" do
        chunks = chunker.chunk_file("empty.rb", "   \n\n  \t  ")
        expect(chunks).to eq([])
      end
    end

    context "with file containing only comments" do
      let(:content) do
        <<~RUBY
          # This is a comment
          # Another comment
          # Yet another comment
        RUBY
      end

      it "creates a single file chunk" do
        chunks = chunker.chunk_file("comments.rb", content)
        expect(chunks.length).to eq(1)
        expect(chunks[0][:type]).to eq("file")
      end
    end

    context "with file containing only top-level code" do
      let(:content) do
        <<~RUBY
          puts "Hello"
          x = 5
          y = 10
          puts x + y
        RUBY
      end

      it "creates a single file chunk" do
        chunks = chunker.chunk_file("script.rb", content)
        expect(chunks.length).to eq(1)
        expect(chunks[0][:type]).to eq("file")
        expect(chunks[0][:metadata][:top_level]).to be true
      end
    end

    context "with syntax errors" do
      let(:content) do
        <<~RUBY
          class BrokenClass
            def broken_method
              puts "Missing end
          end
        RUBY
      end

      it "raises a syntax error" do
        expect do
          chunker.chunk_file("broken.rb", content)
        end.to raise_error(Parser::SyntaxError)
      end
    end

    context "with very large methods" do
      let(:content) do
        lines = ["class BigClass", "  def huge_method"]
        150.times do |i|
          lines << "    puts \"Line #{i}\""
        end
        lines += ["  end", "end"]
        lines.join("\n")
      end

      it "marks large chunks" do
        chunks = chunker.chunk_file("big.rb", content)

        method_chunk = chunks.find { |c| c[:name] == "huge_method" }
        expect(method_chunk[:metadata][:large_chunk]).to be true
        expect(method_chunk[:metadata][:lines_count]).to be > 100
      end
    end

    context "with comments before definitions" do
      let(:content) do
        <<~RUBY
          class Example
            # This method does something important
            # It takes a parameter
            # And returns a value
            def important_method(param)
              param * 2
            end
          end
        RUBY
      end

      it "extracts preceding comments" do
        chunks = chunker.chunk_file("example.rb", content)

        method_chunk = chunks.find { |c| c[:name] == "important_method" }
        expect(method_chunk[:comments]).to include("This method does something important")
        expect(method_chunk[:comments]).to include("It takes a parameter")
        expect(method_chunk[:comments]).to include("And returns a value")
      end
    end

    context "with real-world Rails-like code" do
      let(:content) do
        <<~RUBY
          # Controller for handling user authentication
          class UsersController < ApplicationController
            before_action :authenticate, only: [:edit, :update]

            # Display all users
            def index
              @users = User.all
              render :index
            end

            # Show a specific user
            def show
              @user = User.find(params[:id])
            end

            private

            def authenticate
              redirect_to login_path unless current_user
            end

            def user_params
              params.require(:user).permit(:name, :email)
            end
          end
        RUBY
      end

      it "correctly chunks a Rails controller" do
        chunks = chunker.chunk_file("users_controller.rb", content)

        # Should have: 1 class + 4 methods
        expect(chunks.length).to eq(5)

        class_chunk = chunks.find { |c| c[:type] == "class" }
        expect(class_chunk[:name]).to eq("UsersController")
        expect(class_chunk[:metadata][:parent_class]).to eq("ApplicationController")

        # Check public methods
        index_method = chunks.find { |c| c[:name] == "index" }
        expect(index_method[:metadata][:visibility]).to eq("public")

        # Check private methods
        authenticate_method = chunks.find { |c| c[:name] == "authenticate" }
        expect(authenticate_method[:metadata][:visibility]).to eq("private")

        user_params_method = chunks.find { |c| c[:name] == "user_params" }
        expect(user_params_method[:metadata][:visibility]).to eq("private")
      end
    end

    context "with singleton methods" do
      let(:content) do
        <<~RUBY
          class MyClass
            def self.class_method
              puts "Class method"
            end

            def instance_method
              puts "Instance method"
            end
          end
        RUBY
      end

      it "distinguishes class and instance methods" do
        chunks = chunker.chunk_file("methods.rb", content)

        class_method = chunks.find { |c| c[:name] == "class_method" }
        expect(class_method[:metadata][:class_method]).to be true

        instance_method = chunks.find { |c| c[:name] == "instance_method" }
        expect(instance_method[:metadata][:class_method]).to be false
      end
    end
  end

  # frozen_string_literal: true

  # ========================================================================
  # ADDITIONAL TESTS FOR SLIDING WINDOW CHUNKING
  # Add these test contexts to the end of your existing spec/chunker_spec.rb
  # (before the final "end" that closes the RSpec.describe block)
  # ========================================================================

  describe "sliding window chunking for large methods" do
    let(:config) { Ragify::Config.new({ "chunk_size_limit" => 150, "chunk_overlap" => 20 }) }
    let(:chunker) { described_class.new(config) }

    context "with large methods requiring splitting" do
      let(:content) do
        # Create a 200-line method
        lines = ["class BigClass", "  def huge_method"]
        200.times do |i|
          lines << "    puts \"Line #{i}\""
        end
        lines += ["  end", "end"]
        lines.join("\n")
      end

      it "splits large methods into multiple parts" do
        chunks = chunker.chunk_file("big.rb", content)

        method_parts = chunks.select { |c| c[:name] == "huge_method" }

        # With 150-line limit and 20-line overlap:
        # 200 lines total, stride = 130
        # Part 1: 0-150
        # Part 2: 130-200 (70 lines, overlaps with part 1)
        expect(method_parts.length).to eq(2)
      end

      it "marks chunks as partial with correct metadata" do
        chunks = chunker.chunk_file("big.rb", content)

        method_parts = chunks.select { |c| c[:name] == "huge_method" }

        method_parts.each do |part|
          expect(part[:metadata][:is_partial]).to be true
          expect(part[:metadata][:parent_chunk_id]).to be_a(String)
          expect(part[:metadata][:total_parts]).to eq(2)
          expect(part[:metadata][:overlap_lines]).to eq(20)
        end

        # Verify part numbers
        expect(method_parts[0][:metadata][:part_number]).to eq(1)
        expect(method_parts[1][:metadata][:part_number]).to eq(2)
      end

      it "creates overlapping content between parts" do
        chunks = chunker.chunk_file("big.rb", content)

        method_parts = chunks.select { |c| c[:name] == "huge_method" }.sort_by { |p| p[:metadata][:part_number] }

        part1_lines = method_parts[0][:code].lines
        part2_lines = method_parts[1][:code].lines

        # Last 20 lines of part 1 should match first 20 lines of part 2
        part1_last_20 = part1_lines[-20..-1]
        part2_first_20 = part2_lines[0..19]

        expect(part1_last_20).to eq(part2_first_20)
      end

      it "assigns unique IDs to each part" do
        chunks = chunker.chunk_file("big.rb", content)

        method_parts = chunks.select { |c| c[:name] == "huge_method" }
        ids = method_parts.map { |p| p[:id] }

        # All IDs should be unique
        expect(ids.uniq.length).to eq(ids.length)

        # IDs should follow pattern: parent_id_part1, parent_id_part2
        expect(ids[0]).to end_with("_part1")
        expect(ids[1]).to end_with("_part2")
      end

      it "preserves comments only in first part" do
        content_with_comments = <<~RUBY
          class MyClass
            # This is a very important method
            # It does a lot of things
            def huge_method
              #{"puts 'line'\n" * 200}
            end
          end
        RUBY

        chunks = chunker.chunk_file("test.rb", content_with_comments)
        method_parts = chunks.select { |c| c[:name] == "huge_method" }.sort_by { |p| p[:metadata][:part_number] }

        # First part should have comments
        expect(method_parts[0][:comments]).to include("This is a very important method")

        # Subsequent parts should not have comments
        method_parts[1..-1].each do |part|
          expect(part[:comments]).to eq("")
        end
      end

      it "maintains correct line numbers across parts" do
        chunks = chunker.chunk_file("big.rb", content)
        method_parts = chunks.select { |c| c[:name] == "huge_method" }.sort_by { |p| p[:metadata][:part_number] }

        # Part 1 should start at the method definition
        expect(method_parts[0][:start_line]).to eq(2)

        # Part 2 should start 130 lines later (150 - 20 overlap)
        expect(method_parts[1][:start_line]).to eq(132)

        # Parts should overlap by exactly 20 lines
        part1_end = method_parts[0][:end_line]
        part2_start = method_parts[1][:start_line]

        expect(part1_end - part2_start + 1).to eq(20)
      end
    end

    context "with very large methods (500+ lines)" do
      let(:content) do
        lines = ["class VeryBigClass", "  def massive_method"]
        500.times do |i|
          lines << "    puts \"Line #{i}\""
        end
        lines += ["  end", "end"]
        lines.join("\n")
      end

      it "splits into multiple parts correctly" do
        chunks = chunker.chunk_file("massive.rb", content)
        method_parts = chunks.select { |c| c[:name] == "massive_method" }

        # With 150-line limit and 20-line overlap, stride = 130
        # 500 lines: Part 1: 0-150, Part 2: 130-280, Part 3: 260-410, Part 4: 390-500
        expect(method_parts.length).to eq(4)
      end

      it "has consistent total_parts metadata" do
        chunks = chunker.chunk_file("massive.rb", content)
        method_parts = chunks.select { |c| c[:name] == "massive_method" }

        method_parts.each do |part|
          expect(part[:metadata][:total_parts]).to eq(4)
        end
      end
    end

    context "with methods just under the limit" do
      let(:content) do
        # Create a 140-line method (under 150 limit)
        lines = ["class SmallClass", "  def medium_method"]
        140.times do |i|
          lines << "    puts \"Line #{i}\""
        end
        lines += ["  end", "end"]
        lines.join("\n")
      end

      it "does not split methods under the limit" do
        chunks = chunker.chunk_file("small.rb", content)
        method_parts = chunks.select { |c| c[:name] == "medium_method" }

        # Should be exactly 1 chunk (not split)
        expect(method_parts.length).to eq(1)
        expect(method_parts[0][:metadata][:is_partial]).to be_nil
      end
    end

    context "with custom chunk size and overlap" do
      let(:small_config) { Ragify::Config.new({ "chunk_size_limit" => 50, "chunk_overlap" => 10 }) }
      let(:small_chunker) { described_class.new(small_config) }

      let(:content) do
        lines = ["class TestClass", "  def test_method"]
        100.times do |i|
          lines << "    puts \"Line #{i}\""
        end
        lines += ["  end", "end"]
        lines.join("\n")
      end

      it "respects custom chunk size limit" do
        chunks = small_chunker.chunk_file("test.rb", content)
        method_parts = chunks.select { |c| c[:name] == "test_method" }

        # With 50-line limit and 10-line overlap, stride = 40
        # 100 lines: Part 1: 0-50, Part 2: 40-90, Part 3: 80-100
        expect(method_parts.length).to eq(3)
      end

      it "respects custom overlap configuration" do
        chunks = small_chunker.chunk_file("test.rb", content)
        method_parts = chunks.select { |c| c[:name] == "test_method" }.sort_by { |p| p[:metadata][:part_number] }

        method_parts.each do |part|
          expect(part[:metadata][:overlap_lines]).to eq(10)
        end

        # Verify actual 10-line overlap
        part1_last_10 = method_parts[0][:code].lines[-10..-1]
        part2_first_10 = method_parts[1][:code].lines[0..9]
        expect(part1_last_10).to eq(part2_first_10)
      end
    end

    context "with multiple large methods in same file" do
      let(:content) do
        parts = ["class MultiMethodClass"]

        # First large method (200 lines)
        parts << "  def first_method"
        200.times { |i| parts << "    puts 'first #{i}'" }
        parts << "  end"

        # Second large method (300 lines)
        parts << "  def second_method"
        300.times { |i| parts << "    puts 'second #{i}'" }
        parts << "  end"

        parts << "end"
        parts.join("\n")
      end

      it "splits both methods independently" do
        chunks = chunker.chunk_file("multi.rb", content)

        first_parts = chunks.select { |c| c[:name] == "first_method" }
        second_parts = chunks.select { |c| c[:name] == "second_method" }

        # First method: 200 lines -> 2 parts
        expect(first_parts.length).to eq(2)

        # Second method: 300 lines -> 3 parts
        expect(second_parts.length).to eq(3)
      end

      it "maintains unique parent_chunk_ids for different methods" do
        chunks = chunker.chunk_file("multi.rb", content)

        first_parts = chunks.select { |c| c[:name] == "first_method" }
        second_parts = chunks.select { |c| c[:name] == "second_method" }

        first_parent_id = first_parts[0][:metadata][:parent_chunk_id]
        second_parent_id = second_parts[0][:metadata][:parent_chunk_id]

        # Parent IDs should be different
        expect(first_parent_id).not_to eq(second_parent_id)

        # All parts of same method should share parent ID
        expect(first_parts.map { |p| p[:metadata][:parent_chunk_id] }.uniq).to eq([first_parent_id])
        expect(second_parts.map { |p| p[:metadata][:parent_chunk_id] }.uniq).to eq([second_parent_id])
      end
    end

    context "with nested classes containing large methods" do
      let(:content) do
        <<~RUBY
          module Outer
            class Inner
              def long_method
                #{"puts 'line'\n" * 200}
              end
            end
          end
        RUBY
      end

      it "preserves context in all split chunks" do
        chunks = chunker.chunk_file("nested.rb", content)
        method_parts = chunks.select { |c| c[:name] == "long_method" }

        method_parts.each do |part|
          expect(part[:context]).to eq("module Outer > class Inner")
        end
      end
    end

    context "with large class methods" do
      let(:content) do
        lines = ["class MyClass"]
        lines << "  def self.large_class_method"
        200.times { |i| lines << "    puts 'line #{i}'" }
        lines << "  end"
        lines << "end"
        lines.join("\n")
      end

      it "splits class methods correctly" do
        chunks = chunker.chunk_file("class_method.rb", content)
        method_parts = chunks.select { |c| c[:name] == "large_class_method" }

        expect(method_parts.length).to eq(2)

        method_parts.each do |part|
          expect(part[:metadata][:class_method]).to be true
          expect(part[:metadata][:is_partial]).to be true
        end
      end
    end

    context "realistic integration scenario" do
      let(:realistic_content) do
        <<~RUBY
          module UserManagement
            class UserService
              def initialize(db)
                @db = db
              end

              # This method handles the entire user registration process
              def register_user(params)
                # Validation phase (50 lines)
                #{"validate_param(params)\n    " * 50}

                # Creation phase (50 lines)
                #{"create_user_record(params)\n    " * 50}

                # Notification phase (50 lines)
                #{"send_notifications(params)\n    " * 50}

                # Return phase (50 lines)
                #{"format_response\n    " * 50}
              end

              private

              def validate_param(param)
                # Short validation logic
                param.present?
              end
            end
          end
        RUBY
      end

      it "handles realistic Ruby code with large and small methods" do
        chunks = chunker.chunk_file("user_service.rb", realistic_content)

        # Should have module, class, and methods
        expect(chunks.any? { |c| c[:type] == "module" }).to be true
        expect(chunks.any? { |c| c[:type] == "class" }).to be true

        # The large register_user method should be split
        register_parts = chunks.select { |c| c[:name] == "register_user" }
        expect(register_parts.length).to be > 1
        expect(register_parts.all? { |p| p[:metadata][:is_partial] }).to be true

        # Small methods should not be split
        validate_parts = chunks.select { |c| c[:name] == "validate_param" }
        expect(validate_parts.length).to eq(1)
        expect(validate_parts[0][:metadata][:is_partial]).to be_nil

        # Initialize should not be split
        init_parts = chunks.select { |c| c[:name] == "initialize" }
        expect(init_parts.length).to eq(1)
      end
    end
  end
end
