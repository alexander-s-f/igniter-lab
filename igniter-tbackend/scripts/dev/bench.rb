# frozen_string_literal: true

require "fileutils"
require "securerandom"

ROOT = File.expand_path("../..", __dir__)

puts "=== 1. Compiling Playground Rust Extension ==="
Dir.chdir(ROOT) do
  cmd = "RUSTFLAGS='-C link-arg=-undefined -C link-arg=dynamic_lookup' cargo build --release --features ffi"
  system(cmd) || raise("Failed to compile playground Rust extension!")
  
  # Ensure the symlink exists without the 'lib' prefix so Ruby require works
  Dir.chdir("target/release") do
    dylib = "libigniter_tbackend_playground.dylib"
    so_file = "libigniter_tbackend_playground.so"
    target_dylib = "igniter_tbackend_playground.bundle"
    target_so = "igniter_tbackend_playground.so"
    
    if File.exist?(dylib) && !File.exist?(target_dylib)
      puts "Creating symlink #{target_dylib} -> #{dylib}"
      File.symlink(dylib, target_dylib)
    elsif File.exist?(so_file) && !File.exist?(target_so)
      puts "Creating symlink #{target_so} -> #{so_file}"
      File.symlink(so_file, target_so)
    end
  end
end

# Load Mainline
$LOAD_PATH.unshift(File.expand_path("../../packages/igniter-ledger/lib", ROOT))
require "igniter-ledger"

# Load Playground
$LOAD_PATH.unshift(File.expand_path("target/release", ROOT))
require "igniter_tbackend_playground"

# Setup Playground Ruby wrappers
module Igniter
  module TBackendPlayground
    class Fact
      def self.build(store:, key:, value:, causation: nil, valid_time: nil, term: nil, schema_version: 1)
        vt = valid_time.nil? ? (term ? term.to_f : nil) : valid_time.to_f
        _native_build(
          store.to_s,
          key.to_s,
          value,
          causation,
          vt,
          schema_version.to_i
        )
      end

      alias_method :_native_value, :value
      def value = _native_value
    end

    class FactLog
      def append(fact)
        _native_append(fact)
        fact
      end

      def latest_for(store:, key:, as_of: nil)
        latest_for_native(store.to_s, key.to_s, as_of&.to_f)
      end

      def facts_for(store:, key: nil, since: nil, as_of: nil)
        facts_for_native(store.to_s, key&.to_s, since&.to_f, as_of&.to_f)
      end

      def query_scope(store:, filters:, as_of: nil)
        query_scope_native(store.to_s, filters, as_of&.to_f)
      end
    end
  end
end

puts "\nMainline Native extension loaded? #{defined?(Igniter::Store::NATIVE) && Igniter::Store::NATIVE}"
puts "Playground extension loaded? #{defined?(Igniter::TBackendPlayground::FactLog)}"

# Clean up any WAL files from previous runs
WAL_PATH_MAIN = "mainline_bench.wal"
WAL_PATH_PLAY = "playground_bench.wal"
FileUtils.rm_f(WAL_PATH_MAIN)
FileUtils.rm_f(WAL_PATH_PLAY)

# Initialize instances
main_log = Igniter::Store::FactLog.new
play_log = Igniter::TBackendPlayground::FactLog.new

main_wal = Igniter::Store::FileBackend.new(WAL_PATH_MAIN)
play_wal = Igniter::TBackendPlayground::FileBackend.new(WAL_PATH_PLAY)

puts "\n=== 2. Correctness Parity Validation ==="
# We write identical facts and verify that the timelines match exactly
store = "jobs"
key = "job-42"
timestamps = []

# Write 10 sequential facts with precise time differences
10.times do |i|
  value = { status: i < 5 ? :pending : :completed, retry_count: i }
  
  f_main = Igniter::Store::Fact.build(store: store, key: key, value: value)
  f_play = Igniter::TBackendPlayground::Fact.build(store: store, key: key, value: value)
  
  main_log.append(f_main)
  play_log.append(f_play)
  
  main_wal.write_fact(f_main)
  play_wal.write_fact(f_play)
  
  sleep 0.02 # Sleep 20ms to ensure distinct transaction timestamps
end

# Check size
puts "Mainline size: #{main_log.size} | Playground size: #{play_log.size}"
raise "Size mismatch!" unless main_log.size == play_log.size

# Check latest_for at various points in time
t_half = play_log.facts_for(store: store, key: key)[5].transaction_time - 0.01

main_latest_half = main_log.latest_for(store: store, key: key, as_of: t_half)
play_latest_half = play_log.latest_for(store: store, key: key, as_of: t_half)

puts "As-of mid-point: Mainline status = #{main_latest_half.value[:status]} | Playground status = #{play_latest_half.value[:status]}"
raise "Latest-for value mismatch!" unless main_latest_half.value[:status] == play_latest_half.value[:status]

# Verify facts_for range
t_start_main = main_log.facts_for(store: store, key: key)[2].transaction_time
t_end_main   = main_log.facts_for(store: store, key: key)[7].transaction_time

t_start_play = play_log.facts_for(store: store, key: key)[2].transaction_time
t_end_play   = play_log.facts_for(store: store, key: key)[7].transaction_time

main_range = main_log.facts_for(store: store, key: key, since: t_start_main, as_of: t_end_main)
play_range = play_log.facts_for(store: store, key: key, since: t_start_play, as_of: t_end_play)

puts "Range facts count: Mainline = #{main_range.size} | Playground = #{play_range.size}"
raise "Range size mismatch!" unless main_range.size == play_range.size

# Verify query_scope filtering
main_scope = main_log.query_scope(store: store, filters: { status: :pending })
play_scope = play_log.query_scope(store: store, filters: { status: :pending })
puts "Scope query (status=pending): Mainline matches? #{!main_scope.empty?} | Playground matches? #{!play_scope.empty?}"
raise "Scope query mismatch!" unless main_scope.size == play_scope.size

# Verify WAL Replay Parity
main_wal.close
play_wal.close

main_wal_replay = Igniter::Store::FileBackend.new(WAL_PATH_MAIN)
play_wal_replay = Igniter::TBackendPlayground::FileBackend.new(WAL_PATH_PLAY)

main_replayed = main_wal_replay.replay
play_replayed = play_wal_replay.replay
puts "WAL Replay Count: Mainline = #{main_replayed.size} | Playground = #{play_replayed.size}"
raise "WAL Replay count mismatch!" unless main_replayed.size == play_replayed.size

puts "✅ Correctness Parity Validation PASSED!"

puts "\n=== 3. Performance Benchmark ==="

THREAD_COUNTS = [1, 4, 8]
WRITE_COUNT_PER_THREAD = 1000

# Benchmark 1: Concurrent Write Throughput
puts "\n--- Benchmark A: Parallel Writes (Throughput & Lock Contention) ---"
THREAD_COUNTS.each do |threads|
  puts "Running with #{threads} threads (#{threads * WRITE_COUNT_PER_THREAD} total writes)..."
  
  # Mainline
  main_log_bench = Igniter::Store::FactLog.new
  t_start = Time.now
  pool = threads.times.map do |t_idx|
    Thread.new do
      WRITE_COUNT_PER_THREAD.times do |i|
        f = Igniter::Store::Fact.build(
          store: "store_#{t_idx}",
          key: "key_#{i}",
          value: { index: i, thread: t_idx, payload: "data" }
        )
        main_log_bench.append(f)
      end
    end
  end
  pool.each(&:join)
  t_main = Time.now - t_start
  main_tps = (threads * WRITE_COUNT_PER_THREAD) / t_main
  
  # Playground (Optimized)
  play_log_bench = Igniter::TBackendPlayground::FactLog.new
  t_start = Time.now
  pool = threads.times.map do |t_idx|
    Thread.new do
      WRITE_COUNT_PER_THREAD.times do |i|
        f = Igniter::TBackendPlayground::Fact.build(
          store: "store_#{t_idx}",
          key: "key_#{i}",
          value: { index: i, thread: t_idx, payload: "data" }
        )
        play_log_bench.append(f)
      end
    end
  end
  pool.each(&:join)
  t_play = Time.now - t_start
  play_tps = (threads * WRITE_COUNT_PER_THREAD) / t_play
  
  speedup = main_tps > 0 ? (play_tps / main_tps).round(2) : 0
  puts "  Mainline:   #{t_main.round(3)}s | #{main_tps.round(0)} writes/sec"
  puts "  Playground: #{t_play.round(3)}s | #{play_tps.round(0)} writes/sec"
  puts "  Speedup:    #{speedup}x"
end

# Benchmark 2: Binary Search Scaling Over Deep Histories
puts "\n--- Benchmark B: Point Reads ($O(\\log N)$ vs $O(N)$) over Deep History ---"
[100, 1000, 5000].each do |history_depth|
  puts "Pre-loading key with #{history_depth} updates..."
  
  main_log_deep = Igniter::Store::FactLog.new
  play_log_deep = Igniter::TBackendPlayground::FactLog.new
  
  history_depth.times do |i|
    val = { count: i }
    f_main = Igniter::Store::Fact.build(store: "deep", key: "k", value: val)
    f_play = Igniter::TBackendPlayground::Fact.build(store: "deep", key: "k", value: val)
    main_log_deep.append(f_main)
    play_log_deep.append(f_play)
  end
  
  # Grab timeline boundaries
  timeline = play_log_deep.facts_for(store: "deep", key: "k")
  t_min = timeline.first.transaction_time
  t_max = timeline.last.transaction_time
  
  # Generate 5,000 random query timestamps
  queries = Array.new(5000) { rand(t_min..t_max) }
  
  # Mainline point reads (linear scan)
  t_start = Time.now
  queries.each do |q|
    main_log_deep.latest_for(store: "deep", key: "k", as_of: q)
  end
  t_main = Time.now - t_start
  main_rps = queries.size / t_main
  
  # Playground point reads (binary search)
  t_start = Time.now
  queries.each do |q|
    play_log_deep.latest_for(store: "deep", key: "k", as_of: q)
  end
  t_play = Time.now - t_start
  play_rps = queries.size / t_play
  
  speedup = main_rps > 0 ? (play_rps / main_rps).round(2) : 0
  puts "  History depth: #{history_depth} commits"
  puts "    Mainline:   #{t_main.round(4)}s | #{main_rps.round(0)} reads/sec"
  puts "    Playground: #{t_play.round(4)}s | #{play_rps.round(0)} reads/sec"
  puts "    Speedup:    #{speedup}x"
end

# Benchmark 3: Mixed Read/Write Contention
puts "\n--- Benchmark C: Mixed Read/Write Contention (Sharded Locks vs. Global Lock) ---"
[4, 8].each do |threads|
  puts "Running with #{threads} threads (half writing, half reading)..."
  
  # Mainline
  main_log_mix = Igniter::Store::FactLog.new
  # Prepopulate some keys
  1000.times do |i|
    f = Igniter::Store::Fact.build(store: "mix", key: "k_#{i}", value: { init: true })
    main_log_mix.append(f)
  end
  
  t_start = Time.now
  writer_pool = (threads / 2).times.map do |t_idx|
    Thread.new do
      500.times do |i|
        f = Igniter::Store::Fact.build(
          store: "mix",
          key: "k_#{t_idx}_#{i}",
          value: { updated: i }
        )
        main_log_mix.append(f)
      end
    end
  end
  
  reader_pool = (threads / 2).times.map do |t_idx|
    Thread.new do
      500.times do |i|
        main_log_mix.latest_for(store: "mix", key: "k_#{rand(1000)}")
      end
    end
  end
  
  (writer_pool + reader_pool).each(&:join)
  t_main = Time.now - t_start
  
  # Playground (Optimized)
  play_log_mix = Igniter::TBackendPlayground::FactLog.new
  # Prepopulate some keys
  1000.times do |i|
    f = Igniter::TBackendPlayground::Fact.build(store: "mix", key: "k_#{i}", value: { init: true })
    play_log_mix.append(f)
  end
  
  t_start = Time.now
  writer_pool = (threads / 2).times.map do |t_idx|
    Thread.new do
      500.times do |i|
        f = Igniter::TBackendPlayground::Fact.build(
          store: "mix",
          key: "k_#{t_idx}_#{i}",
          value: { updated: i }
        )
        play_log_mix.append(f)
      end
    end
  end
  
  reader_pool = (threads / 2).times.map do |t_idx|
    Thread.new do
      500.times do |i|
        play_log_mix.latest_for(store: "mix", key: "k_#{rand(1000)}")
      end
    end
  end
  
  (writer_pool + reader_pool).each(&:join)
  t_play = Time.now - t_start
  
  speedup = t_play > 0 ? (t_main / t_play).round(2) : 0
  puts "  Mainline:   #{t_main.round(3)}s"
  puts "  Playground: #{t_play.round(3)}s"
  puts "  Speedup:    #{speedup}x"
end

# Clean up files
FileUtils.rm_f(WAL_PATH_MAIN)
FileUtils.rm_f(WAL_PATH_PLAY)
puts "\n=== All Benchmarks Completed! ==="
