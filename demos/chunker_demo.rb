#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing Ragify's Day 2 chunker capabilities (FIXED VERSION)
# Run this to see how the chunker parses Ruby code

require_relative "../lib/ragify"
require "json"

puts "=" * 80
puts "Ragify Day 2 - Chunker Demonstration (FIXED)"
puts "=" * 80
puts

# Sample Ruby code to parse
sample_code = <<~RUBY
  # User authentication module
  module Authentication
    # Represents a user in the system
    class User < ApplicationRecord
      # User role constants
      ADMIN_ROLE = "admin"
      USER_ROLE = "user"

      # Initialize a new user
      def initialize(name, email)
        @name = name
        @email = email
      end

      # Authenticate the user
      # @param password [String] The password to check
      # @return [Boolean] Whether authentication succeeded
      def authenticate(password)
        BCrypt::Password.new(@password_digest) == password
      end

      # Class method to find a user by email
      def self.find_by_email(email)
        User.where(email: email).first
      end

      private

      # Validate the email format
      def validate_email
        @email.match?(/\\A[\\w+\\-.]+@[a-z\\d\\-.]+\\.[a-z]+\\z/i)
      end

      # Hash the password
      def hash_password(password)
        BCrypt::Password.create(password)
      end
    end

    # Authentication service class
    class AuthService
      def self.login(email, password)
        user = User.find_by_email(email)
        user&.authenticate(password)
      end
    end
  end
RUBY

# Initialize the chunker
config = Ragify::Config.new
chunker = Ragify::Chunker.new(config)

# Parse the sample code
puts "Parsing sample Ruby code..."
puts "Expected: ~10 chunks (1 module, 2 classes, 6 methods, 2 constants)"
puts

chunks = chunker.chunk_file("sample.rb", sample_code)

# Check for errors
error_chunks = chunks.select { |c| c[:type] == "error" }
if error_chunks.any?
  puts "⚠️  WARNING: Found error chunks (indicates a bug in chunker):"
  error_chunks.each do |chunk|
    puts "  #{chunk[:metadata][:error]}: #{chunk[:metadata][:error_message]}"
  end
  puts
end

puts "✓ Found #{chunks.length} chunks:"
puts "-" * 80
puts

# Group chunks by type for better display
chunks_by_type = chunks.group_by { |c| c[:type] }

# Display summary by type
puts "Summary by Type:"
chunks_by_type.each do |type, type_chunks|
  next if type == "error" # Already displayed

  puts "  #{type.capitalize}s (#{type_chunks.length}):"
  type_chunks.each do |chunk|
    context_str = chunk[:context].empty? ? "" : " in #{chunk[:context]}"
    visibility = chunk.dig(:metadata, :visibility)
    vis_str = visibility && visibility != "public" ? " [#{visibility}]" : ""
    puts "    - #{chunk[:name]}#{context_str}#{vis_str}"
  end
end
puts

# Display detailed view of first few chunks
puts "-" * 80
puts "Detailed View (first 5 chunks):"
puts "-" * 80
puts

chunks.first(5).each_with_index do |chunk, i|
  next if chunk[:type] == "error" # Skip error chunks in detail view

  puts "\nChunk #{i + 1}: #{chunk[:type].upcase}"
  puts "  Name: #{chunk[:name]}"
  puts "  Context: #{chunk[:context]}" unless chunk[:context].empty?
  puts "  Lines: #{chunk[:start_line]}-#{chunk[:end_line]}"

  # Type-specific metadata
  case chunk[:type]
  when "class"
    puts "  Parent Class: #{chunk[:metadata][:parent_class]}" if chunk[:metadata][:parent_class]
  when "method"
    puts "  Visibility: #{chunk[:metadata][:visibility]}"
    puts "  Class Method: #{chunk[:metadata][:class_method]}"
    puts "  Parameters: #{chunk[:metadata][:parameters].join(", ")}" if chunk[:metadata][:parameters]&.any?
  end

  # Show comments if present
  unless chunk[:comments].empty?
    puts "  Comments:"
    chunk[:comments].each_line { |line| puts "    #{line.strip}" }
  end

  # Show code preview
  puts "  Code Preview:"
  preview = chunk[:code].lines.first(2).map(&:rstrip).join("\n    ")
  puts "    #{preview}"
  puts "    ..." if chunk[:code].lines.count > 2
end

puts
puts "=" * 80
puts "Verification:"
puts "-" * 80

# Verify expected chunks
expected = {
  "module" => 1,
  "class" => 2,
  "method" => 6,
  "constant" => 2
}

expected.each do |type, expected_count|
  actual_count = chunks.count { |c| c[:type] == type }
  status = actual_count == expected_count ? "✓" : "✗"
  puts "  #{status} #{type.capitalize}s: expected #{expected_count}, got #{actual_count}"
end

puts
if error_chunks.empty?
  puts "✓ No error chunks - chunker working correctly!"
else
  puts "✗ Found #{error_chunks.length} error chunk(s) - needs debugging"
end

puts
puts "=" * 80
puts "Demonstration Complete!"
puts
puts "If you see errors above, copy the FIXED chunker.rb to your project"
puts "=" * 80
