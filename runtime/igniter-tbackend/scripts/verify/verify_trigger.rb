# frozen_string_literal: true
# verify_trigger.rb
# Dynamic Triggers & Asynchronous Webhook Dispatch Verification Test

require "json"
require "socket"
require "zlib"
require "securerandom"
require "webrick"

# ANSI text styling
GREEN   = "\e[32m"
RED     = "\e[31m"
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

# TCP client helper
class TriggerTestClient
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

puts "\n#{BOLD}#{CYAN}=== DISTRIBUTED DYNAMIC TRIGGERS TEST SUITE ===#{RESET}"

# 1. Spawn a concurrent Mock HTTP server using Ruby WEBrick on port 8080
puts "\n[Mock Server] Spawning mock HTTP server on port 8080..."
captured_payloads = []
mock_server = WEBrick::HTTPServer.new(
  Port: 8080,
  Logger: WEBrick::Log.new(File::NULL),
  AccessLog: []
)
mock_server.mount_proc "/callback" do |req, res|
  captured_payloads << JSON.parse(req.body, symbolize_names: true)
  res.status = 200
  res.body = "OK"
end
Thread.new { mock_server.start }

# 2. Spawn the compiled TBackend standalone daemon on port 7409 in ephemeral mode
puts "[TBackend Daemon] Spawning daemon in the background on port 7409..."
daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir nil --pool-size 4", out: "/dev/null", err: "/dev/null")
sleep 1.0 # Allow socket to bind

begin
  client = TriggerTestClient.new("127.0.0.1", 7409)

  # 3. Register a Dynamic Trigger
  puts "\n[Triggers] Registering trigger for store 'webhook_test' with key prefix 'events-'..."
  res_trig = client.send_req(
    op: "trigger_create",
    store: "webhook_test",
    key_prefix: "events-",
    webhook_url: "http://127.0.0.1:8080/callback"
  )
  assert(res_trig[:ok] == true, "Trigger successfully created remotely")
  assert(res_trig[:trigger_id].to_s.start_with?("trig_"), "Trigger ID starts with 'trig_' prefix")

  # 4. Verify trigger list
  res_list = client.send_req(op: "trigger_list")
  assert_equal(1, res_list[:triggers].size, "Trigger registry contains exactly 1 active trigger")

  # 5. Commit matching bitemporal fact (key matches prefix 'events-')
  puts "\n[Write Action] Committing MATCHING fact 'events-signup'..."
  fact_match = {
    id: SecureRandom.uuid,
    store: "webhook_test",
    key: "events-signup",
    value: { user_id: 123, email: "match@dev.com" },
    value_hash: "abcd" * 16,
    transaction_time: Time.now.to_f,
    valid_time: Time.now.to_f,
    schema_version: 1
  }
  start_time = Time.now
  res_write1 = client.send_req(op: "write_fact", fact: fact_match)
  write_latency = Time.now - start_time
  assert(res_write1[:ok] == true, "Matching fact committed successfully")
  puts "   Write latency: #{(write_latency * 1000).round(2)} ms"

  # 6. Commit non-matching bitemporal fact (key prefix 'other-')
  puts "\n[Write Action] Committing NON-MATCHING fact 'other-login'..."
  fact_non_match = {
    id: SecureRandom.uuid,
    store: "webhook_test",
    key: "other-login",
    value: { user_id: 456, email: "nonmatch@dev.com" },
    value_hash: "1234" * 16,
    transaction_time: Time.now.to_f,
    valid_time: Time.now.to_f,
    schema_version: 1
  }
  res_write2 = client.send_req(op: "write_fact", fact: fact_non_match)
  assert(res_write2[:ok] == true, "Non-matching fact committed successfully")

  # 7. Sleep for 500ms to allow async out-of-band webhook dispatch
  puts "\n[Async Verification] Waiting 500ms for asynchronous dispatch thread..."
  sleep 0.5

  # 8. Assertions
  assert_equal(1, captured_payloads.size, "Mock HTTP callback server received EXACTLY 1 POST request!")
  
  if captured_payloads.size == 1
    payload = captured_payloads.first
    assert_equal("events-signup", payload[:key], "Replicated fact key matches 'events-signup'")
    assert_equal(123, payload[:value][:user_id], "Replicated nested user_id is correct")
  end

  # 9. Verify delete trigger
  puts "\n[Triggers] Deleting trigger #{res_trig[:trigger_id]}..."
  res_del = client.send_req(op: "trigger_delete", trigger_id: res_trig[:trigger_id])
  assert(res_del[:ok] == true, "Trigger successfully deleted from registry")
  
  res_list2 = client.send_req(op: "trigger_list")
  assert_equal(0, res_list2[:triggers].size, "Trigger registry is now empty")

  client.close
  puts "\n#{BOLD}#{GREEN}🏆 TRIGGERS VERIFICATION COMPLETED SUCCESSFULLY!#{RESET}\n\n"
rescue => e
  puts "#{RED}Error during triggers test: #{e.message}#{RESET}"
  $failed_tests += 1
ensure
  # 10. Tear down servers
  puts "\n[Tear Down] Stopping servers gracefully..."
  mock_server.shutdown rescue nil
  begin
    Process.kill("INT", daemon_pid)
    Process.wait(daemon_pid)
  rescue => e
    # Process already closed
  end
end

if $failed_tests == 0
  puts "#{GREEN}🏆 ALL TRIGGERS TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Triggers Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
