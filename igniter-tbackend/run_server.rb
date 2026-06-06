# frozen_string_literal: true

require "json"
require "fileutils"

Dir.chdir(__dir__)

# Load config
unless File.exist?("tbackend.config.json")
  puts "Error: tbackend.config.json not found!"
  exit 1
end

config = JSON.parse(File.read("tbackend.config.json"), symbolize_names: true)

# Compile and load Ruby extension
require_relative "tbackend_ruby_extension"
begin
  TBackendRubyExtension.build_and_require!(root: __dir__)
rescue StandardError => e
  puts "Failed to compile or load TBackend Rust extension: #{e.message}"
  exit 1
end

data_dir = config[:data_dir] || "data"
FileUtils.mkdir_p(data_dir)

host = config[:host] || "127.0.0.1"
port = config[:port] || 7401

thread_pool_size = config[:thread_pool_size] || 16
puts "[Server] Starting Rust TCP Server on #{host}:#{port} with pool size #{thread_pool_size}..."
puts "[Server] Dynamic ledgers will be sharded under directory: #{data_dir}"
server = Igniter::TBackendPlayground::Server.start(host, port, data_dir, thread_pool_size)

# Handle clean shutdown signals
running = true
cleanup = proc do
  if running
    running = false
    puts "\n[Server] Graceful shutdown initiated..."
    server.stop rescue nil
    puts "[Server] Shutdown complete."
    exit(0)
  end
end

trap("INT", &cleanup)
trap("TERM", &cleanup)

puts "[Server] Online and listening."

# Prevent background thread from exiting
while running
  sleep 1
end
