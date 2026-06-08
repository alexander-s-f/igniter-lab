# frozen_string_literal: true
# igniter-lab/tools/proof_harness/bounded_command.rb
#
# Lab-only proof harness utility: bounded external command execution with
# hard timeout and child-process-group cleanup.
#
# Problem solved:
#   Unbounded backtick / system() / Open3.capture3 calls in lab proof runners
#   can leave `igniter_compiler`, `igniter-vm`, and `rustc` processes running at
#   100% CPU indefinitely if the compiler or VM hangs. This helper wraps every
#   external call with a hard timeout that kills the full process group on
#   expiry, and reports timeout as proof FAIL — never silently PASS.
#
# Usage:
#   require_relative "../../tools/proof_harness/bounded_command"
#
#   r = BoundedCommand.run(cmd, label: "compile:foo")
#   # or with explicit timeout:
#   r = BoundedCommand.run(cmd, label: "cargo build", timeout: BoundedCommand::CARGO_TIMEOUT)
#   # or run-and-print in one call:
#   r = BoundedCommand.run_checked(cmd, label: "compile:foo")
#
#   r.ok?       # true iff exit 0 and no timeout
#   r.stdout    # captured stdout
#   r.stderr    # captured stderr
#   r.combined  # stdout + "\n" + stderr (convenience for scripts that used 2>&1)
#   r.timed_out # true if timeout fired
#   r.elapsed   # Float seconds
#   r.exit_code # Integer or nil if killed
#   r.pid       # child pid (for log messages)
#
# Timeout policy (all configurable via environment variables):
#   IGNITER_PROOF_TIMEOUT_SECONDS       — per-fixture compiler/VM execution (default 10s)
#   IGNITER_PROOF_CARGO_TIMEOUT_SECONDS — cargo build / cargo test / cargo run (default 120s)
#   IGNITER_PROOF_WIDE_TIMEOUT_SECONDS  — whole-proof guard (default 300s; not auto-applied)
#
# Process cleanup:
#   Spawns each child in its own process group (pgroup: true).
#   On timeout: SIGTERM → 300ms grace → SIGKILL to the entire process group.
#   On normal return: belt-and-suspenders SIGKILL attempt after wait, silently
#   ignored if the process has already exited.
#
# NOT canon, NOT production, NOT stable API.
# Lab safety hardening only. Card: LAB-PROOF-HYGIENE-P1.
# Date: 2026-06-08

require 'open3'

module BoundedCommand
  # ── Timeout defaults ─────────────────────────────────────────────────────────
  EXEC_TIMEOUT  = Integer(ENV.fetch("IGNITER_PROOF_TIMEOUT_SECONDS",       "10"))
  CARGO_TIMEOUT = Integer(ENV.fetch("IGNITER_PROOF_CARGO_TIMEOUT_SECONDS", "120"))
  PROOF_TIMEOUT = Integer(ENV.fetch("IGNITER_PROOF_WIDE_TIMEOUT_SECONDS",  "300"))

  # ── Result ───────────────────────────────────────────────────────────────────
  Result = Struct.new(
    :label, :ok, :stdout, :stderr, :exit_code,
    :timed_out, :elapsed, :pid, :timeout_used,
    keyword_init: true
  ) do
    alias_method :ok?, :ok
    def fail?    = !ok
    def combined = [stdout.to_s, stderr.to_s].reject(&:empty?).join("\n")
  end

  # ── run(cmd, label:, timeout:) → Result ──────────────────────────────────────
  #
  # Spawns cmd in a new process group. Kills the group on timeout.
  # Returns a Result with ok=false on timeout, non-zero exit, or spawn error.
  def self.run(cmd, label:, timeout: EXEC_TIMEOUT)
    t0          = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stdout_buf  = +""
    stderr_buf  = +""
    timed_out   = false
    exit_code   = nil
    captured_pid = nil

    begin
      Open3.popen3(cmd, pgroup: true) do |sin, sout, serr, wait_thr|
        captured_pid = wait_thr.pid
        sin.close

        # Drain pipes in background threads to prevent deadlock when buffers fill
        out_thr = Thread.new { stdout_buf = sout.read rescue "" }
        err_thr = Thread.new { stderr_buf = serr.read rescue "" }

        if wait_thr.join(timeout)
          # Process finished within the timeout window
          exit_code = wait_thr.value&.exitstatus
        else
          # Hard timeout — kill the process group
          timed_out = true
          _kill_group(captured_pid)
          wait_thr.join(3)  # brief grace period for OS bookkeeping
        end

        # Give drain threads a moment to finish after pipes close
        out_thr.join(5)
        err_thr.join(5)
      end
    rescue Errno::ENOENT => e
      stderr_buf << "[BoundedCommand] command not found: #{e.message}"
      exit_code = 127
    rescue => e
      stderr_buf << "[BoundedCommand] spawn error: #{e.class}: #{e.message}"
    end

    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
    ok      = !timed_out && exit_code == 0

    Result.new(
      label:        label,
      ok:           ok,
      stdout:       stdout_buf,
      stderr:       stderr_buf,
      exit_code:    exit_code,
      timed_out:    timed_out,
      elapsed:      elapsed.round(3),
      pid:          captured_pid,
      timeout_used: timeout
    )
  end

  # ── run_checked(cmd, label:, timeout:) → Result ───────────────────────────────
  #
  # run + print a compact FAIL/TIMEOUT line if the command did not pass.
  # On PASS: prints nothing (caller prints its own [+] PASS line as before).
  def self.run_checked(cmd, label:, timeout: EXEC_TIMEOUT)
    r = run(cmd, label: label, timeout: timeout)
    print_result(r) unless r.ok?
    r
  end

  # ── print_result(result) ─────────────────────────────────────────────────────
  #
  # Emit a compact TIMEOUT or FAIL summary for a Result that did not pass.
  # Safe to call on a passing result (prints nothing).
  def self.print_result(r)
    return if r.ok?
    if r.timed_out
      puts "[TIMEOUT] #{r.label}"
      puts "          elapsed=#{r.elapsed}s  limit=#{r.timeout_used}s  pid=#{r.pid || '?'}"
      tail = r.stdout.lines.last(3).join.strip
      puts "          stdout: #{tail[0, 200]}" unless tail.empty?
      tail = r.stderr.lines.last(3).join.strip
      puts "          stderr: #{tail[0, 200]}" unless tail.empty?
    else
      puts "[FAIL]    #{r.label} (exit=#{r.exit_code.inspect}, elapsed=#{r.elapsed}s)"
      tail = r.stderr.lines.last(5).join.strip
      puts "          stderr: #{tail[0, 400]}" unless tail.empty?
    end
  end

  # ── Private helpers ───────────────────────────────────────────────────────────

  # Send SIGTERM then SIGKILL to the process group whose pgid == pid.
  # Safe to call if the group has already exited (ESRCH / EPERM ignored).
  def self._kill_group(pid)
    return unless pid
    begin
      Process.kill("TERM", -pid)
      sleep 0.3
      Process.kill("KILL", -pid)
    rescue Errno::ESRCH, Errno::EPERM
      # Process group already gone — fine
    rescue => e
      # Unexpected; don't raise, just note in stderr
      $stderr.puts "[BoundedCommand] warning: kill_group(#{pid}): #{e.class}: #{e.message}"
    end
  end
  private_class_method :_kill_group
end
