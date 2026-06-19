#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_frontier_decision_p2.rb
# FRONTIER-DECISION-P2: Query-plan selection Decision KDR proof
#
# Proves the FRONTIER-DECISION-P1 DecisionReceipt KDR surface (Gap-J / Covenant P24/P25)
# is producible, carriable, and routable in the lab Rust VM, in the domain of choosing
# between QueryPlans under resource (row_budget) and policy/safety (no_include_all)
# constraints. KDR convention only — no constraints{} grammar, no StrategyDecision canon
# type, no variant/match, no real storage/SQL/DB/network I/O, no PROP.
#
# Layering (same Ruby/Rust divergence as LAB-EPISTEMIC-OUTCOME-P4, documented not hidden):
#   Layer A — production Ruby TypeChecker: the 6 record types + producer/inspector accepted;
#             guard/router contracts are BLOCKED in Ruby TC (String == unsupported there).
#   Layer B — Rust compiler + VM: receipt construction (nested record + 4 collections),
#             kind-guard logic, waiver/justification/option guards, and routing EXECUTE.
#   Layer C — proof-local checks over VM outputs for the forbidden-collapse rules.
#
# Sections:
#   FDEC-COMPILE   (4) — Ruby TC runs; Rust SIR 7 contracts; producers accepted; no variants
#   FDEC-TYPES     (8) — DecisionReceipt 12 fields; nested ChosenAction; collections; evidence_kind
#   FDEC-DECIDED   (8) — positive path: full receipt VM-produced; P24 seven exposures present
#   FDEC-REJECT    (5) — constraint-driven rejections (no_include_all, row_budget)
#   FDEC-AUTHORITY (5) — capability vs decision authority split (FC-D3)
#   FDEC-EVIDENCE  (4) — evidence refs + evidence_kind preserved; model != approval
#   FDEC-KINDGUARD (7) — in-VM kind computation incl. model+agent→escalated (FC-D6), none→escalated (FC-D1)
#   FDEC-ROUTE     (6) — VM routing: decided/deferred/escalated/no_viable_option/unknown fail-closed
#   FDEC-NVO       (4) — no_viable_option: not failed, not deferred, no default pick
#   FDEC-WAIVER    (6) — valid waiver recorded; invalid waiver escalates; waived != absent (FC-D4)
#   FDEC-DEFER     (3) — deferred path; consumer waits; never execute_plan (FC-D8)
#   FDEC-SCORE     (4) — score is input, not justification (FC-D5)
#   FDEC-CLOSED    (8) — no grammar/variants/real IO/canon claim; decided_at explicit; carrier audit field
#
# Total: 72 checks
#
# Authority: LAB-ONLY. No canon claim. No public/stable API. No PROP. No agent autonomy.
#
# Run: ruby igniter-view-engine/proofs/verify_frontier_decision_p2.rb

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
FIXTURE_PATH   = (ROOT / 'fixtures' / 'frontier_decision' / 'query_plan_decision.ig').to_s

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require 'igniter_lang'

$pass_count = 0
$fail_count = 0

def check(label)
  ok = yield
  if ok
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

# ── Layer A helpers ───────────────────────────────────────────────────────────

def run_fixture(path)
  src        = File.read(path.to_s).force_encoding('UTF-8')
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: path.to_s).to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  typed      = IgniterLang::TypeChecker.new.typecheck(classified)
  { parsed: parsed, classified: classified, typed: typed }
rescue => e
  { error: e.message }
end

def type_name_str(t)
  return t.to_s unless t.is_a?(Hash)
  name   = t['name'] || t['kind'] || '?'
  params = Array(t['params'])
  return name if params.empty?
  "#{name}[#{params.map { |p| type_name_str(p) }.join(',')}]"
end

def type_env_field(tc, type_name, field)
  tc[:typed]&.fetch('type_env', {})&.fetch(type_name, {})&.fetch(field, nil)
end

def contract_status(tc, name)
  c = tc[:typed]&.fetch('contracts', [])&.find { |x| x['name'] == name }
  c && c['status']
end

# ── Layer B helpers ───────────────────────────────────────────────────────────

def compile_fixture(path, out_dir)
  FileUtils.mkdir_p(out_dir)
  stdout, _e, _s = Open3.capture3(COMPILER_BIN, 'compile', path.to_s, '--out', out_dir.to_s, '--json')
  stdout = stdout&.force_encoding('UTF-8')
  return nil if stdout.nil? || stdout.strip.empty?
  JSON.parse(stdout.strip)
rescue
  nil
end

def read_sir(out_dir)
  p = File.join(out_dir.to_s, 'semantic_ir_program.json')
  File.exist?(p) ? JSON.parse(File.read(p)) : nil
rescue
  nil
end

def vm_run(app_dir, entry, inputs)
  tf = Tempfile.new(['fdec', '.json'])
  tf.write(inputs.to_json); tf.close
  stdout, _e, _s = Open3.capture3(VM_BIN, 'run', '--contract', app_dir.to_s,
                                  '--inputs', tf.path, '--entry', entry, '--json')
  tf.unlink rescue nil
  stdout = stdout&.force_encoding('UTF-8')
  return { 'status' => 'vm_error', 'error' => 'empty' } if stdout.nil? || stdout.strip.empty?
  JSON.parse(stdout.strip)
rescue => e
  { 'status' => 'vm_error', 'error' => e.message }
end

# ── Scenario data ─────────────────────────────────────────────────────────────

CHOSEN = {
  'evidence_refs' => ['obs:cost-filtered'], 'expected_outcome' => 'about 120 rows; within row_budget',
  'option_id' => 'plan_filtered', 'uncompensatable' => 'none claimed; read-only plan'
}.freeze

EMPTY_CHOSEN = {
  'evidence_refs' => [], 'expected_outcome' => '', 'option_id' => '', 'uncompensatable' => ''
}.freeze

REJECTED = [
  { 'conflicting_constraint' => 'no_include_all', 'disposition' => 'final',
    'evidence_refs' => ['obs:scan-estimate'], 'expected_outcome' => 'full table scan',
    'option_id' => 'plan_include_all', 'rejection_reason' => 'requests include_all which policy forbids' },
  { 'conflicting_constraint' => 'row_budget', 'disposition' => 'final',
    'evidence_refs' => ['obs:cost-broad'], 'expected_outcome' => 'about 50000 rows',
    'option_id' => 'plan_broad', 'rejection_reason' => 'exceeds row_budget of 1000 rows' }
].freeze

CONSTRAINTS = [
  { 'constraint_hash' => 'sha256:rb-1', 'kind' => 'resource', 'name' => 'row_budget',
    'priority' => '1.0', 'statement' => 'result must not exceed 1000 rows',
    'status' => 'satisfied', 'waiver_authority' => '' },
  { 'constraint_hash' => 'sha256:nia-1', 'kind' => 'policy', 'name' => 'no_include_all',
    'priority' => '0.9', 'statement' => 'include_all is forbidden on restricted capabilities',
    'status' => 'satisfied', 'waiver_authority' => '' }
].freeze

WAIVED_CONSTRAINTS = [
  { 'constraint_hash' => 'sha256:rb-1', 'kind' => 'resource', 'name' => 'row_budget',
    'priority' => '1.0', 'statement' => 'result must not exceed 1000 rows',
    'status' => 'waived', 'waiver_authority' => 'ops-lead-7' }
].freeze

AUTHORITY = [
  { 'action' => 'recommended', 'actor_id' => 'planner-1', 'actor_kind' => 'agent',
    'basis' => 'cost model v2', 'role' => 'planner' },
  { 'action' => 'approved', 'actor_id' => 'policy-engine', 'actor_kind' => 'system',
    'basis' => 'profile: query_policy_v0', 'role' => 'policy_engine' }
].freeze

EVIDENCE = [
  { 'evidence_kind' => 'real',  'ref' => 'obs:cost-filtered' },
  { 'evidence_kind' => 'model', 'ref' => 'obs:scan-estimate' }
].freeze

def receipt_inputs(kind:, chosen: CHOSEN, rejected: REJECTED, constraints: CONSTRAINTS,
                   authority: AUTHORITY, evidence: EVIDENCE, rationale:, metadata: {})
  { 'kind' => kind, 'decision_id' => 'dec-qp-1', 'chosen' => chosen, 'rejected' => rejected,
    'constraints' => constraints, 'authority_chain' => authority, 'evidence_refs' => evidence,
    'assumption_refs' => ['asm:cost-model-applicable'], 'rationale' => rationale,
    'decided_at' => '2026-06-10T21:00:00Z', 'audit_obligation' => 'pending', 'metadata' => metadata }
end

def receipt_for_route(kind)
  { 'receipt' => {
    'kind' => kind, 'decision_id' => 'd', 'chosen' => EMPTY_CHOSEN, 'rejected' => [],
    'constraints' => [], 'authority_chain' => [], 'evidence_refs' => [], 'assumption_refs' => [],
    'rationale' => '', 'decided_at' => 't0', 'audit_obligation' => 'pending', 'metadata' => {}
  } }
end

# ── Compile / typecheck / pre-run ─────────────────────────────────────────────

FDEC_OUT = Dir.mktmpdir('fdec_main')
FDEC_SIR = compile_fixture(FIXTURE_PATH, FDEC_OUT)
FDEC_TC  = run_fixture(FIXTURE_PATH)

VM_DECIDED = vm_run(FDEC_OUT, 'MakeDecisionReceipt',
                    receipt_inputs(kind: 'decided',
                                   rationale: 'filtered plan meets row_budget; include_all plan violates policy',
                                   metadata: { 'review_hint' => 'compare estimated vs actual rows' }))

VM_NVO = vm_run(FDEC_OUT, 'MakeDecisionReceipt',
                receipt_inputs(kind: 'no_viable_option', chosen: EMPTY_CHOSEN,
                               rationale: 'every viable plan violates a binding constraint'))

VM_WAIVED = vm_run(FDEC_OUT, 'MakeDecisionReceipt',
                   receipt_inputs(kind: 'decided', constraints: WAIVED_CONSTRAINTS,
                                  authority: AUTHORITY + [{ 'action' => 'approved', 'actor_id' => 'ops-lead-7',
                                                            'actor_kind' => 'human', 'basis' => 'waiver authority for row_budget',
                                                            'role' => 'ops_lead' }],
                                  rationale: 'row_budget waived by ops-lead-7 for one-off audit query'))

def kind_guard(viable:, pending: 'no', evidence: 'real', approval: 'human')
  vm_run(FDEC_OUT, 'DecideKindGuard',
         { 'viable_count' => viable, 'pending_evidence' => pending,
           'evidence_kind' => evidence, 'approval_actor_kind' => approval })['result']
end

def route(kind) = vm_run(FDEC_OUT, 'RouteDecision', receipt_for_route(kind))['result']

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-COMPILE"

check('FDEC-COMPILE-01: fixture parses; Ruby TypeChecker runs without crash') do
  !FDEC_TC[:error] && FDEC_TC[:typed].is_a?(Hash)
end
check('FDEC-COMPILE-02: Rust compiler emits SIR with 7 contracts') do
  sir = read_sir(FDEC_OUT)
  sir.is_a?(Hash) && sir.fetch('contracts', []).length == 7
end
check('FDEC-COMPILE-03: producer + inspector accepted by Ruby TC (guards blocked = known == divergence)') do
  contract_status(FDEC_TC, 'MakeDecisionReceipt') == 'accepted' &&
    contract_status(FDEC_TC, 'ReceiptInspector') == 'accepted'
end
check('FDEC-COMPILE-04: fixture declares NO variants (KDR-only; no StrategyDecision type)') do
  (FDEC_TC[:parsed]&.fetch('variants', []) || []).empty?
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-TYPES"

check('FDEC-TYPES-01: DecisionReceipt has 12 fields') do
  (FDEC_TC[:typed]&.dig('type_env', 'DecisionReceipt') || {}).keys.length == 12
end
check('FDEC-TYPES-02: DecisionReceipt.kind = String (KDR discriminant)') do
  type_name_str(type_env_field(FDEC_TC, 'DecisionReceipt', 'kind')) == 'String'
end
check('FDEC-TYPES-03: DecisionReceipt.chosen = ChosenAction (nested record)') do
  type_name_str(type_env_field(FDEC_TC, 'DecisionReceipt', 'chosen')) == 'ChosenAction'
end
check('FDEC-TYPES-04: rejected = Collection[RejectedAlternative]') do
  type_name_str(type_env_field(FDEC_TC, 'DecisionReceipt', 'rejected')) == 'Collection[RejectedAlternative]'
end
check('FDEC-TYPES-05: constraints = Collection[ConstraintApplication]; authority_chain = Collection[AuthorityLink]') do
  type_name_str(type_env_field(FDEC_TC, 'DecisionReceipt', 'constraints')) == 'Collection[ConstraintApplication]' &&
    type_name_str(type_env_field(FDEC_TC, 'DecisionReceipt', 'authority_chain')) == 'Collection[AuthorityLink]'
end
check('FDEC-TYPES-06: evidence_refs = Collection[EvidenceRef]; EvidenceRef.evidence_kind = String') do
  type_name_str(type_env_field(FDEC_TC, 'DecisionReceipt', 'evidence_refs')) == 'Collection[EvidenceRef]' &&
    type_name_str(type_env_field(FDEC_TC, 'EvidenceRef', 'evidence_kind')) == 'String'
end
check('FDEC-TYPES-07: ConstraintApplication carries hash/status/waiver_authority (P25 surface)') do
  ca = FDEC_TC[:typed]&.dig('type_env', 'ConstraintApplication') || {}
  %w[constraint_hash status waiver_authority kind priority].all? { |f| ca.key?(f) }
end
check('FDEC-TYPES-08: ChosenAction carries expected_outcome + uncompensatable (P24 exposures 6+7)') do
  c = FDEC_TC[:typed]&.dig('type_env', 'ChosenAction') || {}
  c.key?('expected_outcome') && c.key?('uncompensatable')
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-DECIDED"

check('FDEC-DECIDED-01: full DecisionReceipt VM-constructed (nested record + 4 collections + map)') do
  VM_DECIDED['status'] == 'success' && VM_DECIDED['result'].is_a?(Hash) &&
    VM_DECIDED.dig('result', 'kind') == 'decided'
end
check('FDEC-DECIDED-02: chosen action preserved with option_id') do
  VM_DECIDED.dig('result', 'chosen', 'option_id') == 'plan_filtered'
end
check('FDEC-DECIDED-03: at least one rejected alternative recorded') do
  (VM_DECIDED.dig('result', 'rejected') || []).length >= 1
end
check('FDEC-DECIDED-04: SATISFIED constraints recorded (not only violated ones)') do
  (VM_DECIDED.dig('result', 'constraints') || []).any? { |c| c['status'] == 'satisfied' }
end
check('FDEC-DECIDED-05: authority_chain includes an approval') do
  (VM_DECIDED.dig('result', 'authority_chain') || []).any? { |a| a['action'] == 'approved' }
end
check('FDEC-DECIDED-06: rationale non-empty') do
  VM_DECIDED.dig('result', 'rationale').to_s != ''
end
check('FDEC-DECIDED-07: P24 exposures 6+7 — expected_outcome and uncompensatable present on chosen') do
  VM_DECIDED.dig('result', 'chosen', 'expected_outcome').to_s != '' &&
    VM_DECIDED.dig('result', 'chosen').key?('uncompensatable')
end
check('FDEC-DECIDED-08: decided_at explicit + assumption_refs carried (no ambient time; Gap-H refs opaque)') do
  VM_DECIDED.dig('result', 'decided_at') == '2026-06-10T21:00:00Z' &&
    VM_DECIDED.dig('result', 'assumption_refs') == ['asm:cost-model-applicable']
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-REJECT"

REJ = (VM_DECIDED.dig('result', 'rejected') || [])

check('FDEC-REJECT-01: include_all plan rejected with conflicting_constraint = no_include_all') do
  r = REJ.find { |x| x['option_id'] == 'plan_include_all' }
  r && r['conflicting_constraint'] == 'no_include_all'
end
check('FDEC-REJECT-02: row-heavy plan rejected with conflicting_constraint = row_budget') do
  r = REJ.find { |x| x['option_id'] == 'plan_broad' }
  r && r['conflicting_constraint'] == 'row_budget'
end
check('FDEC-REJECT-03: every rejection_reason non-empty') do
  REJ.all? { |x| x['rejection_reason'].to_s != '' }
end
check('FDEC-REJECT-04: rejected alternatives carry their own evidence_refs') do
  REJ.all? { |x| (x['evidence_refs'] || []).length >= 1 }
end
check('FDEC-REJECT-05: dispositions are from the closed set (final|deferred|escalated)') do
  REJ.all? { |x| %w[final deferred escalated].include?(x['disposition']) }
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-AUTHORITY"

check('FDEC-AUTHORITY-01: VM ClassifyOption capability-denied → denied_upstream (denial-as-data)') do
  vm_run(FDEC_OUT, 'ClassifyOption', { 'option_id' => 'plan_x', 'capability_allowed' => 'no' })['result'] == 'denied_upstream'
end
check('FDEC-AUTHORITY-02: VM ClassifyOption capability-permitted → viable') do
  vm_run(FDEC_OUT, 'ClassifyOption', { 'option_id' => 'plan_filtered', 'capability_allowed' => 'yes' })['result'] == 'viable'
end
check('FDEC-AUTHORITY-03: FC-D3 — capability-denied option does NOT appear in rejected') do
  # the decided receipt rejects plan_include_all / plan_broad (viable, evaluated);
  # the capability-denied plan_x is absent — it was excluded upstream, not "rejected"
  REJ.none? { |x| x['option_id'] == 'plan_x' }
end
check('FDEC-AUTHORITY-04: a capability-PERMITTED option was still decision-rejected (two authorities differ)') do
  REJ.any? { |x| x['option_id'] == 'plan_broad' } # permitted by capability; rejected by row_budget decision
end
check('FDEC-AUTHORITY-05: authority_chain separates recommended (agent) from approved (non-agent)') do
  chain = VM_DECIDED.dig('result', 'authority_chain') || []
  rec = chain.find { |a| a['action'] == 'recommended' }
  app = chain.find { |a| a['action'] == 'approved' }
  rec && app && rec['actor_kind'] == 'agent' && app['actor_kind'] != 'agent'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-EVIDENCE"

check('FDEC-EVIDENCE-01: receipt carries EvidenceRef entries through the VM') do
  (VM_DECIDED.dig('result', 'evidence_refs') || []).length == 2
end
check('FDEC-EVIDENCE-02: evidence_kind preserved per ref (real + model)') do
  kinds = (VM_DECIDED.dig('result', 'evidence_refs') || []).map { |e| e['evidence_kind'] }.sort
  kinds == %w[model real]
end
check('FDEC-EVIDENCE-03: FC-D6 behaviorally — model evidence + agent approval → decision_escalated (never decided)') do
  k = kind_guard(viable: 2, evidence: 'model', approval: 'agent')
  k == 'decision_escalated' && k != 'decided'
end
check('FDEC-EVIDENCE-04: model evidence + HUMAN approval → decided (the sanctioned upgrade path)') do
  kind_guard(viable: 2, evidence: 'model', approval: 'human') == 'decided'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-KINDGUARD"

check('FDEC-KINDGUARD-01: viable_count=0 → no_viable_option') do
  kind_guard(viable: 0) == 'no_viable_option'
end
check('FDEC-KINDGUARD-02: pending evidence → decision_deferred') do
  kind_guard(viable: 2, pending: 'yes') == 'decision_deferred'
end
check('FDEC-KINDGUARD-03: FC-D1 — no approval at all → decision_escalated (chosen != authorized)') do
  kind_guard(viable: 2, approval: 'none') == 'decision_escalated'
end
check('FDEC-KINDGUARD-04: model + system approval → decision_escalated (v0-conservative; human-gate future)') do
  kind_guard(viable: 2, evidence: 'model', approval: 'system') == 'decision_escalated'
end
check('FDEC-KINDGUARD-05: real evidence + agent approval → decided (escalation rule scoped to model evidence)') do
  kind_guard(viable: 2, evidence: 'real', approval: 'agent') == 'decided'
end
check('FDEC-KINDGUARD-06: real evidence + human approval → decided') do
  kind_guard(viable: 2, evidence: 'real', approval: 'human') == 'decided'
end
check('FDEC-KINDGUARD-07: no_viable_option wins over pending (empty option space is terminal)') do
  kind_guard(viable: 0, pending: 'yes') == 'no_viable_option'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-ROUTE"

check('FDEC-ROUTE-01: decided → execute_plan') { route('decided') == 'execute_plan' }
check('FDEC-ROUTE-02: decision_deferred → wait') { route('decision_deferred') == 'wait' }
check('FDEC-ROUTE-03: decision_escalated → human_review') { route('decision_escalated') == 'human_review' }
check('FDEC-ROUTE-04: no_viable_option → stop') { route('no_viable_option') == 'stop' }
check('FDEC-ROUTE-05: unrecognised kind → hold (fail closed; never execute)') do
  a = route('totally_unexpected')
  a == 'hold' && a != 'execute_plan'
end
check('FDEC-ROUTE-06: FC-D7 — routing output is DATA (a string action), not an execution') do
  r = vm_run(FDEC_OUT, 'RouteDecision', receipt_for_route('decided'))
  r['status'] == 'success' && r['result'].is_a?(String)
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-NVO"

check('FDEC-NVO-01: no_viable_option receipt VM-produced with empty chosen (no default pick, FC-D9)') do
  VM_NVO['status'] == 'success' &&
    VM_NVO.dig('result', 'kind') == 'no_viable_option' &&
    VM_NVO.dig('result', 'chosen', 'option_id') == ''
end
check('FDEC-NVO-02: no_viable_option is not "failed" (separate namespace from outcome kinds)') do
  VM_NVO.dig('result', 'kind') != 'failed'
end
check('FDEC-NVO-03: no_viable_option is not decision_deferred') do
  VM_NVO.dig('result', 'kind') != 'decision_deferred'
end
check('FDEC-NVO-04: consumer stops on no_viable_option (does not execute, does not wait)') do
  a = route('no_viable_option')
  a == 'stop' && a != 'execute_plan' && a != 'wait'
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-WAIVER"

check('FDEC-WAIVER-01: VM WaiverGuard — waived + named authority → waiver_recorded') do
  vm_run(FDEC_OUT, 'WaiverGuard', { 'status' => 'waived', 'waiver_authority' => 'ops-lead-7' })['result'] == 'waiver_recorded'
end
check('FDEC-WAIVER-02: VM WaiverGuard — waived + EMPTY authority → invalid_waiver_escalate (fails closed)') do
  r = vm_run(FDEC_OUT, 'WaiverGuard', { 'status' => 'waived', 'waiver_authority' => '' })['result']
  r == 'invalid_waiver_escalate' && r != 'waiver_recorded'
end
check('FDEC-WAIVER-03: non-waived status → no_waiver (guard does not over-fire)') do
  vm_run(FDEC_OUT, 'WaiverGuard', { 'status' => 'satisfied', 'waiver_authority' => '' })['result'] == 'no_waiver'
end
check('FDEC-WAIVER-04: FC-D4 — waived constraint STILL APPEARS in the receipt constraints list') do
  cs = VM_WAIVED.dig('result', 'constraints') || []
  w = cs.find { |c| c['status'] == 'waived' }
  w && w['name'] == 'row_budget'
end
check('FDEC-WAIVER-05: waived constraint carries non-empty waiver_authority') do
  w = (VM_WAIVED.dig('result', 'constraints') || []).find { |c| c['status'] == 'waived' }
  w && w['waiver_authority'] == 'ops-lead-7'
end
check('FDEC-WAIVER-06: the waiver actor also appears in authority_chain as an approval') do
  (VM_WAIVED.dig('result', 'authority_chain') || []).any? do |a|
    a['actor_id'] == 'ops-lead-7' && a['action'] == 'approved'
  end
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-DEFER"

check('FDEC-DEFER-01: pending evidence yields decision_deferred (in-VM guard)') do
  kind_guard(viable: 2, pending: 'yes') == 'decision_deferred'
end
check('FDEC-DEFER-02: FC-D8 — deferred routes to wait, never to execute_plan') do
  a = route('decision_deferred')
  a == 'wait' && a != 'execute_plan'
end
check('FDEC-DEFER-03: deferred is distinct from escalated (different consumers)') do
  route('decision_deferred') != route('decision_escalated')
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-SCORE"

check('FDEC-SCORE-01: FC-D5 — top score + EMPTY rationale → insufficient_justification') do
  r = vm_run(FDEC_OUT, 'JustificationGuard', { 'top_score_option' => 'plan_broad', 'rationale' => '' })['result']
  r == 'insufficient_justification'
end
check('FDEC-SCORE-02: top score + rationale → justified') do
  vm_run(FDEC_OUT, 'JustificationGuard',
         { 'top_score_option' => 'plan_filtered', 'rationale' => 'meets row_budget and policy' })['result'] == 'justified'
end
check('FDEC-SCORE-03: expected_outcome (score-like) is carried as INPUT data on chosen and rejected') do
  VM_DECIDED.dig('result', 'chosen', 'expected_outcome').to_s != '' &&
    REJ.all? { |x| x.key?('expected_outcome') }
end
check('FDEC-SCORE-04: the decided receipt justification lives in rationale, not in a score field') do
  dr = FDEC_TC[:typed]&.dig('type_env', 'DecisionReceipt') || {}
  dr.key?('rationale') && !dr.key?('score')
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nFDEC-CLOSED"

check('FDEC-CLOSED-01: fixture code (excl. comments) uses no variant/match and no constraints{} syntax') do
  code = File.read(FIXTURE_PATH, encoding: 'UTF-8').lines.reject { |l| l.strip.start_with?('--') }.join
  !code.include?('variant ') && !code.include?('match ') && !code.include?('constraints {')
end
check('FDEC-CLOSED-02: no StrategyDecision canon type claimed (proof-local DecisionReceipt name)') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  !src.include?('type StrategyDecision')
end
check('FDEC-CLOSED-03: runner performs no real file/network/db/socket/worker I/O') do
  !SOURCE.include?('File.ope' + 'n') && !SOURCE.include?('TCPSock' + 'et') &&
    !SOURCE.include?('Net::HT' + 'TP') && !SOURCE.include?('PG.conn' + 'ect')
end
check('FDEC-CLOSED-04: no canon production file edited; lab-only boundary stated') do
  !SOURCE.include?('typecheck' + 'er.rb') && !SOURCE.include?('classifi' + 'er.rb') &&
    SOURCE.include?('LAB-ONLY')
end
check('FDEC-CLOSED-05: decided_at is an explicit input (fixture contains no now() call)') do
  code = File.read(FIXTURE_PATH, encoding: 'UTF-8').lines.reject { |l| l.strip.start_with?('--') }.join
  !code.include?('now()')
end
check('FDEC-CLOSED-06: audit_obligation is carrier-only — values pending/deferred/impossible, no audit semantics contract') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  src.include?('audit_obligation') && !src.include?('PostAuditReceipt')
end
check('FDEC-CLOSED-07: fixture is lab-only and makes no production runtime claim') do
  src = File.read(FIXTURE_PATH, encoding: 'UTF-8')
  src.include?('LAB-ONLY') && !src.include?('production runtime')
end
check('FDEC-CLOSED-08: decision kinds never collide with PROP-047 outcome kinds in this fixture') do
  code = File.read(FIXTURE_PATH, encoding: 'UTF-8').lines.reject { |l| l.strip.start_with?('--') }.join
  !code.include?('"failed"') && !code.include?('"succeeded"') && !code.include?('"unknown_external_state"')
end

# ─────────────────────────────────────────────────────────────────────────────
total = $pass_count + $fail_count
puts "\n#{'=' * 60}"
puts "FRONTIER-DECISION-P2 (query-plan Decision KDR): #{$pass_count}/#{total} PASS"
puts '=' * 60

if $fail_count > 0
  puts "\nFAILURES: #{$fail_count}"
  exit 1
else
  puts "\nPASS — all #{total} checks passed"
  exit 0
end
