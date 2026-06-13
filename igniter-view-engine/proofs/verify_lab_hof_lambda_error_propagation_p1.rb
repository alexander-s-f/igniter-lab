#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_hof_lambda_error_propagation_p1.rb
# LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1 — HOF Lambda Error Propagation Divergence
#
# Purpose: Classify and prove the divergence where Ruby HOF lambda body errors
# propagate to the parent type_errors accumulator, while Rust HOF filter/map
# create a local temp_errors buffer and discard it after body typecheck.
#
# Key finding:
#   Ruby  — infer_lambda_body receives same type_errors reference (line 2547/2711)
#   Rust  — filter (line 3054), map (line 3145) create temp_errors (discarded)
#   Rust  — flat_map (line 3211), Expr::Lambda (line 4093) also use temp_errors
#           BUT params are hardcoded to Integer — speculation mode, intentional
#
# Sections:
#   A  HOF landscape — source census of temp_errors positions              (5)
#   B  Ruby propagation model — body errors reach parent type_errors       (6)
#   C  Rust silencing via binary — body errors discarded, OOF-TY1 fires    (7)
#   D  Expr::Lambda arm — intentional speculation mode                     (5)
#   E  flat_map / and_then — arguable temp_errors, defer                   (4)
#   F  Parity policy — divergence quantified, fix identified               (5)
#   G  Closed surfaces — no implementation changes                         (3)
#
# Total: 35 checks
#
# Proof axiom: PASS = check precisely characterises the divergence or
#   confirms a known-good baseline. PASS != "feature works".
#
# Authority: lab-only evidence — no canon claim, no stable-API surface.
# Card: LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1
# Date: 2026-06-13

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

# ── Paths ─────────────────────────────────────────────────────────────────────

PROOFS_DIR   = Pathname.new(__dir__).expand_path
LAB_ROOT     = PROOFS_DIR.parent.parent               # igniter-lab/
LANG_ROOT    = LAB_ROOT.parent / "igniter-lang"
COMPILER_BIN = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"

RE_DIR   = LAB_ROOT / "igniter-apps" / "rule_engine"
RE_FILES = %w[types.ig rules.ig engine.ig example.ig].map { |f| RE_DIR / f }

RUST_TC_PATH = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
RUBY_TC_PATH = LANG_ROOT / "lib" / "igniter_lang" / "typechecker.rb"

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

def type_errors(r)       = Array(r["type_errors"] || [])
def oof_rules(r)         = type_errors(r).map { |e| e["rule"] || "" }
def oof_msgs(r)          = type_errors(r).map { |e| e["message"] || "" }
def has_oof?(r, code)    = oof_rules(r).include?(code)
def no_errors(r)         = type_errors(r).empty?
def msg_contains(r, sub) = oof_msgs(r).any? { |m| m.include?(sub) }
def oof_count(r, code)   = oof_rules(r).count(code)

TMPDIR = Dir.mktmpdir("hof_lambda_error_p1_")
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

def rust_lines
  @rust_lines ||= File.readlines(RUST_TC_PATH.to_s)
end

def ruby_lines
  @ruby_lines ||= File.readlines(RUBY_TC_PATH.to_s)
end

def rust_line(n) = rust_lines[n - 1]&.chomp || ""
def ruby_line(n) = ruby_lines[n - 1]&.chomp || ""

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

MAP_BODY_ERROR_SRC = <<~IG
  module MapBodyErrorTest
  import stdlib.collection.map

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = map(widgets, w -> w.missing_field)
    output result : Collection[Widget]
  }
IG

FILTER_BODY_ERROR_SRC = <<~IG
  module FilterBodyErrorTest
  import stdlib.collection.filter

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = filter(widgets, w -> w.missing_flag)
    output result : Collection[Widget]
  }
IG

FOLD_BODY_ERROR_SRC = <<~IG
  module FoldBodyErrorTest
  import stdlib.collection.fold

  type Item { id : Integer }

  contract TestContract {
    input items : Collection[Item]
    compute total = fold(items, 0, (acc, x) -> x.missing_field)
    output total : Integer
  }
IG

MAP_CLEAN_SRC = <<~IG
  module MapCleanTest
  import stdlib.collection.map

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute ids = map(widgets, w -> w.id)
    output ids : Collection[Integer]
  }
IG

# Pre-run Ruby TC on fixtures once
RUBY_MAP_ERROR_RESULT   = run_ruby_tc(MAP_BODY_ERROR_SRC)
RUBY_FILTER_ERROR_RESULT = run_ruby_tc(FILTER_BODY_ERROR_SRC)
RUBY_FOLD_ERROR_RESULT  = run_ruby_tc(FOLD_BODY_ERROR_SRC)
RUBY_MAP_CLEAN_RESULT   = run_ruby_tc(MAP_CLEAN_SRC)

# Pre-run Rust binary on rule_engine (multi-file)
RUST_RE_RESULT = compile_rust(*RE_FILES, label: "rule_engine")

# Rust binary fixtures
MAP_ERROR_FIXTURE_CONTENT = <<~IG
  module MapBodyErrorRustTest
  import stdlib.collection.map

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = map(widgets, w -> w.missing_field)
    output result : Collection[Widget]
  }
IG

# Unknown predicate — only OOF-P1 silenced in Rust body; no OOF-COL3 (Unknown permissive)
FILTER_ERROR_FIXTURE_CONTENT = <<~IG
  module FilterBodyErrorRustTest
  import stdlib.collection.filter

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = filter(widgets, w -> w.missing_flag)
    output result : Collection[Widget]
  }
IG

# Integer predicate — OOF-COL3 fires (not Bool); tests COL3 propagation outside temp_errors
FILTER_INT_PRED_CONTENT = <<~IG
  module FilterIntPredRustTest
  import stdlib.collection.filter

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = filter(widgets, w -> w.id)
    output result : Collection[Widget]
  }
IG

map_error_fixture      = write_fixture("map_body_error_rust",   MAP_ERROR_FIXTURE_CONTENT)
filter_error_fixture   = write_fixture("filter_body_error_rust", FILTER_ERROR_FIXTURE_CONTENT)
filter_int_pred_fixture = write_fixture("filter_int_pred_rust",  FILTER_INT_PRED_CONTENT)

RUST_MAP_ERROR_RESULT      = compile_rust(map_error_fixture, label: "map_body_error")
RUST_FILTER_ERROR_RESULT   = compile_rust(filter_error_fixture, label: "filter_body_error")
RUST_FILTER_INT_PRED_RESULT = compile_rust(filter_int_pred_fixture, label: "filter_int_pred")

# ── Section A: HOF landscape — source census ──────────────────────────────────

section("A  HOF landscape — source census (post-P2: filter/map use type_errors)")

check("A-01: Rust filter: P2 parity comment at line 3054 (temp_errors REMOVED)") {
  rust_line(3054).include?("LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2") &&
    rust_line(3054).include?("filter")
}

check("A-02: Rust map: P2 parity comment at line 3146 (temp_errors REMOVED)") {
  rust_line(3146).include?("LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2") &&
    rust_line(3146).include?("map")
}

check("A-03: Rust flat_map lambda body still uses temp_errors (typechecker.rs line 3213)") {
  rust_line(3213).include?("temp_errors")
}

check("A-04: Rust Expr::Lambda arm still uses temp_errors (typechecker.rs line 4095)") {
  rust_line(4095).include?("temp_errors")
}

check("A-05: Ruby HOF passes type_errors to infer_lambda_body (typechecker.rb line 2547)") {
  ruby_line(2547).include?("type_errors") && ruby_line(2547).include?("infer_lambda_body")
}

# ── Section B: Ruby propagation model ────────────────────────────────────────

section("B  Ruby propagation model — body errors reach parent type_errors")

check("B-01: Ruby map body OOF-P1 propagates (Widget.missing_field)") {
  has_oof?(RUBY_MAP_ERROR_RESULT, "OOF-P1") &&
    msg_contains(RUBY_MAP_ERROR_RESULT, "missing_field")
}

check("B-02: Ruby filter body OOF-P1 propagates (Widget.missing_flag)") {
  has_oof?(RUBY_FILTER_ERROR_RESULT, "OOF-P1") &&
    msg_contains(RUBY_FILTER_ERROR_RESULT, "missing_flag")
}

check("B-03: Ruby fold body OOF-P1 propagates (Item.missing_field)") {
  has_oof?(RUBY_FOLD_ERROR_RESULT, "OOF-P1") &&
    msg_contains(RUBY_FOLD_ERROR_RESULT, "missing_field")
}

RUBY_FILTER_INT_PRED_SRC = <<~IG
  module FilterIntPredRubyTest
  import stdlib.collection.filter

  type Widget { id : Integer }

  contract TestContract {
    input widgets : Collection[Widget]
    compute result = filter(widgets, w -> w.id)
    output result : Collection[Widget]
  }
IG

RUBY_FILTER_INT_PRED_RESULT = run_ruby_tc(RUBY_FILTER_INT_PRED_SRC)

check("B-04: Ruby filter OOF-COL3 propagates when predicate is Integer (not Bool/Unknown)") {
  has_oof?(RUBY_FILTER_INT_PRED_RESULT, "OOF-COL3")
}

check("B-05: Ruby fold passes type_errors to infer_lambda_body (typechecker.rb line 2711)") {
  ruby_line(2711).include?("type_errors") && ruby_line(2711).include?("infer_lambda_body")
}

check("B-06: Ruby map clean (no missing field) produces no OOF-P1") {
  !has_oof?(RUBY_MAP_CLEAN_RESULT, "OOF-P1")
}

# ── Section C: Rust silencing via binary ──────────────────────────────────────

section("C  Rust binary — post-P2: filter/map body errors propagate (parity achieved)")

rust_map_diags        = Array(RUST_MAP_ERROR_RESULT["diagnostics"] || [])
rust_filter_diags     = Array(RUST_FILTER_ERROR_RESULT["diagnostics"] || [])
rust_filter_int_diags = Array(RUST_FILTER_INT_PRED_RESULT["diagnostics"] || [])
rust_re_diags         = Array(RUST_RE_RESULT["diagnostics"] || [])

check("C-01: Rust map body OOF-P1 NOW FIRES (parity with Ruby — P2 resolved)") {
  rust_map_diags.any? { |d| d["rule"] == "OOF-P1" }
}

check("C-02: Rust map: OOF-P1 fires at body site; OOF-TY1 suppressed (OOF-P1 is primary)") {
  rust_map_diags.any? { |d| d["rule"] == "OOF-P1" } &&
    rust_map_diags.none? { |d| d["rule"] == "OOF-TY1" }
}

check("C-03: Rust filter body OOF-P1 NOW FIRES (parity with Ruby — P2 resolved)") {
  rust_filter_diags.any? { |d| d["rule"] == "OOF-P1" }
}

check("C-04: Rust filter OOF-COL3 DOES propagate when predicate is Integer (outside body scope)") {
  rust_filter_int_diags.any? { |d| d["rule"] == "OOF-COL3" }
}

check("C-05: Rule engine Rust binary: OOF-P1 NOW fires (HOF lambda body d.action propagates)") {
  rust_re_diags.any? { |d| d["rule"] == "OOF-P1" }
}

check("C-06: Rule engine Rust binary: OOF-TY1 still present (output boundary)") {
  rust_re_diags.any? { |d| d["rule"] == "OOF-TY1" }
}

check("C-07: Rust filter params correctly bound to element type (line 3052 — elem_ty, not Integer)") {
  # Params are inserted with elem_ty (derived from Collection[T]) — not hardcoded Integer
  # Line 3052: local_symbols.insert(p.clone(), elem_ty.clone())
  line = rust_line(3052)
  line.include?("elem_ty") && !line.include?("Integer")
}

# ── Section D: Expr::Lambda arm — intentional speculation ─────────────────────

section("D  Expr::Lambda arm — intentional speculation mode")

check("D-01: Rust Expr::Lambda arm declares temp_errors at line 4095 (post-P2 line shift)") {
  rust_line(4095).strip == "let mut temp_errors = Vec::new();"
}

check("D-02: Rust Expr::Lambda params hardcoded to Integer (line 4093 post-P2)") {
  rust_line(4093).include?("Integer")
}

check("D-03: Rust Expr::Lambda body passed &mut temp_errors (not type_errors) (line 4098)") {
  rust_line(4098).include?("temp_errors") && !rust_line(4098).include?("type_errors")
}

check("D-04: Rust Expr::Lambda arm starts at line 4090 (post-P2 line shift)") {
  rust_line(4090).include?("Expr::Lambda")
}

check("D-05: Rust Expr::Lambda silencing classified as INTENTIONAL (hardcoded Integer + temp_errors preserved)") {
  # Intentional: Integer placeholder at 4093, temp_errors at 4095.
  rust_line(4093).include?("Integer") && rust_line(4095).include?("temp_errors")
}

# ── Section E: flat_map / and_then — arguable, defer ─────────────────────────

section("E  flat_map / and_then — arguable temp_errors, defer")

check("E-01: Rust flat_map temp_errors at line 3213 (post-P2 line shift)") {
  rust_line(3213).strip == "let mut temp_errors = Vec::new();"
}

check("E-02: Rust flat_map params hardcoded to Integer (line 3211 post-P2)") {
  rust_line(3211).include?("Integer")
}

check("E-03: flat_map params NOT derived from Collection element type (unlike filter/map)") {
  # flat_map inserts Integer, not elem_ty — confirmed at line 3211
  !rust_line(3211).include?("elem_ty")
}

check("E-04: flat_map silencing is ARGUABLE (Integer placeholder at 3211, temp_errors at 3213)") {
  # Structural assertion: Integer placeholder at 3211, temp_errors at 3213.
  rust_line(3211).include?("Integer") && rust_line(3213).include?("temp_errors")
}

# ── Section F: Parity policy ──────────────────────────────────────────────────

section("F  Parity policy — divergence quantified, fix identified")

check("F-01: filter params use elem_ty (correctly typed — gap is unjustified; line 3052)") {
  rust_line(3052).include?("elem_ty")
}

check("F-02: map params use elem_ty (correctly typed; line 3144 post-P2)") {
  rust_line(3144).include?("elem_ty")
}

check("F-03: Ruby-Rust map PARITY — both produce OOF-P1 for same body error (P2 resolved gap)") {
  has_oof?(RUBY_MAP_ERROR_RESULT, "OOF-P1") &&
    rust_map_diags.any? { |d| d["rule"] == "OOF-P1" }
}

check("F-04: Ruby-Rust filter PARITY — both produce OOF-P1 for same body error (P2 resolved gap)") {
  has_oof?(RUBY_FILTER_ERROR_RESULT, "OOF-P1") &&
    rust_filter_diags.any? { |d| d["rule"] == "OOF-P1" }
}

check("F-05: OOF-COL3 propagates from Rust filter for Integer predicate (no regression from parity fix)") {
  # OOF-COL3 fires outside temp_errors scope — parity fix to body errors won't affect it
  rust_filter_int_diags.any? { |d| d["rule"] == "OOF-COL3" }
}

# ── Section G: Closed surfaces ────────────────────────────────────────────────

section("G  Closed surfaces — P2 implemented; filter/map temp_errors removed")

check("G-01: Rust filter: temp_errors REMOVED by P2 (LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2 comment present)") {
  # P2 replaced temp_errors with direct type_errors in the filter body — confirm the comment
  rust_lines.any? { |l| l.include?("LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2") && l.include?("filter") }
}

check("G-02: Rust map: temp_errors REMOVED by P2 (LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2 comment present)") {
  # P2 replaced temp_errors with direct type_errors in the map body — confirm the comment
  rust_lines.any? { |l| l.include?("LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2") && l.include?("map") }
}

check("G-03: No new OOF codes introduced (OOF-P1/OOF-COL3/OOF-TY1 are sufficient)") {
  # Evidence: all diagnostics in fixtures use only known codes
  all_rust  = rust_map_diags + rust_filter_diags + rust_filter_int_diags + rust_re_diags
  all_ruby  = type_errors(RUBY_MAP_ERROR_RESULT) + type_errors(RUBY_FILTER_ERROR_RESULT) +
              type_errors(RUBY_FILTER_INT_PRED_RESULT)
  known = %w[OOF-P1 OOF-COL3 OOF-COL2 OOF-TY1 OOF-TY0 OOF-COL4]
  (all_rust + all_ruby).map { |d| d["rule"] }.uniq.all? { |r| known.include?(r) || r == "ERROR" }
}

# ── Summary ───────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass + $fail
puts "Result: #{$pass}/#{total} #{$fail == 0 ? "PASS" : "FAIL (#{$fail} failures)"}"
puts
if $fail == 0
  puts "VERDICT: PASS — LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1 PROVED"
  puts "         (updated post-P2: filter/map parity implemented)"
  puts
  puts "  Rust filter: P2 parity comment at line 3054 (temp_errors REMOVED)"
  puts "  Rust map:    P2 parity comment at line 3146 (temp_errors REMOVED)"
  puts "  Rust flat_map temp_errors (arguable): line 3213"
  puts "  Rust Expr::Lambda temp_errors (intentional): line 4095"
  puts "  Ruby type_errors propagation:         lines 2547, 2711"
  puts
  puts "  Ruby map body OOF-P1:     PROPAGATES"
  puts "  Rust map body OOF-P1:     PROPAGATES (P2 parity achieved)"
  puts "  Ruby filter body OOF-P1:  PROPAGATES"
  puts "  Rust filter body OOF-P1:  PROPAGATES (P2 parity achieved)"
  puts
  puts "  Resolved: filter + map (P2)"
  puts "  Deferred: flat_map (Integer placeholder params)"
  puts "  Preserved: Expr::Lambda (intentional speculation placeholder)"
else
  puts "VERDICT: FAIL — review failures above"
end
exit($fail == 0 ? 0 : 1)
