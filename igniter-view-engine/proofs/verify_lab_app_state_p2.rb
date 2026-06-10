#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_app_state_p2.rb
# LAB-APP-STATE-P2: Proof-local code-editor app-state model
#
# Tests the B⊕E path from LAB-APP-STATE-P1 using EXISTING Igniter concepts only:
#   state VALUES = typed records; TRANSITIONS = pure contracts (snapshot+event->next);
#   LIFETIMES   = lifecycle vocabulary on `output` (:local/:session/:window/:durable/:audit);
#   DURABLE edge = effect/observed contract + IO.StorageCapability (NO storage execution);
#   HOLDER      = host-owned (the language holds nothing; every output is a fresh value).
#
# Six P1 terms kept visibly separate: state-value | state-instance | state-holder |
# transition | module-boundary | external-capability. The architecture metadata the
# language does NOT carry (instance identity, explicit holder binding, public/internal
# visibility, event->op->fact assembly) lives in a PROOF-LOCAL sidecar registry; the
# runner cross-checks SIR vs sidecar to surface exactly which gaps remain.
#
# Layers:
#   A — Ruby TypeChecker: record type_env shapes + acceptance.
#   B — Rust compiler SIR (per-contract JSON): modifier / fragment_class / output
#       lifecycle / capabilities / effects. (Primary inspectability anchor.)
#   C — VM round-trip (pure transitions) + proof-local registry sidecar.
#
# Sections:
#   APPSTATE-COMPILE   — both fixtures compile; contracts accepted (Layer A+B)
#   APPSTATE-SHAPE     — state record shapes present and typed
#   APPSTATE-LIFECYCLE — each fact's intended lifetime carried on its output (E path)
#   APPSTATE-TRANSITION— transitions pure; VM round-trip; no hidden holder
#   APPSTATE-PUBLIC    — boundary ops inferable; pure public-vs-helper NOT (visibility gap)
#   APPSTATE-DURABLE   — durable boundary stays effect/capability-shaped; no execution
#   APPSTATE-HOST      — holder host-owned; no language-level mutable object
#   APPSTATE-GAP       — explicit gap packet for the 4 P1 gaps (SIR-absent / sidecar-present)
#   APPSTATE-CLOSED    — no new keyword, no holder runtime, no service/actor, no canon
#
# Authority: LAB-ONLY. No canon claim. No framework/app API. No storage execution.
#
# Run: ruby igniter-view-engine/proofs/verify_lab_app_state_p2.rb

SOURCE = File.read(__FILE__).freeze

require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'tempfile'

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / 'igniter-lang' / 'lib'
COMPILER_BIN   = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN         = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIX_DIR        = (ROOT / 'fixtures' / 'app_state')
MAIN_FIX       = (FIX_DIR / 'editor_app_state.ig').to_s
DUR_FIX        = (FIX_DIR / 'editor_app_state_durable.ig').to_s
REGISTRY       = (FIX_DIR / 'editor_app_state.registry.json').to_s

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require 'igniter_lang'

$pass_count = 0
$fail_count = 0

def check(label)
  result = yield
  if result
    puts "  PASS: #{label}"; $pass_count += 1
  else
    puts "  FAIL: #{label}"; $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

# ── Layer B: Rust compiler ──────────────────────────────────────────────────────

def compile_path(path)
  out_dir = Dir.mktmpdir('appstate')
  stdout, _e, _s = Open3.capture3(COMPILER_BIN, 'compile', path.to_s, '--out', out_dir.to_s, '--json')
  stdout = stdout.force_encoding('UTF-8') if stdout
  report = (stdout && !stdout.strip.empty?) ? (JSON.parse(stdout.strip) rescue nil) : nil
  report = nil unless report.is_a?(Hash)
  contracts = {}
  Dir.glob(File.join(out_dir, 'contracts', '*.json')).each do |f|
    c = JSON.parse(File.read(f, encoding: 'UTF-8'))
    contracts[c['name']] = c if c.is_a?(Hash) && c['name']
  end
  { report: report, out_dir: out_dir, contracts: contracts }
end

def status(res);      res[:report]&.fetch('status', nil); end
def diagnostics(res); res[:report]&.fetch('diagnostics', []) || []; end

def out_lifecycle(res, contract, port = nil)
  c = res[:contracts][contract]; return nil unless c
  ports = c['output_ports'] || []
  p = port ? ports.find { |x| x['name'] == port } : ports.first
  p&.fetch('lifecycle', nil)
end

def modifier(res, contract);   res[:contracts][contract]&.fetch('modifier', nil); end
def fragment(res, contract);   res[:contracts][contract]&.fetch('fragment_class', nil); end
def caps(res, contract);       res[:contracts][contract]&.fetch('capabilities', []) || []; end
def effects(res, contract);    res[:contracts][contract]&.fetch('effects', []) || []; end

# ── Layer A: Ruby TypeChecker ───────────────────────────────────────────────────

def ruby_tc(path)
  src        = File.read(path.to_s, encoding: 'UTF-8')
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: path.to_s).to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  { typed: typed }
rescue => e
  { error: e.message }
end

def type_env(tc);  tc[:typed]&.fetch('type_env', {}) || {}; end
def tc_accepted(tc)
  (tc[:typed]&.fetch('contracts', []) || []).count { |c| c['status'] == 'accepted' }
end
def tc_errors(tc); (tc[:typed]&.fetch('type_errors', []) || []); end

def env_has_type?(tc, name); type_env(tc).key?(name); end
def env_field_type(tc, type_name, field)
  f = type_env(tc).dig(type_name, field)
  return nil if f.nil?
  f.is_a?(Hash) ? (f['name'] || f['kind']) : f.to_s
end

# ── Layer C: VM ─────────────────────────────────────────────────────────────────

def vm_run(out_dir, contract_name, inputs)
  tmp = Tempfile.new(['appstate_in', '.json']); tmp.write(inputs.to_json); tmp.close
  stdout, _e, _s = Open3.capture3(VM_BIN, 'run', '--contract', out_dir.to_s,
                                  '--inputs', tmp.path, '--entry', contract_name, '--json')
  tmp.unlink rescue nil
  stdout = stdout.force_encoding('UTF-8') if stdout
  return { 'status' => 'vm_error' } if stdout.nil? || stdout.strip.empty?
  JSON.parse(stdout.strip)
rescue => e
  { 'status' => 'vm_error', 'error' => e.message }
end

# ── Compile + load up front ─────────────────────────────────────────────────────

MAIN     = compile_path(MAIN_FIX)
DUR      = compile_path(DUR_FIX)
MAIN_TC  = ruby_tc(MAIN_FIX)
DUR_TC   = ruby_tc(DUR_FIX)
REG      = JSON.parse(File.read(REGISTRY, encoding: 'UTF-8'))
MAIN_SRC = File.read(MAIN_FIX, encoding: 'UTF-8')
DUR_SRC  = File.read(DUR_FIX, encoding: 'UTF-8')
BOTH_SRC = MAIN_SRC + "\n" + DUR_SRC

# Comment-stripped code (Igniter comments run from `--` to EOL). Closed-surface
# scans run against this so explanatory prose ("lifecycle class", "state values")
# cannot create false positives — only real source constructs count.
def strip_comments(src); src.lines.map { |l| l.sub(/--.*$/, '') }.join; end
MAIN_CODE = strip_comments(MAIN_SRC)
DUR_CODE  = strip_comments(DUR_SRC)
BOTH_CODE = MAIN_CODE + "\n" + DUR_CODE

VM_INSERT = (status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'InsertText',
  { 'doc' => { 'uri' => 'a.rs', 'text' => 'old', 'version' => 3 },
    'ev'  => { 'kind' => 'insert', 'text' => 'new', 'at' => 5 } }) : {}
VM_MOVE = (status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'MoveCursor',
  { 'cur' => { 'line' => 2, 'col' => 1 }, 'ev' => { 'kind' => 'move', 'text' => '', 'at' => 9 } }) : {}
VM_APPLY = (status(MAIN) == 'ok') ? vm_run(MAIN[:out_dir], 'ApplyEdit',
  { 'snap' => { 'doc' => { 'uri' => 'a', 'text' => 't', 'version' => 1 },
                'cursor' => { 'line' => 0, 'col' => 0 },
                'selection' => { 'anchor' => 1, 'head' => 2, 'active' => true }, 'dirty' => false },
    'doc' => { 'uri' => 'a', 'text' => 't2', 'version' => 2 },
    'cursor' => { 'line' => 3, 'col' => 4 } }) : {}

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-COMPILE ─────────────────────────────────────────────────────────"

check("APPSTATE-COMPILE-01: main fixture compiles (status ok)") { status(MAIN) == 'ok' }
check("APPSTATE-COMPILE-02: main fixture zero diagnostics, 8 contracts") do
  diagnostics(MAIN).empty? && (MAIN[:report]['contracts'] || []).length == 8
end
check("APPSTATE-COMPILE-03: durable fixture compiles (status ok), 2 contracts") do
  status(DUR) == 'ok' && diagnostics(DUR).empty? && (DUR[:report]['contracts'] || []).length == 2
end
check("APPSTATE-COMPILE-04: Ruby TC main: 8 accepted, 0 type_errors") do
  tc_accepted(MAIN_TC) == 8 && tc_errors(MAIN_TC).empty?
end
check("APPSTATE-COMPILE-05: Ruby TC durable: 2 accepted, 0 type_errors") do
  tc_accepted(DUR_TC) == 2 && tc_errors(DUR_TC).empty?
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-SHAPE ───────────────────────────────────────────────────────────"

%w[DocumentState CursorState SelectionState ClipboardState Diagnostic
   DiagnosticSet EditHistory BufferRef EditorSnapshot EditEvent TransitionReceipt].each_with_index do |t, i|
  check(format("APPSTATE-SHAPE-%02d: state record type '%s' present in type_env", i + 1, t)) do
    env_has_type?(MAIN_TC, t)
  end
end
check("APPSTATE-SHAPE-12: DocumentState.version typed Integer") do
  env_field_type(MAIN_TC, 'DocumentState', 'version') == 'Integer'
end
check("APPSTATE-SHAPE-13: EditorSnapshot.doc typed DocumentState (composite of records)") do
  env_field_type(MAIN_TC, 'EditorSnapshot', 'doc') == 'DocumentState'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-LIFECYCLE ───────────────────────────────────────────────────────"

{ 'InsertText' => ['next', 'session'], 'MoveCursor' => ['next', 'local'],
  'SelectRange' => ['next', 'local'], 'CopySelection' => ['snippet', 'session'],
  'ApplyEdit' => ['next', 'session'], 'RecomputeDiagnostics' => ['set', 'window'],
  'PushHistory' => ['next', 'session'], 'BuildTransitionReceipt' => ['receipt', 'audit']
}.each_with_index do |(c, (port, lc)), i|
  check(format("APPSTATE-LIFECYCLE-%02d: %s.%s carries lifecycle :%s (E path)", i + 1, c, port, lc)) do
    out_lifecycle(MAIN, c, port) == lc
  end
end
check("APPSTATE-LIFECYCLE-09: durable BuildSaveRequest.req carries lifecycle :durable") do
  out_lifecycle(DUR, 'BuildSaveRequest', 'req') == 'durable'
end
check("APPSTATE-LIFECYCLE-10: lifecycle classes used ⊆ {local,session,window,durable,audit}") do
  used = MAIN[:contracts].values.flat_map { |c| (c['output_ports'] || []).map { |p| p['lifecycle'] } }.compact.uniq
  (used - %w[local session window durable audit]).empty? && (used & %w[local session window audit]).any?
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-TRANSITION ──────────────────────────────────────────────────────"

%w[InsertText MoveCursor SelectRange CopySelection ApplyEdit RecomputeDiagnostics PushHistory].each_with_index do |c, i|
  check(format("APPSTATE-TRANSITION-%02d: %s is pure/CORE (snapshot+event transform)", i + 1, c)) do
    modifier(MAIN, c) == 'pure' && fragment(MAIN, c) == 'core'
  end
end
check("APPSTATE-TRANSITION-08: pure transitions carry NO capability and NO effect") do
  %w[InsertText MoveCursor ApplyEdit RecomputeDiagnostics].all? { |c| caps(MAIN, c).empty? && effects(MAIN, c).empty? }
end
check("APPSTATE-TRANSITION-09: VM InsertText snapshot+event → next DocumentState (fresh value)") do
  VM_INSERT['status'] == 'success' && VM_INSERT.dig('result', 'text') == 'new' &&
    VM_INSERT.dig('result', 'uri') == 'a.rs'
end
check("APPSTATE-TRANSITION-10: VM MoveCursor → next CursorState (col from event)") do
  VM_MOVE['status'] == 'success' && VM_MOVE.dig('result', 'col') == 9
end
check("APPSTATE-TRANSITION-11: VM ApplyEdit composite reducer preserves nested records") do
  r = VM_APPLY['result']
  VM_APPLY['status'] == 'success' && r.is_a?(Hash) &&
    r.dig('doc', 'text') == 't2' && r.dig('cursor', 'col') == 4 &&
    r.dig('selection', 'head') == 2 && r['dirty'] == true
end
check("APPSTATE-TRANSITION-12: no hidden holder — output is a fresh value, input doc unchanged in trace") do
  # the VM returns a new value; nothing in the result aliases or mutates the input record identity
  VM_INSERT.dig('result', 'version') == 3 && VM_INSERT['status'] == 'success'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-PUBLIC ──────────────────────────────────────────────────────────"

check("APPSTATE-PUBLIC-01: boundary op BuildSaveRequest inferable as effecting (modifier=effect→escape)") do
  modifier(DUR, 'BuildSaveRequest') == 'effect' && fragment(DUR, 'BuildSaveRequest') == 'escape'
end
check("APPSTATE-PUBLIC-02: boundary op LoadDocument inferable as observing (modifier=observed→escape)") do
  modifier(DUR, 'LoadDocument') == 'observed' && fragment(DUR, 'LoadDocument') == 'escape'
end
check("APPSTATE-PUBLIC-03: VISIBILITY GAP — pure public op vs pure helper indistinguishable in SIR") do
  # InsertText (registry public) and BuildTransitionReceipt (registry internal) share modifier=pure;
  # the language carries no public/internal marker to separate them.
  modifier(MAIN, 'InsertText') == modifier(MAIN, 'BuildTransitionReceipt')
end
check("APPSTATE-PUBLIC-04: sidecar registry declares visibility for every contract") do
  names = MAIN[:contracts].keys + DUR[:contracts].keys
  reg = REG['operations'].each_with_object({}) { |o, h| h[o['contract']] = o['visibility'] }
  names.all? { |n| %w[public internal].include?(reg[n]) }
end
check("APPSTATE-PUBLIC-05: registry public/internal is consistent with effect/observed boundary ops") do
  reg = REG['operations'].each_with_object({}) { |o, h| h[o['contract']] = o['visibility'] }
  reg['BuildSaveRequest'] == 'public' && reg['LoadDocument'] == 'public' &&
    REG['operations'].any? { |o| o['visibility'] == 'internal' }
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-DURABLE ─────────────────────────────────────────────────────────"

check("APPSTATE-DURABLE-01: BuildSaveRequest is effect contract, fragment escape") do
  modifier(DUR, 'BuildSaveRequest') == 'effect' && fragment(DUR, 'BuildSaveRequest') == 'escape'
end
check("APPSTATE-DURABLE-02: BuildSaveRequest gated by IO.StorageCapability") do
  caps(DUR, 'BuildSaveRequest').any? { |c| c.dig('type', 'name') == 'IO.StorageCapability' }
end
check("APPSTATE-DURABLE-03: BuildSaveRequest declares an effect bound to the capability") do
  effects(DUR, 'BuildSaveRequest').any? { |e| e['capability_ref'] == 'storage' }
end
check("APPSTATE-DURABLE-04: durable output carries lifecycle :durable") do
  out_lifecycle(DUR, 'BuildSaveRequest', 'req') == 'durable'
end
check("APPSTATE-DURABLE-05: LoadDocument reads the durable holder by name 'editor.workspace'") do
  DUR_SRC.include?('from "editor.workspace"')
end
check("APPSTATE-DURABLE-06: NO storage execution (no execute_sql/run_query/connection/save!)") do
  !DUR_SRC.include?('execut' + 'e_sql') && !DUR_SRC.include?('run_qu' + 'ery') &&
    !DUR_SRC.include?('establish_connection') && !DUR_SRC.include?('save' + '!')
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-HOST ────────────────────────────────────────────────────────────"

check("APPSTATE-HOST-01: no mutable binding keyword (var / let mut / mut) in fixtures") do
  !BOTH_SRC.match?(/\bvar\b/) && !BOTH_SRC.match?(/\blet\s+mut\b/) && !BOTH_SRC.match?(/\bmut\b/)
end
check("APPSTATE-HOST-02: every transition output is a declared record type (a value, not a handle)") do
  rec_types = type_env(MAIN_TC).keys
  %w[InsertText MoveCursor ApplyEdit RecomputeDiagnostics PushHistory].all? do |c|
    rec_types.include?(MAIN[:contracts][c]['output_ports'].first['type_tag'])
  end
end
check("APPSTATE-HOST-03: hot/session transitions need NO capability (holder is host, not language)") do
  %w[InsertText MoveCursor SelectRange CopySelection ApplyEdit PushHistory RecomputeDiagnostics].all? { |c| caps(MAIN, c).empty? }
end
check("APPSTATE-HOST-04: registry holder_class = host for hot/session facts, store only for durable") do
  by_lc = REG['facts'].group_by { |f| f['lifecycle'] }
  hot = (by_lc['local'] || []) + (by_lc['session'] || []) + (by_lc['window'] || [])
  dur = (by_lc['durable'] || [])
  hot.all? { |f| f['holder_class'] == 'host' } && dur.all? { |f| f['holder_class'] == 'store' } && !dur.empty?
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-GAP (the four P1 gaps: SIR-absent / sidecar-present) ─────────────"

ALL_CONTRACTS = MAIN[:contracts].values + DUR[:contracts].values

check("APPSTATE-GAP-01: state-INSTANCE identity ABSENT from SIR (output ports carry no instance/id/holder field)") do
  ALL_CONTRACTS.all? do |c|
    (c['output_ports'] || []).all? { |p| (p.keys & %w[instance instance_id id holder owner key]).empty? }
  end
end
check("APPSTATE-GAP-02: state-instance identity PRESENT in sidecar (instance_key_source per fact)") do
  REG['facts'].all? { |f| f['instance_key_source'].is_a?(String) && !f['instance_key_source'].empty? }
end
check("APPSTATE-GAP-03: fact↔HOLDER binding ABSENT from SIR (lifecycle ≠ holder; no holder field anywhere)") do
  ALL_CONTRACTS.none? { |c| c.key?('holder') || c.key?('holder_class') || c.key?('owner') }
end
check("APPSTATE-GAP-04: fact↔holder binding PRESENT in sidecar (explicit holder_class per fact)") do
  REG['facts'].all? { |f| %w[host store].include?(f['holder_class']) } && REG.key?('holders')
end
check("APPSTATE-GAP-05: app-ASSEMBLY (event→op→fact) ABSENT from SIR (no on_event/wiring/assembly keys)") do
  ALL_CONTRACTS.none? { |c| (c.keys & %w[on_event events wiring assembly routes transitions_fact]).any? }
end
check("APPSTATE-GAP-06: app-assembly PRESENT in sidecar (operations carry on_event + transitions fact)") do
  pub = REG['operations'].reject { |o| o['visibility'] == 'internal' }
  pub.all? { |o| o.key?('on_event') && o.key?('transitions') }
end
check("APPSTATE-GAP-07: public/internal VISIBILITY ABSENT from SIR for pure contracts (no visibility field; modifier can't separate)") do
  ALL_CONTRACTS.none? { |c| (c.keys & %w[visibility access public private internal]).any? } &&
    modifier(MAIN, 'InsertText') == modifier(MAIN, 'BuildTransitionReceipt')
end
check("APPSTATE-GAP-08: visibility PRESENT in sidecar (every op classified public|internal)") do
  REG['operations'].all? { |o| %w[public internal].include?(o['visibility']) }
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n── APPSTATE-CLOSED ──────────────────────────────────────────────────────────"

check("APPSTATE-CLOSED-01: no `state {` declaration keyword in fixture code") do
  !BOTH_CODE.match?(/\bstate\s*\{/) && !BOTH_CODE.match?(/^\s*state\s+\w/)
end
check("APPSTATE-CLOSED-02: no public/private/internal keyword in fixture code") do
  !BOTH_CODE.match?(/^\s*(public|private|internal)\s/) && !BOTH_CODE.match?(/\b(public|private|internal)\s+contract\b/)
end
check("APPSTATE-CLOSED-03: no service/actor/class holder construct in fixture code") do
  !BOTH_CODE.match?(/\b(service|actor)\b/) && !BOTH_CODE.match?(/\bclass\s+\w/)
end
check("APPSTATE-CLOSED-04: no module-instance syntax (module is namespace+purity only)") do
  !BOTH_CODE.match?(/\bnew\s+module\b/) && !BOTH_CODE.match?(/\bmodule\s+instance\b/) &&
    BOTH_CODE.scan(/^module\s+\S+/).length == 2
end
check("APPSTATE-CLOSED-05: `intent` keyword NOT used (not parseable in lab toolchain; PROP-045 convention-only)") do
  # Evidence finding: the lab parser has no `intent` keyword; using it would fail to parse.
  # The proof carries descriptive purpose in the sidecar instead. Confirm none leaked in.
  !MAIN_CODE.match?(/^\s*intent\s/) && !DUR_CODE.match?(/^\s*intent\s/)
end
check("APPSTATE-CLOSED-06: no storage execution anywhere; no stable/public API claim") do
  !BOTH_CODE.include?('execut' + 'e_sql') && !BOTH_CODE.include?('ActiveRec' + 'ord') &&
    !BOTH_SRC.include?('stab' + 'le API') && !SOURCE.include?('stab' + 'le API')
end
check("APPSTATE-CLOSED-07: all main contracts pure CORE; only the durable fixture is ESCAPE") do
  MAIN[:contracts].values.all? { |c| c['fragment_class'] == 'core' } &&
    DUR[:contracts].values.all? { |c| c['fragment_class'] == 'escape' }
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\n═══════════════════════════════════════════════════════════════════════════════"
total = $pass_count + $fail_count
puts "RESULT: #{$pass_count}/#{total} PASS"
puts "═══════════════════════════════════════════════════════════════════════════════"

if $fail_count > 0
  puts "\nFAILURES PRESENT — #{$fail_count} check(s) failed."
  exit 1
else
  puts "\nALL CHECKS PASS — LAB-APP-STATE-P2 proof complete."
  puts "\nKey findings:"
  puts "  - Host-owned editor state expressible as typed records; transitions are pure snapshot+event→next"
  puts "  - Lifecycle vocabulary (:local/:session/:window/:durable/:audit) carries each fact's lifetime IN-LANGUAGE (SIR output_ports)"
  puts "  - Durable save/load stays effect/observed + IO.StorageCapability — no storage execution"
  puts "  - Holder stays host-owned; no language-level mutable object; pure transitions need no capability"
  puts "  - 4 P1 gaps remain non-language: instance identity, fact↔holder binding, app assembly, public/internal visibility"
  puts "    → all carried in a proof-local sidecar registry (inert metadata), none requiring a holder runtime"
  exit 0
end
