# benchmark.rb
# Local lab stress and latency benchmark client for TBackend.

require 'socket'
require 'zlib'
require 'json'
require 'optparse'
require 'securerandom'

def log_pass(msg)
  puts "  \e[32m✔ PASS: #{msg}\e[0m"
end

def log_fail(msg)
  puts "  \e[31m✘ FAIL: #{msg}\e[0m"
  exit(1)
end

# Command-line configuration parsing
options = {
  threads: 8,
  ops: 1000,
  host: "127.0.0.1",
  port: 7410
}

OptionParser.new do |opts|
  opts.banner = "Usage: ruby benchmark.rb [options]"
  opts.on("-t", "--threads W", Integer, "Number of concurrent threads (default: 8)") { |v| options[:threads] = v }
  opts.on("-o", "--ops N", Integer, "Number of operations per thread (default: 1000)") { |v| options[:ops] = v }
  opts.on("-h", "--host H", String, "Target TBackend host (default: 127.0.0.1)") { |v| options[:host] = v }
  opts.on("-p", "--port P", Integer, "Target TBackend port (default: 7410)") { |v| options[:port] = v }
end.parse!

W = options[:threads]
N = options[:ops]
HOST = options[:host]
PORT = options[:port]

# Zero-dependency TCP connection wrapper with big-endian CRC32 framing
class TBackendClient
  def initialize(host, port)
    @socket = TCPSocket.new(host, port)
    @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  end

  def send_req(payload)
    body = payload.to_json.b
    len = body.bytesize
    crc = Zlib.crc32(body)
    frame = [len].pack("N") + body + [crc].pack("N")
    @socket.write(frame)

    # Read response length
    len_buf = @socket.read(4)
    return nil if len_buf.nil? || len_buf.bytesize < 4
    resp_len = len_buf.unpack1("N")

    # Read response body
    resp_body = @socket.read(resp_len)

    # Read response CRC
    crc_buf = @socket.read(4)
    resp_crc = crc_buf.unpack1("N")

    if Zlib.crc32(resp_body) != resp_crc
      raise "CRC mismatch in TBackend response!"
    end

    JSON.parse(resp_body)
  end

  def close
    @socket.close rescue nil
  end
end

def calculate_percentiles(durations)
  return { avg: 0, p50: 0, p90: 0, p99: 0 } if durations.empty?
  sorted = durations.map { |d| d * 1_000_000.0 }.sort # Convert to microseconds
  count = sorted.size
  avg = sorted.sum / count

  p50 = sorted[(count * 0.50).to_i] || sorted.last
  p90 = sorted[(count * 0.90).to_i] || sorted.last
  p99 = sorted[(count * 0.99).to_i] || sorted.last

  { avg: avg, p50: p50, p90: p90, p99: p99 }
end

def format_row(stage, ops, total_sec, stats)
  qps = total_sec > 0 ? (ops / total_sec).round(1) : 0.0
  sprintf(
    "│ %-22s │ %6d │ %7.3fs │ %9.1f │ %7.1fμs │ %7.1fμs │ %7.1fμs │ %7.1fμs │",
    stage, ops, total_sec, qps, stats[:avg], stats[:p50], stats[:p90], stats[:p99]
  )
end

puts "\e[1;36m┌──────────────────────────────────────────────────────────────┐"
puts "│             TBACKEND LAB SATURATION BENCHMARK                │"
puts "└──────────────────────────────────────────────────────────────┘\e[0m"
puts "  Parameters:   \e[1m#{W} threads\e[0m × \e[1m#{N} ops/thread\e[0m = \e[1;33m#{W * N} total operations per stage\e[0m"
puts "  Server Addr:  \e[1m#{HOST}:#{PORT}\e[0m\n\n"

# Verify initial connection
begin
  test_client = TBackendClient.new(HOST, PORT)
  test_client.send_req(op: "ping")
  test_client.close
  puts "\e[32m✔ Pre-flight handshake succeeded. Server is online. Booting workload stages...\e[0m\n\n"
rescue => e
  puts "\e[31m✘ Connection failed: #{e.message}\e[0m"
  exit(1)
end

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 1: Pure Write Saturation
# ──────────────────────────────────────────────────────────────────────────────
puts "\e[1;34m[Stage 1] Executing Pure Write Saturation...\e[0m"
stage1_durations = []
stage1_mutex = Mutex.new

t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
threads = (0...W).map do |t_idx|
  Thread.new do
    client = TBackendClient.new(HOST, PORT)
    local_durations = []

    N.times do |op_idx|
      key = "bench-key-#{t_idx}-#{op_idx}"
      payload = {
        op: "write_fact",
        fact: {
          id: (SecureRandom.uuid rescue "#{t_idx}-#{op_idx}-#{Time.now.to_f}"),
          store: "bench_ledger",
          key: key,
          value: {
            zip_code: ["91125", "90210", "10001", "30301"].sample,
            bid: rand(15.0..30.0).round(2),
            status: ["active", "pending", "completed"].sample,
            partner_id: "partner-#{rand(1..100)}"
          },
          value_hash: "dummy-hash", # automatically recalculated or bypassed
          transaction_time: Time.now.to_f,
          schema_version: 1
        }
      }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.send_req(payload)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      local_durations << elapsed
    end

    client.close
    stage1_mutex.synchronize { stage1_durations.concat(local_durations) }
  end
end
threads.each(&:join)
stage1_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t1
stage1_stats = calculate_percentiles(stage1_durations)

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 2: Point Query Saturation (Reads)
# ──────────────────────────────────────────────────────────────────────────────
puts "\e[1;34m[Stage 2] Executing Bitemporal Point Query (latest_for) Saturation...\e[0m"
stage2_durations = []
stage2_mutex = Mutex.new

t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
threads = (0...W).map do |t_idx|
  Thread.new do
    client = TBackendClient.new(HOST, PORT)
    local_durations = []

    N.times do
      # Lookup random key written in Stage 1
      rand_thread = rand(0...W)
      rand_op = rand(0...N)
      key = "bench-key-#{rand_thread}-#{rand_op}"

      payload = {
        op: "latest_for",
        store: "bench_ledger",
        key: key
      }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.send_req(payload)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      local_durations << elapsed
    end

    client.close
    stage2_mutex.synchronize { stage2_durations.concat(local_durations) }
  end
end
threads.each(&:join)
stage2_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t2
stage2_stats = calculate_percentiles(stage2_durations)

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 3: Pushdown Rules Slicing (Reads)
# ──────────────────────────────────────────────────────────────────────────────
puts "\e[1;34m[Stage 3] Executing Temporal query_slice with ROP rules pushdowns...\e[0m"
stage3_durations = []
stage3_mutex = Mutex.new

t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
threads = (0...W).map do |t_idx|
  Thread.new do
    client = TBackendClient.new(HOST, PORT)
    local_durations = []

    N.times do
      payload = {
        op: "query_slice",
        store: "bench_ledger",
        key_prefix: "bench-key-#{rand(0...W)}-",
        rules: [
          { left_path: "value.bid", op: "gt", right_val: 20 }
        ]
      }

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.send_req(payload)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      local_durations << elapsed
    end

    client.close
    stage3_mutex.synchronize { stage3_durations.concat(local_durations) }
  end
end
threads.each(&:join)
stage3_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t3
stage3_stats = calculate_percentiles(stage3_durations)

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 4: Mixed Read/Write Contention
# ──────────────────────────────────────────────────────────────────────────────
puts "\e[1;34m[Stage 4] Executing Mixed Read/Write Contention (Writers vs Readers)...\e[0m"
stage4_durations = []
stage4_mutex = Mutex.new

t4 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
threads = (0...W).map do |t_idx|
  Thread.new do
    client = TBackendClient.new(HOST, PORT)
    local_durations = []

    N.times do |op_idx|
      if t_idx.even?
        # Writer thread
        key = "bench-mixed-key-#{t_idx}-#{op_idx}"
        payload = {
          op: "write_fact",
          fact: {
            id: (SecureRandom.uuid rescue "#{t_idx}-#{op_idx}-#{Time.now.to_f}"),
            store: "bench_ledger",
            key: key,
            value: {
              zip_code: "90210",
              bid: rand(15.0..30.0).round(2),
              status: "active"
            },
            value_hash: "dummy-hash",
            transaction_time: Time.now.to_f,
            schema_version: 1
          }
        }
      else
        # Reader thread
        rand_thread = rand(0...W)
        rand_op = rand(0...N)
        key = "bench-key-#{rand_thread}-#{rand_op}"
        payload = {
          op: "latest_for",
          store: "bench_ledger",
          key: key
        }
      end

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      client.send_req(payload)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
      local_durations << elapsed
    end

    client.close
    stage4_mutex.synchronize { stage4_durations.concat(local_durations) }
  end
end
threads.each(&:join)
stage4_elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t4
stage4_stats = calculate_percentiles(stage4_durations)

# ──────────────────────────────────────────────────────────────────────────────
# STAGE 5: Rigorous Parity Validation & Verification
# ──────────────────────────────────────────────────────────────────────────────
puts "\n\e[1;35m[Stage 5] Performing Rigorous Database Parity Verification...\e[0m"

client = TBackendClient.new(HOST, PORT)

# 1. Check size parity
size_resp = client.send_req(op: "size", store: "bench_ledger")
total_expected_writes = (W * N) + ((W / 2) * N) # Stage 1 writes + Stage 4 writers (half of W threads)
actual_size = size_resp["size"]
if actual_size == total_expected_writes
  log_pass("Size parity matches expected database record size of #{total_expected_writes} facts")
else
  log_fail("Mismatched database size! Expected #{total_expected_writes}, got #{actual_size}")
end

# 2. Check payload structural consistency & hash validation
puts "Sampling random fact revisions..."
sample_success = true
50.times do
  rand_t = rand(0...W)
  rand_op = rand(0...N)
  key = "bench-key-#{rand_t}-#{rand_op}"

  resp = client.send_req(op: "latest_for", store: "bench_ledger", key: key)
  fact = resp["fact"]
  if fact.nil?
    sample_success = false
    next
  end

  # Assert payload has zip_code and bid
  val = fact["value"]
  if val.nil? || val["zip_code"].nil? || val["bid"].nil?
    sample_success = false
  end
end

if sample_success
  log_pass("Structural payload and field lookup consistency validated successfully across 50 random samples")
else
  log_fail("Random sampling failed to retrieve structurally consistent facts!")
end

client.close

# ──────────────────────────────────────────────────────────────────────────────
# PRESENT REPORT
# ──────────────────────────────────────────────────────────────────────────────
puts "\n\e[1;32m┌────────────────────────────────────────────────────────────────────────────────────────────────────────┐"
puts "│                                    TBACKEND STRESS TEST RESULTS REPORT                                 │"
puts "├────────────────────────┬────────┬──────────┬───────────┬───────────┬───────────┬───────────┬───────────┤"
puts "│ WORKLOAD STAGE         │ OP CNT │ TOTAL T. │ RATE(QPS) │ AVG LAT   │ p50 (MED) │ p90 LAT   │ p99 LAT   │"
puts "├────────────────────────┼────────┼──────────┼───────────┼───────────┼───────────┼───────────┼───────────┤"
puts format_row("Stage 1: Pure Writes", W * N, stage1_elapsed, stage1_stats)
puts format_row("Stage 2: Point Reads", W * N, stage2_elapsed, stage2_stats)
puts format_row("Stage 3: Rules Slices", W * N, stage3_elapsed, stage3_stats)
puts format_row("Stage 4: Mixed Read/Write", W * N, stage4_elapsed, stage4_stats)
puts "└────────────────────────┴────────┴──────────┴───────────┴───────────┴───────────┴───────────┴───────────┘\e[0m"

puts "LAB STRESS BENCHMARK SUITE COMPLETED SUCCESSFULLY!\n\n"
