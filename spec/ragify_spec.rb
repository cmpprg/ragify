# frozen_string_literal: true

RSpec.describe Ragify do
  it "has a version number" do
    expect(Ragify::VERSION).not_to be nil
    expect(Ragify::VERSION).to eq("0.1.0")
  end

  describe Ragify::Config do
    it "creates default configuration" do
      config = Ragify::Config.new
      expect(config.ollama_url).to eq("http://localhost:11434")
      expect(config.model).to eq("nomic-embed-text")
      expect(config.chunk_size_limit).to eq(1000)
      expect(config.search_result_limit).to eq(5)
      expect(config.ignore_patterns).to be_an(Array)
    end

    it "merges custom configuration with defaults" do
      custom_config = { "ollama_url" => "http://custom:11434" }
      config = Ragify::Config.new(custom_config)
      expect(config.ollama_url).to eq("http://custom:11434")
      expect(config.model).to eq("nomic-embed-text") # Still has default
    end
  end

  describe Ragify::Indexer do
    let(:test_dir) { Dir.mktmpdir }
    let(:config) { Ragify::Config.new }
    let(:indexer) { Ragify::Indexer.new(test_dir, config) }

    after { FileUtils.rm_rf(test_dir) }

    it "discovers Ruby files in directory" do
      # Create test files
      FileUtils.mkdir_p("#{test_dir}/app/models")
      File.write("#{test_dir}/app/models/user.rb", "class User; end")
      File.write("#{test_dir}/app/models/post.rb", "class Post; end")
      File.write("#{test_dir}/README.md", "# README") # Should be ignored

      files = indexer.discover_files
      expect(files.length).to eq(2)
      expect(files).to all(end_with(".rb"))
    end

    it "ignores files matching patterns" do
      # Create test files
      File.write("#{test_dir}/user.rb", "class User; end")
      FileUtils.mkdir_p("#{test_dir}/spec")
      File.write("#{test_dir}/spec/user_spec.rb", "# test")

      # Create .ragifyignore
      File.write("#{test_dir}/.ragifyignore", "spec/**/*")

      files = indexer.discover_files
      expect(files.length).to eq(1)
      expect(files.first).to end_with("user.rb")
    end

    it "reads file content" do
      File.write("#{test_dir}/test.rb", "class Test\nend")
      content = indexer.read_file("#{test_dir}/test.rb")
      expect(content).to include("class Test")
      expect(content).to include("end")
    end

    it "validates Ruby files" do
      File.write("#{test_dir}/valid.rb", "class User\nend")
      expect(indexer.validate_ruby_file("#{test_dir}/valid.rb")).to be true
    end
  end
end
