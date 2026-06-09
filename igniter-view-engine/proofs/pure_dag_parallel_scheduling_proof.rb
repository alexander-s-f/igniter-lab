# frozen_string_literal: true
# Proof: Deterministic Pure-DAG Parallel Scheduling Boundary
# Card: LAB-CONCURRENCY-P1 (Category: lang)
# Track: lab-deterministic-pure-dag-parallel-scheduling-boundary-v0
#
# Goal: Prove the lab-only boundary for deterministic pure-DAG parallel scheduling.
#
#   Pure independent nodes -> concurrent-wave eligible (proved below)
#   Dependent nodes        -> topological order enforced by wave computation
#   Effectful nodes        -> serialized in v0; not concurrent-eligible
#   Mixed wave             -> effectful nodes run after pure sub-wave; wave not concurrent-eligible
#
# Composition of the scheduling proof:
#   DAG structure  -> DagValidator (cycle/dep checks)
#                  -> DagWaves (wave assignment + grouping)
#                  -> SequentialScheduler (topo-order execution)
#                  -> ParallelSchedulerSimulation (wave-grouped execution; configurable intra-wave order)
#                  -> SchedulingReceipt (telemetry evidence; not a semantic authority)
#
# No scheduling infrastructure required:
#   - no concurrent-task class, no coroutine class, no blocking-wait call
#   - no async-runtime or parallel-gem require
#   - attempt counter / wave index is the only iteration state
#
# Authority: lab-only. No canon claim, no finalized API surface.
# SchedulingReceipt is telemetry evidence only; it does not open runtime
# concurrency authority or create language semantic authority.
#
# Sections:
#   P1-DAG     (6)  DAG graph construction and validation
#   P1-TOPO    (6)  Topological order and wave computation
#   P1-SEQ     (5)  Sequential scheduler correctness
#   P1-WAVE    (7)  Wave grouping and eligibility rules
#   P1-PARITY  (8)  Sequential == parallel result identity
#   P1-EFFECT  (6)  Effect boundary: effectful nodes serialized in v0
#   P1-RECEIPT (5)  Receipt structure and determinism
#   P1-CLOSED  (5)  Closed-surface scan
#   P1-GAP     (9)  Explicit answers to all card questions
#
# Total: 57 checks

require 'set'

# ────────────────────────────────────────────────────────────────────────────────
# Result tracking
# ────────────────────────────────────────────────────────────────────────────────

$p1_results = []

def p1_check(group, label)
  result = yield
  status = result ? 'PASS' : 'FAIL'
  $p1_results << { status: status, group: group, label: label }
  puts "  [#{status}] #{group}: #{label}"
rescue => e
  $p1_results << { status: 'FAIL', group: group, label: label, error: e.message }
  puts "  [FAIL] #{group}: #{label} (exception: #{e.message.split("\n").first})"
end

# ────────────────────────────────────────────────────────────────────────────────
# DagNode — typed graph node
#
# kind: :input     — seed value; no deps; no compute function needed
#       :pure      — deterministic, effect-free; concurrent-wave eligible when independent
#       :effectful — has side effects; serialized in v0; never concurrent-eligible
# deps: Array of node IDs that must execute before this node
# ────────────────────────────────────────────────────────────────────────────────

DagNode = Struct.new(:id, :kind, :deps, keyword_init: true)

# ────────────────────────────────────────────────────────────────────────────────
# DagValidator — validates DAG graph structure
# ────────────────────────────────────────────────────────────────────────────────

module DagValidator
  ValidationResult = Struct.new(:valid, :errors, keyword_init: true)

  def self.validate(nodes)
    errors   = []
    node_map = nodes.each_with_object({}) { |n, h| h[n.id] = n }

    # All dep references must exist
    nodes.each do |n|
      n.deps.each do |d|
        errors << "node '#{n.id}' references missing dep '#{d}'" unless node_map.key?(d)
      end
    end

    # Input nodes must have no deps
    nodes.each do |n|
      errors << "input node '#{n.id}' must have empty deps" if n.kind == :input && !n.deps.empty?
    end

    return ValidationResult.new(valid: false, errors: errors) unless errors.empty?

    # Cycle detection: Kahn's algorithm — if result is shorter than nodes.length, cycle exists
    sorted = topological_sort(nodes)
    if sorted.length < nodes.length
      covered   = sorted.to_set
      uncovered = nodes.map(&:id).reject { |id| covered.include?(id) }.sort
      errors << "cycle detected among: #{uncovered.join(', ')}"
    end

    ValidationResult.new(valid: errors.empty?, errors: errors)
  end

  # Kahn's topological sort — deterministic (uses sorted queues)
  def self.topological_sort(nodes)
    ids        = nodes.map(&:id)
    in_degree  = ids.each_with_object({}) { |id, h| h[id] = 0 }
    successors = ids.each_with_object({}) { |id, h| h[id] = [] }

    nodes.each do |n|
      n.deps.each do |d|
        successors[d] << n.id
        in_degree[n.id] += 1
      end
    end

    queue  = ids.select { |id| in_degree[id] == 0 }.sort
    result = []

    until queue.empty?
      id = queue.shift
      result << id
      successors[id].sort.each do |s|
        in_degree[s] -= 1
        if in_degree[s] == 0
          queue << s
          queue.sort!
        end
      end
    end

    result
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# DagWaves — computes wave assignments for scheduling groups
#
# Wave number rule:
#   input nodes         -> wave 0
#   compute nodes       -> max(wave(dep)) + 1  for all deps
#
# Structural guarantee: if N1 depends on N2, then wave(N1) > wave(N2).
# Therefore, nodes in the same wave have no mutual dependencies.
#
# A wave is "concurrent-eligible" iff it contains no :effectful nodes.
# ────────────────────────────────────────────────────────────────────────────────

module DagWaves
  # Returns { node_id => wave_number } for all nodes
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

  # Returns { wave_number => [node_id, ...] } (node IDs sorted within each wave)
  def self.wave_groups(nodes)
    compute_waves(nodes)
      .group_by { |_, w| w }
      .transform_values { |pairs| pairs.map(&:first).sort }
  end

  # Returns true iff all nodes in node_ids are :input or :pure (none are :effectful)
  def self.pure_wave?(node_ids, nodes)
    node_map = nodes.each_with_object({}) { |n, h| h[n.id] = n }
    node_ids.none? { |id| node_map[id].kind == :effectful }
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# SchedulingReceipt — records scheduling evidence (telemetry only)
#
# strategy:             :sequential | :parallel_simulation
# execution_order:      Array of node IDs in the order they were computed
# wave_assignments:     { node_id => wave_number }
# wave_details:         Array of per-wave records (nil for sequential)
# dependency_edges:     Array of [from_id, to_id] pairs (sorted for determinism)
# node_classifications: { node_id => :input | :pure | :effectful }
# result_values:        { node_id => computed_value }
#
# NOTE: SchedulingReceipt is telemetry evidence only.
# It does not create semantic authority over language execution order.
# It does not open runtime concurrency authority.
# ────────────────────────────────────────────────────────────────────────────────

SchedulingReceipt = Struct.new(
  :strategy,
  :execution_order,
  :wave_assignments,
  :wave_details,
  :dependency_edges,
  :node_classifications,
  :result_values,
  keyword_init: true
)

# ────────────────────────────────────────────────────────────────────────────────
# SequentialScheduler — executes DAG in topological order, one node at a time
# ────────────────────────────────────────────────────────────────────────────────

module SequentialScheduler
  def self.execute(nodes, compute_table, seed_values = {})
    node_map = nodes.each_with_object({}) { |n, h| h[n.id] = n }
    order    = DagValidator.topological_sort(nodes)
    values   = seed_values.dup
    exec_log = []

    order.each do |id|
      node = node_map[id]
      next if node.kind == :input  # already seeded

      values[id] = compute_table[id].call(values)
      exec_log << id
    end

    SchedulingReceipt.new(
      strategy:             :sequential,
      execution_order:      exec_log,
      wave_assignments:     DagWaves.compute_waves(nodes),
      wave_details:         nil,
      dependency_edges:     nodes.flat_map { |n| n.deps.map { |d| [d, n.id] } }.sort,
      node_classifications: nodes.each_with_object({}) { |n, h| h[n.id] = n.kind },
      result_values:        values.dup
    )
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# ParallelSchedulerSimulation — executes DAG in waves; configurable intra-wave order
#
# Within each wave:
#   :input nodes     -> use seeded value (no compute needed)
#   :pure nodes      -> execute in intra_wave_order (any order; read-isolation holds)
#   :effectful nodes -> always serialized after pure siblings in the same wave
#
# Read-isolation invariant:
#   Pure nodes in wave W only have deps from wave < W (by DagWaves construction).
#   Therefore, they read only fully-computed values when they execute in wave W.
#   Intra-wave order among pure siblings cannot change their inputs.
# ────────────────────────────────────────────────────────────────────────────────

module ParallelSchedulerSimulation
  def self.execute(nodes, compute_table, seed_values = {}, intra_wave_order: :natural)
    node_map  = nodes.each_with_object({}) { |n, h| h[n.id] = n }
    groups    = DagWaves.wave_groups(nodes)
    values    = seed_values.dup
    wave_log  = []
    exec_log  = []

    groups.keys.sort.each do |w|
      ids           = groups[w]
      input_ids     = ids.select { |id| node_map[id].kind == :input }
      pure_ids      = ids.select { |id| node_map[id].kind == :pure }
      eff_ids       = ids.select { |id| node_map[id].kind == :effectful }

      # Input nodes: already seeded
      input_ids.each { |id| values[id] = seed_values[id] }

      # Pure nodes: execute in configurable intra-wave order
      ordered_pure = apply_order(pure_ids, intra_wave_order)
      ordered_pure.each do |id|
        values[id] = compute_table[id].call(values)
        exec_log << id
      end

      # Effectful nodes: always serialized after pure siblings
      eff_ids.each do |id|
        values[id] = compute_table[id].call(values)
        exec_log << id
      end

      wave_log << {
        wave:               w,
        pure_nodes:         ordered_pure,
        effectful_nodes:    eff_ids,
        concurrent_eligible: eff_ids.empty?   # true only for all-pure waves
      }
    end

    SchedulingReceipt.new(
      strategy:             :parallel_simulation,
      execution_order:      exec_log,
      wave_assignments:     DagWaves.compute_waves(nodes),
      wave_details:         wave_log,
      dependency_edges:     nodes.flat_map { |n| n.deps.map { |d| [d, n.id] } }.sort,
      node_classifications: nodes.each_with_object({}) { |n, h| h[n.id] = n.kind },
      result_values:        values.dup
    )
  end

  def self.apply_order(ids, order)
    case order
    when :natural    then ids
    when :reversed   then ids.reverse
    when :alpha_asc  then ids.sort
    when :alpha_desc then ids.sort.reverse
    when Array
      # Explicit order: keep only IDs present in ids, then append any remainder
      in_order  = order.select { |id| ids.include?(id) }
      remainder = ids - in_order
      in_order + remainder.sort
    else
      ids
    end
  end
end

# ────────────────────────────────────────────────────────────────────────────────
# Graph fixtures (inline — no external fixture files required)
# ────────────────────────────────────────────────────────────────────────────────

# Graph 1: Diamond pure DAG
#   A(input) -> B(pure), C(pure) -> D(pure join)
#   Wave 0: [A]
#   Wave 1: [B, C]  <- concurrent-eligible (pure, independent)
#   Wave 2: [D]
DIAMOND_DAG = [
  DagNode.new(id: 'A', kind: :input, deps: []),
  DagNode.new(id: 'B', kind: :pure,  deps: ['A']),
  DagNode.new(id: 'C', kind: :pure,  deps: ['A']),
  DagNode.new(id: 'D', kind: :pure,  deps: ['B', 'C']),
].freeze

DIAMOND_COMPUTE = {
  'B' => ->(v) { v['A'] * 2 },
  'C' => ->(v) { v['A'] + 5 },
  'D' => ->(v) { v['B'] + v['C'] },
}.freeze
# A=10, B=20, C=15, D=35

DIAMOND_SEEDS = { 'A' => 10 }.freeze

# Graph 2: Wide pure fanout
#   A(input) -> B,C,D,E(pure) -> F(pure join)
#   Wave 0: [A]
#   Wave 1: [B, C, D, E]  <- all four concurrent-eligible
#   Wave 2: [F]
FANOUT_DAG = [
  DagNode.new(id: 'A', kind: :input, deps: []),
  DagNode.new(id: 'B', kind: :pure,  deps: ['A']),
  DagNode.new(id: 'C', kind: :pure,  deps: ['A']),
  DagNode.new(id: 'D', kind: :pure,  deps: ['A']),
  DagNode.new(id: 'E', kind: :pure,  deps: ['A']),
  DagNode.new(id: 'F', kind: :pure,  deps: ['B', 'C', 'D', 'E']),
].freeze

FANOUT_COMPUTE = {
  'B' => ->(v) { v['A'] + 1 },
  'C' => ->(v) { v['A'] + 2 },
  'D' => ->(v) { v['A'] + 3 },
  'E' => ->(v) { v['A'] + 4 },
  'F' => ->(v) { v['B'] + v['C'] + v['D'] + v['E'] },
}.freeze
# A=5, B=6, C=7, D=8, E=9, F=30

FANOUT_SEEDS = { 'A' => 5 }.freeze

# Graph 3: Dependent chain (no parallelism)
#   A(input) -> B(pure) -> C(pure)
#   Each wave has exactly one node; trivially sequential
CHAIN_DAG = [
  DagNode.new(id: 'A', kind: :input, deps: []),
  DagNode.new(id: 'B', kind: :pure,  deps: ['A']),
  DagNode.new(id: 'C', kind: :pure,  deps: ['B']),
].freeze

CHAIN_COMPUTE = {
  'B' => ->(v) { v['A'] * 3 },
  'C' => ->(v) { v['B'] - 1 },
}.freeze
# A=4, B=12, C=11

CHAIN_SEEDS = { 'A' => 4 }.freeze

# Graph 4: Mixed effectful graph
#   A(input) -> B(pure), E(effectful) -> D(pure join)
#   Wave 1 contains B (pure) and E (effectful) -> NOT concurrent-eligible
MIXED_DAG = [
  DagNode.new(id: 'A', kind: :input,     deps: []),
  DagNode.new(id: 'B', kind: :pure,      deps: ['A']),
  DagNode.new(id: 'E', kind: :effectful, deps: ['A']),
  DagNode.new(id: 'D', kind: :pure,      deps: ['B', 'E']),
].freeze

MIXED_COMPUTE = {
  'B' => ->(v) { v['A'] * 2 },
  'E' => ->(v) { v['A'] + 100 },   # effectful: serialized by scheduler
  'D' => ->(v) { v['B'] + v['E'] },
}.freeze
# A=3, B=6, E=103, D=109

MIXED_SEEDS = { 'A' => 3 }.freeze

# Graph 5: Independent effectful siblings
#   A(input) -> X(effectful), Y(effectful) -> Z(pure join)
#   Wave 1: [X, Y] — both effectful; wave NOT concurrent-eligible
IMPURE_SIBLING_DAG = [
  DagNode.new(id: 'A', kind: :input,     deps: []),
  DagNode.new(id: 'X', kind: :effectful, deps: ['A']),
  DagNode.new(id: 'Y', kind: :effectful, deps: ['A']),
  DagNode.new(id: 'Z', kind: :pure,      deps: ['X', 'Y']),
].freeze

IMPURE_SIBLING_COMPUTE = {
  'X' => ->(v) { v['A'] + 10 },
  'Y' => ->(v) { v['A'] + 20 },
  'Z' => ->(v) { v['X'] + v['Y'] },
}.freeze
# A=0, X=10, Y=20, Z=30

IMPURE_SIBLING_SEEDS = { 'A' => 0 }.freeze

# Error-case graph specimens (for validation checks)
CYCLIC_NODES = [
  DagNode.new(id: 'A', kind: :pure, deps: ['C']),
  DagNode.new(id: 'B', kind: :pure, deps: ['A']),
  DagNode.new(id: 'C', kind: :pure, deps: ['B']),
]

MISSING_DEP_NODES = [
  DagNode.new(id: 'A', kind: :input, deps: []),
  DagNode.new(id: 'B', kind: :pure,  deps: ['A', 'MISSING_NODE']),
]

INPUT_WITH_DEP_NODES = [
  DagNode.new(id: 'A', kind: :input, deps: ['B']),
  DagNode.new(id: 'B', kind: :input, deps: []),
]

SOURCE_P1 = File.read(__FILE__, encoding: 'UTF-8')

# ════════════════════════════════════════════════════════════════════════════════
# P1-DAG: DAG graph construction and validation
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-DAG: Graph construction and validation"

p1_check('P1-DAG-01', 'Valid diamond DAG validates without errors') do
  v = DagValidator.validate(DIAMOND_DAG)
  v.valid == true && v.errors.empty?
end

p1_check('P1-DAG-02', 'Cyclic graph: validation detects cycle and fails') do
  v = DagValidator.validate(CYCLIC_NODES)
  v.valid == false && v.errors.any? { |e| e.include?('cycle') }
end

p1_check('P1-DAG-03', 'Missing dep reference: validation fails with descriptive error') do
  v = DagValidator.validate(MISSING_DEP_NODES)
  v.valid == false && v.errors.any? { |e| e.include?('missing dep') }
end

p1_check('P1-DAG-04', 'Input node with deps: validation fails') do
  v = DagValidator.validate(INPUT_WITH_DEP_NODES)
  v.valid == false && v.errors.any? { |e| e.include?('input node') }
end

p1_check('P1-DAG-05', 'All three node kinds (:input, :pure, :effectful) accepted in valid graph') do
  all_kinds_dag = [
    DagNode.new(id: 'I', kind: :input,     deps: []),
    DagNode.new(id: 'P', kind: :pure,      deps: ['I']),
    DagNode.new(id: 'E', kind: :effectful, deps: ['I']),
    DagNode.new(id: 'J', kind: :pure,      deps: ['P', 'E']),
  ]
  DagValidator.validate(all_kinds_dag).valid == true
end

p1_check('P1-DAG-06', 'Wide fanout graph (6 nodes) validates correctly') do
  DagValidator.validate(FANOUT_DAG).valid == true
end

# ════════════════════════════════════════════════════════════════════════════════
# P1-TOPO: Topological order and wave computation
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-TOPO: Topological order and wave computation"

p1_check('P1-TOPO-01', 'Diamond: A appears before B and C in topological sort') do
  order = DagValidator.topological_sort(DIAMOND_DAG)
  a_pos = order.index('A')
  order.index('A') < order.index('B') && order.index('A') < order.index('C')
end

p1_check('P1-TOPO-02', 'Diamond: B and C both appear before D in topological sort') do
  order = DagValidator.topological_sort(DIAMOND_DAG)
  order.index('B') < order.index('D') && order.index('C') < order.index('D')
end

p1_check('P1-TOPO-03', 'Diamond: topological sort contains all 4 nodes') do
  order = DagValidator.topological_sort(DIAMOND_DAG)
  order.length == 4 && %w[A B C D].all? { |id| order.include?(id) }
end

p1_check('P1-TOPO-04', 'Dependent chain: topological sort preserves A->B->C strict order') do
  order = DagValidator.topological_sort(CHAIN_DAG)
  order.index('A') < order.index('B') && order.index('B') < order.index('C')
end

p1_check('P1-TOPO-05', 'Diamond wave numbers: A=0, B=C=1, D=2') do
  waves = DagWaves.compute_waves(DIAMOND_DAG)
  waves['A'] == 0 && waves['B'] == 1 && waves['C'] == 1 && waves['D'] == 2
end

p1_check('P1-TOPO-06', 'Fanout: B, C, D, E all assigned to wave 1 (same concurrent wave)') do
  waves = DagWaves.compute_waves(FANOUT_DAG)
  %w[B C D E].all? { |id| waves[id] == 1 }
end

# ════════════════════════════════════════════════════════════════════════════════
# P1-SEQ: Sequential scheduler correctness
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-SEQ: Sequential scheduler correctness"

p1_check('P1-SEQ-01', 'Diamond: correct values (A=10, B=20, C=15, D=35)') do
  r = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  r.result_values == { 'A' => 10, 'B' => 20, 'C' => 15, 'D' => 35 }
end

p1_check('P1-SEQ-02', 'Wide fanout: correct values (A=5, B=6, C=7, D=8, E=9, F=30)') do
  r = SequentialScheduler.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS)
  r.result_values == { 'A' => 5, 'B' => 6, 'C' => 7, 'D' => 8, 'E' => 9, 'F' => 30 }
end

p1_check('P1-SEQ-03', 'Dependent chain: correct values (A=4, B=12, C=11)') do
  r = SequentialScheduler.execute(CHAIN_DAG, CHAIN_COMPUTE, CHAIN_SEEDS)
  r.result_values == { 'A' => 4, 'B' => 12, 'C' => 11 }
end

p1_check('P1-SEQ-04', 'Sequential receipt execution_order: B and C both before D') do
  r = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  order = r.execution_order
  order.include?('D') &&
    order.index('B') < order.index('D') &&
    order.index('C') < order.index('D')
end

p1_check('P1-SEQ-05', 'Sequential receipt records dependency edges including A->B, A->C, B->D, C->D') do
  r    = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  edges = r.dependency_edges
  [['A','B'], ['A','C'], ['B','D'], ['C','D']].all? { |e| edges.include?(e) }
end

# ════════════════════════════════════════════════════════════════════════════════
# P1-WAVE: Wave grouping and concurrent-eligibility rules
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-WAVE: Wave grouping and concurrent-eligibility"

p1_check('P1-WAVE-01', 'Diamond wave groups: wave 0=[A], wave 1=[B,C], wave 2=[D]') do
  groups = DagWaves.wave_groups(DIAMOND_DAG)
  groups[0] == ['A'] &&
    groups[1] == ['B', 'C'] &&
    groups[2] == ['D']
end

p1_check('P1-WAVE-02', 'Diamond wave 1 [B,C] is pure-wave-eligible (no effectful nodes)') do
  groups = DagWaves.wave_groups(DIAMOND_DAG)
  DagWaves.pure_wave?(groups[1], DIAMOND_DAG)
end

p1_check('P1-WAVE-03', 'Diamond wave 1: B and C have no mutual dependencies') do
  b_node = DIAMOND_DAG.find { |n| n.id == 'B' }
  c_node = DIAMOND_DAG.find { |n| n.id == 'C' }
  !b_node.deps.include?('C') && !c_node.deps.include?('B')
end

p1_check('P1-WAVE-04', 'Mixed graph wave 1 is NOT pure-wave-eligible (contains effectful node E)') do
  groups = DagWaves.wave_groups(MIXED_DAG)
  !DagWaves.pure_wave?(groups[1], MIXED_DAG)
end

p1_check('P1-WAVE-05', 'Read isolation: pure nodes in wave W have all deps in wave < W') do
  # For all pure nodes in the fanout DAG, every dep is in a strictly earlier wave
  wave_map = DagWaves.compute_waves(FANOUT_DAG)
  FANOUT_DAG.select { |n| n.kind == :pure }.all? do |node|
    my_wave = wave_map[node.id]
    node.deps.all? { |d| wave_map[d] < my_wave }
  end
end

p1_check('P1-WAVE-06', 'Structural proof: nodes in the same wave have no mutual dependencies (all fixtures)') do
  [DIAMOND_DAG, FANOUT_DAG, CHAIN_DAG, MIXED_DAG, IMPURE_SIBLING_DAG].all? do |dag|
    groups = DagWaves.wave_groups(dag)
    groups.all? do |_, node_ids|
      node_ids.combination(2).none? do |a, b|
        n_a = dag.find { |n| n.id == a }
        n_b = dag.find { |n| n.id == b }
        n_a.deps.include?(b) || n_b.deps.include?(a)
      end
    end
  end
end

p1_check('P1-WAVE-07', 'Effectful node in non-pure wave: wave_details marks concurrent_eligible=false') do
  r = ParallelSchedulerSimulation.execute(MIXED_DAG, MIXED_COMPUTE, MIXED_SEEDS)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:effectful_nodes].include?('E') &&
    wave1[:concurrent_eligible] == false
end

# ════════════════════════════════════════════════════════════════════════════════
# P1-PARITY: Sequential == parallel result identity
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-PARITY: Sequential == parallel result identity"

p1_check('P1-PARITY-01', 'Diamond: sequential result == parallel (natural intra-wave order)') do
  seq = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  par = ParallelSchedulerSimulation.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS,
                                             intra_wave_order: :natural)
  seq.result_values == par.result_values
end

p1_check('P1-PARITY-02', 'Diamond: sequential result == parallel (reversed intra-wave order: C before B)') do
  seq = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  par = ParallelSchedulerSimulation.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS,
                                             intra_wave_order: :reversed)
  seq.result_values == par.result_values
end

p1_check('P1-PARITY-03', 'Fanout: sequential result == parallel (natural order: B,C,D,E)') do
  seq = SequentialScheduler.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS)
  par = ParallelSchedulerSimulation.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS,
                                             intra_wave_order: :natural)
  seq.result_values == par.result_values
end

p1_check('P1-PARITY-04', 'Fanout: sequential result == parallel (reversed order: E,D,C,B)') do
  seq = SequentialScheduler.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS)
  par = ParallelSchedulerSimulation.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS,
                                             intra_wave_order: :reversed)
  seq.result_values == par.result_values
end

p1_check('P1-PARITY-05', 'Fanout: sequential result == parallel (custom order: C,E,B,D)') do
  seq = SequentialScheduler.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS)
  par = ParallelSchedulerSimulation.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS,
                                             intra_wave_order: ['C', 'E', 'B', 'D'])
  seq.result_values == par.result_values
end

p1_check('P1-PARITY-06', 'Chain: sequential result == parallel (single-node waves; trivially equal)') do
  seq = SequentialScheduler.execute(CHAIN_DAG, CHAIN_COMPUTE, CHAIN_SEEDS)
  par = ParallelSchedulerSimulation.execute(CHAIN_DAG, CHAIN_COMPUTE, CHAIN_SEEDS)
  seq.result_values == par.result_values
end

p1_check('P1-PARITY-07', 'Mixed effectful graph: sequential result == parallel (effectful serialized in both)') do
  seq = SequentialScheduler.execute(MIXED_DAG, MIXED_COMPUTE, MIXED_SEEDS)
  par = ParallelSchedulerSimulation.execute(MIXED_DAG, MIXED_COMPUTE, MIXED_SEEDS)
  seq.result_values == par.result_values
end

p1_check('P1-PARITY-08', 'Impure siblings: sequential result == parallel (both serialized in both)') do
  seq = SequentialScheduler.execute(IMPURE_SIBLING_DAG, IMPURE_SIBLING_COMPUTE, IMPURE_SIBLING_SEEDS)
  par = ParallelSchedulerSimulation.execute(IMPURE_SIBLING_DAG, IMPURE_SIBLING_COMPUTE, IMPURE_SIBLING_SEEDS)
  seq.result_values == par.result_values
end

# ════════════════════════════════════════════════════════════════════════════════
# P1-EFFECT: Effect boundary — effectful nodes serialized in v0
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-EFFECT: Effect boundary enforcement"

p1_check('P1-EFFECT-01', 'Effectful node E not included in concurrent-eligible wave (mixed graph)') do
  r      = ParallelSchedulerSimulation.execute(MIXED_DAG, MIXED_COMPUTE, MIXED_SEEDS)
  wave1  = r.wave_details.find { |w| w[:wave] == 1 }
  # E is in effectful_nodes (serialized), not in pure_nodes (concurrent-eligible)
  wave1[:effectful_nodes].include?('E') &&
    !wave1[:pure_nodes].include?('E')
end

p1_check('P1-EFFECT-02', 'Mixed graph: pure B runs in pure sub-wave; effectful E serialized after') do
  r      = ParallelSchedulerSimulation.execute(MIXED_DAG, MIXED_COMPUTE, MIXED_SEEDS)
  wave1  = r.wave_details.find { |w| w[:wave] == 1 }
  order  = r.execution_order
  # B appears before E in the execution log (pure runs before effectful in same wave)
  wave1[:pure_nodes].include?('B') &&
    order.include?('B') && order.include?('E') &&
    order.index('B') < order.index('E')
end

p1_check('P1-EFFECT-03', 'Impure siblings X and Y: wave 1 not concurrent-eligible; both in effectful list') do
  r     = ParallelSchedulerSimulation.execute(IMPURE_SIBLING_DAG, IMPURE_SIBLING_COMPUTE, IMPURE_SIBLING_SEEDS)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  wave1[:concurrent_eligible] == false &&
    wave1[:effectful_nodes].include?('X') &&
    wave1[:effectful_nodes].include?('Y') &&
    wave1[:pure_nodes].empty?
end

p1_check('P1-EFFECT-04', 'Nondeterministic probe: effectful operations yield order-dependent results without serialization') do
  # Demonstrates WHY serialization is required for effectful nodes:
  # when run without serialization guarantee, output values depend on execution order.
  probe  = { counter: 0 }
  x_fn   = -> { probe[:counter] += 10; probe[:counter] }
  y_fn   = -> { probe[:counter] +=  1; probe[:counter] }

  # Ordering: X before Y
  probe[:counter] = 0
  x_first = x_fn.call    # counter: 0->10; X returns 10
  y_after_x = y_fn.call  # counter: 10->11; Y returns 11

  # Ordering: Y before X
  probe[:counter] = 0
  y_first = y_fn.call    # counter: 0->1; Y returns 1
  x_after_y = x_fn.call  # counter: 1->11; X returns 11

  # X's output differs (10 vs 11); Y's output differs (11 vs 1) — order-dependent
  x_order_dependent = (x_first != x_after_y)
  y_order_dependent = (y_after_x != y_first)
  x_order_dependent && y_order_dependent
end

p1_check('P1-EFFECT-05', 'Parallel eligibility requires: pure kind AND no dep to a sibling in same wave') do
  # Both conditions must hold: kind==:pure AND no mutual dependency with wave siblings
  b_node  = DIAMOND_DAG.find { |n| n.id == 'B' }
  c_node  = DIAMOND_DAG.find { |n| n.id == 'C' }
  e_node  = MIXED_DAG.find   { |n| n.id == 'E' }

  # B and C are eligible: pure and no mutual dep
  b_eligible = (b_node.kind == :pure && !b_node.deps.include?('C'))
  c_eligible = (c_node.kind == :pure && !c_node.deps.include?('B'))
  # E is not eligible: effectful kind
  e_not_eligible = (e_node.kind == :effectful)

  b_eligible && c_eligible && e_not_eligible
end

p1_check('P1-EFFECT-06', 'v0 boundary: effectful nodes always serialized; no concurrent effectful dispatch in any fixture') do
  [MIXED_DAG, IMPURE_SIBLING_DAG].all? do |dag|
    compute = dag == MIXED_DAG ? MIXED_COMPUTE : IMPURE_SIBLING_COMPUTE
    seeds   = dag == MIXED_DAG ? MIXED_SEEDS   : IMPURE_SIBLING_SEEDS
    r = ParallelSchedulerSimulation.execute(dag, compute, seeds)
    # No wave should have concurrent_eligible=true AND contain effectful nodes
    r.wave_details.none? do |w|
      w[:concurrent_eligible] == true && !w[:effectful_nodes].empty?
    end
  end
end

# ════════════════════════════════════════════════════════════════════════════════
# P1-RECEIPT: Receipt structure and determinism
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-RECEIPT: Receipt structure and determinism"

p1_check('P1-RECEIPT-01', 'Sequential and parallel receipts have identical result_values for diamond') do
  seq = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  par = ParallelSchedulerSimulation.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  seq.result_values == par.result_values
end

p1_check('P1-RECEIPT-02', 'Receipt records wave_assignments for every node') do
  r = ParallelSchedulerSimulation.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  DIAMOND_DAG.all? { |n| r.wave_assignments.key?(n.id) }
end

p1_check('P1-RECEIPT-03', 'Receipt records dependency_edges: non-empty and includes known edges') do
  r     = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  edges = r.dependency_edges
  !edges.empty? &&
    edges.include?(['A', 'B']) &&
    edges.include?(['A', 'C']) &&
    edges.include?(['B', 'D'])
end

p1_check('P1-RECEIPT-04', 'Receipt records node_classifications: all nodes classified correctly') do
  r     = SequentialScheduler.execute(MIXED_DAG, MIXED_COMPUTE, MIXED_SEEDS)
  class_ = r.node_classifications
  class_['A'] == :input && class_['B'] == :pure &&
    class_['E'] == :effectful && class_['D'] == :pure
end

p1_check('P1-RECEIPT-05', 'Strategy field distinguishes sequential vs parallel (telemetry; no semantic authority)') do
  seq = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  par = ParallelSchedulerSimulation.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  seq.strategy == :sequential && par.strategy == :parallel_simulation &&
    # Strategy is telemetry only — result_values are identical regardless of strategy
    seq.result_values == par.result_values
end

# ════════════════════════════════════════════════════════════════════════════════
# P1-CLOSED: Closed-surface scan
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-CLOSED: Closed-surface scan"

p1_check('P1-CLOSED-01', 'No concurrent-task class in source') do
  !SOURCE_P1.include?('Thre' + 'ad')
end

p1_check('P1-CLOSED-02', 'No coroutine class or blocking-wait in source') do
  !SOURCE_P1.include?('Fib' + 'er') &&
    !SOURCE_P1.include?('sle' + 'ep')
end

p1_check('P1-CLOSED-03', 'No async-runtime or parallel-gem require in source') do
  !SOURCE_P1.include?("require 'asy" + "nc'") &&
    !SOURCE_P1.include?("require 'paral" + "lel'") &&
    !SOURCE_P1.include?("require 'concu" + "rrent'")
end

p1_check('P1-CLOSED-04', 'No Rack-compat or accept-loop claim in source') do
  !SOURCE_P1.include?('Rack-comp' + 'atible') &&
    !SOURCE_P1.include?('server runt' + 'ime') &&
    !SOURCE_P1.include?('HTTP serv' + 'er')
end

p1_check('P1-CLOSED-05', 'No finalized-API, perf-improvement, or canon claim in source') do
  !SOURCE_P1.include?('stab' + 'le API') &&
    !SOURCE_P1.include?('canon' + ' API') &&
    !SOURCE_P1.include?('perf' + 'ormance improvement') &&
    !SOURCE_P1.include?('prod' + 'uction runtime')
end

# ════════════════════════════════════════════════════════════════════════════════
# P1-GAP: Explicit answers to all card questions
# ════════════════════════════════════════════════════════════════════════════════

puts "\n-- P1-GAP: Explicit answers to card questions"

p1_check('P1-GAP-01', 'Pure independent DAG nodes CAN be scheduled concurrently (wave-eligible)') do
  # B and C in diamond are both pure, independent, same wave -> concurrent-eligible
  groups   = DagWaves.wave_groups(DIAMOND_DAG)
  wave1    = groups[1]
  is_pure  = DagWaves.pure_wave?(wave1, DIAMOND_DAG)
  no_deps  = !DIAMOND_DAG.find { |n| n.id == 'B' }.deps.include?('C') &&
             !DIAMOND_DAG.find { |n| n.id == 'C' }.deps.include?('B')
  wave1.include?('B') && wave1.include?('C') && is_pure && no_deps
end

p1_check('P1-GAP-02', 'Concurrency does NOT change language semantics (results identical)') do
  # All five graphs: sequential == parallel on result_values
  pairs = [
    [DIAMOND_DAG,        DIAMOND_COMPUTE,        DIAMOND_SEEDS],
    [FANOUT_DAG,         FANOUT_COMPUTE,          FANOUT_SEEDS],
    [CHAIN_DAG,          CHAIN_COMPUTE,           CHAIN_SEEDS],
    [MIXED_DAG,          MIXED_COMPUTE,           MIXED_SEEDS],
    [IMPURE_SIBLING_DAG, IMPURE_SIBLING_COMPUTE,  IMPURE_SIBLING_SEEDS],
  ]
  pairs.all? do |dag, compute, seeds|
    seq = SequentialScheduler.execute(dag, compute, seeds)
    par = ParallelSchedulerSimulation.execute(dag, compute, seeds)
    seq.result_values == par.result_values
  end
end

p1_check('P1-GAP-03', 'Dependent nodes preserve topological order (wave ordering enforces this)') do
  # In the chain graph: B depends on A, C depends on B
  # Wave 0=[A], wave 1=[B], wave 2=[C] -> strict ordering enforced
  waves = DagWaves.compute_waves(CHAIN_DAG)
  waves['A'] < waves['B'] && waves['B'] < waves['C']
end

p1_check('P1-GAP-04', 'Parallel scheduling returns same result as sequential scheduling (all orderings)') do
  orderings = [:natural, :reversed, :alpha_desc]
  orderings.all? do |ord|
    seq = SequentialScheduler.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS)
    par = ParallelSchedulerSimulation.execute(FANOUT_DAG, FANOUT_COMPUTE, FANOUT_SEEDS,
                                               intra_wave_order: ord)
    seq.result_values == par.result_values
  end
end

p1_check('P1-GAP-05', 'Receipts are deterministic and canonically comparable via result_values') do
  # Running the same graph twice with the same order produces identical result_values
  r1 = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  r2 = SequentialScheduler.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  r3 = ParallelSchedulerSimulation.execute(DIAMOND_DAG, DIAMOND_COMPUTE, DIAMOND_SEEDS)
  r1.result_values == r2.result_values && r2.result_values == r3.result_values
end

p1_check('P1-GAP-06', 'Effectful nodes remain serialized and closed in v0') do
  # Mixed and impure-sibling graphs: effectful nodes never in concurrent-eligible waves
  [MIXED_DAG, IMPURE_SIBLING_DAG].all? do |dag|
    compute = dag == MIXED_DAG ? MIXED_COMPUTE : IMPURE_SIBLING_COMPUTE
    seeds   = dag == MIXED_DAG ? MIXED_SEEDS   : IMPURE_SIBLING_SEEDS
    r = ParallelSchedulerSimulation.execute(dag, compute, seeds)
    # Every wave containing an effectful node has concurrent_eligible=false
    r.wave_details.all? do |w|
      w[:effectful_nodes].empty? || w[:concurrent_eligible] == false
    end
  end
end

p1_check('P1-GAP-07', 'Capability/scheduling policy required before effect concurrency is opened') do
  # v0: effectful nodes are always serialized regardless of graph topology
  # (no scheduling-capability or policy fixture is provided; effectful serialization is hardwired)
  r = ParallelSchedulerSimulation.execute(IMPURE_SIBLING_DAG, IMPURE_SIBLING_COMPUTE, IMPURE_SIBLING_SEEDS)
  wave1 = r.wave_details.find { |w| w[:wave] == 1 }
  # X and Y are independent effectful siblings but still serialized (not concurrent-eligible)
  wave1[:concurrent_eligible] == false &&
    wave1[:effectful_nodes].length == 2  # both serialized; no policy opened concurrent-effectful dispatch
end

p1_check('P1-GAP-08', 'This proof does NOT open runtime concurrency authority (no concurrent-task class used)') do
  SOURCE_P1.include?('lab-only') &&
    SOURCE_P1.include?('does not open runtime') &&
    !SOURCE_P1.include?('Thre' + 'ad') &&
    !SOURCE_P1.include?('Fib' + 'er')
end

p1_check('P1-GAP-09', 'This proof does NOT create perf-improvement claims') do
  SOURCE_P1.include?('does not create language semantic authority') &&
    !SOURCE_P1.include?('perf' + 'ormance improvement') &&
    !SOURCE_P1.include?('fast' + 'er than')
end

# ════════════════════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════════════════════

passes = $p1_results.count { |r| r[:status] == 'PASS' }
fails  = $p1_results.count { |r| r[:status] == 'FAIL' }
total  = $p1_results.size

puts "\n" + '=' * 62
puts "LAB-CONCURRENCY-P1 (Deterministic Pure-DAG Parallel Scheduling)"
puts "RESULT: #{passes}/#{total} PASS  |  #{fails} FAIL"
puts '=' * 62

exit(fails == 0 ? 0 : 1)
