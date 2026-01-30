# frozen_string_literal: true

require "thor"
require "pastel"
require "tty-progressbar"

module Ragify
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "version", "Show Ragify version"
    def version
      puts "Ragify version #{Ragify::VERSION}"
    end

    desc "init", "Initialize Ragify in the current directory"
    method_option :force, type: :boolean, aliases: "-f", desc: "Force reinitialize"
    def init
      pastel = Pastel.new

      puts pastel.cyan("Initializing Ragify...")

      # Check if already initialized
      if File.exist?(".ragify") && !options[:force]
        puts pastel.yellow("Ragify already initialized. Use --force to reinitialize.")
        return
      end

      # Create .ragify directory
      Dir.mkdir(".ragify") unless Dir.exist?(".ragify")
      puts pastel.green("✓ Created .ragify directory")

      # Create config file
      Ragify::Config.create_default
      puts pastel.green("✓ Created default configuration")

      # Create .ragifyignore file
      create_ragifyignore
      puts pastel.green("✓ Created .ragifyignore file")

      # Check Ollama installation
      puts "\n" + pastel.cyan("Checking dependencies...")
      check_ollama

      puts "\n" + pastel.green("✓ Ragify initialized successfully!")
      puts "\nNext steps:"
      puts "  1. Run: ragify index"
      puts "  2. Run: ragify search \"your query\""
    end

    desc "index [PATH]", "Index Ruby files in the project"
    method_option :path, type: :string, aliases: "-p", desc: "Path to index (default: current directory)"
    method_option :verbose, type: :boolean, aliases: "-v", desc: "Verbose output"
    method_option :strict, type: :boolean, aliases: "-s", desc: "Fail on first error (for CI/CD)"
    method_option :yes, type: :boolean, aliases: "-y", desc: "Continue without prompting on errors"
    method_option :no_embeddings, type: :boolean, desc: "Skip embedding generation"
    def index(path = nil)
      pastel = Pastel.new
      path ||= options[:path] || Dir.pwd

      puts pastel.cyan("Indexing project: #{path}")

      # Load configuration
      config = Ragify::Config.load

      # Initialize components
      indexer = Ragify::Indexer.new(path, config, verbose: options[:verbose])
      chunker = Ragify::Chunker.new(config)
      store = Ragify::Store.new

      # Open the store
      store.open
      puts pastel.dim("Database: #{store.db_path}")

      # Discover files
      puts "\n" + pastel.cyan("Discovering Ruby files...")
      files = indexer.discover_files

      if files.empty?
        puts pastel.yellow("No Ruby files found to index.")
        store.close
        return
      end

      puts pastel.green("Found #{files.length} Ruby files")

      if options[:verbose]
        puts "\nFiles to index:"
        files.each { |file| puts "  - #{file}" }
      end

      # Parse and chunk files
      puts "\n" + pastel.cyan("Parsing and chunking files...")

      all_chunks = []
      failures = []
      stats = {
        total_files: files.length,
        successful: 0,
        failed: 0,
        classes: 0,
        modules: 0,
        methods: 0,
        constants: 0
      }

      # Create progress bar
      bar = TTY::ProgressBar.new(
        "[:bar] :current/:total :percent :eta",
        total: files.length,
        width: 40
      )

      files.each do |file_path|
        begin
          content = indexer.read_file(file_path)

          if content
            chunks = chunker.chunk_file(file_path, content)
            all_chunks.concat(chunks)

            # Update statistics
            stats[:successful] += 1
            chunks.each do |chunk|
              case chunk[:type]
              when "class" then stats[:classes] += 1
              when "module" then stats[:modules] += 1
              when "method" then stats[:methods] += 1
              when "constant" then stats[:constants] += 1
              end
            end

            if options[:verbose]
              puts "\n  #{file_path}: #{chunks.length} chunks"
              chunks.each do |chunk|
                context_str = chunk[:context].empty? ? "" : " (#{chunk[:context]})"
                puts "    - #{chunk[:type]}: #{chunk[:name]}#{context_str}"
              end
            end
          else
            stats[:failed] += 1
            failures << {
              file: file_path,
              error: "Could not read file"
            }
          end
        rescue Parser::SyntaxError => e
          stats[:failed] += 1
          failures << {
            file: file_path,
            error: "Syntax error: #{e.diagnostic.message}",
            line: e.diagnostic.location.line
          }
          puts pastel.red("\n✗ #{file_path}:#{e.diagnostic.location.line}") if options[:verbose]

          # Strict mode: fail immediately
          if options[:strict]
            puts "\n" + pastel.red("Error in #{file_path}:#{e.diagnostic.location.line}")
            puts pastel.red("  #{e.diagnostic.message}")
            puts "\nExiting due to --strict flag"
            store.close
            exit 1
          end
        rescue StandardError => e
          stats[:failed] += 1
          failures << {
            file: file_path,
            error: "Parse error: #{e.message}"
          }
          puts pastel.red("\n✗ #{file_path}: #{e.message}") if options[:verbose]

          # Strict mode: fail immediately
          if options[:strict]
            puts "\n" + pastel.red("Error in #{file_path}")
            puts pastel.red("  #{e.message}")
            puts "\nExiting due to --strict flag"
            store.close
            exit 1
          end
        end

        bar.advance
      end

      # Display results
      puts "\n"
      puts pastel.green("✓ Successfully processed: #{stats[:successful]} files → #{all_chunks.length} chunks")

      # Show failures if any
      if failures.any?
        puts pastel.yellow("⚠️  Skipped #{failures.length} file(s) with errors:\n")

        failures.each do |failure|
          puts "  #{failure[:file]}" + (failure[:line] ? ":#{failure[:line]}" : "")
          puts pastel.dim("    #{failure[:error]}")
        end

        puts "\n" + pastel.dim("─" * 60)
        puts pastel.yellow("These files were NOT indexed and won't be searchable.")

        # Check if too many failures
        failure_rate = failures.length.to_f / files.length
        if failure_rate > 0.2
          puts "\n" + pastel.red("✗ Failed to parse #{failures.length}/#{files.length} files (>20%)")
          puts pastel.red("This likely indicates a configuration problem.")
          puts "Check your Ruby version and Parser gem compatibility."
          store.close
          exit 1
        end

        # Prompt to continue (unless --yes flag)
        unless options[:yes]
          require "tty-prompt"
          prompt = TTY::Prompt.new

          puts
          continue = prompt.yes?(
            "Continue with embedding #{all_chunks.length} chunks?",
            default: true
          )

          unless continue
            puts pastel.yellow("\nIndexing cancelled.")
            puts "Fix the errors above and run: ragify index"
            store.close
            exit 0
          end

          puts
        end
      end

      puts "\nChunks extracted:"
      puts "  Classes: #{stats[:classes]}"
      puts "  Modules: #{stats[:modules]}"
      puts "  Methods: #{stats[:methods]}"
      puts "  Constants: #{stats[:constants]}"
      puts "\n  Total chunks: #{all_chunks.length}"

      # Clear existing data for indexed files
      puts "\n" + pastel.cyan("Clearing old data for indexed files...")
      files.each { |file| store.delete_file(file) }

      # Day 3 & 4: Generate embeddings and store
      if all_chunks.any? && !options[:no_embeddings]
        puts "\n" + pastel.cyan("Generating embeddings...")

        begin
          # Initialize embedder
          embedder = Ragify::Embedder.new(config)

          # Check Ollama availability
          if embedder.ollama_available?
            # Check model availability
            if embedder.model_available?
              # Prepare texts for embedding
              puts pastel.dim("Preparing #{all_chunks.length} chunks for embedding...")
              prepared_texts = all_chunks.map { |chunk| embedder.prepare_chunk_text(chunk) }

              # Generate embeddings with progress bar
              puts
              embeddings = embedder.embed_batch(
                prepared_texts,
                batch_size: 5,
                show_progress: true
              )

              puts pastel.green("\n✓ Generated #{embeddings.length} embeddings")

              # Show cache stats
              cache_stats = embedder.cache_stats
              puts "  Cache: #{cache_stats[:size]} embeddings (~#{cache_stats[:memory_kb]} KB)"
              puts "  Embedding dimensions: 768 (nomic-embed-text)"

              # Day 4: Store chunks with embeddings
              puts "\n" + pastel.cyan("Storing chunks and embeddings...")

              chunks_with_embeddings = all_chunks.zip(embeddings)
              stored_count = store.insert_batch(chunks_with_embeddings)

              puts pastel.green("✓ Stored #{stored_count} chunks with embeddings")
            else
              puts pastel.yellow("\n⚠️  Model '#{config.model}' not found")
              puts "  Pull model: ollama pull #{config.model}"
              puts "\n" + pastel.dim("Storing chunks without embeddings...")
              store_chunks_without_embeddings(store, all_chunks)
            end
          else
            puts pastel.yellow("\n⚠️  Ollama not running - skipping embeddings")
            puts "  Start Ollama: ollama serve"
            puts "  Then run: ragify index again"
            puts "\n" + pastel.dim("Storing chunks without embeddings...")
            store_chunks_without_embeddings(store, all_chunks)
          end
        rescue Ragify::OllamaConnectionError => e
          puts pastel.yellow("\n⚠️  #{e.message}")
          puts "  Storing chunks without embeddings..."
          store_chunks_without_embeddings(store, all_chunks)
        rescue Ragify::OllamaTimeoutError => e
          puts pastel.red("\n✗ Timeout: #{e.message}")
          puts "  Ollama may be overloaded. Try reducing batch size."
          puts "  Storing chunks without embeddings..."
          store_chunks_without_embeddings(store, all_chunks)
        rescue Ragify::OllamaError => e
          puts pastel.red("\n✗ Embedding error: #{e.message}")
          puts "  Storing chunks without embeddings..."
          store_chunks_without_embeddings(store, all_chunks)
        end
      elsif all_chunks.any?
        # --no-embeddings flag
        puts "\n" + pastel.cyan("Storing chunks (embeddings skipped)...")
        store_chunks_without_embeddings(store, all_chunks)
      end

      # Show final stats
      puts "\n" + pastel.cyan("Database Statistics:")
      db_stats = store.stats
      puts "  Total chunks: #{db_stats[:total_chunks]}"
      puts "  Total embeddings: #{db_stats[:total_vectors]}"
      puts "  Total files: #{db_stats[:total_files]}"
      puts "  Database size: #{db_stats[:database_size_mb]} MB"

      store.close

      puts "\n" + pastel.green("✓ Indexing complete!")
      puts pastel.dim("Run: ragify search \"your query\"")
    rescue Ragify::Error => e
      puts pastel.red("Error: #{e.message}")
      exit 1
    end

    desc "search QUERY", "Search for code using semantic search"
    method_option :limit, type: :numeric, aliases: "-l", default: 5, desc: "Number of results"
    method_option :type, type: :string, aliases: "-t", desc: "Filter by type (method, class, module, constant)"
    method_option :path, type: :string, aliases: "-p", desc: "Filter by file path pattern"
    method_option :min_score, type: :numeric, aliases: "-m", desc: "Minimum similarity score (0.0-1.0)"
    method_option :format, type: :string, aliases: "-f", default: "colorized",
                           desc: "Output format (colorized, plain, json)"
    method_option :semantic, type: :boolean, desc: "Use semantic search only (requires Ollama)"
    method_option :text, type: :boolean, desc: "Use text search only (no Ollama required)"
    def search(query)
      pastel = Pastel.new

      # Validate options
      if options[:semantic] && options[:text]
        puts pastel.red("Error: Cannot use both --semantic and --text flags")
        exit 1
      end

      # Validate type filter
      valid_types = %w[method class module constant file]
      if options[:type] && !valid_types.include?(options[:type])
        puts pastel.red("Error: Invalid type '#{options[:type]}'. Valid types: #{valid_types.join(", ")}")
        exit 1
      end

      # Validate min_score
      if options[:min_score] && (options[:min_score] < 0.0 || options[:min_score] > 1.0)
        puts pastel.red("Error: --min-score must be between 0.0 and 1.0")
        exit 1
      end

      # Check if ragify is initialized
      unless File.exist?(".ragify")
        puts pastel.yellow("Ragify not initialized. Run: ragify init")
        exit 1
      end

      # Load configuration
      config = Ragify::Config.load

      # Open store
      store = Ragify::Store.new
      store.open

      # Check if there's any data
      stats = store.stats
      if stats[:total_chunks].zero?
        puts pastel.yellow("No indexed data found. Run: ragify index")
        store.close
        exit 1
      end

      # Determine search mode
      mode = :hybrid
      mode = :semantic if options[:semantic]
      mode = :text if options[:text]

      # Initialize embedder (may be nil if not needed for text-only search)
      embedder = nil
      embedder = Ragify::Embedder.new(config) unless mode == :text

      # Initialize searcher
      searcher = Ragify::Searcher.new(store, embedder, config)

      # Check if semantic search is available for non-text modes
      if mode != :text && !searcher.semantic_available?
        if mode == :semantic
          puts pastel.red("Error: Semantic search unavailable. Ollama not running or model not found.")
          puts "  Start Ollama: ollama serve"
          puts "  Pull model: ollama pull #{config.model}"
          store.close
          exit 1
        else
          # Hybrid mode falls back to text with warning
          puts pastel.yellow("⚠️  Ollama not available. Falling back to text search.")
          puts pastel.dim("  For better results, start Ollama: ollama serve")
          puts
          mode = :text
        end
      end

      # Show search info
      mode_label = { hybrid: "hybrid (semantic + text)", semantic: "semantic", text: "text" }[mode]
      puts pastel.cyan("Searching: \"#{query}\"")
      puts pastel.dim("Mode: #{mode_label} | Limit: #{options[:limit]}")

      filters = []
      filters << "type=#{options[:type]}" if options[:type]
      filters << "path=#{options[:path]}" if options[:path]
      filters << "min_score=#{options[:min_score]}" if options[:min_score]
      puts pastel.dim("Filters: #{filters.join(", ")}") if filters.any?
      puts

      begin
        # Perform search
        results = searcher.search(
          query,
          limit: options[:limit],
          type: options[:type],
          path_filter: options[:path],
          min_score: options[:min_score],
          mode: mode
        )

        if results.empty?
          puts pastel.yellow("No results found.")
          puts
          puts "Try:"
          puts "  - Using different keywords"
          puts "  - Removing filters"
          puts "  - Lowering --min-score" if options[:min_score]
          store.close
          return
        end

        # Format and display results
        format_sym = options[:format].to_sym
        output = searcher.format_results(results, format: format_sym)
        puts output

        # Summary
        if format_sym != :json
          puts pastel.green("Found #{results.length} result(s)")
          puts pastel.dim("Database: #{stats[:total_chunks]} chunks from #{stats[:total_files]} files")
        end
      rescue Ragify::SearchError => e
        puts pastel.red("Search error: #{e.message}")
        store.close
        exit 1
      rescue Ragify::OllamaError => e
        puts pastel.red("Ollama error: #{e.message}")
        puts "  Try: ragify search \"#{query}\" --text"
        store.close
        exit 1
      ensure
        store.close
      end
    end

    desc "status", "Show Ragify status and statistics"
    def status
      pastel = Pastel.new

      unless File.exist?(".ragify")
        puts pastel.yellow("Ragify not initialized. Run: ragify init")
        return
      end

      puts pastel.cyan("Ragify Status")
      puts pastel.dim("─" * 40)

      # Open store and get stats
      store = Ragify::Store.new
      store.open

      stats = store.stats

      puts "\n" + pastel.bold("Database:")
      puts "  Path: #{store.db_path}"
      puts "  Size: #{stats[:database_size_mb]} MB"
      puts "  Schema version: #{stats[:schema_version]}"

      puts "\n" + pastel.bold("Index Statistics:")
      puts "  Total files indexed: #{stats[:total_files]}"
      puts "  Total chunks: #{stats[:total_chunks]}"
      puts "  Total embeddings: #{stats[:total_vectors]}"

      if stats[:chunks_by_type].any?
        puts "\n  Chunks by type:"
        stats[:chunks_by_type].each do |type, count|
          puts "    #{type}: #{count}"
        end
      end

      puts "\n  Last indexed: #{stats[:last_indexed_at]}" if stats[:last_indexed_at]

      # Check Ollama status
      puts "\n" + pastel.bold("Dependencies:")
      check_ollama_status(pastel)

      store.close
    end

    desc "reindex", "Rebuild the index from scratch"
    method_option :force, type: :boolean, aliases: "-f", desc: "Skip confirmation"
    def reindex
      pastel = Pastel.new

      unless File.exist?(".ragify")
        puts pastel.yellow("Ragify not initialized. Run: ragify init")
        return
      end

      puts pastel.yellow("This will clear and rebuild the entire index.")

      unless options[:force]
        require "tty-prompt"
        prompt = TTY::Prompt.new

        continue = prompt.yes?("Continue?", default: false)
        return unless continue
      end

      # Clear the database
      store = Ragify::Store.new
      store.open
      store.clear_all
      puts pastel.green("✓ Cleared existing index")
      store.close

      # Run index command
      invoke :index
    end

    desc "clear", "Clear all indexed data"
    method_option :force, type: :boolean, aliases: "-f", desc: "Skip confirmation"
    def clear
      pastel = Pastel.new

      unless File.exist?(".ragify")
        puts pastel.yellow("Ragify not initialized. Run: ragify init")
        return
      end

      puts pastel.yellow("This will delete all indexed data.")

      unless options[:force]
        require "tty-prompt"
        prompt = TTY::Prompt.new

        continue = prompt.yes?("Continue?", default: false)
        return unless continue
      end

      store = Ragify::Store.new
      store.open
      store.clear_all
      store.close

      puts pastel.green("✓ Cleared all indexed data")
    end

    private

    def store_chunks_without_embeddings(store, chunks)
      bar = TTY::ProgressBar.new(
        "Storing [:bar] :current/:total",
        total: chunks.length,
        width: 40
      )

      chunks.each do |chunk|
        store.insert_chunk(chunk, nil)
        bar.advance
      end

      puts Pastel.new.green("\n✓ Stored #{chunks.length} chunks (without embeddings)")
    end

    def create_ragifyignore
      ignore_content = <<~IGNORE
        # Ragify ignore patterns
        # Similar to .gitignore syntax

        # Test files
        spec/**/*
        test/**/*

        # Generated files
        db/schema.rb

        # Dependencies
        vendor/**/*
        node_modules/**/*

        # Build artifacts
        pkg/**/*
        tmp/**/*

        # Documentation
        doc/**/*

        # Add your own patterns below:
      IGNORE

      File.write(".ragifyignore", ignore_content)
    end

    def check_ollama
      pastel = Pastel.new

      begin
        # Try to connect to Ollama
        require "faraday"
        conn = Faraday.new(url: "http://localhost:11434") do |f|
          f.response :json
        end
        response = conn.get("/api/tags")

        if response.status == 200
          puts pastel.green("✓ Ollama is running")

          # Check for nomic-embed-text model
          models = response.body["models"] || []
          has_nomic = models.any? { |m| m["name"].include?("nomic-embed-text") }

          if has_nomic
            puts pastel.green("✓ nomic-embed-text model is available")
          else
            puts pastel.yellow("! nomic-embed-text model not found")
            puts "  Run: ollama pull nomic-embed-text"
          end
        end
      rescue Faraday::ConnectionFailed
        puts pastel.yellow("! Ollama not running")
        puts "  Install from: https://ollama.com"
        puts "  Then run: ollama serve"
      rescue StandardError => e
        puts pastel.yellow("! Could not check Ollama: #{e.message}")
      end
    end

    def check_ollama_status(pastel)
      require "faraday"
      conn = Faraday.new(url: "http://localhost:11434") do |f|
        f.response :json
      end
      response = conn.get("/api/tags")

      if response.status == 200
        puts pastel.green("  ✓ Ollama: running")

        models = response.body["models"] || []
        has_nomic = models.any? { |m| m["name"].include?("nomic-embed-text") }

        if has_nomic
          puts pastel.green("  ✓ Model: nomic-embed-text available")
        else
          puts pastel.yellow("  ! Model: nomic-embed-text not found")
        end
      end
    rescue Faraday::ConnectionFailed
      puts pastel.yellow("  ! Ollama: not running")
    rescue StandardError => e
      puts pastel.yellow("  ! Ollama: error (#{e.message})")
    end
  end
end
