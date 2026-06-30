# frozen_string_literal: true
# verify_cross_store.rb
# Bitemporally Synchronized Cross-Store Time Travel & Relational Joins Verification Test

require "json"
require "socket"
require "zlib"
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
class CrossStoreTestClient
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

puts "\n#{BOLD}#{CYAN}=== TBACKEND CROSS-STORE RELATIONAL TEST SUITE ===#{RESET}"

# 1. Spawn the compiled TBackend standalone daemon on port 7409 in ephemeral mode
puts "\n[TBackend Daemon] Spawning daemon in the background on port 7409..."
daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir nil --pool-size 4", out: "/dev/null", err: "/dev/null")
sleep 1.0 # Allow socket to bind

begin
  client = CrossStoreTestClient.new("127.0.0.1", 7409)

  # Assert server is online
  assert(client.send_req(op: "ping")[:ok] == true, "Daemon connected and pinged successfully")

  # 2. Seed data
  puts "\n[Seeding] Committing bitemporal transaction facts for orders and agents..."
  
  orders = [
    { key: "order-101", value: { item: "Raspberry Pi 5", agent_ref: "agent-alpha" } },
    { key: "order-102", value: { item: "ESP32-S3", agent_ref: "agent-beta" } },
    { key: "order-103", value: { item: "IMU Sensor", agent_ref: "agent-unknown" } }
  ]

  agents = [
    { key: "agent-alpha", value: { name: "Swarm Scout", zone: "A" } },
    { key: "agent-beta", value: { name: "Swarm Mining", zone: "B" } }
  ]

  orders.each do |order|
    fact = {
      id: SecureRandom.uuid,
      store: "orders",
      key: order[:key],
      value: order[:value],
      value_hash: "o" * 64,
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
    client.send_req(op: "write_fact", fact: fact)
    sleep 0.02
  end

  agents.each do |agent|
    fact = {
      id: SecureRandom.uuid,
      store: "agents",
      key: agent[:key],
      value: agent[:value],
      value_hash: "a" * 64,
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
    client.send_req(op: "write_fact", fact: fact)
    sleep 0.02
  end

  # Store pre-update timestamp for time-travel verification
  time_pre_update = Time.now.to_f
  sleep 0.05

  # 3. Verify cross_store_query (Synchronous Multi-Store Time-Travel)
  puts "\n[Cross-Store Query] Verifying synchronous time travel lookups..."
  
  res_query = client.send_req(
    op: "cross_store_query",
    stores: ["orders", "agents"],
    keys: ["order-101", "agent-alpha"]
  )
  assert_equal(true, res_query[:ok], "Cross-store query completed successfully")
  
  order_retrieved = res_query[:results][:orders][:"order-101"]
  agent_retrieved = res_query[:results][:agents][:"agent-alpha"]
  
  assert(order_retrieved != nil, "Retrieved order record from 'orders' partition")
  assert_equal("Raspberry Pi 5", order_retrieved[:value][:item], "Retrieved order item matches seeded value")
  assert(agent_retrieved != nil, "Retrieved agent record from 'agents' partition")
  assert_equal("Swarm Scout", agent_retrieved[:value][:name], "Retrieved agent name matches seeded value")

  # 4. Verify cross_store_join (Inner Join)
  puts "\n[Cross-Store Join] Verifying temporal Inner Join..."
  
  res_join_inner = client.send_req(
    op: "cross_store_join",
    left_store: "orders",
    right_store: "agents",
    join_field: "value.agent_ref",
    right_key: "key",
    join_type: "inner"
  )
  assert_equal(true, res_join_inner[:ok], "Inner join completed successfully")
  
  results_inner = res_join_inner[:results]
  assert_equal(2, results_inner.size, "Inner join returned exactly 2 matched rows (excluding order-103 with unknown agent)")
  
  # Assert order-101 joined with agent-alpha
  pair_alpha = results_inner.find { |r| r[:left][:key] == "order-101" }
  assert(pair_alpha != nil, "Found joined record for order-101")
  if pair_alpha
    assert_equal("agent-alpha", pair_alpha[:right][:key], "Joined right key matches 'agent-alpha'")
    assert_equal("Swarm Scout", pair_alpha[:right][:value][:name], "Joined agent name matches 'Swarm Scout'")
  end

  # 5. Verify cross_store_join (Left Join)
  puts "\n[Cross-Store Join] Verifying temporal Left Join..."
  
  res_join_left = client.send_req(
    op: "cross_store_join",
    left_store: "orders",
    right_store: "agents",
    join_field: "value.agent_ref",
    right_key: "key",
    join_type: "left"
  )
  assert_equal(true, res_join_left[:ok], "Left join completed successfully")
  
  results_left = res_join_left[:results]
  assert_equal(3, results_left.size, "Left join returned exactly 3 rows (including unmatched order-103)")
  
  pair_unknown = results_left.find { |r| r[:left][:key] == "order-103" }
  assert(pair_unknown != nil, "Found row for order-103 in left join")
  if pair_unknown
    assert_equal(nil, pair_unknown[:right], "Right side of unmatched order is null as expected")
  end

  # 6. Verify Bitemporal Time Travel Joins
  puts "\n[Time-Travel Join] Verifying temporal coordinate consistency..."
  
  # Update agent-alpha name
  puts "   Modifying agent-alpha name to 'New Scout'..."
  fact_update = {
    id: SecureRandom.uuid,
    store: "agents",
    key: "agent-alpha",
    value: { name: "New Scout", zone: "A" },
    value_hash: "update-hash",
    transaction_time: Time.now.to_f,
    valid_time: Time.now.to_f,
    schema_version: 1
  }
  client.send_req(op: "write_fact", fact: fact_update)
  sleep 0.05

  # Run join at PRESENT time (should return New Scout)
  puts "   Executing left join at PRESENT bitemporal coordinate..."
  res_present = client.send_req(
    op: "cross_store_join",
    left_store: "orders",
    right_store: "agents",
    join_field: "value.agent_ref",
    right_key: "key",
    join_type: "inner"
  )
  pair_alpha_present = res_present[:results].find { |r| r[:left][:key] == "order-101" }
  assert_equal("New Scout", pair_alpha_present[:right][:value][:name], "Present time join returns updated agent name 'New Scout'")

  # Run join at historical time travel boundary (should return Swarm Scout)
  puts "   Executing left join time-travelling to AS-OF #{Time.at(time_pre_update).strftime('%H:%M:%S.%L')}..."
  res_historical = client.send_req(
    op: "cross_store_join",
    left_store: "orders",
    right_store: "agents",
    join_field: "value.agent_ref",
    right_key: "key",
    join_type: "inner",
    as_of: time_pre_update
  )
  pair_alpha_hist = res_historical[:results].find { |r| r[:left][:key] == "order-101" }
  assert_equal("Swarm Scout", pair_alpha_hist[:right][:value][:name], "Historical time travel join successfully rolls back state, returning old agent name 'Swarm Scout'!")

  client.close
  puts "\n#{BOLD}#{GREEN}🏆 CROSS-STORE PACK VERIFICATION COMPLETED SUCCESSFULLY!#{RESET}\n\n"
rescue => e
  puts "#{RED}Error during cross-store test: #{e.message}#{RESET}"
  puts e.backtrace.join("\n")
  $failed_tests += 1
ensure
  # 7. Tear down daemon gracefully
  puts "\n[Tear Down] Stopping daemon gracefully..."
  begin
    Process.kill("INT", daemon_pid)
    Process.wait(daemon_pid)
  rescue => e
    # Process already closed
  end
end

if $failed_tests == 0
  puts "#{GREEN}🏆 ALL CROSS-STORE TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Cross-Store Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
