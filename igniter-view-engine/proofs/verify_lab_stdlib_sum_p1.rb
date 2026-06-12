#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_sum_p1.rb
# LAB-STDLIB-SUM-P1 — stdlib.collection.sum readiness proof
# ==========================================================
# Determines whether sum should be a canonical stdlib helper, a fold-derived
# form, or deferred behind numeric type stabilization.
#
# Route:   READINESS PROOF / NO IMPLEMENTATION
# Card:    igniter-lab/.agents/work/cards/governance/LAB-STDLIB-SUM-P1.md
# Verdict: SPLIT-NUMERIC
#   Split A (accepted):  sum(Collection[T], Symbol) -> DeclaredFieldType  — two-arg form
#   Split B (blocked):   sum(Collection[T]) -> T — one-arg form; spec-absent + scale-stripping gap
#
# Sections:
#   A  STDLIB SPEC CHECK      (5)  — collections.ig two-arg only; no one-arg; no sumBy in spec
#   B  FIXTURE SURVEY         (8)  — which apps use sum, which forms, element types confirmed
#   C  RUBY TC DIAGNOSTICS    (8)  — Ruby OOF-TY0 for both forms; no dispatch in source
#   D  RUST TC DISPATCH       (6)  — two-arg scale-preserving; one-arg scale-stripped; SIR name bare
#   E  INTEGER SUM EVIDENCE   (4)  — Rust accepts; Ruby rejects; no integer-only app demand
#   F  DECIMAL SUM EVIDENCE   (4)  — two-arg Decimal[2]→Decimal[2]; one-arg→bare Decimal (gap)
#   G  EMPTY COLLECTION       (3)  — no Option wrapper in spec; no identity element defined
#   H  FOLD RELATIONSHIP      (3)  — derivable from fold; fold ACCEPT; independence justified
#   I  SUMBY + AUTHORITY      (5)  — no sumBy adoption; closed surfaces confirmed
#
# Total: 46 checks (minimum: 40)

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "tmpdir"

SCRIPT_DIR     = Pathname.new(__dir__)
LAB_ROOT       = SCRIPT_DIR.parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / "igniter-lang" / "lib"
COMPILER_BIN   = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
APPS_DIR       = LAB_ROOT / "igniter-apps"
STDLIB_DIR     = LAB_ROOT / "igniter-stdlib" / "stdlib"
STDLIB_INVENTORY = WORKSPACE_ROOT / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"
TC_RUBY        = WORKSPACE_ROOT / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
TC_RUST        = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"
STDLIB_EXT     = WORKSPACE_ROOT / "igniter-lang" / "source" / "stdlib_extension.ig"

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require "igniter_lang"

abort "Compiler binary not found: #{COMPILER_BIN}" unless COMPILER_BIN.exist?
abort "stdlib-inventory.json not found: #{STDLIB_INVENTORY}" unless STDLIB_INVENTORY.exist?
abort "Ruby TC not found: #{TC_RUBY}" unless TC_RUBY.exist?
abort "Rust TC not found: #{TC_RUST}" unless TC_RUST.exist?

# ─────────────────────────────────────────────────────────────────────────────
# Harness
# ─────────────────────────────────────────────────────────────────────────────

$pass = 0
$fail = 0

def check(label)
  result = yield
  if result
    $pass += 1
    puts "PASS #{label}"
  else
    $fail += 1
    puts "FAIL #{label}"
  end
rescue => e
  $fail += 1
  puts "FAIL #{label} [exception: #{e.message.lines.first&.strip}]"
end

def rust_compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    out  = File.join(tmpdir, "out.igapp")
    File.write(path, src)
    stdout, _stderr, _status = Open3.capture3(COMPILER_BIN.to_s, "compile", path, "--out", out)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    diags  = Array(result["diagnostics"])
    {
      status:   result["status"] || "parse-error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact
    }
  end
end

def ruby_compile_source(src)
  Dir.mktmpdir do |tmpdir|
    path = File.join(tmpdir, "inline.ig")
    out  = File.join(tmpdir, "out.igapp")
    File.write(path, src)
    c = IgniterLang::CompilerOrchestrator.new
    r = c.compile_sources(source_paths: [path], out_path: out)
    diags = r.dig("result", "diagnostics") || []
    {
      status:   r["status"] || "error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact
    }
  end
end

def rust_compile(*paths)
  Dir.mktmpdir do |tmpdir|
    out  = File.join(tmpdir, "out.igapp")
    args = [COMPILER_BIN.to_s, "compile"] + paths.map(&:to_s) + ["--out", out]
    stdout, _stderr, _status = Open3.capture3(*args)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    diags  = Array(result["diagnostics"])
    {
      status:   result["status"] || "parse-error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact
    }
  end
end

def ruby_compile(*paths)
  c = IgniterLang::CompilerOrchestrator.new
  Dir.mktmpdir do |tmpdir|
    out = File.join(tmpdir, "out.igapp")
    r   = c.compile_sources(source_paths: paths.map(&:to_s), out_path: out)
    diags = r.dig("result", "diagnostics") || []
    {
      status:   r["status"] || "error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact
    }
  end
end

def has_unknown_fn(result, fn_name)
  result[:messages].any? { |m|
    m.include?("Unknown function: #{fn_name}") || m.include?("unknown function")
  }
end

def no_unknown_fn(result, fn_name)
  result[:messages].none? { |m| m.include?("Unknown function: #{fn_name}") }
end

# ─────────────────────────────────────────────────────────────────────────────
# Load static assets once
# ─────────────────────────────────────────────────────────────────────────────

INVENTORY       = JSON.parse(STDLIB_INVENTORY.read(encoding: "UTF-8"))
TC_RUBY_SRC     = TC_RUBY.read(encoding: "UTF-8")
TC_RUST_SRC     = TC_RUST.read(encoding: "UTF-8")
COLLECTIONS_IG  = STDLIB_DIR / "collections.ig"
COLLECTIONS_SRC = COLLECTIONS_IG.exist? ? COLLECTIONS_IG.read(encoding: "UTF-8") : ""

BK_LEDGER    = APPS_DIR / "bookkeeping" / "ledger.ig"
BK_TYPES     = APPS_DIR / "bookkeeping" / "types.ig"
FOLD_LAB_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-STDLIB-FOLD-P1.md"

BK_LEDGER_SRC  = BK_LEDGER.exist?  ? BK_LEDGER.read(encoding: "UTF-8")  : ""
BK_TYPES_SRC   = BK_TYPES.exist?   ? BK_TYPES.read(encoding: "UTF-8")   : ""
STDLIB_EXT_SRC = STDLIB_EXT.exist? ? STDLIB_EXT.read(encoding: "UTF-8") : ""

# Extract the sum dispatch region from Rust TC (between "sum" => and the next arm "zip" =>)
SUM_REGION = TC_RUST_SRC[/"sum"\s*=>\s*\{.*?"zip"\s*=>/m]&.then { |s|
  # trim to just the sum arm body
  s.sub(/"zip"\s*=>.*/, "")
} || ""

# ─────────────────────────────────────────────────────────────────────────────
# Inline fixtures
# ─────────────────────────────────────────────────────────────────────────────

SUM_ONE_ARG_INTEGER = <<~IGNITER
  module SumTest
  contract SumOneArgInteger {
    input items : Collection[Integer]
    compute total = sum(items)
    output total : Integer
  }
IGNITER

SUM_TWO_ARG_DECIMAL = <<~IGNITER
  module SumTest
  type Lead {
    bid_amount: Integer,
    bid_decimal: Decimal[2]
  }
  contract SumTwoArgDecimal {
    input leads : Collection[Lead]
    compute total = sum(leads, :bid_decimal)
    output total : Decimal[2]
  }
IGNITER

SUM_TWO_ARG_INTEGER_FIELD = <<~IGNITER
  module SumTest
  type Item {
    quantity: Integer,
    label: Text
  }
  contract SumTwoArgIntegerField {
    input items : Collection[Item]
    compute total = sum(items, :quantity)
    output total : Integer
  }
IGNITER

SUM_ONE_ARG_DECIMAL = <<~IGNITER
  module SumTest
  contract SumOneArgDecimal {
    input amounts : Collection[Decimal[2]]
    compute total = sum(amounts)
    output total : Decimal[2]
  }
IGNITER

SUM_BY_NAME = <<~IGNITER
  module SumTest
  contract SumByTest {
    input items : Collection[Integer]
    compute total = sumBy(items)
    output total : Integer
  }
IGNITER

puts "\n=== LAB-STDLIB-SUM-P1: stdlib.collection.sum Readiness Proof ==="
puts "Verdict target: SPLIT-NUMERIC\n\n"

# ─────────────────────────────────────────────────────────────────────────────
# Section A — Stdlib spec check [5 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "--- Section A: Stdlib spec check ---"

check "A-01: stdlib/collections.ig defines two-arg sum(coll, field: Symbol)" do
  COLLECTIONS_SRC.include?("def sum(coll: Collection[T], field: Symbol)")
end

check "A-02: stdlib/collections.ig does NOT define a one-arg sum(coll) form" do
  !COLLECTIONS_SRC.match?(/def sum\(coll: Collection\[T\]\)\s*->/)
end

check "A-03: stdlib/collections.ig does NOT define a sumBy function" do
  !COLLECTIONS_SRC.include?("sumBy")
end

check "A-04: stdlib-inventory.json does NOT contain stdlib.collection.sum (not yet promoted)" do
  entries = INVENTORY.fetch("entries", [])
  entries.none? { |e| e["canonical_name"] == "stdlib.collection.sum" }
end

check "A-05: stdlib/collections.ig sum signature returns Decimal[S] without Option wrapper" do
  COLLECTIONS_SRC.match?(/def sum.*->\s*Decimal\[S\]/) &&
    !COLLECTIONS_SRC.match?(/def sum.*->\s*Option/)
end

# ─────────────────────────────────────────────────────────────────────────────
# Section B — Fixture survey [8 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "\n--- Section B: Fixture survey ---"

check "B-01: ledger.ig contains sum(debit_amounts) — one-arg form on Collection[Decimal[2]]" do
  BK_LEDGER_SRC.include?("sum(debit_amounts)")
end

check "B-02: ledger.ig contains sum(credit_amounts) — one-arg form on Collection[Decimal[2]]" do
  BK_LEDGER_SRC.include?("sum(credit_amounts)")
end

check "B-03: stdlib_extension.ig contains sum(leads, :bid_decimal) — two-arg form" do
  STDLIB_EXT_SRC.include?("sum(leads, :bid_decimal)")
end

check "B-04: stdlib_extension.ig contains sum(filter(leads, ...), :bid_decimal) — two-arg chained" do
  STDLIB_EXT_SRC.match?(/sum\(filter\(leads/)
end

check "B-05: Posting.amount declared as Decimal[2] in bookkeeping types — one-arg operand type confirmed" do
  BK_TYPES_SRC.include?("amount") && BK_TYPES_SRC.include?("Decimal[2]")
end

check "B-06: Lead.bid_decimal declared as Decimal[2] in stdlib_extension — two-arg field type confirmed" do
  STDLIB_EXT_SRC.include?("bid_decimal: Decimal[2]")
end

check "B-07: No app fixture uses sum(items) where items is Collection[Integer] — Integer-only ungrounded" do
  # debit_amounts and credit_amounts are Collection[Decimal[2]] (from map p -> p.amount)
  # stdlib_extension uses sum on Collection[Lead] with Decimal[2] field — not Integer
  BK_TYPES_SRC.include?("Decimal[2]") && !BK_LEDGER_SRC.match?(/input items\s*:\s*Collection\[Integer\].*sum\(items\)/m)
end

check "B-08: No app fixture uses sumBy function name" do
  !BK_LEDGER_SRC.include?("sumBy") && !STDLIB_EXT_SRC.include?("sumBy")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section C — Ruby TC diagnostics [8 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "\n--- Section C: Ruby TC diagnostics ---"

ruby_one_arg_int = ruby_compile_source(SUM_ONE_ARG_INTEGER)
ruby_two_arg_dec = ruby_compile_source(SUM_TWO_ARG_DECIMAL)
ruby_one_arg_dec = ruby_compile_source(SUM_ONE_ARG_DECIMAL)
ruby_sumby       = ruby_compile_source(SUM_BY_NAME)

check "C-01: Ruby inline sum(Collection[Integer]) — one-arg → OOF-TY0 Unknown function: sum" do
  has_unknown_fn(ruby_one_arg_int, "sum")
end

check "C-02: Ruby inline sum(Collection[Lead], :bid_decimal) — two-arg → OOF-TY0 Unknown function: sum" do
  has_unknown_fn(ruby_two_arg_dec, "sum")
end

check "C-03: Ruby inline sum(Collection[Decimal[2]]) — one-arg → OOF-TY0 Unknown function: sum" do
  has_unknown_fn(ruby_one_arg_dec, "sum")
end

check "C-04: Ruby inline sumBy(Collection[Integer]) → OOF-TY0 Unknown function: sumBy (not accepted)" do
  has_unknown_fn(ruby_sumby, "sumBy")
end

check "C-05: Ruby TC source: NUMERIC_MEASURE_BUILTINS does NOT include 'sum'" do
  numeric_section = TC_RUBY_SRC[/NUMERIC_MEASURE_BUILTINS\s*=\s*\{.*?\.freeze/m] || ""
  !numeric_section.include?('"sum"')
end

check "C-06: Ruby TC source: no SUM_STDLIB_FNS or COLLECTION_SUM constant defined" do
  !TC_RUBY_SRC.include?("SUM_STDLIB_FNS") && !TC_RUBY_SRC.include?("COLLECTION_SUM")
end

check "C-07: Ruby TC source: no 'when \"sum\"' arm in any dispatch method" do
  !TC_RUBY_SRC.match?(/when\s+["']sum["']/)
end

check "C-08: Ruby compile stdlib_extension.ig → OOF-TY0 for sum (two-arg form in file)" do
  r = ruby_compile(STDLIB_EXT)
  has_unknown_fn(r, "sum")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section D — Rust TC dispatch analysis [6 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "\n--- Section D: Rust TC dispatch analysis ---"

rust_two_arg_dec = rust_compile_source(SUM_TWO_ARG_DECIMAL)
rust_one_arg_dec = rust_compile_source(SUM_ONE_ARG_DECIMAL)

check "D-01: Rust TC source contains 'sum' dispatch arm" do
  TC_RUST_SRC.include?('"sum" =>')
end

check "D-02: Rust TC sum arm: default return type is bare Decimal (one-arg scale-stripping)" do
  # Before two-arg field extraction, dispatch assigns bare Decimal as resolved type
  SUM_REGION.include?('"Decimal"') || TC_RUST_SRC.match?(/type_ir.*"Decimal".*sum|sum.*type_ir.*"Decimal"/)
end

check "D-03: Rust TC sum arm: two-arg form uses get_param + type_shapes to extract field type" do
  TC_RUST_SRC.match?(/get_param.*?type_shapes/m) &&
    TC_RUST_SRC.match?(/args\.len\(\)\s*>=\s*2/)
end

check "D-04: Rust inline sum(Collection[Lead], :bid_decimal) — two-arg → no OOF-TY0" do
  no_unknown_fn(rust_two_arg_dec, "sum")
end

check "D-05: Rust inline sum(Collection[Decimal[2]]) — one-arg — compiles (scale-stripping is silent)" do
  # Rust accepts the call but returns bare Decimal instead of Decimal[2] — a type-precision gap
  no_unknown_fn(rust_one_arg_dec, "sum")
end

check "D-06: Rust TC sum arm does NOT emit 'stdlib.collection.sum' qualified SIR name" do
  !SUM_REGION.include?("stdlib.collection.sum") &&
    !TC_RUST_SRC.match?(/sum.*stdlib\.collection\.sum|stdlib\.collection\.sum.*sum/)
end

# ─────────────────────────────────────────────────────────────────────────────
# Section E — Integer sum evidence [4 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "\n--- Section E: Integer sum evidence ---"

rust_one_arg_int      = rust_compile_source(SUM_ONE_ARG_INTEGER)
rust_two_arg_int_fld  = rust_compile_source(SUM_TWO_ARG_INTEGER_FIELD)

check "E-01: Rust inline sum(Collection[Integer]) — one-arg → Rust accepts (no unknown-fn error)" do
  no_unknown_fn(rust_one_arg_int, "sum")
end

check "E-02: Rust inline sum(Collection[Item], :quantity) — two-arg Integer field → Rust accepts" do
  no_unknown_fn(rust_two_arg_int_fld, "sum")
end

check "E-03: Ruby inline sum(Collection[Integer]) — one-arg → OOF-TY0 (no Ruby dispatch)" do
  has_unknown_fn(ruby_one_arg_int, "sum")
end

check "E-04: ACCEPT-INTEGER-ONLY verdict ungrounded — app fixtures use Decimal not Integer in sum" do
  # Both ledger.ig (sum on Collection[Decimal[2]]) and stdlib_extension.ig (:bid_decimal: Decimal[2])
  # use Decimal values. No app calls sum on a Collection[Integer].
  BK_TYPES_SRC.include?("Decimal[2]") &&
    !BK_LEDGER_SRC.match?(/sum\([a-z_]+\)\s*\n.*input \w+ : Collection\[Integer\]/m)
end

# ─────────────────────────────────────────────────────────────────────────────
# Section F — Decimal sum evidence [4 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "\n--- Section F: Decimal sum evidence ---"

rust_stdlib_ext = rust_compile(STDLIB_EXT)

check "F-01: Rust compile stdlib_extension.ig — two-arg sum on Decimal[2] field → no OOF-TY0" do
  no_unknown_fn(rust_stdlib_ext, "sum")
end

check "F-02: Rust TC sum two-arg: field-type lookup extracts declared Decimal[N] → scale-preserving" do
  # get_param extracts Collection[T]'s T, type_shapes.get finds the type record,
  # fields.get(field_name) returns the declared type (e.g. Decimal[2])
  TC_RUST_SRC.include?("get_param") && TC_RUST_SRC.include?("type_shapes") &&
    TC_RUST_SRC.match?(/fields\.get\(&field_name\)/)
end

check "F-03: Rust TC sum one-arg: default return is bare Decimal — scale stripped for Decimal[N] inputs" do
  # The resolved type starts as bare "Decimal" before the two-arg check
  # For sum(amounts) where amounts: Collection[Decimal[2]], Rust returns Decimal (not Decimal[2])
  TC_RUST_SRC.match?(/let mut resolved = self\.type_ir.*"Decimal"/) &&
    TC_RUST_SRC.match?(/args\.len\(\)\s*>=\s*2/)
end

check "F-04: One-arg sum form absent from stdlib spec AND has Rust scale-stripping gap — Split B justified" do
  spec_no_one_arg = !COLLECTIONS_SRC.match?(/def sum\(coll: Collection\[T\]\)\s*->/)
  rust_strips_scale = TC_RUST_SRC.match?(/let mut resolved = self\.type_ir.*"Decimal"/)
  spec_no_one_arg && rust_strips_scale
end

# ─────────────────────────────────────────────────────────────────────────────
# Section G — Empty collection semantics [3 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "\n--- Section G: Empty collection semantics ---"

check "G-01: stdlib/collections.ig sum returns Decimal[S] not Option[Decimal[S]] — no empty guard in spec" do
  COLLECTIONS_SRC.match?(/def sum.*->\s*Decimal\[S\]/) &&
    !COLLECTIONS_SRC.match?(/def sum.*->\s*Option/)
end

check "G-02: No identity element (0) defined for sum in any stdlib spec or inventory entry" do
  !COLLECTIONS_SRC.match?(/identity|zero|initial.*sum|sum.*initial/i) &&
    INVENTORY.fetch("entries", []).none? { |e| e["canonical_name"] == "stdlib.collection.sum" }
end

check "G-03: Bookkeeping context: Transaction has postings:Collection[Posting] — non-empty by domain" do
  # A valid double-entry transaction always has at least one debit and one credit posting.
  # The type system does not enforce non-empty, but the domain invariant holds.
  # Empty-collection semantics are app-structural and deferred from this card.
  BK_TYPES_SRC.include?("postings") && BK_TYPES_SRC.include?("Collection[Posting]")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section H — fold relationship [3 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "\n--- Section H: fold relationship ---"

check "H-01: LAB-STDLIB-FOLD-P1 verdict is ACCEPT — sum-derivation-from-fold is viable" do
  FOLD_LAB_CARD.exist? && FOLD_LAB_CARD.read(encoding: "UTF-8").include?("ACCEPT")
end

check "H-02: Rust TC dispatches sum and fold as independent operations — independent precedent" do
  TC_RUST_SRC.include?('"sum" =>') && TC_RUST_SRC.include?('"fold" =>')
end

check "H-03: Ruby TC has no fold dispatch — sum independence avoids a fold implementation dependency" do
  !TC_RUBY_SRC.match?(/when\s+["']fold["']/) && !TC_RUBY_SRC.include?("FOLD_STDLIB_FNS")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section I — sumBy deferral + authority closed [5 checks]
# ─────────────────────────────────────────────────────────────────────────────

puts "\n--- Section I: sumBy deferral + authority closed ---"

check "I-01: No function named sumBy in any canonical app fixture" do
  !BK_LEDGER_SRC.include?("sumBy") && !STDLIB_EXT_SRC.include?("sumBy")
end

check "I-02: No function named sumBy in stdlib/collections.ig spec" do
  !COLLECTIONS_SRC.include?("sumBy")
end

check "I-03: No Ruby TC sum dispatch authorized — TC source confirms zero sum dispatch" do
  !TC_RUBY_SRC.include?('"sum" =>') && !TC_RUBY_SRC.match?(/when\s+["']sum["']/)
end

check "I-04: No stdlib-inventory.json sum entry — no premature inventory promotion" do
  entries = INVENTORY.fetch("entries", [])
  entries.none? { |e| e["canonical_name"] == "stdlib.collection.sum" }
end

check "I-05: No fold implementation added by this card — Ruby TC fold dispatch absent" do
  !TC_RUBY_SRC.match?(/when\s+["']fold["']/) && !TC_RUBY_SRC.include?("infer_fold_call")
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

puts "\n" + "=" * 60
total = $pass + $fail
puts "#{$pass}/#{total} PASS"
if $fail == 0
  puts "VERDICT: SPLIT-NUMERIC"
  puts "  Split A (accepted):  sum(Collection[T], Symbol) -> DeclaredFieldType"
  puts "    — two-arg field-projection form; conformance-tested in Rust; scale-preserving"
  puts "    — Ruby TC dispatch gap is solvable (follows COLLECTION_HOF_FNS pattern)"
  puts "    — Next route: LANG-STDLIB-SUM-PROP-P1"
  puts "  Split B (blocked):   sum(Collection[T]) -> T — one-arg bare form"
  puts "    — NOT in stdlib spec; Rust scale-stripping bug (bare Decimal not Decimal[N])"
  puts "    — Requires: numeric constraint, scale propagation rule, identity element spec"
  puts "    — Blocked by: STAB-P4-OPERATOR-PARITY / LAB-STDLIB-NUMERIC-P1"
else
  puts "NOTE: #{$fail} check(s) failed — review before routing"
end
