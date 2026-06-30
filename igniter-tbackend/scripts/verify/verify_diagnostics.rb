# frozen_string_literal: true
# verify_diagnostics.rb
# Diagnostics, Observable Telemetry & Store Statistics Pack Verification Test

require "json"
require "socket"
require "zlib"
require "fileutils"
require "securerandom"

# ANSI text styling
GREEN   = "\e[32m"
RED     = "\e[31m"
CYAN    = "\e[36m"
YELLOW  = "\e[33m"
BOLD    = "\e[1m"
RESET   = "\e[0m"

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

# TCP client helper
class DiagnosticsTestClient
  def initialize(host, port)
    @socket = TCPSocket.new(host, port)
    @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
  end

  def send_req(req)
    body = JSON.generate(req).b
    frame = [body.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
    @socket.write(frame)

    header = @socket.read(4)
    return { ok: false, error: "EOF" } unless header && header.bytesize == 4

    len = header.unpack1("N")
    resp_body = @socket.read(len)
    return { ok: false, error: "Truncated" } unless resp_body && resp_body.bytesize == len

    _crc = @socket.read(4)
    JSON.parse(resp_body, symbolize_names: true)
  end

  def close
    @socket.close rescue nil
  end
end

puts "\n#{BOLD}#{CYAN}=== TBACKEND DIAGNOSTICS & UNOBSTRUCTED METRICS TEST SUITE ===#{RESET}"

# Setup clean diagnostics data dir
DATA_DIR = "diagnostics_data"
FileUtils.rm_rf(DATA_DIR)
FileUtils.mkdir_p(DATA_DIR)

# 1. Spawn the compiled TBackend standalone daemon on port 7409
puts "\n[TBackend Daemon] Spawning daemon in the background on port 7409..."
daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir #{DATA_DIR} --pool-size 4", out: "/dev/null", err: "/dev/null")
sleep 1.0 # Allow socket to bind

begin
  client = DiagnosticsTestClient.new("127.0.0.1", 7409)

  # Assert server is online
  assert(client.send_req(op: "ping")[:ok] == true, "Daemon connected and pinged successfully")

  # 2. Seed multiple partitions with varying bitemporal characteristics
  puts "\n[Seeding] Committing facts to 'store_A' and 'store_B' to populate stats..."
  
  # store_A: 4 version updates for "user-1", 1 update for "user-2" (Total: 5 facts, Key cardinality: 2, Max version depth: 4)
  5.times do |i|
    key = (i < 4) ? "user-1" : "user-2"
    fact = {
      id: SecureRandom.uuid,
      store: "store_A",
      key: key,
      value: { username: "alex", active: true, balance: 100.0 * i, meta: { tags: ["ruby", "rust"], val: i } },
      value_hash: "hash-a-#{i}",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
    client.send_req(op: "write_fact", fact: fact)
  end

  # store_B: 3 unique keys, 1 version each (Total: 3 facts, Key cardinality: 3, Max version depth: 1)
  3.times do |i|
    fact = {
      id: SecureRandom.uuid,
      store: "store_B",
      key: "task-#{i}",
      value: { title: "Refactor database engine #{i}", complexity: "high" },
      value_hash: "hash-b-#{i}",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
    client.send_req(op: "write_fact", fact: fact)
  end

  # 3. Query Diagnostics Summary
  puts "\n[Diagnostics Summary] Fetching global node summary telemetry..."
  res_summary = client.send_req(op: "diagnostics_summary")
  
  assert_equal(true, res_summary[:ok], "diagnostics_summary route completed successfully")
  
  summary = res_summary[:summary]
  assert_equal("127.0.0.1", summary[:host], "Reported host is 127.0.0.1")
  assert_equal(7409, summary[:port], "Reported port is 7409")
  assert_equal(DATA_DIR, summary[:data_dir], "Reported data directory matches physical path")
  assert_equal(4, summary[:pool_size], "Reported thread pool size matches input")
  assert(summary[:uptime_seconds] > 0, "Uptime is tracked correctly as a positive float: #{summary[:uptime_seconds]}s")
  assert_equal(2, summary[:total_stores], "Server successfully counts exactly 2 active stores")
  assert(summary[:registered_stores].include?("store_A"), "Active stores array contains 'store_A'")
  assert(summary[:registered_stores].include?("store_B"), "Active stores array contains 'store_B'")
  assert_equal(8, summary[:total_facts_across_stores], "Global database facts counter registers exactly 8 total facts across all engines")
  
  # Audit routes registration in signature
  ops = summary[:registered_operations]
  assert(ops.include?("diagnostics_summary"), "Mounted command registry maps diagnostics_summary")
  assert(ops.include?("diagnostics_stores"), "Mounted command registry maps diagnostics_stores")
  assert(ops.include?("write_fact"), "Core bitemporal ledger commands are present")

  # 4. Query Diagnostics Stores (Global Map)
  puts "\n[Store Telemetry] Fetching all-store detailed analytics..."
  res_stores = client.send_req(op: "diagnostics_stores")
  assert_equal(true, res_stores[:ok], "diagnostics_stores all-stores route completed successfully")
  
  stores = res_stores[:stores]
  assert_equal(2, stores.length, "Stores list returns statistics for exactly 2 dynamic stores")

  store_a_stat = stores.find { |s| s[:store_name] == "store_A" }
  assert_equal(5, store_a_stat[:in_memory_facts], "store_A correctly audits 5 in-memory records")
  assert_equal(2, store_a_stat[:key_cardinality], "store_A correctly audits key cardinality of exactly 2 unique keys")
  assert_equal(4, store_a_stat[:max_version_depth], "store_A correctly audits maximum version timeline depth of 4 for 'user-1'")
  assert(store_a_stat[:estimated_memory_bytes] > 1000, "store_A estimates memory footprint successfully: #{store_a_stat[:estimated_memory_bytes]} bytes")
  assert_equal(true, store_a_stat[:has_persistence], "store_A reports persistent storage is active")
  assert(store_a_stat[:wal_disk_bytes] > 0, "store_A reports positive physical WAL disk size: #{store_a_stat[:wal_disk_bytes]} bytes")

  store_b_stat = stores.find { |s| s[:store_name] == "store_B" }
  assert_equal(3, store_b_stat[:in_memory_facts], "store_B correctly audits 3 in-memory records")
  assert_equal(3, store_b_stat[:key_cardinality], "store_B correctly audits key cardinality of exactly 3 unique keys")
  assert_equal(1, store_b_stat[:max_version_depth], "store_B correctly audits maximum version timeline depth of 1")
  assert(store_b_stat[:estimated_memory_bytes] > 500, "store_B estimates memory footprint successfully: #{store_b_stat[:estimated_memory_bytes]} bytes")

  # 5. Query Diagnostics Stores for a Specific Store
  puts "\n[Store Telemetry] Querying fine-grained metrics for 'store_A' only..."
  res_single = client.send_req(op: "diagnostics_stores", store: "store_A")
  assert_equal(true, res_single[:ok], "diagnostics_stores single-store query completed successfully")
  
  single_stat = res_single[:store]
  assert_equal("store_A", single_stat[:store_name], "Returned store stats matches target name 'store_A'")
  assert_equal(5, single_stat[:in_memory_facts], "Single store reports exactly 5 facts")
  assert_equal(2, single_stat[:key_cardinality], "Single store reports exactly 2 unique keys")

  # 6. Verify Traffic/Bandwidth Telemetry Audits
  puts "\n[Observability] Verifying real-time request counts and network bandwidth tracker..."
  res_telemetry = client.send_req(op: "diagnostics_summary")
  tel = res_telemetry[:telemetry]
  assert(tel[:total_requests] > 10, "BaseAuditPack processed requests tracked correctly in diagnostics dashboard: #{tel[:total_requests]}")
  assert(tel[:bytes_read] > 0, "Bandwidth bytes read tracker registers positive raw input traffic: #{tel[:bytes_read]} B")
  assert(tel[:bytes_written] > 0, "Bandwidth bytes written tracker registers positive raw output traffic: #{tel[:bytes_written]} B")
  assert(tel[:average_latency_us] >= 0.0, "Latency telemetry tracks and computes average network latencies in microseconds")

  client.close
  puts "\n#{BOLD}#{GREEN}🏆 DIAGNOSTICS & SYSTEM observability PACK VERIFICATION COMPLETED SUCCESSFULLY!#{RESET}\n\n"
rescue => e
  puts "#{RED}Error during diagnostics test: #{e.message}#{RESET}"
  puts e.backtrace.join("\n")
  $failed_tests += 1
ensure
  # Graceful teardown
  puts "\n[Tear Down] Stopping servers and cleaning up diagnostics directories..."
  begin
    Process.kill("INT", daemon_pid)
    Process.wait(daemon_pid)
  rescue => e
    # Process already closed
  end
  FileUtils.rm_rf(DATA_DIR)
end

if $failed_tests == 0
  puts "#{GREEN}🏆 ALL DIAGNOSTICS TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Diagnostics Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
