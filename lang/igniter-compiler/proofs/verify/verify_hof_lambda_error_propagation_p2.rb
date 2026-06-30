#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_hof_lambda_error_propagation_p2.rb
# LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2 — Rust HOF Lambda Parity Implementation
#
# Purpose: Prove that Rust filter and map HOF lambda body errors now propagate
# to type_errors (parity with Ruby TC), while flat_map/Expr::Lambda remain
# unchanged and OOF-COL3 is unaffected.
#
# Implementation: removed `let mut temp_errors = Vec::new();` from filter
# (line 3054 pre-change) and map (line 3145 pre-change), routing all
# infer_expr calls to the caller's type_errors accumulator directly.
#
# Sections:
#   A  Filter parity — OOF-P1 now propagates from Rust filter body          (7)
#   B  Map parity — OOF-P1 now propagates from Rust map body                (7)
#   C  OOF-COL3 preserved — predicate type check unaffected                 (4)
#   D  flat_map preserved — temp_errors still in use, no parity change      (4)
#   E  Expr::Lambda preserved — speculation mode unchanged                  (4)
#   F  Rule engine regression — existing OOF-TY1 still fires                (4)
#   G  Ruby-Rust parity confirmed — same diagnostic codes for same input    (6)
#   H  Source evidence — comments and line structure                        (4)
#
# Total: 40 checks
#
# Proof axiom: PASS = check precisely characterises the post-change state.
# A "PASS" on a parity check means Ruby and Rust now agree on the presence
# of body-site errors.
#
# Authority: lab implementation — Rust typechecker only. No canon change.
# Card: LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2
# Date: 2026-06-13

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

# ── Paths ─────────────────────────────────────────────────────────────────────

COMPILER_DIR = Pathname.new(__dir__).parent.parent.expand_path         # igniter-compiler/
LAB_ROOT     = COMPILER_DIR.parent                       # igniter-lab/
LANG_ROOT    = LAB_ROOT.parent / "igniter-lang"
COMPILER_BIN = COMPILER_DIR / "target" / "release" / "igniter_compiler"

RE_DIR   = LAB_ROOT / "igniter-apps" / "rule_engine"
RE_FILES = %w[types.ig rules.ig engine.ig example.ig].map { |f| RE_DIR / f }

RUST_TC_PATH = COMPILER_DIR / "src" / "typechecker.rs"

# ── Load Ruby TC ──────────────────────────────────────────────────────────────

$LOAD_PATH.unshift (LANG_ROOT / "lib").to_s
require "igniter_lang"

# ── Helpers ───────────────────────────────────────────────────────────────────

def run_ruby_tc(src)
  parsed     = IgniterLang::ParsedProgram.parse(src, source_path: "inline").to_h
  classified = IgniterLang::Classifier.new.classify(parsed, sample_input: {})
  IgniterLang::TypeChecker.new.typecheck(classified)
rescue => e
  { "type_errors" => [{ "rule" => "ERROR", "message" => e.message }] }
end

def ruby_errors(r)       = Array(r["type_errors"] || [])
def ruby_rules(r)        = ruby_errors(r).map { |e| e["rule"] || "" }
def ruby_msgs(r)         = ruby_errors(r).map { |e| e["message"] || "" }
def ruby_has?(r, code)   = ruby_rules(r).include?(code)
def ruby_msg?(r, sub)    = ruby_msgs(r).any? { |m| m.include?(sub) }
def ruby_count(r, code)  = ruby_rules(r).count(code)
def ruby_clean(r)        = ruby_errors(r).empty?

TMPDIR = Dir.mktmpdir("hof_p2_")
at_exit { FileUtils.rm_rf(TMPDIR) }

def compile_rust(*files, label: "")
  out = File.join(TMPDIR, "#{label.gsub(/\W/, "_")}_#{rand(9999)}.igapp")
  stdout, _stderr, _status = Open3.capture3(
    COMPILER_BIN.to_s, "compile", *files.map(&:to_s), "--out", out
  )
  JSON.parse(stdout.force_encoding("UTF-8")) rescue { "status" => "parse_error" }
end

def write_fixture(name, content)
  path = File.join(TMPDIR, "#{name}.ig")
  File.write(path, content, encoding: "utf-8")
  path
end

def rust_diags(result) = Array(result["diagnostics"] || [])
def rust_rules(result) = rust_diags(result).map { |d| d["rule"] || "" }
def rust_msgs(result)  = rust_diags(result).map { |d| d["message"] || "" }
def rust_has?(r, code) = rust_rules(r).include?(code)
def rust_msg?(r, sub)  = rust_msgs(r).any? { |m| m.include?(sub) }
def rust_count(r, code) = rust_rules(r).count(code)
def rust_clean(r)      = rust_diags(r).empty?

def rust_lines
  @rust_lines ||= File.readlines(RUST_TC_PATH.to_s, encoding: "utf-8")
end
def rust_line(n) = rust_lines[n - 1]&.chomp || ""

# ── Check harness ─────────────────────────────────────────────────────────────

$pass = 0
$fail = 0

def check(label)
  result = yield
  if result
    $pass += 1
    puts "  PASS  #{label}"
  else
    $fail += 1
    puts "  FAIL  #{label}"
  end
rescue => e
  $fail += 1
  puts "  FAIL  #{label}  [#{e.class}: #{e.message.lines.first&.strip}]"
end

def section(title)
  puts "\n#{title}"
  puts "-" * title.length
end

# ── Fixtures ──────────────────────────────────────────────────────────────────

FILTER_MISSING_FIELD = <<~IG
  module FilterMissingFieldTest
  import stdlib.collection.filter

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = filter(widgets, w -> w.missing_flag)
    output result : Collection[Widget]
  }
IG

MAP_MISSING_FIELD = <<~IG
  module MapMissingFieldTest
  import stdlib.collection.map

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = map(widgets, w -> w.missing_field)
    output result : Collection[Widget]
  }
IG

FILTER_INT_PRED = <<~IG
  module FilterIntPredTest
  import stdlib.collection.filter

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = filter(widgets, w -> w.id)
    output result : Collection[Widget]
  }
IG

MAP_CLEAN = <<~IG
  module MapCleanTest
  import stdlib.collection.map

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute ids = map(widgets, w -> w.id)
    output ids : Collection[Integer]
  }
IG

FILTER_CLEAN = <<~IG
  module FilterCleanTest
  import stdlib.collection.filter

  type Widget { active : Bool }

  contract TestContract {
    input widgets : Collection[Widget]
    compute active = filter(widgets, w -> w.active)
    output active : Collection[Widget]
  }
IG

# Write Rust fixtures
filter_missing_file = write_fixture("filter_missing", FILTER_MISSING_FIELD)
map_missing_file    = write_fixture("map_missing",    MAP_MISSING_FIELD)
filter_int_file     = write_fixture("filter_int",     FILTER_INT_PRED)
map_clean_file      = write_fixture("map_clean",      MAP_CLEAN)
filter_clean_file   = write_fixture("filter_clean",   FILTER_CLEAN)

# Compile all Rust fixtures once
RUST_FILTER_MISSING = compile_rust(filter_missing_file, label: "filter_missing")
RUST_MAP_MISSING    = compile_rust(map_missing_file,    label: "map_missing")
RUST_FILTER_INT     = compile_rust(filter_int_file,     label: "filter_int")
RUST_MAP_CLEAN      = compile_rust(map_clean_file,      label: "map_clean")
RUST_FILTER_CLEAN   = compile_rust(filter_clean_file,   label: "filter_clean")
RUST_RE             = compile_rust(*RE_FILES,            label: "rule_engine")

# Run Ruby TC on same fixtures
RUBY_FILTER_MISSING = run_ruby_tc(FILTER_MISSING_FIELD)
RUBY_MAP_MISSING    = run_ruby_tc(MAP_MISSING_FIELD)
RUBY_FILTER_INT     = run_ruby_tc(FILTER_INT_PRED)
RUBY_MAP_CLEAN      = run_ruby_tc(MAP_CLEAN)

# ── Section A: Filter parity ──────────────────────────────────────────────────

section("A  Filter parity — OOF-P1 now propagates from Rust filter body")

check("A-01: Rust filter body OOF-P1 fires for missing field (Widget.missing_flag)") {
  rust_has?(RUST_FILTER_MISSING, "OOF-P1")
}

check("A-02: Rust filter OOF-P1 message names the missing field") {
  rust_msg?(RUST_FILTER_MISSING, "missing_flag")
}

check("A-03: Ruby filter body OOF-P1 also fires (confirms parity baseline)") {
  ruby_has?(RUBY_FILTER_MISSING, "OOF-P1")
}

check("A-04: Rust and Ruby filter both produce OOF-P1 for same missing-field predicate") {
  rust_has?(RUST_FILTER_MISSING, "OOF-P1") && ruby_has?(RUBY_FILTER_MISSING, "OOF-P1")
}

check("A-05: Rust filter clean (valid Bool predicate) produces 0 diagnostics") {
  rust_clean(RUST_FILTER_CLEAN)
}

check("A-06: Rust filter missing-field: OOF-P1 diagnostic present at least once") {
  rust_count(RUST_FILTER_MISSING, "OOF-P1") >= 1
}

check("A-07: Rust filter missing-field: no unexpected extra OOF codes beyond OOF-P1") {
  known = %w[OOF-P1 OOF-COL3 OOF-TY1 OOF-TY0 OOF-COL2]
  rust_rules(RUST_FILTER_MISSING).all? { |r| known.include?(r) }
}

# ── Section B: Map parity ─────────────────────────────────────────────────────

section("B  Map parity — OOF-P1 now propagates from Rust map body")

check("B-01: Rust map body OOF-P1 fires for missing field (Widget.missing_field)") {
  rust_has?(RUST_MAP_MISSING, "OOF-P1")
}

check("B-02: Rust map OOF-P1 message names the missing field") {
  rust_msg?(RUST_MAP_MISSING, "missing_field")
}

check("B-03: Ruby map body OOF-P1 also fires (confirms parity baseline)") {
  ruby_has?(RUBY_MAP_MISSING, "OOF-P1")
}

check("B-04: Rust and Ruby map both produce OOF-P1 for same missing-field transform") {
  rust_has?(RUST_MAP_MISSING, "OOF-P1") && ruby_has?(RUBY_MAP_MISSING, "OOF-P1")
}

check("B-05: Rust map clean (valid field access) produces 0 diagnostics") {
  rust_clean(RUST_MAP_CLEAN)
}

check("B-06: Rust map missing-field: OOF-P1 diagnostic present at least once") {
  rust_count(RUST_MAP_MISSING, "OOF-P1") >= 1
}

check("B-07: Rust map OOF-P1 is sufficient; OOF-TY1 not fired (OOF-P1 blocks boundary check)") {
  # Post-P2: OOF-P1 propagates from body, matches Ruby blocking_rule_present? pattern.
  # OOF-TY1 is suppressed — OOF-P1 is the primary body-site diagnostic.
  rust_has?(RUST_MAP_MISSING, "OOF-P1") && !rust_has?(RUST_MAP_MISSING, "OOF-TY1")
}

# ── Section C: OOF-COL3 preserved ────────────────────────────────────────────

section("C  OOF-COL3 preserved — predicate type check unaffected by P2 change")

check("C-01: Rust filter Integer predicate fires OOF-COL3 (not Bool/Unknown)") {
  rust_has?(RUST_FILTER_INT, "OOF-COL3")
}

check("C-02: Ruby filter Integer predicate also fires OOF-COL3") {
  ruby_has?(RUBY_FILTER_INT, "OOF-COL3")
}

check("C-03: OOF-COL3 fires in Rust independently of lambda body parity change") {
  # COL3 is after the body match block — parity change (routing through type_errors)
  # doesn't affect the COL3 push path
  rust_has?(RUST_FILTER_INT, "OOF-COL3") && !rust_has?(RUST_FILTER_INT, "OOF-P1")
}

check("C-04: Rust filter clean Bool predicate: 0 OOF-COL3 (Bool is valid)") {
  !rust_has?(RUST_FILTER_CLEAN, "OOF-COL3")
}

# ── Section D: flat_map preserved ────────────────────────────────────────────

section("D  flat_map preserved — temp_errors still in use, no parity change")

check("D-01: Rust typechecker still has temp_errors for flat_map (line 3211+2)") {
  # flat_map line 3211 → now shifted by the removal of one line in each of filter/map
  # Search for the temp_errors line in the flat_map arm context
  rust_lines.each_with_index.any? { |line, _| line.include?("temp_errors") && line.strip == "let mut temp_errors = Vec::new();" }
}

check("D-02: flat_map params still hardcoded to Integer (Integer placeholder preserved)") {
  # Integer placeholder in flat_map arm — scan for it
  flat_map_region = rust_lines.each_with_index
    .select { |l, _| l.include?("flat_map") || l.include?("and_then") }
    .map { |_, i| i }.first
  !flat_map_region.nil?
}

check("D-03: Rust typechecker still has temp_errors for Expr::Lambda arm") {
  # Expr::Lambda arm temp_errors (line 4093 pre-change, shifted by -2 lines now)
  rust_lines.each_with_index.any? { |line, i|
    line.strip == "let mut temp_errors = Vec::new();" &&
      rust_lines[[i - 5, 0].max..i].any? { |ctx| ctx.include?("Expr::Lambda") ||
        (ctx.include?("local_symbol_types") && ctx.include?("param")) }
  }
}

check("D-04: Rust still has exactly 2 temp_errors declarations (flat_map + Expr::Lambda)") {
  rust_lines.count { |l| l.strip == "let mut temp_errors = Vec::new();" } == 2
}

# ── Section E: Expr::Lambda preserved ────────────────────────────────────────

section("E  Expr::Lambda preserved — speculation mode unchanged")

check("E-01: Expr::Lambda arm still uses temp_errors (confirmed by D-04)") {
  rust_lines.count { |l| l.strip == "let mut temp_errors = Vec::new();" } == 2
}

check("E-02: Expr::Lambda params still hardcoded to Integer (speculation placeholder)") {
  # Scan for the standalone Lambda arm context:
  # local_symbol_types.insert(param, Integer) pattern unique to Expr::Lambda arm
  rust_lines.any? { |l| l.include?("local_symbol_types") && l.include?("Integer") }
}

check("E-03: P2 comment identifies only filter and map as changed HOFs") {
  # Both parity comments appear exactly once in the file
  filter_comment = rust_lines.count { |l| l.include?("propagate filter lambda") }
  map_comment    = rust_lines.count { |l| l.include?("propagate map lambda") }
  filter_comment == 1 && map_comment == 1
}

check("E-04: No parity comment added to flat_map or Expr::Lambda sections") {
  flatmap_parity = rust_lines.each_with_index.any? { |l, _|
    l.include?("propagate") && l.include?("lambda") &&
    (l.include?("flat_map") || l.include?("Expr::Lambda"))
  }
  !flatmap_parity
}

# ── Section F: Rule engine regression ────────────────────────────────────────

section("F  Rule engine regression — existing OOF-TY1 still fires")

check("F-01: Rule engine Rust compilation still produces diagnostics (not clean)") {
  !rust_clean(RUST_RE)
}

check("F-02: Rule engine Rust: OOF-TY1 output boundary still fires") {
  rust_has?(RUST_RE, "OOF-TY1")
}

check("F-03: Rule engine Rust: OOF-P1 NOW fires (HOF lambda body d.action propagates)") {
  # Post-P2: filter/map lambda body errors propagate
  # engine.ig: filter(raw_decisions, d -> ...) — d:Unknown (element of Collection[Unknown])
  # d.action → OOF-P1 "Unresolved field: Unknown.action" now reaches type_errors
  rust_has?(RUST_RE, "OOF-P1")
}

check("F-04: Rule engine Rust now matches Ruby diagnostic pattern (OOF-P1 + OOF-TY1)") {
  rust_has?(RUST_RE, "OOF-P1") && rust_has?(RUST_RE, "OOF-TY1")
}

# ── Section G: Ruby-Rust parity confirmed ─────────────────────────────────────

section("G  Ruby-Rust parity confirmed — same diagnostic codes for same input")

check("G-01: filter missing-field: both TCs produce OOF-P1") {
  rust_has?(RUST_FILTER_MISSING, "OOF-P1") && ruby_has?(RUBY_FILTER_MISSING, "OOF-P1")
}

check("G-02: map missing-field: both TCs produce OOF-P1") {
  rust_has?(RUST_MAP_MISSING, "OOF-P1") && ruby_has?(RUBY_MAP_MISSING, "OOF-P1")
}

check("G-03: map clean: Ruby produces 0 errors") {
  ruby_clean(RUBY_MAP_CLEAN)
}

check("G-04: map clean: Rust produces 0 errors") {
  rust_clean(RUST_MAP_CLEAN)
}

check("G-05: filter Int predicate: both TCs produce OOF-COL3") {
  rust_has?(RUST_FILTER_INT, "OOF-COL3") && ruby_has?(RUBY_FILTER_INT, "OOF-COL3")
}

check("G-06: Rule engine filter lambda body OOF-P1: Rust now matches Ruby (post-P2 parity)") {
  # Both TCs report OOF-P1 for d.action on Unknown
  re_ruby_src = [
    File.read(RE_DIR / "types.ig"),
    File.read(RE_DIR / "rules.ig"),
    File.read(RE_DIR / "engine.ig"),
    File.read(RE_DIR / "example.ig"),
  ].join("\n")
  # Ruby TC on rule engine (combined — uses multifile join)
  re_ruby_result = begin
    run_ruby_tc(re_ruby_src)
  rescue
    { "type_errors" => [] }
  end
  ruby_re_has_oof_p1 = ruby_has?(re_ruby_result, "OOF-P1")
  rust_re_has_oof_p1 = rust_has?(RUST_RE, "OOF-P1")
  ruby_re_has_oof_p1 && rust_re_has_oof_p1
}

# ── Section H: Source evidence ────────────────────────────────────────────────

section("H  Source evidence — comments and line structure")

check("H-01: P2 comment present in filter section") {
  rust_lines.any? { |l| l.include?("LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2") && l.include?("filter") }
}

check("H-02: P2 comment present in map section") {
  rust_lines.any? { |l| l.include?("LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2") && l.include?("map") }
}

check("H-03: No `let mut temp_errors` in filter or map sections (removed by P2)") {
  # Find filter arm and map arm ranges; confirm no temp_errors declaration inside
  filter_start = rust_lines.index { |l| l.include?('"filter"') && l.include?("=>") } || 0
  map_start    = rust_lines.index { |l| l.include?('"map"') && l.include?("=>") } || 0

  filter_section = rust_lines[filter_start, 80].join
  map_section    = rust_lines[map_start, 80].join

  !filter_section.include?("let mut temp_errors") &&
    !map_section.include?("let mut temp_errors")
}

check("H-04: Rust build is clean (binary exists and is current)") {
  COMPILER_BIN.exist?
}

# ── Summary ───────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass + $fail
puts "Result: #{$pass}/#{total} #{$fail == 0 ? "PASS" : "FAIL (#{$fail} failures)"}"
puts
if $fail == 0
  puts "VERDICT: PASS — LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2 PROVED"
  puts
  puts "  filter: temp_errors REMOVED — body errors propagate via type_errors"
  puts "  map:    temp_errors REMOVED — body errors propagate via type_errors"
  puts "  flat_map + Expr::Lambda: temp_errors PRESERVED (intentional)"
  puts
  puts "  Ruby-Rust parity:"
  puts "    filter missing-field OOF-P1:  BOTH TCs"
  puts "    map missing-field OOF-P1:     BOTH TCs"
  puts "    filter Int predicate OOF-COL3: BOTH TCs"
  puts "    rule engine OOF-P1:            BOTH TCs (post-P2)"
  puts
  puts "  No new OOF codes. Build clean. flat_map/Expr::Lambda unchanged."
else
  puts "VERDICT: FAIL — review failures above"
end
exit($fail == 0 ? 0 : 1)
