# frozen_string_literal: true
# verify_snapshot.rb
# Declarative Bitemporal Rollups, Memory Index Pruning & Atomic WAL Compaction Verification Test

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
class SnapshotTestClient
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

puts "\n#{BOLD}#{CYAN}=== TBACKEND DYNAMIC ROLLUPS & COMPACTION TEST SUITE ===#{RESET}"

# Setup clean compaction data dir
DATA_DIR = "compaction_data"
FileUtils.rm_rf(DATA_DIR)
FileUtils.mkdir_p(DATA_DIR)

# 1. Spawn the compiled TBackend standalone daemon on port 7409 pointing to compaction_data/
puts "\n[TBackend Daemon] Spawning daemon in the background on port 7409..."
daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir #{DATA_DIR} --pool-size 4 --unsafe-compaction true", out: "/dev/null", err: "/dev/null")
sleep 1.0 # Allow socket to bind

begin
  client = SnapshotTestClient.new("127.0.0.1", 7409)

  # Assert server is online
  assert(client.send_req(op: "ping")[:ok] == true, "Daemon connected and pinged successfully")

  # 2. Seed LeadSignal Webhook facts
  puts "\n[Seeding] Committing 10 facts (5 backdated cold facts, 5 warm present-time facts)..."
  
  # A. Cold facts: transaction_time is 4 days ago (Time.now - 345600.0) -> exceeds 3 days retention
  time_cold = Time.now.to_f - 345600.0
  5.times do |i|
    fact = {
      id: SecureRandom.uuid,
      store: "lead_signals",
      key: "lead-cold-#{i}",
      value: { vendor_name: "eLocal", zip_code: "90210", accepted: true, bid: 45.0 + i },
      value_hash: "cold-hash-#{i}",
      transaction_time: time_cold,
      valid_time: time_cold,
      schema_version: 1
    }
    client.send_req(op: "write_fact", fact: fact)
  end

  # B. Warm facts: transaction_time is Present time -> inside 3 days retention
  time_warm = Time.now.to_f
  5.times do |i|
    fact = {
      id: SecureRandom.uuid,
      store: "lead_signals",
      key: "lead-warm-#{i}",
      value: { vendor_name: "eLocal", zip_code: "90210", accepted: true, bid: 60.0 + i },
      value_hash: "warm-hash-#{i}",
      transaction_time: time_warm,
      valid_time: time_warm,
      schema_version: 1
    }
    client.send_req(op: "write_fact", fact: fact)
  end

  # Let's verify total size is 10
  assert_equal(10, client.send_req(op: "size", store: "lead_signals")[:size], "Memory log contains exactly 10 raw facts before compaction")
  
  # Capturing initial WAL file size
  wal_path = "#{DATA_DIR}/lead_signals.wal"
  assert(File.exist?(wal_path), "Durable WAL file successfully created on disk")
  initial_wal_size = File.size(wal_path)
  puts "   Initial WAL file size: #{initial_wal_size} bytes"

  # 3. Create Rollup Policy
  puts "\n[Snapshot Policy] Creating 3-day retention daily rollup policy..."
  res_policy = client.send_req(
    op: "snapshot_policy_create",
    source_store: "lead_signals",
    target_store: "lead_signals_summary",
    retention_period: 259200.0, # 3 days in seconds
    group_by: ["value.vendor_name", "value.zip_code", "value.accepted"],
    aggregates: [
      { field: "value.bid", op: "sum" },
      { field: "", op: "count" }
    ],
    interval: "daily"
  )
  assert_equal(true, res_policy[:ok], "Rollup policy successfully created remotely")
  policy_id = res_policy[:policy_id]
  assert(policy_id.start_with?("pol_"), "Policy ID has 'pol_' prefix")

  # 4. Trigger manual Rollup Sweep & WAL Compaction
  puts "\n[Compaction Trigger] Running manual snapshot_trigger sweep..."
  res_trigger = client.send_req(
    op: "snapshot_trigger",
    policy_id: policy_id
  )
  assert_equal(true, res_trigger[:ok], "Manual compactor sweep completed successfully")
  assert_equal(5, res_trigger[:pruned_facts], "Compactor successfully identified and pruned exactly 5 cold facts older than 3 days!")
  assert_equal(1, res_trigger[:created_summaries], "Compactor generated exactly 1 daily aggregate summary fact in the target store!")

  # 5. Assert Memory Index Pruning
  puts "\n[RAM Audit] Verifying memory index state after sweep..."
  assert_equal(5, client.send_req(op: "size", store: "lead_signals")[:size], "Memory log of source store is successfully pruned, holding only 5 warm facts!")
  assert_equal(1, client.send_req(op: "size", store: "lead_signals_summary")[:size], "Memory log of target store contains exactly 1 rolled-up summary fact!")

  # Verify rolled-up aggregates
  res_summary = client.send_req(op: "facts_for", store: "lead_signals_summary")
  summary_fact = res_summary[:facts].first
  assert_equal("eLocal", summary_fact[:value][:value_vendor_name], "Summary group value matches 'eLocal'")
  assert_equal("90210", summary_fact[:value][:value_zip_code], "Summary group value matches '90210'")
  assert_equal(true, summary_fact[:value][:value_accepted], "Summary group value matches accepted: true")
  assert_equal(5, summary_fact[:value][:count_fact], "Rollup count aggregate correctly calculates 5 raw facts")
  # Sum of bids: 45 + 46 + 47 + 48 + 49 = 235.0
  assert_equal(235.0, summary_fact[:value][:sum_value_bid], "Rollup sum of bids aggregate correctly calculates 235.0 price total")

  # 6. Assert Disk Space Compaction
  puts "\n[Disk Audit] Verifying physical disk WAL compaction..."
  compacted_wal_size = File.size(wal_path)
  puts "   Compacted WAL file size: #{compacted_wal_size} bytes"
  assert(compacted_wal_size < initial_wal_size, "Atomic WAL compaction successfully shrunk file size on disk!")

  client.close

  # 7. Restart Daemon and verify Warm Boot Preloading Replay correctness
  puts "\n[TBackend Daemon] Stopping daemon to test reboot recovery..."
  Process.kill("INT", daemon_pid)
  Process.wait(daemon_pid)

  puts "\n[TBackend Daemon] Rebooting daemon on port 7409 using compacted storage..."
  daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir #{DATA_DIR} --pool-size 4 --unsafe-compaction true", out: "/dev/null", err: "/dev/null")
  sleep 1.0 # Allow bind

  client2 = SnapshotTestClient.new("127.0.0.1", 7409)
  
  # Verify that only the 5 warm facts are loaded at boot time!
  assert_equal(5, client2.send_req(op: "size", store: "lead_signals")[:size], "Warm boot preloader preloaded exactly 5 warm facts from compacted WAL!")
  assert_equal(1, client2.send_req(op: "size", store: "lead_signals_summary")[:size], "Warm boot preloader preloaded exactly 1 rolled-up summary fact!")

  # Verify warm facts values are intact
  res_warm = client2.send_req(op: "facts_for", store: "lead_signals", key: "lead-warm-0")
  warm_fact = res_warm[:facts].first
  assert_equal("eLocal", warm_fact[:value][:vendor_name], "Warm fact payload vendor replayed successfully from compacted WAL")
  assert_equal("90210", warm_fact[:value][:zip_code], "Warm fact payload zip replayed successfully from compacted WAL")
  assert(warm_fact[:value_hash].is_a?(String) && warm_fact[:value_hash].match?(/\A[0-9a-f]{64}\z/), "Warm fact carries server canonical blake3 value_hash")
  assert(warm_fact[:value_hash] != "warm-hash-0", "Warm fact value_hash was server-stamped, not legacy client echo")

  client2.close
  puts "\n#{BOLD}#{GREEN}🏆 SNAPSHOT/COMPACTION PACK VERIFICATION COMPLETED SUCCESSFULLY!#{RESET}\n\n"
rescue => e
  puts "#{RED}Error during snapshot test: #{e.message}#{RESET}"
  puts e.backtrace.join("\n")
  $failed_tests += 1
ensure
  # Graceful teardown
  puts "\n[Tear Down] Stopping servers and cleaning up compaction directories..."
  begin
    Process.kill("INT", daemon_pid)
    Process.wait(daemon_pid)
  rescue => e
    # Process already closed
  end
  FileUtils.rm_rf(DATA_DIR)
end

if $failed_tests == 0
  puts "#{GREEN}🏆 ALL SNAPSHOT/COMPACTION TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Snapshot/Compaction Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
