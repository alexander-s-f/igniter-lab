# frozen_string_literal: true
# verify_auth.rb
# Security, Role-Based Access Control (RBAC), Store Isolation (ACLs) + P9 hash/id token storage.

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

def a_fact(store, key, value)
  {
    id: SecureRandom.uuid,
    store: store,
    key: key,
    value: value,
    value_hash: SecureRandom.hex(8),
    transaction_time: Time.now.to_f,
    valid_time: Time.now.to_f,
    schema_version: 1
  }
end

puts "\n#{BOLD}#{CYAN}=== TBACKEND SECURITY & ACCESS CONTROL TEST SUITE (P9 hash/id storage) ===#{RESET}"

DATA_DIR  = "auth_data"
SEC_DIR   = File.join(DATA_DIR, "security")
HANDOFF   = File.join(SEC_DIR, "BOOTSTRAP_ADMIN_TOKEN")
LOG       = "auth_daemon.log"
PORT      = 7409
AUTH_OFF_DATA_DIR = "auth_off_data"
AUTH_OFF_LOG      = "auth_off_daemon.log"
AUTH_OFF_PORT     = 7410
UNIX      = RUBY_PLATFORM !~ /mswin|mingw/
FileUtils.rm_rf(DATA_DIR)
FileUtils.rm_rf(AUTH_OFF_DATA_DIR)
FileUtils.rm_f(LOG)
FileUtils.rm_f(AUTH_OFF_LOG)
FileUtils.mkdir_p(DATA_DIR)
FileUtils.mkdir_p(AUTH_OFF_DATA_DIR)

def spawn_daemon(mode)
  spawn(
    "./target/release/tbackend --host 127.0.0.1 --port #{PORT} --data-dir #{DATA_DIR} --pool-size 4 --auth-enabled true",
    %i[out err] => [LOG, mode]
  )
end

# 0. Auth disabled — should not create any bootstrap token or security state.
puts "\n[Auth Disabled] Boot with auth off must not mint BOOTSTRAP_ADMIN_TOKEN..."
auth_off_pid = spawn(
  "./target/release/tbackend --host 127.0.0.1 --port #{AUTH_OFF_PORT} --data-dir #{AUTH_OFF_DATA_DIR} --pool-size 4 --auth-enabled false",
  %i[out err] => [AUTH_OFF_LOG, "w"]
)
begin
  sleep 1.0
  auth_off_client = AuthTestClient.new("127.0.0.1", AUTH_OFF_PORT)
  auth_off_ping = auth_off_client.send_req(op: "ping")
  assert_equal(true, auth_off_ping[:ok], "auth-off daemon accepts ping without a token")
  auth_off_client.close
  assert(!File.exist?(File.join(AUTH_OFF_DATA_DIR, "security", "BOOTSTRAP_ADMIN_TOKEN")),
         "auth-off daemon does not write BOOTSTRAP_ADMIN_TOKEN")
  assert(!Dir.exist?(File.join(AUTH_OFF_DATA_DIR, "security")),
         "auth-off daemon does not create security/ token state")
ensure
  begin
    Process.kill("INT", auth_off_pid)
    Process.wait(auth_off_pid)
  rescue
    # already stopped
  end
  FileUtils.rm_rf(AUTH_OFF_DATA_DIR)
  FileUtils.rm_f(AUTH_OFF_LOG)
end

# 1. First persistent boot — should mint a RANDOM bootstrap admin token (no admin_default).
puts "\n[TBackend Daemon] First boot on port #{PORT} (data-dir #{DATA_DIR})..."
daemon_pid = spawn_daemon("w")
sleep 1.0

# Track every plaintext token value the suite ever holds, to prove none of them land on disk / in logs / in lists.
all_token_values = []

begin
  # ── P9 Bootstrap: random one-time admin token via a 0600 handoff file ──────────────────────────────
  puts "\n[P9 Bootstrap] A random admin token must be handed off once; admin_default must be gone..."
  assert(File.exist?(HANDOFF), "bootstrap handoff file #{HANDOFF} exists")
  admin_tok = File.exist?(HANDOFF) ? File.read(HANDOFF).strip : ""
  assert(!admin_tok.empty?, "handoff contains a non-empty bootstrap admin token")
  all_token_values << admin_tok
  assert(admin_tok != "admin_default", "bootstrap token is NOT the retired constant 'admin_default'")
  assert(Dir.glob(File.join(SEC_DIR, "admin_default*")).empty?, "no admin_default* file is written")

  first_boot_files = Dir.glob(File.join(SEC_DIR, "*.json"))
  assert_equal(1, first_boot_files.length, "exactly one persisted token file after first boot")
  assert(first_boot_files.all? { |f| File.basename(f, ".json") =~ /\A[0-9a-f]{64}\z/ },
         "persisted filename is an opaque 64-hex hash, not a token value")
  assert(first_boot_files.none? { |f| File.basename(f, ".json") == admin_tok },
         "persisted filename does NOT equal the bootstrap token value")

  if UNIX
    assert_equal("600", format("%o", File.stat(HANDOFF).mode & 0o777), "handoff file is mode 0600")
    assert_equal("700", format("%o", File.stat(SEC_DIR).mode & 0o777), "security/ dir is mode 0700")
  end

  client = AuthTestClient.new("127.0.0.1", PORT)

  # No token -> rejected.
  puts "\n[Securing Check] ping WITHOUT a token must be rejected..."
  res_no_token = client.send_req(op: "ping")
  assert_equal(false, res_no_token[:ok], "ping without a token is blocked by AuthMiddleware")
  assert(res_no_token[:error].include?("missing 'token' parameter"), "error points to missing token")

  # Bootstrap admin token authenticates.
  puts "\n[Admin Bootstrapping] Authenticating with the handed-off bootstrap token..."
  res_admin_ping = client.send_req(op: "ping", token: admin_tok)
  assert_equal(true, res_admin_ping[:ok], "bootstrap admin token authenticates and pings successfully")

  # Bad token -> rejected.
  res_bad = client.send_req(op: "ping", token: "definitely-not-a-real-token")
  assert_equal(false, res_bad[:ok], "an invalid token is rejected")
  assert(res_bad[:error].include?("invalid token"), "error points to invalid token")

  # ── P9 Create: tokens are generated server-side; legacy target_token is rejected ────────────────────
  puts "\n[P9 Create] auth_token_create generates the bearer token server-side and returns it once..."
  res_legacy = client.send_req(op: "auth_token_create", token: admin_tok, target_token: "i_pick_my_own",
                               target_role: "read_only", allowed_stores: ["lead_signals"], persist: true)
  assert_equal(false, res_legacy[:ok], "caller-supplied target_token is rejected")
  assert(res_legacy[:error].to_s.include?("no longer accepted"), "rejection explains tokens are server-generated")

  def create_token(client, admin_tok, role, stores)
    res = client.send_req(op: "auth_token_create", token: admin_tok,
                          target_role: role, allowed_stores: stores, persist: true)
    assert_equal(true, res[:ok], "auth_token_create(#{role}, #{stores.inspect}) succeeds")
    assert(res[:token].is_a?(String) && !res[:token].empty?, "create returns a one-time generated token")
    assert(res[:id].is_a?(String) && res[:id] =~ /\A[0-9a-f]{16}\z/, "create returns a 16-hex opaque id")
    assert_equal(role, res[:role], "create echoes the role")
    res
  end

  res_w = create_token(client, admin_tok, "write_only", ["lead_signals"])
  res_r = create_token(client, admin_tok, "read_only",  ["lead_signals"])
  res_f = create_token(client, admin_tok, "read_only",  ["financial_ledger"])
  write_tok, write_id = res_w[:token], res_w[:id]
  read_tok            = res_r[:token]
  finance_tok         = res_f[:token]
  all_token_values.push(write_tok, read_tok, finance_tok)

  # ── P9 Storage proof: no token material in filenames or file bodies ─────────────────────────────────
  puts "\n[P9 Storage] persisted filenames + bodies must never contain a bearer token value..."
  token_files = Dir.glob(File.join(SEC_DIR, "*.json"))
  assert(token_files.length >= 4, "all four tokens persisted (#{token_files.length} files)")
  assert(token_files.all? { |f| File.basename(f, ".json") =~ /\A[0-9a-f]{64}\z/ },
         "every persisted filename is a 64-hex hash")
  bad_name = token_files.select { |f| all_token_values.include?(File.basename(f, ".json")) }
  assert(bad_name.empty?, "no persisted filename equals a bearer token value")
  bodies = token_files.map { |f| File.read(f) }
  leaked = all_token_values.select { |t| bodies.any? { |b| b.include?(t) } }
  assert(leaked.empty?, "no persisted file body contains a bearer token value (#{leaked.length} leaks)")
  parsed = bodies.map { |b| JSON.parse(b) }
  assert(parsed.all? { |h| h.key?("token_hash") && !h.key?("token") },
         "persisted bodies carry token_hash, never a plaintext token field")

  if UNIX
    assert_equal("700", format("%o", File.stat(SEC_DIR).mode & 0o777), "security/ remains 0700")
    bad_perm = token_files.reject { |f| (File.stat(f).mode & 0o777) == 0o600 }
    assert(bad_perm.empty?, "all token JSON files are mode 0600 (#{bad_perm.length} not 0600)")
  end

  # ── P9 List: id + metadata only; no token, no full hash ─────────────────────────────────────────────
  puts "\n[P9 List] auth_token_list returns id/metadata only..."
  res_list = client.send_req(op: "auth_token_list", token: admin_tok)
  assert_equal(true, res_list[:ok], "auth_token_list succeeds for admin")
  list = res_list[:tokens] || []
  assert_equal(4, res_list[:count], "list count is 4 (admin + 3 created)")
  assert_equal(res_list[:count], list.length, "count matches number of entries")
  assert(list.all? { |t| t.key?(:id) && t.key?(:role) && t.key?(:allowed_stores) && t.key?(:persist) },
         "each entry carries id/role/allowed_stores/persist")
  assert(list.all? { |t| t[:id].to_s =~ /\A[0-9a-f]{16}\z/ }, "each entry id is a 16-hex opaque id")
  bad_keys = list.flat_map(&:keys).map(&:to_s) & %w[token token_hash target_token]
  assert(bad_keys.empty?, "list entries expose no token/token_hash keys (found: #{bad_keys.inspect})")
  list_json = res_list.to_json
  leaked_in_list = all_token_values.select { |t| list_json.include?(t) }
  assert(leaked_in_list.empty?, "no bearer token value appears in the list response")
  assert(list_json !~ /[0-9a-f]{64}/, "no full 64-hex hash appears in the list response")

  # ── RBAC / ACL enforcement (using the generated tokens) ─────────────────────────────────────────────
  puts "\n[RBAC/ACL] write_only token restrictions..."
  res_w_ok = client.send_req(op: "write_fact", token: write_tok, fact: a_fact("lead_signals", "lead-1", { vendor: "eLocal" }))
  assert_equal(true, res_w_ok[:ok], "write token writes to whitelisted store 'lead_signals'")
  res_w_bad = client.send_req(op: "write_fact", token: write_tok, fact: a_fact("financial_ledger", "tx-101", { amount: 500 }))
  assert_equal(false, res_w_bad[:ok], "write token blocked from non-whitelisted store 'financial_ledger'")
  assert(res_w_bad[:error].include?("not authorized for store"), "error details store ACL violation")
  res_w_read = client.send_req(op: "latest_for", token: write_tok, store: "lead_signals", key: "lead-1")
  assert_equal(false, res_w_read[:ok], "write token blocked from read ops (RBAC)")
  assert(res_w_read[:error].include?("role 'write_only' cannot execute"), "error details RBAC role violation")

  puts "\n[RBAC/ACL] read_only token restrictions..."
  res_r_ok = client.send_req(op: "latest_for", token: read_tok, store: "lead_signals", key: "lead-1")
  assert_equal(true, res_r_ok[:ok], "read token reads whitelisted store 'lead_signals'")
  res_r_bad = client.send_req(op: "latest_for", token: read_tok, store: "financial_ledger", key: "tx-101")
  assert_equal(false, res_r_bad[:ok], "read token blocked from non-whitelisted store 'financial_ledger'")
  res_r_write = client.send_req(op: "write_fact", token: read_tok, fact: a_fact("lead_signals", "lead-2", { vendor: "eLocal" }))
  assert_equal(false, res_r_write[:ok], "read token blocked from writing facts (RBAC)")

  puts "\n[RBAC/ACL] finance token store isolation..."
  client.send_req(op: "write_fact", token: admin_tok, fact: a_fact("financial_ledger", "tx-101", { amount: 5000 }))
  res_f_ok = client.send_req(op: "latest_for", token: finance_tok, store: "financial_ledger", key: "tx-101")
  assert_equal(true, res_f_ok[:ok], "finance token reads whitelisted store 'financial_ledger'")
  assert_equal(5000, res_f_ok[:fact][:value][:amount], "finance token reads the correct value")
  res_f_bad = client.send_req(op: "latest_for", token: finance_tok, store: "lead_signals", key: "lead-1")
  assert_equal(false, res_f_bad[:ok], "finance token blocked from non-whitelisted store 'lead_signals'")

  client.close

  # ── Restart: reload by hash/id + legacy fail-closed ─────────────────────────────────────────────────
  puts "\n[TBackend Daemon] Stopping to test restart reload..."
  Process.kill("INT", daemon_pid)
  Process.wait(daemon_pid)

  # Inject a LEGACY plaintext token file (old P6A/P8 format) while the daemon is down.
  legacy_plain = "legacy_plaintext_admin"
  all_token_values << legacy_plain
  File.write(File.join(SEC_DIR, "legacymock.json"),
             JSON.pretty_generate("token" => legacy_plain, "role" => "admin", "allowed_stores" => ["*"], "persist" => true))

  puts "\n[TBackend Daemon] Rebooting; new-format tokens must reload, legacy plaintext must be refused..."
  daemon_pid = spawn_daemon("a")
  sleep 1.0
  client2 = AuthTestClient.new("127.0.0.1", PORT)

  puts "\n[Warm Boot] generated tokens still authenticate after restart (reload by hash)..."
  res_reboot_w = client2.send_req(op: "write_fact", token: write_tok, fact: a_fact("lead_signals", "lead-3", { vendor: "eLocal" }))
  assert_equal(true, res_reboot_w[:ok], "reloaded write token writes whitelisted store on boot")
  res_reboot_w_bad = client2.send_req(op: "write_fact", token: write_tok, fact: a_fact("financial_ledger", "tx-102", { amount: 1000 }))
  assert_equal(false, res_reboot_w_bad[:ok], "reloaded write token still blocked from non-whitelisted store")
  res_admin_after = client2.send_req(op: "ping", token: admin_tok)
  assert_equal(true, res_admin_after[:ok], "reloaded bootstrap admin token still authenticates")

  puts "\n[Legacy Fail-Closed] an old plaintext token file must NOT be accepted as a credential..."
  res_legacy_login = client2.send_req(op: "ping", token: legacy_plain)
  assert_equal(false, res_legacy_login[:ok], "legacy plaintext token is rejected after reboot")
  assert(res_legacy_login[:error].to_s.include?("invalid token"), "legacy token yields 'invalid token'")

  # ── Delete by id + last-admin guard ─────────────────────────────────────────────────────────────────
  puts "\n[P9 Delete] delete by opaque id removes the persisted file..."
  res_del = client2.send_req(op: "auth_token_delete", token: admin_tok, target_id: write_id)
  assert_equal(true, res_del[:ok], "auth_token_delete(target_id) succeeds")
  assert(Dir.glob(File.join(SEC_DIR, "*.json")).none? { |f| File.basename(f).start_with?(write_id) },
         "the deleted token's persisted file is gone")
  res_w_deleted = client2.send_req(op: "write_fact", token: write_tok, fact: a_fact("lead_signals", "lead-4", { vendor: "eLocal" }))
  assert_equal(false, res_w_deleted[:ok], "the deleted token is rejected on subsequent use")
  assert(res_w_deleted[:error].include?("invalid token"), "deleted token yields 'invalid token'")

  puts "\n[P9 Last-Admin Guard] deleting the final admin must be refused..."
  res_list2 = client2.send_req(op: "auth_token_list", token: admin_tok)
  admin_entry = (res_list2[:tokens] || []).find { |t| t[:role] == "admin" }
  assert(!admin_entry.nil?, "exactly one admin remains in the registry")
  admin_count = (res_list2[:tokens] || []).count { |t| t[:role] == "admin" }
  assert_equal(1, admin_count, "there is a single admin (last-admin condition holds)")
  res_del_admin = client2.send_req(op: "auth_token_delete", token: admin_tok, target_id: admin_entry[:id])
  assert_equal(false, res_del_admin[:ok], "deleting the last admin is refused")
  assert(res_del_admin[:error].to_s.include?("last remaining admin"), "refusal cites the last-admin guard")
  res_admin_alive = client2.send_req(op: "ping", token: admin_tok)
  assert_equal(true, res_admin_alive[:ok], "admin token still works after the refused deletion")

  client2.close
  puts "\n#{BOLD}#{GREEN}🏆 P9 STORAGE-HARDENING VERIFICATION COMPLETED!#{RESET}\n"
rescue => e
  puts "#{RED}Error during auth test: #{e.message}#{RESET}"
  puts e.backtrace.join("\n")
  $failed_tests += 1
ensure
  puts "\n[Tear Down] Stopping daemon and scanning logs for token leakage..."
  begin
    Process.kill("INT", daemon_pid)
    Process.wait(daemon_pid)
  rescue
    # already stopped
  end

  # ── Audit: no bearer token value may appear in daemon logs ──────────────────────────────────────────
  if File.exist?(LOG)
    log_text = File.read(LOG)
    leaked_log = all_token_values.reject(&:empty?).select { |t| log_text.include?(t) }
    assert(leaked_log.empty?, "no bearer token value appears in daemon logs (#{leaked_log.length} leaks)")
  end

  FileUtils.rm_rf(DATA_DIR)
  FileUtils.rm_f(LOG)
end

if $failed_tests == 0
  puts "#{GREEN}🏆 ALL SECURITY TESTS PASSED!#{RESET}\n"
  exit(0)
else
  puts "#{RED}✘ Security Test Suite failed with #{$failed_tests} failure(s).#{RESET}\n"
  exit(1)
end
