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
end
