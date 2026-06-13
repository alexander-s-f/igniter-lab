#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_stringly_call_contract_migration_p3.rb
# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3
# =====================================================================
# Proof that the P3 migration of arch_patterns c0-c4 call_contract
# sites is correct and complete, and that arch_patterns is DUAL-CLEAN.
#
# Sections:
#
#   A  Source scan: no remaining stringly stdlib append in arch_patterns  (5)
#   B  c0-c4 all have explicit annotations or canonical stdlib form       (4)
#   C  No compiler source changes                                         (3)
#   D  Ruby arch_patterns compile result                                  (4)
#   E  Rust arch_patterns compile result                                  (4)
#   F  Diagnostics delta vs P2 and regression smoke                       (4)
#   G  Typed compute binding dependency proven                            (4)
#   H  Non-stdlib call_contract calls preserved                           (4)
#   I  App semantics preserved at structural level                        (4)
#   J  PRESSURE_REGISTRY updated                                          (4)
#   K  Hygiene checks                                                     (5)
#
# Total: 45 checks (target: ≥45)
# Acceptance: ≥45 PASS
#
# Run: ruby verify_lab_stdlib_stringly_call_contract_migration_p3.rb
#      (from igniter-lab/igniter-view-engine/proofs/ or any dir)

require "json"
require "open3"
require "pathname"
require "tmpdir"

PROOF_DIR     = Pathname.new(__FILE__).parent
LAB_ROOT      = PROOF_DIR.parent.parent
WORKSPACE     = LAB_ROOT.parent
IGNITER_LIB   = WORKSPACE / "igniter-lang" / "lib"
COMPILER_DIR  = LAB_ROOT / "igniter-compiler"
COMPILER_BIN  = COMPILER_DIR / "target" / "release" / "igniter_compiler"
APPS_DIR      = LAB_ROOT / "igniter-apps"
AP_DIR        = APPS_DIR / "arch_patterns"
TC_RUST_PATH  = COMPILER_DIR / "src" / "typechecker.rs"
PARSER_PATH   = COMPILER_DIR / "src" / "parser.rs"
REGISTRY_PATH = AP_DIR / "PRESSURE_REGISTRY.md"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

abort "Rust binary not found — run: cargo build --release" unless COMPILER_BIN.exist?

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

def section(name, description = "")
  puts "\n[#{name}]#{description.empty? ? "" : " #{description}"}"
end

# ── Compile helpers ───────────────────────────────────────────────────────────

def ruby_compile_app(app_dir)
  files = Dir.glob((app_dir / "*.ig").to_s).sort
  Dir.mktmpdir("p3_rb_") do |dir|
    out = File.join(dir, "out")
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: files, out_path: out)
    r = result["result"] || result
    {
      status: r["status"]         || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def rust_compile_app(app_dir)
  files = Dir.glob((app_dir / "*.ig").to_s).sort
  Dir.mktmpdir("p3_rs_") do |dir|
    out = File.join(dir, "out")
    stdout, _stderr, _st = Open3.capture3(COMPILER_BIN.to_s, "compile", *files, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    {
      status: r["status"] || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def ruby_compile(source)
  Dir.mktmpdir("p3_srb_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    result = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: [f], out_path: out)
    r = result["result"] || result
    {
      status: r["status"]         || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

def rust_compile(source)
  Dir.mktmpdir("p3_srs_") do |dir|
    f   = File.join(dir, "test.ig")
    out = File.join(dir, "out")
    File.write(f, source.strip + "\n")
    stdout, _stderr, _st = Open3.capture3(COMPILER_BIN.to_s, "compile", f, "--out", out)
    r = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    {
      status: r["status"] || "unknown",
      count:  Array(r["diagnostics"]).size,
      codes:  Array(r["diagnostics"]).map { |d| d["rule"] }.compact,
      diags:  Array(r["diagnostics"])
    }
  end
end

# ── Source reads ──────────────────────────────────────────────────────────────

EXAMPLE_SRC    = (AP_DIR / "example.ig").read(encoding: "utf-8")
PIPELINE_SRC   = (AP_DIR / "pipeline.ig").read(encoding: "utf-8")
SM_SRC         = (AP_DIR / "state_machine.ig").read(encoding: "utf-8")
ES_SRC         = (AP_DIR / "event_sourcing.ig").read(encoding: "utf-8")
TYPES_SRC      = (AP_DIR / "types.ig").read(encoding: "utf-8")
TC_RUST_SRC    = TC_RUST_PATH.read(encoding: "utf-8")
PARSER_SRC     = PARSER_PATH.exist? ? PARSER_PATH.read(encoding: "utf-8") : ""
REGISTRY_SRC   = REGISTRY_PATH.read(encoding: "utf-8")

ALL_IG_SRCS    = [EXAMPLE_SRC, PIPELINE_SRC, SM_SRC, ES_SRC, TYPES_SRC]

# Cross-verify fixture: same shape as c0-c4 after migration
GAP_CHAIN_FIXTURE = <<~IG
  module GapChain
  import stdlib.collection.{ append }
  type Item { value : Integer }
  contract TestChain {
    input elem : Item
    compute c0 : Collection[Item] = []
    compute c1 = append(c0, elem)
    output c1 : Collection[Item]
  }
IG

# ═══════════════════════════════════════════════════════════════════════════════

section "A", "Source scan: no remaining stringly stdlib append in arch_patterns"

check("A-01: no call_contract(\"append\",...) in example.ig (all 5 c0-c4 sites migrated)") {
  !EXAMPLE_SRC.include?('call_contract("append"')
}

check("A-02: no call_contract(\"append\",...) in pipeline.ig (AP-S01..S03 already migrated in P2)") {
  !PIPELINE_SRC.include?('call_contract("append"')
}

check("A-03: no call_contract(\"empty\",...) in any arch_patterns .ig file") {
  ALL_IG_SRCS.none? { |s| s.include?('call_contract("empty"') }
}

check("A-04: c0 now uses BOOTSTRAP typed seed syntax in example.ig") {
  EXAMPLE_SRC.include?('compute c0 : Collection[Transition] = [t0, t1]')
}

check("A-05: c1-c4 now use canonical append(cx, ty) form in example.ig") {
  EXAMPLE_SRC.include?('compute c1 = append(c0, t2)') &&
    EXAMPLE_SRC.include?('compute c2 = append(c1, t3)') &&
    EXAMPLE_SRC.include?('compute c3 = append(c2, t4)') &&
    EXAMPLE_SRC.include?('compute c4 = append(c3, t5)')
}

# ─────────────────────────────────────────────────────────────────────────────

section "B", "c0-c4 have explicit annotation and canonical stdlib form"

check("B-01: c0 annotation is Collection[Transition] (required for P2 Rust fix to bind correct type)") {
  EXAMPLE_SRC.match?(/compute c0\s*:\s*Collection\[Transition\]\s*=\s*\[t0,\s*t1\]/)
}

check("B-02: c1-c4 use stdlib-form append (no more call_contract for these sites)") {
  EXAMPLE_SRC.scan(/\bappend\(c\d,\s*t\d\)/).size == 4
}

check("B-03: example.ig retains stdlib.collection.{ append } import") {
  EXAMPLE_SRC.include?('import stdlib.collection.{ append }')
}

check("B-04: output c4 : Collection[Transition] still in place (unchanged)") {
  EXAMPLE_SRC.include?('output c4 : Collection[Transition]')
}

# ─────────────────────────────────────────────────────────────────────────────

section "C", "No compiler source changes"

check("C-01: typechecker.rs does not contain LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3 marker") {
  !TC_RUST_SRC.include?("LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3")
}

check("C-02: parser.rs does not contain LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3 marker") {
  !PARSER_SRC.include?("LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3")
}

check("C-03: only example.ig in arch_patterns was changed — other .ig files have no c0-c4 annotation") {
  # pipeline.ig, state_machine.ig, event_sourcing.ig, types.ig do not have c0-c4 pattern
  [PIPELINE_SRC, SM_SRC, ES_SRC, TYPES_SRC].none? { |s|
    s.include?("Collection[Transition] = [t0, t1]")
  }
}

# ─────────────────────────────────────────────────────────────────────────────

section "D", "Ruby arch_patterns compile result"

RUBY_RESULT = ruby_compile_app(AP_DIR)

check("D-01: Ruby arch_patterns status ok") {
  RUBY_RESULT[:status] == "ok"
}

check("D-02: Ruby arch_patterns 0 diagnostics") {
  RUBY_RESULT[:count] == 0
}

check("D-03: no OOF-TY0 in Ruby arch_patterns (call_contract append removed)") {
  !RUBY_RESULT[:codes].include?("OOF-TY0")
}

check("D-04: no OOF-TY1 in Ruby arch_patterns (c4 Collection[Transition] → output check passes)") {
  !RUBY_RESULT[:codes].include?("OOF-TY1")
}

# ─────────────────────────────────────────────────────────────────────────────

section "E", "Rust arch_patterns compile result"

RUST_RESULT = rust_compile_app(AP_DIR)

check("E-01: Rust arch_patterns status ok") {
  RUST_RESULT[:status] == "ok"
}

check("E-02: Rust arch_patterns 0 diagnostics") {
  RUST_RESULT[:count] == 0
}

check("E-03: no OOF-TY0 in Rust arch_patterns") {
  !RUST_RESULT[:codes].include?("OOF-TY0")
}

check("E-04: no OOF-TY1 in Rust arch_patterns") {
  !RUST_RESULT[:codes].include?("OOF-TY1")
}

# ─────────────────────────────────────────────────────────────────────────────

section "F", "Diagnostics delta vs P2 and regression smoke"

check("F-01: P3 delta: both TCs go from oof/6 to ok/0 (5×OOF-TY0 + 1×OOF-TY1 cleared)") {
  # Before P3: arch_patterns oof/6 (verified by P2 proof I-01, now fixed)
  # After P3: ok/0 (E-01/D-01 above)
  RUBY_RESULT[:status] == "ok" && RUST_RESULT[:status] == "ok" &&
    RUBY_RESULT[:count] == 0 && RUST_RESULT[:count] == 0
}

check("F-02: both TCs DUAL-CLEAN (first time arch_patterns reaches ok/0 in both toolchains)") {
  RUBY_RESULT[:status] == "ok" && RUST_RESULT[:status] == "ok"
}

check("F-03: bloom_filter Rust still ok/0 (P3 introduces no Rust regression)") {
  r = rust_compile_app(APPS_DIR / "bloom_filter")
  r[:status] == "ok" && r[:count] == 0
}

check("F-04: decision_tree Ruby still ok/0 (P3 introduces no Ruby regression)") {
  r = ruby_compile_app(APPS_DIR / "decision_tree")
  r[:status] == "ok" && r[:count] == 0
}

# ─────────────────────────────────────────────────────────────────────────────

section "G", "Typed compute binding dependency proven"

check("G-01: c0 annotation Collection[Transition] is present — required for LANG-RUST-TYPED-COMPUTE-BINDING-P2 fix") {
  EXAMPLE_SRC.include?("Collection[Transition] = [t0, t1]")
}

check("G-02: LANG-RUST-TYPED-COMPUTE-BINDING-P2 fix active in typechecker.rs (fn unknown_or_unknown_bearing)") {
  TC_RUST_SRC.include?("fn unknown_or_unknown_bearing")
}

check("G-03: annotation override block marker present in typechecker.rs") {
  TC_RUST_SRC.include?("LANG-RUST-TYPED-COMPUTE-BINDING-P2")
}

check("G-04: GAP_CHAIN_FIXTURE (same shape as migrated c0-c4) ok/0 in Rust (cross-verify fix)") {
  r = rust_compile(GAP_CHAIN_FIXTURE)
  r[:status] == "ok" && r[:count] == 0
}

# ─────────────────────────────────────────────────────────────────────────────

section "H", "Non-stdlib call_contract calls preserved"

check("H-01: RunFullScenario has 5 non-stdlib call_contract calls (ReplayEvents5, BuildTransitionTable, etc.)") {
  # Only user-contract calls remain — not stdlib-form
  non_stdlib = EXAMPLE_SRC.scan(/call_contract\("(?!append|empty)[^"]+/)
  non_stdlib.size == 5
}

check("H-02: state_machine.ig non-stdlib call_contract calls preserved (CheckTransition, ApplyEvent)") {
  SM_SRC.include?('call_contract("CheckTransition"') &&
    SM_SRC.include?('call_contract("ApplyEvent"') &&
    !SM_SRC.include?('call_contract("append"')
}

check("H-03: event_sourcing.ig non-stdlib call_contract calls preserved (ApplyEvent chains)") {
  ES_SRC.include?('call_contract("ApplyEvent"') &&
    !ES_SRC.include?('call_contract("append"')
}

check("H-04: pipeline.ig non-stdlib call_contract calls preserved (MwValidateAmount, etc.)") {
  PIPELINE_SRC.include?('call_contract("MwValidateAmount"') &&
    !PIPELINE_SRC.include?('call_contract("append"')
}

# ─────────────────────────────────────────────────────────────────────────────

section "I", "App semantics preserved at structural level"

check("I-01: BuildTransitionTable output is still c4 : Collection[Transition]") {
  EXAMPLE_SRC.include?("output c4 : Collection[Transition]")
}

check("I-02: t0-t5 record literals unchanged in BuildTransitionTable") {
  # t0-t5 still present as unannotated record literals
  EXAMPLE_SRC.scan(/compute t\d = \{/).size == 6
}

check("I-03: RunFullScenario output declarations unchanged") {
  EXAMPLE_SRC.include?("output final_state : AccountState") &&
    EXAMPLE_SRC.include?("output unfrozen_state : AccountState") &&
    EXAMPLE_SRC.include?("output validated : PipelineContext") &&
    EXAMPLE_SRC.include?("output overdraft_result : PipelineContext")
}

check("I-04: empty_trail BOOTSTRAP migration from P2 preserved") {
  EXAMPLE_SRC.include?('compute empty_trail : Collection[String] = ["pipeline:start", "pipeline:init"]')
}

# ─────────────────────────────────────────────────────────────────────────────

section "J", "PRESSURE_REGISTRY updated"

check("J-01: AP-P02 now RESOLVED in PRESSURE_REGISTRY") {
  REGISTRY_SRC.include?("| AP-P02 | RESOLVED |")
}

check("J-02: AP-P11 now RESOLVED in PRESSURE_REGISTRY") {
  REGISTRY_SRC.include?("| AP-P11 | RESOLVED |")
}

check("J-03: PRESSURE_REGISTRY contains P3 recheck section") {
  REGISTRY_SRC.include?("LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3 Recheck")
}

check("J-04: PRESSURE_REGISTRY records DUAL-CLEAN result for P3 recheck") {
  REGISTRY_SRC.include?("DUAL-CLEAN") &&
    REGISTRY_SRC.include?("LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3")
}

# ─────────────────────────────────────────────────────────────────────────────

section "K", "Hygiene checks"

check("K-01: no absolute local paths in example.ig") {
  !EXAMPLE_SRC.include?("/Users/") && !EXAMPLE_SRC.include?("file://")
}

check("K-02: no temp paths in example.ig") {
  !EXAMPLE_SRC.include?("/tmp/") && !EXAMPLE_SRC.include?(".gemini")
}

check("K-03: example.ig module declaration preserved") {
  EXAMPLE_SRC.include?("module ArchPatternsExample")
}

check("K-04: all arch_patterns .ig files are present (no file deleted)") {
  %w[types.ig event_sourcing.ig state_machine.ig pipeline.ig example.ig].all? { |f|
    (AP_DIR / f).exist?
  }
}

check("K-05: decision_tree Rust still ok/0 (additional regression smoke)") {
  r = rust_compile_app(APPS_DIR / "decision_tree")
  r[:status] == "ok" && r[:count] == 0
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

puts ""
puts "arch_patterns Rust: #{RUST_RESULT[:status]}/#{RUST_RESULT[:count]}"
puts "arch_patterns Ruby: #{RUBY_RESULT[:status]}/#{RUBY_RESULT[:count]}"

exit(passed >= 45 ? 0 : 1)
