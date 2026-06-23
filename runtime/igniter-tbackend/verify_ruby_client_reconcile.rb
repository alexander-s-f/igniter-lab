# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "socket"
require "timeout"
require "zlib"
require_relative "tbackend_client"

HOST = "127.0.0.1"
PORT = 7422
DATA_DIR = "ruby_client_reconcile_data"
LOG_PATH = "ruby_client_reconcile_daemon.log"
BINARY = "./target/release/tbackend"
$failed = 0

def assert(condition, message)
  if condition
    puts "PASS: #{message}"
  else
    $failed += 1
    puts "FAIL: #{message}"
  end
end

def value_hash(value)
  Zlib.crc32(JSON.generate(value.sort.to_h)).to_s
end

def make_fact(store, key, payload = "p16")
  now = Time.now.to_f
  value = { "payload" => payload, "key" => key }
  {
    "id" => SecureRandom.uuid,
    "store" => store,
    "key" => key,
    "value" => value,
    "value_hash" => value_hash(value),
    "transaction_time" => now,
    "valid_time" => now,
    "schema_version" => 1
  }
end

def conflict_variant(fact)
  variant = fact.dup
  variant["value"] = { "payload" => "conflict", "key" => fact["key"] }
  variant["value_hash"] = value_hash(variant["value"])
  variant
end

def encode_frame(req)
  body = JSON.generate(req).b
  [body.bytesize].pack("N") + body + [Zlib.crc32(body)].pack("N")
end

def read_exact(socket, bytes)
  data = +"".b
  while data.bytesize < bytes
    chunk = socket.read(bytes - data.bytesize)
    raise EOFError, "socket closed" if chunk.nil? || chunk.empty?

    data << chunk
  end
  data
end

def decode_frame(socket)
  header = read_exact(socket, 4)
  len = header.unpack1("N")
  body = read_exact(socket, len)
  _crc = read_exact(socket, 4)
  JSON.parse(body)
end

def send_once_without_observing_ack(fact)
  socket = TCPSocket.new(HOST, PORT)
  socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
  socket.write(encode_frame(op: "write_fact_once", fact: fact))
  sleep 0.1
ensure
  socket.close if socket && !socket.closed?
end

def start_daemon
  raise "#{BINARY} missing; run cargo build --release --bin tbackend first" unless File.executable?(BINARY)

  FileUtils.rm_rf(DATA_DIR)
  FileUtils.rm_f(LOG_PATH)
  log = File.open(LOG_PATH, "wb")
  pid = Process.spawn(
    BINARY,
    "--host", HOST,
    "--port", PORT.to_s,
    "--data-dir", DATA_DIR,
    "--pool-size", "4",
    "--max-inflight-requests", "1",
    out: log,
    err: log
  )
  log.close

  client = TBackendClient.new(host: HOST, port: PORT, connect_timeout: 0.2, request_timeout: 0.5)
  deadline = Time.now + 8.0
  last_result = nil
  while Time.now < deadline
    exited = Process.waitpid(pid, Process::WNOHANG)
    raise "daemon exited early: #{exited}" if exited

    last_result = client.ping
    return pid if last_result[:ok] == true

    sleep 0.1
  end

  raise "daemon did not become ready: #{last_result.inspect}"
end

def stop_daemon(pid)
  return true unless pid

  begin
    Process.kill("INT", pid)
  rescue Errno::ESRCH
    return true
  end

  deadline = Time.now + 8.0
  while Time.now < deadline
    exited = Process.waitpid(pid, Process::WNOHANG)
    return !exited.nil? if exited

    sleep 0.1
  end

  Process.kill("KILL", pid)
  Process.waitpid(pid)
  false
rescue Errno::ECHILD
  true
end

def preseed_large_store(client)
  payload = "x" * 65_536
  256.times do |index|
    result = client.write_fact_once(make_fact("p16_big", "k-#{index}", payload), timeout: 10.0)
    raise "preseed failed at #{index}: #{result.inspect}" unless result[:status] == "committed_acked"
  end
end

def hold_one_inflight_request
  socket = TCPSocket.new(HOST, PORT)
  socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, true)
  socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVBUF, 1024)
  socket.write(encode_frame(op: "facts_for", store: "p16_big"))
  sleep 0.3
  socket
end

def force_overload
  found = nil
  mutex = Mutex.new
  threads = 8.times.map do |thread_id|
    Thread.new do
      client = TBackendClient.new(host: HOST, port: PORT, request_timeout: 3.0)
      index = 0
      deadline = Time.now + 5.0

      while Time.now < deadline
        break if mutex.synchronize { !found.nil? }

        fact = make_fact("p16_overload_probe", "rejected-#{thread_id}-#{index}")
        result = client.write_fact_once(fact, timeout: 3.0)
        if result[:status] == "rejected_before_commit"
          mutex.synchronize { found ||= { fact: fact, result: result } }
          break
        end
        index += 1
      end
    end
  end

  threads.each(&:join)
  found
end

def capture_token_request
  server = TCPServer.new(HOST, 0)
  port = server.addr[1]
  queue = Queue.new

  thread = Thread.new do
    socket = server.accept
    header = read_exact(socket, 4)
    len = header.unpack1("N")
    body = read_exact(socket, len)
    _crc = read_exact(socket, 4)
    queue << JSON.parse(body)
    socket.write(encode_frame(ok: true, pong: true))
  ensure
    socket.close if socket && !socket.closed?
    server.close unless server.closed?
  end

  [port, queue, thread]
end

def run_checks
  token_value = SecureRandom.hex(16)
  unavailable_client = TBackendClient.new(
    host: HOST,
    port: 65_530,
    token: token_value,
    connect_timeout: 0.1,
    request_timeout: 0.1
  )
  unavailable = unavailable_client.write_fact_once(make_fact("p16_unavailable", "no-daemon"))
  assert(unavailable[:status] == "unavailable", "unavailable daemon is non-fatal")
  assert(!unavailable.inspect.include?(token_value), "transport result does not expose bearer token value")

  capture_port, queue, capture_thread = capture_token_request
  token_client = TBackendClient.new(host: HOST, port: capture_port, token: token_value, request_timeout: 1.0)
  token_ping = token_client.ping
  captured = queue.pop
  capture_thread.join
  assert(token_ping[:status] == "ok", "captured token ping receives ok response")
  assert(captured["token"] == token_value, "optional token is sent as request token field")
  assert(!token_ping.inspect.include?(token_value), "successful result does not echo bearer token value")

  pid = start_daemon
  client = TBackendClient.new(host: HOST, port: PORT, request_timeout: 5.0)

  ping = client.ping
  assert(ping[:status] == "ok", "temporary daemon ping maps to ok")

  first = make_fact("p16_once", "normal")
  first_result = client.write_fact_once(first)
  assert(first_result[:status] == "committed_acked", "first write_fact_once maps to committed_acked")

  replay_result = client.write_fact_once(first)
  assert(replay_result[:status] == "idempotent_replay", "same fact retry maps to idempotent_replay")

  conflict_result = client.write_fact_once(conflict_variant(first))
  assert(conflict_result[:status] == "duplicate_fact_id_conflict", "same id different value maps to duplicate_fact_id_conflict")
  assert(conflict_result[:retryable] == false, "duplicate_fact_id_conflict is not retryable")

  size_result = client.size(store: "p16_once")
  assert(size_result.dig(:response, :size) == 1, "commit/replay/conflict leaves one timeline fact")

  no_ack = make_fact("p16_no_ack_retry", "same-id")
  send_once_without_observing_ack(no_ack)
  retry_after_no_ack = client.write_fact_once(no_ack)
  assert(retry_after_no_ack[:status] == "idempotent_replay", "no-ack retry through write_fact_once maps to idempotent_replay")

  preseed_large_store(client)
  timeout_client = TBackendClient.new(host: HOST, port: PORT, request_timeout: 0.001)
  timeout_result = timeout_client.facts_for(store: "p16_big")
  assert(timeout_result[:status] == "timeout_unknown", "request timeout is non-fatal timeout_unknown")

  blocker = hold_one_inflight_request
  rejected = force_overload
  blocker.close
  assert(!rejected.nil?, "overload rejection can be forced")
  if rejected
    assert(rejected[:result][:status] == "rejected_before_commit", "overload maps to rejected_before_commit")
    assert(rejected[:result][:retryable] == true, "overload result is retryable")
    rejected_facts = client.facts_for(store: rejected[:fact]["store"], key: rejected[:fact]["key"])
    assert(rejected_facts.dig(:response, :facts) == [], "rejected_before_commit fact is not present")
  end

  safe_fact = make_fact("p16_safe_helper", "overload-or-timeout")
  safe_result = client.write_fact_once_safe(safe_fact, attempts: 2)
  assert(%w[committed_acked idempotent_replay].include?(safe_result[:status]), "write_fact_once_safe returns a committed status under low load")
  assert(safe_result[:attempt_count] == 1, "write_fact_once_safe records attempt metadata")

  stopped = stop_daemon(pid)
  assert(stopped, "daemon stopped cleanly")
ensure
  stop_daemon(pid) if defined?(pid) && pid
  FileUtils.rm_rf(DATA_DIR)
  FileUtils.rm_f(LOG_PATH)
end

run_checks

if $failed.positive?
  puts "FAILURES: #{$failed}"
  exit 1
end

puts "ALL RUBY CLIENT RECONCILE TESTS PASSED"
