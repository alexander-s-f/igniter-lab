# frozen_string_literal: true
# verify_auth.rb
# Security, Role-Based Access Control (RBAC) & Store Isolation (ACLs) Pack Verification Test

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
class AuthTestClient
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

puts "\n#{BOLD}#{CYAN}=== TBACKEND SECURITY & ACCESS CONTROL TEST SUITE ===#{RESET}"

# Setup clean storage data folder
DATA_DIR = "auth_data"
FileUtils.rm_rf(DATA_DIR)
FileUtils.mkdir_p(DATA_DIR)

# 1. Spawn the compiled TBackend standalone daemon on port 7409 pointing to auth_data/
puts "\n[TBackend Daemon] Spawning daemon in the background on port 7409..."
daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir #{DATA_DIR} --pool-size 4 --auth-enabled true", out: "/dev/null", err: "/dev/null")
sleep 1.0 # Allow socket to bind

begin
  client = AuthTestClient.new("127.0.0.1", 7409)

  # 2. Assert connection WITHOUT a token is rejected immediately!
  puts "\n[Securing Check] Attempting to ping the server WITHOUT a token..."
  res_no_token = client.send_req(op: "ping")
  assert_equal(false, res_no_token[:ok], "Connection WITHOUT a token is successfully blocked by AuthMiddleware!")
  assert(res_no_token[:error].include?("missing 'token' parameter"), "Error message points to missing token: #{res_no_token[:error]}")

  # 3. Assert default preloaded token "admin_default" works
  puts "\n[Admin Bootstrapping] Authenticating using default preloaded token 'admin_default'..."
  res_admin_ping = client.send_req(op: "ping", token: "admin_default")
  assert_equal(true, res_admin_ping[:ok], "Default admin_default token authenticates and executes successfully!")

  # 4. Register whitelisted tokens for RBAC & ACL checks
  puts "\n[RBAC Configuration] Registering three tokens with different roles and whitelists..."
  
  # A. write_token: write_only role, restricted to "lead_signals"
  res_w = client.send_req(
    op: "auth_token_create",
    token: "admin_default",
    target_token: "write_token",
    target_role: "write_only",
    allowed_stores: ["lead_signals"],
    persist: true
  )
  assert_equal(true, res_w[:ok], "Token 'write_token' successfully created")

  # B. read_token: read_only role, restricted to "lead_signals"
  res_r = client.send_req(
    op: "auth_token_create",
    token: "admin_default",
    target_token: "read_token",
    target_role: "read_only",
    allowed_stores: ["lead_signals"],
    persist: true
  )
  assert_equal(true, res_r[:ok], "Token 'read_token' successfully created")

  # C. finance_token: read_only role, restricted to "financial_ledger"
  res_f = client.send_req(
    op: "auth_token_create",
    token: "admin_default",
    target_token: "finance_token",
    target_role: "read_only",
    allowed_stores: ["financial_ledger"],
    persist: true
  )
  assert_equal(true, res_f[:ok], "Token 'finance_token' successfully created")

  # ── LAB-TBACKEND-AUTH-REDACTION-P8: redacted listing + token-file permissions ──────────────────────
  puts "\n[P8 Redaction] auth_token_list must return metadata only, never token values..."
  res_list = client.send_req(op: "auth_token_list", token: "admin_default")
  assert_equal(true, res_list[:ok], "auth_token_list succeeds for admin")
  list = res_list[:tokens] || []
  assert(res_list[:count] == list.length && list.length >= 4, "auth_token_list returns a count and all tokens (>=4): #{res_list[:count]}")
  # No token material in any entry: no :token / :token_hash / :id / :target_token keys.
  bad_keys = list.flat_map(&:keys).map(&:to_s) & %w[token token_hash id target_token]
  assert(bad_keys.empty?, "list entries expose no token/hash/id keys (found: #{bad_keys.inspect})")
  # Metadata IS present.
  assert(list.all? { |t| t.key?(:role) && t.key?(:allowed_stores) && t.key?(:persist) }, "list entries carry role/allowed_stores/persist")
  # Known bearer token strings must not appear anywhere in the serialized list response.
  list_json = res_list.to_json
  %w[admin_default write_token read_token finance_token].each do |tok|
    assert(!list_json.include?(tok), "bearer token '#{tok[0,4]}…' does NOT appear in the list response")
  end

  puts "\n[P8 Permissions] security dir must be 0700; token files must be 0600 (Unix)..."
  if RUBY_PLATFORM !~ /mswin|mingw/
    sec_dir = File.join(DATA_DIR, "security")
    dir_mode = format("%o", File.stat(sec_dir).mode & 0o777)
    assert_equal("700", dir_mode, "#{sec_dir} is mode 0700")
    token_files = Dir.glob(File.join(sec_dir, "*.json"))
    assert(!token_files.empty?, "persisted token files exist")
    bad_perm = token_files.reject { |f| (File.stat(f).mode & 0o777) == 0o600 }
    assert(bad_perm.empty?, "all token JSON files are mode 0600 (#{bad_perm.length} not 0600)")
  else
    puts "  (skipped on non-Unix)"
  end

  # 5. Assert RBAC & ACL enforcement checks
  puts "\n[RBAC/ACL Enforcement] Auditing write_token restrictions..."
  
  # Write matching store -> SUCCESS
  res_w_ok = client.send_req(
    op: "write_fact",
    token: "write_token",
    fact: {
      id: SecureRandom.uuid,
      store: "lead_signals",
      key: "lead-1",
      value: { vendor: "eLocal" },
      value_hash: "hash-1",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )
  assert_equal(true, res_w_ok[:ok], "write_token successfully writes to whitelisted store 'lead_signals'!")

  # Write non-matching store -> BLOCKED (ACL violation!)
  res_w_bad_store = client.send_req(
    op: "write_fact",
    token: "write_token",
    fact: {
      id: SecureRandom.uuid,
      store: "financial_ledger",
      key: "tx-101",
      value: { amount: 500 },
      value_hash: "hash-2",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )
  assert_equal(false, res_w_bad_store[:ok], "write_token is successfully blocked from writing to non-whitelisted store 'financial_ledger'!")
  assert(res_w_bad_store[:error].include?("not authorized for store"), "Error details store ACL violation: #{res_w_bad_store[:error]}")

  # Read matching store using write_token -> BLOCKED (RBAC role violation!)
  res_w_read = client.send_req(op: "latest_for", token: "write_token", store: "lead_signals", key: "lead-1")
  assert_equal(false, res_w_read[:ok], "write_token is successfully blocked from executing read commands!")
  assert(res_w_read[:error].include?("role 'write_only' cannot execute"), "Error details RBAC role violation: #{res_w_read[:error]}")

  puts "\n[RBAC/ACL Enforcement] Auditing read_token restrictions..."

  # Read matching store -> SUCCESS
  res_r_ok = client.send_req(op: "latest_for", token: "read_token", store: "lead_signals", key: "lead-1")
  assert_equal(true, res_r_ok[:ok], "read_token successfully reads whitelisted store 'lead_signals'!")

  # Read non-matching store -> BLOCKED (ACL violation!)
  res_r_bad_store = client.send_req(op: "latest_for", token: "read_token", store: "financial_ledger", key: "tx-101")
  assert_equal(false, res_r_bad_store[:ok], "read_token is successfully blocked from reading non-whitelisted store 'financial_ledger'!")

  # Write matching store using read_token -> BLOCKED (RBAC role violation!)
  res_r_write = client.send_req(
    op: "write_fact",
    token: "read_token",
    fact: {
      id: SecureRandom.uuid,
      store: "lead_signals",
      key: "lead-2",
      value: { vendor: "eLocal" },
      value_hash: "hash-3",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )
  assert_equal(false, res_r_write[:ok], "read_token is successfully blocked from writing facts!")

  puts "\n[RBAC/ACL Enforcement] Auditing finance_token restrictions..."

  # Seed a financial record using admin token first
  client.send_req(
    op: "write_fact",
    token: "admin_default",
    fact: {
      id: SecureRandom.uuid,
      store: "financial_ledger",
      key: "tx-101",
      value: { amount: 5000 },
      value_hash: "hash-4",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )

  # Read whitelisted financial_ledger -> SUCCESS
  res_f_ok = client.send_req(op: "latest_for", token: "finance_token", store: "financial_ledger", key: "tx-101")
  assert_equal(true, res_f_ok[:ok], "finance_token successfully reads whitelisted store 'financial_ledger'!")
  assert_equal(5000, res_f_ok[:fact][:value][:amount], "finance_token successfully reads correct financial value!")

  # Read non-whitelisted lead_signals -> BLOCKED (ACL violation!)
  res_f_bad_store = client.send_req(op: "latest_for", token: "finance_token", store: "lead_signals", key: "lead-1")
  assert_equal(false, res_f_bad_store[:ok], "finance_token is successfully blocked from reading non-whitelisted store 'lead_signals'!")

  client.close

  # 6. Restart Daemon to verify boot preload preloading
  puts "\n[TBackend Daemon] Stopping daemon to test persistent token reboot recovery..."
  Process.kill("INT", daemon_pid)
  Process.wait(daemon_pid)

  puts "\n[TBackend Daemon] Rebooting daemon on port 7409 using compacted storage..."
  daemon_pid = spawn("./target/release/tbackend --host 127.0.0.1 --port 7409 --data-dir #{DATA_DIR} --pool-size 4 --auth-enabled true", out: "/dev/null", err: "/dev/null")
  sleep 1.0 # Allow bind

  client2 = AuthTestClient.new("127.0.0.1", 7409)

  # Check that the tokens are preloaded on reboot and maintain their RBAC/ACL whitelists
  puts "\n[Warm Boot Verification] Testing preloaded write_token permissions..."
  res_reboot_w = client2.send_req(
    op: "write_fact",
    token: "write_token",
    fact: {
      id: SecureRandom.uuid,
      store: "lead_signals",
      key: "lead-3",
      value: { vendor: "eLocal" },
      value_hash: "hash-5",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )
  assert_equal(true, res_reboot_w[:ok], "Preloaded write_token successfully writes whitelisted stores on boot!")

  res_reboot_w_bad = client2.send_req(
    op: "write_fact",
    token: "write_token",
    fact: {
      id: SecureRandom.uuid,
      store: "financial_ledger",
      key: "tx-102",
      value: { amount: 1000 },
      value_hash: "hash-6",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )
  assert_equal(false, res_reboot_w_bad[:ok], "Preloaded write_token remains blocked from writing non-whitelisted stores!")

  # 7. Clean up and delete token
  puts "\n[Token Deletion] Deleting token write_token remotely..."
  res_del = client2.send_req(op: "auth_token_delete", token: "admin_default", target_token: "write_token")
  assert_equal(true, res_del[:ok], "Token write_token successfully deleted from registry")

  # Verify deleted token is rejected
  res_w_deleted = client2.send_req(
    op: "write_fact",
    token: "write_token",
    fact: {
      id: SecureRandom.uuid,
      store: "lead_signals",
      key: "lead-4",
      value: { vendor: "eLocal" },
      value_hash: "hash-7",
      transaction_time: Time.now.to_f,
      valid_time: Time.now.to_f,
      schema_version: 1
    }
  )
  assert_equal(false, res_w_deleted[:ok], "Subsequent writes using deleted token are rejected immediately!")
  assert(res_w_deleted[:error].include?("invalid token"), "Error message points to invalid token: #{res_w_deleted[:error]}")

  client2.close
  puts "\n#{BOLD}#{GREEN}🏆 SECURITY & ACCESS CONTROL PACK VERIFICATION COMPLETED SUCCESSFULLY!#{RESET}\n\n"
rescue => e
  puts "#{RED}Error during auth test: #{e.message}#{RESET}"
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
  FileUtils.rm_rf(DATA_DIR)
end

if $failed_tests == 0
  puts "#{GREEN}🏆 ALL SECURITY TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Security Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
