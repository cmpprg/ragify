# frozen_string_literal: true

require "thor"
require "pastel"
require "tty-progressbar"

module Ragify
  class CLI < Thor
    # Class-level quiet flag for use in class methods
    class << self
      attr_accessor :quiet_mode
    end

    def self.exit_on_failure?
      true
    end

    desc "version", "Show Ragify version"
    def version
      puts "Ragify version #{Ragify::VERSION}"
    end

    desc "init", "Initialize Ragify in the current directory"
    method_option :force, type: :boolean, aliases: "-f", desc: "Force reinitialize"
    method_option :quiet, type: :boolean, aliases: "-q", desc: "Suppress non-essential output"
    def init
      pastel = Pastel.new
      quiet = options[:quiet]

      log pastel.cyan("Initializing Ragify..."), quiet

      # Check if already initialized
      if File.exist?(".ragify") && !options[:force]
        puts pastel.yellow("Ragify already initialized. Use --force to reinitialize.")
        return
      end

      # Create .ragify directory
      Dir.mkdir(".ragify") unless Dir.exist?(".ragify")
      log pastel.green("✓ Created .ragify directory"), quiet

      # Create config file
      Ragify::Config.create_default
      log pastel.green("✓ Created default configuration"), quiet

      # Create .ragifyignore file
      create_ragifyignore
      log pastel.green("✓ Created .ragifyignore file"), quiet

      # Check Ollama installation
      log "\n" + pastel.cyan("Checking dependencies..."), quiet
      check_ollama_and_pull_model(quiet)

      puts "\n" + pastel.green("✓ Ragify initialized successfully!")
      puts "\nNext steps:"
      puts "  1. Run: ragify index"
      puts "  2. Run: ragify search \"your query\""
    end

    desc "index [PATH]", "Index Ruby files in the project"
    method_option :path, type: :string, aliases: "-p", desc: "Path to index (default: current directory)"
    method_option :verbose, type: :boolean, aliases: "-v", desc: "Verbose output"
    method_option :quiet, type: :boolean, aliases: "-q", desc: "Suppress non-essential output"
    method_option :strict, type: :boolean, aliases: "-s", desc: "Fail on first error (for CI/CD)"
    method_option :yes, type: :boolean, aliases: "-y", desc: "Continue without prompting on errors"
    method_option :no_embeddings, type: :boolean, desc: "Skip embedding generation"
    def index(path = nil)
      pastel = Pastel.new
      path ||= options[:path] || Dir.pwd
      quiet = options[:quiet]
      verbose = options[:verbose] && !quiet # verbose is ignored if quiet is set

      log pastel.cyan("Indexing project: #{path}"), quiet

      # Load configuration
      config = Ragify::Config.load

      # Initialize components
      indexer = Ragify::Indexer.new(path, config, verbose: verbose)
      chunker = Ragify::Chunker.new(config)
      store = Ragify::Store.new

      # Open the store
      store.open
      log pastel.dim("Database: #{store.db_path}"), quiet

      # Discover files
      log "\n" + pastel.cyan("Discovering Ruby files..."), quiet
      files = indexer.discover_files

      if files.empty?
        puts pastel.yellow("No Ruby files found to index.")
        store.close
        return
      end

      log pastel.green("Found #{files.length} Ruby files"), quiet

      if verbose
        puts "\nFiles to index:"
        files.each { |file| puts "  - #{file}" }
      end

      # Parse and chunk files
      log "\n" + pastel.cyan("Parsing and chunking files..."), quiet

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

      # Create progress bar (unless quiet)
      bar = nil
      unless quiet
        bar = TTY::ProgressBar.new(
          "[:bar] :current/:total :percent :eta",
          total: files.length,
          width: 40
        )
      end

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

            if verbose
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
          puts pastel.red("\n✗ #{file_path}:#{e.diagnostic.location.line}") if verbose

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
          puts pastel.red("\n✗ #{file_path}: #{e.message}") if verbose

          # Strict mode: fail immediately
          if options[:strict]
            puts "\n" + pastel.red("Error in #{file_path}")
            puts pastel.red("  #{e.message}")
            puts "\nExiting due to --strict flag"
            store.close
            exit 1
          end
        end

        bar&.advance
      end

      # Display results
      puts "\n" unless quiet
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

        # Prompt to continue (unless --yes flag or --quiet flag)
        unless options[:yes] || quiet
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

      unless quiet
        puts "\nChunks extracted:"
        puts "  Classes: #{stats[:classes]}"
        puts "  Modules: #{stats[:modules]}"
        puts "  Methods: #{stats[:methods]}"
        puts "  Constants: #{stats[:constants]}"
        puts "\n  Total chunks: #{all_chunks.length}"
      end

      # Clear existing data for indexed files
      log "\n" + pastel.cyan("Clearing old data for indexed files..."), quiet
      files.each { |file| store.delete_file(file) }

      # Day 3 & 4: Generate embeddings and store
      if all_chunks.any? && !options[:no_embeddings]
        log "\n" + pastel.cyan("Generating embeddings..."), quiet

        begin
          # Initialize embedder
          embedder = Ragify::Embedder.new(config)

          # Check Ollama availability
          if embedder.ollama_available?
            # Check model availability
            if embedder.model_available?
              # Prepare texts for embedding
              log pastel.dim("Preparing #{all_chunks.length} chunks for embedding..."), quiet
              prepared_texts = all_chunks.map { |chunk| embedder.prepare_chunk_text(chunk) }

              # Generate embeddings with progress bar
              puts unless quiet
              embeddings = embedder.embed_batch(
                prepared_texts,
                batch_size: 5,
                show_progress: !quiet
              )

              log pastel.green("\n✓ Generated #{embeddings.length} embeddings"), quiet

              # Show cache stats
              unless quiet
                cache_stats = embedder.cache_stats
                puts "  Cache: #{cache_stats[:size]} embeddings (~#{cache_stats[:memory_kb]} KB)"
                puts "  Embedding dimensions: 768 (nomic-embed-text)"
              end

              # Day 4: Store chunks with embeddings
              log "\n" + pastel.cyan("Storing chunks and embeddings..."), quiet

              chunks_with_embeddings = all_chunks.zip(embeddings)
              stored_count = store.insert_batch(chunks_with_embeddings)

              log pastel.green("✓ Stored #{stored_count} chunks with embeddings"), quiet
            else
              puts pastel.yellow("\n⚠️  Model '#{config.model}' not found")
              puts "  Pull model: ollama pull #{config.model}"
              log "\n" + pastel.dim("Storing chunks without embeddings..."), quiet
              store_chunks_without_embeddings(store, all_chunks, quiet)
            end
          else
            puts pastel.yellow("\n⚠️  Ollama not running - skipping embeddings")
            puts "  Start Ollama: ollama serve"
            puts "  Then run: ragify index again"
            log "\n" + pastel.dim("Storing chunks without embeddings..."), quiet
            store_chunks_without_embeddings(store, all_chunks, quiet)
          end
        rescue Ragify::OllamaConnectionError => e
          puts pastel.yellow("\n⚠️  #{e.message}")
          puts "  Storing chunks without embeddings..."
          store_chunks_without_embeddings(store, all_chunks, quiet)
        rescue Ragify::OllamaTimeoutError => e
          puts pastel.red("\n✗ Timeout: #{e.message}")
          puts "  Ollama may be overloaded. Try reducing batch size."
          puts "  Storing chunks without embeddings..."
          store_chunks_without_embeddings(store, all_chunks, quiet)
        rescue Ragify::OllamaError => e
          puts pastel.red("\n✗ Embedding error: #{e.message}")
          puts "  Storing chunks without embeddings..."
          store_chunks_without_embeddings(store, all_chunks, quiet)
        end
      elsif all_chunks.any?
        # --no-embeddings flag
        log "\n" + pastel.cyan("Storing chunks (embeddings skipped)..."), quiet
        store_chunks_without_embeddings(store, all_chunks, quiet)
      end

      # Show final stats
      unless quiet
        puts "\n" + pastel.cyan("Database Statistics:")
        db_stats = store.stats
        puts "  Total chunks: #{db_stats[:total_chunks]}"
        puts "  Total embeddings: #{db_stats[:total_vectors]}"
        puts "  Total files: #{db_stats[:total_files]}"
        puts "  Database size: #{db_stats[:database_size_mb]} MB"
      end

      store.close

      puts "\n" + pastel.green("✓ Indexing complete!")
      puts pastel.dim("Run: ragify search \"your query\"") unless quiet
    rescue Ragify::Error => e
      puts pastel.red("Error: #{e.message}")
      exit 1
    end

    desc "search QUERY", "Search for code using semantic search"
    method_option :limit, type: :numeric, aliases: "-l", default: 5, desc: "Number of results"
    method_option :type, type: :string, aliases: "-t", desc: "Filter by type (method, class, module, constant)"
    method_option :path, type: :string, aliases: "-p", desc: "Filter by file path pattern"
    method_option :min_score, type: :numeric, aliases: "-m", desc: "Minimum similarity score (0.0-1.0)"
    method_option :vector_weight, type: :numeric, aliases: "-w", default: 0.7,
                                  desc: "Vector weight for hybrid search (0.0-1.0, default: 0.7)"
    method_option :format, type: :string, aliases: "-f", default: "colorized",
                           desc: "Output format (colorized, plain, json)"
    method_option :semantic, type: :boolean, desc: "Use semantic search only (requires Ollama)"
    method_option :text, type: :boolean, desc: "Use text search only (no Ollama required)"
    method_option :quiet, type: :boolean, aliases: "-q", desc: "Suppress non-essential output"
    def search(query)
      pastel = Pastel.new
      quiet = options[:quiet]

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

      # Validate vector_weight
      if options[:vector_weight] && (options[:vector_weight] < 0.0 || options[:vector_weight] > 1.0)
        puts pastel.red("Error: --vector-weight must be between 0.0 and 1.0")
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
          puts pastel.yellow("⚠️  Ollama not available. Falling back to text search.") unless quiet
          puts pastel.dim("  For better results, start Ollama: ollama serve") unless quiet
          puts unless quiet
          mode = :text
        end
      end

      # Show search info
      unless quiet
        mode_label = { hybrid: "hybrid (semantic + text)", semantic: "semantic", text: "text" }[mode]
        puts pastel.cyan("Searching: \"#{query}\"")
        mode_info = "Mode: #{mode_label} | Limit: #{options[:limit]}"
        mode_info += " | Vector weight: #{options[:vector_weight]}" if mode == :hybrid
        puts pastel.dim(mode_info)

        filters = []
        filters << "type=#{options[:type]}" if options[:type]
        filters << "path=#{options[:path]}" if options[:path]
        filters << "min_score=#{options[:min_score]}" if options[:min_score]
        puts pastel.dim("Filters: #{filters.join(", ")}") if filters.any?
        puts
      end

      begin
        # Perform search
        results = searcher.search(
          query,
          limit: options[:limit],
          type: options[:type],
          path_filter: options[:path],
          min_score: options[:min_score],
          mode: mode,
          vector_weight: options[:vector_weight]
        )

        if results.empty?
          puts pastel.yellow("No results found.")
          unless quiet
            puts
            puts "Try:"
            puts "  - Using different keywords"
            puts "  - Removing filters"
            puts "  - Lowering --min-score" if options[:min_score]
          end
          store.close
          return
        end

        # Format and display results
        format_sym = options[:format].to_sym
        output = searcher.format_results(results, format: format_sym)
        puts output

        # Summary
        if format_sym != :json && !quiet
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
    method_option :quiet, type: :boolean, aliases: "-q", desc: "Suppress non-essential output"
    def status
      pastel = Pastel.new
      quiet = options[:quiet]

      unless File.exist?(".ragify")
        puts pastel.yellow("Ragify not initialized. Run: ragify init")
        return
      end

      log pastel.cyan("Ragify Status"), quiet
      log pastel.dim("─" * 40), quiet

      # Open store and get stats
      store = Ragify::Store.new
      store.open

      stats = store.stats

      if quiet
        # Quiet mode: just essential info
        puts "Files: #{stats[:total_files]}"
        puts "Chunks: #{stats[:total_chunks]}"
        puts "Embeddings: #{stats[:total_vectors]}"
        puts "Size: #{stats[:database_size_mb]} MB"
      else
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
      end

      store.close
    end

    desc "reindex", "Rebuild the index from scratch"
    method_option :force, type: :boolean, aliases: "-f", desc: "Skip confirmation"
    method_option :quiet, type: :boolean, aliases: "-q", desc: "Suppress non-essential output"
    def reindex
      pastel = Pastel.new
      quiet = options[:quiet]

      unless File.exist?(".ragify")
        puts pastel.yellow("Ragify not initialized. Run: ragify init")
        return
      end

      puts pastel.yellow("This will clear and rebuild the entire index.") unless quiet

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
      log pastel.green("✓ Cleared existing index"), quiet
      store.close

      # Run index command
      invoke :index
    end

    desc "clear", "Clear all indexed data"
    method_option :force, type: :boolean, aliases: "-f", desc: "Skip confirmation"
    method_option :quiet, type: :boolean, aliases: "-q", desc: "Suppress non-essential output"
    def clear
      pastel = Pastel.new
      quiet = options[:quiet]

      unless File.exist?(".ragify")
        puts pastel.yellow("Ragify not initialized. Run: ragify init")
        return
      end

      puts pastel.yellow("This will delete all indexed data.") unless quiet

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

    # Log message unless quiet mode is enabled
    def log(message, quiet = false)
      puts message unless quiet
    end

    def store_chunks_without_embeddings(store, chunks, quiet = false)
      unless quiet
        bar = TTY::ProgressBar.new(
          "Storing [:bar] :current/:total",
          total: chunks.length,
          width: 40
        )
      end

      chunks.each do |chunk|
        store.insert_chunk(chunk, nil)
        bar&.advance
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

    def check_ollama_and_pull_model(quiet = false)
      pastel = Pastel.new

      begin
        # Try to connect to Ollama
        require "faraday"
        conn = Faraday.new(url: "http://localhost:11434") do |f|
          f.response :json
          f.options.timeout = 5
          f.options.open_timeout = 5
        end
        response = conn.get("/api/tags")

        if response.status == 200
          log pastel.green("✓ Ollama is running"), quiet

          # Check for nomic-embed-text model
          models = response.body["models"] || []
          has_nomic = models.any? { |m| m["name"].include?("nomic-embed-text") }

          if has_nomic
            log pastel.green("✓ nomic-embed-text model is available"), quiet
          else
            puts pastel.yellow("! nomic-embed-text model not found")
            puts "  This model is required for semantic search."
            puts "  Size: ~274MB download"
            puts

            # Prompt to pull the model
            require "tty-prompt"
            prompt = TTY::Prompt.new

            if prompt.yes?("Would you like to download nomic-embed-text now?", default: true)
              puts
              puts pastel.cyan("Pulling nomic-embed-text model...")
              puts pastel.dim("This may take a few minutes depending on your connection speed.")
              puts

              # Execute ollama pull
              success = system("ollama pull nomic-embed-text")

              if success
                puts
                puts pastel.green("✓ nomic-embed-text model installed successfully!")
              else
                puts
                puts pastel.red("✗ Failed to pull model")
                puts "  Try manually: ollama pull nomic-embed-text"
              end
            else
              puts
              puts pastel.yellow("Skipping model download.")
              puts "  You can install it later: ollama pull nomic-embed-text"
              puts "  Note: Semantic search won't work without this model."
            end
          end
        end
      rescue Faraday::ConnectionFailed
        puts pastel.yellow("! Ollama not running")
        puts "  Install from: https://ollama.com"
        puts "  Then run: ollama serve"
        puts "  Finally: ollama pull nomic-embed-text"
      rescue Faraday::TimeoutError
        puts pastel.yellow("! Ollama connection timed out")
        puts "  Make sure Ollama is running: ollama serve"
      rescue StandardError => e
        puts pastel.yellow("! Could not check Ollama: #{e.message}")
      end
    end

    def check_ollama_status(pastel)
      require "faraday"
      conn = Faraday.new(url: "http://localhost:11434") do |f|
        f.response :json
        f.options.timeout = 5
        f.options.open_timeout = 5
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
    rescue Faraday::TimeoutError
      puts pastel.yellow("  ! Ollama: connection timed out")
    rescue StandardError => e
      puts pastel.yellow("  ! Ollama: error (#{e.message})")
    end
  end
end
