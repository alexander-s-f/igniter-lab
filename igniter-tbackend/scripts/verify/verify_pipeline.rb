# frozen_string_literal: true
# verify_pipeline.rb
# Reactive Event-Driven Pipelines, State Combines & ROP Rules Engine Pack Verification Test

require "json"
require "socket"
require "zlib"
require "fileutils"
require "securerandom"
require "webrick"

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
class PipelineTestClient
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

puts "\n#{BOLD}#{CYAN}=== TBACKEND REACTIVE EVENT PIPELINE TEST SUITE ===#{RESET}"

# Setup clean storage data folder
DATA_DIR = "pipeline_data"
FileUtils.rm_rf(DATA_DIR)
FileUtils.mkdir_p(DATA_DIR)

# 1. Spawn a concurrent mock HTTP callback server on port 8080
puts "\n[Mock Server] Spawning mock HTTP server on port 8080..."
received_webhooks = []
mock_server = WEBrick::HTTPServer.new(
  Port: 8080,
  Logger: WEBrick::Log.new(File::NULL),
  AccessLog: []
)
mock_server.mount_proc "/leads" do |req, res|
  received_webhooks << JSON.parse(req.body, symbolize_names: true)
  res.status = 200
  res.body = "OK"
end
mock_thread = Thread.new { mock_server.start }

# 2. Spawn the compiled TBackend standalone daemon on port 7409
puts "\n[TBackend Daemon] Spawning daemon in the background on port 7409..."
daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir #{DATA_DIR} --pool-size 4", out: "/dev/null", err: "/dev/null")
sleep 1.0 # Allow socket to bind

begin
  client = PipelineTestClient.new("127.0.0.1", 7409)

  # Assert server is online
  assert(client.send_req(op: "ping")[:ok] == true, "Daemon connected and pinged successfully")

  # 3. Seed baseline state facts for combined stores
  puts "\n[Seeding] Seeding availabilities and balances state facts..."
  
  # A. availabilities: partner-101 has 15 availability count
  client.send_req(
    op: "write_fact",
    fact: {
      id: SecureRandom.uuid,
      store: "availabilities",
      key: "partner-101",
      value: { count: 15 },
      value_hash: "avail-hash",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )

  # B. balances: partner-101 has 2500 balance amount
  client.send_req(
    op: "write_fact",
    fact: {
      id: SecureRandom.uuid,
      store: "balances",
      key: "partner-101",
      value: { amount: 2500 },
      value_hash: "bal-hash",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )

  # 4. Create a Persistent Pipeline over TCP
  puts "\n[Pipeline Creation] Registering daily reactive persistent business pipeline..."
  res_pipe = client.send_req(
    op: "pipeline_create",
    trigger_store: "lead_signals",
    combines: [
      { store: "availabilities", key_path: "lead_signals.value.partner_id", alias: "avail" },
      { store: "balances", key_path: "lead_signals.value.partner_id", alias: "bal" }
    ],
    rules: [
      { left_path: "lead_signals.value.zip_code", op: "eq", right_val: "91125" },
      { left_path: "avail.value.count", op: "gt", right_val: 10 },
      { left_path: "bal.value.amount", op: "gt", right_val: 1000 }
    ],
    transform_template: {
      lead_id: "{{lead_signals.id}}",
      partner: "{{lead_signals.value.partner_id}}",
      status: "approved",
      stats: {
        avail: "{{avail.value.count}}",
        bal: "{{bal.value.amount}}"
      }
    },
    action_target_store: "approved_leads",
    action_webhook_url: "http://127.0.0.1:8080/leads",
    persist: true
  )

  assert_equal(true, res_pipe[:ok], "Pipeline registered successfully")
  pipeline_id = res_pipe[:pipeline_id]
  assert(pipeline_id.start_with?("pipe_"), "Pipeline ID starts with 'pipe_' prefix: #{pipeline_id}")

  # 5. Assert dynamic file creation
  pipe_file = "#{DATA_DIR}/pipelines/#{pipeline_id}.json"
  assert(File.exist?(pipe_file), "Durable pipeline configuration successfully written to disk: #{pipe_file}")

  # 6. Commit a MATCHING lead signals fact
  puts "\n[Action Write] Committing MATCHING webhook signal..."
  lead_id = SecureRandom.uuid
  client.send_req(
    op: "write_fact",
    fact: {
      id: lead_id,
      store: "lead_signals",
      key: "lead-matching-1",
      value: { partner_id: "partner-101", zip_code: "91125" },
      value_hash: "signal-hash-1",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )

  # Wait for asynchronous out-of-band execution
  puts "\n[Async Dispatch] Waiting 800ms for asynchronous pipeline background dispatch..."
  sleep 0.8

  # Assert transformed fact committed to target storeapproved_leads
  assert_equal(1, client.send_req(op: "size", store: "approved_leads")[:size], "Transformed fact automatically streamed to approved_leads partition!")

  res_stream = client.send_req(op: "facts_for", store: "approved_leads")
  stream_fact = res_stream[:facts].first
  assert_equal(lead_id, stream_fact[:value][:lead_id], "Transformed fact maps triggered lead ID: #{lead_id}")
  assert_equal("partner-101", stream_fact[:value][:partner], "Transformed fact resolves partner_id mapping")
  assert_equal("approved", stream_fact[:value][:status], "Transformed fact includes constant approved status")
  assert_equal(15, stream_fact[:value][:stats][:avail], "Transformed fact correctly resolves combined availability count (15)")
  assert_equal(2500, stream_fact[:value][:stats][:bal], "Transformed fact correctly resolves combined balance amount (2500)")

  # Assert mock server received webhook
  assert_equal(1, received_webhooks.length, "Mock HTTP server successfully captured exactly 1 webhook reaction!")
  webhook_payload = received_webhooks.first
  assert_equal("approved", webhook_payload[:status], "Webhook payload includes template stats status")
  assert_equal(15, webhook_payload[:stats][:avail], "Webhook payload successfully contains bitemporally synchronized availability state")

  # 7. Commit a NON-MATCHING webhook signal (does not match zip_code rule)
  puts "\n[Action Write] Committing NON-MATCHING signal (zip code 90210)..."
  client.send_req(
    op: "write_fact",
    fact: {
      id: SecureRandom.uuid,
      store: "lead_signals",
      key: "lead-nonmatching-1",
      value: { partner_id: "partner-101", zip_code: "90210" },
      value_hash: "signal-hash-2",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )
  sleep 0.5
  assert_equal(1, client.send_req(op: "size", store: "approved_leads")[:size], "Non-matching signals are successfully short-circuited/pruned by rules evaluator!")
  assert_equal(1, received_webhooks.length, "No extra webhooks were dispatched, proving perfect short-circuiting!")

  client.close

  # 8. Restart Daemon to verify boot preload preloading
  puts "\n[TBackend Daemon] Stopping daemon to test persistent pipeline reboot recovery..."
  Process.kill("INT", daemon_pid)
  Process.wait(daemon_pid)

  puts "\n[TBackend Daemon] Rebooting daemon on port 7409 using compacted storage..."
  daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir #{DATA_DIR} --pool-size 4", out: "/dev/null", err: "/dev/null")
  sleep 1.0 # Allow bind

  client2 = PipelineTestClient.new("127.0.0.1", 7409)

  # Check that the preloaded pipeline registry contains the preloaded pipeline
  res_list = client2.send_req(op: "pipeline_list")
  assert_equal(1, res_list[:pipelines].length, "Warm boot preloaded exactly 1 persistent pipeline configuration from storage!")
  assert_equal(pipeline_id, res_list[:pipelines].first[:id], "Loaded pipeline ID matches: #{pipeline_id}")

  # Commit another matching fact to verify preloaded pipeline runs successfully
  puts "\n[Action Write] Committing MATCHING webhook signal against preloaded warm registry..."
  lead_id_2 = SecureRandom.uuid
  client2.send_req(
    op: "write_fact",
    fact: {
      id: lead_id_2,
      store: "lead_signals",
      key: "lead-matching-2",
      value: { partner_id: "partner-101", zip_code: "91125" },
      value_hash: "signal-hash-3",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )
  sleep 0.8

  assert_equal(2, client2.send_req(op: "size", store: "approved_leads")[:size], "Preloaded pipeline successfully triggered out-of-band streaming!")
  assert_equal(2, received_webhooks.length, "Preloaded pipeline successfully dispatched out-of-band webhook response!")

  # 9. Clean up and delete pipeline
  puts "\n[Pipeline Deletion] Deleting pipeline #{pipeline_id} remotely..."
  res_del = client2.send_req(op: "pipeline_delete", pipeline_id: pipeline_id)
  assert_equal(true, res_del[:ok], "Pipeline successfully deleted from registry")
  assert_equal(0, client2.send_req(op: "pipeline_list")[:pipelines].length, "Registry is now empty")
  assert(!File.exist?(pipe_file), "Durable pipeline configuration file successfully erased from disk!")

  client2.close
  puts "\n#{BOLD}#{GREEN}🏆 PIPELINE PACK VERIFICATION COMPLETED SUCCESSFULLY!#{RESET}\n\n"
rescue => e
  puts "#{RED}Error during pipeline test: #{e.message}#{RESET}"
  puts e.backtrace.join("\n")
  $failed_tests += 1
ensure
  # Graceful teardown
  puts "\n[Tear Down] Stopping servers and cleaning up directories..."
  begin
    Process.kill("INT", daemon_pid)
    Process.wait(daemon_pid)
  rescue => e
    # Process already closed
  end
  mock_server.shutdown rescue nil
  mock_thread.join rescue nil
  FileUtils.rm_rf(DATA_DIR)
end

if $failed_tests == 0
  puts "#{GREEN}🏆 ALL PIPELINE TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Pipeline Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
