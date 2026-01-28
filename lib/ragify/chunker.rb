# frozen_string_literal: true

require "parser/current"
require "digest"

module Ragify
  # Chunker splits Ruby code into semantically meaningful chunks
  # Uses the Parser gem to build an AST and extract classes, modules, methods, and constants
  class Chunker
    # Maximum lines for a single chunk before splitting
    MAX_CHUNK_LINES = 100

    attr_reader :config

    def initialize(config)
      @config = config
    end

    # Chunk a Ruby file into semantically meaningful pieces
    # @param file_path [String] Path to the Ruby file
    # @param content [String] Content of the Ruby file
    # @return [Array<Hash>] Array of chunk hashes with metadata
    def chunk_file(file_path, content)
      return [] if content.nil? || content.strip.empty?

      chunks = []

      begin
        # Parse the Ruby code into an AST
        buffer = Parser::Source::Buffer.new(file_path)
        buffer.source = content

        parser = Parser::CurrentRuby.new
        ast = parser.parse(buffer)

        # Extract chunks from the AST
        extract_chunks(ast, file_path, content, chunks) if ast

        # If no chunks were extracted (e.g., file with only top-level code),
        # create a single chunk for the entire file
        chunks << create_file_chunk(file_path, content) if chunks.empty? && !content.strip.empty?
      rescue Parser::SyntaxError => e
        # Re-raise syntax errors - caller should handle them
        # Don't create error chunks, let the indexer decide what to do
        raise e
      rescue StandardError => e
        # Re-raise parsing errors - caller should handle them
        raise e
      end

      # Filter out anonymous chunks - they're not useful for search
      chunks.reject! { |chunk| chunk[:name] == "anonymous" }

      chunks
    end

    private

    # Extract chunks from an AST node recursively
    def extract_chunks(node, file_path, content, chunks, context = [])
      return unless node.is_a?(Parser::AST::Node)

      case node.type
      when :class
        extract_class(node, file_path, content, chunks, context)
      when :module
        extract_module(node, file_path, content, chunks, context)
      when :def, :defs
        extract_method(node, file_path, content, chunks, context)
      when :casgn
        extract_constant(node, file_path, content, chunks, context)
      when :begin, :block, :if, :case, :while, :until, :for
        # For container nodes, just recurse into children
        node.children.each do |child|
          extract_chunks(child, file_path, content, chunks, context)
        end
      else
        # Recursively process child nodes for other node types
        node.children.each do |child|
          extract_chunks(child, file_path, content, chunks, context)
        end
      end
    end

    # Extract a class definition
    def extract_class(node, file_path, content, chunks, context)
      class_name = extract_name(node.children[0])
      new_context = context + ["class #{class_name}"]

      chunk = create_chunk(
        node: node,
        file_path: file_path,
        content: content,
        type: "class",
        name: class_name,
        context: context.join(" > "),
        metadata: {
          parent_class: extract_parent_class(node),
          context_path: new_context
        }
      )

      chunks << chunk if chunk

      # Process class body for methods and nested classes
      body = node.children[2]
      extract_chunks(body, file_path, content, chunks, new_context) if body
    end

    # Extract a module definition
    def extract_module(node, file_path, content, chunks, context)
      module_name = extract_name(node.children[0])
      new_context = context + ["module #{module_name}"]

      chunk = create_chunk(
        node: node,
        file_path: file_path,
        content: content,
        type: "module",
        name: module_name,
        context: context.join(" > "),
        metadata: {
          context_path: new_context
        }
      )

      chunks << chunk if chunk

      # Process module body
      body = node.children[1]
      extract_chunks(body, file_path, content, chunks, new_context) if body
    end

    # Extract a method definition
    def extract_method(node, file_path, content, chunks, context)
      is_class_method = node.type == :defs
      method_name = if is_class_method
                      extract_name(node.children[1])
                    else
                      extract_name(node.children[0])
                    end

      # Determine visibility based on context
      visibility = determine_visibility(node, content)

      chunk = create_chunk(
        node: node,
        file_path: file_path,
        content: content,
        type: "method",
        name: method_name,
        context: context.join(" > "),
        metadata: {
          visibility: visibility,
          class_method: is_class_method,
          parameters: extract_parameters(node),
          context_path: context
        }
      )

      chunks << chunk if chunk
    end

    # Extract a constant definition
    def extract_constant(node, file_path, content, chunks, context)
      constant_name = extract_name(node.children[1])

      chunk = create_chunk(
        node: node,
        file_path: file_path,
        content: content,
        type: "constant",
        name: constant_name,
        context: context.join(" > "),
        metadata: {
          context_path: context
        }
      )

      chunks << chunk if chunk
    end

    # Create a chunk hash from an AST node
    def create_chunk(node:, file_path:, content:, type:, name:, context:, metadata:)
      location = node.location
      return nil unless location

      start_line = location.line
      end_line = location.last_line

      # Extract the code for this chunk
      code = extract_code(content, start_line, end_line)

      # If the chunk is too large, we still include it but mark it
      lines_count = end_line - start_line + 1
      if lines_count > MAX_CHUNK_LINES
        metadata[:large_chunk] = true
        metadata[:lines_count] = lines_count
      end

      # Extract any comments/docstrings before the definition
      comments = extract_comments(content, start_line)

      # Create unique ID for this chunk
      chunk_id = generate_chunk_id(file_path, type, name, start_line)

      {
        id: chunk_id,
        type: type,
        name: name,
        code: code,
        context: context,
        file_path: file_path,
        start_line: start_line,
        end_line: end_line,
        comments: comments,
        metadata: metadata
      }
    end

    # Create a chunk for an entire file (when no structure is detected)
    def create_file_chunk(file_path, content)
      {
        id: generate_chunk_id(file_path, "file", "top_level", 1),
        type: "file",
        name: File.basename(file_path, ".rb"),
        code: content,
        context: "",
        file_path: file_path,
        start_line: 1,
        end_line: content.lines.count,
        comments: "",
        metadata: {
          top_level: true
        }
      }
    end

    # Extract code between line numbers
    def extract_code(content, start_line, end_line)
      lines = content.lines
      lines[start_line - 1..end_line - 1].join
    end

    # Extract comments immediately before a definition
    def extract_comments(content, definition_line)
      lines = content.lines
      comments = []

      # Look backwards from the definition line for comments
      (definition_line - 2).downto(0) do |i|
        line = lines[i].strip
        break if line.empty? || !line.start_with?("#")

        comments.unshift(line)
      end

      comments.join("\n")
    end

    # Generate a unique ID for a chunk
    def generate_chunk_id(file_path, type, name, line)
      # Create a hash from the file path, type, name, and line number
      content = "#{file_path}:#{type}:#{name}:#{line}"
      Digest::SHA256.hexdigest(content)[0..15]
    end

    # Extract the name from an AST node or Symbol
    def extract_name(node)
      return "anonymous" if node.nil?
      return node.to_s if node.is_a?(Symbol)

      case node.type
      when :const
        node.children[1].to_s
      when :sym
        node.children[0].to_s
      else
        node.to_s
      end
    end

    # Extract parent class name from a class node
    def extract_parent_class(class_node)
      parent = class_node.children[1]
      return nil unless parent

      extract_name(parent)
    end

    # Extract method parameters
    def extract_parameters(method_node)
      args_node = method_node.children[1]
      return [] unless args_node

      args_node.children.map do |arg|
        next nil unless arg.is_a?(Parser::AST::Node)

        case arg.type
        when :arg
          arg.children[0].to_s
        when :optarg
          default_val = arg.children[1]&.location&.expression&.source || "..."
          "#{arg.children[0]}=#{default_val}"
        when :kwarg
          "#{arg.children[0]}:"
        when :kwoptarg
          default_val = arg.children[1]&.location&.expression&.source || "..."
          "#{arg.children[0]}: #{default_val}"
        when :restarg
          "*#{arg.children[0]}"
        when :kwrestarg
          "**#{arg.children[0]}"
        when :blockarg
          "&#{arg.children[0]}"
        else
          arg.to_s
        end
      end.compact
    rescue StandardError
      []
    end

    # Determine method visibility (public, private, protected)
    # This is a simplified version - a full implementation would need to track
    # visibility modifiers in the AST traversal
    def determine_visibility(node, content)
      # Check if the method appears after a visibility modifier
      location = node.location
      return "public" unless location

      # Look for visibility keywords before this method
      lines_before = content.lines[0...location.line - 1]
      lines_before.reverse_each do |line|
        stripped = line.strip
        return "private" if stripped == "private"
        return "protected" if stripped == "protected"
        return "public" if stripped == "public"

        # Stop at class/module boundaries
        break if stripped.match?(/^(class|module)\b/)
      end

      "public"
    end
  end
end
