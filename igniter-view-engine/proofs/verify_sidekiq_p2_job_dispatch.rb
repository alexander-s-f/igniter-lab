# verify_sidekiq_p2_job_dispatch.rb
#
# LAB-SIDEKIQ-P2: Static Job Dispatch Table with Pure Job Contracts
#
# Purpose: Prove that call_contract dispatches to named job contracts by
# job_class string, enforcing arity and fail-closed errors, using the same
# dispatch table mechanism as LAB-RACK-P9 applied to a Sidekiq-like domain.
# No Redis, no worker daemon, no scheduler, no ServiceLoop, no async execution.
#
# Implementation:
#   igniter-view-engine/fixtures/sidekiq_core/job_dispatch_table.ig
#     Five contracts:
#       ProcessOrderJob   — order_id + order_id  (stub: doubles the value)
#       ComputeReportJob  — period * 10           (stub: report computation)
#       ValidatePaymentJob — amount + attempt     (stub: validation score)
#       JobDispatcher     — routes by job_class via call_contract(job_class, ...)
#       SelfDispatch      — calls itself (cycle detection test)
#   igniter-vm/src/vm.rs + compiler.rs + main.rs — LAB-RACK-P9 call_contract (unchanged)
#   igniter-compiler/src/typechecker.rs           — LAB-RACK-P9 fixes (unchanged)
#
# Proof scope:
#   SJOB-COMPILE    — fixture compiles; 5 contracts accepted
#   SJOB-SOURCE     — vm.rs/compiler.rs contain P9 call_contract mechanism
#   SJOB-HAPPY      — ProcessOrderJob/ComputeReportJob/ValidatePaymentJob dispatch
#   SJOB-FC         — all fail-closed constraints enforced:
#     FC-01 unknown job class → error (lists available)
#     FC-02 arity mismatch    → error (shows expected vs got)
#     FC-03 non-string first arg → OOF-TY0 at compile time
#     FC-04 effect callee blocked → error (modifier guard)
#     FC-05 self-dispatch cycle   → cycle error
#     FC-06 depth > 8 blocked     → max depth error
#   SJOB-REG        — P9 regression: multi_contract_caller.ig still green
#   SJOB-CLOSED     — closed-surface scan (no Redis, no ServiceLoop, no Sidekiq claims)
#   SJOB-GAP        — gap packet: async/queue/retry/effect-dispatch documented
#
# Proof axiom: PASS means the stated property holds.
# CLOSED: lab-only, no Redis, no queue storage, no worker daemon, no scheduler,
#         no ServiceLoop, no Sidekiq compatibility claim, no canon grammar edits,
#         no stable/public API, no production runtime claims.
#         call_contract is explicitly lab-only; no canon claim, no stable API.
#
# Authority: lab-only evidence — no canon claim, no stable API surface.
# Card: LAB-SIDEKIQ-P2
# Date: 2026-06-09

require 'json'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__).parent
FIXTURE_DIR  = ROOT / 'fixtures/sidekiq_core'
P9_FIX_DIR   = ROOT / 'fixtures/rack_core'
OUT_DIR      = ROOT / 'out/p2_job_dispatch'
COMPILER_BIN = File.expand_path('../../igniter-compiler/target/release/igniter_compiler', __dir__)
VM_MANIFEST  = File.expand_path('../../igniter-vm/Cargo.toml', __dir__)
VM_SRC       = File.expand_path('../../igniter-vm/src/vm.rs', __dir__)
COMPILER_SRC = File.expand_path('../../igniter-vm/src/compiler.rs', __dir__)

FileUtils.mkdir_p(OUT_DIR)

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

def compile_inline(source_str, label)
  dir = File.join(OUT_DIR.to_s, "inline_#{label}")
  FileUtils.mkdir_p(dir)
  src = File.join(dir, "#{label}.ig")
  File.write(src, source_str)
  compile_fixture(src, File.join(dir, 'igapp'))
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

JOB_IGAPP   = (OUT_DIR / 'job_dispatch').to_s
JOB_RESULT  = compile_fixture(
  FIXTURE_DIR / 'job_dispatch_table.ig',
  JOB_IGAPP
)

P9_IGAPP    = (OUT_DIR / 'p9_reg').to_s
P9_RESULT   = compile_fixture(
  P9_FIX_DIR / 'multi_contract_caller.ig',
  P9_IGAPP
)

# Inline fail-closed fixtures

NON_STRING_JOB_SRC = <<~IG
  module Test.NonStringJob

  pure contract NonStringJobClass {
    input  n : Integer
    compute result = call_contract(n, "jid", 1, 2)
    output result : Integer
  }
IG

ARITY_SHORT_SRC = <<~IG
  module Test.ArityShort

  pure contract ArityTarget {
    input  job_id  : String
    input  arg1    : Integer
    input  arg2    : Integer
    compute result = arg1 + arg2
    output result  : Integer
  }

  pure contract ShortDispatcher {
    input  job_id : String
    input  arg1   : Integer
    compute result = call_contract("ArityTarget", job_id, arg1)
    output result  : Integer
  }
IG

EFFECT_JOB_SRC = <<~IG
  module Test.EffectJob

  effect contract EffectWorker {
    input  job_id : String
    input  arg1   : Integer
    input  arg2   : Integer
    compute result = arg1 + arg2
    output result  : Integer
  }

  pure contract EffectJobDispatcher {
    input  job_id : String
    input  arg1   : Integer
    input  arg2   : Integer
    compute result = call_contract("EffectWorker", job_id, arg1, arg2)
    output result  : Integer
  }
IG

DEPTH_CHAIN_SRC = begin
  parts = (1..9).map do |i|
    callee = i < 9 ? "DJ#{i+1}" : "DJBase"
    "pure contract DJ#{i} {\n  input job_id : String\n  input arg1 : Integer\n  input arg2 : Integer\n  compute result = call_contract(\"#{callee}\", job_id, arg1, arg2)\n  output result : Integer\n}"
  end
  parts << "pure contract DJBase {\n  input job_id : String\n  input arg1 : Integer\n  input arg2 : Integer\n  compute result = arg1 + arg2\n  output result : Integer\n}"
  "module Test.DepthChain\n\n" + parts.join("\n\n")
end

# LAB-SIDEKIQ-P3 fix (2026-06-09):
# SelfDispatch was removed from job_dispatch_table.ig because the P10 TypeChecker now
# detects self-recursion via literal callee resolution at COMPILE TIME (OOF-TY0), not
# at VM runtime. SelfDispatch is tested below as a separate inline compile-time check.
SELF_DISPATCH_SRC = <<~IG
  module Test.SelfDispatch

  pure contract SelfDispatch {
    input  job_id  : String
    input  arg1    : Integer
    input  arg2    : Integer
    compute result = call_contract("SelfDispatch", job_id, arg1, arg2)
    output result  : Integer
  }
IG

NONSTR_RESULT  = compile_inline(NON_STRING_JOB_SRC, 'non_string_job')
ARITY_RESULT   = compile_inline(ARITY_SHORT_SRC,    'arity_short')
EFFECT_RESULT  = compile_inline(EFFECT_JOB_SRC,     'effect_job')
DEPTH_RESULT   = compile_inline(DEPTH_CHAIN_SRC,    'depth_chain_job')
SELF_RESULT    = compile_inline(SELF_DISPATCH_SRC,  'self_dispatch_job')

puts "LAB-SIDEKIQ-P2: Static Job Dispatch Table with Pure Job Contracts"
puts "═" * 72

# ── SJOB-COMPILE ──────────────────────────────────────────────────────────────
section 'SJOB-COMPILE: job_dispatch_table.ig compiles (4 contracts accepted)'

check('SJOB-COMPILE-01: fixture compiles with status=ok') do
  JOB_RESULT['status'] == 'ok'
end

check('SJOB-COMPILE-02: all 4 core contracts present in igapp') do
  # SelfDispatch removed (P10 TypeChecker now catches literal self-recursion at compile time).
  contracts = JOB_RESULT['contracts'] || []
  %w[ProcessOrderJob ComputeReportJob ValidatePaymentJob JobDispatcher].all? do |c|
    contracts.include?(c)
  end
end

check('SJOB-COMPILE-03: no diagnostics in job dispatch fixture') do
  (JOB_RESULT['diagnostics'] || []).empty?
end

check('SJOB-COMPILE-04: all stages ok (parse, classify, typecheck, emit, assemble)') do
  stages = JOB_RESULT['stages'] || {}
  %w[parse classify typecheck emit assemble].all? { |s| stages[s] == 'ok' }
end

check('SJOB-COMPILE-05: effect_job fixture rejected at compile time with OOF-TY0 (P10: effect callee detected via literal resolution)') do
  # P10 TypeChecker resolves literal callee "EffectWorker" statically and rejects at compile time.
  EFFECT_RESULT['status'] == 'oof' &&
    (EFFECT_RESULT['diagnostics'] || []).any? { |d| d['rule'] == 'OOF-TY0' }
end

check('SJOB-COMPILE-06: depth_chain fixture compiles ok (depth caught at VM not compile time)') do
  DEPTH_RESULT['status'] == 'ok'
end

# ── SJOB-SOURCE ───────────────────────────────────────────────────────────────
section 'SJOB-SOURCE: call_contract mechanism present in source files (LAB-RACK-P9 reuse)'

VM_SOURCE  = File.read(VM_SRC)
CC_SOURCE  = File.read(COMPILER_SRC)

check('SJOB-SOURCE-01: vm.rs contains DispatchEntry struct') do
  VM_SOURCE.include?('struct DispatchEntry')
end

check('SJOB-SOURCE-02: vm.rs contains call_contract dispatch arm') do
  VM_SOURCE.include?('"call_contract"')
end

check('SJOB-SOURCE-03: vm.rs contains __call_chain__ cycle detection') do
  VM_SOURCE.include?('__call_chain__')
end

check('SJOB-SOURCE-04: vm.rs contains MAX_CALL_DEPTH') do
  VM_SOURCE.include?('MAX_CALL_DEPTH')
end

check('SJOB-SOURCE-05: compiler.rs contains build_dispatch_entry') do
  CC_SOURCE.include?('build_dispatch_entry')
end

check('SJOB-SOURCE-06: vm.rs contains LAB-RACK-P9 annotation (P9 mechanism reused)') do
  VM_SOURCE.include?('LAB-RACK-P9')
end

# ── SJOB-HAPPY ────────────────────────────────────────────────────────────────
section 'SJOB-HAPPY: happy-path job dispatch'

# ProcessOrderJob: order_id=21, attempt=0 → 21+21=42
HAPPY_ORDER   = run_vm(JOB_IGAPP,
  { 'job_class' => 'ProcessOrderJob', 'job_id' => 'jid-1', 'arg1' => 21, 'arg2' => 0 },
  entry_name: 'JobDispatcher')

# ComputeReportJob: period=5, code=1 → 5*10=50
HAPPY_REPORT  = run_vm(JOB_IGAPP,
  { 'job_class' => 'ComputeReportJob', 'job_id' => 'jid-2', 'arg1' => 5, 'arg2' => 1 },
  entry_name: 'JobDispatcher')

# ComputeReportJob: period=3, code=2 → 3*10=30 (different period)
HAPPY_REPORT2 = run_vm(JOB_IGAPP,
  { 'job_class' => 'ComputeReportJob', 'job_id' => 'jid-3', 'arg1' => 3, 'arg2' => 2 },
  entry_name: 'JobDispatcher')

# ValidatePaymentJob: amount=100, attempt=1 → 100+1=101
HAPPY_PAY     = run_vm(JOB_IGAPP,
  { 'job_class' => 'ValidatePaymentJob', 'job_id' => 'jid-4', 'arg1' => 100, 'arg2' => 1 },
  entry_name: 'JobDispatcher')

# ValidatePaymentJob: amount=0, attempt=0 → 0+0=0
HAPPY_PAY0    = run_vm(JOB_IGAPP,
  { 'job_class' => 'ValidatePaymentJob', 'job_id' => 'jid-5', 'arg1' => 0, 'arg2' => 0 },
  entry_name: 'JobDispatcher')

# Direct job contract execution (bypassing dispatcher)
HAPPY_DIRECT  = run_vm(JOB_IGAPP,
  { 'job_id' => 'jid-d', 'order_id' => 7, 'attempt' => 0 },
  entry_name: 'ProcessOrderJob')

check('SJOB-HAPPY-01: ProcessOrderJob via JobDispatcher(order_id=21) → 42') do
  HAPPY_ORDER['status'] == 'success' && HAPPY_ORDER['result'] == 42
end

check('SJOB-HAPPY-02: ComputeReportJob via JobDispatcher(period=5) → 50') do
  HAPPY_REPORT['status'] == 'success' && HAPPY_REPORT['result'] == 50
end

check('SJOB-HAPPY-03: ComputeReportJob via JobDispatcher(period=3) → 30') do
  HAPPY_REPORT2['status'] == 'success' && HAPPY_REPORT2['result'] == 30
end

check('SJOB-HAPPY-04: ValidatePaymentJob via JobDispatcher(amount=100,attempt=1) → 101') do
  HAPPY_PAY['status'] == 'success' && HAPPY_PAY['result'] == 101
end

check('SJOB-HAPPY-05: ValidatePaymentJob via JobDispatcher(amount=0,attempt=0) → 0') do
  HAPPY_PAY0['status'] == 'success' && HAPPY_PAY0['result'] == 0
end

check('SJOB-HAPPY-06: ProcessOrderJob executed directly (bypassing dispatcher) → 14') do
  HAPPY_DIRECT['status'] == 'success' && HAPPY_DIRECT['result'] == 14
end

check('SJOB-HAPPY-07: all 3 job classes dispatch without error') do
  [HAPPY_ORDER, HAPPY_REPORT, HAPPY_PAY].all? { |r| r['status'] == 'success' }
end

# ── SJOB-FC ───────────────────────────────────────────────────────────────────
section 'SJOB-FC: all fail-closed constraints enforced'

# FC-01: unknown job class
FC01 = run_vm(JOB_IGAPP,
  { 'job_class' => 'NonExistentJob', 'job_id' => 'jid-x', 'arg1' => 1, 'arg2' => 0 },
  entry_name: 'JobDispatcher')

check('SJOB-FC-01a: unknown job class → status=error') do
  FC01['status'] == 'error'
end

check('SJOB-FC-01b: unknown job class error mentions "no contract named"') do
  FC01['error'].to_s.include?('no contract named')
end

check('SJOB-FC-01c: unknown job class error lists available job contracts') do
  err = FC01['error'].to_s
  err.include?('available') && err.include?('ProcessOrderJob')
end

# FC-02: arity mismatch
FC02 = run_vm(ARITY_RESULT['igapp_path'] || ARITY_RESULT['_out_dir'],
  { 'job_id' => 'jid-a', 'arg1' => 5 },
  entry_name: 'ShortDispatcher')

check('SJOB-FC-02a: arity mismatch → status=error') do
  FC02['status'] == 'error'
end

check('SJOB-FC-02b: arity mismatch error mentions "expects" and "got"') do
  err = FC02['error'].to_s
  err.include?('expects') && err.include?('got')
end

check('SJOB-FC-02c: arity mismatch error names the callee contract') do
  FC02['error'].to_s.include?('ArityTarget')
end

# FC-03: non-string first arg → compile-time OOF-TY0
check('SJOB-FC-03a: non-string job_class → compiler status=oof') do
  NONSTR_RESULT['status'] == 'oof'
end

check('SJOB-FC-03b: non-string job_class → OOF-TY0 diagnostic present') do
  diags = NONSTR_RESULT['diagnostics'] || []
  diags.any? { |d| d['rule'] == 'OOF-TY0' }
end

check('SJOB-FC-03c: non-string job_class → diagnostic mentions "String"') do
  diags = NONSTR_RESULT['diagnostics'] || []
  diags.any? { |d| d['message'].to_s.include?('String') }
end

# FC-04: effect callee rejected at COMPILE TIME (P10 TypeChecker literal resolution)
# call_contract("EffectWorker", ...) with a literal callee is resolved statically;
# OOF-TY0 fires because EffectWorker is not pure.
check('SJOB-FC-04a: effect callee → compile-time OOF-TY0 (P10 literal callee resolution)') do
  EFFECT_RESULT['status'] == 'oof'
end

check('SJOB-FC-04b: effect callee compile error mentions "not pure"') do
  (EFFECT_RESULT['diagnostics'] || []).any? { |d| d['message'].to_s.include?('not pure') }
end

check('SJOB-FC-04c: effect callee compile error names the job contract') do
  (EFFECT_RESULT['diagnostics'] || []).any? { |d| d['message'].to_s.include?('EffectWorker') }
end

# FC-05: self-dispatch cycle rejected at COMPILE TIME (P10 TypeChecker literal resolution)
# call_contract("SelfDispatch", ...) inside SelfDispatch is detected as self-recursion
# by the TypeChecker via literal callee resolution. OOF-TY0 fires at compile time.
# (Previously a VM-level cycle error; P10 moves this check earlier.)
check('SJOB-FC-05a: self-dispatch cycle → compile-time OOF-TY0 (P10 literal callee resolution)') do
  SELF_RESULT['status'] == 'oof'
end

check('SJOB-FC-05b: self-dispatch compile error mentions "self-recursion"') do
  (SELF_RESULT['diagnostics'] || []).any? { |d| d['message'].to_s.include?('self-recursion') }
end

check('SJOB-FC-05c: self-dispatch compile error mentions SelfDispatch') do
  (SELF_RESULT['diagnostics'] || []).any? { |d| d['message'].to_s.include?('SelfDispatch') }
end

# FC-06: depth > 8 blocked
FC06 = run_vm(DEPTH_RESULT['igapp_path'] || DEPTH_RESULT['_out_dir'],
  { 'job_id' => 'jid-d', 'arg1' => 1, 'arg2' => 0 },
  entry_name: 'DJ1')

check('SJOB-FC-06a: depth > 8 → status=error') do
  FC06['status'] == 'error'
end

check('SJOB-FC-06b: depth > 8 error mentions "max call depth"') do
  FC06['error'].to_s.include?('max call depth')
end

check('SJOB-FC-06c: depth > 8 error states the limit (8)') do
  FC06['error'].to_s.include?('8')
end

# ── SJOB-REG ──────────────────────────────────────────────────────────────────
section 'SJOB-REG: P9 regression — multi_contract_caller.ig still green'

check('SJOB-REG-01: multi_contract_caller.ig compiles ok') do
  P9_RESULT['status'] == 'ok'
end

check('SJOB-REG-02: CallerDoubler/CallerSmall/CallerGate all present') do
  contracts = P9_RESULT['contracts'] || []
  %w[CallerDoubler CallerSmall CallerGate].all? { |c| contracts.include?(c) }
end

REG_DBL = run_vm(P9_IGAPP, { 'n' => 10 }, entry_name: 'CallerDoubler')
check('SJOB-REG-03: P9 CallerDoubler(n=10) → 21 (P9 unchanged)') do
  REG_DBL['status'] == 'success' && REG_DBL['result'] == 21
end

REG_SMALL = run_vm(P9_IGAPP, { 'n' => 50 }, entry_name: 'CallerSmall')
check('SJOB-REG-04: P9 CallerSmall(n=50) → true') do
  REG_SMALL['status'] == 'success' && REG_SMALL['result'] == true
end

REG_GATE = run_vm(P9_IGAPP, { 'method' => 'GET', 'path' => '/' }, entry_name: 'CallerGate')
check('SJOB-REG-05: P9 CallerGate(GET, /) → 200') do
  REG_GATE['status'] == 'success' && REG_GATE['result'] == 200
end

# ── SJOB-CLOSED ───────────────────────────────────────────────────────────────
section 'SJOB-CLOSED: closed-surface scan'

SOURCE = File.read(__FILE__)

check('SJOB-CLOSED-01: no TCP/UDP socket use in proof source') do
  !SOURCE.include?('TCPSo' + 'cket') &&
  !SOURCE.include?('UDPSo' + 'cket') &&
  !SOURCE.include?("require 'so" + "cket'")
end

check('SJOB-CLOSED-02: no network I/O calls in proof source') do
  !SOURCE.include?('Net::HT' + 'TP') &&
  !SOURCE.include?("require 'net/ht" + "tp'")
end

check('SJOB-CLOSED-03: no Redis connection in proof source') do
  !SOURCE.include?("require 'red" + "is'") &&
  !SOURCE.include?('Redi' + 's.new') &&
  !SOURCE.include?('redi' + 's://')
end

check('SJOB-CLOSED-04: no ServiceLoop require or live invocation in proof source') do
  # Gap packet mentions ServiceLoop in documentation (expected); check only for actual
  # requires or method calls that would invoke a runtime service loop.
  !SOURCE.include?("require 'ser" + "vice_loop'") &&
  !SOURCE.include?("Servi" + "ceLoop.new") &&
  !SOURCE.include?("Servi" + "ceLoop.start") &&
  !SOURCE.include?("Servi" + "ceLoop.run")
end

check('SJOB-CLOSED-05: no production API or Sidekiq compatibility claims') do
  !SOURCE.include?('stable-' + 'API') &&
  !SOURCE.include?('Sidekiq-comp' + 'atible') &&
  !SOURCE.include?('public' + '-runtime')
end

check('SJOB-CLOSED-06: call_contract is lab-only — proof makes no canon claim') do
  !SOURCE.include?('canon' + ' job dispatch') &&
  !SOURCE.include?('stable' + ' dispatch')
end

# ── SJOB-GAP ──────────────────────────────────────────────────────────────────
section 'SJOB-GAP: gap packet'

GAP_PACKET = {
  card:      'LAB-SIDEKIQ-P2',
  date:      '2026-06-09',
  authority: 'lab-only — no canon claim, no stable API surface, no Sidekiq compatibility',

  closed_by_p2: {
    job_dispatch_table: {
      description: 'call_contract("JobClassName", job_id, arg1, arg2) dispatches to a ' \
                   'named pure job contract in the same igapp at VM runtime',
      mechanism:   'Reuses LAB-RACK-P9 call_contract dispatch table (DispatchEntry, ' \
                   'MAX_CALL_DEPTH=8, __call_chain__ cycle detection). No new VM/compiler changes.',
      fail_closed: 'unknown job class, arity mismatch, non-string arg, effect callee, ' \
                   'self-dispatch cycle, depth > 8 all error clearly'
    }
  },

  v0_policy: {
    pure_callee_only: {
      status: 'enforced',
      detail: 'Only pure job contracts may be dispatched; effect/privileged callee → error. ' \
              'This is the correct v0 constraint — real Sidekiq jobs are usually effectful, ' \
              'creating pressure for effect-callee dispatch design in P3.'
    },
    no_cycles_or_recursion: {
      status: 'enforced',
      detail: 'Call chain tracked in temporal_context; any repeat name → error. ' \
              'Prevents infinite job chains.'
    },
    max_depth_8: {
      status: 'enforced',
      detail: 'MAX_CALL_DEPTH=8; exceeding → clear error.'
    }
  },

  still_open: {
    async_execution: {
      status: 'deferred',
      detail: 'call_contract is synchronous; real job execution is async. ' \
              'Async dispatch requires ServiceLoop (PROP-037, Stage 4+). Permanently closed for v0.'
    },
    queue_storage: {
      status: 'deferred',
      detail: 'No StorageCapability type; no Redis; no persistent queue. ' \
              'Dynamic enqueue/dequeue requires StorageCapability design (new lab track needed).'
    },
    retry_policy: {
      status: 'deferred',
      detail: 'BudgetedLocalLoop retry is the P3 candidate. ' \
              'max_steps = max_attempts; decreases fuel = attempt counter.'
    },
    job_receipt_schema: {
      status: 'deferred',
      detail: 'call_contract returns Integer stub in P2. ' \
              'Structured JobReceipt record type (job_id, status, elapsed_ms, output) is P3/P4.'
    },
    effect_job_dispatch: {
      status: 'deferred',
      detail: 'Pure-callee-only in v0. Real Sidekiq jobs are almost always effectful. ' \
              'Effect-callee dispatch design requires understanding how capability grants ' \
              'thread through the dispatch chain — P3 design preflight candidate.'
    },
    scheduler: {
      status: 'permanently_closed_v0',
      detail: 'Clock authority and ServiceLoop required. PROP-037 + Stage 4+.'
    },
    worker_daemon: {
      status: 'permanently_closed_v0',
      detail: 'No runtime worker loop. ServiceLoop is PROP-037 territory.'
    },
    sidekiq_compatibility: {
      status: 'permanently_closed',
      detail: 'Not a goal at any stage. Sidekiq is reference architecture for language pressure only.'
    }
  },

  p3_candidates: [
    'P3a: JobReceipt schema — structured output record replacing Integer stub',
    'P3b: BudgetedLocalLoop retry policy — attempt counter + max_attempts proof',
    'P3c: Effect callee design preflight — capability grant threading design'
  ],

  deferred: 'async execution; queue storage; retry policy; job receipt schema; ' \
            'effect dispatch design; scheduler; worker daemon',
  next_route: 'LAB-SIDEKIQ-P3: choose from P3a (JobReceipt), P3b (retry policy), or P3c (effect design)'
}.freeze

check('SJOB-GAP-01: gap packet has closed_by_p2 with job_dispatch_table') do
  GAP_PACKET[:closed_by_p2].key?(:job_dispatch_table)
end

check('SJOB-GAP-02: gap packet v0_policy has pure_callee_only enforced') do
  GAP_PACKET[:v0_policy][:pure_callee_only][:status] == 'enforced'
end

check('SJOB-GAP-03: gap packet still_open contains async_execution') do
  GAP_PACKET[:still_open].key?(:async_execution)
end

check('SJOB-GAP-04: gap packet still_open contains queue_storage') do
  GAP_PACKET[:still_open].key?(:queue_storage)
end

check('SJOB-GAP-05: gap packet still_open contains retry_policy') do
  GAP_PACKET[:still_open].key?(:retry_policy)
end

check('SJOB-GAP-06: gap packet sidekiq_compatibility is permanently_closed') do
  GAP_PACKET[:still_open][:sidekiq_compatibility][:status] == 'permanently_closed'
end

# ── Summary ───────────────────────────────────────────────────────────────────
total   = RESULTS.size
passed  = RESULTS.count { |r| r[:passed] }
failed  = total - passed

puts "\n#{'═' * 72}"
puts "  LAB-SIDEKIQ-P2: Static Job Dispatch Table with Pure Job Contracts"
puts "  #{passed}/#{total} PASS#{failed > 0 ? " — FAILURES: #{FAILURES.join(', ')}" : ''}"
puts "#{'═' * 72}"

exit(failed > 0 ? 1 : 0)
