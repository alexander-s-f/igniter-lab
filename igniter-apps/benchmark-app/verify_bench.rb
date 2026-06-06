# verify_bench.rb
# Local lab coordinator for the TBackend benchmark harness.

require 'open3'

def log_info(msg)
  puts "\e[34m[*] #{msg}\e[0m"
end

def log_err(msg)
  puts "\e[31m[!] #{msg}\e[0m"
end

# Port and addresses
PORT = 7410
HOST = "127.0.0.1"

# 1. Compile the local release-mode binary used by the lab benchmark harness.
tbackend_dir = File.expand_path("../../igniter-tbackend", __dir__)
log_info("Compiling local release-mode TBackend binary...")
compile_success = system("RUSTFLAGS=\"-C link-arg=-undefined -C link-arg=dynamic_lookup\" cargo build --release", chdir: tbackend_dir)
unless compile_success
  log_err("Compilation failed!")
  exit(1)
end

# 2. Spawn TBackend daemon in ephemeral mode pointing to port 7410
log_info("Spawning TBackend daemon in background on port #{PORT}...")
daemon_path = File.join(tbackend_dir, "target/release/tbackend")
daemon_cmd = "#{daemon_path} --host #{HOST} --port #{PORT} --data-dir nil --pool-size 16"
stdin, stdout, stderr, wait_thr = Open3.popen3(daemon_cmd)

# Wait briefly for socket binding
sleep(1.5)

begin
  # 3. Spawn benchmark client with a bounded lab workload.
  # 12 parallel threads, 1,500 operations per thread, total 18,000 requests per stage
  log_info("Running saturation benchmark (12 threads × 1500 ops = 18k ops per stage)...")
  bench_script = File.expand_path("benchmark.rb", __dir__)
  bench_success = system("ruby #{bench_script} --threads 12 --ops 1500 --host #{HOST} --port #{PORT}")

  if bench_success
    puts "\n\e[32mBENCHMARK COORDINATOR SUITE COMPLETED SUCCESSFULLY!\e[0m\n\n"
  else
    log_err("Benchmark execution reported errors or failed parity assertions!")
    exit(1)
  end

ensure
  # 4. Gracefully kill daemon process
  log_info("Stopping TBackend daemon process gracefully...")
  stdin.close rescue nil
  stdout.close rescue nil
  stderr.close rescue nil
  if wait_thr && wait_thr.pid
    Process.kill("KILL", wait_thr.pid) rescue nil
  end
end
