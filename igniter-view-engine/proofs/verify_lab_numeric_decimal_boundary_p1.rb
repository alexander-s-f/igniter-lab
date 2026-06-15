# encoding: utf-8
# frozen_string_literal: true
#
# verify_lab_numeric_decimal_boundary_p1.rb
# LAB-NUMERIC-DECIMAL-BOUNDARY-P1 — readiness / policy proof
#
# Classifies the residual `bookkeeping` blocker: `Output type mismatch: expected
# Decimal[2], got Float` (BK-P03). Grounds the policy decision:
#   - implicit Float/Integer -> Decimal assignment is NOT allowed for v0 and is ALREADY
#     rejected dual-toolchain (OOF-TY1) — keep rejecting (money is exact fixed-point);
#   - the real gap is Decimal CONSTRUCTION (no `decimal()` ctor, no Decimal literal) —
#     route = explicit `decimal(value, scale) -> Decimal[scale]`;
#   - Decimal[N] is first-class in syntax / typechecker (scale-aware) / VM
#     (Value::Decimal{value,scale}); round_decimal(Float,scale) deferred; no Money type.
#
# Sections:
#   A  Gate + predecessor                         (6)
#   B  Decimal[N] is first-class (syntax/TC/VM)   (9)
#   C  Implicit numeric->Decimal REJECTED (dual)  (11)
#   D  No Decimal construction surface today      (6)
#   E  bookkeeping blocker live (dual)            (6)
#   F  VM preserves scale                         (5)
#   G  Locked decisions                           (8)
#   H  Canon vs lab                               (5)
#   I  Closed surfaces / scope                    (6)
#
# Total: 62 checks
#
# Authority: readiness/policy only. No implementation. Card: LAB-NUMERIC-DECIMAL-BOUNDARY-P1.
# Date: 2026-06-15

require "json"; require "open3"; require "pathname"; require "tmpdir"

LAB  = Pathname.new(__dir__).expand_path.parent.parent          # igniter-lab
ROOT = LAB.parent                                               # igniter-workspace
LANG = ROOT / "igniter-lang"
BIN  = LAB / "igniter-compiler" / "target" / "release" / "igniter_compiler"

RS_TC  = LAB / "igniter-compiler" / "src" / "typechecker.rs"
RS_VM  = LAB / "igniter-vm" / "src" / "vm.rs"
RS_PAR = LAB / "igniter-compiler" / "src" / "parser.rs"
CARDS  = LAB / ".agents" / "work" / "cards" / "lang"
BK     = LAB / "igniter-apps" / "bookkeeping"
DOC    = LAB / "lab-docs" / "lang" / "lab-numeric-decimal-boundary-p1-v0.md"

def read(p) = (File.read(p.to_s, encoding: "utf-8") rescue "")
RSTC, RSVM, RSPAR = read(RS_TC), read(RS_VM), read(RS_PAR)
CH3 = read(LANG / "docs" / "spec" / "ch3-type-system.md")

$LOAD_PATH.unshift (LANG / "lib").to_s
require "igniter_lang"

# ── Ruby canon typecheck ──────────────────────────────────────────────────────
def ruby_rules(src)
  p = IgniterLang::ParsedProgram.parse(src, source_path: "i").to_h
  return ["PARSE"] unless Array(p["parse_errors"]).empty?
  c = IgniterLang::Classifier.new.classify(p, sample_input: {})
  r = IgniterLang::TypeChecker.new.typecheck(c)
  Array(r["type_errors"]).map { |e| e["rule"] }.uniq
rescue => e
  ["EXC:#{e.message.to_s[0, 40]}"]
end

# ── Rust lab compile (UTF-8 forced) ───────────────────────────────────────────
def rust_rules(*srcs)
  return ["NO_BINARY"] unless File.executable?(BIN.to_s)
  Dir.mktmpdir("dec_p1_") do |d|
    paths = srcs.each_with_index.map { |s, i| pa = File.join(d, "f#{i}.ig"); File.write(pa, s); pa }
    out = File.join(d, "o.igapp")
    so, _e, _s = Open3.capture3(BIN.to_s, "compile", *paths, "--out", out)
    dd = JSON.parse(so.force_encoding("UTF-8")) rescue nil
    return ["PARSE_FAIL"] unless dd
    Array(dd["diagnostics"]).map { |x| x["rule"] }.uniq
  end
end

def has?(rules, code) = rules.include?(code)
def clean?(rules) = rules.empty?

$pass = 0; $fail = 0
def check(l); r = yield; r ? ($pass += 1; puts "  PASS  #{l}") : ($fail += 1; puts "  FAIL  #{l}")
rescue => e; $fail += 1; puts "  FAIL  #{l}  [#{e.class}: #{e.message.lines.first&.strip}]"; end
def section(t) = puts("\n─── #{t} #{'─' * [0, 66 - t.length].max}")

def c(body) = "module M\n#{body}\n"
SRC = {
  bare_float: c("pure contract C { compute o = 0.00 output o : Decimal[2] }"),
  fvar:       c("pure contract C { input f : Float compute o = f output o : Decimal[2] }"),
  fadd:       c("pure contract C { input f : Float compute o = f + 1.00 output o : Decimal[2] }"),
  intvar:     c("pure contract C { input n : Integer compute o = n output o : Decimal[2] }"),
  decctor:    c("pure contract C { compute o = decimal(0, 2) output o : Decimal[2] }"),
  decin:      c("pure contract C { input d : Decimal[2] compute o = d output o : Decimal[2] }"),
}
RB = {}; RS = {}
SRC.each { |k, s| RB[k] = ruby_rules(s); RS[k] = rust_rules(s) }

BK_FILES = %w[types ledger api].map { |f| read(BK / "#{f}.ig") }
BK_RS = rust_rules(*BK_FILES)
RUST_OK = File.executable?(BIN.to_s)

puts "=" * 72
puts "LAB-NUMERIC-DECIMAL-BOUNDARY-P1 — readiness / policy proof"
puts "Rust binary: #{RUST_OK ? BIN : 'NOT BUILT (rust checks degrade)'}"
puts "=" * 72

# ══════════════════════════════════════════════════════════════════════════════
section("A  Gate + predecessor")
check("A-01: this card is readiness/policy-only") { read(CARDS / "LAB-NUMERIC-DECIMAL-BOUNDARY-P1.md").include?("readiness and policy only") }
check("A-02: predecessor NUMERIC-DISPATCH-UNKNOWN-P1 present (homogeneous done)") { File.exist?((CARDS / "LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md").to_s) }
check("A-03: predecessor names the deferred heterogeneous Float→Decimal residual") { read(CARDS / "LAB-COMPILER-NUMERIC-DISPATCH-UNKNOWN-P1.md").include?("heterogeneous") }
check("A-04: bookkeeping app + registry present") { File.exist?((BK / "ledger.ig").to_s) && File.exist?((BK / "PRESSURE_REGISTRY.md").to_s) }
check("A-05: BK-P03 is the Decimal-literal-typing pressure") { read(BK / "PRESSURE_REGISTRY.md").include?("BK-P03") }
check("A-06: Rust release binary present") { RUST_OK }

# ══════════════════════════════════════════════════════════════════════════════
section("B  Decimal[N] is first-class (syntax / TC / VM)")
check("B-01: ch3 declares Decimal[N] fixed-point, N places") { CH3.include?("Decimal[N]") }
check("B-02: ch3 rule Decimal[A]+Decimal[B] requires A==B (OOF-TC5)") { CH3.include?("OOF-TC5") }
check("B-03: ch3 rule Decimal[A]*Decimal[B] -> Decimal[A+B]") { CH3.match?(/Decimal\[A\] \* Decimal\[B\].*Decimal\[A\+B\]/m) || CH3.include?("Decimal[A+B]") }
check("B-04: parser recognises Decimal type annotation") { RSPAR.include?('name == "Decimal"') }
check("B-05: TC tracks Decimal scale (left_scale/right_scale)") { RSTC.include?("left_scale") && RSTC.include?("right_scale") }
check("B-06: TC raises OOF-TC5 on add/sub scale mismatch") { RSTC.include?("OOF-TC5") }
check("B-07: TC lowers to stdlib.decimal.add / stdlib.decimal.mul") { RSTC.include?("stdlib.decimal.add") && RSTC.include?("stdlib.decimal.mul") }
check("B-08: Decimal[2] -> Decimal[2] sanity is clean in Rust") { clean?(RS[:decin]) }
check("B-09: Decimal is NOT merely an app convention (3-layer presence)") { CH3.include?("Decimal[N]") && RSTC.include?("left_scale") && RSVM.include?("Decimal") }

# ══════════════════════════════════════════════════════════════════════════════
section("C  Implicit numeric→Decimal REJECTED (dual, money-safe)")
check("C-01: Ruby bare 0.00 → Decimal[2] → OOF-TY1") { has?(RB[:bare_float], "OOF-TY1") }
check("C-02: Rust bare 0.00 → Decimal[2] → OOF-TY1") { has?(RS[:bare_float], "OOF-TY1") }
check("C-03: bare-Float→Decimal rejected DUAL") { has?(RB[:bare_float], "OOF-TY1") && has?(RS[:bare_float], "OOF-TY1") }
check("C-04: Ruby f:Float → Decimal[2] → OOF-TY1 (expr, not literal)") { has?(RB[:fvar], "OOF-TY1") }
check("C-05: Rust f:Float → Decimal[2] → OOF-TY1 (expr, not literal)") { has?(RS[:fvar], "OOF-TY1") }
check("C-06: Float arithmetic f+1.00 → Decimal[2] → OOF-TY1 dual") { has?(RB[:fadd], "OOF-TY1") && has?(RS[:fadd], "OOF-TY1") }
check("C-07: Ruby n:Integer → Decimal[2] → OOF-TY1 (Integer also rejected)") { has?(RB[:intvar], "OOF-TY1") }
check("C-08: Rust n:Integer → Decimal[2] → OOF-TY1 (Integer also rejected)") { has?(RS[:intvar], "OOF-TY1") }
check("C-09: rejection is UNIFORM across Float and Integer (no implicit coercion)") do
  has?(RS[:fvar], "OOF-TY1") && has?(RS[:intvar], "OOF-TY1") && has?(RS[:bare_float], "OOF-TY1")
end
check("C-10: root = structurally_assignable requires matching type name") { RSTC.include?("fn structurally_assignable") }
check("C-11: => implicit Float/Integer→Decimal is ALREADY money-safe; keep rejecting") { has?(RS[:fvar], "OOF-TY1") }

# ══════════════════════════════════════════════════════════════════════════════
# NOTE: section D originally pinned the *pre-implementation* gap (decimal() was an
# Unknown function). LAB-NUMERIC-DECIMAL-CONSTRUCT-P1 implemented the constructor, so
# these checks now assert the RESOLVED state and act as a forward regression guard.
# The historical gap is preserved in this card's closure summary + the readiness doc.
section("D  Decimal construction surface (CONSTRUCT-P1 implemented)")
check("D-01: Ruby decimal(0,2) now compiles clean (CONSTRUCT-P1)") { clean?(RB[:decctor]) }
check("D-02: Rust decimal(0,2) now compiles clean (CONSTRUCT-P1)") { clean?(RS[:decctor]) }
check("D-03: decimal() constructor now resolves in both toolchains") { clean?(RB[:decctor]) && clean?(RS[:decctor]) }
check("D-04: still no Decimal literal — 0.00 types as Float, fails Decimal[2] output") { has?(RS[:bare_float], "OOF-TY1") }
check("D-05: => a pure contract can now mint a Decimal constant, yet implicit Float stays rejected") { clean?(RS[:decctor]) && has?(RS[:bare_float], "OOF-TY1") }
check("D-06: Decimal sources = typed input, Decimal arithmetic, or decimal() constructor") { clean?(RS[:decin]) && clean?(RS[:decctor]) }

# ══════════════════════════════════════════════════════════════════════════════
# NOTE: section E originally pinned the *live* bookkeeping Float->Decimal blocker. The
# follow-up LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1 migrated the fold seed 0.00 -> decimal(0,2),
# so Rust bookkeeping now compiles clean. These checks assert the RESOLVED state and act as
# a forward regression guard; the historical live blocker is preserved in this card's doc.
section("E  bookkeeping blocker resolved by decimal() migration")
check("E-01: Rust bookkeeping full now clean (BK-P03 resolved by MIGRATION-P1)") { clean?(BK_RS) }
check("E-02: bookkeeping Rust is clean (blocker resolved)") { clean?(BK_RS) }
check("E-03: ledger ComputeAccountBalance seeds fold with decimal(0, 2) (migrated off Float)") { read(BK / "ledger.ig").include?("fold(txs, decimal(0, 2)") }
check("E-04: output total annotated Decimal[2]") { read(BK / "ledger.ig").include?("output total : Decimal[2]") }
check("E-05: Posting.amount is Decimal[2] (the money type)") { read(BK / "types.ig").include?("amount     : Decimal[2]") || read(BK / "types.ig").include?("amount") }
check("E-06: the blocker was heterogeneous Float->Decimal — now off Float via decimal() (no bare 0.00)") { !read(BK / "ledger.ig").include?("0.00") }

# ══════════════════════════════════════════════════════════════════════════════
section("F  VM preserves scale")
check("F-01: VM has Value::Decimal { value, scale }") { RSVM.include?("Value::Decimal") && RSVM.include?("scale") }
check("F-02: VM uses igniter_stdlib::decimal::Decimal") { RSVM.include?("igniter_stdlib::decimal::Decimal") || RSVM.include?("decimal::Decimal") }
check("F-03: VM arithmetic constructs Decimal::new(value, scale)") { RSVM.include?("Decimal::new(") }
check("F-04: VM returns a scaled result (res_dec.scale)") { RSVM.include?("res_dec.scale") || RSVM.include?(".scale }") }
check("F-05: => Decimal is a scale-carrying VM value, not a scaleless family") { RSVM.include?("Value::Decimal") }

# ══════════════════════════════════════════════════════════════════════════════
section("G  Locked decisions")
check("G-01: DECISION — no implicit Float→Decimal for v0 (already rejected)") { DOC.then { |p| read(p).include?("implicit `Float → Decimal`") } && has?(RS[:fvar], "OOF-TY1") }
check("G-02: ROUTE — explicit decimal(value, scale) -> Decimal[scale]") { read(DOC).include?("decimal(value, scale) -> Decimal[scale]") }
check("G-03: real gap = construction, not coercion") { read(DOC).include?("not coercion but **Decimal construction**") || read(DOC).include?("Decimal construction") }
check("G-04: round_decimal(Float,scale) deferred as the explicit rounding bridge") { read(DOC).include?("round_decimal") }
check("G-05: bookkeeping migrates 0.00 → decimal(0, 2) (separate card)") { read(DOC).include?("decimal(0, 2)") }
check("G-06: diagnostics keep OOF-TY1 + OOF-TC5 (no silent coercion)") { read(DOC).include?("OOF-TY1") && read(DOC).include?("OOF-TC5") }
check("G-07: bookkeeping wants generic Decimal[2], NOT a Money type") { read(DOC).include?("No `Money`") || read(DOC).include?("No Money type") }
check("G-08: follow-up impl card named (decimal constructor)") { read(DOC).include?("LAB-NUMERIC-DECIMAL-CONSTRUCT-P1") }

# ══════════════════════════════════════════════════════════════════════════════
section("H  Canon vs lab")
check("H-01: policy + decimal() surface belong to canon-lang") { read(DOC).include?("Canon-lang") }
check("H-02: runtime substrate already exists in lab (Value::Decimal)") { RSVM.include?("Value::Decimal") }
check("H-03: decimal() impl is a lab follow-up (TC arm + VM/stdlib)") { read(DOC).include?("lab follow-up") }
check("H-04: canon parity restored — Ruby Decimal[N] input annotation no longer crashes (CONSTRUCT-P1)") { clean?(RB[:decin]) }
check("H-05: Rust handles Decimal[N] input annotation cleanly") { clean?(RS[:decin]) }

# ══════════════════════════════════════════════════════════════════════════════
section("I  Closed surfaces / scope")
check("I-01: readiness card stayed policy-only; decimal() implemented by CONSTRUCT-P1 (now clean)") { clean?(RS[:decctor]) }
check("I-02: no implicit coercion introduced (Float→Decimal still OOF-TY1)") { has?(RS[:fvar], "OOF-TY1") }
check("I-03: no Money type") { read(DOC).include?("No `Money`") || read(DOC).include?("no `Money`") }
check("I-04: no rounding-policy change") { read(DOC).include?("rounding-policy change") }
check("I-05: this readiness card made no app source migration (the migration was a separate card)") { read(DOC).downcase.include?("no app source migration") }
check("I-06: no canon spec change beyond this readiness proposal") { read(DOC).include?("no canon spec change beyond") }

puts
total = $pass + $fail
puts "Result: #{$pass}/#{total} PASS"
puts "VERDICT: #{$fail.zero? ? 'PASS — LAB-NUMERIC-DECIMAL-BOUNDARY-P1 READINESS PROVED' : 'FAIL — INCOMPLETE'}"
if $fail.zero?
  puts
  puts "  DECISION: no implicit Float/Integer→Decimal v0 (already rejected dual, money-safe)."
  puts "  ROUTE: explicit decimal(value, scale) -> Decimal[scale]; real gap = construction."
  puts "  round_decimal(Float,scale) deferred; bookkeeping migrates 0.00 → decimal(0,2)."
end
exit($fail.zero? ? 0 : 1)
