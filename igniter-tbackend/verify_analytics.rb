# frozen_string_literal: true
# verify_analytics.rb
# Bitemporal Timeline Slicing, Grouped Aggregations, Time-Series Calculations & Metrics Verification Test

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

def assert_in_delta(expected, actual, delta = 0.001, msg = "Assertion failed")
  if (expected - actual).abs <= delta
    puts "  #{GREEN}✔ PASS:#{RESET} #{msg} (Value: #{actual.round(4)})"
  else
    puts "  #{RED}✘ FAIL:#{RESET} #{msg} - Expected: #{expected} (delta: #{delta}), Got: #{actual}"
    $failed_tests += 1
  end
end

# TCP client helper
class AnalyticsTestClient
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

puts "\n#{BOLD}#{CYAN}=== TBACKEND BITEMPORAL ANALYTICS TEST SUITE ===#{RESET}"

# 1. Spawn the compiled TBackend standalone daemon on port 7409 in ephemeral mode
puts "\n[TBackend Daemon] Spawning daemon in the background on port 7409..."
daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir nil --pool-size 4", out: "/dev/null", err: "/dev/null")
sleep 1.0 # Allow socket to bind

begin
  client = AnalyticsTestClient.new("127.0.0.1", 7409)

  # Assert server is online
  assert(client.send_req(op: "ping")[:ok] == true, "Daemon connected and pinged successfully")

  # 2. Seed data
  puts "\n[Seeding] Committing bitemporal transaction facts for trades..."
  
  trades = [
    { key: "trade-1", value: { category: "crypto", price: 50000.0, volume: 1.5, producer: "node-A" } },
    { key: "trade-2", value: { category: "forex", price: 1.12, volume: 10000.0, producer: "node-B" } },
    { key: "trade-3", value: { category: "crypto", price: 60000.0, volume: 2.0, producer: "node-A" } },
    { key: "trade-4", value: { category: "forex", price: 1.15, volume: 5000.0, producer: "node-A" } }
  ]

  trades.each do |trade|
    fact = {
      id: SecureRandom.uuid,
      store: "analytics_test",
      key: trade[:key],
      value: trade[:value],
      value_hash: "a" * 64,
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
    client.send_req(op: "write_fact", fact: fact)
    sleep 0.05
  end

  # 3. Verify query_slice
  puts "\n[Query Slice] Verifying timeline slices..."
  
  # Slice with prefix and filter
  res_slice1 = client.send_req(
    op: "query_slice",
    store: "analytics_test",
    key_prefix: "trade-",
    filters: { producer: "node-A" }
  )
  assert_equal(true, res_slice1[:ok], "Slice request completed successfully")
  assert_equal(3, res_slice1[:facts].size, "Sliced segment contains exactly 3 facts matching 'producer: node-A'")

  # Slice with category filter
  res_slice2 = client.send_req(
    op: "query_slice",
    store: "analytics_test",
    filters: { category: "forex" }
  )
  assert_equal(2, res_slice2[:facts].size, "Sliced segment contains exactly 2 facts matching 'category: forex'")

  # 4. Verify analytics_aggregate (Grouped Aggregations)
  puts "\n[Analytics Aggregate] Verifying grouped aggregations..."
  
  res_agg = client.send_req(
    op: "analytics_aggregate",
    store: "analytics_test",
    group_by: "value.category",
    aggregates: [
      { field: "value.price", op: "avg" },
      { field: "value.volume", op: "sum" },
      { field: "", op: "count" }
    ]
  )
  assert_equal(true, res_agg[:ok], "Grouped aggregation completed successfully")
  assert_equal(2, res_agg[:results].size, "Aggregate returns exactly 2 groups (crypto and forex)")

  # Find groups
  crypto_group = res_agg[:results].find { |r| r[:group_value] == "crypto" }
  forex_group  = res_agg[:results].find { |r| r[:group_value] == "forex" }

  assert(crypto_group != nil, "Crypto group exists")
  assert(forex_group != nil, "Forex group exists")

  if crypto_group
    # Crypto: price: 50000 & 60000 -> avg: 55000; volume: 1.5 & 2.0 -> sum: 3.5; count: 2
    assert_in_delta(55000.0, crypto_group[:aggregates][:"avg_value.price"], 0.01, "Crypto avg price is correct")
    assert_in_delta(3.5, crypto_group[:aggregates][:"sum_value.volume"], 0.01, "Crypto sum volume is correct")
    assert_equal(2.0, crypto_group[:aggregates][:count_fact], "Crypto fact count is correct")
  end

  if forex_group
    # Forex: price: 1.12 & 1.15 -> avg: 1.135; volume: 10000 & 5000 -> sum: 15000; count: 2
    assert_in_delta(1.135, forex_group[:aggregates][:"avg_value.price"], 0.001, "Forex avg price is correct")
    assert_in_delta(15000.0, forex_group[:aggregates][:"sum_value.volume"], 0.01, "Forex sum volume is correct")
    assert_equal(2.0, forex_group[:aggregates][:count_fact], "Forex fact count is correct")
  end

  # 5. Verify analytics_calculate (Time-Series Window calculations)
  puts "\n[Analytics Calculate] Verifying bitemporal time-series calculations..."
  
  # Seed sequential versions for a single key to build deep timeline
  puts "   Seeding 5 sequential versions of 'trade-1'..."
  prices = [100.0, 110.0, 120.0, 130.0, 140.0]
  prices.each do |price|
    fact = {
      id: SecureRandom.uuid,
      store: "analytics_test",
      key: "trade-1",
      value: { category: "crypto", price: price, volume: 1.0, producer: "node-A" },
      value_hash: "hash-" + price.to_s,
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
    client.send_req(op: "write_fact", fact: fact)
    sleep 0.02
  end

  # Calculate moving average (SMA) with window 3
  res_calc_sma = client.send_req(
    op: "analytics_calculate",
    store: "analytics_test",
    key: "trade-1",
    field: "value.price",
    calculation: "sma",
    window_size: 3
  )
  assert_equal(true, res_calc_sma[:ok], "Moving average query completed successfully")
  
  # Raw facts for trade-1 include the initial seed (50000.0) + 5 updates
  # Total of 6 data points.
  # Values in history: [50000.0, 100.0, 110.0, 120.0, 130.0, 140.0]
  series = res_calc_sma[:series]
  assert_equal(6, series.size, "Calculated timeline series contains exactly 6 data points")

  # Last point calculated value should be SMA(120, 130, 140) = 130.0
  last_point = series.last
  assert_in_delta(130.0, last_point[:calculated_value], 0.01, "SMA over window 3 on last point is correct")
  assert_in_delta(140.0, last_point[:raw_value], 0.01, "Raw value on last point is correct")

  # Calculate variance / stddev
  res_calc_std = client.send_req(
    op: "analytics_calculate",
    store: "analytics_test",
    key: "trade-1",
    field: "value.price",
    calculation: "stddev"
  )
  # Values history: [50000.0, 100.0, 110.0, 120.0, 130.0, 140.0]
  # Let's verify standard deviation calculation on last point
  assert_equal(true, res_calc_std[:ok], "Standard deviation query completed successfully")
  puts "   Calculated Standard Deviation on last version: #{res_calc_std[:series].last[:calculated_value].round(2)}"
  assert(res_calc_std[:series].last[:calculated_value] > 0.0, "StdDev is positive and non-zero")

  # 6. Verify dynamic pushdown rules filters (New Feature)
  puts "\n[Rules Pushdown] Verifying native server-side ROP rules filtration..."
  
  res_rules = client.send_req(
    op: "query_slice",
    store: "analytics_test",
    rules: [
      { left_path: "value.category", op: "eq", right_val: "crypto" },
      { left_path: "value.price", op: "gt", right_val: 100.0 },
      { left_path: "value.price", op: "lt", right_val: 55000.0 }
    ]
  )
  assert_equal(true, res_rules[:ok], "Rules pushdown slice query completed successfully")
  # Expected matches: trade-1 (initial: 50000.0) + trade-1 updates (110.0, 120.0, 130.0, 140.0) = 5 facts
  assert_equal(5, res_rules[:facts].size, "Rules pushdown filter returns exactly 5 matched facts directly from the database!")

  # 7. Verify analytics_metrics (Partition Diagnostics)
  puts "\n[Analytics Metrics] Verifying partition diagnostic metrics..."
  
  res_metrics = client.send_req(
    op: "analytics_metrics",
    store: "analytics_test"
  )
  assert_equal(true, res_metrics[:ok], "Metrics query completed successfully")
  
  metrics = res_metrics[:stores][:analytics_test]
  assert(metrics != nil, "Analytics metrics for 'analytics_test' partition exists")
  if metrics
    assert_equal(9, metrics[:total_facts], "Total facts in partition is exactly 9 (4 initial trades + 5 updates)")
    assert_equal(4, metrics[:unique_keys], "Total unique keys in partition is exactly 4")
    assert_equal(2.25, metrics[:avg_versions_per_key], "Average versions per key is exactly 2.25")
    assert_equal(6, metrics[:max_versions_per_key], "Max version depth for 'trade-1' key is exactly 6")
    assert(metrics[:size_bytes] > 0, "Store estimated size is reported correctly")
  end

  client.close
  puts "\n#{BOLD}#{GREEN}🏆 ANALYTICS PACK VERIFICATION COMPLETED SUCCESSFULLY!#{RESET}\n\n"
rescue => e
  puts "#{RED}Error during analytics test: #{e.message}#{RESET}"
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
  puts "#{GREEN}🏆 ALL ANALYTICS TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Analytics Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
