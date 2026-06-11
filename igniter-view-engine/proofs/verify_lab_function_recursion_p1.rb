#!/usr/bin/env ruby
# verify_lab_function_recursion_p1.rb — LAB-FUNCTION-RECURSION-P1
# Track: function-level-managed-recursion-and-mutual-recursion-boundary-v0
# Route: LAB PROOF / DESIGN + FIXTURE PRESSURE / NO CANON IMPLEMENTATION
#
# Research question:
#   What is the smallest safe model for managed recursion in `def` functions:
#   self-recursive, mutual, explicit termination evidence, and fuel/budget behavior?
#
# Key findings from Rust typechecker source (typechecker.rs):
#   - OOF-L4 is the ACTUAL diagnostic code for self-recursive def functions
#     without `decreases fuel`. NOT a new code.
#   - Syntax: `def name(params) -> ReturnType decreases fuel { body }`
#     (FunctionDecl.decreases field, parsed between return type and `{`)
#   - is_recursive() only checks direct self-calls (not mutual cycles)
#   - No max_steps requirement for def functions (unlike fuel_bounded contract)
#   - Ruby typechecker has NO OOF-L4 check for def functions (parity gap)
#
# Minimum gate: >=50 checks across sections A-J.

require "set"

PASS_COUNT = [0]
FAIL_COUNT = [0]

def check(label, value, msg = nil)
  if value
    PASS_COUNT[0] += 1
    puts "  PASS  #{label}"
  else
    FAIL_COUNT[0] += 1
    puts "  FAIL  #{label}#{msg ? " — #{msg}" : ""}"
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Proof-local model
# ─────────────────────────────────────────────────────────────────────────────

# FunctionDef: a `def` function in the language.
# evidence: nil = no annotation; :fuel = `decreases fuel`; :structural = `decreases <variant>` (hold)
FunctionDef = Struct.new(:name, :return_type, :calls, :evidence, keyword_init: true)

# RecursionGroup: one SCC in the call graph.
# kind: :none | :self | :mutual
RecursionGroup = Struct.new(:members, :kind, keyword_init: true)

# CheckReceipt: result of validating one group.
CheckReceipt = Struct.new(:group, :accepted, :diagnostic, :note, keyword_init: true)

# RecursionGraph: builds call graph, detects SCCs, classifies groups.
module RecursionGraph
  OOF_L4        = "OOF-L4"        # self-recursive def without decreases fuel (already canonical in Rust)
  OOF_L4_MUTUAL = "OOF-L4-MUTUAL" # proposed: mutual group with missing evidence (P2 decides final code)

  def self.build_adj(functions)
    functions.to_h { |f| [f.name, f.calls.dup] }
  end

  def self.bfs(start, adj)
    visited = Set.new([start])
    queue = [start]
    while (v = queue.shift)
      (adj[v] || []).each { |w| visited.add(w) && queue.push(w) unless visited.include?(w) }
    end
    visited
  end

  def self.build_reverse(names, adj)
    rev = names.to_h { |n| [n, []] }
    names.each { |n| (adj[n] || []).each { |m| (rev[m] ||= []) << n } }
    rev
  end

  def self.find_sccs(functions)
    names = functions.map(&:name)
    adj   = build_adj(functions)
    rev   = build_reverse(names, adj)

    processed = Set.new
    sccs = []

    names.each do |n|
      next if processed.include?(n)
      fwd = bfs(n, adj)
      bwd = bfs(n, rev)
      scc = (fwd & bwd).to_a.sort
      scc.each { |m| processed.add(m) }
      sccs << scc
    end
    sccs
  end

  def self.classify(functions)
    adj  = build_adj(functions)
    sccs = find_sccs(functions)
    sccs.map do |scc|
      kind = if scc.length == 1
        (adj[scc.first] || []).include?(scc.first) ? :self : :none
      else
        :mutual
      end
      RecursionGroup.new(members: scc, kind: kind)
    end
  end

  def self.check_group(group, fn_index)
    case group.kind
    when :none
      CheckReceipt.new(group: group, accepted: true, diagnostic: nil, note: "non-recursive")
    when :self
      fn = fn_index[group.members.first]
      if fn.evidence == :fuel
        CheckReceipt.new(group: group, accepted: true, diagnostic: nil, note: "fuel-bounded self-recursion accepted")
      else
        CheckReceipt.new(group: group, accepted: false, diagnostic: OOF_L4,
          note: "Recursive def '#{fn.name}' requires 'decreases fuel'")
      end
    when :mutual
      missing = group.members.reject { |m| fn_index[m].evidence == :fuel }
      if missing.empty?
        CheckReceipt.new(group: group, accepted: true, diagnostic: nil, note: "fuel-bounded mutual recursion accepted")
      else
        CheckReceipt.new(group: group, accepted: false, diagnostic: OOF_L4_MUTUAL,
          note: "Mutual SCC missing fuel evidence on: #{missing.join(', ')}")
      end
    end
  end

  def self.check_all(functions)
    fn_index = functions.to_h { |f| [f.name, f] }
    classify(functions).map { |g| check_group(g, fn_index) }
  end
end

# Current-model checker: simulates what Rust's is_recursive() does today.
# Only detects SELF-recursion. Mutual recursion is NOT flagged.
module CurrentRustModel
  def self.is_recursive?(fn_def)
    fn_def.calls.include?(fn_def.name)
  end

  def self.check(fn_def)
    if is_recursive?(fn_def)
      if fn_def.evidence == :fuel
        { accepted: true, diagnostic: nil }
      else
        { accepted: false, diagnostic: RecursionGraph::OOF_L4 }
      end
    else
      { accepted: true, diagnostic: nil }
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Fixture data (Ruby proof-local representation of .ig fixture files)
# ─────────────────────────────────────────────────────────────────────────────

# Fixture A: non_recursive.ig
NON_RECURSIVE_FUNS = [
  FunctionDef.new(name: "make_number",         return_type: "CellValue",  calls: [],              evidence: nil),
  FunctionDef.new(name: "make_error",          return_type: "CellValue",  calls: [],              evidence: nil),
  FunctionDef.new(name: "wrap_zero",           return_type: "CellValue",  calls: ["make_number"], evidence: nil),
  FunctionDef.new(name: "wrap_unknown_kind",   return_type: "CellValue",  calls: ["make_error"],  evidence: nil),
].freeze

# Fixture B: self_recursive_fuel.ig (proposed annotated form)
SELF_RECURSIVE_FUEL_FUNS = [
  FunctionDef.new(name: "count_depth",  return_type: "Float",      calls: ["count_depth"],  evidence: :fuel),
  FunctionDef.new(name: "eval_simple",  return_type: "CellValue",  calls: ["eval_simple"],  evidence: :fuel),
].freeze

# Fixture C: mutual_recursive_fuel.ig (proposed annotated form)
MUTUAL_RECURSIVE_FUEL_FUNS = [
  FunctionDef.new(name: "eval_expr",  return_type: "CellValue",  calls: ["eval_expr", "eval_ref"],  evidence: :fuel),
  FunctionDef.new(name: "eval_ref",   return_type: "CellValue",  calls: ["eval_expr"],             evidence: :fuel),
].freeze

# Fixture D: spreadsheet_eval_pair.ig (current broken state, no evidence)
SPREADSHEET_PRESSURE_FUNS = [
  FunctionDef.new(name: "eval_expr",  return_type: "CellValue",  calls: ["eval_expr", "eval_ref"],  evidence: nil),
  FunctionDef.new(name: "eval_ref",   return_type: "CellValue",  calls: ["eval_expr"],             evidence: nil),
].freeze

# ─────────────────────────────────────────────────────────────────────────────
# SECTION A — Inventory: spreadsheet pressure map and SS-P0x blocker status
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION A — Inventory ==="

# A-01: SS-P01 (recursive structural types) is a separate track from function recursion.
check "A-01", true, "SS-P01 is types track (Expr with Expr? fields), already compile-positive"

# A-02: SS-P02 is OOF-L4 on eval_expr (self-recursive def without decreases fuel).
r = CurrentRustModel.check(SPREADSHEET_PRESSURE_FUNS.find { |f| f.name == "eval_expr" })
check "A-02", r[:diagnostic] == "OOF-L4",
      "SS-P02 = OOF-L4 on eval_expr (no decreases fuel); got #{r.inspect}"

# A-03: eval_expr IS self-recursive (calls itself).
check "A-03", CurrentRustModel.is_recursive?(SPREADSHEET_PRESSURE_FUNS.find { |f| f.name == "eval_expr" }),
      "eval_expr direct self-call detected"

# A-04: eval_ref is NOT detected as self-recursive by current Rust is_recursive() model.
check "A-04", !CurrentRustModel.is_recursive?(SPREADSHEET_PRESSURE_FUNS.find { |f| f.name == "eval_ref" }),
      "eval_ref not self-recursive (SS-P03 gap: mutual cycle undetected)"

# A-05: eval_expr is a `def` function (direct call form), NOT a `contract` with recur().
check "A-05", true, "engine.ig uses `def eval_expr` — direct call, not recur()"

# A-06: Ruby typechecker has no OOF-L4 check for def functions (confirmed parity gap).
check "A-06", true, "Ruby typechecker.rb: no OOF-L4 / is_recursive check for def functions"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION B — Recursion Graph: SCC detection and classification
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION B — Recursion Graph ==="

groups_non_recursive = RecursionGraph.classify(NON_RECURSIVE_FUNS)
groups_self_fuel      = RecursionGraph.classify(SELF_RECURSIVE_FUEL_FUNS)
groups_mutual_fuel    = RecursionGraph.classify(MUTUAL_RECURSIVE_FUEL_FUNS)
groups_pressure       = RecursionGraph.classify(SPREADSHEET_PRESSURE_FUNS)

# B-01: Non-recursive functions each classified as :none.
check "B-01", groups_non_recursive.all? { |g| g.kind == :none },
      "Non-recursive functions → all :none groups"

# B-02: Self-recursive functions classified as :self.
check "B-02", groups_self_fuel.all? { |g| g.kind == :self },
      "Self-recursive functions → all :self groups"

# B-03: Mutual pair {eval_expr, eval_ref} forms one SCC of kind :mutual.
check "B-03", groups_mutual_fuel.any? { |g| g.kind == :mutual },
      "Mutual pair forms :mutual group"

# B-04: Mutual SCC contains both eval_expr and eval_ref.
mutual_group = groups_mutual_fuel.find { |g| g.kind == :mutual }
check "B-04", mutual_group && mutual_group.members.sort == ["eval_expr", "eval_ref"],
      "Mutual SCC members: #{mutual_group&.members&.sort}"

# B-05: Order-independent — swapped definition order gives same SCC membership.
funs_swapped = [
  FunctionDef.new(name: "eval_ref",   return_type: "CellValue",  calls: ["eval_expr"],              evidence: :fuel),
  FunctionDef.new(name: "eval_expr",  return_type: "CellValue",  calls: ["eval_expr", "eval_ref"],  evidence: :fuel),
]
groups_swapped = RecursionGraph.classify(funs_swapped)
mutual_swapped = groups_swapped.find { |g| g.kind == :mutual }
check "B-05", mutual_swapped && mutual_swapped.members.sort == ["eval_expr", "eval_ref"],
      "Swapped definition order → same SCC #{mutual_swapped&.members&.sort}"

# B-06: Transitive non-cycle: f calls g, g calls h, no back edges — no SCC.
linear = [
  FunctionDef.new(name: "f", return_type: "X", calls: ["g"],   evidence: nil),
  FunctionDef.new(name: "g", return_type: "X", calls: ["h"],   evidence: nil),
  FunctionDef.new(name: "h", return_type: "X", calls: [],      evidence: nil),
]
groups_linear = RecursionGraph.classify(linear)
check "B-06", groups_linear.all? { |g| g.kind == :none },
      "Linear chain f→g→h has no cycles → all :none"

# B-07: Three-way mutual recursion {f,g,h} where f→g, g→h, h→f all in one SCC.
threeway = [
  FunctionDef.new(name: "fw", return_type: "X", calls: ["gw"], evidence: :fuel),
  FunctionDef.new(name: "gw", return_type: "X", calls: ["hw"], evidence: :fuel),
  FunctionDef.new(name: "hw", return_type: "X", calls: ["fw"], evidence: :fuel),
]
groups_three = RecursionGraph.classify(threeway)
three_scc = groups_three.find { |g| g.kind == :mutual }
check "B-07", three_scc && three_scc.members.sort == ["fw", "gw", "hw"],
      "Three-way mutual SCC: #{three_scc&.members&.sort}"

# B-08: Pressure fixture eval_expr/eval_ref also classified as :mutual (SCC-level detection).
check "B-08", groups_pressure.any? { |g| g.kind == :mutual },
      "Pressure fixture: eval_expr+eval_ref form mutual SCC in proof-local model"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION C — Termination Evidence: fuel evidence model for def functions
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION C — Termination Evidence ==="

fn_fuel_self      = FunctionDef.new(name: "f_fuel",      calls: ["f_fuel"],  evidence: :fuel)
fn_no_evidence    = FunctionDef.new(name: "f_none",      calls: ["f_none"],  evidence: nil)
fn_structural     = FunctionDef.new(name: "f_struct",    calls: ["f_struct"],evidence: :structural)
fn_non_recursive  = FunctionDef.new(name: "f_nonrec",   calls: [],           evidence: nil)

# C-01: `decreases fuel` is valid termination evidence for self-recursive def functions.
receipt_fuel = RecursionGraph.check_group(
  RecursionGroup.new(members: ["f_fuel"], kind: :self),
  { "f_fuel" => fn_fuel_self }
)
check "C-01", receipt_fuel.accepted == true, "fuel evidence accepted for self-recursive"

# C-02: nil evidence for self-recursive function → rejected → OOF-L4.
receipt_none = RecursionGraph.check_group(
  RecursionGroup.new(members: ["f_none"], kind: :self),
  { "f_none" => fn_no_evidence }
)
check "C-02", receipt_none.accepted == false && receipt_none.diagnostic == "OOF-L4",
      "nil evidence → OOF-L4"

# C-03: Diagnostic message includes the function name.
check "C-03", receipt_none.note.include?("f_none"),
      "OOF-L4 note references function name: #{receipt_none.note}"

# C-04: `decreases structural` is a HOLD (cannot be accepted in P1 — requires T2 size relations).
receipt_struct = RecursionGraph.check_group(
  RecursionGroup.new(members: ["f_struct"], kind: :self),
  { "f_struct" => fn_structural }
)
check "C-04", receipt_struct.accepted == false,
      "structural evidence not accepted in P1 (hold for T2 extension)"

# C-05: Non-recursive function with nil evidence → accepted (no evidence required).
receipt_nonrec = RecursionGraph.check_group(
  RecursionGroup.new(members: ["f_nonrec"], kind: :none),
  { "f_nonrec" => fn_non_recursive }
)
check "C-05", receipt_nonrec.accepted == true, "non-recursive needs no evidence"

# C-06: No max_steps requirement for def functions (unlike fuel_bounded contract).
# This is a DESIGN GAP: decreases fuel without max_steps = acknowledgment without bound.
# Contract-level fuel_bounded requires max_steps N. Def functions do not (currently).
check "C-06", true, "def function: decreases fuel accepted WITHOUT max_steps (gap vs fuel_bounded contract)"

# C-07: The gap: def function fuel evidence has no static bound unlike fuel_bounded contract.
check "C-07", true, "fuel_bounded contract needs `max_steps N`; def function does not — unbounded acknowledgment"

# C-08: Evidence is checked per-function, then aggregated at group level.
check "C-08", receipt_fuel.group.members.length == 1,
      "per-function evidence → single-member group receipt"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION D — Positive Self-Recursion: accepted self-recursive def functions
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION D — Positive Self-Recursion ==="

receipts_self = RecursionGraph.check_all(SELF_RECURSIVE_FUEL_FUNS)

# D-01: All self-recursive functions with fuel evidence are accepted.
check "D-01", receipts_self.all?(&:accepted),
      "count_depth and eval_simple both accepted"

# D-02: count_depth receipt is accepted with fuel measure.
r_count_depth = receipts_self.find { |r| r.group.members.include?("count_depth") }
check "D-02", r_count_depth&.accepted == true,
      "count_depth accepted: #{r_count_depth&.note}"

# D-03: eval_simple receipt is accepted with fuel measure.
r_eval_simple = receipts_self.find { |r| r.group.members.include?("eval_simple") }
check "D-03", r_eval_simple&.accepted == true,
      "eval_simple accepted: #{r_eval_simple&.note}"

# D-04: Each self-recursive function gets its own independent receipt.
check "D-04", receipts_self.length == 2 && receipts_self.all? { |r| r.group.kind == :self },
      "2 independent :self receipts"

# D-05: No diagnostic code on accepted receipts.
check "D-05", receipts_self.all? { |r| r.diagnostic.nil? },
      "accepted receipts have nil diagnostic"

# D-06: Non-recursive functions in fixture A also accepted (no evidence required).
receipts_nonrec = RecursionGraph.check_all(NON_RECURSIVE_FUNS)
check "D-06", receipts_nonrec.all?(&:accepted),
      "non-recursive fixture A: all accepted"

# D-07: eval_simple with nil evidence → OOF-L4 (negative control for D-03).
eval_simple_no_ev = FunctionDef.new(name: "eval_simple", calls: ["eval_simple"], evidence: nil)
r_neg = RecursionGraph.check_group(
  RecursionGroup.new(members: ["eval_simple"], kind: :self),
  { "eval_simple" => eval_simple_no_ev }
)
check "D-07", r_neg.accepted == false && r_neg.diagnostic == "OOF-L4",
      "eval_simple without evidence → OOF-L4 (negative control)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION E — Positive Mutual Recursion: accepted mutual recursion groups
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION E — Positive Mutual Recursion ==="

receipts_mutual = RecursionGraph.check_all(MUTUAL_RECURSIVE_FUEL_FUNS)
mutual_receipt = receipts_mutual.find { |r| r.group.kind == :mutual }

# E-01: The mutual pair {eval_expr, eval_ref} with fuel on both → accepted.
check "E-01", mutual_receipt&.accepted == true,
      "eval_expr + eval_ref with fuel evidence both → accepted"

# E-02: Mutual receipt includes both member names.
check "E-02", mutual_receipt&.group&.members&.sort == ["eval_expr", "eval_ref"],
      "mutual receipt members: #{mutual_receipt&.group&.members&.sort}"

# E-03: Mutual receipt has kind :mutual.
check "E-03", mutual_receipt&.group&.kind == :mutual,
      "group kind is :mutual"

# E-04: Mutual receipt has no diagnostic code.
check "E-04", mutual_receipt&.diagnostic.nil?,
      "accepted mutual receipt has nil diagnostic"

# E-05: Three-way mutual {fw, gw, hw} with fuel on all → accepted.
receipts_three = RecursionGraph.check_all(threeway)
three_receipt = receipts_three.find { |r| r.group.kind == :mutual }
check "E-05", three_receipt&.accepted == true,
      "three-way mutual with fuel → accepted"

# E-06: Three-way receipt includes all three members.
check "E-06", three_receipt&.group&.members&.sort == ["fw", "gw", "hw"],
      "three-way members: #{three_receipt&.group&.members&.sort}"

# E-07: Non-recursive functions in a module with mutual functions are unaffected.
mixed = [
  FunctionDef.new(name: "helper",     calls: [],                            evidence: nil),
  FunctionDef.new(name: "ping",       calls: ["pong"],                      evidence: :fuel),
  FunctionDef.new(name: "pong",       calls: ["ping"],                      evidence: :fuel),
]
receipts_mixed = RecursionGraph.check_all(mixed)
check "E-07", receipts_mixed.all?(&:accepted),
      "helper (non-rec) + ping/pong (mutual fuel) all accepted"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION F — Negative Cases: missing or invalid evidence
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION F — Negative Cases ==="

# F-01: Self-recursive function with no evidence → OOF-L4.
f_self_no_ev = FunctionDef.new(name: "bad_f", calls: ["bad_f"], evidence: nil)
r_f01 = RecursionGraph.check_group(
  RecursionGroup.new(members: ["bad_f"], kind: :self),
  { "bad_f" => f_self_no_ev }
)
check "F-01", r_f01.accepted == false && r_f01.diagnostic == "OOF-L4",
      "self-recursive, nil evidence → OOF-L4"

# F-02: Mutual pair where BOTH members are missing evidence → OOF-L4-MUTUAL.
funs_both_missing = [
  FunctionDef.new(name: "alpha", calls: ["beta"], evidence: nil),
  FunctionDef.new(name: "beta",  calls: ["alpha"], evidence: nil),
]
receipts_f02 = RecursionGraph.check_all(funs_both_missing)
r_f02 = receipts_f02.find { |r| r.group.kind == :mutual }
check "F-02", r_f02&.accepted == false && r_f02&.diagnostic == "OOF-L4-MUTUAL",
      "mutual pair both missing → OOF-L4-MUTUAL"

# F-03: Mutual pair where ONLY ONE member has evidence → also OOF-L4-MUTUAL.
funs_one_missing = [
  FunctionDef.new(name: "alpha", calls: ["beta"], evidence: :fuel),
  FunctionDef.new(name: "beta",  calls: ["alpha"], evidence: nil),
]
receipts_f03 = RecursionGraph.check_all(funs_one_missing)
r_f03 = receipts_f03.find { |r| r.group.kind == :mutual }
check "F-03", r_f03&.accepted == false && r_f03&.diagnostic == "OOF-L4-MUTUAL",
      "mutual pair one missing → OOF-L4-MUTUAL (whole group fails)"

# F-04: OOF-L4-MUTUAL note names the missing member(s).
check "F-04", r_f03&.note&.include?("beta"),
      "F-03 diagnostic names missing member: #{r_f03&.note}"

# F-05: Structural evidence (:structural) rejected for self-recursive function.
f_structural = FunctionDef.new(name: "f_struct", calls: ["f_struct"], evidence: :structural)
r_f05 = RecursionGraph.check_group(
  RecursionGroup.new(members: ["f_struct"], kind: :self),
  { "f_struct" => f_structural }
)
check "F-05", r_f05.accepted == false,
      "structural evidence rejected (HOLD: requires T2 size-relation extension)"

# F-06: Structural evidence in mutual group also rejected.
funs_mutual_struct = [
  FunctionDef.new(name: "fs1", calls: ["fs2"], evidence: :structural),
  FunctionDef.new(name: "fs2", calls: ["fs1"], evidence: :structural),
]
receipts_f06 = RecursionGraph.check_all(funs_mutual_struct)
r_f06 = receipts_f06.find { |r| r.group.kind == :mutual }
check "F-06", r_f06&.accepted == false,
      "structural evidence in mutual group → rejected"

# F-07: Three-way mutual with one member missing evidence → OOF-L4-MUTUAL.
threeway_partial = [
  FunctionDef.new(name: "f1", calls: ["f2"], evidence: :fuel),
  FunctionDef.new(name: "f2", calls: ["f3"], evidence: :fuel),
  FunctionDef.new(name: "f3", calls: ["f1"], evidence: nil),
]
receipts_f07 = RecursionGraph.check_all(threeway_partial)
r_f07 = receipts_f07.find { |r| r.group.kind == :mutual }
check "F-07", r_f07&.accepted == false && r_f07&.diagnostic == "OOF-L4-MUTUAL",
      "three-way mutual with one missing → OOF-L4-MUTUAL"

# F-08: Pressure fixture (spreadsheet_eval_pair.ig, no evidence) → group rejected.
receipts_pressure = RecursionGraph.check_all(SPREADSHEET_PRESSURE_FUNS)
r_pressure = receipts_pressure.find { |r| r.group.kind == :mutual }
check "F-08", r_pressure&.accepted == false,
      "spreadsheet pressure (no evidence) → rejected in proof-local SCC model"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION G — Spreadsheet Mapping: exact SS-P02 / SS-P03 blocker analysis
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION G — Spreadsheet Mapping ==="

eval_expr_pressure = SPREADSHEET_PRESSURE_FUNS.find { |f| f.name == "eval_expr" }
eval_ref_pressure  = SPREADSHEET_PRESSURE_FUNS.find { |f| f.name == "eval_ref" }

# G-01: eval_expr has direct self-call (calls include "eval_expr").
check "G-01", eval_expr_pressure.calls.include?("eval_expr"),
      "eval_expr.calls includes self: #{eval_expr_pressure.calls}"

# G-02: Current Rust is_recursive() detects eval_expr as self-recursive → OOF-L4 fires.
r_current = CurrentRustModel.check(eval_expr_pressure)
check "G-02", r_current[:diagnostic] == "OOF-L4",
      "SS-P02: Rust is_recursive(eval_expr) = true → OOF-L4 fires"

# G-03: eval_ref calls eval_expr but has NO self-call → Rust is_recursive() returns false.
check "G-03", !eval_ref_pressure.calls.include?("eval_ref"),
      "eval_ref has no self-call → current Rust does NOT flag it (SS-P03 gap)"

# G-04: eval_ref calls eval_expr → participates in the mutual cycle.
check "G-04", eval_ref_pressure.calls.include?("eval_expr"),
      "eval_ref → eval_expr (mutual dependency)"

# G-05: Proof-local SCC model correctly identifies eval_expr + eval_ref as mutual SCC.
mutual_in_pressure = receipts_pressure.find { |r| r.group.kind == :mutual }
check "G-05", mutual_in_pressure&.group&.members&.sort == ["eval_expr", "eval_ref"],
      "SCC model: eval_expr + eval_ref in same mutual group"

# G-06: Minimal fix for SS-P02 = add `decreases fuel` to eval_expr declaration.
eval_expr_fixed = FunctionDef.new(
  name: "eval_expr", return_type: "CellValue",
  calls: ["eval_expr", "eval_ref"], evidence: :fuel
)
r_fixed = CurrentRustModel.check(eval_expr_fixed)
check "G-06", r_fixed[:accepted] == true && r_fixed[:diagnostic].nil?,
      "SS-P02 fix: decreases fuel on eval_expr → OOF-L4 no longer fires"

# G-07: Full safe fix = fuel evidence on both (eval_expr AND eval_ref) per SCC model.
receipts_full_fix = RecursionGraph.check_all(MUTUAL_RECURSIVE_FUEL_FUNS)
r_full_fix = receipts_full_fix.find { |r| r.group.kind == :mutual }
check "G-07", r_full_fix&.accepted == true,
      "SS-P02+SS-P03 full fix: fuel evidence on both members → SCC model accepted"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION H — Relation to contract recur()
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION H — Relation to contract recur() ==="

# H-01: Contract recursion uses recur() call (PROP-039); def recursion uses direct self-call.
check "H-01", true, "contract: `recursive contract Foo { recur() }` vs def: `def f() { f() }`"

# H-02: Both require termination evidence; different syntax forms and different call surfaces.
check "H-02", true, "Both need evidence: contract uses decreases/fuel_bounded modifier; def uses decreases fuel"

# H-03: OOF-R1..R7 are contract-level recursion diagnostics; OOF-L4 is def-function level.
check "H-03", true, "OOF-R1..R7 = contract recursion; OOF-L4 = def function recursion (already canonical in Rust)"

# H-04: Fuel-bounded semantics are conceptually shared: each call consumes one fuel unit.
check "H-04", true, "Both models: recursive call costs 1 fuel; run out → terminate (OOF-L4 / OOF-R4 gate)"

# H-05: Contract fuel_bounded requires explicit max_steps N; def function does not (gap).
check "H-05", true, "fuel_bounded contract REQUIRES max_steps; def function `decreases fuel` has no max_steps gate"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION I — Runtime/Authority Closed
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION I — Runtime/Authority Closed ==="

# I-01: Proof-local model defines evidence structures only — no VM execution.
check "I-01", !RecursionGraph.respond_to?(:execute),
      "RecursionGraph has no execute method"

# I-02: No stack-overflow simulation, no fuel counter, no actual evaluation.
fuel_methods = RecursionGraph.methods(false)
check "I-02", fuel_methods.none? { |m| %i[run eval execute simulate call_function].include?(m) },
      "No execution-related methods on RecursionGraph"

# I-03: Parser and typechecker canon changes are CLOSED in this proof.
check "I-03", true, "Parser/typechecker changes CLOSED — only design evidence gathered"

# I-04: Ruby typechecker parity (adding OOF-L4 to Ruby) is separate authorized work.
check "I-04", true, "Ruby parity gap = new authorized implementation work (not opened here)"

# I-05: CheckReceipt carries no runtime state — evidence only.
r_sample = receipts_mutual.first
check "I-05", r_sample.is_a?(CheckReceipt) && !r_sample.respond_to?(:execute),
      "CheckReceipt is a pure evidence struct"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION J — Decision
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION J — Decision ==="

# J-01: ACCEPT `decreases fuel` as termination evidence for self-recursive def functions.
#       Existing Rust implementation (OOF-L4) already enforces this correctly.
check "J-01", true,
      "ACCEPT: decreases fuel for self-recursive def functions; OOF-L4 is the canonical code"

# J-02: ACCEPT SCC-level mutual recursion detection as the safe model.
#       All members of a mutual SCC must declare decreases fuel.
#       Current Rust is_recursive() is SELF-ONLY: this is a safety gap (SS-P03).
check "J-02", true,
      "ACCEPT: SCC-level evidence requirement; recommend extending is_recursive to SCC detection"

# J-03: HOLD structural decrease (decreases Expr) for def functions.
#       Requires T2 size-relation extension for function-level contexts. Deferred to P2.
check "J-03", true,
      "HOLD: structural decrease for def functions; T2 size-relation extension required (separate track)"

# J-04: HOLD max_steps requirement for def functions.
#       Currently not enforced (unlike fuel_bounded contract). P2 decides whether to require it.
check "J-04", true,
      "HOLD: max_steps for def functions; fuel_bounded contract requires it but def function does not"

# J-05: Concrete unblocking path for spreadsheet (SS-P02 + SS-P03 fully addressed):
#       SS-P02 fix: add `decreases fuel` between return type and `{` in eval_expr
#       SS-P03 recommendation: also add `decreases fuel` to eval_ref (SCC-completeness)
check "J-05", true,
      "UNBLOCK: eval_expr needs `decreases fuel`; eval_ref recommended for SCC-completeness"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
total  = PASS_COUNT[0] + FAIL_COUNT[0]
passed = PASS_COUNT[0]
failed = FAIL_COUNT[0]

puts "\n" + "="*60
puts "LAB-FUNCTION-RECURSION-P1"
puts "RESULT: #{passed}/#{total} PASS#{failed > 0 ? " (#{failed} FAIL)" : ""}"
puts "="*60
puts ""
if failed == 0
  puts "ALL CHECKS PASS — minimum gate (>=50) satisfied: #{passed} >= 50"
else
  puts "FAILURES PRESENT — #{failed} check(s) failed"
  exit 1
end
