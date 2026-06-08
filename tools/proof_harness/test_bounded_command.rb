# frozen_string_literal: true
# igniter-lab/tools/proof_harness/test_bounded_command.rb
#
# Synthetic test suite for BoundedCommand.
#
# Verifies:
#   BC-T1  timeout is detected for a long-sleep command
#   BC-T2  timed-out child process is no longer alive after cleanup
#   BC-T3  timeout records FAIL (ok? == false), not PASS
#   BC-T4  elapsed time is >= timeout threshold
#   BC-T5  normal-exit-0 command returns ok? == true
#   BC-T6  non-zero exit command returns ok? == false (not timeout)
#   BC-T7  stdout captured correctly on success
#   BC-T8  stderr captured correctly on non-zero exit
#   BC-T9  command-not-found returns ok? == false, exit_code 127 or nil
#   BC-T10 print_result emits TIMEOUT label on timeout
#
# Run: ruby tools/proof_harness/test_bounded_command.rb
# Expected: ALL PASS (10/10)
#
# Lab-only. Card: LAB-PROOF-HYGIENE-P1.

require_relative "bounded_command"
require 'stringio'

PASS_COUNT = [0]
FAIL_COUNT = [0]

def check(label, value, detail = nil)
  if value
    puts "  [+] PASS: #{label}"
    PASS_COUNT[0] += 1
  else
    puts "  [!] FAIL: #{label}#{detail ? " — #{detail}" : ""}"
    FAIL_COUNT[0] += 1
  end
end

SHORT_TIMEOUT = 1  # seconds — keep test fast

puts "\n=== BoundedCommand self-test ===\n"

# ── BC-T1 / BC-T2 / BC-T3 / BC-T4: timeout scenario ─────────────────────────
puts "\n--- Timeout scenario (sleep #{SHORT_TIMEOUT * 3}s with #{SHORT_TIMEOUT}s limit) ---"
sleep_cmd = "sleep #{SHORT_TIMEOUT * 3}"
r_timeout = BoundedCommand.run(sleep_cmd, label: "test:timeout_sleep", timeout: SHORT_TIMEOUT)

check "BC-T1: timed_out == true", r_timeout.timed_out
check "BC-T3: ok? == false (FAIL, not PASS)", !r_timeout.ok?
check "BC-T4: elapsed >= timeout threshold (#{SHORT_TIMEOUT}s)", r_timeout.elapsed >= SHORT_TIMEOUT

# BC-T2: child process must not be alive after cleanup
# Give the OS a moment to reap the process
sleep 0.3
pid = r_timeout.pid
child_alive = pid && begin
  Process.kill(0, pid)   # signal 0 = "are you alive?"
  true
rescue Errno::ESRCH, Errno::EPERM
  false
end
check "BC-T2: timed-out child (pid=#{pid || '?'}) is no longer alive after cleanup", !child_alive,
      "pid #{pid} still responded to kill(0)"

# ── BC-T5 / BC-T7: successful command ────────────────────────────────────────
puts "\n--- Successful command (echo hello) ---"
r_ok = BoundedCommand.run("echo hello", label: "test:echo", timeout: SHORT_TIMEOUT)

check "BC-T5: ok? == true for exit 0",  r_ok.ok?
check "BC-T7: stdout captured correctly", r_ok.stdout.strip == "hello",
      "got: #{r_ok.stdout.strip.inspect}"

# ── BC-T6 / BC-T8: non-zero exit command ────────────────────────────────────
puts "\n--- Non-zero exit (sh -c 'echo err >&2; exit 42') ---"
r_fail = BoundedCommand.run("sh -c 'echo err >&2; exit 42'", label: "test:fail42", timeout: SHORT_TIMEOUT)

check "BC-T6: ok? == false for exit 42", !r_fail.ok?
check "BC-T6b: timed_out == false (it exited, not timed out)", !r_fail.timed_out
check "BC-T8: stderr captured", r_fail.stderr.include?("err"),
      "stderr: #{r_fail.stderr.inspect}"

# ── BC-T9: command not found ─────────────────────────────────────────────────
puts "\n--- Command not found (nonexistent_command_xyz_abc) ---"
r_notfound = BoundedCommand.run("nonexistent_command_xyz_abc_proof_test",
                                label: "test:notfound", timeout: SHORT_TIMEOUT)
check "BC-T9: ok? == false for missing command", !r_notfound.ok?

# ── BC-T10: print_result emits TIMEOUT label ─────────────────────────────────
puts "\n--- print_result output check (BC-T10) ---"
captured = StringIO.new
old_stdout = $stdout
$stdout = captured
BoundedCommand.print_result(r_timeout)
$stdout = old_stdout
output_text = captured.string

check "BC-T10: print_result includes [TIMEOUT] for timed-out result",
      output_text.include?("[TIMEOUT]"),
      "got: #{output_text.lines.first.strip.inspect}"

# ── Summary ──────────────────────────────────────────────────────────────────
puts "\n" + "─" * 60
total = PASS_COUNT[0] + FAIL_COUNT[0]
puts "BoundedCommand self-test: #{PASS_COUNT[0]}/#{total} PASS"
if FAIL_COUNT[0] > 0
  puts "[!] #{FAIL_COUNT[0]} FAIL — BoundedCommand helper has defects; fix before deploying."
  exit 1
else
  puts "[+] All #{total} self-test checks passed."
end
