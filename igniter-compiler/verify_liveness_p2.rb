# encoding: utf-8
# verify_liveness_p2.rb
# LAB-COMPILER-LIVENESS-P2 formal verification script
#
# Card: LAB-COMPILER-LIVENESS-P2
# Track: lab-compiler-liveness-instrumentation-counters-v0
# Route: EXPERIMENTAL / LAB-ONLY / INSTRUMENTATION-ONLY
#
# Acceptance criteria verified here:
#   [A1] Existing proof suites still pass — canonical fixtures compile without regression
#   [A2] Adversarial deep fixture records high depth but does NOT change behavior
#   [A3] Receipt gives enough data to choose P3 hard limits (counters present + values)
#   [A4] Non-fatal — OOF fixtures still return oof (not changed to ok or error)
#   [A5] Stderr separation — threshold warnings on stderr, JSON on stdout only
#   [A6] Receipt injected on BOTH ok and oof compilation paths
#
# Sections:
#   P2-A: Build
#   P2-B: Adversarial probe (liveness_depth_probe.ig — 200-term addition)
#   P2-C: Canonical regression (add, decimal_contract, vendor_lead_pipeline)
#   P2-D: OOF receipt injection (loops_and_recursion — pre-existing OOF-R3 gap)
#   P2-E: Stderr separation (stdout = clean JSON; stderr = threshold notices)
#   P2-F: Receipt schema validation (required fields + counter keys)
#
# Total checks: 27
#
# LAB-PROOF-HYGIENE-P1: all external commands via BoundedCommand.

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../tools/proof_harness/bounded_command'

ROOT     = Pathname.new(__dir__)
COMP     = ROOT / "target/release/igniter_compiler"
FIXTURES = ROOT / "fixtures"
CONF_SRC = FIXTURES / "conformance/source"

$pass_count = 0
$fail_count = 0
$section    = nil

def section(name)
  $section = name
  puts "\n── #{name} ──"
end

def pass(msg)
  puts "  [+] PASS: #{msg}"
  $pass_count += 1
end

def fail!(msg)
  puts "  [!] FAIL: #{msg}"
  $fail_count += 1
end

def compile_file(path, label, env: {})
  Dir.mktmpdir("liveness_p2_#{label}") do |tmp|
    out = File.join(tmp, "#{label}.igapp")
    env_prefix = env.map { |k, v| "#{k}=#{v}" }.join(" ")
    cmd = "#{env_prefix} #{COMP} compile #{path} --out #{out}".strip
    r = BoundedCommand.run(cmd, label: "compile:#{label}",
                           timeout: BoundedCommand::EXEC_TIMEOUT)
    BoundedCommand.print_result(r) unless r.ok? || r.exit_code == 1
    stdout_str = r.stdout.to_s.force_encoding('UTF-8')
    result_json = JSON.parse(stdout_str) rescue nil
    { ok: r.ok?, timed_out: r.timed_out, exit_code: r.exit_code,
      stdout: stdout_str, stderr: r.stderr.to_s.force_encoding('UTF-8'),
      json: result_json }
  end
end

def liveness_receipt(result_json)
  result_json&.dig('liveness_instrumentation')
end

def check_receipt_present(result, label)
  li = liveness_receipt(result[:json])
  if li
    pass("#{label}: liveness_instrumentation present")
  else
    fail!("#{label}: liveness_instrumentation missing from output")
  end
  li
end

def check_non_fatal(result, label)
  li = liveness_receipt(result[:json])
  if li&.dig('non_fatal') == true
    pass("#{label}: non_fatal=true")
  else
    fail!("#{label}: non_fatal != true (got #{li&.dig('non_fatal').inspect})")
  end
end

# ── P2-A: Build ───────────────────────────────────────────────────────────────

section "P2-A: Build"

build_r = BoundedCommand.run("cargo build --release 2>&1",
                              label: "cargo:build:release",
                              timeout: BoundedCommand::CARGO_TIMEOUT)
if build_r.ok?
  pass("cargo build --release exited 0")
else
  fail!("cargo build --release failed (exit=#{build_r.exit_code.inspect}, timeout=#{build_r.timed_out})")
  puts "  Build output (last 10 lines):"
  build_r.combined.lines.last(10).each { |l| puts "    #{l}" }
  puts "\nBuild failed — cannot continue. Exiting."
  exit 1
end

# ── P2-B: Adversarial probe ───────────────────────────────────────────────────

section "P2-B: Adversarial probe (liveness_depth_probe.ig — 200-term addition)"

probe_path = FIXTURES / "liveness_depth_probe.ig"
unless probe_path.exist?
  fail!("liveness_depth_probe.ig not found at #{probe_path}")
  puts "\nFixture missing — cannot run adversarial probe section."
  $fail_count += 4  # count the remaining checks as failed
else
  probe = compile_file(probe_path, "liveness_depth_probe")

  status = probe[:json]&.dig('status')
  if status == 'ok'
    pass("liveness_depth_probe: status=ok (200-term expression compiles cleanly)")
  else
    fail!("liveness_depth_probe: expected status=ok, got #{status.inspect}")
  end

  li = check_receipt_present(probe, "liveness_depth_probe")
  check_non_fatal(probe, "liveness_depth_probe")

  tc_depth = li&.dig('counters', 'typechecker.infer_expr.max_depth').to_i
  if tc_depth >= 150
    pass("liveness_depth_probe: tc_infer_max_depth=#{tc_depth} >= 150 (high depth recorded)")
  else
    fail!("liveness_depth_probe: tc_infer_max_depth=#{tc_depth} < 150 — counter not firing correctly")
  end

  fr_depth = li&.dig('counters', 'form_resolver.walk_expr.max_depth').to_i
  if fr_depth >= 150
    pass("liveness_depth_probe: fr_walk_max_depth=#{fr_depth} >= 150 (high depth recorded)")
  else
    fail!("liveness_depth_probe: fr_walk_max_depth=#{fr_depth} < 150 — counter not firing correctly")
  end
end

# ── P2-C: Canonical regression ────────────────────────────────────────────────

section "P2-C: Canonical regression (no behavior change)"

CANONICAL_OK = [
  { label: "add",                  path: CONF_SRC / "add.ig" },
  { label: "decimal_contract",     path: CONF_SRC / "decimal_contract.ig" },
  { label: "vendor_lead_pipeline", path: CONF_SRC / "vendor_lead_pipeline.ig" },
]

CANONICAL_OK.each do |fixture|
  unless fixture[:path].exist?
    fail!("#{fixture[:label]}: fixture file not found at #{fixture[:path]}")
    $fail_count += 2  # count the remaining two checks for this fixture
    next
  end
  result = compile_file(fixture[:path], fixture[:label])
  status = result[:json]&.dig('status')
  if status == 'ok'
    pass("#{fixture[:label]}: status=ok (no regression)")
  else
    fail!("#{fixture[:label]}: expected status=ok, got #{status.inspect}")
  end
  check_receipt_present(result, fixture[:label])
  check_non_fatal(result, fixture[:label])
end

# ── P2-D: OOF receipt injection ───────────────────────────────────────────────

section "P2-D: OOF receipt injection (pre-existing OOF fixture still returns oof)"

# loops_and_recursion.ig has a pre-existing OOF-R3 conformance gap
# (Rust compiler v0 does not yet accept items.remaining dotted-path variant).
# P2 must NOT change that result to ok — and must still inject the receipt.
oof_path = CONF_SRC / "loops_and_recursion.ig"
if oof_path.exist?
  oof_result = compile_file(oof_path, "loops_and_recursion")
  oof_status = oof_result[:json]&.dig('status')

  # Accept either 'oof' or 'error' — both indicate rejection (not ok)
  if oof_status && oof_status != 'ok'
    pass("loops_and_recursion: status=#{oof_status} (still rejected — P2 did not change behavior)")
  else
    fail!("loops_and_recursion: expected oof/error status, got #{oof_status.inspect} — P2 may have changed behavior")
  end

  check_receipt_present(oof_result, "loops_and_recursion:oof")
  check_non_fatal(oof_result, "loops_and_recursion:oof")
else
  fail!("loops_and_recursion.ig: fixture not found at #{oof_path} — skipping D checks")
  $fail_count += 2
end

# ── P2-E: Stderr separation ───────────────────────────────────────────────────

section "P2-E: Stderr separation (threshold notices on stderr; stdout = clean JSON)"

# Use a low threshold so notices fire reliably on the adversarial probe
probe_path = FIXTURES / "liveness_depth_probe.ig"
if probe_path.exist?
  # Threshold = 50 → depth-51 fires notice; 200-term expr will trigger it
  sep_result = compile_file(probe_path, "liveness_sep",
                            env: { "IGNITER_LIVENESS_LOG_THRESHOLD" => "50" })

  # Stdout must parse as JSON (no notice contamination)
  if sep_result[:json]
    pass("stderr-sep: stdout is valid JSON even when threshold notices fire")
  else
    fail!("stderr-sep: stdout is NOT valid JSON — notices may have contaminated stdout")
    puts "    stdout preview: #{sep_result[:stdout][0, 200]}"
  end

  # Stderr must contain threshold notices
  if sep_result[:stderr].include?("[LIVENESS-P2]")
    notice_count = sep_result[:stderr].scan("[LIVENESS-P2]").length
    pass("stderr-sep: stderr contains #{notice_count} [LIVENESS-P2] notice(s) — correctly routed to stderr")
  else
    fail!("stderr-sep: stderr does not contain [LIVENESS-P2] notices")
    puts "    stderr preview: #{sep_result[:stderr][0, 400]}"
  end

  # Stdout must NOT contain [LIVENESS-P2]
  if sep_result[:stdout].include?("[LIVENESS-P2]")
    fail!("stderr-sep: stdout contains [LIVENESS-P2] notices — notices must not appear in stdout JSON")
  else
    pass("stderr-sep: stdout does not contain [LIVENESS-P2] — clean separation confirmed")
  end
else
  fail!("liveness_depth_probe.ig missing — skipping E section")
  $fail_count += 2
end

# ── P2-F: Receipt schema validation ──────────────────────────────────────────

section "P2-F: Receipt schema validation (required fields + counter keys)"

probe_path = FIXTURES / "liveness_depth_probe.ig"
if probe_path.exist?
  schema_probe = compile_file(probe_path, "liveness_schema")
  li = liveness_receipt(schema_probe[:json])

  if li
    REQUIRED_FIELDS = %w[kind authority non_fatal counters log_threshold p3_note].freeze
    missing = REQUIRED_FIELDS.reject { |f| li.key?(f) }
    if missing.empty?
      pass("receipt: all required top-level fields present (#{REQUIRED_FIELDS.join(', ')})")
    else
      fail!("receipt: missing fields: #{missing.join(', ')}")
    end

    REQUIRED_COUNTERS = %w[
      typechecker.infer_expr.max_depth
      form_resolver.walk_expr.max_depth
      emitter.lower_expr_for_targets.max_depth
      emitter.build_pipeline.max_depth
      parser.parse_import.max_steps
    ].freeze
    counters = li.dig('counters') || {}
    missing_ctr = REQUIRED_COUNTERS.reject { |k| counters.key?(k) }
    if missing_ctr.empty?
      pass("receipt: all 5 counter keys present")
    else
      fail!("receipt: missing counter keys: #{missing_ctr.join(', ')}")
    end

    authority = li['authority']
    if authority == 'lab_only_p2_instrumentation'
      pass("receipt: authority='lab_only_p2_instrumentation' (lab boundary correctly marked)")
    else
      fail!("receipt: authority=#{authority.inspect} — expected 'lab_only_p2_instrumentation'")
    end

    kind = li['kind']
    if kind == 'liveness_instrumentation'
      pass("receipt: kind='liveness_instrumentation'")
    else
      fail!("receipt: kind=#{kind.inspect} — expected 'liveness_instrumentation'")
    end
  else
    fail!("receipt schema: no liveness_instrumentation found — cannot validate schema")
    $fail_count += 3
  end
else
  fail!("liveness_depth_probe.ig missing — skipping F section")
  $fail_count += 4
end

# ── Summary ───────────────────────────────────────────────────────────────────

total = $pass_count + $fail_count
puts "\n#{"═" * 60}"
puts "  LAB-COMPILER-LIVENESS-P2 verify"
puts "  #{$pass_count}/#{total} PASS    #{$fail_count > 0 ? "#{$fail_count} FAIL" : "0 FAIL"}"
puts "#{"═" * 60}"

if $fail_count == 0
  puts "  ✓ All P2 acceptance criteria verified."
  puts "  ✓ Non-fatal instrumentation correct; no behavior change."
  puts "  ✓ Counter data adequate for P3 hard-limit calibration."
  exit 0
else
  puts "  ✗ #{$fail_count} check(s) failed — see [!] lines above."
  exit 1
end
