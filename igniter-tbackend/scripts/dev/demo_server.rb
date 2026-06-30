# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "socket"
require "json"
require "zlib"

ROOT = File.expand_path("../..", __dir__)
Dir.chdir(ROOT)

puts "=== 1. Compiling Playground Rust Extension ==="
require_relative "tbackend_ruby_extension"
TBackendRubyExtension.build_and_require!(root: ROOT)

# Setup Playground Ruby wrappers
module Igniter
  module TBackendPlayground
    class Fact
      def self.build(store:, key:, value:, causation: nil, valid_time: nil, term: nil, schema_version: 1)
        vt = valid_time.nil? ? (term ? term.to_f : nil) : valid_time.to_f
        _native_build(
          store.to_s,
          key.to_s,
          value,
          causation,
          vt,
          schema_version.to_i
        )
      end

      alias_method :_native_value, :value
      def value = _native_value
    end

    class FactLog
      def append(fact)
        _native_append(fact)
        fact
      end

      def latest_for(store:, key:, as_of: nil)
        latest_for_native(store.to_s, key.to_s, as_of&.to_f)
      end

      def facts_for(store:, key: nil, since: nil, as_of: nil)
        facts_for_native(store.to_s, key&.to_s, since&.to_f, as_of&.to_f)
      end

      def query_scope(store:, filters:, as_of: nil)
        query_scope_native(store.to_s, filters, as_of&.to_f)
      end
    end

    # High-Performance Bitemporal Network Client
    class Client
      def initialize(host = "127.0.0.1", port = 7401)
        @socket = TCPSocket.new(host, port)
        @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
      end

      def ping
        send_req(op: "ping")[:pong] == true
      end

      def write_fact(fact)
        send_req(op: "write_fact", fact: fact.to_h)
      end

      def latest_for(store:, key:, as_of: nil)
        res = send_req(op: "latest_for", store: store, key: key, as_of: as_of)
        if res[:ok] && res[:fact]
          Fact.build(
            store: res[:fact][:store],
            key: res[:fact][:key],
            value: res[:fact][:value],
            causation: res[:fact][:causation],
            valid_time: res[:fact][:valid_time],
            schema_version: res[:fact][:schema_version]
          )
        else
          nil
        end
      end

      def facts_for(store:, key: nil, since: nil, as_of: nil)
        res = send_req(op: "facts_for", store: store, key: key, since: since, as_of: as_of)
        if res[:ok] && res[:facts]
          res[:facts].map do |f|
            Fact.build(
              store: f[:store],
              key: f[:key],
              value: f[:value],
              causation: f[:causation],
              valid_time: f[:valid_time],
              schema_version: f[:schema_version]
            )
          end
        else
          []
        end
      end

      def query_scope(store:, filters:, as_of: nil)
        res = send_req(op: "query_scope", store: store, filters: filters, as_of: as_of)
        if res[:ok] && res[:facts]
          res[:facts].map do |f|
            Fact.build(
              store: f[:store],
              key: f[:key],
              value: f[:value],
              causation: f[:causation],
              valid_time: f[:valid_time],
              schema_version: f[:schema_version]
            )
          end
        else
          []
        end
      end

      def close
        send_req(op: "close") rescue nil
        @socket.close
      end

      private

      def send_req(req)
        body = JSON.generate(req).b
        frame = [body.bytesize].pack("N") << body << [Zlib.crc32(body)].pack("N")
        @socket.write(frame)
        
        header = @socket.read(4)
        return { ok: false, error: "EOF" } unless header && header.bytesize == 4
        
        len = header.unpack1("N")
        resp_body = @socket.read(len)
        return { ok: false, error: "Truncated body" } unless resp_body && resp_body.bytesize == len
        
        crc_bytes = @socket.read(4)
        return { ok: false, error: "Truncated CRC" } unless crc_bytes && crc_bytes.bytesize == 4
        
        raise "CRC mismatch" unless Zlib.crc32(resp_body) == crc_bytes.unpack1("N")
        
        JSON.parse(resp_body, symbolize_names: true)
      end
    end
  end
end

puts "\n=== 2. Starting Rust-Native TCP Server ==="
WAL_PATH = "server_demo.wal"
FileUtils.rm_f(WAL_PATH)

log = Igniter::TBackendPlayground::FactLog.new
wal = Igniter::TBackendPlayground::FileBackend.new(WAL_PATH)

# Start Rust Server on port 7401 in a native background thread
server = Igniter::TBackendPlayground::Server.start("127.0.0.1", 7401, log, wal, 16)
puts "Rust TCP Server is listening on 127.0.0.1:7401"

# Wait a fraction of a second for binding
sleep 0.1

puts "\n=== 3. Running Bitemporal Network Verification ==="
begin
  # Create a client
  client = Igniter::TBackendPlayground::Client.new
  puts "Client connected. Ping successful? #{client.ping}"
  raise "Ping failed!" unless client.ping

  store = "technician_jobs"
  key = "job-101"

  # Write 5 chronological job states over network
  t_writes = []
  5.times do |i|
    value = { status: i < 3 ? "in_progress" : "completed", step: i }
    t_before = Time.now.to_f
    t_writes << t_before
    fact = Igniter::TBackendPlayground::Fact.build(store: store, key: key, value: value)
    
    # Send write over the network socket
    client.write_fact(fact)
    
    puts "  [Write] Step #{i}: status = #{value[:status]}"
    sleep 0.05
  end

  # Check point-in-time lookup at midpoint over network
  t_mid = t_writes[2] - 0.02
  latest_mid = client.latest_for(store: store, key: key, as_of: t_mid)
  puts "\n[Time Travel Query] status at midpoint: #{latest_mid.value[:status]} (expected: in_progress)"
  raise "Correctness mismatch!" unless latest_mid.value[:status] == "in_progress"

  # Check range slice query over network
  range = client.facts_for(store: store, key: key, since: t_writes[0] - 0.01, as_of: t_writes[3] + 0.02)
  puts "[Range Query] Facts count in range: #{range.size} (expected: 4)"
  raise "Range query size mismatch!" unless range.size == 4

  # Check scope filtering query over network
  scope = client.query_scope(store: store, filters: { status: "completed" })
  puts "[Scope Query] Completed jobs in store: #{scope.size} (expected: 1)"
  raise "Scope size mismatch!" unless scope.size == 1

  puts "\n=== 4. Parallel Concurrent Clients Load Test ==="
  THREAD_COUNT = 8
  REQUESTS_PER_THREAD = 200

  t_start = Time.now
  threads = THREAD_COUNT.times.map do |t_idx|
    Thread.new do
      # Each thread creates its own TCP client connection
      c = Igniter::TBackendPlayground::Client.new
      
      REQUESTS_PER_THREAD.times do |i|
        # Perform mixed read/write actions
        if i % 5 == 0
          fact = Igniter::TBackendPlayground::Fact.build(
            store: "load_store_#{t_idx}",
            key: "key_#{i}",
            value: { load_index: i }
          )
          c.write_fact(fact)
        else
          c.latest_for(store: store, key: key)
        end
      end
      c.close
    end
  end
  threads.each(&:join)
  t_elapsed = Time.now - t_start
  total_ops = THREAD_COUNT * REQUESTS_PER_THREAD
  qps = total_ops / t_elapsed

  puts "Concurrent Load Test Completed:"
  puts "  Threads:     #{THREAD_COUNT}"
  puts "  Total Ops:   #{total_ops} (network writes + bitemporal lookups)"
  puts "  Elapsed:     #{t_elapsed.round(3)} seconds"
  puts "  Throughput:  #{qps.round(0)} requests/sec over TCP!"

  puts "\n✅ Full-Cycle Runtime + Sharded Temporal TCP Server Validation PASSED!"

ensure
  puts "\n=== 5. Stopping Rust Server ==="
  server.stop
  wal.close
  FileUtils.rm_f(WAL_PATH)
  puts "Stopped."
end
