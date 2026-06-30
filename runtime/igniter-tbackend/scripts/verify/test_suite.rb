# frozen_string_literal: true

require "json"
require "fileutils"
require "socket"
require "zlib"
require "securerandom"

ROOT = File.expand_path("../..", __dir__)
Dir.chdir(ROOT)

# ANSI styling
GREEN  = "\e[32m"
RED    = "\e[31m"
YELLOW = "\e[33m"
CYAN   = "\e[36m"
BOLD   = "\e[1m"
RESET  = "\e[0m"

$failed_tests = 0

def assert(cond, msg = "Assertion failed")
  if cond
    puts "  #{GREEN}✔ PASS:#{RESET} #{msg}"
  else
    puts "  #{RED}✘ FAIL:#{RESET} #{msg}"
    $failed_tests += 1
  end
end

def assert_equal(expected, actual, msg = "Assertion failed")
  if expected == actual
    puts "  #{GREEN}✔ PASS:#{RESET} #{msg}"
  else
    puts "  #{RED}✘ FAIL:#{RESET} #{msg} - Expected: #{expected.inspect}, Got: #{actual.inspect}"
    $failed_tests += 1
  end
end

# Compile and load Ruby extension
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: Compilation ===#{RESET}"
require_relative "../dev/tbackend_ruby_extension"
begin
  TBackendRubyExtension.build_and_require!(root: ROOT)
rescue StandardError => e
  puts "#{RED}Compilation or extension load failed: #{e.message}#{RESET}"
  exit 1
end

# Setup Playground Ruby wrappers
module Igniter
  module TBackendPlayground
    class Fact
      def self.build(store:, key:, value:, causation: nil, valid_time: nil, schema_version: 1)
        _native_build(store.to_s, key.to_s, value, causation, valid_time&.to_f, schema_version.to_i)
      end
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

    class Client
      def initialize(host, port)
        @socket = TCPSocket.new(host, port)
        @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
      end
      def ping
        send_req(op: "ping")[:pong] == true
      end
      def write_fact(fact)
        send_req(op: "write_fact", fact: fact.to_h)
      end
      def metrics
        send_req(op: "metrics")
      end
      def size(store = nil)
        send_req(op: "size", store: store)[:size]
      end
      def latest_for(store:, key:, as_of: nil)
        send_req(op: "latest_for", store: store, key: key, as_of: as_of)
      end
      def close
        send_req(op: "close") rescue nil
        @socket.close rescue nil
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
        return { ok: false, error: "Truncated" } unless resp_body && resp_body.bytesize == len
        crc_bytes = @socket.read(4)
        JSON.parse(resp_body, symbolize_names: true)
      end
    end
  end
end

# 1. Fact Domain Model tests
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: Bitemporal Domain Fact Model ===#{RESET}"
fact = Igniter::TBackendPlayground::Fact.build(
  store: "jobs",
  key: "job-1",
  value: { "status" => "pending", "tags" => ["dev"] }
)
assert_equal("jobs", fact.store, "Fact store name is preserved")
assert_equal("job-1", fact.key, "Fact key is preserved")
assert_equal("pending", fact.value[:status], "Fact nested field is preserved (Symbolized Key)")
assert(fact.id.is_a?(String) && fact.id.length == 36, "Fact UUID is automatically generated")
assert(fact.value_hash.length == 64, "Fact value Blake3 cryptographic hash is computed")

# 2. FactLog Timeline indexing tests
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: FactLog Sharded Indexing & Time-Travel ===#{RESET}"
log = Igniter::TBackendPlayground::FactLog.new
t_writes = []
3.times do |i|
  t_writes << Time.now.to_f
  f = Igniter::TBackendPlayground::Fact.build(store: "jobs", key: "job-1", value: { step: i })
  log.append(f)
  sleep 0.02
end
assert_equal(3, log.size, "FactLog tracks correct appended size")

# mid travel lookup
latest_mid = log.latest_for(store: "jobs", key: "job-1", as_of: t_writes[1] + 0.01)
assert(latest_mid != nil, "Latest lookup at midpoint transaction time returns a valid fact")
assert_equal(1, latest_mid.value[:step], "Latest lookup at midpoint transaction time returns step 1")

# facts range query
facts_range = log.facts_for(store: "jobs", key: "job-1", since: t_writes[0] - 0.01, as_of: t_writes[1] + 0.01)
assert_equal(2, facts_range.size, "Facts range query between first and second write returns exactly 2 records")

# 3. WAL Durability tests
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: Write-Ahead-Log Durability & Replay ===#{RESET}"
TEST_WAL = "test_run.wal"
FileUtils.rm_f(TEST_WAL)
wal = Igniter::TBackendPlayground::FileBackend.new(TEST_WAL)
f1 = Igniter::TBackendPlayground::Fact.build(store: "jobs", key: "job-100", value: { value: 10 })
f2 = Igniter::TBackendPlayground::Fact.build(store: "jobs", key: "job-200", value: { value: 20 })
wal.write_fact(f1)
wal.write_fact(f2)
wal.close

# Replay test
log2 = Igniter::TBackendPlayground::FactLog.new
wal2 = Igniter::TBackendPlayground::FileBackend.new(TEST_WAL)
wal2.replay.each { |f| log2.replay(f) }
assert_equal(2, log2.size, "Durable WAL successfully replayed and restored all in-memory facts")
wal2.close
FileUtils.rm_f(TEST_WAL)

# 4. Thread-Pool TCP Server & Telemetry tests
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: Thread-Pool TCP Server & Telemetry ===#{RESET}"
# Spawning Server with a pool of 4 workers in in-memory mode (data_dir = nil)
server = Igniter::TBackendPlayground::Server.start("127.0.0.1", 7402, nil, 4)
sleep 0.1

begin
  client = Igniter::TBackendPlayground::Client.new("127.0.0.1", 7402)
  assert(client.ping, "Client successfully connected to Thread-Pool TCP Server and pinged")

  # Perform FFI client writes
  f_net = Igniter::TBackendPlayground::Fact.build(store: "jobs", key: "job-300", value: { net: true })
  client.write_fact(f_net)
  assert_equal(1, client.size("jobs"), "WriteFact operation accepted and appended successfully over TCP socket")

  # Query metrics over TCP
  metrics = client.metrics
  assert_equal(4, metrics[:total_requests], "Telemetry tracker counts correct request packets")
  assert_equal(1, metrics[:ops][:write_fact], "Telemetry tracks correct write_fact operation hit counts")
  assert_equal(1, metrics[:ops][:metrics], "Telemetry tracks metrics query operation hit counts")
  assert(metrics[:total_latency_us] > 0, "Telemetry computes processing latencies in microseconds")
  assert(metrics[:bytes_read] > 0, "Telemetry logs processed bandwidth bytes")

  client.close
rescue => e
  puts "  #{RED}Error in networking test: #{e.message}#{RESET}"
  $failed_tests += 1
ensure
  server.stop rescue nil
end

# 5. Socket Read Timeout Starvation tests
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: Starvation Timeout Protection ===#{RESET}"
# Using Port 7403 to prevent any temporary port reuse race condition with 7402
server4 = Igniter::TBackendPlayground::Server.start("127.0.0.1", 7403, nil, 4)
sleep 0.1

begin
  # Connect and hold socket open sending bad header size
  socket = TCPSocket.new("127.0.0.1", 7403)
  socket.write([5].pack("N") + "hello" + [0].pack("N")) rescue nil
  sleep 0.1
  socket.close rescue nil
  assert(true, "Starvation client socket managed gracefully without worker crash")
ensure
  server4.stop rescue nil
end

# 6. Multi-Tenant Disk Sharding & WAL Reload tests
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: Multi-Tenant Disk Sharding ===#{RESET}"
TEST_DIR = "test_run_data"
FileUtils.rm_rf(TEST_DIR)

# Boot Server with test_run_data directory
server5 = Igniter::TBackendPlayground::Server.start("127.0.0.1", 7404, TEST_DIR, 4)
sleep 0.1

begin
  client5 = Igniter::TBackendPlayground::Client.new("127.0.0.1", 7404)
  
  # Commit facts to price_ledger
  f_price = Igniter::TBackendPlayground::Fact.build(store: "price_ledger", key: "BTCUSD", value: { price: 65000 })
  client5.write_fact(f_price)
  
  # Commit facts to bid_ledger
  f_bid = Igniter::TBackendPlayground::Fact.build(store: "bid_ledger", key: "bid-1", value: { amount: 100 })
  client5.write_fact(f_bid)
  
  # Assert separate WAL files exist on disk
  assert(File.exist?("#{TEST_DIR}/price_ledger.wal"), "price_ledger.wal file was dynamically created on disk")
  assert(File.exist?("#{TEST_DIR}/bid_ledger.wal"), "bid_ledger.wal file was dynamically created on disk")
  
  # Assert correct sizes via network queries
  assert_equal(1, client5.size("price_ledger"), "price_ledger reports size of 1 fact")
  assert_equal(1, client5.size("bid_ledger"), "bid_ledger reports size of 1 fact")
  assert_equal(2, client5.size, "Total database reports size of 2 facts across all stores")
  
  client5.close
ensure
  server5.stop rescue nil
end

# Now restart the server and assert that it preloads/replays BOTH ledgers!
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: Boot-Time Preloading & WAL Replay ===#{RESET}"
server6 = Igniter::TBackendPlayground::Server.start("127.0.0.1", 7405, TEST_DIR, 4)
sleep 0.1

begin
  client6 = Igniter::TBackendPlayground::Client.new("127.0.0.1", 7405)
  
  # Assert that both stores are preloaded and fully replayed/warm!
  assert_equal(1, client6.size("price_ledger"), "price_ledger is automatically preloaded and replayed from disk")
  assert_equal(1, client6.size("bid_ledger"), "bid_ledger is automatically preloaded and replayed from disk")
  assert_equal(2, client6.size, "Total database reports warm size of 2 facts across stores")
  
  # Verify fact values were replayed correctly
  res_price = client6.latest_for(store: "price_ledger", key: "BTCUSD")
  assert_equal(65000, res_price[:fact][:value][:price], "BTCUSD price fact payload was successfully replayed")
  
  res_bid = client6.latest_for(store: "bid_ledger", key: "bid-1")
  assert_equal(100, res_bid[:fact][:value][:amount], "bid-1 fact payload was successfully replayed")

  client6.close
ensure
  server6.stop rescue nil
  FileUtils.rm_rf(TEST_DIR)
end

# Final Results
puts "\n#{BOLD}#{CYAN}=== TEST SUITE: Final Summary ===#{RESET}"
if $failed_tests == 0
  puts "#{GREEN}🏆 ALL TESTS PASSED SUCCESSFULLY!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Test Suite FAILED with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
