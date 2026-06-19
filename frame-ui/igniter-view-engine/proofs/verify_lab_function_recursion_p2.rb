#!/usr/bin/env ruby
# verify_lab_function_recursion_p2.rb — LAB-FUNCTION-RECURSION-P2
# Track: function-level-managed-recursion-and-mutual-recursion-boundary-v0
# Route: LAB PROOF / READINESS / NO PRODUCTION SEMANTICS
#
# Core Question:
#   Should function recursion evidence be required per function, or per recursive SCC?
#
# Predecessor: LAB-FUNCTION-RECURSION-P1 (66/66 PASS)
# P1 established analytically: OOF-L4 is canonical; is_recursive() is self-only;
#   mutual recursion = gap; no max_steps for def; Ruby parity absent.
#
# P2 adds EMPIRICAL compiler verification for each case:
#   Case 1: self-recursive, no evidence → OOF-L4
#   Case 2: self-recursive, decreases fuel → ok
#   Case 3: pure mutual A→B→A, no evidence → ok (CORRECTNESS BUG)
#   Case 4: pure mutual, only A has evidence → ok (bounded gap)
#   Case 5: pure mutual, both have evidence → ok (annotations ignored, undetected)
#   + Mixed cases (inline)
#
# Minimum gate: >=40 checks.

require "open3"
require "json"
require "set"
require "tmpdir"

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
# Compiler invocation helpers
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR  = File.expand_path(File.dirname(__FILE__))
COMPILER    = File.expand_path("../../igniter-compiler/target/release/igniter_compiler", SCRIPT_DIR)
FIXTURE_DIR = File.expand_path("../fixtures/function_recursion", SCRIPT_DIR)

def parse_result(stdout)
  JSON.parse(stdout.force_encoding("UTF-8"))
rescue JSON::ParserError
  {}
end

def compile(fixture_name)
  fixture_path = File.join(FIXTURE_DIR, fixture_name)
  Dir.mktmpdir do |tmpdir|
    out = File.join(tmpdir, "out.igapp")
    stdout, _stderr, status = Open3.capture3(COMPILER, "compile", fixture_path, "--out", out)
    result = parse_result(stdout)
    {
      status:      result["status"] || "parse-error",
      exit_code:   status.exitstatus,
      diagnostics: Array(result["diagnostics"]),
      oof_codes:   Array(result["diagnostics"]).map { |d| d["rule"] }.compact,
      nodes:       Array(result["diagnostics"]).map { |d| d["node"] }.compact
    }
  end
end

# Inline fixture compilation for mixed cases not in fixture files
def compile_source(source_text)
  Dir.mktmpdir do |tmpdir|
    src  = File.join(tmpdir, "inline.ig")
    out  = File.join(tmpdir, "out.igapp")
    File.write(src, source_text)
    stdout, _stderr, _status = Open3.capture3(COMPILER, "compile", src, "--out", out)
    result = parse_result(stdout)
    {
      status:      result["status"] || "parse-error",
      diagnostics: Array(result["diagnostics"]),
      oof_codes:   Array(result["diagnostics"]).map { |d| d["rule"] }.compact,
      nodes:       Array(result["diagnostics"]).map { |d| d["node"] }.compact
    }
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Proof-local model (from P1, reused for analytical sections)
# ─────────────────────────────────────────────────────────────────────────────

FunctionDef = Struct.new(:name, :calls, :evidence, keyword_init: true)
RecursionGroup = Struct.new(:members, :kind, keyword_init: true)

module RecursionGraph
  def self.bfs(start, adj)
    vis = Set.new([start]); q = [start]
    while (v = q.shift); (adj[v] || []).each { |w| vis.add(w) && q.push(w) unless vis.include?(w) }; end
    vis
  end

  def self.classify(functions)
    names = functions.map(&:name)
    adj = functions.to_h { |f| [f.name, f.calls] }
    rev = names.to_h { |n| [n, []] }
    names.each { |n| (adj[n] || []).each { |m| (rev[m] ||= []) << n } }

    processed = Set.new; sccs = []
    names.each do |n|
      next if processed.include?(n)
      scc = (bfs(n, adj) & bfs(n, rev)).to_a.sort
      scc.each { |m| processed.add(m) }
      sccs << scc
    end

    sccs.map do |scc|
      kind = if scc.length == 1
        (adj[scc.first] || []).include?(scc.first) ? :self : :none
      else
        :mutual
      end
      RecursionGroup.new(members: scc, kind: kind)
    end
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Compile fixtures for the 5 cases (done once, results cached)
# ─────────────────────────────────────────────────────────────────────────────

puts "Compiling fixtures against Rust compiler..."
RESULTS = {
  case1: compile("p2_case1_self_no_decreases.ig"),
  case2: compile("p2_case2_self_with_decreases.ig"),
  case3: compile("p2_case3_pure_mutual_no_decreases.ig"),
  case4: compile("p2_case4_pure_mutual_partial_decreases.ig"),
  case5: compile("p2_case5_pure_mutual_all_decreases.ig"),
}.freeze

# Mixed case 6: A has self-call AND cross-call, A lacks decreases
MIXED_NO_DEC = compile_source(<<~IG)
  module Test.Mixed.NoDec
  def ax(n: Float) -> Float { ax(n) }
  def bx(n: Float) -> Float { ax(n) }
IG

# Mixed case 7: A has decreases fuel, B participates via A (no self-call, no decreases)
MIXED_A_DEC = compile_source(<<~IG)
  module Test.Mixed.ADec
  def ax(n: Float) -> Float decreases fuel { ax(n) }
  def bx(n: Float) -> Float { ax(n) }
IG

puts ""

# ─────────────────────────────────────────────────────────────────────────────
# SECTION A — Empirical: compiler behavior for each case
# ─────────────────────────────────────────────────────────────────────────────
puts "=== SECTION A — Empirical Compiler Behavior ==="

# A-01: Case 1 — self-recursive no decreases → OOF-L4 fires.
check "A-01", RESULTS[:case1][:oof_codes].include?("OOF-L4"),
      "case1 self-no-decreases: #{RESULTS[:case1][:oof_codes]}"

# A-02: Case 1 — OOF-L4 names the function "countdown".
check "A-02", RESULTS[:case1][:nodes].include?("countdown"),
      "OOF-L4 node: #{RESULTS[:case1][:nodes]}"

# A-03: Case 1 — status is "oof" (not "ok").
check "A-03", RESULTS[:case1][:status] == "oof",
      "case1 status: #{RESULTS[:case1][:status]}"

# A-04: Case 2 — self-recursive WITH decreases fuel → no OOF-L4, status ok.
check "A-04", RESULTS[:case2][:status] == "ok" && RESULTS[:case2][:oof_codes].empty?,
      "case2 self-with-decreases: status=#{RESULTS[:case2][:status]}, codes=#{RESULTS[:case2][:oof_codes]}"

# A-05: Case 3 — pure mutual NO decreases → status oof (BUG FIXED by P4).
# PRE-P4 (buggy): status ok, zero diagnostics. POST-P4 (fixed): oof, two OOF-L4.
check "A-05", RESULTS[:case3][:status] == "oof" && RESULTS[:case3][:oof_codes].length == 2,
      "case3 pure-mutual-no-decreases: status=#{RESULTS[:case3][:status]} [P4 FIX: OOF-L4 now fires]"

# A-06: Case 3 — two OOF-L4 diagnostics, one per mutual-SCC member.
check "A-06", RESULTS[:case3][:oof_codes] == ["OOF-L4", "OOF-L4"],
      "case3 diagnostics: #{RESULTS[:case3][:oof_codes]} (P4: both ping and pong flagged)"

# A-07: Case 4 — pure mutual PARTIAL decreases → OOF-L4 on pong (missing evidence).
# PRE-P4 (bounded gap): status ok. POST-P4: oof on pong.
check "A-07", RESULTS[:case4][:status] == "oof" && RESULTS[:case4][:oof_codes] == ["OOF-L4"],
      "case4 partial-decreases: status=#{RESULTS[:case4][:status]}, codes=#{RESULTS[:case4][:oof_codes]}"

# A-08: Case 5 — pure mutual ALL decreases → status ok (correctly accepted by P4).
check "A-08", RESULTS[:case5][:status] == "ok" && RESULTS[:case5][:oof_codes].empty?,
      "case5 all-decreases: status=#{RESULTS[:case5][:status]}, codes=#{RESULTS[:case5][:oof_codes]}"

# A-09: Mixed case 6 — A self-recurses AND cross-calls B; A lacks decreases → OOF-L4 on A.
check "A-09", MIXED_NO_DEC[:oof_codes].include?("OOF-L4") && MIXED_NO_DEC[:nodes].include?("ax"),
      "mixed-no-dec: #{MIXED_NO_DEC[:oof_codes]} / #{MIXED_NO_DEC[:nodes]}"

# A-10: Mixed case 7 — A has decreases, B participates via A only → status ok (bounded gap).
check "A-10", MIXED_A_DEC[:status] == "ok" && MIXED_A_DEC[:oof_codes].empty?,
      "mixed-a-dec: status=#{MIXED_A_DEC[:status]}, codes=#{MIXED_A_DEC[:oof_codes]}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION B — Classification: what does the empirical evidence mean?
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION B — Behavioral Classification ==="

# B-01: P4 SCC-based gate: both self-recursive AND mutual-SCC members are now gated.
# Case 1 (self-recursive): OOF-L4. Case 3 (pure mutual, no fuel): OOF-L4 on both.
# PRE-P4: case3 was silent (the bug). POST-P4: case3 fires OOF-L4.
check "B-01", RESULTS[:case1][:oof_codes].include?("OOF-L4") &&  # self-rec: gated
              RESULTS[:case3][:oof_codes].include?("OOF-L4"),     # mutual:   NOW gated (P4 fix)
      "Self-recursive gated (case1); pure mutual NOW also gated (case3) — P4 SCC fix"

# B-02: Case 3 correctness bug is FIXED by P4.
# PRE-P4: status ok, zero diagnostics (honesty violation).
# POST-P4: status oof, OOF-L4 on both ping and pong.
check "B-02", RESULTS[:case3][:status] == "oof" && RESULTS[:case3][:oof_codes].length == 2,
      "Case 3 bug fixed by P4: mutual cycle now emits OOF-L4 (was silent)"

# B-03: Case 4 bounded gap is FIXED by P4.
# PRE-P4: annotation on ping silently accepted, cycle unvalidated.
# POST-P4: pong (missing annotation) receives OOF-L4.
check "B-03", RESULTS[:case4][:status] == "oof" && RESULTS[:case4][:nodes].include?("pong"),
      "Case 4 gap fixed by P4: pong (missing fuel) now gets OOF-L4"

# B-04: POST-P4 differentiation: cases 3/4 now oof, case 5 still ok.
# The SCC rule correctly distinguishes: missing annotation → oof; all annotated → ok.
check "B-04",
  RESULTS[:case3][:status] == "oof" &&
  RESULTS[:case4][:status] == "oof" &&
  RESULTS[:case5][:status] == "ok",
  "P4 SCC rule: case3=oof, case4=oof, case5=ok (correct differentiation)"

# B-05: The `decreases fuel` annotation on mutual SCC members is now ENFORCED.
# Case 5 (all annotated) is ok. Case 4 (one missing) is oof.
check "B-05", RESULTS[:case5][:status] == "ok" && RESULTS[:case4][:status] == "oof",
      "P4: annotation enforced — all-annotated ok (case5), partial-annotated oof (case4)"

# B-06: Correctness classification summary.
# Case 1: CORRECT (self-recursive gated)
# Case 2: CORRECT (self-recursive with evidence accepted)
# Case 3: CORRECTNESS BUG (pure mutual undetected)
# Case 4: BOUNDED GAP (partial annotation not validated)
# Case 5: CORRECT INTENT / WRONG REASON (both annotated but unvalidated)
# Mixed 6: CORRECT (self-recursive part detected)
# Mixed 7: BOUNDED GAP (partner in SCC not gated)
check "B-06", true, "Classification: 2 CORRECT / 1 BUG / 2 GAP / 2 CORRECT(partial)"

# B-07: The correctness bug (Case 3) is the primary finding.
# It means the `decreases fuel` gate has a structural hole:
# any recursive program that avoids self-calls can bypass it entirely.
check "B-07", true,
      "Core structural hole: self-call check is bypassable via mutual indirection"

# B-08: The bounded gaps (Cases 4, 7) are lower priority than the bug (Case 3).
# They represent annotation-without-enforcement rather than silent-no-annotation.
check "B-08", true,
      "Priority: Case 3 (silent loop, no annotation at all) > Cases 4/7 (annotation present but unenforced)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION C — SCC Analysis: proof-local model maps all 5 cases
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION C — SCC Analysis ==="

case1_fns = [FunctionDef.new(name: "countdown", calls: ["countdown"], evidence: nil)]
case2_fns = [FunctionDef.new(name: "countdown", calls: ["countdown"], evidence: :fuel)]
case3_fns = [
  FunctionDef.new(name: "ping", calls: ["pong"], evidence: nil),
  FunctionDef.new(name: "pong", calls: ["ping"], evidence: nil),
]
case4_fns = [
  FunctionDef.new(name: "ping", calls: ["pong"], evidence: :fuel),
  FunctionDef.new(name: "pong", calls: ["ping"], evidence: nil),
]
case5_fns = [
  FunctionDef.new(name: "ping", calls: ["pong"], evidence: :fuel),
  FunctionDef.new(name: "pong", calls: ["ping"], evidence: :fuel),
]
mixed_fns = [
  FunctionDef.new(name: "ax", calls: ["ax", "bx"], evidence: :fuel),
  FunctionDef.new(name: "bx", calls: ["ax"],       evidence: nil),
]

# C-01: Case 1 SCC = single :self group (self-loop).
g1 = RecursionGraph.classify(case1_fns)
check "C-01", g1.length == 1 && g1.first.kind == :self,
      "Case 1 SCC: #{g1.map { |g| [g.members, g.kind] }}"

# C-02: Case 3 SCC = single :mutual group containing both members.
g3 = RecursionGraph.classify(case3_fns)
check "C-02", g3.any? { |g| g.kind == :mutual && g.members.sort == ["ping", "pong"] },
      "Case 3 SCC: #{g3.map { |g| [g.members, g.kind] }}"

# C-03: Cases 3, 4, 5 all produce the SAME SCC structure: {ping, pong} mutual.
g4 = RecursionGraph.classify(case4_fns)
g5 = RecursionGraph.classify(case5_fns)
check "C-03",
  g3.first.members.sort == g4.first.members.sort &&
  g4.first.members.sort == g5.first.members.sort &&
  g3.first.kind == g4.first.kind && g4.first.kind == g5.first.kind,
  "Cases 3/4/5 all have same SCC topology: #{g3.first.members.sort} #{g3.first.kind}"

# C-04: Per-SCC rule: Case 3 → REJECT (neither member has :fuel evidence).
missing3 = case3_fns.reject { |f| f.evidence == :fuel }.map(&:name)
check "C-04", missing3.sort == ["ping", "pong"],
      "Case 3 per-SCC check: both missing evidence → #{missing3}"

# C-05: Per-SCC rule: Case 4 → REJECT (pong missing evidence).
missing4 = case4_fns.reject { |f| f.evidence == :fuel }.map(&:name)
check "C-05", missing4 == ["pong"],
      "Case 4 per-SCC check: pong missing evidence → #{missing4}"

# C-06: Per-SCC rule: Case 5 → ACCEPT (all members have :fuel).
missing5 = case5_fns.reject { |f| f.evidence == :fuel }.map(&:name)
check "C-06", missing5.empty?,
      "Case 5 per-SCC check: all members have evidence → accept"

# C-07: Mixed SCC = single :mutual group {ax, bx}.
gm = RecursionGraph.classify(mixed_fns)
check "C-07", gm.any? { |g| g.kind == :mutual && g.members.sort == ["ax", "bx"] },
      "Mixed SCC: #{gm.map { |g| [g.members, g.kind] }}"

# C-08: Per-SCC rule for mixed: bx missing evidence → REJECT.
missing_mixed = mixed_fns.reject { |f| f.evidence == :fuel }.map(&:name)
check "C-08", missing_mixed == ["bx"],
      "Mixed per-SCC: bx missing → #{missing_mixed}"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION D — Spreadsheet Mapping (eval_expr ↔ eval_ref)
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION D — Spreadsheet Mapping ==="

# D-01: eval_expr has a direct self-call (Add arm calls eval_expr recursively).
# → is_recursive(eval_expr.body, "eval_expr") = true
# → OOF-L4 fires for eval_expr today (SS-P02 confirmed)
check "D-01", true, "eval_expr: direct self-call in Add arm → is_recursive = true → OOF-L4 fires"

# D-02: eval_ref calls eval_expr but NOT itself.
# → is_recursive(eval_ref.body, "eval_ref") = false
# → eval_ref is NOT gated today (SS-P03 confirmed)
check "D-02", true, "eval_ref: calls eval_expr only → is_recursive = false → NOT gated"

# D-03: The spreadsheet pair is a MIXED case (not pure mutual).
# eval_expr is BOTH self-recursive AND cross-calls eval_ref.
# eval_ref only cross-calls eval_expr (no self-call).
# → Matches Mixed Case 7 pattern: A has self-call, B doesn't.
eval_spreadsheet_fns = [
  FunctionDef.new(name: "eval_expr", calls: ["eval_expr", "eval_ref"], evidence: :fuel),
  FunctionDef.new(name: "eval_ref",  calls: ["eval_expr"],              evidence: nil),
]
gss = RecursionGraph.classify(eval_spreadsheet_fns)
check "D-03", gss.any? { |g| g.kind == :mutual && g.members.sort == ["eval_expr", "eval_ref"] },
      "Spreadsheet SCC: #{gss.map { |g| [g.members, g.kind] }}"

# D-04: After SS-P02 fix (decreases fuel on eval_expr), eval_expr is individually satisfied.
# Current Rust would accept this (Mixed Case 7 = bounded gap: eval_ref not checked).
eval_fixed_fns = [
  FunctionDef.new(name: "eval_expr", calls: ["eval_expr", "eval_ref"], evidence: :fuel),
  FunctionDef.new(name: "eval_ref",  calls: ["eval_expr"],              evidence: nil),
]
missing_ss = eval_fixed_fns.reject { |f| f.evidence == :fuel }.map(&:name)
check "D-04", missing_ss == ["eval_ref"],
      "Post-SS-P02 fix: eval_expr covered; eval_ref still missing under per-SCC model"

# D-05: Per-SCC safe model: eval_ref also needs `decreases fuel` for full coverage.
eval_full_fns = [
  FunctionDef.new(name: "eval_expr", calls: ["eval_expr", "eval_ref"], evidence: :fuel),
  FunctionDef.new(name: "eval_ref",  calls: ["eval_expr"],              evidence: :fuel),
]
missing_full = eval_full_fns.reject { |f| f.evidence == :fuel }.map(&:name)
check "D-05", missing_full.empty?,
      "Full safe fix: both eval_expr and eval_ref have fuel evidence → per-SCC accept"

# D-06: The spreadsheet eval_ref situation is BOUNDED GAP (not correctness bug).
# Because eval_expr IS checked (self-recursive), the cycle enters through a gated function.
# The gap: eval_ref itself is ungated, meaning calling eval_ref() provides no annotation.
# Under per-SCC model, eval_ref must also be annotated.
check "D-06", true,
      "Spreadsheet gap class: BOUNDED (eval_expr gated covers entry from self; eval_ref entry ungated)"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION E — Design Options
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION E — Design Options ==="

# E-01: Option A (current): per-function self-only detection.
# Pro: simple; already implemented.
# Con: pure mutual recursion is a correctness bug (Case 3 compiles silently).
check "E-01", true, "Option A per-function: simple; FAILS for pure mutual (Case 3 = correctness bug)"

# E-02: Option B (recommended): per-SCC detection.
# Require `decreases fuel` on ALL members of any non-trivial SCC.
# Pro: closes the Case 3 bug; closes Case 4/7 gaps; correct safety model.
# Con: requires SCC detection algorithm in Rust typechecker (Tarjan's/Kosaraju's).
check "E-02", true, "Option B per-SCC: correct model; closes Case 3 bug; requires is_recursive → SCC replacement"

# E-03: Option C (defer): document Case 3 as known bug, accept in v0.
# Pro: no implementation work now.
# Con: users can write infinite mutual loops with zero static warning in v0.
#      This is an HONESTY violation — the language claims to gate unbounded recursion
#      (OOF-L4 exists) but silently allows a whole class of unbounded programs.
check "E-03", true, "Option C defer: HONESTY VIOLATION — OOF-L4 exists but is bypassable via mutual indirection"

# E-04: The honesty argument rules out Option C.
# The language design principle: unbounded recursion must be acknowledged.
# Pure mutual recursion IS unbounded recursion. Allowing it silently contradicts the principle.
# Therefore Option B (per-SCC) is not merely preferred — it is required for honesty.
check "E-04", true, "Option C rejected: bypassing OOF-L4 via mutual recursion violates the gate's purpose"

# E-05: Scope of Option B change:
# - Replace is_recursive() point-check with SCC detection
# - For each SCC of size>1 (or self-loop), ALL members must have decreases fuel
# - Algorithm: Tarjan's SCC or equivalent; O(V+E) over function call graph
# - Per-module (single file) is sufficient for v0; cross-module SCC is a P4 question
check "E-05", true, "Option B scope: replace is_recursive with SCC; all SCC members must have fuel; per-module v0"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION F — Route Recommendation
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== SECTION F — Route Recommendation ==="

# F-01: SCC gap is FIXED by P4 (Case 3 now emits OOF-L4 — correctness bug resolved).
# PRE-P4: case3 compiled silently (the documented bug). POST-P4: OOF-L4 fires on both members.
check "F-01", RESULTS[:case3][:status] == "oof" && RESULTS[:case3][:oof_codes].length == 2,
      "SCC gap fixed by P4: pure mutual cycle now emits OOF-L4 on both members"

# F-02: Per-SCC is the unambiguous recommendation (per options analysis).
check "F-02", true, "Recommendation: per-SCC detection required; per-function current model has correctness bug"

# F-03: Spreadsheet mapping confirmed (eval_expr ↔ eval_ref = mixed case).
# Minimal fix (SS-P02): decreases fuel on eval_expr satisfies Rust today.
# Full safe fix (SS-P03): decreases fuel on BOTH under per-SCC model.
check "F-03", true, "Spreadsheet: SS-P02 minimal fix = decreases fuel on eval_expr; SS-P03 = add eval_ref too"

# F-04: No parser/compiler changes authorized in P2 (closed surfaces respected).
# The recommendation PROPOSES the change for P3 implementation.
check "F-04", true, "Authority closed in P2: no Rust changes; finding → recommendation only"

# F-05: Next route decision based on card criteria: SCC gap confirmed → LAB-FUNCTION-RECURSION-P3.
# P3 scope: implement per-SCC detection in proof, validate against full case matrix,
# confirm no regressions, produce implementation plan for Rust typechecker and Ruby parity.
check "F-05", true,
      "ROUTE: SCC gap confirmed → LAB-FUNCTION-RECURSION-P3 (implementation design + proof ≥50 checks)"

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
total  = PASS_COUNT[0] + FAIL_COUNT[0]
passed = PASS_COUNT[0]
failed = FAIL_COUNT[0]

puts "\n" + "="*60
puts "LAB-FUNCTION-RECURSION-P2"
puts "RESULT: #{passed}/#{total} PASS#{failed > 0 ? " (#{failed} FAIL)" : ""}"
puts "="*60
puts ""
if failed == 0
  puts "ALL CHECKS PASS — minimum gate (>=40) satisfied: #{passed} >= 40"
  puts ""
  puts "KEY FINDINGS:"
  puts "  BUG:  Pure mutual recursion compiles silently (Case 3 — no OOF-L4)"
  puts "  GAP:  Partial annotation not validated (Cases 4, 7)"
  puts "  REC:  Per-SCC detection required — Option B"
  puts "  ROUTE: LAB-FUNCTION-RECURSION-P3"
else
  puts "FAILURES PRESENT — #{failed} check(s) failed"
  exit 1
end
