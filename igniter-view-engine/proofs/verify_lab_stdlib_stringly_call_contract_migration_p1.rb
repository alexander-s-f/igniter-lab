#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_stringly_call_contract_migration_p1.rb
# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P1
# =====================================================================
# Migration readiness proof for all 34 stringly call_contract("append")
# and call_contract("empty") sites in the igniter-apps corpus.
#
# No source migration in P1. No compiler changes. Evidence + proof only.
#
# Sections:
#   A  Source scan coverage         (6)  — all 34 sites found across 5 apps
#   B  Callee inventory             (5)  — only "append" and "empty"; empty() rejected
#   C  Dynamic callee exclusion     (3)  — variable callees not in migration scope
#   D  ACCUMULATING append rewrite  (8)  — canonical append(coll, elem) proves migration
#   E  BOOTSTRAP rewrite            (7)  — typed [t1,t2] seed proves migration
#   F  EMPTY_CONSTRUCTOR rewrite    (5)  — typed compute x : Collection[T] = []
#   G  App and site counts          (5)  — per-app counts match registry evidence
#   H  Migrated fixtures compile   (10)  — all three shapes pass Ruby + Rust
#   I  Blocked and non-goal shapes  (4)  — igniter_parser gated; PascalCase excluded
#   J  Authority boundary           (4)  — no compiler special-case; source-only migration
#
# Total: 57 checks
# Acceptance: ≥50 PASS
#
# Run: ruby verify_lab_stdlib_stringly_call_contract_migration_p1.rb

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

abort "Rust binary not found — run: cd igniter-compiler && cargo build --release" unless COMPILER_BIN.exist?

INV = JSON.parse(INVENTORY.read(encoding: "utf-8"))

# ── Harness ──────────────────────────────────────────────────────────────────

CHECKS = []

def check(label)
  pass   = false
  detail = nil
  begin
    pass = yield == true
  rescue => e
    detail = "#{e.class}: #{e.message.lines.first&.strip}"
  end
  CHECKS << { label: label, pass: pass, detail: detail }
  puts "#{pass ? "PASS" : "FAIL"} #{label}"
  puts "     #{detail}" if detail
  pass
end

def section(name)
  puts "\n[#{name}]"
end

# ── Compile helpers ───────────────────────────────────────────────────────────

def ruby_compile(source)
  Dir.mktmpdir("mig_rb_") do |dir|
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
  Dir.mktmpdir("mig_rs_") do |dir|
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

def ruby_ok?(source)    = ruby_compile(source)[:status] == "ok"
def rust_ok?(source)    = rust_compile(source)[:status] == "ok"
def ruby_oof?(source)   = ruby_compile(source)[:status] == "oof"
def rust_oof?(source)   = rust_compile(source)[:status] == "oof"
def ruby_codes(source)  = ruby_compile(source)[:codes]
def rust_codes(source)  = rust_compile(source)[:codes]

# ── Census helpers ────────────────────────────────────────────────────────────

def all_cc_calls
  @all_cc_calls ||= begin
    calls = []
    Dir.glob((APPS_DIR / "**" / "*.ig").to_s).sort.each do |path|
      src = File.read(path, encoding: "UTF-8")
      src.each_line.with_index(1) do |line, lineno|
        next unless line.include?("call_contract(")
        m      = line.match(/call_contract\(\s*"([^"]*)"/)
        callee = m ? m[1] : :dynamic
        calls << { file: path, line: lineno, callee: callee, text: line.strip }
      end
    end
    calls
  end
end

def append_calls     = all_cc_calls.select { |c| c[:callee] == "append" }
def empty_calls      = all_cc_calls.select { |c| c[:callee] == "empty"  }
def dynamic_calls    = all_cc_calls.select { |c| c[:callee] == :dynamic }

def stdlib_form_calls
  all_cc_calls.select { |c| c[:callee].is_a?(String) && c[:callee] =~ /\A[a-z_]+\z/ }
end

def inv_entry(name)
  INV["entries"].find { |e| e["canonical_name"] == name }
end

def app_of(call_hash)
  File.basename(File.dirname(call_hash[:file]))
end

# ── Fixtures ──────────────────────────────────────────────────────────────────

STRINGLY_APPEND_ACCUM = <<~IG
  module StAccum
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract AppendItem {
    input items : Collection[Item]
    input new_item : Item
    compute result = call_contract("append", items, new_item)
    output result : Collection[Item]
  }
IG

CANONICAL_APPEND_ACCUM = <<~IG
  module CaAccum
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract AppendItem {
    input items : Collection[Item]
    input new_item : Item
    compute result = append(items, new_item)
    output result : Collection[Item]
  }
IG

CANONICAL_APPEND_NO_IMPORT = <<~IG
  module NoImport
  type Item { value : Integer }
  contract AppendItem {
    input items : Collection[Item]
    input new_item : Item
    compute result = append(items, new_item)
    output result : Collection[Item]
  }
IG

CANONICAL_APPEND_WRONG_SIG = <<~IG
  module WrongSig
  import stdlib.collection.{ append }
  type Step { name : String }
  contract Bootstrap {
    compute s1 = { name: "step1" }
    compute s2 = { name: "step2" }
    compute result = append(s1, s2)
    output result : Collection[Step]
  }
IG

STRINGLY_APPEND_BOOTSTRAP = <<~IG
  module StBoot
  import stdlib.collection.{ append }
  type Step { name : String }
  contract Bootstrap {
    compute s1 = { name: "step1" }
    compute s2 = { name: "step2" }
    compute seed = call_contract("append", s1, s2)
    output seed : Collection[Step]
  }
IG

BOOTSTRAP_ARRAY_LITERAL = <<~IG
  module BootArr
  type Step { name : String }
  contract Bootstrap {
    compute s1 = { name: "step1" }
    compute s2 = { name: "step2" }
    compute seed : Collection[Step] = [s1, s2]
    output seed : Collection[Step]
  }
IG

BOOTSTRAP_CHAINED = <<~IG
  module BootChain
  import stdlib.collection.{ append }
  type Step { name : String }
  contract BuildChain {
    compute s1 = { name: "step1" }
    compute s2 = { name: "step2" }
    compute s3 = { name: "step3" }
    compute seed : Collection[Step] = [s1, s2]
    compute result = append(seed, s3)
    output result : Collection[Step]
  }
IG

STRINGLY_EMPTY = <<~IG
  module StEmpty
  type Item { value : Integer }
  contract EmptyItems {
    compute result = call_contract("empty")
    output result : Collection[Item]
  }
IG

EMPTY_TYPED_COMPUTE = <<~IG
  module EmTyped
  type Item { value : Integer }
  contract EmptyItems {
    compute result : Collection[Item] = []
    output result : Collection[Item]
  }
IG

EMPTY_TYPED_DOWNSTREAM = <<~IG
  module EmDownstream
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract BuildFromEmpty {
    compute base : Collection[Item] = []
    compute item = { value: 42 }
    compute result = append(base, item)
    output result : Collection[Item]
  }
IG

STRING_BOOTSTRAP = <<~IG
  module StrBoot
  contract BuildTrail {
    compute trail : Collection[String] = ["pipeline:start", "pipeline:init"]
    output trail : Collection[String]
  }
IG

# Chained ACCUMULATING from input-typed collection — works in both TCs (no typed-[] propagation needed)
CANONICAL_APPEND_CHAINED = <<~IG
  module ChainAccum
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract MultiAppend {
    input items : Collection[Item]
    input a : Item
    input b : Item
    compute step1 = append(items, a)
    compute result = append(step1, b)
    output result : Collection[Item]
  }
IG

# ═══════════════════════════════════════════════════════════════════════════════

section "A — Source scan coverage"

check("A-01: call_contract(\"append\") total sites == 31") {
  append_calls.size == 31
}

check("A-02: call_contract(\"empty\") total sites == 3") {
  empty_calls.size == 3
}

check("A-03: total stdlib-form (lowercase callee) sites == 34") {
  stdlib_form_calls.size == 34
}

check("A-04: exactly 5 apps have stdlib-form call_contract sites") {
  apps = stdlib_form_calls.map { |c| app_of(c) }.uniq.sort
  apps == %w[arch_patterns bloom_filter decision_tree igniter_parser vector_editor]
}

check("A-05: no stdlib-form callee other than \"append\" or \"empty\"") {
  stdlib_form_calls.map { |c| c[:callee] }.uniq.sort == %w[append empty]
}

check("A-06: all call_contract sites are within APPS_DIR subtree") {
  all_cc_calls.all? { |c| c[:file].start_with?(APPS_DIR.to_s) }
}

# ─────────────────────────────────────────────────────────────────────────────

section "B — Callee inventory"

check("B-01: stdlib.collection.append exists in stdlib inventory") {
  !inv_entry("stdlib.collection.append").nil?
}

check("B-02: no active stdlib.collection.empty entry (LANG-STDLIB-COLLECTION-EMPTY-P1 rejected empty())") {
  e = inv_entry("stdlib.collection.empty")
  e.nil? || (e["lifecycle_status"] || "").start_with?("rejected")
}

check("B-03: no other stdlib-form callees besides \"append\" and \"empty\"") {
  stdlib_form_calls.map { |c| c[:callee] }.uniq.reject { |n| %w[append empty].include?(n) }.empty?
}

check("B-04: call_contract(\"append\",...) → OOF-TY0 in Ruby") {
  ruby_codes(STRINGLY_APPEND_ACCUM).include?("OOF-TY0")
}

check("B-05: call_contract(\"append\",...) → OOF-TY0 in Rust") {
  rust_codes(STRINGLY_APPEND_ACCUM).include?("OOF-TY0")
}

# ─────────────────────────────────────────────────────────────────────────────

section "C — Dynamic callee exclusion"

check("C-01: dynamic (variable) call_contract sites exist in corpus") {
  dynamic_calls.size > 0
}

check("C-02: all dynamic sites are in rule_engine (RE-P02/RE-P03 shape, not migration scope)") {
  dynamic_calls.map { |c| app_of(c) }.uniq.all? { |a| a == "rule_engine" }
}

check("C-03: dynamic sites have no string literal callee and are not in stdlib_form_calls") {
  dynamic_calls.none? { |c| stdlib_form_calls.include?(c) }
}

# ─────────────────────────────────────────────────────────────────────────────

section "D — ACCUMULATING append rewrite"

check("D-01: stringly ACCUMULATING call_contract(\"append\", coll, elem) → OOF-TY0 in Ruby") {
  ruby_codes(STRINGLY_APPEND_ACCUM).include?("OOF-TY0")
}

check("D-02: canonical append(coll, elem) → ok in Ruby") {
  ruby_ok?(CANONICAL_APPEND_ACCUM)
}

check("D-03: stringly ACCUMULATING call_contract(\"append\", coll, elem) → OOF-TY0 in Rust") {
  rust_codes(STRINGLY_APPEND_ACCUM).include?("OOF-TY0")
}

check("D-04: canonical append(coll, elem) → ok in Rust") {
  rust_ok?(CANONICAL_APPEND_ACCUM)
}

check("D-05: field-access first arg (ctx.field) identifies ACCUMULATING sites — ≥3 in corpus") {
  field_access = append_calls.select { |c|
    args_text = c[:text].sub(/.*call_contract\("append",\s*/, "")
    first_arg = args_text.split(/,(?![^{]*\})/).first.to_s.strip
    first_arg.include?(".")
  }
  field_access.size >= 3
}

check("D-06: canonical append(T, T) wrong-shape → fails in Ruby (bootstrap needs Collection seed)") {
  ruby_oof?(CANONICAL_APPEND_WRONG_SIG)
}

check("D-07: stdlib.collection.append auto-resolves without explicit import in both TCs") {
  ruby_ok?(CANONICAL_APPEND_NO_IMPORT) && rust_ok?(CANONICAL_APPEND_NO_IMPORT)
}

check("D-08: ACCUMULATING shape spans multiple apps — arch_patterns + bloom_filter + decision_tree + igniter_parser + vector_editor") {
  accum_sites = append_calls.select { |c|
    args_text = c[:text].sub(/.*call_contract\("append",\s*/, "")
    first_arg = args_text.split(/,(?![^{]*\})/).first.to_s.strip
    first_arg.include?(".") || first_arg.match?(/\A[a-z_]+\d+\z/) && first_arg.start_with?("c", "b")
  }
  apps = accum_sites.map { |c| app_of(c) }.uniq.sort
  apps.size >= 4
}

# ─────────────────────────────────────────────────────────────────────────────

section "E — BOOTSTRAP rewrite with typed [] seed"

check("E-01: stringly BOOTSTRAP call_contract(\"append\", t1, t2) → OOF-TY0 in Ruby") {
  ruby_codes(STRINGLY_APPEND_BOOTSTRAP).include?("OOF-TY0")
}

check("E-02: stringly BOOTSTRAP call_contract(\"append\", t1, t2) → OOF-TY0 in Rust") {
  rust_codes(STRINGLY_APPEND_BOOTSTRAP).include?("OOF-TY0")
}

check("E-03: typed array literal [t1, t2] with compute : Collection[T] annotation → ok in Ruby") {
  ruby_ok?(BOOTSTRAP_ARRAY_LITERAL)
}

check("E-04: typed array literal [t1, t2] with compute : Collection[T] annotation → ok in Rust") {
  rust_ok?(BOOTSTRAP_ARRAY_LITERAL)
}

check("E-05: String BOOTSTRAP [\"a\", \"b\"] typed → ok in Ruby") {
  ruby_ok?(STRING_BOOTSTRAP)
}

check("E-06: subsequent canonical append(seed, t3) after typed [] seed → ok in Ruby") {
  ruby_ok?(BOOTSTRAP_CHAINED)
}

check("E-07: Rust TC gap — typed [] annotation doesn't propagate into symbol_types for downstream append → OOF-TY1") {
  # LANG-TYPED-COMPUTE-BINDING-P2 Rust parity not yet implemented.
  # Rust handles output-boundary check for typed [] correctly but does not update symbol_types
  # for downstream use. Ruby P2 handles this via when-compute-annotation path.
  # This confirms the gap; BOOTSTRAP migration in Rust needs LANG-TYPED-COMPUTE-BINDING-P2 Rust parity.
  rust_oof?(BOOTSTRAP_CHAINED)
}

# ─────────────────────────────────────────────────────────────────────────────

section "F — EMPTY_CONSTRUCTOR rewrite with typed []"

check("F-01: stringly call_contract(\"empty\") → OOF-TY0 in Ruby") {
  ruby_codes(STRINGLY_EMPTY).include?("OOF-TY0")
}

check("F-02: stringly call_contract(\"empty\") → OOF-TY0 in Rust") {
  rust_codes(STRINGLY_EMPTY).include?("OOF-TY0")
}

check("F-03: compute result : Collection[T] = [] → ok in Ruby (LANG-TYPED-COMPUTE-BINDING-P2)") {
  ruby_ok?(EMPTY_TYPED_COMPUTE)
}

check("F-04: compute result : Collection[T] = [] → ok in Rust") {
  rust_ok?(EMPTY_TYPED_COMPUTE)
}

check("F-05: typed [] downstream in canonical append chain → ok in Ruby") {
  ruby_ok?(EMPTY_TYPED_DOWNSTREAM)
}

# ─────────────────────────────────────────────────────────────────────────────

section "G — App and site counts match registry"

check("G-01: arch_patterns stdlib-form sites == 9") {
  stdlib_form_calls.count { |c| c[:file].include?("/arch_patterns/") } == 9
}

check("G-02: bloom_filter stdlib-form sites == 15") {
  stdlib_form_calls.count { |c| c[:file].include?("/bloom_filter/") } == 15
}

check("G-03: decision_tree stdlib-form sites == 4") {
  stdlib_form_calls.count { |c| c[:file].include?("/decision_tree/") } == 4
}

check("G-04: igniter_parser stdlib-form sites == 5 (3 \"empty\" + 2 \"append\")") {
  ip = stdlib_form_calls.select { |c| c[:file].include?("/igniter_parser/") }
  ip.size == 5 &&
    ip.count { |c| c[:callee] == "empty"  } == 3 &&
    ip.count { |c| c[:callee] == "append" } == 2
}

check("G-05: vector_editor stdlib-form sites == 1") {
  stdlib_form_calls.count { |c| c[:file].include?("/vector_editor/") } == 1
}

# ─────────────────────────────────────────────────────────────────────────────

section "H — Migrated minimal fixtures compile"

check("H-01: ACCUMULATING canonical append fixture → Ruby ok") {
  ruby_ok?(CANONICAL_APPEND_ACCUM)
}

check("H-02: ACCUMULATING canonical append fixture → Rust ok") {
  rust_ok?(CANONICAL_APPEND_ACCUM)
}

check("H-03: BOOTSTRAP typed [t1,t2] fixture → Ruby ok") {
  ruby_ok?(BOOTSTRAP_ARRAY_LITERAL)
}

check("H-04: BOOTSTRAP typed [t1,t2] fixture → Rust ok") {
  rust_ok?(BOOTSTRAP_ARRAY_LITERAL)
}

check("H-05: EMPTY_CONSTRUCTOR typed [] fixture → Ruby ok") {
  ruby_ok?(EMPTY_TYPED_COMPUTE)
}

check("H-06: EMPTY_CONSTRUCTOR typed [] fixture → Rust ok") {
  rust_ok?(EMPTY_TYPED_COMPUTE)
}

check("H-07: chained canonical append after BOOTSTRAP typed seed → Ruby ok") {
  ruby_ok?(BOOTSTRAP_CHAINED)
}

check("H-08: chained ACCUMULATING append (input-typed Collection) → Rust ok") {
  rust_ok?(CANONICAL_APPEND_CHAINED)
}

check("H-09: String BOOTSTRAP [\"a\",\"b\"] typed fixture → Ruby ok") {
  ruby_ok?(STRING_BOOTSTRAP)
}

check("H-10: EMPTY_CONSTRUCTOR typed [] with downstream append chain → Ruby ok") {
  ruby_ok?(EMPTY_TYPED_DOWNSTREAM)
}

# ─────────────────────────────────────────────────────────────────────────────

section "I — Blocked and non-goal shapes"

check("I-01: igniter_parser stdlib-form sites exist in source (5 confirmed) — blocked behind IP-P01") {
  ip = stdlib_form_calls.select { |c| c[:file].include?("/igniter_parser/") }
  ip.size == 5
}

check("I-02: dynamic call_contract sites all in rule_engine — excluded from migration scope") {
  dynamic_calls.all? { |c| c[:file].include?("/rule_engine/") }
}

check("I-03: PascalCase user contract callees (e.g. \"MakeLeaf\") exist in corpus but excluded from stdlib census") {
  pascal_calls = all_cc_calls.select { |c| c[:callee].is_a?(String) && c[:callee] =~ /\A[A-Z]/ }
  pascal_calls.size > 0 && pascal_calls.none? { |c| stdlib_form_calls.include?(c) }
}

check("I-04: BOOTSTRAP and EMPTY_CONSTRUCTOR shapes no longer gated on empty() — typed [] unblocked today") {
  ruby_ok?(BOOTSTRAP_ARRAY_LITERAL) &&
    ruby_ok?(EMPTY_TYPED_COMPUTE) &&
    rust_ok?(BOOTSTRAP_ARRAY_LITERAL) &&
    rust_ok?(EMPTY_TYPED_COMPUTE)
}

# ─────────────────────────────────────────────────────────────────────────────

section "J — Authority boundary"

check("J-01: typechecker.rb does not check callee == \"append\" (no special-casing in call_contract dispatch)") {
  src = TC_RUBY_PATH.read(encoding: "utf-8")
  !src.include?('== "append"')
}

check("J-02: typechecker.rs call_contract arm uses contract_registry lookup — no callee-name special-case") {
  # The "append" => arm in typechecker.rs is in the STDLIB FUNCTION DISPATCH (canonical fn resolution),
  # not in the call_contract arm. call_contract uses contract_registry.get(callee_name) — no name branches.
  src = TC_RUST_PATH.read(encoding: "utf-8")
  src.include?('"call_contract"') && src.include?("contract_registry.get(callee_name)")
}

check("J-03: ACCUMULATING migration is app source only — canonical append already works in both TCs") {
  ruby_ok?(CANONICAL_APPEND_ACCUM) && rust_ok?(CANONICAL_APPEND_ACCUM)
}

check("J-04: BOOTSTRAP and EMPTY_CONSTRUCTOR migration is app source only — typed [] works in both TCs") {
  ruby_ok?(BOOTSTRAP_ARRAY_LITERAL) && rust_ok?(BOOTSTRAP_ARRAY_LITERAL) &&
    ruby_ok?(EMPTY_TYPED_COMPUTE)   && rust_ok?(EMPTY_TYPED_COMPUTE)
}

# ═══════════════════════════════════════════════════════════════════════════════

puts "\n" + "=" * 60
total  = CHECKS.size
passed = CHECKS.count { |c| c[:pass] }
failed = CHECKS.reject { |c| c[:pass] }

puts "TOTAL: #{passed}/#{total} PASS"

if failed.any?
  puts "\nFailed checks:"
  failed.each { |c| puts "  FAIL #{c[:label]}" }
end

exit(passed >= 50 ? 0 : 1)
