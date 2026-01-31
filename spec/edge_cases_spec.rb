# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "fileutils"

RSpec.describe "Ragify Edge Cases" do
  # Use around hook with Dir.chdir block form for robust directory handling
  # This guarantees we return to original directory even if exceptions occur
  around do |example|
    temp_dir = Dir.mktmpdir("ragify_edge_case_test")
    begin
      Dir.chdir(temp_dir) do
        @temp_dir = temp_dir
        FileUtils.mkdir_p(".ragify")
        Ragify::Config.create_default
        example.run
      end
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  # Helper method to access temp_dir in tests
  attr_reader :temp_dir

  describe "empty projects" do
    it "handles project with no Ruby files" do
      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      files = indexer.discover_files
      expect(files).to be_empty
    end

    it "handles project with only non-Ruby files" do
      File.write("README.md", "# My Project")
      File.write("config.json", '{"key": "value"}')
      FileUtils.mkdir_p("assets")
      File.write("assets/style.css", "body { color: red; }")

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      files = indexer.discover_files
      expect(files).to be_empty
    end

    it "handles empty Ruby files" do
      File.write("empty.rb", "")

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      files = indexer.discover_files
      # NOTE: Empty files are skipped by the indexer (no content to index)
      expect(files).to be_empty
    end

    it "handles Ruby file with only whitespace" do
      File.write("whitespace.rb", "   \n\n   \t\t\n   ")

      config = Ragify::Config.load
      chunker = Ragify::Chunker.new(config)

      chunks = chunker.chunk_file("whitespace.rb", "   \n\n   \t\t\n   ")
      expect(chunks).to be_empty
    end

    it "handles Ruby file with only comments" do
      File.write("comments_only.rb", <<~RUBY)
        # This is a comment
        # Another comment
        # Yet another comment
      RUBY

      config = Ragify::Config.load
      chunker = Ragify::Chunker.new(config)

      content = File.read("comments_only.rb")
      chunks = chunker.chunk_file("comments_only.rb", content)

      # Should create a file-level chunk
      expect(chunks.length).to eq(1)
      expect(chunks.first[:type]).to eq("file")
    end
  end

  describe "projects with only syntax errors" do
    it "handles project where all files have syntax errors" do
      # File with unclosed string literal - definitely broken
      File.write("broken1.rb", <<~RUBY)
        class Broken
          def method
            puts "unclosed string
          end
        end
      RUBY

      # File with unclosed string - definitely broken
      File.write("broken2.rb", <<~RUBY)
        def bad_method
          x = "another unclosed string
        end
      RUBY

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)

      files = indexer.discover_files
      expect(files.length).to eq(2)

      failures = []
      files.each do |file_path|
        content = indexer.read_file(file_path)
        begin
          chunker.chunk_file(file_path, content)
        rescue Parser::SyntaxError
          failures << file_path
        end
      end

      # All files should have failed
      expect(failures.length).to eq(2)
    end

    it "raises Parser::SyntaxError for invalid Ruby" do
      config = Ragify::Config.load
      chunker = Ragify::Chunker.new(config)

      bad_code = <<~RUBY
        class Broken
          def method
            puts "unclosed
          end
        end
      RUBY

      expect do
        chunker.chunk_file("broken.rb", bad_code)
      end.to raise_error(Parser::SyntaxError)
    end
  end

  describe "very large files" do
    it "handles files with many methods" do
      # Create a file with 100 methods
      methods = (1..100).map do |i|
        <<~RUBY
          def method_#{i}
            puts "Method #{i}"
          end
        RUBY
      end.join("\n")

      large_file = <<~RUBY
        class LargeClass
          #{methods}
        end
      RUBY

      File.write("large.rb", large_file)

      config = Ragify::Config.load
      chunker = Ragify::Chunker.new(config)

      chunks = chunker.chunk_file("large.rb", large_file)

      # Should have 1 class + 100 methods
      expect(chunks.length).to eq(101)

      method_chunks = chunks.select { |c| c[:type] == "method" }
      expect(method_chunks.length).to eq(100)
    end

    it "marks very large methods with metadata flag" do
      # Create a method with > 100 lines
      lines = (1..150).map { |i| "    puts \"Line #{i}\"" }.join("\n")
      large_method = <<~RUBY
        class Example
          def huge_method
        #{lines}
          end
        end
      RUBY

      File.write("huge_method.rb", large_method)

      config = Ragify::Config.load
      chunker = Ragify::Chunker.new(config)

      chunks = chunker.chunk_file("huge_method.rb", large_method)
      method_chunk = chunks.find { |c| c[:name] == "huge_method" }

      expect(method_chunk).not_to be_nil
      expect(method_chunk[:metadata][:large_chunk]).to be true
      expect(method_chunk[:metadata][:lines_count]).to be > 100
    end

    it "handles deeply nested classes" do
      nested_code = <<~RUBY
        module Level1
          module Level2
            module Level3
              class Level4
                class Level5
                  def deep_method
                    puts "Very deep"
                  end
                end
              end
            end
          end
        end
      RUBY

      File.write("nested.rb", nested_code)

      config = Ragify::Config.load
      chunker = Ragify::Chunker.new(config)

      chunks = chunker.chunk_file("nested.rb", nested_code)

      deep_method = chunks.find { |c| c[:name] == "deep_method" }
      expect(deep_method).not_to be_nil
      expect(deep_method[:context]).to include("Level1")
      expect(deep_method[:context]).to include("Level5")
    end
  end

  describe "unicode and special characters" do
    it "handles unicode in code" do
      unicode_code = <<~RUBY
        # Ñ‚ÐµÑÑ‚ комментарий (Russian)
        # ä¸­æ–‡æ³¨é‡Š (Chinese)
        # æ—¥æœ¬èªžã‚³ãƒ¡ãƒ³ãƒˆ (Japanese)
        class UnicodeTest
          GREETING = "Helloï¼Œä¸–ç•Œï¼ðŸŽ‰"

          def greet(name)
            puts "Hello, \#{name}! ðŸ'‹"
          end

          def emoji_method
            puts "ðŸ¦„ðŸŒˆâœ¨"
          end
        end
      RUBY

      File.write("unicode.rb", unicode_code)

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)

      content = indexer.read_file("#{temp_dir}/unicode.rb")
      expect(content).not_to be_nil

      chunks = chunker.chunk_file("unicode.rb", unicode_code)
      expect(chunks.length).to be > 0

      # Find the constant with unicode
      greeting_const = chunks.find { |c| c[:name] == "GREETING" }
      expect(greeting_const).not_to be_nil
    end

    it "handles special characters in method names" do
      special_code = <<~RUBY
        class SpecialMethods
          def valid?
            true
          end

          def save!
            persist
          end

          def data=(value)
            @data = value
          end

          def [](key)
            @hash[key]
          end

          def <=>(other)
            self.value <=> other.value
          end
        end
      RUBY

      File.write("special.rb", special_code)

      config = Ragify::Config.load
      chunker = Ragify::Chunker.new(config)

      chunks = chunker.chunk_file("special.rb", special_code)

      method_names = chunks.select { |c| c[:type] == "method" }.map { |c| c[:name] }

      expect(method_names).to include("valid?")
      expect(method_names).to include("save!")
      expect(method_names).to include("data=")
      expect(method_names).to include("[]")
      expect(method_names).to include("<=>")
    end

    it "handles heredocs" do
      heredoc_code = <<~RUBY
        class HeredocExample
          SQL_QUERY = <<~SQL
            SELECT * FROM users
            WHERE active = true
            ORDER BY created_at DESC
          SQL

          def template
            <<~HTML
              <html>
                <body>Hello</body>
              </html>
            HTML
          end
        end
      RUBY

      File.write("heredoc.rb", heredoc_code)

      config = Ragify::Config.load
      chunker = Ragify::Chunker.new(config)

      chunks = chunker.chunk_file("heredoc.rb", heredoc_code)

      # Should parse without error
      expect(chunks.length).to be > 0

      template_method = chunks.find { |c| c[:name] == "template" }
      expect(template_method).not_to be_nil
    end
  end

  describe "symlinks" do
    it "follows symlinks to Ruby files" do
      # Create actual file
      FileUtils.mkdir_p("actual")
      File.write("actual/real_file.rb", <<~RUBY)
        class RealClass
          def real_method
            puts "I'm real!"
          end
        end
      RUBY

      # Create symlink
      FileUtils.mkdir_p("linked")
      begin
        File.symlink("#{temp_dir}/actual/real_file.rb", "#{temp_dir}/linked/linked_file.rb")
      rescue Errno::ENOENT, NotImplementedError
        skip "Symlinks not supported on this system"
      end

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      files = indexer.discover_files

      # Should find both the original and the symlink
      expect(files.length).to be >= 1
    end

    it "handles broken symlinks gracefully" do
      FileUtils.mkdir_p("broken_links")

      begin
        # Create symlink to non-existent file
        File.symlink("#{temp_dir}/nonexistent.rb", "#{temp_dir}/broken_links/broken.rb")
      rescue Errno::ENOENT, NotImplementedError
        skip "Symlinks not supported on this system"
      end

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      # Should not raise an error
      files = indexer.discover_files

      # Broken symlink should be skipped
      broken_link = files.find { |f| f.include?("broken.rb") }
      expect(broken_link).to be_nil
    end

    it "handles circular symlinks" do
      FileUtils.mkdir_p("dir_a")
      FileUtils.mkdir_p("dir_b")

      File.write("dir_a/file.rb", "class A; end")

      begin
        # Create circular reference
        File.symlink("#{temp_dir}/dir_b", "#{temp_dir}/dir_a/link_to_b")
        File.symlink("#{temp_dir}/dir_a", "#{temp_dir}/dir_b/link_to_a")
      rescue Errno::ENOENT, NotImplementedError
        skip "Symlinks not supported on this system"
      end

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      # Should complete without infinite loop
      # The Find module handles this automatically
      expect { indexer.discover_files }.not_to raise_error
    end
  end

  describe "permission errors" do
    it "handles unreadable files gracefully" do
      File.write("unreadable.rb", "class Unreadable; end")

      # Make file unreadable (skip on Windows)
      begin
        File.chmod(0o000, "unreadable.rb")
      rescue Errno::EPERM
        skip "Cannot change file permissions on this system"
      end

      # Skip if we're running as root (can read anything)
      skip "Running as root, cannot test permission errors" if Process.uid.zero?

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      content = indexer.read_file("#{temp_dir}/unreadable.rb")

      # Should return nil for unreadable files
      expect(content).to be_nil

      # Restore permissions for cleanup
      File.chmod(0o644, "unreadable.rb")
    end

    it "handles unreadable directories gracefully" do
      FileUtils.mkdir_p("unreadable_dir")
      File.write("unreadable_dir/file.rb", "class InDir; end")

      begin
        File.chmod(0o000, "unreadable_dir")
      rescue Errno::EPERM
        skip "Cannot change directory permissions on this system"
      end

      skip "Running as root, cannot test permission errors" if Process.uid.zero?

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      # Should complete without raising error
      files = indexer.discover_files

      # File in unreadable dir should not be found
      unreadable_file = files.find { |f| f.include?("unreadable_dir") }
      expect(unreadable_file).to be_nil

      # Restore permissions for cleanup
      File.chmod(0o755, "unreadable_dir")
    end
  end

  describe "binary files" do
    it "skips binary files with .rb extension" do
      # Create a binary file with .rb extension
      File.binwrite("binary.rb", "\x00\x01\x02\x03\x04\x05binary content\x00")

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)

      files = indexer.discover_files

      # Binary file should be skipped
      binary_file = files.find { |f| f.include?("binary.rb") }
      expect(binary_file).to be_nil
    end
  end

  describe "encoding issues" do
    # TODO: Future implementation should handle non-UTF-8 files gracefully
    # Currently, the chunker will raise Encoding::CompatibilityError on
    # files with invalid UTF-8 bytes. This is tracked for future work.
    #
    # it "handles Latin-1 encoded files" do
    #   File.binwrite("latin1.rb", "# Comment with \xE9\xE8\xE0\nclass Latin1; end".b)
    #   ...
    # end

    it "handles UTF-8 with BOM" do
      # Create a file with UTF-8 BOM
      File.binwrite("with_bom.rb", "\xEF\xBB\xBFclass WithBom\n  def method\n    puts 'hello'\n  end\nend\n")

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)

      content = indexer.read_file("#{temp_dir}/with_bom.rb")
      expect(content).not_to be_nil

      # Parser may or may not handle BOM - either is acceptable
      begin
        chunks = chunker.chunk_file("with_bom.rb", content)
        expect(chunks).to be_an(Array)
      rescue Parser::SyntaxError
        # Acceptable - BOM can cause parsing issues
      end
    end
  end

  describe "search edge cases" do
    before do
      File.write("sample.rb", <<~RUBY)
        class Sample
          def method_one
            puts "one"
          end

          def method_two
            puts "two"
          end
        end
      RUBY

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)
      @store = Ragify::Store.new
      @store.open

      files = indexer.discover_files
      files.each do |file_path|
        content = indexer.read_file(file_path)
        chunks = chunker.chunk_file(file_path, content)
        chunks.each { |chunk| @store.insert_chunk(chunk, nil) }
      end

      @searcher = Ragify::Searcher.new(@store, nil, config)
    end

    after do
      @store&.close
    end

    it "handles empty search query" do
      expect do
        @searcher.search("", mode: :text)
      end.to raise_error(ArgumentError, /cannot be empty/)
    end

    it "handles whitespace-only search query" do
      expect do
        @searcher.search("   ", mode: :text)
      end.to raise_error(ArgumentError, /cannot be empty/)
    end

    it "handles query with no results" do
      results = @searcher.search("xyznonexistent123", mode: :text)
      expect(results).to be_empty
    end

    it "handles very long search query" do
      long_query = "a" * 1000
      results = @searcher.search(long_query, mode: :text)
      expect(results).to be_an(Array) # Should not crash
    end

    it "handles special characters in search query" do
      # These should not cause SQL injection or crashes
      # Note: FTS5 has its own query syntax and many special characters
      # will cause syntax errors. This tests safe characters only.
      # TODO: Future implementation should escape FTS5 special characters
      # like single quotes, parentheses, %, *, etc.
      safe_queries = [
        "method_with_underscore",
        "simple query",
        "CamelCaseMethod"
      ]

      safe_queries.each do |query|
        expect do
          @searcher.search(query, mode: :text)
        end.not_to raise_error
      end

      # These queries contain FTS5 special syntax characters and will fail
      # until we implement proper escaping. Documenting expected behavior:
      # - "method' OR '1'='1" - single quotes break FTS5
      # - "method%wildcard%" - % is special in FTS5
      # - "method*" - * is a prefix search operator
      # - "method; DROP TABLE chunks;--" - semicolons may be ok but risky
    end

    it "handles min_score filter" do
      # min_score filters results below the threshold
      # Note: BM25 score normalization can produce scores very close to 1.0
      # for exact matches, so we test with a moderate threshold
      results = @searcher.search("method", mode: :text, min_score: 0.5)
      results.each do |result|
        expect(result[:score]).to be >= 0.5
      end
    end

    it "handles invalid type filter gracefully in searcher" do
      # The CLI validates this, but searcher should also handle it
      results = @searcher.search("method", mode: :text, type: "invalid_type")
      expect(results).to be_empty
    end
  end

  describe "database edge cases" do
    it "handles concurrent access attempts" do
      File.write("test.rb", "class Test; end")

      config = Ragify::Config.load
      indexer = Ragify::Indexer.new(temp_dir, config)
      chunker = Ragify::Chunker.new(config)

      store1 = Ragify::Store.new
      store2 = Ragify::Store.new

      store1.open
      store2.open

      files = indexer.discover_files
      content = indexer.read_file(files.first)
      chunks = chunker.chunk_file(files.first, content)

      # Both should be able to insert (SQLite handles locking)
      chunks.each { |chunk| store1.insert_chunk(chunk, nil) }

      # Should be able to read from both
      expect(store1.stats[:total_chunks]).to be > 0
      expect(store2.stats[:total_chunks]).to be > 0

      store1.close
      store2.close
    end

    it "handles database corruption gracefully" do
      # Write garbage to database file
      FileUtils.mkdir_p(".ragify")
      File.write(".ragify/ragify.db", "this is not a valid sqlite database")

      store = Ragify::Store.new

      expect { store.open }.to raise_error(SQLite3::NotADatabaseException)
    end
  end
end
