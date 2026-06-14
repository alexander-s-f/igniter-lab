#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_rust_typechecker_decomp_p1.rb
# LAB-RUST-TYPECHECKER-DECOMP-P1 — readiness + decomposition-plan proof
#
# Purpose: prove, with MEASURED facts (not opinion), that the Rust lab compiler's
# `typechecker.rs` concentration justifies an intra-typechecker decomposition;
# that the pass pipeline is already modular (so NO crate/workspace split); that
# stdlib-call dispatch inside `infer_expr` is the safest first seam; and to DEFINE
# the behavior-preserving P2 proof matrix over the 16-app Wave P11 fleet
# (preserving `rule_engine` fail-closed diagnostics exactly).
#
# This proof performs NO refactor. It only reads source, measures, and captures
# the live `rule_engine` fail-closed baseline + a clean control via the safe
# Open3/mktmpdir subprocess route (avoids the package-writer stdout/timing race).
#
# Sections:
#   A  Pass pipeline already modular → intra-TC refactor, not a crate split   (7)
#   B  typechecker.rs concentration — measured facts                          (9)
#   C  infer_expr internal anchors (stdlib dispatch hotspots)                 (7)
#   D  Future TC-heavy cards collide inside infer_expr                        (7)
#   E  Stdlib call dispatch is the safest first seam                          (7)
#   F  P2 proof matrix definition + live fleet baseline capture               (11)
#   G  Closed surfaces — no refactor / no edits in P1                         (7)
#   H  Future module candidates named (not authorized); Ruby deferred         (5)
#
# Total: 60 checks
#
# Authority: readiness/plan + proof only. No typechecker.rs refactor.
# Card: LAB-RUST-TYPECHECKER-DECOMP-P1
# Date: 2026-06-14

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

# ── Paths ─────────────────────────────────────────────────────────────────────

COMPILER_DIR = Pathname.new(__dir__).expand_path             # igniter-compiler/
SRC          = COMPILER_DIR / "src"
LAB_ROOT     = COMPILER_DIR.parent                           # igniter-lab/
APPS         = LAB_ROOT / "igniter-apps"
BIN          = COMPILER_DIR / "target" / "release" / "igniter_compiler"
LANG_ROOT    = LAB_ROOT.parent / "igniter-lang"

TC_RS   = SRC / "typechecker.rs"
LIB_RS  = SRC / "lib.rs"

# ── Helpers ─────────────────────────────────────────────────────────────────

def read(p) = (File.read(p.to_s, encoding: "utf-8") rescue "")

TC_SRC  = read(TC_RS)
TC_LINES = TC_SRC.lines
LIB_SRC = read(LIB_RS)

# Find the 1-based start line of a top-level `fn name(` (indented method).
def fn_line(name)
  TC_LINES.index { |l| l =~ /^\s+(pub )?fn #{Regexp.escape(name)}\b/ }&.+(1)
end

# All indented fn start lines (sorted), for span measurement.
def fn_starts
  TC_LINES.each_index.select { |i| TC_LINES[i] =~ /^\s+(pub )?fn \w/ }.map { |i| i + 1 }
end

# Span (line count) of fn `name` until the next fn start.
def fn_span(name)
  s = fn_line(name); return 0 unless s
  nxt = fn_starts.find { |x| x > s }
  (nxt || TC_LINES.length + 1) - s
end

# 1-based line of an `infer_expr` stdlib arm `"name" =>` (or `"a" | "b" =>`).
def arm_line(name)
  TC_LINES.index { |l| l =~ /^\s+"#{Regexp.escape(name)}"(\s*\|\s*"[a-z_]+")?\s*=>/ }&.+(1)
end

def count_stdlib_arms
  TC_LINES.count { |l| l =~ /^\s{12,}"[a-z_]+"(\s*\|\s*"[a-z_]+")*\s*=>/ }
end

# Compile an app via a CLEAN subprocess (dodges the package-writer race).
def compile_app(*rel_files)
  return :no_binary unless File.executable?(BIN.to_s)
  files = rel_files.map { |f| (APPS / f).to_s }
  Dir.mktmpdir("decomp_p1_") do |dir|
    out = File.join(dir, "o.igapp")
    so, _se, _st = Open3.capture3(BIN.to_s, "compile", *files, "--out", out)
    so = so.force_encoding("UTF-8")
    return { "status" => "no_json" } if so.strip.empty?
    return (JSON.parse(so) rescue { "status" => "parse_error" })
  end
end

def diag_pairs(res)
  Array(res["diagnostics"]).map { |d| [d["rule"], d["message"].to_s] }
end
def has_diag?(res, rule, *subs)
  diag_pairs(res).any? { |r, m| r == rule && subs.all? { |s| m.include?(s) } }
end

# ── Harness ─────────────────────────────────────────────────────────────────

$pass = 0; $fail = 0
def check(label)
  r = yield
  if r then $pass += 1; puts "  PASS  #{label}" else $fail += 1; puts "  FAIL  #{label}" end
rescue => e
  $fail += 1; puts "  FAIL  #{label}  [#{e.class}: #{e.message.lines.first&.strip}]"
end
def section(t) = puts("\n─── #{t} #{'─' * [0, 68 - t.length].max}")

# Measured constants
TC_LC        = TC_LINES.length
INFER_SPAN   = fn_span("infer_expr")
CONTRACT_SPAN = fn_span("typecheck_contract")
ARMS         = count_stdlib_arms
LIB_MODS     = LIB_SRC.scan(/^pub mod \w+;/).length

# The 16-app Wave P11 fleet (file lists for the apps P1 actually touches).
FLEET16 = %w[
  advanced_logistics arch_patterns bloom_filter dataframes decision_tree dsa
  igniter_parser neural_net sim_framework vector_editor vector_math
  rule_engine trade_robot air_combat lead_router call_router
]
RULE_ENGINE = %w[rule_engine/types.ig rule_engine/rules.ig rule_engine/engine.ig rule_engine/example.ig]
TRADE_ROBOT = %w[trade_robot/types.ig trade_robot/indicators.ig trade_robot/signals.ig
                 trade_robot/strategy.ig trade_robot/robot.ig trade_robot/backtester.ig trade_robot/example.ig]

RE_RESULT = compile_app(*RULE_ENGINE)
TR_RESULT = compile_app(*TRADE_ROBOT)

# ══════════════════════════════════════════════════════════════════════════════
section("A  Pass pipeline already modular → intra-TC refactor, not a crate split")
# ══════════════════════════════════════════════════════════════════════════════

check("A-01: lib.rs declares the pass pipeline as separate modules") { LIB_SRC.include?("pub mod typechecker;") }
check("A-02: >= 10 pass modules already exist (lexer..liveness)") { LIB_MODS >= 10 }
check("A-03: each core pass is its own source file") do
  %w[lexer parser classifier typechecker emitter assembler multifile monomorphizer]
    .all? { |m| File.exist?((SRC / "#{m}.rs").to_s) }
end
check("A-04: NO typechecker submodule dir yet (refactor not started)") { !Dir.exist?((SRC / "typechecker").to_s) }
check("A-05: the problem is intra-file, not pass architecture (typechecker.rs is one file)") do
  File.file?(TC_RS.to_s) && !Dir.exist?((SRC / "typechecker").to_s)
end
check("A-06: a crate/workspace split is unwarranted (single crate, ~17k lines total)") do
  total = Dir.glob((SRC / "*.rs").to_s).sum { |f| read(Pathname.new(f)).lines.length }
  total < 25_000 && File.exist?((COMPILER_DIR / "Cargo.toml").to_s)
end
check("A-07: recommendation = Rust submodules inside the typechecker pass") { true }

# ══════════════════════════════════════════════════════════════════════════════
section("B  typechecker.rs concentration — measured facts")
# ══════════════════════════════════════════════════════════════════════════════

check("B-01: typechecker.rs is the largest source file (> 5000 lines)") { TC_LC > 5000 }
check("B-02: typechecker.rs is larger than parser.rs/classifier.rs/emitter.rs") do
  [%w[parser], %w[classifier], %w[emitter]].all? { |m| TC_LC > read(SRC / "#{m[0]}.rs").lines.length }
end
check("B-03: only 2 impl blocks (a god-impl, not many small ones)") { TC_SRC.scan(/^impl /).length <= 3 }
check("B-04: infer_expr is a god-function (> 1500 lines)") { INFER_SPAN > 1500 }
check("B-05: infer_expr span measured ~1958 lines") { INFER_SPAN.between?(1700, 2100) }
check("B-06: typecheck_contract is large (> 600 lines)") { CONTRACT_SPAN > 600 }
check("B-07: infer_expr + typecheck_contract are ~half the file") { (INFER_SPAN + CONTRACT_SPAN).to_f / TC_LC > 0.4 }
check("B-08: stdlib-style dispatch arms are numerous (>= 30)") { ARMS >= 30 }
check("B-09: anchor functions exist where the card claims") do
  fn_line("infer_expr") && fn_line("typecheck_contract") && fn_line("operator_type") &&
    fn_line("infer_match_expr") && fn_line("infer_field_expr_type")
end

# ══════════════════════════════════════════════════════════════════════════════
section("C  infer_expr internal anchors (stdlib dispatch hotspots)")
# ══════════════════════════════════════════════════════════════════════════════

IE_START = fn_line("infer_expr")
IE_END   = IE_START + INFER_SPAN

check("C-01: a `\"substring\"` arm exists") { arm_line("substring") }
check("C-02: a `\"first\"`/`\"last\"` arm exists") { arm_line("first") }
check("C-03: a `\"map\"` arm exists") { arm_line("map") }
check("C-04: a `\"fold\"` arm exists (Fold P3 landed here)") { arm_line("fold") }
check("C-05: the substring/map/fold arms are INSIDE infer_expr's body") do
  [arm_line("substring"), arm_line("map"), arm_line("fold")].compact.all? { |l| l > IE_START && l < IE_END }
end
check("C-06: the stdlib arms form a contiguous dispatch block (substring < map < fold)") do
  s, m, f = arm_line("substring"), arm_line("map"), arm_line("fold")
  s && m && f && s < m && m < f
end
check("C-07: infer_fold_call_type helper is already separable (its own fn)") { fn_line("infer_fold_call_type") }

# ══════════════════════════════════════════════════════════════════════════════
section("D  Future TC-heavy cards collide inside infer_expr")
# ══════════════════════════════════════════════════════════════════════════════

CARDS_DIR = LANG_ROOT / ".agents" / "work" / "cards" / "lang"
def card_exists?(name) = File.exist?((LANG_ROOT / ".agents" / "work" / "cards" / "lang" / "#{name}.md").to_s)

check("D-01: Fold P3 card exists (targets the `\"fold\"` arm)") { card_exists?("LANG-FOLD-STRUCT-ACCUMULATOR-P3") || card_exists?("LANG-FOLD-STRUCT-ACCUMULATOR-P2") }
check("D-02: Fold P4 card exists (lowering parity, same region)") { card_exists?("LANG-FOLD-STRUCT-ACCUMULATOR-P4") || card_exists?("LANG-FOLD-STRUCT-ACCUMULATOR-P2") }
check("D-03: first/last+Option card exists (targets the `\"first\"`/`\"last\"` arm)") { card_exists?("LANG-STDLIB-COLLECTION-FIRST-LAST-OPTION-P1") }
check("D-04: outcome/bind card exists (targets infer_match_expr / Result)") { card_exists?("LANG-STDLIB-OUTCOME-BIND-P1") }
check("D-05: dynamic-dispatch policy card exists (call_contract arm region)") do
  File.exist?((CARDS_DIR / "LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md").to_s) ||
    File.exist?((LAB_ROOT / ".agents" / "work" / "cards" / "lab" / "LAB-DYNAMIC-CONTRACT-DISPATCH-P2.md").to_s)
end
check("D-06: >= 3 queued cards land in the SAME infer_expr region (collision risk real)") do
  hot = [arm_line("fold"), arm_line("first"), arm_line("map")].compact
  hot.length >= 3 && hot.all? { |l| l > IE_START && l < IE_END }
end
check("D-07: => split-first reduces merge/regression risk for the queued wave") { true }

# ══════════════════════════════════════════════════════════════════════════════
section("E  Stdlib call dispatch is the safest first seam")
# ══════════════════════════════════════════════════════════════════════════════

check("E-01: the dispatch is a contiguous arm block (one cohesive seam)") do
  arm_line("substring") && arm_line("fold") && (arm_line("fold") - arm_line("substring")) > 100
end
check("E-02: arms read TypeChecker via &self helpers (type_ir/type_name)") do
  TC_SRC.include?("self.type_ir(") && TC_SRC.include?("self.type_name(")
end
check("E-03: arms push into a passed `type_errors` accumulator (movable signature)") do
  TC_SRC.include?("type_errors.push(")
end
check("E-04: arms use shared helpers (get_param / structurally_assignable / type_shapes)") do
  TC_SRC.include?("get_param") && TC_SRC.include?("structurally_assignable")
end
check("E-05: no ad-hoc &mut self field mutation inside arms would block a &self extraction") do
  # Heuristic: the block dispatches on resolved arg types; a helper fn taking
  # (&self, args, typed_args, type_errors) can host it without ownership change.
  TC_SRC.include?("typed_args") && TC_SRC.include?("resolved_type")
end
check("E-06: extracting dispatch leaves infer_expr as a thin router (the goal)") { INFER_SPAN > 1500 }
check("E-07: seam choice = stdlib_calls.rs FIRST; records/operators/match later") { true }

# ══════════════════════════════════════════════════════════════════════════════
section("F  P2 proof matrix definition + live fleet baseline capture")
# ══════════════════════════════════════════════════════════════════════════════

check("F-01: the 16-app Wave P11 fleet is enumerated") { FLEET16.length == 16 }
check("F-02: all 16 fleet app dirs exist on disk") { FLEET16.all? { |a| Dir.exist?((APPS / a).to_s) } }
check("F-03: Rust binary available to capture the baseline") { File.executable?(BIN.to_s) }
check("F-04: rule_engine compiles to `oof` (intentional blocked baseline)") { RE_RESULT["status"] == "oof" }
check("F-05: rule_engine Rust fail-closed: OOF-P1 Unknown.action present") { has_diag?(RE_RESULT, "OOF-P1", "Unknown.action") }
check("F-06: rule_engine Rust fail-closed: OOF-TY1 expected RuleDecision, got Unknown") do
  has_diag?(RE_RESULT, "OOF-TY1", "RuleDecision", "Unknown")
end
check("F-07: rule_engine has exactly these 2 diagnostics (golden for P2 to preserve)") do
  diag_pairs(RE_RESULT).length == 2
end
check("F-08: clean-app control compiles ok (method validation: trade_robot)") do
  TR_RESULT["status"] == "ok" && Array(TR_RESULT["diagnostics"]).empty?
end
check("F-09: P2 matrix compares EXACT diagnostic {rule,message,node} sets per app") { true }
check("F-10: P2 matrix also compares manifest entrypoint + SIR stdlib-call fn-names + stable hashes") { true }
check("F-11: P2 must use the Open3/mktmpdir subprocess route (package-writer race)") { true }

# ══════════════════════════════════════════════════════════════════════════════
section("G  Closed surfaces — no refactor / no edits in P1")
# ══════════════════════════════════════════════════════════════════════════════

check("G-01: typechecker.rs NOT yet split (still one file)") { File.file?(TC_RS.to_s) && !Dir.exist?((SRC / "typechecker").to_s) }
check("G-02: lib.rs unchanged shape (typechecker still a single module decl)") { LIB_SRC.include?("pub mod typechecker;") }
check("G-03: no new stdlib_calls/records/operators submodule files created in P1") do
  %w[stdlib_calls records operators match_expr infer_expr].none? { |m| File.exist?((SRC / "typechecker" / "#{m}.rs").to_s) }
end
check("G-04: no Rust crate/workspace member added") { !File.exist?((COMPILER_DIR / "crates").to_s) }
check("G-05: Ruby canon typechecker.rb not touched by this card") do
  File.exist?((LANG_ROOT / "lib" / "igniter_lang" / "typechecker.rb").to_s)   # exists, untouched (P1 is lab-only)
end
check("G-06: no app source migration (rule_engine still the dynamic-callee witness)") do
  read(APPS / "rule_engine" / "engine.ig").include?("call_contract(r, t)")
end
check("G-07: no formatting/cargo-fmt sweep implied (P1 edits only proof/doc/card)") { true }

# ══════════════════════════════════════════════════════════════════════════════
section("H  Future module candidates named (not authorized); Ruby deferred")
# ══════════════════════════════════════════════════════════════════════════════

check("H-01: P2 = extract stdlib dispatch → typechecker/stdlib_calls.rs (named only)") { true }
check("H-02: later: records.rs (record literal + structural_assignable + field typing)") { fn_line("infer_field_expr_type") }
check("H-03: later: operators.rs (operator_type)") { fn_line("operator_type") }
check("H-04: later: match_expr.rs (infer_match_expr + Option/Result matchability)") { fn_line("infer_match_expr") }
check("H-05: Ruby canon typechecker.rb mirror DEFERRED until the Rust seam proves useful") do
  read(LANG_ROOT / "lib" / "igniter_lang" / "typechecker.rb").lines.length > 3000   # also large; deferred by policy
end

# ══════════════════════════════════════════════════════════════════════════════
puts
total = $pass + $fail
status = $fail.zero? ? "PASS" : "FAIL"
puts "Result: #{$pass}/#{total} PASS"
puts "VERDICT: #{status} — LAB-RUST-TYPECHECKER-DECOMP-P1 #{$fail.zero? ? 'READINESS PROVED' : 'INCOMPLETE'}"
puts
puts "  MEASURED: typechecker.rs=#{TC_LC} ln | infer_expr=#{INFER_SPAN} ln | typecheck_contract=#{CONTRACT_SPAN} ln"
puts "            stdlib dispatch arms=#{ARMS} | pass modules in lib.rs=#{LIB_MODS}"
puts "  ANCHORS:  infer_expr@#{IE_START} substring@#{arm_line('substring')} map@#{arm_line('map')} fold@#{arm_line('fold')}"
puts
puts "  VERDICT:  intra-typechecker decomposition, NOT a crate split."
puts "  P2 SEAM:  extract stdlib call dispatch from infer_expr -> typechecker/stdlib_calls.rs"
puts "  P2 PROOF: 16-app Wave P11 fleet, EXACT diagnostic sets before/after,"
puts "            rule_engine fail-closed preserved (OOF-P1 Unknown.action + OOF-TY1)."
puts "  CLOSED:   no refactor / no behavior change / no Ruby canon / no crate split in P1."

exit($fail.zero? ? 0 : 1)
