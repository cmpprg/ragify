# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Ragify Integration", :integration do
  let(:temp_dir) { Dir.mktmpdir("ragify_integration_test") }
  let(:original_dir) { Dir.pwd }

  before do
    Dir.chdir(temp_dir)
  end

  after do
    Dir.chdir(original_dir)
    FileUtils.rm_rf(temp_dir)
  end

  describe "full indexing and search workflow" do
    before do
      # Create a sample Ruby project structure
      FileUtils.mkdir_p("app/models")
      FileUtils.mkdir_p("app/controllers")
      FileUtils.mkdir_p("lib")

      # Create sample Ruby files
      File.write("app/models/user.rb", <<~RUBY)
        # User model for authentication
        class User < ApplicationRecord
          # Role constants
          ADMIN_ROLE = "admin"
          MEMBER_ROLE = "member"

          has_secure_password
          has_many :posts

          # Authenticate user with password
          # @param password [String] The password to verify
          # @return [Boolean] Whether authentication succeeded
          def authenticate(password)
            return false if locked?
            BCrypt::Password.new(password_digest) == password
          end

          # Check if user has admin privileges
          def admin?
            role == ADMIN_ROLE
          end

          # Find user by email (case-insensitive)
          def self.find_by_email(email)
            where(email: email.downcase.strip).first
          end

          private

          def locked?
            locked_at.present?
          end
        end
      RUBY

      File.write("app/models/post.rb", <<~RUBY)
        # Blog post model
        class Post < ApplicationRecord
          belongs_to :user
          has_many :comments

          validates :title, presence: true
          validates :body, presence: true

          # Publish the post
          def publish!
            update!(published: true, published_at: Time.current)
            notify_subscribers
          end

          # Get recent published posts
          def self.recent(limit = 10)
            where(published: true)
              .order(published_at: :desc)
              .limit(limit)
          end

          private

          def notify_subscribers
            # Implementation here
          end
        end
      RUBY

      File.write("app/controllers/users_controller.rb", <<~RUBY)
        # Controller for user management
        class UsersController < ApplicationController
          before_action :authenticate_user
          before_action :find_user, only: [:show, :edit, :update]

          def index
            @users = User.all
          end

          def show
            # @user set by before_action
          end

          def create
            @user = User.new(user_params)
            if @user.save
              redirect_to @user
            else
              render :new
            end
          end

          private

          def find_user
            @user = User.find(params[:id])
          end

          def user_params
            params.require(:user).permit(:name, :email, :password)
          end
        end
      RUBY

      File.write("lib/authentication.rb", <<~RUBY)
        # Authentication helper module
        module Authentication
          # Hash a password securely
          def self.hash_password(password)
            BCrypt::Password.create(password)
          end

          # Verify password against hash
          def self.verify_password(password, hash)
            BCrypt::Password.new(hash) == password
          end

          # Generate a secure random token
          def self.generate_token
            SecureRandom.urlsafe_base64(32)
          end
        end
      RUBY

      # Initialize Ragify
      FileUtils.mkdir_p(".ragify")
      Ragify::Config.create_default
    end

    it "indexes Ruby files and creates chunks" do
      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)
      store = Ragify::Store.new

      store.open

      # Discover files
      files = indexer.discover_files
      expect(files.length).to eq(4) # user.rb, post.rb, users_controller.rb, authentication.rb

      # Chunk all files
      all_chunks = []
      files.each do |file_path|
        content = indexer.read_file(file_path)
        chunks = chunker.chunk_file(file_path, content)
        all_chunks.concat(chunks)
      end

      # Verify we got meaningful chunks
      expect(all_chunks.length).to be > 10

      # Check that we have various chunk types
      types = all_chunks.map { |c| c[:type] }.uniq
      expect(types).to include("class", "method", "module", "constant")

      # Store chunks (without embeddings for this test)
      all_chunks.each { |chunk| store.insert_chunk(chunk, nil) }

      # Verify storage
      stats = store.stats
      expect(stats[:total_chunks]).to eq(all_chunks.length)
      expect(stats[:total_files]).to eq(4)

      store.close
    end

    it "can search indexed code with text search" do
      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)
      store = Ragify::Store.new
      embedder = nil # No Ollama needed for text search
      searcher = Ragify::Searcher.new(store, embedder, config)

      store.open

      # Index all files
      files = indexer.discover_files
      files.each do |file_path|
        content = indexer.read_file(file_path)
        chunks = chunker.chunk_file(file_path, content)
        chunks.each { |chunk| store.insert_chunk(chunk, nil) }
      end

      # Search for authentication-related code
      results = searcher.search("authenticate", mode: :text, limit: 5)

      expect(results).not_to be_empty
      expect(results.first[:chunk][:name]).to eq("authenticate")

      # Search for user-related code
      results = searcher.search("User", mode: :text, limit: 5)
      expect(results).not_to be_empty

      # Filter by type
      results = searcher.search("user", mode: :text, type: "class", limit: 5)
      results.each do |result|
        expect(result[:chunk][:type]).to eq("class")
      end

      # Filter by path
      results = searcher.search("find", mode: :text, path_filter: "controller", limit: 5)
      results.each do |result|
        expect(result[:chunk][:file_path]).to include("controller")
      end

      store.close
    end

    it "preserves context in chunks" do
      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)

      files = indexer.discover_files
      user_file = files.find { |f| f.end_with?("user.rb") }
      content = indexer.read_file(user_file)
      chunks = chunker.chunk_file(user_file, content)

      # Find the authenticate method
      auth_chunk = chunks.find { |c| c[:name] == "authenticate" }
      expect(auth_chunk).not_to be_nil
      expect(auth_chunk[:context]).to eq("class User")
      expect(auth_chunk[:metadata][:visibility]).to eq("public")

      # Find the locked? method
      locked_chunk = chunks.find { |c| c[:name] == "locked?" }
      expect(locked_chunk).not_to be_nil
      expect(locked_chunk[:metadata][:visibility]).to eq("private")

      # Find constants
      admin_const = chunks.find { |c| c[:name] == "ADMIN_ROLE" }
      expect(admin_const).not_to be_nil
      expect(admin_const[:type]).to eq("constant")
      expect(admin_const[:context]).to eq("class User")
    end

    it "formats search results correctly" do
      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)
      store = Ragify::Store.new
      searcher = Ragify::Searcher.new(store, nil, config)

      store.open

      # Index all files
      files = indexer.discover_files
      files.each do |file_path|
        content = indexer.read_file(file_path)
        chunks = chunker.chunk_file(file_path, content)
        chunks.each { |chunk| store.insert_chunk(chunk, nil) }
      end

      results = searcher.search("authenticate", mode: :text, limit: 2)

      # Test plain format
      plain_output = searcher.format_results(results, format: :plain)
      expect(plain_output).to include("authenticate")
      expect(plain_output).to include("Score:")
      expect(plain_output).to include("File:")

      # Test JSON format
      json_output = searcher.format_results(results, format: :json)
      parsed = JSON.parse(json_output)
      expect(parsed).to be_an(Array)
      expect(parsed.first).to have_key("name")
      expect(parsed.first).to have_key("score")
      expect(parsed.first).to have_key("file_path")

      store.close
    end

    it "handles reindexing correctly" do
      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)
      store = Ragify::Store.new

      store.open

      # Initial index
      files = indexer.discover_files
      files.each do |file_path|
        content = indexer.read_file(file_path)
        chunks = chunker.chunk_file(file_path, content)
        chunks.each { |chunk| store.insert_chunk(chunk, nil) }
      end

      initial_count = store.stats[:total_chunks]
      expect(initial_count).to be > 0

      # Clear and reindex
      store.clear_all
      expect(store.stats[:total_chunks]).to eq(0)

      # Reindex
      files.each do |file_path|
        content = indexer.read_file(file_path)
        chunks = chunker.chunk_file(file_path, content)
        chunks.each { |chunk| store.insert_chunk(chunk, nil) }
      end

      expect(store.stats[:total_chunks]).to eq(initial_count)

      store.close
    end
  end

  describe "with Ollama available", :ollama_required do
    before do
      # Create a minimal project
      FileUtils.mkdir_p("lib")

      File.write("lib/sample.rb", <<~RUBY)
        # Sample class for testing
        class Sample
          def process_data(input)
            validate(input)
            transform(input)
          end

          def validate(data)
            raise ArgumentError if data.nil?
          end

          def transform(data)
            data.to_s.upcase
          end
        end
      RUBY

      FileUtils.mkdir_p(".ragify")
      Ragify::Config.create_default
    end

    it "performs semantic search with embeddings" do
      config = Ragify::Config.load
      embedder = Ragify::Embedder.new(config)

      skip "Ollama not available" unless embedder.ollama_available?
      skip "Model not available" unless embedder.model_available?

      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)
      store = Ragify::Store.new

      store.open

      # Index with embeddings
      files = indexer.discover_files
      files.each do |file_path|
        content = indexer.read_file(file_path)
        chunks = chunker.chunk_file(file_path, content)
        chunks.each do |chunk|
          text = embedder.prepare_chunk_text(chunk)
          embedding = embedder.embed(text)
          store.insert_chunk(chunk, embedding)
        end
      end

      # Verify embeddings were stored
      expect(store.stats[:total_vectors]).to eq(store.stats[:total_chunks])

      # Test semantic search
      searcher = Ragify::Searcher.new(store, embedder, config)
      results = searcher.search("data validation", mode: :semantic, limit: 3)

      expect(results).not_to be_empty
      # Validate method should be highly relevant
      names = results.map { |r| r[:chunk][:name] }
      expect(names).to include("validate")

      store.close
    end

    it "performs hybrid search combining semantic and text" do
      config = Ragify::Config.load
      embedder = Ragify::Embedder.new(config)

      skip "Ollama not available" unless embedder.ollama_available?
      skip "Model not available" unless embedder.model_available?

      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)
      store = Ragify::Store.new

      store.open

      # Index with embeddings
      files = indexer.discover_files
      files.each do |file_path|
        content = indexer.read_file(file_path)
        chunks = chunker.chunk_file(file_path, content)
        chunks.each do |chunk|
          text = embedder.prepare_chunk_text(chunk)
          embedding = embedder.embed(text)
          store.insert_chunk(chunk, embedding)
        end
      end

      searcher = Ragify::Searcher.new(store, embedder, config)

      # Test hybrid search
      results = searcher.search("transform data", mode: :hybrid, limit: 3)

      expect(results).not_to be_empty
      # Should include vector_score and text_score
      expect(results.first).to have_key(:vector_score)
      expect(results.first).to have_key(:text_score)

      store.close
    end
  end
end
