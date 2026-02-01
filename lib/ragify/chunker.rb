# frozen_string_literal: true

require "parser/current"
require "digest"

module Ragify
  # Chunker splits Ruby code into semantically meaningful chunks
  # Uses the Parser gem to build an AST and extract classes, modules, methods, and constants
  class Chunker
    # Maximum lines for a single chunk before splitting (fallback if config not set)
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

      # Split large chunks with sliding window overlap
      split_large_chunks(chunks)
    end

    private

    # Split large chunks using sliding window with overlap
    # @param chunks [Array<Hash>] Array of chunks
    # @return [Array<Hash>] Array with large chunks split into parts
    def split_large_chunks(chunks)
      result = []

      chunks.each do |chunk|
        lines = chunk[:code].lines
        lines_count = lines.count
        chunk_limit = @config.chunk_size_limit || MAX_CHUNK_LINES

        if lines_count <= chunk_limit
          # Chunk fits within limit - keep as is
          result << chunk
        else
          # Chunk is too large - split with overlap
          parts = split_chunk_with_overlap(chunk, lines, chunk_limit)
          result.concat(parts)
        end
      end

      result
    end

    # Split a single chunk into multiple parts with overlap
    # @param chunk [Hash] Original chunk
    # @param lines [Array<String>] Lines of code
    # @param limit [Integer] Maximum lines per chunk
    # @return [Array<Hash>] Array of chunk parts
    def split_chunk_with_overlap(chunk, lines, limit)
      overlap = @config.chunk_overlap || 20
      stride = limit - overlap # How far we move forward each time
      total_lines = lines.count
      parts = []
      part_number = 1

      # Calculate total parts for metadata
      total_parts = ((total_lines - overlap).to_f / stride).ceil
      total_parts = [total_parts, 1].max # At least 1 part

      start_idx = 0
      while start_idx < total_lines
        # Calculate end index for this part
        end_idx = [start_idx + limit, total_lines].min

        # Extract lines for this part
        part_lines = lines[start_idx...end_idx]
        part_code = part_lines.join

        # Calculate actual line numbers in original file
        part_start_line = chunk[:start_line] + start_idx
        part_end_line = chunk[:start_line] + end_idx - 1

        # Create part chunk
        part_chunk = {
          id: "#{chunk[:id]}_part#{part_number}",
          type: chunk[:type],
          name: chunk[:name],
          code: part_code,
          context: chunk[:context],
          file_path: chunk[:file_path],
          start_line: part_start_line,
          end_line: part_end_line,
          comments: part_number == 1 ? chunk[:comments] : "", # Only first part gets comments
          metadata: {
            **chunk[:metadata],
            is_partial: true,
            part_number: part_number,
            total_parts: total_parts,
            parent_chunk_id: chunk[:id],
            overlap_lines: overlap
          }
        }

        parts << part_chunk
        part_number += 1

        # Move forward by stride amount
        start_idx += stride

        # If we're close to the end, just finish
        break if start_idx + overlap >= total_lines
      end

      parts
    end

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

      # Mark large chunks (for visibility, splitting happens later)
      lines_count = end_line - start_line + 1
      if lines_count > 100
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
      return node.children[1].to_s if node.is_a?(Parser::AST::Node) && node.type == :const

      "anonymous"
    end

    # Extract parent class name from a class node
    def extract_parent_class(node)
      parent_node = node.children[1]
      return nil unless parent_node

      return unless parent_node.is_a?(Parser::AST::Node) && parent_node.type == :const

      parent_node.children[1].to_s
    end

    # Extract method parameters from a method node
    def extract_parameters(node)
      return [] unless node.is_a?(Parser::AST::Node)

      # Method parameters are in different positions for def vs defs
      args_node = if node.type == :defs
                    node.children[2]
                  else
                    node.children[1]
                  end

      return [] unless args_node && args_node.is_a?(Parser::AST::Node)

      params = []

      args_node.children.each do |child|
        next unless child.is_a?(Parser::AST::Node)

        case child.type
        when :arg
          params << child.children[0].to_s
        when :optarg
          params << "#{child.children[0]}=#{child.children[1].location.expression.source}"
        when :restarg
          params << "*#{child.children[0]}"
        when :kwarg
          params << "#{child.children[0]}:"
        when :kwoptarg
          params << "#{child.children[0]}: #{child.children[1].location.expression.source}"
        when :kwrestarg
          params << "**#{child.children[0]}"
        when :blockarg
          params << "&#{child.children[0]}"
        end
      end

      params
    end

    # Determine method visibility from context
    def determine_visibility(node, content)
      location = node.location
      return "public" unless location

      # Look backwards from method definition for visibility modifiers
      lines = content.lines
      (location.line - 1).downto(0) do |i|
        line = lines[i].strip
        return "private" if line == "private"
        return "protected" if line == "protected"
        return "public" if line == "public"

        # Stop if we hit another definition
        break if line.match?(/^(class|module)\b/)
      end

      "public"
    end
  end
end
