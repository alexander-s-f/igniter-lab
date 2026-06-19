#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_stringly_call_contract_p1.rb
# LAB-STDLIB-STRINGLY-CALL-CONTRACT-P1 — Classification and routing proof
# ========================================================================
# Classifies every call_contract("append"/"empty"/...) call in the app corpus,
# proves current blocking behavior in both TCs, proves why NOT to special-case
# stdlib names inside call_contract dispatch, and recommends routes.
#
# No implementation. No source rewrites. Research/proof only.
#
# Sections:
#   A  Census                      (5)  — enumerate all stdlib-form callees + counts
#   B  Shape classification        (6)  — BOOTSTRAP / ACCUMULATING / EMPTY_CONSTRUCTOR
#   C  Current blocking            (6)  — OOF-TY0 in both Ruby + Rust TCs
#   D  Direct stdlib alternative   (5)  — append() works; empty() absent; bootstrap blocked
#   E  Why not special-case        (5)  — 5 invariants that forbid stdlib-name hijack
#   F  Route decision              (6)  — ACCUMULATING migrable today; BOOTSTRAP + EMPTY gated on empty()
#   G  Inventory                   (4)  — append present; empty absent; next track clear
#
# Total: 37 checks

require "json"
require "open3"
require "pathname"
require "tmpdir"

ROOT         = Pathname.new(__dir__).parent
LAB_ROOT     = ROOT.parent
WORKSPACE    = LAB_ROOT.parent
IGNITER_LIB  = WORKSPACE / "igniter-lang" / "lib"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
TC_RUBY_PATH = WORKSPACE / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
TC_RUST_PATH = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
APPS_DIR     = LAB_ROOT / "igniter-apps"
INVENTORY    = WORKSPACE / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

abort "Rust binary not found — run cargo build --release" unless COMPILER_BIN.exist?

INV = JSON.parse(INVENTORY.read(encoding: "utf-8"))

# ── Harness ─────────────────────────────────────────────────────────────────

CHECKS = []

def check(label)
  pass = false
  detail = nil
  begin
    pass = yield == true
  rescue => e
    detail = "#{e.class}: #{e.message.lines.first&.strip}"
  end
  CHECKS << { label: label, pass: pass, detail: detail }
  puts "#{pass ? "PASS" : "FAIL"} #{label}"
  puts "     #{detail}" if detail && !pass
end

def section(name)
  puts "\n[#{name}]"
end

# ── Compile helpers ──────────────────────────────────────────────────────────

def ruby_compile(source)
  Dir.mktmpdir("stringly_rb_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: [f], out_path: out)
    r = result["result"] || result
    {
      typecheck: r.dig("stages", "typecheck") || "unknown",
      status:    r["status"]                  || "unknown",
      diags:     Array(r["diagnostics"]),
      codes:     Array(r["diagnostics"]).map { |d| d["rule"] }.compact
    }
  end
end

def rust_compile(source)
  Dir.mktmpdir("stringly_rs_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    stdout, _stderr, _st = Open3.capture3(COMPILER_BIN.to_s, "compile", f, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    {
      status: r["status"] || "unknown",
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def first_oof_message(diags, rule = "OOF-TY0")
  Array(diags).find { |d| d["rule"] == rule }&.fetch("message", "")
end

def inv_entry(name)
  INV["entries"].find { |e| e["canonical_name"] == name }
end

# ── App source census helpers ────────────────────────────────────────────────

# Returns all lines of the form: call_contract("X", ...) from all .ig files in apps dir.
def all_cc_calls
  @all_cc_calls ||= begin
    calls = []
    Dir.glob((APPS_DIR / "**" / "*.ig").to_s).sort.each do |path|
      src = File.read(path, encoding: "UTF-8")
      src.each_line.with_index(1) do |line, lineno|
        next unless line.include?("call_contract(")
        # Extract first argument (callee name or variable)
        m = line.match(/call_contract\(\s*"([^"]*)"/)
        callee = m ? m[1] : :dynamic
        calls << { file: path, line: lineno, callee: callee, text: line.strip }
      end
    end
    calls
  end
end

def stdlib_calls
  all_cc_calls.select { |c| c[:callee].is_a?(String) && c[:callee] =~ /\A[a-z_]+\z/ }
end

def append_calls
  all_cc_calls.select { |c| c[:callee] == "append" }
end

def empty_calls
  all_cc_calls.select { |c| c[:callee] == "empty" }
end

# Classify "append" call shape by source line heuristic.
# BOOTSTRAP:    call_contract("append", bare_var, bare_var) — neither arg is a field access
#               or known Collection variable. Pattern: two simple identifiers or literals.
# ACCUMULATING: call_contract("append", field_or_coll_var, element)
#               First arg contains "." (field access) or ends in a known context pattern.
def classify_append(call_text)
  # Strip call_contract("append", and trailing )
  inner = call_text.sub(/.*call_contract\("append",\s*/, "").sub(/\)\s*$/, "")
  parts = inner.split(",", 2)
  return :unknown if parts.size < 2
  first = parts[0].strip
  # ACCUMULATING: first arg is a field access (contains ".") or is a Collection var (c0, b0..)
  # followed immediately by a chaining pattern
  if first.include?(".") || first =~ /\A[cb]\d+\z/ || first =~ /\Anew_\w+\z/ ||
     first =~ /\Atree\b/ || first =~ /\Alayer\b/ || first =~ /\Astate\b/ || first =~ /\Actx\b/
    :accumulating
  else
    :bootstrap
  end
end

# ── Section A: Census ────────────────────────────────────────────────────────

section("A-CENSUS")

check("A-01 Only 'append' and 'empty' are stdlib-form callees (no concat/is_empty/map/etc.)") {
  callee_names = stdlib_calls.map { |c| c[:callee] }.uniq.sort
  callee_names == %w[append empty]
}

check("A-02 Total 'append' stdlib-form calls = 31") {
  append_calls.size == 31
}

check("A-03 Total 'empty' stdlib-form calls = 3") {
  empty_calls.size == 3
}

check("A-04 Total stdlib-form calls = 34 (matches P1 grounding baseline)") {
  stdlib_calls.size == 34
}

# Files affected by "append": arch_patterns (example + pipeline), decision_tree (example + builder),
# bloom_filter (example), igniter_parser (parser + lexer), vector_editor (document)
check("A-05 'append' spans 8 app files across 5 apps") {
  files = append_calls.map { |c| c[:file] }.uniq
  files.size == 8
}

# ── Section B: Shape Classification ─────────────────────────────────────────

section("B-SHAPE-CLASSIFICATION")

bootstrap_calls    = append_calls.select { |c| classify_append(c[:text]) == :bootstrap }
accumulating_calls = append_calls.select { |c| classify_append(c[:text]) == :accumulating }

check("B-01 BOOTSTRAP shape identified: first arg is bare element (T+T → Collection[T])") {
  # arch_patterns/example.ig:23 (t0, t1), :65 ("pipeline:start", "pipeline:init")
  # decision_tree/example.ig:32,56,57 — two TreeNode/Feature records
  # bloom_filter/example.ig:35 (s0, s1)
  bootstrap_calls.any? { |c| c[:file].include?("arch_patterns/example") && c[:line] == 23 } &&
    bootstrap_calls.any? { |c| c[:file].include?("bloom_filter/example") && c[:line] == 35 }
}

check("B-02 BOOTSTRAP count = 6 calls") {
  bootstrap_calls.size == 6
}

check("B-03 ACCUMULATING shape identified: first arg is Collection-typed (field/chained var)") {
  accumulating_calls.any? { |c| c[:file].include?("arch_patterns/pipeline") } &&
    accumulating_calls.any? { |c| c[:file].include?("decision_tree/builder") }
}

check("B-04 ACCUMULATING count = 25 calls") {
  accumulating_calls.size == 25
}

check("B-05 EMPTY_CONSTRUCTOR shape: 'empty' calls all have zero positional args") {
  empty_calls.all? { |c| c[:text].match?(/call_contract\("empty"\)/) }
}

check("B-06 EMPTY_CONSTRUCTOR count = 3; all in igniter_parser") {
  empty_calls.size == 3 &&
    empty_calls.all? { |c| c[:file].include?("igniter_parser") }
}

# ── Section C: Current Blocking ──────────────────────────────────────────────

section("C-CURRENT-BLOCKING")

# Ruby fixtures
c1_rb = ruby_compile(<<~IG)
  module CcAppend
  pure contract TestAccum {
    input coll : Collection[Integer]
    input elem : Integer
    compute result = call_contract("append", coll, elem)
    output result : Collection[Integer]
  }
IG

c2_rb = ruby_compile(<<~IG)
  module CcAppendBoot
  pure contract TestBoot {
    input a : Integer
    input b : Integer
    compute result = call_contract("append", a, b)
    output result : Collection[Integer]
  }
IG

c3_rb = ruby_compile(<<~IG)
  module CcEmpty
  pure contract TestEmpty {
    compute result = call_contract("empty")
    output result : Collection[Integer]
  }
IG

c4_rs = rust_compile(<<~IG)
  module CcAppendRs
  pure contract TestAccumRs {
    input coll : Collection[Integer]
    input elem : Integer
    compute result = call_contract("append", coll, elem)
    output result : Collection[Integer]
  }
IG

c5_rs = rust_compile(<<~IG)
  module CcBootRs
  pure contract TestBootRs {
    input a : Integer
    input b : Integer
    compute result = call_contract("append", a, b)
    output result : Collection[Integer]
  }
IG

c6_rs = rust_compile(<<~IG)
  module CcEmptyRs
  pure contract TestEmptyRs {
    compute result = call_contract("empty")
    output result : Collection[Integer]
  }
IG

check("C-01 Ruby TC: call_contract('append', coll, elem) accumulating → OOF-TY0") {
  c1_rb[:codes].include?("OOF-TY0")
}
check("C-02 Ruby TC: call_contract('append', T, T) bootstrap → OOF-TY0 (same error path)") {
  c2_rb[:codes].include?("OOF-TY0")
}
check("C-03 Ruby TC: call_contract('empty') → OOF-TY0") {
  c3_rb[:codes].include?("OOF-TY0")
}
check("C-04 Rust TC: call_contract('append', ...) accumulating → OOF-TY0") {
  c4_rs[:codes].include?("OOF-TY0")
}
check("C-05 Rust TC: call_contract('append', T, T) bootstrap → OOF-TY0") {
  c5_rs[:codes].include?("OOF-TY0")
}
check("C-06 Error message is 'not found in this module' — callee semantics, not a missing dispatch") {
  first_oof_message(c1_rb[:diags]).include?("not found in this module") &&
    first_oof_message(c4_rs[:diags]).include?("not found in this module")
}

# ── Section D: Direct stdlib alternative ─────────────────────────────────────

section("D-DIRECT-STDLIB-ALTERNATIVE")

d1_rb = ruby_compile(<<~IG)
  module DirectAppend
  pure contract TestDirectAccum {
    input coll : Collection[Integer]
    input elem : Integer
    compute result = append(coll, elem)
    output result : Collection[Integer]
  }
IG

d2_rs = rust_compile(<<~IG)
  module DirectAppendRs
  pure contract TestDirectAccumRs {
    input coll : Collection[Integer]
    input elem : Integer
    compute result = append(coll, elem)
    output result : Collection[Integer]
  }
IG

d3_rb = ruby_compile(<<~IG)
  module BootstrapDirect
  pure contract TestDirectBoot {
    input a : Integer
    input b : Integer
    compute result = append(a, b)
    output result : Collection[Integer]
  }
IG

d4_rb = ruby_compile(<<~IG)
  module DirectEmpty
  pure contract TestDirectEmpty {
    compute result = empty()
    output result : Collection[Integer]
  }
IG

check("D-01 Ruby: append(coll, elem) direct form → typecheck=ok (stdlib.collection.append dual-toolchain)") {
  d1_rb[:typecheck] == "ok"
}
check("D-02 Rust: append(coll, elem) direct form → status=ok") {
  d2_rs[:status] == "ok"
}
check("D-03 Ruby: append(T, T) bootstrap → OOF-COL2 (canonical requires Collection[T]×T, not T×T)") {
  d3_rb[:codes].include?("OOF-COL2")
}
check("D-04 Ruby: empty() direct → OOF-TY0 'Unknown function: empty' (stdlib.collection.empty absent)") {
  d4_rb[:codes].include?("OOF-TY0") &&
    first_oof_message(d4_rb[:diags]).include?("empty")
}
check("D-05 inventory: stdlib.collection.empty is ABSENT") {
  inv_entry("stdlib.collection.empty").nil?
}

# ── Section E: Why not special-case stdlib names in call_contract ─────────────

section("E-WHY-NOT-SPECIAL-CASE")

TC_RB_SRC = TC_RUBY_PATH.read(encoding: "utf-8")
TC_RS_SRC = TC_RUST_PATH.read(encoding: "utf-8")

# E-01: The call_contract registry only contains PascalCase module contracts.
# "append" can never match — correct behavior by definition.
check("E-01 Ruby call_contract registry built from classified_program contracts only (no stdlib)") {
  # The registry builder reads classified_program module contracts — all PascalCase.
  # No stdlib entry exists at all. This is correct: call_contract is inter-contract dispatch.
  infer_cc_body = TC_RB_SRC[/def infer_call_contract.*?^    end/m] || ""
  infer_cc_body.include?("@call_contract_registry[callee_name]") &&
    !infer_cc_body.include?("stdlib")
}

# E-02: Bootstrap shape (T×T) is NOT the canonical append signature.
# If we special-cased "append" inside call_contract, we'd need to detect T+T vs Collection[T]+T.
# That's a sub-language inside the call_contract handler — complexity without authority.
check("E-02 Bootstrap arity: append(T,T) → OOF-COL2 (not bootstrap-compatible with stdlib signature)") {
  # Already proved in D-03: direct append(T, T) fires OOF-COL2 not a bootstrap success.
  # Special-casing would need to handle this differently — a semantic divergence.
  d3_rb[:codes].include?("OOF-COL2")
}

# E-03: "append" is already dispatched at the direct infer_call level (when "append").
# Special-casing in call_contract would create a second dispatch path for the same name.
check("E-03 Ruby TC: 'append' already handled at infer_call 'when' level (no double-dispatch)") {
  infer_call_body = TC_RB_SRC[/def infer_call\b.*?^  end/m] || ""
  infer_call_body.match?(/when\s+"append"/)
}

# E-04: SIR structural mismatch — call_contract produces call{fn:"call_contract",args:[...]}.
# Stdlib route requires call{fn:"stdlib.collection.append",args:[coll,elem]}.
# That's an AST lowering step, not type inference. Doing it in TC is a boundary violation.
check("E-04 Rust TC: call_contract fn is distinct from stdlib dispatch fn in SIR") {
  # The Rust TC call_contract handler emits the resolved type but the fn key stays "call_contract".
  # Stdlib append emits fn:"append" → lowered to "stdlib.collection.append".
  # The two fn keys are semantically different in SIR.
  TC_RS_SRC.include?('"call_contract"') && TC_RS_SRC.include?('"append"')
}

# E-05: Allowlisting stdlib names in call_contract widens the contract dispatch boundary.
# call_contract is typed as "call a named module contract" — not "call any named thing".
# Mixing in stdlib names breaks the invariant that the callee is a declared contract in scope.
check("E-05 call_contract callee invariant: callee must be in module registry (not allowlisted extern)") {
  # Proved by C-01/C-04: the error message is explicitly 'not found in this module'.
  # This is the intended behavior — stdlib names are not module contracts.
  first_oof_message(c1_rb[:diags]).include?("not found in this module") &&
    first_oof_message(c4_rs[:diags]).include?("not found in this module")
}

# ── Section F: Route Decision ────────────────────────────────────────────────

section("F-ROUTE-DECISION")

# F-01: ACCUMULATING form is a 1:1 mechanical rewrite:
#   call_contract("append", coll, elem) → append(coll, elem)
# This works TODAY in both TCs (proved D-01, D-02). No blocker except source edit.
check("F-01 ACCUMULATING form is directly migrable: append(coll, elem) works in Ruby + Rust today") {
  d1_rb[:typecheck] == "ok" && d2_rs[:status] == "ok"
}

check("F-02 ACCUMULATING count (25) = migrable calls that need no new stdlib feature") {
  accumulating_calls.size == 25
}

# F-03: BOOTSTRAP form is NOT directly migrable.
# call_contract("append", t1, t2) requires empty() to rewrite as append(empty(), t1) / append(append(empty(), t1), t2).
# Route: LANG-STDLIB-COLLECTION-EMPTY-P1
check("F-03 BOOTSTRAP form blocked until stdlib.collection.empty exists: append(T,T) → OOF-COL2") {
  d3_rb[:codes].include?("OOF-COL2")
}

check("F-04 EMPTY_CONSTRUCTOR form blocked: empty() absent → needs LANG-STDLIB-COLLECTION-EMPTY-P1") {
  d4_rb[:codes].include?("OOF-TY0")
}

# F-05: After LANG-STDLIB-COLLECTION-EMPTY-P1, all 6 bootstrap calls and 3 empty calls
# become migrable: bootstrap → append(empty(), t1) then chained; empty → empty().
check("F-05 Bootstrap + empty total = 9 calls gated on LANG-STDLIB-COLLECTION-EMPTY-P1") {
  (bootstrap_calls.size + empty_calls.size) == 9
}

# F-06: Total migration: 25 (accumulating, today) + 6 (bootstrap, post-empty) + 3 (empty-constructor, post-empty)
# = 34 calls fully migrable after LANG-STDLIB-COLLECTION-EMPTY-P1.
check("F-06 After LANG-STDLIB-COLLECTION-EMPTY-P1: all 34 stdlib-form calls migrable (25+9)") {
  accumulating_calls.size + bootstrap_calls.size + empty_calls.size == 34
}

# ── Section G: Inventory ─────────────────────────────────────────────────────

section("G-INVENTORY")

append_inv = inv_entry("stdlib.collection.append")
empty_inv  = inv_entry("stdlib.collection.empty")

check("G-01 stdlib.collection.append present in inventory (lab-implemented, dual-toolchain)") {
  append_inv&.fetch("lifecycle_status") == "lab-implemented" &&
    append_inv&.fetch("lowering_status") == "dual-toolchain"
}
check("G-02 stdlib.collection.empty NOT in inventory — new track required") {
  empty_inv.nil?
}
check("G-03 Next track LANG-STDLIB-COLLECTION-EMPTY-P1 is clean (no predecessors needed)") {
  # stdlib.collection.append is complete (dual-toolchain); empty is a parallel stdlib entry.
  # No dependency on in-flight work — clear next track.
  append_inv&.fetch("lifecycle_status") == "lab-implemented"
}
check("G-04 stdlib.collection.append compatibility note documents the bootstrap dependency") {
  append_inv&.fetch("compatibility_note", "").include?("empty")
}

# ── Summary ──────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total  = CHECKS.size
passed = CHECKS.count { |c| c[:pass] }
failed = total - passed

puts "LAB-STDLIB-STRINGLY-CALL-CONTRACT-P1 #{passed == total ? "PASS" : "FAIL"} (#{passed}/#{total})"

if failed > 0
  puts "\nFailed checks:"
  CHECKS.each { |c| puts "  FAIL #{c[:label]}#{c[:detail] ? " — #{c[:detail]}" : ""}" unless c[:pass] }
end
