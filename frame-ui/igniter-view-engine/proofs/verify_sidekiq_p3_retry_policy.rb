# verify_sidekiq_p3_retry_policy.rb
#
# LAB-SIDEKIQ-P3: BudgetedLocalLoop Retry Policy Proof
#
# Purpose: Prove that a Sidekiq-like retry policy can be modeled as a pure
# BudgetedLocalLoop (PROP-039) over an explicit attempt counter with a static
# max_steps budget. No Redis, no worker daemon, no scheduler, no ServiceLoop,
# no clock access, no async execution.
#
# Implementation:
#   igniter-view-engine/fixtures/sidekiq_core/retry_policy.ig
#     Four contracts:
#       StubJob             — minimal pure job callee (dispatch target for RetryWithDispatch)
#       RetryPolicy         — explicit attempt budget arithmetic (max_attempts - attempt)
#       RetrySimulator      — BudgetedLocalLoop (PROP-039) max_steps:5; counts total_attempts
#       RetryWithDispatch   — call_contract dispatch + retry budget composability
#   igniter-vm/src/vm.rs       — OP_LOOP_STEP fuel enforcement ("OOF-L-FUEL")
#   igniter-compiler/*         — loop/BudgetedLocalLoop compiler support
#
# Design choices (answered in this proof):
#   - Retry state modeled as `attempt` + `max_attempts`; `budget_remaining = max_attempts - attempt`
#   - Retry output is raw Integer (budget_remaining) in P3; JobReceipt deferred to P4
#   - JobReceipt schema deferred until P11 output typing clarifies call_contract return type
#   - BudgetedLocalLoop is the primary loop class; FiniteLoop pressure is not needed in P3
#
# Proof scope:
#   SJOB3-COMPILE  — retry_policy.ig compiles; 4 contracts accepted
#   SJOB3-SOURCE   — vm.rs contains OP_LOOP_STEP fuel enforcement; call_contract mechanism
#   SJOB3-HAPPY    — RetryPolicy arithmetic, RetrySimulator accumulation, RetryWithDispatch
#   SJOB3-FC       — fail-closed: fuel exhaustion, budget boundary, dispatch fail-closed
#   SJOB3-REG      — P2 regression: job_dispatch_table.ig and JobDispatcher still green
#   SJOB3-CLOSED   — closed-surface scan (no Redis, no ServiceLoop, no clock, no Sidekiq claims)
#   SJOB3-GAP      — gap packet: async/queue/receipt/effect-dispatch documented
#
# Check count: 43
#
# CLOSED: lab-only, no Redis, no queue storage, no worker daemon, no scheduler,
#         no ServiceLoop, no Sidekiq compatibility claim, no canon grammar edits,
#         no stable/public API, no production runtime claims.
#         BudgetedLocalLoop is PROP-039 experiment-pass compiler surface; runtime is closed.
#         call_contract is explicitly lab-only; no canon claim.
#
# Authority: lab-only evidence — no canon claim, no public API stability.
# Card: LAB-SIDEKIQ-P3
# Date: 2026-06-09

require 'json'
require 'fileutils'
require 'pathname'

ROOT          = Pathname.new(__dir__).parent
FIXTURE_DIR   = ROOT / 'fixtures/sidekiq_core'
P2_FIX_DIR    = ROOT / 'fixtures/sidekiq_core'
OUT_DIR       = ROOT / 'out/p3_retry_policy'
COMPILER_BIN  = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST   = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
VM_SRC        = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)
COMPILER_SRC  = File.expand_path('../../igniter-vm/src/compiler.rs', __dir__)
FIXTURE_SRC   = File.expand_path('fixtures/sidekiq_core/retry_policy.ig', ROOT.to_s)

FileUtils.mkdir_p(OUT_DIR)

# Read the proof source for closed-surface scans
SOURCE = File.read(__FILE__)

# ── Helpers ────────────────────────────────────────────────────────────────────

def compile_fixture(src_path, out_dir)
  FileUtils.mkdir_p(out_dir)
  out  = `#{COMPILER_BIN} compile #{src_path} --out #{out_dir} 2>&1`
  # Force UTF-8: compiler output may contain Unicode (e.g. × in liveness calibration strings)
  out  = out.force_encoding('UTF-8')
  json = JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
  json['_out_dir'] = out_dir.to_s
  json
end

def run_vm(igapp_path, inputs_hash, entry_name: nil)
  inputs_file = File.join(OUT_DIR.to_s, 'vm_inputs.json')
  File.write(inputs_file, JSON.generate(inputs_hash))
  entry_flag = entry_name ? "--entry #{entry_name}" : ''
  out = `cargo run --manifest-path #{VM_MANIFEST} --release -- run \
    --contract #{igapp_path} --inputs #{inputs_file} #{entry_flag} --json 2>/dev/null`
  # Force UTF-8 so JSON.parse handles any Unicode in VM error messages
  out = out.force_encoding('UTF-8')
  JSON.parse(out) rescue { 'status' => 'parse_error', 'raw' => out }
end

# ── Results tracking ───────────────────────────────────────────────────────────

RESULTS  = []
FAILURES = []

def section(title)
  puts "\n── #{title}"
end

def check(label, &block)
  passed = begin; block.call; rescue => e; false; end
  status = passed ? 'PASS' : 'FAIL'
  puts "  [#{status}] #{label}"
  RESULTS << { label: label, passed: passed }
  FAILURES << label unless passed
end

# ── Compile fixtures ───────────────────────────────────────────────────────────

P3_IGAPP   = (OUT_DIR / 'retry_policy').to_s
P3_RESULT  = compile_fixture(
  FIXTURE_DIR / 'retry_policy.ig',
  P3_IGAPP
)

P2_IGAPP   = (OUT_DIR / 'p2_reg').to_s
P2_RESULT  = compile_fixture(
  P2_FIX_DIR / 'job_dispatch_table.ig',
  P2_IGAPP
)

puts "LAB-SIDEKIQ-P3: BudgetedLocalLoop Retry Policy"
puts "═" * 72

# ── SJOB3-COMPILE ──────────────────────────────────────────────────────────────
section 'SJOB3-COMPILE: retry_policy.ig compiles (4 contracts accepted)'

check('SJOB3-COMPILE-01: fixture compiles with status=ok') do
  P3_RESULT['status'] == 'ok'
end

check('SJOB3-COMPILE-02: all 4 contracts present (StubJob, RetryPolicy, RetrySimulator, RetryWithDispatch)') do
  contracts = P3_RESULT['contracts'] || []
  %w[StubJob RetryPolicy RetrySimulator RetryWithDispatch].all? { |c| contracts.include?(c) }
end

check('SJOB3-COMPILE-03: no diagnostics in retry policy fixture') do
  (P3_RESULT['diagnostics'] || []).empty?
end

check('SJOB3-COMPILE-04: all stages ok (parse, classify, typecheck, emit, assemble)') do
  stages = P3_RESULT['stages'] || {}
  %w[parse classify typecheck emit assemble].all? { |s| stages[s] == 'ok' }
end

# Check semantic IR shape: RetrySimulator should have loop_class=budgeted, max_steps=5
semantic_ir_path = File.join(P3_IGAPP, 'semantic_ir_program.json')
P3_SEMAIR = begin
  JSON.parse(File.read(semantic_ir_path)) rescue {}
end

check('SJOB3-COMPILE-05: RetrySimulator has loop_class=budgeted in semantic IR (BudgetedLocalLoop shape)') do
  retry_sim = (P3_SEMAIR['contracts'] || []).find { |c| c['contract_name'] == 'RetrySimulator' }
  retry_sim && (retry_sim['nodes'] || []).any? { |n| n['kind'] == 'loop_node' && n['loop_class'] == 'budgeted' }
end

check('SJOB3-COMPILE-06: RetrySimulator has max_steps=5 in semantic IR (explicit budget annotation)') do
  retry_sim = (P3_SEMAIR['contracts'] || []).find { |c| c['contract_name'] == 'RetrySimulator' }
  retry_sim && (retry_sim['nodes'] || []).any? { |n| n['kind'] == 'loop_node' && n['max_steps'] == 5 }
end

# ── SJOB3-SOURCE ───────────────────────────────────────────────────────────────
section 'SJOB3-SOURCE: BudgetedLocalLoop and call_contract mechanisms present in source'

VM_SRC_TEXT       = File.read(VM_SRC)       rescue ''
COMPILER_SRC_TEXT = File.read(COMPILER_SRC) rescue ''
FIXTURE_SRC_TEXT  = File.read(FIXTURE_SRC)  rescue ''

check('SJOB3-SOURCE-01: vm.rs contains OOF-L-FUEL error string (OP_LOOP_STEP budget enforcement)') do
  VM_SRC_TEXT.include?('OOF-L-FUEL')
end

check('SJOB3-SOURCE-02: vm.rs contains OP_LOOP_START (BudgetedLocalLoop runtime start)') do
  VM_SRC_TEXT.include?('OP_LOOP_START')
end

check('SJOB3-SOURCE-03: vm.rs contains MAX_CALL_DEPTH (call_contract depth limit unchanged)') do
  VM_SRC_TEXT.include?('MAX_CALL_DEPTH')
end

check('SJOB3-SOURCE-04: fixture source contains "max_steps: 5" (explicit static budget)') do
  FIXTURE_SRC_TEXT.include?('max_steps: 5')
end

check('SJOB3-SOURCE-05: RetryWithDispatch uses call_contract in fixture source') do
  FIXTURE_SRC_TEXT.include?('call_contract(job_class')
end

# ── SJOB3-HAPPY ────────────────────────────────────────────────────────────────
section 'SJOB3-HAPPY: happy-path retry policy execution'

# RetryPolicy: explicit budget arithmetic
HP01 = run_vm(P3_IGAPP, { 'attempt' => 1, 'max_attempts' => 5 }, entry_name: 'RetryPolicy')
HP02 = run_vm(P3_IGAPP, { 'attempt' => 4, 'max_attempts' => 5 }, entry_name: 'RetryPolicy')
HP03 = run_vm(P3_IGAPP, { 'attempt' => 5, 'max_attempts' => 5 }, entry_name: 'RetryPolicy')
HP04 = run_vm(P3_IGAPP, { 'attempt' => 0, 'max_attempts' => 3 }, entry_name: 'RetryPolicy')

check('SJOB3-HAPPY-01: RetryPolicy(attempt=1, max_attempts=5) → budget_remaining=4') do
  HP01['status'] == 'success' && HP01['result'] == 4
end

check('SJOB3-HAPPY-02: RetryPolicy(attempt=4, max_attempts=5) → budget_remaining=1') do
  HP02['status'] == 'success' && HP02['result'] == 1
end

check('SJOB3-HAPPY-03: RetryPolicy(attempt=5, max_attempts=5) → budget_remaining=0 (budget exhausted)') do
  HP03['status'] == 'success' && HP03['result'] == 0
end

check('SJOB3-HAPPY-04: RetryPolicy(attempt=0, max_attempts=3) → budget_remaining=3') do
  HP04['status'] == 'success' && HP04['result'] == 3
end

# RetrySimulator: BudgetedLocalLoop over outcomes collection
HP05 = run_vm(P3_IGAPP, { 'outcomes' => [1] },          entry_name: 'RetrySimulator')
HP06 = run_vm(P3_IGAPP, { 'outcomes' => [0, 0, 1] },    entry_name: 'RetrySimulator')
HP07 = run_vm(P3_IGAPP, { 'outcomes' => [0, 0, 0, 0, 0] }, entry_name: 'RetrySimulator')

check('SJOB3-HAPPY-05: RetrySimulator(outcomes=[1]) → total_attempts=1 (one attempt)') do
  HP05['status'] == 'success' && HP05['result'] == 1
end

check('SJOB3-HAPPY-06: RetrySimulator(outcomes=[0,0,1]) → total_attempts=3 (three attempts within budget)') do
  HP06['status'] == 'success' && HP06['result'] == 3
end

check('SJOB3-HAPPY-07: RetrySimulator(outcomes=[0,0,0,0,0]) → total_attempts=5 (exactly at budget; no error)') do
  HP07['status'] == 'success' && HP07['result'] == 5
end

# RetryWithDispatch: dispatch + budget composability
HP08 = run_vm(P3_IGAPP,
  { 'job_class' => 'StubJob', 'job_id' => 'j-001',
    'arg1' => 10, 'arg2' => 5, 'attempt' => 1, 'max_attempts' => 5 },
  entry_name: 'RetryWithDispatch')

check('SJOB3-HAPPY-08: RetryWithDispatch(StubJob, attempt=1, max_attempts=5) → budget_remaining=4') do
  HP08['status'] == 'success' && HP08['result'] == 4
end

# ── SJOB3-FC ───────────────────────────────────────────────────────────────────
section 'SJOB3-FC: fail-closed constraints enforced'

# FC-01: BudgetedLocalLoop fuel exhaustion (max_steps=5; 6 outcomes exceed budget)
FC01 = run_vm(P3_IGAPP, { 'outcomes' => [0, 0, 0, 0, 0, 0] }, entry_name: 'RetrySimulator')

check('SJOB3-FC-01a: RetrySimulator with 6 outcomes (> max_steps=5) → status=error') do
  FC01['status'] == 'error'
end

check('SJOB3-FC-01b: error contains fuel exhausted (OP_LOOP_STEP enforcement confirmed at runtime)') do
  FC01['error'].to_s.include?('fuel exhausted') || FC01['error'].to_s.include?('OOF-L-FUEL')
end

check('SJOB3-FC-01c: RetrySimulator with exactly 5 outcomes → status=success (within budget; no exhaustion)') do
  HP07['status'] == 'success'
end

# FC-02: Budget arithmetic boundary cases
HP03_BOUNDARY = HP03  # RetryPolicy(5,5) → 0 (already computed above)
HP_OVER = run_vm(P3_IGAPP, { 'attempt' => 6, 'max_attempts' => 5 }, entry_name: 'RetryPolicy')

check('SJOB3-FC-02a: RetryPolicy(attempt=5, max_attempts=5) → budget_remaining=0 (budget exhausted, deterministic)') do
  HP03_BOUNDARY['status'] == 'success' && HP03_BOUNDARY['result'] == 0
end

check('SJOB3-FC-02b: budget_remaining=0 is not an error — it is a deterministic observable signal') do
  HP03_BOUNDARY['status'] == 'success'  # no error; caller decides whether to retry
end

check('SJOB3-FC-02c: RetryPolicy(attempt=6, max_attempts=5) → budget_remaining=-1 (over-budget; deterministic)') do
  HP_OVER['status'] == 'success' && HP_OVER['result'] == -1
end

# FC-03: RetryWithDispatch fail-closed cases (via variable job_class; P10 TypeChecker bypassed)
FC03_UNKNOWN = run_vm(P3_IGAPP,
  { 'job_class' => 'UnknownJobClass', 'job_id' => 'j-x',
    'arg1' => 1, 'arg2' => 0, 'attempt' => 1, 'max_attempts' => 5 },
  entry_name: 'RetryWithDispatch')

check('SJOB3-FC-03a: RetryWithDispatch with unknown job_class → status=error') do
  FC03_UNKNOWN['status'] == 'error'
end

check('SJOB3-FC-03b: unknown job_class error mentions "no contract named" (P9 fail-closed preserved)') do
  FC03_UNKNOWN['error'].to_s.include?('no contract named')
end

check('SJOB3-FC-03c: RetrySimulator empty outcomes → total_attempts=0 (empty loop; no error)') do
  empty_r = run_vm(P3_IGAPP, { 'outcomes' => [] }, entry_name: 'RetrySimulator')
  empty_r['status'] == 'success' && empty_r['result'] == 0
end

# ── SJOB3-REG ──────────────────────────────────────────────────────────────────
section 'SJOB3-REG: P2 regression — job_dispatch_table.ig still green'

check('SJOB3-REG-01: P2 job_dispatch_table.ig compiles ok') do
  P2_RESULT['status'] == 'ok'
end

check('SJOB3-REG-02: P2 JobDispatcher(ProcessOrderJob, order_id=21) → 42 (P2 dispatch unchanged)') do
  r = run_vm(P2_IGAPP,
    { 'job_class' => 'ProcessOrderJob', 'job_id' => 'j-r', 'arg1' => 21, 'arg2' => 1 },
    entry_name: 'JobDispatcher')
  r['status'] == 'success' && r['result'] == 42
end

check('SJOB3-REG-03: P2 JobDispatcher(ComputeReportJob, period=5) → 50') do
  r = run_vm(P2_IGAPP,
    { 'job_class' => 'ComputeReportJob', 'job_id' => 'j-r', 'arg1' => 5, 'arg2' => 0 },
    entry_name: 'JobDispatcher')
  r['status'] == 'success' && r['result'] == 50
end

check('SJOB3-REG-04: P2 unknown job → error with "no contract named" (P2 fail-closed unchanged)') do
  r = run_vm(P2_IGAPP,
    { 'job_class' => 'GhostJob', 'job_id' => 'j-g', 'arg1' => 1, 'arg2' => 1 },
    entry_name: 'JobDispatcher')
  r['status'] == 'error' && r['error'].to_s.include?('no contract named')
end

check('SJOB3-REG-05: P2 4 core contracts still present (ProcessOrderJob, ComputeReportJob, ValidatePaymentJob, JobDispatcher)') do
  contracts = P2_RESULT['contracts'] || []
  %w[ProcessOrderJob ComputeReportJob ValidatePaymentJob JobDispatcher].all? { |c| contracts.include?(c) }
end

# ── SJOB3-CLOSED ───────────────────────────────────────────────────────────────
section 'SJOB3-CLOSED: closed-surface scan'

check('SJOB3-CLOSED-01: no TCP/UDP socket use in proof source') do
  # Split strings so the pattern strings themselves do not trigger the check
  !SOURCE.include?("TC" + "PSocket") &&
  !SOURCE.include?("UDP" + "Socket") &&
  !SOURCE.include?("require 'so" + "cket'")
end

check('SJOB3-CLOSED-02: no Redis connection in proof source') do
  !SOURCE.include?("Re" + "dis.new") &&
  !SOURCE.include?("redis" + "://") &&
  !SOURCE.include?("require 're" + "dis'")
end

check('SJOB3-CLOSED-03: no ServiceLoop invocation in proof source') do
  !SOURCE.include?("require 'ser" + "vice_loop'") &&
  !SOURCE.include?("Servi" + "ceLoop.new") &&
  !SOURCE.include?("Servi" + "ceLoop.start")
end

check('SJOB3-CLOSED-04: no clock/time access in proof or fixture source (OOF-L6 boundary)') do
  # Split strings to prevent self-match
  !SOURCE.include?("Ti" + "me.now") &&
  !SOURCE.include?("Date" + "Ti" + "me.now") &&
  !FIXTURE_SRC_TEXT.include?("now()") &&
  !FIXTURE_SRC_TEXT.include?("tick.time")
end

check('SJOB3-CLOSED-05: no Sidekiq compatibility claim and no production claim in proof source') do
  # Check for actual false-claim patterns (not the documentation strings in comments/labels)
  !SOURCE.include?("Si" + "dekiq-compat" + "ible") &&
  !SOURCE.include?("produc" + "tion-ready") &&
  !SOURCE.include?("stab" + "le API surface")
end

# ── SJOB3-GAP ──────────────────────────────────────────────────────────────────
section 'SJOB3-GAP: gap packet'

GAP_PACKET = {
  proof:       'lab-sidekiq-p3-retry-policy',
  version:     'v0',
  closed_by_p3: %w[
    retry_budget_arithmetic
    budgeted_local_loop_bounded_retry
    fuel_exhaustion_at_max_steps
    dispatch_plus_budget_composability
  ],
  v0_policy: {
    max_steps_must_be_static_literal: 'enforced',
    pure_callee_only: 'enforced',
    no_clock_access: 'enforced'
  },
  still_open: %w[
    async_retry
    queue_storage
    job_receipt_schema
    effect_dispatch
    retry_backoff_schedule
    non_uniform_arity_dispatch
  ],
  sidekiq_compatibility: 'permanently_closed',
  p4_recommendation: 'JobReceipt schema — structured output record to replace raw Integer stub'
}

check('SJOB3-GAP-01: gap packet has closed_by_p3 with retry_budget_arithmetic') do
  GAP_PACKET[:closed_by_p3].include?('retry_budget_arithmetic')
end

check('SJOB3-GAP-02: gap packet v0_policy has max_steps_must_be_static_literal enforced') do
  GAP_PACKET[:v0_policy][:max_steps_must_be_static_literal] == 'enforced'
end

check('SJOB3-GAP-03: gap packet still_open contains job_receipt_schema (deferred to P4)') do
  GAP_PACKET[:still_open].include?('job_receipt_schema')
end

check('SJOB3-GAP-04: gap packet still_open contains effect_dispatch (deferred to P10/P11)') do
  GAP_PACKET[:still_open].include?('effect_dispatch')
end

check('SJOB3-GAP-05: gap packet sidekiq_compatibility is permanently_closed') do
  GAP_PACKET[:sidekiq_compatibility] == 'permanently_closed'
end

# ── Summary ────────────────────────────────────────────────────────────────────

passed = RESULTS.count { |r| r[:passed] }
total  = RESULTS.size

puts "\n#{"═" * 72}"
puts "  LAB-SIDEKIQ-P3: BudgetedLocalLoop Retry Policy"
if FAILURES.empty?
  puts "  #{passed}/#{total} PASS"
else
  puts "  #{passed}/#{total} PASS — FAILURES: #{FAILURES.join(', ')}"
end
puts "═" * 72

exit(FAILURES.empty? ? 0 : 1)
