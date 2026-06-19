# frozen_string_literal: true
# Proof: stdlib/io/network FFI Surface Contract
# Card: LAB-STDLIB-NET-P3
# No real TCP sockets. In-memory stub only.

require_relative '../lib/network_ffi_stub'
require 'json'
require 'pathname'

FIXTURE_DIR_FFI = Pathname.new(__FILE__).dirname.parent / 'fixtures' / 'network_capability'

# ═══════════════════════════════════════════════════════════════════════════════
# Result tracking helpers
# ═══════════════════════════════════════════════════════════════════════════════

$ffi_results = []

def ffi_pass(group, check)
  $ffi_results << { status: 'PASS', group: group, check: check }
  print '.'
end

def ffi_fail(group, check, detail = nil)
  $ffi_results << { status: 'FAIL', group: group, check: check, detail: detail }
  print 'F'
end

def ffi_assert(group, check, condition, detail = nil)
  if condition
    ffi_pass(group, check)
  else
    ffi_fail(group, check, detail || 'expected true, got false')
  end
end

def ffi_assert_err(group, check, json_str, expected_error_type: nil, expected_code: nil)
  parsed = JSON.parse(json_str)
  is_err = parsed.key?('err')
  type_ok = expected_error_type.nil? || parsed.dig('err', 'error_type') == expected_error_type
  code_ok = expected_code.nil? || parsed.dig('err', 'code') == expected_code

  if is_err && type_ok && code_ok
    ffi_pass(group, check)
  else
    detail = "expected err"
    detail += " error_type=#{expected_error_type}" if expected_error_type
    detail += " code=#{expected_code}" if expected_code
    detail += "; got #{json_str[0, 120]}"
    ffi_fail(group, check, detail)
  end
end

# ═══════════════════════════════════════════════════════════════════════════════
# Load fixtures
# ═══════════════════════════════════════════════════════════════════════════════

var_a_cap = JSON.parse((FIXTURE_DIR_FFI / 'variant_a_loopback_connect.json').read(encoding: 'UTF-8'))
var_b_cap = JSON.parse((FIXTURE_DIR_FFI / 'variant_b_localhost_listen.json').read(encoding: 'UTF-8'))
var_c_cap = JSON.parse((FIXTURE_DIR_FFI / 'variant_c_https_outbound.json').read(encoding: 'UTF-8'))

var_a_json = JSON.generate(var_a_cap)
var_b_json = JSON.generate(var_b_cap)
var_c_json = JSON.generate(var_c_cap)

# ═══════════════════════════════════════════════════════════════════════════════
# NET-FFI-* — FFI surface method existence checks
# ═══════════════════════════════════════════════════════════════════════════════

ffi_assert('NET-FFI', 'NET-FFI-1', NetworkFFIStub.respond_to?(:stdlib_io_network_connect),
           'NetworkFFIStub must respond to stdlib_io_network_connect')

ffi_assert('NET-FFI', 'NET-FFI-2', NetworkFFIStub.respond_to?(:stdlib_io_network_listen),
           'NetworkFFIStub must respond to stdlib_io_network_listen')

ffi_assert('NET-FFI', 'NET-FFI-3', NetworkFFIStub.respond_to?(:stdlib_io_network_accept),
           'NetworkFFIStub must respond to stdlib_io_network_accept')

ffi_assert('NET-FFI', 'NET-FFI-4', NetworkFFIStub.respond_to?(:stdlib_io_network_send),
           'NetworkFFIStub must respond to stdlib_io_network_send')

ffi_assert('NET-FFI', 'NET-FFI-5', NetworkFFIStub.respond_to?(:stdlib_io_network_receive),
           'NetworkFFIStub must respond to stdlib_io_network_receive')

ffi_assert('NET-FFI', 'NET-FFI-6', NetworkFFIStub.respond_to?(:stdlib_io_network_close),
           'NetworkFFIStub must respond to stdlib_io_network_close')

# NET-FFI-7: All return values are valid JSON strings
NetworkFFIStub.reset!
ret_connect = NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '8080', var_a_json)
ffi_assert('NET-FFI', 'NET-FFI-7',
           begin; JSON.parse(ret_connect); true; rescue; false; end,
           "connect result must be valid JSON: #{ret_connect[0,80]}")

# NET-FFI-8: All return values are either {"ok": ...} or {"err": ...}
parsed_connect = JSON.parse(ret_connect)
ffi_assert('NET-FFI', 'NET-FFI-8',
           parsed_connect.key?('ok') || parsed_connect.key?('err'),
           "result must have 'ok' or 'err' top-level key, got #{parsed_connect.keys.inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# NET-CONN-* — Connect lifecycle checks
# ═══════════════════════════════════════════════════════════════════════════════

NetworkFFIStub.reset!

# NET-CONN-1: connect("127.0.0.1", "8080", cap_json) → ok with ConnectReceipt
result = JSON.parse(NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '8080', var_a_json))
ffi_assert('NET-CONN', 'NET-CONN-1a', result.key?('ok'), "expected ok, got #{result.inspect[0,100]}")
ffi_assert('NET-CONN', 'NET-CONN-1b',
           result.dig('ok', 'connection_id').is_a?(String) && !result.dig('ok', 'connection_id').to_s.empty?,
           "connection_id must be non-empty string")
ffi_assert('NET-CONN', 'NET-CONN-1c', result.dig('ok', 'host') == '127.0.0.1',
           "host must be 127.0.0.1, got #{result.dig('ok', 'host').inspect}")
ffi_assert('NET-CONN', 'NET-CONN-1d', result.dig('ok', 'port') == 8080,
           "port must be 8080, got #{result.dig('ok', 'port').inspect}")
ffi_assert('NET-CONN', 'NET-CONN-1e', result.dig('ok', 'stub_mode') == true,
           "stub_mode must be true")
ffi_assert('NET-CONN', 'NET-CONN-1f', result.dig('ok', 'capability_id') == var_a_cap['capability_id'],
           "capability_id mismatch")
ffi_assert('NET-CONN', 'NET-CONN-1g', result.dig('ok', 'timestamp').is_a?(Integer),
           "timestamp must be an integer")

conn_id = result.dig('ok', 'connection_id')

# NET-CONN-2: After connect, connection_id is in NetworkFFIStub::CONNECTIONS
ffi_assert('NET-CONN', 'NET-CONN-2',
           NetworkFFIStub::CONNECTIONS.key?(conn_id),
           "conn_id #{conn_id.inspect} must be in CONNECTIONS registry")

# NET-CONN-3: send → ok with SendReceipt
send_result = JSON.parse(NetworkFFIStub.stdlib_io_network_send(conn_id, 'hello igniter', var_a_json))
ffi_assert('NET-CONN', 'NET-CONN-3a', send_result.key?('ok'), "send expected ok, got #{send_result.inspect[0,100]}")
ffi_assert('NET-CONN', 'NET-CONN-3b', send_result.dig('ok', 'bytes_sent') == 'hello igniter'.bytesize,
           "bytes_sent must be #{' hello igniter'.bytesize}, got #{send_result.dig('ok', 'bytes_sent').inspect}")
ffi_assert('NET-CONN', 'NET-CONN-3c', send_result.dig('ok', 'stub_mode') == true,
           "stub_mode must be true in send receipt")

# NET-CONN-4: receive → ok with ReceiveObservation
recv_result = JSON.parse(NetworkFFIStub.stdlib_io_network_receive(conn_id, '1024', var_a_json))
ffi_assert('NET-CONN', 'NET-CONN-4a', recv_result.key?('ok'), "receive expected ok, got #{recv_result.inspect[0,100]}")
ffi_assert('NET-CONN', 'NET-CONN-4b', recv_result.dig('ok', 'data').is_a?(String),
           "data must be a string")
ffi_assert('NET-CONN', 'NET-CONN-4c',
           recv_result.dig('ok', 'bytes_received').is_a?(Integer) && recv_result.dig('ok', 'bytes_received') <= 1024,
           "bytes_received must be integer <= 1024")
ffi_assert('NET-CONN', 'NET-CONN-4d', recv_result.dig('ok', 'stub_mode') == true,
           "stub_mode must be true in receive observation")

# NET-CONN-5: close → ok with CloseReceipt
close_result = JSON.parse(NetworkFFIStub.stdlib_io_network_close(conn_id, var_a_json))
ffi_assert('NET-CONN', 'NET-CONN-5a', close_result.key?('ok'), "close expected ok, got #{close_result.inspect[0,100]}")
ffi_assert('NET-CONN', 'NET-CONN-5b', close_result.dig('ok', 'connection_id') == conn_id,
           "connection_id in CloseReceipt must match")
ffi_assert('NET-CONN', 'NET-CONN-5c', close_result.dig('ok', 'stub_mode') == true,
           "stub_mode must be true in close receipt")

# NET-CONN-6: After close, send on closed connection → err ConnectionNotFound
send_after_close = JSON.parse(NetworkFFIStub.stdlib_io_network_send(conn_id, 'data', var_a_json))
ffi_assert('NET-CONN', 'NET-CONN-6',
           send_after_close.key?('err'),
           "send after close must return err, got #{send_after_close.inspect[0,100]}")

# ═══════════════════════════════════════════════════════════════════════════════
# NET-LISTEN-* — Listen lifecycle checks
# ═══════════════════════════════════════════════════════════════════════════════

NetworkFFIStub.reset!

# NET-LISTEN-1: listen → ok with ListenReceipt
listen_result = JSON.parse(NetworkFFIStub.stdlib_io_network_listen('127.0.0.1', '4000', var_b_json))
ffi_assert('NET-LISTEN', 'NET-LISTEN-1a', listen_result.key?('ok'),
           "listen expected ok, got #{listen_result.inspect[0,100]}")
ffi_assert('NET-LISTEN', 'NET-LISTEN-1b',
           listen_result.dig('ok', 'listener_id').is_a?(String) && !listen_result.dig('ok', 'listener_id').to_s.empty?,
           "listener_id must be non-empty string")
ffi_assert('NET-LISTEN', 'NET-LISTEN-1c', listen_result.dig('ok', 'port') == 4000,
           "port must be 4000, got #{listen_result.dig('ok', 'port').inspect}")
ffi_assert('NET-LISTEN', 'NET-LISTEN-1d', listen_result.dig('ok', 'stub_mode') == true,
           "stub_mode must be true in ListenReceipt")

listener_id = listen_result.dig('ok', 'listener_id')

# NET-LISTEN-2: listener_id is in NetworkFFIStub::LISTENERS
ffi_assert('NET-LISTEN', 'NET-LISTEN-2',
           NetworkFFIStub::LISTENERS.key?(listener_id),
           "listener_id #{listener_id.inspect} must be in LISTENERS registry")

# NET-LISTEN-3: accept → ok with AcceptReceipt
accept_result = JSON.parse(NetworkFFIStub.stdlib_io_network_accept(listener_id, var_b_json))
ffi_assert('NET-LISTEN', 'NET-LISTEN-3a', accept_result.key?('ok'),
           "accept expected ok, got #{accept_result.inspect[0,100]}")
ffi_assert('NET-LISTEN', 'NET-LISTEN-3b',
           accept_result.dig('ok', 'connection_id').is_a?(String) && !accept_result.dig('ok', 'connection_id').to_s.empty?,
           "accepted connection_id must be non-empty string")
ffi_assert('NET-LISTEN', 'NET-LISTEN-3c', accept_result.dig('ok', 'listener_id') == listener_id,
           "listener_id in AcceptReceipt must match")
ffi_assert('NET-LISTEN', 'NET-LISTEN-3d', accept_result.dig('ok', 'peer_address') == '127.0.0.1',
           "stub peer_address must be 127.0.0.1")
ffi_assert('NET-LISTEN', 'NET-LISTEN-3e', accept_result.dig('ok', 'stub_mode') == true,
           "stub_mode must be true in AcceptReceipt")

# ═══════════════════════════════════════════════════════════════════════════════
# NET-FFI-POLICY-* — Policy enforcement at FFI boundary
# ═══════════════════════════════════════════════════════════════════════════════

NetworkFFIStub.reset!

# NET-FFI-POLICY-1: connect to external host → NET-1 E-NET-LOOPBACK-VIOLATION
ffi_assert_err('NET-FFI-POLICY', 'NET-FFI-POLICY-1',
               NetworkFFIStub.stdlib_io_network_connect('10.0.0.1', '8080', var_a_json),
               expected_code: 'E-NET-LOOPBACK-VIOLATION')

# NET-FFI-POLICY-2: connect to non-loopback RFC1918 host → NET-1 fires first (loopback_only=true)
ffi_assert_err('NET-FFI-POLICY', 'NET-FFI-POLICY-2',
               NetworkFFIStub.stdlib_io_network_connect('192.168.1.1', '8080', var_a_json),
               expected_code: 'E-NET-LOOPBACK-VIOLATION')

# NET-FFI-POLICY-3: connect to blocked port → NET-3 E-NET-PORT-BLOCKED
ffi_assert_err('NET-FFI-POLICY', 'NET-FFI-POLICY-3',
               NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '80', var_a_json),
               expected_code: 'E-NET-PORT-BLOCKED')

# NET-FFI-POLICY-4: listen attempt with connect-only cap → NET-4 E-NET-DIRECTION-BLOCKED
ffi_assert_err('NET-FFI-POLICY', 'NET-FFI-POLICY-4',
               NetworkFFIStub.stdlib_io_network_listen('127.0.0.1', '4000', var_a_json),
               expected_code: 'E-NET-DIRECTION-BLOCKED')

# NET-FFI-POLICY-5: variant_c has tls_required:true → stub refuses with StubModeError
ffi_assert_err('NET-FFI-POLICY', 'NET-FFI-POLICY-5',
               NetworkFFIStub.stdlib_io_network_connect('api.example.com', '443', var_c_json),
               expected_error_type: 'StubModeError')

# NET-FFI-POLICY-6: malformed cap JSON → InvalidJson
ffi_assert_err('NET-FFI-POLICY', 'NET-FFI-POLICY-6',
               NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '8080', 'not valid json'),
               expected_error_type: 'InvalidJson')

# NET-FFI-POLICY-7: wrong resource_type (file cap) → CapabilityError schema invalid
file_cap = {
  'capability_id' => 'cap-file-01',
  'resource_type' => 'file',
  'sandbox_dir'   => 'out/sandbox',
  'allowed_absolute_paths' => [],
  'read_allowed'  => true,
  'write_allowed' => false
}
ffi_assert_err('NET-FFI-POLICY', 'NET-FFI-POLICY-7',
               NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '8080', JSON.generate(file_cap)),
               expected_error_type: 'CapabilityError')

# ═══════════════════════════════════════════════════════════════════════════════
# NET-FFI-REGISTRY-* — Registry isolation checks
# ═══════════════════════════════════════════════════════════════════════════════

NetworkFFIStub.reset!

# NET-FFI-REGISTRY-1: unknown conn_id to send → ConnectionNotFound
ffi_assert_err('NET-FFI-REGISTRY', 'NET-FFI-REGISTRY-1',
               NetworkFFIStub.stdlib_io_network_send('unknown-conn-id', 'data', var_a_json),
               expected_error_type: 'ConnectionNotFound')

# NET-FFI-REGISTRY-2: unknown conn_id to receive → ConnectionNotFound
ffi_assert_err('NET-FFI-REGISTRY', 'NET-FFI-REGISTRY-2',
               NetworkFFIStub.stdlib_io_network_receive('unknown-conn-id', '512', var_a_json),
               expected_error_type: 'ConnectionNotFound')

# NET-FFI-REGISTRY-3: unknown conn_id to close → ConnectionNotFound
ffi_assert_err('NET-FFI-REGISTRY', 'NET-FFI-REGISTRY-3',
               NetworkFFIStub.stdlib_io_network_close('unknown-conn-id', var_a_json),
               expected_error_type: 'ConnectionNotFound')

# NET-FFI-REGISTRY-4: unknown listener_id to accept → ListenerNotFound
ffi_assert_err('NET-FFI-REGISTRY', 'NET-FFI-REGISTRY-4',
               NetworkFFIStub.stdlib_io_network_accept('unknown-listener-id', var_b_json),
               expected_error_type: 'ListenerNotFound')

# NET-FFI-REGISTRY-5: reset! clears all connections and listeners
NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '8080', var_a_json)
NetworkFFIStub.stdlib_io_network_listen('127.0.0.1', '4000', var_b_json)
NetworkFFIStub.reset!
ffi_assert('NET-FFI-REGISTRY', 'NET-FFI-REGISTRY-5',
           NetworkFFIStub::CONNECTIONS.empty? && NetworkFFIStub::LISTENERS.empty?,
           "After reset!, CONNECTIONS and LISTENERS must both be empty")

# ═══════════════════════════════════════════════════════════════════════════════
# NET-FFI-GUARD-* — No-real-network assertions
# ═══════════════════════════════════════════════════════════════════════════════

# NET-FFI-GUARD-1: stub source file does not USE real network APIs (non-comment lines only)
# Scan uses split string literals so the check itself does not trigger on its own source.
_g1_tcp  = 'TCP' + 'Socket'
_g1_udp  = 'UDP' + 'Socket'
_g1_sock = "require 'sock" + "et'"
_g1_http = "require 'net/" + "http'"
stub_source = File.read(File.expand_path('../lib/network_ffi_stub.rb', __dir__), encoding: 'UTF-8')
stub_non_comment_lines = stub_source.each_line.reject { |l| l.strip.start_with?('#') }.join
guard1_clean = [_g1_tcp, _g1_udp, _g1_sock, _g1_http].none? { |tok| stub_non_comment_lines.include?(tok) }
ffi_assert('NET-FFI-GUARD', 'NET-FFI-GUARD-1', guard1_clean,
           'network_ffi_stub.rb must not USE real socket/network APIs in non-comment code')

# NET-FFI-GUARD-2: stub_mode: true present in ALL ok receipts
NetworkFFIStub.reset!
guard2_cap = var_a_json
guard2_conn_str = NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '9090', guard2_cap)
guard2_conn = JSON.parse(guard2_conn_str)
guard2_conn_id = guard2_conn.dig('ok', 'connection_id')

guard2_send   = JSON.parse(NetworkFFIStub.stdlib_io_network_send(guard2_conn_id, 'ping', guard2_cap))
guard2_recv   = JSON.parse(NetworkFFIStub.stdlib_io_network_receive(guard2_conn_id, '64', guard2_cap))
guard2_close  = JSON.parse(NetworkFFIStub.stdlib_io_network_close(guard2_conn_id, guard2_cap))

guard2_listen_str = NetworkFFIStub.stdlib_io_network_listen('127.0.0.1', '5000', var_b_json)
guard2_listen     = JSON.parse(guard2_listen_str)
guard2_lid        = guard2_listen.dig('ok', 'listener_id')
guard2_accept     = JSON.parse(NetworkFFIStub.stdlib_io_network_accept(guard2_lid, var_b_json))

all_stub_mode = [guard2_conn, guard2_send, guard2_recv, guard2_close, guard2_listen, guard2_accept].all? do |r|
  r.dig('ok', 'stub_mode') == true
end
ffi_assert('NET-FFI-GUARD', 'NET-FFI-GUARD-2', all_stub_mode,
           "Every ok receipt in the lifecycle must carry stub_mode: true")

# NET-FFI-GUARD-3: proof runner itself does not USE real network APIs (non-comment lines only)
# Scan uses split string literals to avoid triggering the check on its own source.
_tcp  = 'TCP' + 'Socket'
_udp  = 'UDP' + 'Socket'
_sock = "require 'sock" + "et'"
_http = "require 'net/" + "http'"
proof_source = File.read(__FILE__, encoding: 'UTF-8')
proof_non_comment_lines = proof_source.each_line.reject { |l| l.strip.start_with?('#') }.join
guard3_clean = [_tcp, _udp, _sock, _http].none? { |tok| proof_non_comment_lines.include?(tok) }
ffi_assert('NET-FFI-GUARD', 'NET-FFI-GUARD-3', guard3_clean,
           'Proof runner must not USE real socket/network APIs in non-comment code')

# ═══════════════════════════════════════════════════════════════════════════════
# NET-FFI-C-* — Variant C specific checks
# ═══════════════════════════════════════════════════════════════════════════════

NetworkFFIStub.reset!

# NET-FFI-C-1: Variant C with tls_required:true → stub returns StubModeError
ffi_assert_err('NET-FFI-C', 'NET-FFI-C-1',
               NetworkFFIStub.stdlib_io_network_connect('api.example.com', '443', var_c_json),
               expected_error_type: 'StubModeError')

# NET-FFI-C-2: Variant C with host not in allowlist → E-NET-HOST-BLOCKED
# (variant_c has loopback_only:false so NET-1 passes, then tls check fires first...
#  but actually tls check happens before host check in our impl — so we get StubModeError)
# The spec says: loopback=false passes NET-1, then NET-2 host blocked for evil.com
# Since tls_required fires before NET-1/NET-2, we get StubModeError first.
# This is correct behavior: stub refuses tls_required caps entirely.
# We verify we get an error (any error type) — the meaningful assertion is err returned.
result_c2 = JSON.parse(NetworkFFIStub.stdlib_io_network_connect('evil.com', '443', var_c_json))
ffi_assert('NET-FFI-C', 'NET-FFI-C-2', result_c2.key?('err'),
           "connect with var_c to evil.com must return err (tls_required fires first or host blocked)")

# NET-FFI-C-3: Variant C connect to wrong port → since tls_required fires first, we get StubModeError
# To test E-NET-PORT-BLOCKED for variant_c shape without tls, build a tls=false variant_c:
var_c_no_tls = var_c_cap.merge('tls_required' => false)
var_c_no_tls_json = JSON.generate(var_c_no_tls)
ffi_assert_err('NET-FFI-C', 'NET-FFI-C-3',
               NetworkFFIStub.stdlib_io_network_connect('api.example.com', '80', var_c_no_tls_json),
               expected_code: 'E-NET-PORT-BLOCKED')

# NET-FFI-C-4 (bonus): Variant C no-tls + host not in allowlist → E-NET-HOST-BLOCKED
ffi_assert_err('NET-FFI-C', 'NET-FFI-C-4',
               NetworkFFIStub.stdlib_io_network_connect('evil.com', '443', var_c_no_tls_json),
               expected_code: 'E-NET-HOST-BLOCKED')

# ═══════════════════════════════════════════════════════════════════════════════
# Additional lifecycle coherence checks (NET-EXTRA-*)
# ═══════════════════════════════════════════════════════════════════════════════

NetworkFFIStub.reset!

# NET-EXTRA-1: Accepted connection stored in CONNECTIONS registry
listen2_str = NetworkFFIStub.stdlib_io_network_listen('127.0.0.1', '7000', var_b_json)
listen2      = JSON.parse(listen2_str)
lid2         = listen2.dig('ok', 'listener_id')
accept2      = JSON.parse(NetworkFFIStub.stdlib_io_network_accept(lid2, var_b_json))
accepted_conn_id = accept2.dig('ok', 'connection_id')
ffi_assert('NET-EXTRA', 'NET-EXTRA-1',
           NetworkFFIStub::CONNECTIONS.key?(accepted_conn_id),
           "Accepted conn_id must be stored in CONNECTIONS registry")

# NET-EXTRA-2: Close marks connection as not open (CONNECTIONS entry persists but open=false)
NetworkFFIStub.reset!
conn3_str = NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '8888', var_a_json)
conn3_id  = JSON.parse(conn3_str).dig('ok', 'connection_id')
NetworkFFIStub.stdlib_io_network_close(conn3_id, var_a_json)
ffi_assert('NET-EXTRA', 'NET-EXTRA-2',
           NetworkFFIStub::CONNECTIONS.key?(conn3_id) && !NetworkFFIStub::CONNECTIONS[conn3_id]['open'],
           "After close, connection entry must exist but open must be false")

# NET-EXTRA-3: receive after close → ConnectionNotFound
recv_after_close = JSON.parse(NetworkFFIStub.stdlib_io_network_receive(conn3_id, '100', var_a_json))
ffi_assert('NET-EXTRA', 'NET-EXTRA-3',
           recv_after_close.key?('err'),
           "receive after close must return err")

# NET-EXTRA-4: Two simultaneous connections have distinct IDs
NetworkFFIStub.reset!
c4a = JSON.parse(NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '8001', var_a_json)).dig('ok', 'connection_id')
c4b = JSON.parse(NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '8002', var_a_json)).dig('ok', 'connection_id')
ffi_assert('NET-EXTRA', 'NET-EXTRA-4', c4a != c4b,
           "Each connect call must produce a distinct connection_id")

# NET-EXTRA-5: connect returns JSON parseable by JSON.parse (envelope shape)
NetworkFFIStub.reset!
raw5 = NetworkFFIStub.stdlib_io_network_connect('127.0.0.1', '9999', var_a_json)
parsed5 = JSON.parse(raw5)
ffi_assert('NET-EXTRA', 'NET-EXTRA-5',
           parsed5.keys.sort == ['ok'] || parsed5.keys.sort == ['err'],
           "Result must have exactly one top-level key: 'ok' or 'err', got #{parsed5.keys.inspect}")

# ═══════════════════════════════════════════════════════════════════════════════
# Print Results Matrix
# ═══════════════════════════════════════════════════════════════════════════════

puts "\n"
puts '=' * 76
puts 'NetworkFFI Proof — Results Matrix (LAB-STDLIB-NET-P3)'
puts '=' * 76

col_group  = 20
col_check  = 24
col_status = 6

header = "  #{'GROUP'.ljust(col_group)} #{'CHECK'.ljust(col_check)} STATUS"
puts header
puts '-' * 76

current_group = nil
$ffi_results.each do |r|
  if r[:group] != current_group
    puts '' if current_group
    current_group = r[:group]
  end
  status_str = r[:status]
  line = "  #{r[:group].to_s.ljust(col_group)} #{r[:check].to_s.ljust(col_check)} #{status_str}"
  puts line
  puts "    Detail: #{r[:detail]}" if r[:detail] && r[:status] == 'FAIL'
end

puts '-' * 76

total   = $ffi_results.size
passing = $ffi_results.count { |r| r[:status] == 'PASS' }
failing = $ffi_results.count { |r| r[:status] == 'FAIL' }

puts "Total: #{total}  |  PASS: #{passing}  |  FAIL: #{failing}"
puts '=' * 76

if failing.zero?
  puts 'Result: ALL CHECKS PASSED'
  exit 0
else
  puts "Result: #{failing} CHECK(S) FAILED"
  exit 1
end
