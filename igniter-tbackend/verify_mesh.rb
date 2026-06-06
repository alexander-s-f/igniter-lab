# frozen_string_literal: true
# verify_mesh.rb
# Multi-Node Bitemporal Gossip Synchronization & Replication Test Suite

require "json"
require "fileutils"
require "socket"
require "zlib"
require "securerandom"

# ANSI text styling
GREEN   = "\e[32m"
RED     = "\e[31m"
YELLOW  = "\e[33m"
CYAN    = "\e[36m"
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

# TCP Frame Client helper
class MeshTestClient
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

puts "\n#{BOLD}#{CYAN}=== DISTRIBUTED P2P MESH CLUSTER TEST SUITE ===#{RESET}"

# 1. Clean up stale directories
DIR_A = "test_mesh_data_A"
DIR_B = "test_mesh_data_B"
DIR_C = "test_mesh_data_C"
FileUtils.rm_rf(DIR_A)
FileUtils.rm_rf(DIR_B)
FileUtils.rm_rf(DIR_C)

# 2. Spawn 3 standalone tbackend nodes forming a cross-connected mesh
puts "\n[Mesh Setup] Spawning 3 concurrent TBackend daemons cross-linked as peers..."
pids = []

# Node A: Port 7402, Peer list contains B & C
pids << spawn("./target/release/tbackend --host 127.0.0.1 --port 7402 --data-dir #{DIR_A} --peers 127.0.0.1:7403,127.0.0.1:7404 --pool-size 4", out: "/dev/null", err: "/dev/null")
# Node B: Port 7403, Peer list contains A & C
pids << spawn("./target/release/tbackend --host 127.0.0.1 --port 7403 --data-dir #{DIR_B} --peers 127.0.0.1:7402,127.0.0.1:7404 --pool-size 4", out: "/dev/null", err: "/dev/null")
# Node C: Port 7404, Peer list contains A & B
pids << spawn("./target/release/tbackend --host 127.0.0.1 --port 7404 --data-dir #{DIR_C} --peers 127.0.0.1:7402,127.0.0.1:7403 --pool-size 4", out: "/dev/null", err: "/dev/null")

sleep 1.0 # Allow nodes to boot and bind TCP ports

begin
  # 3. Connect TCP client to Node A (port 7402) and commit a fact
  puts "\n[Node A] Committing fact 'agent-alpha' to 'swarm_logs'..."
  client_a = MeshTestClient.new("127.0.0.1", 7402)
  fact_a = {
    id: SecureRandom.uuid,
    store: "swarm_logs",
    key: "agent-alpha",
    value: { status: "scouting", zone: "zone-10" },
    value_hash: "abcd" * 16,
    transaction_time: Time.now.to_f,
    valid_time: Time.now.to_f,
    schema_version: 1
  }
  res_a = client_a.send_req(op: "write_fact", fact: fact_a)
  assert(res_a[:ok] == true, "Fact successfully written to Node A")
  client_a.close

  # 4. Connect TCP client to Node B (port 7403) and commit a different fact
  puts "\n[Node B] Committing fact 'agent-beta' to 'swarm_logs'..."
  client_b = MeshTestClient.new("127.0.0.1", 7403)
  fact_b = {
    id: SecureRandom.uuid,
    store: "swarm_logs",
    key: "agent-beta",
    value: { status: "mining", mining_payload: "kryptonite" },
    value_hash: "1234" * 16,
    transaction_time: Time.now.to_f + 0.05,
    valid_time: Time.now.to_f,
    schema_version: 1
  }
  res_b = client_b.send_req(op: "write_fact", fact: fact_b)
  assert(res_b[:ok] == true, "Fact successfully written to Node B")
  client_b.close

  # 5. Let the Gossip background sync cycles run!
  puts "\n[Gossip Anti-Entropy] Waiting 8 seconds for WAL sync propagation cycles..."
  sleep 8.0

  # 6. Connect TCP client to Node C (port 7404)
  # Node C has NEVER received any direct writes from the client!
  puts "\n[Node C] Connecting to Node C (which received 0 direct writes)..."
  client_c = MeshTestClient.new("127.0.0.1", 7404)

  # 7. Query Node C for all facts in the 'swarm_logs' partition!
  res_c = client_c.send_req(op: "facts_for", store: "swarm_logs")
  puts "   Node C Timeline Query Response: #{res_c.inspect}"
  
  facts = res_c[:facts]
  assert(facts != nil, "Node C returned a non-nil timeline array")
  assert_equal(2, facts.size, "Node C successfully gossip-replicated BOTH facts across the P2P mesh cluster!")

  if facts.size == 2
    # Verify values and sorting
    assert_equal("agent-alpha", facts[0][:key], "First replicated fact matches key 'agent-alpha'")
    assert_equal("scouting", facts[0][:value][:status], "First fact status scouting payload is correct")
    assert_equal("agent-beta", facts[1][:key], "Second replicated fact matches key 'agent-beta'")
    assert_equal("mining", facts[1][:value][:status], "Second fact status mining payload is correct")
  end

  # 8. Check dynamic WAL persistent sharding on Node C
  assert(File.exist?("#{DIR_C}/swarm_logs.wal"), "Node C successfully persisted synchronized updates into its own local WAL file on disk!")

  client_c.close
  puts "\n#{BOLD}#{GREEN}🏆 MESH REPLICATION COMPLETED SUCCESSFULLY!#{RESET}\n\n"
rescue => e
  puts "#{RED}Error during mesh cluster test: #{e.message}#{RESET}"
  $failed_tests += 1
ensure
  # 9. Graceful shutdown
  puts "\n[Mesh Shutdown] Terminating background processes gracefully..."
  pids.each do |pid|
    begin
      Process.kill("INT", pid) # SIGINT triggers the ctrlc graceful shutdown flushing WALs
      Process.wait(pid)
    rescue => e
      # Process already closed
    end
  end

  # 10. Clean up directories
  FileUtils.rm_rf(DIR_A)
  FileUtils.rm_rf(DIR_B)
  FileUtils.rm_rf(DIR_C)
end

if $failed_tests == 0
  puts "#{GREEN}🏆 ALL MESH CLUSTER TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Mesh Cluster Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
