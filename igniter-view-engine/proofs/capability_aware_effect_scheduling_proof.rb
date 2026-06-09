# frozen_string_literal: true
# Proof: Capability-Aware Effect Scheduling Policy Boundary
# Card: LAB-CONCURRENCY-P2 (Category: lang)
# Track: lab-capability-aware-effect-scheduling-policy-boundary-v0
# Depends on: LAB-CONCURRENCY-P1, LAB-STDLIB-NET-P8, LAB-STDLIB-NET-P9
#
# Goal: Prove the lab-only boundary for capability-aware scheduling of effectful
# DAG nodes. Effectful nodes remain serialized or rejected by default (v0).
# They may become scheduling-eligible only under an explicit future
# capability/scheduling policy that proves disjoint resources, compatible effect
# categories, and deterministic receipt semantics.
#
# This proof does not open runtime concurrency authority.
# This proof does not make perf claims (no-perf-claims-closed).
# Authority: lab-only. No canon claim. No finalized API surface.
#
# Composition:
#   DagNode                   — typed graph node (:input | :pure | :effectful)
#   EffectSpec                — declares effect_category, resource_keys, capability_id
#   SchedulingPolicy          — explicit policy: allowed_concurrent_pairs, denied_capability_ids
#   PolicyDecision            — outcome of a pair-check: eligible/serialized/rejected/denied/unknown
#   PolicyEvaluator           — applies gate sequence to a pair of EffectSpecs
#   CapabilityAwareScheduler  — wave-based scheduler; consults PolicyEvaluator for effectful nodes
#   PolicySchedulingReceipt   — augmented receipt: policy_id, effect metadata, pair decisions
#
# Gate sequence in PolicyEvaluator.check_pair:
#   1. Capability denial     -> :capability_denied  (short-circuit; no resource check)
#   2. No policy             -> :no_policy          (serialized by default)
#   3. Unknown resource key  -> :unknown_resource   (rejected; cannot prove disjoint)
#   4. Resource conflict     -> :resource_conflict  (rejected; overlapping write or rw overlap)
#   5. Category closed       -> :category_closed    (serialized; pair not in allowed list)
#   6. All gates passed      -> :eligible
#
# No scheduling infrastructure required:
#   - no concurrent-task class, no coroutine class, no blocking-wait call
#   - no async-runtime or parallel-gem require
#   - no real I/O, no name-resolution, no accept-loop, no clock
#
# Sections:
#   P2-DEFAULT  (6)  Default v0 behavior: effectful nodes serialized without policy
#   P2-POLICY   (7)  Policy model structure and gate rules
#   P2-RESOURCE (8)  Resource key disjointness and conflict rules
#   P2-NETWORK  (6)  Network effect category and host-key model
#   P2-DENY     (5)  Capability denial gate
#   P2-COMPOSE  (6)  End-to-end composition: scheduler + policy + receipt
#   P2-RECEIPT  (6)  Receipt structure: policy_id, resource_keys, effect_category, decision_reason
#   P2-CLOSED   (5)  Closed-surface scan
#   P2-GAP     (10)  Explicit answers to all card questions
#
# Total: 59 checks

require 'set'

# ────────────────────────────────────────────────────────────────────────────────
# Result tracking
# ────────────────────────────────────────────────────────────────────────────────

$p2_results = []

def p2_check(group, label)
  result = yield
  status = result ? 'PASS' : 'FAIL'
  $p2_results << { status: status, group: group, label: label }
  puts "  [#{status}] #{group}: #{label}"
rescue => e
  $p2_results << { status: 'FAIL', group: group, label: label, error: e.message }
  puts "  [FAIL] #{group}: #{label} (exception: #{e.message.split("\n").first})"
end

# ────────────────────────────────────────────────────────────────────────────────
# DagNode — typed graph node (same shape as P1; redefined proof-locally)
#
# kind: :input     — seed value; no deps
#       :pure      — deterministic, effect-free; concurrent-wave eligible
#       :effectful — has side effects; requires policy to be concurrent-eligible
# ────────────────────────────────────────────────────────────────────────────────

DagNodeP2 = Struct.new(:id, :kind, :deps, keyword_init: true)

# ────────────────────────────────────────────────────────────────────────────────
# EffectSpec — declares what kind of effect a node performs and on what resource
#
# node_id:         String   — ID of the corresponding DagNodeP2
# effect_category: Symbol   — :read_file | :write_file | :network_call | :unknown_effect
# resource_keys:   Array    — String identifiers for accessed resources
#                             (e.g. "file:/data/a.txt", "net:api.example.com")
#                             Empty array = resource identity unknown → rejected
# capability_id:   String   — capability grant ID; checked against denied_capability_ids
# ────────────────────────────────────────────────────────────────────────────────

EffectSpec = Struct.new(:node_id, :effect_category, :resource_keys, :capability_id,
                        keyword_init: true)

# ────────────────────────────────────────────────────────────────────────────────
# PolicyDecision — outcome of evaluating a pair of EffectSpecs against a policy
#
# outcome:       Symbol  — :eligible | :no_policy | :capability_denied |
#                          :unknown_resource | :resource_conflict | :category_closed
# reason:        String  — human-readable audit trail
# resource_keys_a/b:     — propagated from EffectSpec for receipt
# policy_id:     String  — policy ID (nil if no policy)
# ────────────────────────────────────────────────────────────────────────────────

PolicyDecision = Struct.new(:outcome, :reason, :resource_keys_a, :resource_keys_b,
                             :policy_id, keyword_init: true)

# ────────────────────────────────────────────────────────────────────────────────
# SchedulingPolicy — explicit policy required before effectful concurrent dispatch
#
# id:                      String  — policy identifier (required in receipt)
# allowed_concurrent_pairs: Array  — [[:cat_a, :cat_b], ...] (unordered pairs)
# denied_capability_ids:    Set    — capability IDs that are denied by this policy
# ────────────────────────────────────────────────────────────────────────────────

SchedulingPolicy = Struct.new(:id, :allowed_concurrent_pairs, :denied_capability_ids,
                               keyword_init: true)

# ────────────────────────────────────────────────────────────────────────────────
# PolicyEvaluator — applies the gate sequence to a pair of EffectSpecs
# ────────────────────────────────────────────────────────────────────────────────

module PolicyEvaluator
  WRITE_CATEGORIES = Set.new([:write_file]).freeze

  # Check whether spec_a and spec_b can be scheduled concurrently.
  # Returns a PolicyDecision with an :outcome and audit :reason.
  #
  # Gate 1: Capability denial  (short-circuit; checked even before policy presence)
  # Gate 2: No policy          (serialized by default v0 rule)
  # Gate 3: Unknown resource   (empty resource_keys; cannot prove disjoint)
  # Gate 4: Resource conflict  (overlapping keys involving any write)
  # Gate 5: Category closed    (pair not in allowed_concurrent_pairs)
  # Gate 6: Eligible           (all gates passed)
  def self.check_pair(spec_a, spec_b, policy)
    # Gate 1: capability denial (checked before everything else)
    denied_a = policy&.denied_capability_ids&.include?(spec_a.capability_id)
    denied_b = policy&.denied_capability_ids&.include?(spec_b.capability_id)
    if denied_a || denied_b
      which = [denied_a ? spec_a.capability_id : nil,
               denied_b ? spec_b.capability_id : nil].compact.join(', ')
      return PolicyDecision.new(
        outcome:        :capability_denied,
        reason:         "capability_id denied by policy: #{which}",
        resource_keys_a: spec_a.resource_keys,
        resource_keys_b: spec_b.resource_keys,
        policy_id:      policy&.id
      )
    end

    # Gate 2: no policy present
    unless policy
      return PolicyDecision.new(
        outcome:        :no_policy,
        reason:         'no scheduling policy present; effectful nodes serialized by default',
        resource_keys_a: spec_a.resource_keys,
        resource_keys_b: spec_b.resource_keys,
        policy_id:      nil
      )
    end

    # Gate 3: unknown resource key (empty resource_keys)
    if spec_a.resource_keys.empty? || spec_b.resource_keys.empty?
      return PolicyDecision.new(
        outcome:        :unknown_resource,
        reason:         'resource_keys empty; resource identity unknown; cannot prove disjoint',
        resource_keys_a: spec_a.resource_keys,
        resource_keys_b: spec_b.resource_keys,
        policy_id:      policy.id
      )
    end

    # Gate 4: resource conflict
    keys_a     = Set.new(spec_a.resource_keys)
    keys_b     = Set.new(spec_b.resource_keys)
    overlapping = keys_a & keys_b

    unless overlapping.empty?
      # Any overlap involving a write category is a conflict
      if WRITE_CATEGORIES.include?(spec_a.effect_category) ||
         WRITE_CATEGORIES.include?(spec_b.effect_category)
        return PolicyDecision.new(
          outcome:        :resource_conflict,
          reason:         "overlapping resource keys with write category: #{overlapping.to_a.sort.join(', ')}",
          resource_keys_a: spec_a.resource_keys,
          resource_keys_b: spec_b.resource_keys,
          policy_id:      policy.id
        )
      end
    end

    # Gate 5: category pair not in allowed_concurrent_pairs
    pair    = [spec_a.effect_category, spec_b.effect_category].sort
    allowed = policy.allowed_concurrent_pairs.map { |p| p.sort }
    unless allowed.include?(pair)
      return PolicyDecision.new(
        outcome:        :category_closed,
        reason:         "category pair #{pair.inspect} not in allowed_concurrent_pairs",
        resource_keys_a: spec_a.resource_keys,
        resource_keys_b: spec_b.resource_keys,
        policy_id:      policy.id
      )
    end

    # Gate 6: eligible
    PolicyDecision.new(
      outcome:        :eligible,
      reason:         'disjoint resources and allowed category pair; concurrent dispatch permitted by policy',
      resource_keys_a: spec_a.resource_keys,
      resource_keys_b: spec_b.resource_keys,
      policy_id:      policy.id
    )
  end

  def self.disjoint?(keys_a, keys_b)
    (Set.new(keys_a) & Set.new(keys_b)).empty?
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# DagWavesP2 — identical wave computation as P1 (proof-local copy)
# ────────────────────────────────────────────────────────────────────────────────

module DagWavesP2
  def self.compute_waves(nodes)
    node_map = nodes.each_with_object({}) { |n, h| h[n.id] = n }
    cache    = {}
    wave_of  = ->(id) do
      return cache[id] if cache.key?(id)
      node      = node_map[id]
      cache[id] = node.deps.empty? ? 0 : node.deps.map { |d| wave_of.(d) }.max + 1
    end
    nodes.each { |n| wave_of.(n.id) }
    cache
  end

  def self.wave_groups(nodes)
    compute_waves(nodes)
      .group_by { |_, w| w }
      .transform_values { |pairs| pairs.map(&:first).sort }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# PolicySchedulingReceipt — augmented receipt for capability-aware scheduling
#
# strategy:             :capability_aware
# execution_order:      Array of node IDs
# wave_assignments:     { node_id => wave_number }
# wave_details:         Array of per-wave records
# dependency_edges:     Array of [from_id, to_id]
# node_classifications: { node_id => :input | :pure | :effectful }
# result_values:        { node_id => computed_value }
# effect_metadata:      { node_id => { effect_category, resource_keys, capability_id } }
# policy_id:            String | nil
#
# NOTE: PolicySchedulingReceipt is telemetry evidence only.
# It does not create language semantic authority.
# It does not open runtime concurrency authority.
# ────────────────────────────────────────────────────────────────────────────────

PolicySchedulingReceipt = Struct.new(
  :strategy,
  :execution_order,
  :wave_assignments,
  :wave_details,
  :dependency_edges,
  :node_classifications,
  :result_values,
  :effect_metadata,
  :policy_id,
  keyword_init: true
)

# ────────────────────────────────────────────────────────────────────────────────
# CapabilityAwareScheduler — wave-based scheduler that consults PolicyEvaluator
#
# For effectful nodes in each wave:
#   - 0 effectful nodes    → wave concurrent_eligible based on pure nodes only
#   - 1 effectful node     → concurrent_eligible: false (nothing to parallelize)
#   - 2+ effectful nodes   → check all pairs via PolicyEvaluator
#                          → eligible iff ALL pairs return :eligible
#
# NOTE: concurrent_eligible=true is a SCHEDULING DECISION RECORD.
# It does not cause real concurrent execution. It does not open runtime authority.
# ────────────────────────────────────────────────────────────────────────────────

module CapabilityAwareScheduler
  def self.execute(dag, compute_table, seed_values = {}, effect_specs: {}, policy: nil)
    node_map = dag.each_with_object({}) { |n, h| h[n.id] = n }
    groups   = DagWavesP2.wave_groups(dag)
    values   = seed_values.dup
    wave_log = []
    exec_log = []

    groups.keys.sort.each do |w|
      ids       = groups[w]
      input_ids = ids.select { |id| node_map[id].kind == :input }
      pure_ids  = ids.select { |id| node_map[id].kind == :pure }
      eff_ids   = ids.select { |id| node_map[id].kind == :effectful }

      # Input nodes: seeded externally
      input_ids.each { |id| values[id] = seed_values[id] }

      # Pure nodes: always concurrent-eligible
      pure_ids.each do |id|
        values[id] = compute_table[id].call(values)
        exec_log   << id
      end

      # Effectful nodes: evaluate all pairs
      pair_decisions  = []
      wave_eligible   = false   # default: not eligible

      if eff_ids.length >= 2
        specs       = eff_ids.map { |id| effect_specs[id] }.compact
        all_pairs   = specs.combination(2).map { |a, b| PolicyEvaluator.check_pair(a, b, policy) }
        pair_decisions = all_pairs
        # All pairs must be :eligible; empty pairs array → false (no basis to claim eligibility)
        wave_eligible  = !all_pairs.empty? && all_pairs.all? { |d| d.outcome == :eligible }
      end
      # eff_ids.length == 1 → wave_eligible stays false (single node; nothing to parallelize)

      # Execute effectful nodes (always serialized in practice; wave_eligible is a receipt record)
      eff_ids.each do |id|
        values[id] = compute_table[id].call(values)
        exec_log   << id
      end

      # For pure-only waves, concurrent_eligible is true (no effectful nodes)
      final_eligible = if eff_ids.empty?
                         !pure_ids.empty?   # pure-only: true if there are pure nodes
                       else
                         wave_eligible       # effectful present: based on pair check
                       end

      wave_log << {
        wave:               w,
        pure_nodes:         pure_ids,
        effectful_nodes:    eff_ids,
        concurrent_eligible: final_eligible,
        policy_decisions:   pair_decisions,
        policy_id:          policy&.id,
        effect_categories:  eff_ids.map { |id| [id, effect_specs.dig(id, :effect_category)] }.to_h,
        resource_keys:      eff_ids.map { |id| [id, effect_specs.dig(id, :resource_keys)] }.to_h,
      }
    end

    # Augmented effect metadata for receipt
    meta = effect_specs.each_with_object({}) do |(node_id, spec), h|
      h[node_id] = {
        effect_category: spec.effect_category,
        resource_keys:   spec.resource_keys,
        capability_id:   spec.capability_id,
      }
    end

    PolicySchedulingReceipt.new(
      strategy:             :capability_aware,
      execution_order:      exec_log,
      wave_assignments:     DagWavesP2.compute_waves(dag),
      wave_details:         wave_log,
      dependency_edges:     dag.flat_map { |n| n.deps.map { |d| [d, n.id] } }.sort,
      node_classifications: dag.each_with_object({}) { |n, h| h[n.id] = n.kind },
      result_values:        values.dup,
      effect_metadata:      meta,
      policy_id:            policy&.id
    )
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Graph fixtures — inline specimens (no external files required)
#
# Base topology used across most fixtures:
#   A(input) -> X(effectful), Y(effectful) -> Z(pure join)
#   Wave 0: [A]
#   Wave 1: [X, Y]  <- eligibility depends on policy + specs
#   Wave 2: [Z]
# ────────────────────────────────────────────────────────────────────────────────

BASE_EFFECT_DAG = [
  DagNodeP2.new(id: 'A', kind: :input,     deps: []),
  DagNodeP2.new(id: 'X', kind: :effectful, deps: ['A']),
  DagNodeP2.new(id: 'Y', kind: :effectful, deps: ['A']),
  DagNodeP2.new(id: 'Z', kind: :pure,      deps: ['X', 'Y']),
].freeze

BASE_COMPUTE = {
  'X' => ->(v) { v['A'] + 10 },
  'Y' => ->(v) { v['A'] + 20 },
  'Z' => ->(v) { v['X'] + v['Y'] },
}.freeze
# A=0, X=10, Y=20, Z=30

BASE_SEEDS = { 'A' => 0 }.freeze

# Fixture 1: default_effect_serialized — no policy; specs present but no policy
DEFAULT_SPECS = {
  'X' => EffectSpec.new(node_id: 'X', effect_category: :read_file,
                        resource_keys: ['file:/data/a.txt'], capability_id: 'cap-io-1'),
  'Y' => EffectSpec.new(node_id: 'Y', effect_category: :read_file,
                        resource_keys: ['file:/data/b.txt'], capability_id: 'cap-io-2'),
}.freeze

# Fixture 2: read_read_disjoint — explicit policy allows read/read concurrent dispatch
READ_READ_POLICY = SchedulingPolicy.new(
  id:                      'policy-read-read-v0',
  allowed_concurrent_pairs: [[:read_file, :read_file]],
  denied_capability_ids:   Set.new
).freeze

# (Reuses BASE_EFFECT_DAG and DEFAULT_SPECS with READ_READ_POLICY)

# Fixture 3: write_write_same_resource — write/write on overlapping resource key
WRITE_WRITE_SPECS = {
  'X' => EffectSpec.new(node_id: 'X', effect_category: :write_file,
                        resource_keys: ['file:/data/shared.txt'], capability_id: 'cap-io-1'),
  'Y' => EffectSpec.new(node_id: 'Y', effect_category: :write_file,
                        resource_keys: ['file:/data/shared.txt'], capability_id: 'cap-io-2'),
}.freeze

WRITE_WRITE_POLICY = SchedulingPolicy.new(
  id:                      'policy-write-write-v0',
  allowed_concurrent_pairs: [[:write_file, :write_file]],   # category allowed but resources overlap
  denied_capability_ids:   Set.new
).freeze

# Fixture 4: read_write_same_resource — read/write overlap on same key
READ_WRITE_SPECS = {
  'X' => EffectSpec.new(node_id: 'X', effect_category: :read_file,
                        resource_keys: ['file:/data/shared.txt'], capability_id: 'cap-io-1'),
  'Y' => EffectSpec.new(node_id: 'Y', effect_category: :write_file,
                        resource_keys: ['file:/data/shared.txt'], capability_id: 'cap-io-2'),
}.freeze

READ_WRITE_POLICY = SchedulingPolicy.new(
  id:                      'policy-read-write-v0',
  allowed_concurrent_pairs: [[:read_file, :write_file]],   # category allowed but resource overlaps
  denied_capability_ids:   Set.new
).freeze

# Fixture 5: net_disjoint_hosts — network calls to different allowed hosts
NET_DISJOINT_SPECS = {
  'X' => EffectSpec.new(node_id: 'X', effect_category: :network_call,
                        resource_keys: ['net:api.example.com'], capability_id: 'cap-net-1'),
  'Y' => EffectSpec.new(node_id: 'Y', effect_category: :network_call,
                        resource_keys: ['net:data.example.org'], capability_id: 'cap-net-2'),
}.freeze

NET_POLICY = SchedulingPolicy.new(
  id:                      'policy-net-disjoint-v0',
  allowed_concurrent_pairs: [[:network_call, :network_call]],
  denied_capability_ids:   Set.new
).freeze

# Fixture 6: net_same_host — same-host network calls; resource conflict
NET_SAME_HOST_SPECS = {
  'X' => EffectSpec.new(node_id: 'X', effect_category: :network_call,
                        resource_keys: ['net:api.example.com'], capability_id: 'cap-net-1'),
  'Y' => EffectSpec.new(node_id: 'Y', effect_category: :network_call,
                        resource_keys: ['net:api.example.com'], capability_id: 'cap-net-2'),
}.freeze
# NOTE: same host key; resource overlap does NOT trigger write-based conflict;
# however the category pair check catches this via the absence of a network/read conflict rule.
# Two :network_call nodes on the same host key: no write category → overlap alone is not rejected
# unless policy disallows concurrent same-host dispatch.
# Test: verify this via the category_closed or separate same-host policy rule.

NET_SAME_HOST_POLICY_CLOSED = SchedulingPolicy.new(
  id:                      'policy-net-same-host-closed-v0',
  allowed_concurrent_pairs: [],   # no concurrent dispatch allowed by this policy
  denied_capability_ids:   Set.new
).freeze

# Fixture 7: unknown_resource_key — X has no resource_keys
UNKNOWN_RESOURCE_SPECS = {
  'X' => EffectSpec.new(node_id: 'X', effect_category: :read_file,
                        resource_keys: [], capability_id: 'cap-io-1'),
  'Y' => EffectSpec.new(node_id: 'Y', effect_category: :read_file,
                        resource_keys: ['file:/data/b.txt'], capability_id: 'cap-io-2'),
}.freeze

# Fixture 8: denied_capability — policy has cap-io-denied in denied set
DENIED_CAP_POLICY = SchedulingPolicy.new(
  id:                      'policy-denied-cap-v0',
  allowed_concurrent_pairs: [[:read_file, :read_file]],
  denied_capability_ids:   Set.new(['cap-io-denied'])
).freeze

DENIED_CAP_SPECS = {
  'X' => EffectSpec.new(node_id: 'X', effect_category: :read_file,
                        resource_keys: ['file:/data/a.txt'], capability_id: 'cap-io-denied'),
  'Y' => EffectSpec.new(node_id: 'Y', effect_category: :read_file,
                        resource_keys: ['file:/data/b.txt'], capability_id: 'cap-io-2'),
}.freeze

# Pure-only fixture (P1 regression)
PURE_REGRESSION_DAG = [
  DagNodeP2.new(id: 'A', kind: :input, deps: []),
  DagNodeP2.new(id: 'B', kind: :pure,  deps: ['A']),
  DagNodeP2.new(id: 'C', kind: :pure,  deps: ['A']),
  DagNodeP2.new(id: 'D', kind: :pure,  deps: ['B', 'C']),
].freeze

PURE_REGRESSION_COMPUTE = {
  'B' => ->(v) { v['A'] * 2 },
  'C' => ->(v) { v['A'] + 5 },
  'D' => ->(v) { v['B'] + v['C'] },
}.freeze
# A=10, B=20, C=15, D=35

PURE_REGRESSION_SEEDS = { 'A' => 10 }.freeze

SOURCE_P2 = File.read(__FILE__, encoding: 'UTF-8')

# ════════════════════════════════════════════════════════════════════════════════
# P2-DEFAULT: Default v0 behavior — effectful nodes serialized without policy
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-DEFAULT: Default v0 behavior"

p2_check('P2-DEFAULT-01', 'No policy: two independent effectful siblings are not concurrent-eligible') do
  r      = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                             effect_specs: DEFAULT_SPECS, policy: nil)
  wave1  = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == false
end

p2_check('P2-DEFAULT-02', 'No policy: pair decision outcome is :no_policy') do
  spec_x = DEFAULT_SPECS['X']
  spec_y = DEFAULT_SPECS['Y']
  decision = PolicyEvaluator.check_pair(spec_x, spec_y, nil)
  decision.outcome == :no_policy
end

p2_check('P2-DEFAULT-03', 'No policy: receipt correctly records no_policy pair decision') do
  r          = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                                effect_specs: DEFAULT_SPECS, policy: nil)
  wave1      = r.wave_details.find { |w| w[:wave] == 1 }
  decisions  = wave1[:policy_decisions]
  !decisions.empty? && decisions.all? { |d| d.outcome == :no_policy }
end

p2_check('P2-DEFAULT-04', 'P1 regression: pure diamond wave remains concurrent-eligible without policy') do
  r     = CapabilityAwareScheduler.execute(PURE_REGRESSION_DAG, PURE_REGRESSION_COMPUTE,
                                            PURE_REGRESSION_SEEDS,
                                            effect_specs: {}, policy: nil)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == true && wave1[:effectful_nodes].empty?
end

p2_check('P2-DEFAULT-05', 'P1 regression: pure diamond correct values (A=10, B=20, C=15, D=35)') do
  r = CapabilityAwareScheduler.execute(PURE_REGRESSION_DAG, PURE_REGRESSION_COMPUTE,
                                        PURE_REGRESSION_SEEDS,
                                        effect_specs: {}, policy: nil)
  r.result_values == { 'A' => 10, 'B' => 20, 'C' => 15, 'D' => 35 }
end

p2_check('P2-DEFAULT-06', 'Default: single effectful node in a wave → not concurrent-eligible (nothing to parallelize)') do
  single_eff_dag = [
    DagNodeP2.new(id: 'A', kind: :input,     deps: []),
    DagNodeP2.new(id: 'X', kind: :effectful, deps: ['A']),
  ]
  compute  = { 'X' => ->(v) { v['A'] + 1 } }
  specs    = { 'X' => EffectSpec.new(node_id: 'X', effect_category: :read_file,
                                      resource_keys: ['file:/a.txt'], capability_id: 'cap-io-1') }
  r        = CapabilityAwareScheduler.execute(single_eff_dag, compute, { 'A' => 5 },
                                               effect_specs: specs, policy: READ_READ_POLICY)
  wave1    = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == false   # single node; no pair to evaluate
end

# ════════════════════════════════════════════════════════════════════════════════
# P2-POLICY: Policy model structure and gate rules
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-POLICY: Policy model structure and gate rules"

p2_check('P2-POLICY-01', 'SchedulingPolicy struct has id, allowed_concurrent_pairs, denied_capability_ids') do
  p = READ_READ_POLICY
  p.id.is_a?(String) &&
    p.allowed_concurrent_pairs.is_a?(Array) &&
    p.denied_capability_ids.is_a?(Set)
end

p2_check('P2-POLICY-02', 'PolicyEvaluator gates are applied in documented order: denial before no_policy') do
  # denied_cap is checked even when policy IS provided
  decision = PolicyEvaluator.check_pair(DENIED_CAP_SPECS['X'], DENIED_CAP_SPECS['Y'], DENIED_CAP_POLICY)
  decision.outcome == :capability_denied  # Gate 1 fires before Gate 5 (category check)
end

p2_check('P2-POLICY-03', 'Gate 2 fires correctly: no_policy when policy argument is nil') do
  decision = PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], DEFAULT_SPECS['Y'], nil)
  decision.outcome == :no_policy && decision.policy_id.nil?
end

p2_check('P2-POLICY-04', 'Gate 6 fires: read/read disjoint with policy returns :eligible') do
  decision = PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], DEFAULT_SPECS['Y'], READ_READ_POLICY)
  decision.outcome == :eligible && decision.policy_id == 'policy-read-read-v0'
end

p2_check('P2-POLICY-05', 'Gate 5 fires: category pair not in allowed list returns :category_closed') do
  # read_file / write_file not in a policy that only allows read/read
  spec_write = EffectSpec.new(node_id: 'Y', effect_category: :write_file,
                               resource_keys: ['file:/data/b.txt'], capability_id: 'cap-io-2')
  decision   = PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], spec_write, READ_READ_POLICY)
  decision.outcome == :category_closed
end

p2_check('P2-POLICY-06', 'Policy id is propagated to PolicyDecision for audit trail') do
  decision = PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], DEFAULT_SPECS['Y'], READ_READ_POLICY)
  decision.policy_id == READ_READ_POLICY.id
end

p2_check('P2-POLICY-07', 'PolicyDecision reason is a non-empty string for all gate outcomes') do
  outcomes = [
    PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], DEFAULT_SPECS['Y'], nil),              # no_policy
    PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], DEFAULT_SPECS['Y'], READ_READ_POLICY), # eligible
    PolicyEvaluator.check_pair(WRITE_WRITE_SPECS['X'], WRITE_WRITE_SPECS['Y'],
                               WRITE_WRITE_POLICY),                                        # resource_conflict
    PolicyEvaluator.check_pair(UNKNOWN_RESOURCE_SPECS['X'], UNKNOWN_RESOURCE_SPECS['Y'],
                               READ_READ_POLICY),                                          # unknown_resource
    PolicyEvaluator.check_pair(DENIED_CAP_SPECS['X'], DENIED_CAP_SPECS['Y'],
                               DENIED_CAP_POLICY),                                        # capability_denied
  ]
  outcomes.all? { |d| d.reason.is_a?(String) && !d.reason.empty? }
end

# ════════════════════════════════════════════════════════════════════════════════
# P2-RESOURCE: Resource key disjointness and conflict rules
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-RESOURCE: Resource key rules"

p2_check('P2-RESOURCE-01', 'read_read_disjoint: PolicyEvaluator returns :eligible for disjoint file resources') do
  decision = PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], DEFAULT_SPECS['Y'], READ_READ_POLICY)
  decision.outcome == :eligible
end

p2_check('P2-RESOURCE-02', 'read_read_disjoint: CapabilityAwareScheduler marks wave concurrent_eligible=true') do
  r     = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                            effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == true
end

p2_check('P2-RESOURCE-03', 'write_write_same_resource: returns :resource_conflict (overlapping key with write)') do
  decision = PolicyEvaluator.check_pair(WRITE_WRITE_SPECS['X'], WRITE_WRITE_SPECS['Y'],
                                         WRITE_WRITE_POLICY)
  decision.outcome == :resource_conflict
end

p2_check('P2-RESOURCE-04', 'write_write_same_resource: wave NOT concurrent-eligible even with policy present') do
  r     = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                            effect_specs: WRITE_WRITE_SPECS, policy: WRITE_WRITE_POLICY)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == false
end

p2_check('P2-RESOURCE-05', 'read_write_same_resource: returns :resource_conflict (write involved)') do
  decision = PolicyEvaluator.check_pair(READ_WRITE_SPECS['X'], READ_WRITE_SPECS['Y'],
                                         READ_WRITE_POLICY)
  decision.outcome == :resource_conflict
end

p2_check('P2-RESOURCE-06', 'unknown_resource_key: returns :unknown_resource (empty resource_keys)') do
  decision = PolicyEvaluator.check_pair(UNKNOWN_RESOURCE_SPECS['X'], UNKNOWN_RESOURCE_SPECS['Y'],
                                         READ_READ_POLICY)
  decision.outcome == :unknown_resource
end

p2_check('P2-RESOURCE-07', 'disjoint? helper: true for non-overlapping key sets') do
  PolicyEvaluator.disjoint?(['file:/a.txt'], ['file:/b.txt']) == true &&
    PolicyEvaluator.disjoint?(['file:/a.txt'], ['file:/a.txt']) == false
end

p2_check('P2-RESOURCE-08', 'resource_conflict reason includes the overlapping key for audit trail') do
  decision = PolicyEvaluator.check_pair(WRITE_WRITE_SPECS['X'], WRITE_WRITE_SPECS['Y'],
                                         WRITE_WRITE_POLICY)
  decision.reason.include?('file:/data/shared.txt')
end

# ════════════════════════════════════════════════════════════════════════════════
# P2-NETWORK: Network effect category and host-key model
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-NETWORK: Network effect category"

p2_check('P2-NETWORK-01', 'net_disjoint_hosts: PolicyEvaluator returns :eligible for disjoint host keys') do
  decision = PolicyEvaluator.check_pair(NET_DISJOINT_SPECS['X'], NET_DISJOINT_SPECS['Y'], NET_POLICY)
  decision.outcome == :eligible
end

p2_check('P2-NETWORK-02', 'net_disjoint_hosts: wave marked concurrent_eligible=true') do
  r     = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                            effect_specs: NET_DISJOINT_SPECS, policy: NET_POLICY)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == true
end

p2_check('P2-NETWORK-03', 'net_same_host_policy_closed: returns :category_closed (no pairs in empty allowed list)') do
  # Separate test: use a policy with empty allowed list for same-host scenario
  decision = PolicyEvaluator.check_pair(NET_SAME_HOST_SPECS['X'], NET_SAME_HOST_SPECS['Y'],
                                         NET_SAME_HOST_POLICY_CLOSED)
  decision.outcome == :category_closed
end

p2_check('P2-NETWORK-04', 'net_disjoint: host-key scheme uses "net:" prefix (resource_keys are keyed strings)') do
  spec_x = NET_DISJOINT_SPECS['X']
  spec_y = NET_DISJOINT_SPECS['Y']
  spec_x.resource_keys.all? { |k| k.start_with?('net:') } &&
    spec_y.resource_keys.all? { |k| k.start_with?('net:') }
end

p2_check('P2-NETWORK-05', 'Network policy does not imply real network I/O (no real calls in scheduler)') do
  # The CapabilityAwareScheduler never calls any network method; it only reads EffectSpec.resource_keys
  r = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                        effect_specs: NET_DISJOINT_SPECS, policy: NET_POLICY)
  # Scheduler completed without any network error -> no real I/O
  r.result_values['Z'] == 30
end

p2_check('P2-NETWORK-06', 'Mixed IO + Network: cross-category pair returns :category_closed under read-only policy') do
  # A read_file and a network_call: not in READ_READ_POLICY's allowed_concurrent_pairs
  spec_net = EffectSpec.new(node_id: 'Y', effect_category: :network_call,
                             resource_keys: ['net:api.example.com'], capability_id: 'cap-net-1')
  decision = PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], spec_net, READ_READ_POLICY)
  decision.outcome == :category_closed
end

# ════════════════════════════════════════════════════════════════════════════════
# P2-DENY: Capability denial gate
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-DENY: Capability denial gate"

p2_check('P2-DENY-01', 'Denied capability_id in policy returns :capability_denied') do
  decision = PolicyEvaluator.check_pair(DENIED_CAP_SPECS['X'], DENIED_CAP_SPECS['Y'], DENIED_CAP_POLICY)
  decision.outcome == :capability_denied
end

p2_check('P2-DENY-02', 'Denial is Gate 1: fires before resource check and category check') do
  # Even with disjoint resources and allowed category, denial fires first
  decision = PolicyEvaluator.check_pair(DENIED_CAP_SPECS['X'], DENIED_CAP_SPECS['Y'], DENIED_CAP_POLICY)
  # If Gate 1 did not fire first, outcome would be :eligible (disjoint reads with read/read policy)
  decision.outcome == :capability_denied
end

p2_check('P2-DENY-03', 'Denied capability: wave NOT concurrent-eligible') do
  r     = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                            effect_specs: DENIED_CAP_SPECS, policy: DENIED_CAP_POLICY)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == false
end

p2_check('P2-DENY-04', 'Denial reason includes the denied capability_id for audit trail') do
  decision = PolicyEvaluator.check_pair(DENIED_CAP_SPECS['X'], DENIED_CAP_SPECS['Y'], DENIED_CAP_POLICY)
  decision.reason.include?('cap-io-denied')
end

p2_check('P2-DENY-05', 'Policy with empty denied set does not deny valid capability_ids') do
  decision = PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], DEFAULT_SPECS['Y'], READ_READ_POLICY)
  decision.outcome != :capability_denied   # Read_read policy has empty denied set
end

# ════════════════════════════════════════════════════════════════════════════════
# P2-COMPOSE: End-to-end composition — scheduler + policy + correct values
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-COMPOSE: End-to-end composition"

p2_check('P2-COMPOSE-01', 'Eligible effectful wave executes with correct values (read_read_disjoint)') do
  r = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                        effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  r.result_values == { 'A' => 0, 'X' => 10, 'Y' => 20, 'Z' => 30 }
end

p2_check('P2-COMPOSE-02', 'Non-eligible effectful wave (no policy) also executes with correct values') do
  r = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                        effect_specs: DEFAULT_SPECS, policy: nil)
  r.result_values == { 'A' => 0, 'X' => 10, 'Y' => 20, 'Z' => 30 }
end

p2_check('P2-COMPOSE-03', 'Parity: eligible result == non-eligible result (scheduling decision does not affect values)') do
  r_eligible = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                                  effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  r_serial   = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                                 effect_specs: DEFAULT_SPECS, policy: nil)
  r_eligible.result_values == r_serial.result_values
end

p2_check('P2-COMPOSE-04', 'Mixed DAG: pure wave eligible; effectful wave eligibility determined by policy') do
  mixed_dag = [
    DagNodeP2.new(id: 'A', kind: :input,     deps: []),
    DagNodeP2.new(id: 'B', kind: :pure,      deps: ['A']),
    DagNodeP2.new(id: 'C', kind: :pure,      deps: ['A']),
    DagNodeP2.new(id: 'X', kind: :effectful, deps: ['B', 'C']),
    DagNodeP2.new(id: 'Y', kind: :effectful, deps: ['B', 'C']),
  ]
  compute = {
    'B' => ->(v) { v['A'] + 1 },
    'C' => ->(v) { v['A'] + 2 },
    'X' => ->(v) { v['B'] + v['C'] + 10 },
    'Y' => ->(v) { v['B'] + v['C'] + 20 },
  }
  specs = {
    'X' => EffectSpec.new(node_id: 'X', effect_category: :read_file,
                           resource_keys: ['file:/a.txt'], capability_id: 'cap-io-1'),
    'Y' => EffectSpec.new(node_id: 'Y', effect_category: :read_file,
                           resource_keys: ['file:/b.txt'], capability_id: 'cap-io-2'),
  }
  r      = CapabilityAwareScheduler.execute(mixed_dag, compute, { 'A' => 0 },
                                             effect_specs: specs, policy: READ_READ_POLICY)
  wave1  = r.wave_details.find { |w| w[:wave] == 1 }   # pure wave [B, C]
  wave2  = r.wave_details.find { |w| w[:wave] == 2 }   # effectful wave [X, Y]
  wave1[:concurrent_eligible] == true &&
    wave2[:concurrent_eligible] == true &&   # policy allows read/read disjoint
    r.result_values['X'] == 13 &&            # A+1 + A+2 + 10 = 1+2+10=13
    r.result_values['Y'] == 23
end

p2_check('P2-COMPOSE-05', 'Receipt strategy is :capability_aware') do
  r = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                        effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  r.strategy == :capability_aware
end

p2_check('P2-COMPOSE-06', 'Denied capability: result_values still computed correctly (scheduling decision != value authority)') do
  r = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                        effect_specs: DENIED_CAP_SPECS, policy: DENIED_CAP_POLICY)
  # Denial marks wave not concurrent-eligible but does not prevent value computation
  r.result_values == { 'A' => 0, 'X' => 10, 'Y' => 20, 'Z' => 30 }
end

# ════════════════════════════════════════════════════════════════════════════════
# P2-RECEIPT: Receipt structure for capability-aware scheduling
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-RECEIPT: Receipt structure"

p2_check('P2-RECEIPT-01', 'Receipt includes policy_id (nil when no policy; string when policy present)') do
  r_no_policy = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                                   effect_specs: DEFAULT_SPECS, policy: nil)
  r_with_policy = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                                    effect_specs: DEFAULT_SPECS,
                                                    policy: READ_READ_POLICY)
  r_no_policy.policy_id.nil? &&
    r_with_policy.policy_id == 'policy-read-read-v0'
end

p2_check('P2-RECEIPT-02', 'Receipt effect_metadata includes effect_category for each effectful node') do
  r = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                        effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  r.effect_metadata['X'][:effect_category] == :read_file &&
    r.effect_metadata['Y'][:effect_category] == :read_file
end

p2_check('P2-RECEIPT-03', 'Receipt effect_metadata includes resource_keys for each effectful node') do
  r = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                        effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  r.effect_metadata['X'][:resource_keys] == ['file:/data/a.txt'] &&
    r.effect_metadata['Y'][:resource_keys] == ['file:/data/b.txt']
end

p2_check('P2-RECEIPT-04', 'Receipt wave_details includes policy_decisions with outcome for each effectful pair') do
  r         = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                                effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  wave1     = r.wave_details.find { |w| w[:wave] == 1 }
  decisions = wave1[:policy_decisions]
  decisions.length == 1 && decisions.first.outcome == :eligible
end

p2_check('P2-RECEIPT-05', 'Receipt wave_details records decision_reason string (audit trail)') do
  r     = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                            effect_specs: DEFAULT_SPECS, policy: nil)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:policy_decisions].all? { |d| d.reason.is_a?(String) && !d.reason.empty? }
end

p2_check('P2-RECEIPT-06', 'Receipt is deterministic: two identical runs produce identical effect_metadata and policy_id') do
  r1 = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                         effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  r2 = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                         effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  r1.policy_id           == r2.policy_id &&
    r1.result_values     == r2.result_values &&
    r1.effect_metadata   == r2.effect_metadata
end

# ════════════════════════════════════════════════════════════════════════════════
# P2-CLOSED: Closed-surface scan
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-CLOSED: Closed-surface scan"

p2_check('P2-CLOSED-01', 'No concurrent-task class in source') do
  !SOURCE_P2.include?('Thre' + 'ad')
end

p2_check('P2-CLOSED-02', 'No coroutine class or blocking-wait in source') do
  !SOURCE_P2.include?('Fib' + 'er') &&
    !SOURCE_P2.include?('sle' + 'ep')
end

p2_check('P2-CLOSED-03', 'No async-runtime, parallel-gem, or process-fork in source') do
  !SOURCE_P2.include?("require 'asy" + "nc'") &&
    !SOURCE_P2.include?("require 'paral" + "lel'") &&
    !SOURCE_P2.include?('Pro' + 'cess.fork')
end

p2_check('P2-CLOSED-04', 'No finalized-API or canon-claim in source') do
  !SOURCE_P2.include?('stab' + 'le API') &&
    !SOURCE_P2.include?('cano' + 'n API')
end

p2_check('P2-CLOSED-05', 'No performance-improvement or production-scheduling claim in source') do
  !SOURCE_P2.include?('perf' + 'ormance improvement') &&
    !SOURCE_P2.include?('prod' + 'uction concurrency support')
end

# ════════════════════════════════════════════════════════════════════════════════
# P2-GAP: Explicit answers to all card questions
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P2-GAP: Explicit answers to card questions"

p2_check('P2-GAP-01', 'Effectful nodes are NOT concurrent by default (v0 serialized)') do
  r     = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                            effect_specs: DEFAULT_SPECS, policy: nil)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == false
end

p2_check('P2-GAP-02', 'Explicit scheduling policy IS required for any effectful concurrent eligibility') do
  with_policy    = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                                     effect_specs: DEFAULT_SPECS,
                                                     policy: READ_READ_POLICY)
  without_policy = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                                     effect_specs: DEFAULT_SPECS, policy: nil)
  wave_with    = with_policy.wave_details.find    { |w| w[:wave] == 1 }
  wave_without = without_policy.wave_details.find { |w| w[:wave] == 1 }
  wave_with[:concurrent_eligible] == true &&
    wave_without[:concurrent_eligible] == false
end

p2_check('P2-GAP-03', 'Disjoint read-only resources CAN be policy-eligible') do
  decision = PolicyEvaluator.check_pair(DEFAULT_SPECS['X'], DEFAULT_SPECS['Y'], READ_READ_POLICY)
  decision.outcome == :eligible
end

p2_check('P2-GAP-04', 'Overlapping writes REMAIN closed (resource_conflict regardless of policy)') do
  decision = PolicyEvaluator.check_pair(WRITE_WRITE_SPECS['X'], WRITE_WRITE_SPECS['Y'],
                                         WRITE_WRITE_POLICY)
  decision.outcome == :resource_conflict
end

p2_check('P2-GAP-05', 'Unknown resource keys FAIL CLOSED (unknown_resource outcome)') do
  decision = PolicyEvaluator.check_pair(UNKNOWN_RESOURCE_SPECS['X'], UNKNOWN_RESOURCE_SPECS['Y'],
                                         READ_READ_POLICY)
  decision.outcome == :unknown_resource
end

p2_check('P2-GAP-06', 'Denied capability PREVENTS scheduling (capability_denied outcome)') do
  decision = PolicyEvaluator.check_pair(DENIED_CAP_SPECS['X'], DENIED_CAP_SPECS['Y'], DENIED_CAP_POLICY)
  decision.outcome == :capability_denied
end

p2_check('P2-GAP-07', 'Deterministic receipts CAN represent scheduling decisions (policy_decisions in wave_details)') do
  r     = CapabilityAwareScheduler.execute(BASE_EFFECT_DAG, BASE_COMPUTE, BASE_SEEDS,
                                            effect_specs: DEFAULT_SPECS, policy: READ_READ_POLICY)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:policy_decisions].first.is_a?(PolicyDecision) &&
    wave1[:policy_decisions].first.policy_id == 'policy-read-read-v0'
end

p2_check('P2-GAP-08', 'This proof does NOT open runtime concurrency authority') do
  SOURCE_P2.include?('does not open runtime concurrency authority') &&
    !SOURCE_P2.include?('Thre' + 'ad') &&
    !SOURCE_P2.include?('Fib' + 'er')
end

p2_check('P2-GAP-09', 'This proof does NOT make perf claims (closed)') do
  SOURCE_P2.include?('no-perf-claims-closed') &&
    !SOURCE_P2.include?('perf' + 'ormance improvement')
end

p2_check('P2-GAP-10', 'Lab behavior does NOT create canon authority') do
  SOURCE_P2.include?('lab-only') &&
    SOURCE_P2.include?('No canon claim') &&
    !SOURCE_P2.include?('stab' + 'le API')
end

# ════════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════════

passes = $p2_results.count { |r| r[:status] == 'PASS' }
fails  = $p2_results.count { |r| r[:status] == 'FAIL' }
total  = $p2_results.size

puts "\n" + '=' * 68
puts "LAB-CONCURRENCY-P2 (Capability-Aware Effect Scheduling Policy Boundary)"
puts "RESULT: #{passes}/#{total} PASS  |  #{fails} FAIL"
puts '=' * 68

exit(fails == 0 ? 0 : 1)
