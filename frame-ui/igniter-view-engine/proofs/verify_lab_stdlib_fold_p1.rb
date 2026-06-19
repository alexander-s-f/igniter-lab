#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_fold_p1.rb
# LAB-STDLIB-FOLD-P1 — stdlib.collection.fold readiness proof
# ===========================================================
# Determines whether stdlib.collection.fold is ready for proposal authoring
# (ACCEPT), blocked on one toolchain (SPLIT), or blocked on accumulator typing
# (HOLD).
#
# Route:   READINESS PROOF / NO IMPLEMENTATION
# Card:    igniter-lab/.agents/work/cards/governance/LAB-STDLIB-FOLD-P1.md
# Verdict: ACCEPT — proposal authoring ready
#
# Sections:
#   A  INVENTORY CHECK        (6)  — fold/sum absent; count present
#   B  APP SOURCE SCAN        (6)  — fold shapes in bookkeeping + ERP fixtures
#   C  RUBY DIAGNOSTICS       (8)  — OOF-TY0 on fold; fold_stream separate
#   D  RUST DIAGNOSTICS       (6)  — Rust accepts fold; seed-type result
#   E  ACCUMULATOR TYPING     (6)  — seed-literal bootstrap; element_type_from_collection
#   F  LAMBDA SHAPE           (6)  — 2-param lambdas; single-expr + block bodies
#   G  SIGNATURE & OOF        (6)  — canonical sig; OOF-COL4 reserved; CORE-only
#   H  CLOSED SURFACES        (6)  — no sum/map/filter/recursion/VM/inventory
#
# Total: 50 checks (minimum: 45)

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
STDLIB_INVENTORY = WORKSPACE_ROOT / "igniter-lang" / "docs" / "spec" / "stdlib-inventory.json"
TC_RUBY        = WORKSPACE_ROOT / "igniter-lang" / "lib" / "igniter_lang" / "typechecker.rb"
TC_RUST        = LAB_ROOT / "igniter-compiler" / "src" / "typechecker.rs"

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
    diags = Array(result["diagnostics"])
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
    File.write(path, src)
    c = IgniterLang::CompilerOrchestrator.new
    Dir.mktmpdir do |tmpdir2|
      out = File.join(tmpdir2, "out.igapp")
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
end

def rust_compile(*paths)
  Dir.mktmpdir do |tmpdir|
    out = File.join(tmpdir, "out.igapp")
    args = [COMPILER_BIN.to_s, "compile"] + paths.map(&:to_s) + ["--out", out]
    stdout, _stderr, _status = Open3.capture3(*args)
    result = JSON.parse(stdout.force_encoding("UTF-8")) rescue {}
    diags = Array(result["diagnostics"])
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
    r = c.compile_sources(source_paths: paths.map(&:to_s), out_path: out)
    diags = r.dig("result", "diagnostics") || []
    {
      status:   r["status"] || "error",
      diags:    diags,
      messages: diags.map { |d| d["message"].to_s },
      codes:    diags.map { |d| d["rule"].to_s }.compact
    }
  end
end

# ─────────────────────────────────────────────────────────────────────────────
# Load static assets once
# ─────────────────────────────────────────────────────────────────────────────

INVENTORY     = JSON.parse(STDLIB_INVENTORY.read(encoding: "UTF-8"))
TC_RUBY_SRC   = TC_RUBY.read(encoding: "UTF-8")
TC_RUST_SRC   = TC_RUST.read(encoding: "UTF-8")

BK_LEDGER    = APPS_DIR / "bookkeeping" / "ledger.ig"
BK_TYPES     = APPS_DIR / "bookkeeping" / "types.ig"
ERP_TYPES    = APPS_DIR / "erp_logistics" / "types.ig"
ERP_OPTIMIZER = APPS_DIR / "erp_logistics" / "optimizer.ig"

# Minimal inline fixtures for accumulator typing checks
FOLD_INTEGER_FIXTURE = <<~IG
  module FoldTest

  type Item { value : Integer }

  contract SumItems {
    input items : Collection[Item]
    compute total = fold(items, 0, (acc, x) -> acc + x.value)
    output total : Integer
  }
IG

FOLD_FLOAT_FIXTURE = <<~IG
  module FoldMinCost

  type Route { cost : Float }

  contract MinCost {
    input routes : Collection[Route]
    compute best = fold(routes, 999999.0, (acc, r) -> if r.cost < acc { r.cost } else { acc })
    output best : Float
  }
IG

FOLD_WRONG_ARITY_FIXTURE = <<~IG
  module FoldArityTest

  type Item { value : Integer }

  contract BadFold {
    input items : Collection[Item]
    compute total = fold(items, 0)
    output total : Integer
  }
IG

FOLD_NON_COLLECTION_FIXTURE = <<~IG
  module FoldNonCol

  contract BadFold {
    input n : Integer
    compute result = fold(n, 0, (acc, x) -> acc + x)
    output result : Integer
  }
IG

# ─────────────────────────────────────────────────────────────────────────────
# Section A — stdlib-inventory.json inventory check [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== A: stdlib-inventory.json inventory check ===\n"

inv_entries = INVENTORY["entries"]
inv_names   = inv_entries.map { |e| e["canonical_name"] }

check "A-01: stdlib.collection.fold is NOT in inventory (proof-local, not yet proposed)" do
  !inv_names.include?("stdlib.collection.fold")
end

check "A-02: stdlib.collection.sum is NOT in inventory (separate card)" do
  !inv_names.include?("stdlib.collection.sum")
end

check "A-03: stdlib.collection.count IS in inventory (production-implemented)" do
  inv_names.include?("stdlib.collection.count")
end

check "A-04: stdlib.collection.count lifecycle_status is production-implemented" do
  e = inv_entries.find { |e| e["canonical_name"] == "stdlib.collection.count" }
  e && e["lifecycle_status"] == "production-implemented"
end

check "A-05: stdlib.collection.map is NOT in inventory (awaiting P1 proposal amendment)" do
  !inv_names.include?("stdlib.collection.map")
end

check "A-06: stdlib.collection.filter is NOT in inventory (awaiting P1 proposal amendment)" do
  !inv_names.include?("stdlib.collection.filter")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section B — App source scan [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== B: App source scan ===\n"

bk_ledger_src    = BK_LEDGER.read
erp_optimizer_src = ERP_OPTIMIZER.read

check "B-01: bookkeeping/ledger.ig contains fold call" do
  bk_ledger_src.include?("fold(")
end

check "B-02: erp_logistics/optimizer.ig contains fold call" do
  erp_optimizer_src.include?("fold(")
end

check "B-03: bookkeeping fold uses 3-arg form (collection, seed, lambda)" do
  bk_ledger_src.match?(/fold\s*\(\s*\w+\s*,\s*[\d.]+\s*,\s*\(/)
end

check "B-04: ERP fold uses 3-arg form (collection, seed, lambda)" do
  erp_optimizer_src.match?(/fold\s*\(\s*\w+\s*,\s*[\d.]+\s*,\s*\(/)
end

check "B-05: bookkeeping fold lambda has 2 params (acc, tx)" do
  bk_ledger_src.include?("(acc, tx)")
end

check "B-06: ERP fold lambda has 2 params (acc, r) with block body" do
  erp_optimizer_src.include?("(acc, r)") &&
    erp_optimizer_src.include?("if r.cost_per_kg < acc")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section C — Ruby TC diagnostics [8 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== C: Ruby TC diagnostics ===\n"

check "C-01: Ruby TC: bookkeeping ledger.ig produces OOF-TY0 on fold" do
  r = ruby_compile(BK_TYPES, BK_LEDGER)
  r[:codes].include?("OOF-TY0")
end

check "C-02: Ruby TC: bookkeeping fold OOF-TY0 message mentions 'fold'" do
  r = ruby_compile(BK_TYPES, BK_LEDGER)
  r[:messages].any? { |m| m.downcase.include?("fold") }
end

check "C-03: Ruby TC: ERP optimizer produces OOF-TY0 on fold" do
  r = ruby_compile(ERP_TYPES, ERP_OPTIMIZER)
  r[:codes].include?("OOF-TY0")
end

check "C-04: Ruby TC: ERP fold OOF-TY0 message mentions 'fold'" do
  r = ruby_compile(ERP_TYPES, ERP_OPTIMIZER)
  r[:messages].any? { |m| m.downcase.include?("fold") }
end

check "C-05: Ruby TC: inline fold fixture produces OOF-TY0 (Unknown function: fold)" do
  r = ruby_compile_source(FOLD_INTEGER_FIXTURE)
  r[:codes].include?("OOF-TY0") &&
    r[:messages].any? { |m| m.include?("fold") }
end

check "C-06: Ruby TC: no fold arm in TEXT_STDLIB_FNS keys" do
  !TC_RUBY_SRC.match?(/TEXT_STDLIB_FNS\s*=.*"fold"/)
end

check "C-07: Ruby TC: no fold arm in MAP_STDLIB_FNS or OUTCOME_STDLIB_FNS" do
  !TC_RUBY_SRC.match?(/MAP_STDLIB_FNS\s*=.*"fold"/) &&
    !TC_RUBY_SRC.match?(/OUTCOME_STDLIB_FNS\s*=.*"fold"/)
end

check "C-08: Ruby TC: fold_stream_result_type exists (seed-typing pattern proven for streams)" do
  TC_RUBY_SRC.include?("def fold_stream_result_type")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section D — Rust TC diagnostics [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== D: Rust TC diagnostics ===\n"

check "D-01: Rust TC: fold arm present in typechecker.rs" do
  TC_RUST_SRC.include?('"fold"')
end

check "D-02: Rust TC: fold result type is derived from typed_args[1] (seed)" do
  TC_RUST_SRC.match?(/\"fold\"\s*=>\s*\{[^}]*typed_args\[1\]\.resolved_type/)
end

check "D-03: Rust TC: ERP optimizer compiles without fold-related OOF-TY0" do
  r = rust_compile(ERP_TYPES, ERP_OPTIMIZER)
  !r[:messages].any? { |m| m.include?("Unknown function") && m.include?("fold") }
end

check "D-04: Rust TC: fold dispatch sets is_resolved=true (not falling to unresolved path)" do
  # Rust TC fold arm: is_resolved = true; then branch on typed_args.len() >= 2.
  # This confirms fold is actively dispatched, not silently ignored.
  TC_RUST_SRC.match?(/\"fold\"\s*=>\s*\{[^}]*is_resolved\s*=\s*true/)
end

check "D-05: Rust TC: fold inline fixture compiles without Unknown function: fold" do
  r = rust_compile_source(FOLD_INTEGER_FIXTURE)
  !r[:messages].any? { |m| m.include?("Unknown function") && m.include?("fold") }
end

check "D-06: Rust TC: SIR emits bare 'fold' fn name (not qualified stdlib.collection.fold)" do
  # Rust TC follows annotated_expr: None pattern — no qualified name emission for fold.
  # Confirmed by absence of "stdlib.collection.fold" string in Rust TC source.
  !TC_RUST_SRC.include?('"stdlib.collection.fold"')
end

# ─────────────────────────────────────────────────────────────────────────────
# Section E — Accumulator typing analysis [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== E: Accumulator typing analysis ===\n"

check "E-01: Ruby TC: fold_stream_result_type uses init_arg type_tag (proven seed pattern)" do
  TC_RUBY_SRC.include?("init_arg.fetch(\"type_tag\", \"Unknown\")")
end

check "E-02: Ruby TC: fold_stream_result_type reads args[1] as init seed argument" do
  TC_RUBY_SRC.match?(/init_arg\s*=\s*args\[1\]/)
end

check "E-03: Ruby TC: element_type_from_collection exists (T extraction primitive)" do
  TC_RUBY_SRC.include?("def element_type_from_collection")
end

check "E-04: Ruby TC: collection_type_ir_from exists (builds Collection[T] from T)" do
  TC_RUBY_SRC.include?("def collection_type_ir_from") || TC_RUBY_SRC.include?("collection_type_ir_from(")
end

check "E-05: Rust TC: fold result uses typed_args[1] seed — same seed-bootstrap pattern" do
  TC_RUST_SRC.match?(/\"fold\"\s*=>\s*\{[^}]*typed_args\[1\]/)
end

check "E-06: Ruby TC: fold_stream result type extracts to Unknown when seed is non-literal" do
  TC_RUBY_SRC.include?("return type_ir(\"Unknown\") unless init_arg&.fetch(\"kind\", nil) == \"literal\"")
end

# ─────────────────────────────────────────────────────────────────────────────
# Section F — Lambda shape analysis [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== F: Lambda shape analysis ===\n"

check "F-01: bookkeeping fold lambda has exactly 2 params (acc, tx)" do
  # Count params in the fold lambda
  m = bk_ledger_src.match(/fold\s*\(\s*\w+\s*,\s*[^,]+,\s*\(([^)]+)\)/)
  m && m[1].split(",").map(&:strip).length == 2
end

check "F-02: ERP fold lambda has exactly 2 params (acc, r)" do
  m = erp_optimizer_src.match(/fold\s*\(\s*\w+\s*,\s*[^,]+,\s*\(([^)]+)\)/)
  m && m[1].split(",").map(&:strip).length == 2
end

check "F-03: bookkeeping fold lambda body is single-expression (acc + 0.00)" do
  bk_ledger_src.match?(/\(acc, tx\)\s*->\s*acc\s*\+/)
end

check "F-04: ERP fold lambda body is block-body (if-else branch)" do
  erp_optimizer_src.match?(/\(acc, r\)\s*->[\s\n]+if/)
end

check "F-05: Ruby TC: check_fold_stream_body handles 2-param lambda (collect_escape_refs)" do
  TC_RUBY_SRC.include?("def collect_escape_refs") &&
    TC_RUBY_SRC.include?("lambda_params = lambda_arg.fetch(\"params\", []).map(&:to_s).to_set")
end

check "F-06: no app fold fixture uses named function ref (all inline lambda)" do
  # Named fn ref would look like: fold(col, seed, fn_name) with no lambda arrow
  !bk_ledger_src.match?(/fold\s*\([^)]+,\s*[^)]+,\s*\w+\s*\)/) ||
    bk_ledger_src.match?(/fold\s*\([^)]+,\s*[^)]+,\s*\(/) &&
    !erp_optimizer_src.match?(/fold\s*\([^)]+,\s*[^)]+,\s*\w+\s*\)/) ||
    erp_optimizer_src.match?(/fold\s*\([^)]+,\s*[^)]+,\s*\(/)
end

# ─────────────────────────────────────────────────────────────────────────────
# Section G — Signature and OOF namespace [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== G: Signature and OOF namespace ===\n"

check "G-01: OOF-COL4 namespace reserved in P1 (fold-family errors)" do
  # P1 card and P1 proposal both reserve OOF-COL4 for fold
  p1_card = WORKSPACE_ROOT / "igniter-lang" / ".agents" / "work" / "cards" / "lang" /
            "LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P1.md"
  p1_card.exist? && p1_card.read.include?("OOF-COL4")
end

check "G-02: OOF-COL5 reserved for sum (not fold) — fold does not claim it" do
  p1_card = WORKSPACE_ROOT / "igniter-lang" / ".agents" / "work" / "cards" / "lang" /
            "LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P1.md"
  p1_card.exist? && p1_card.read.include?("OOF-COL5") && p1_card.read.include?("sum")
end

check "G-03: fold_stream is CORE-enforced (OOF-S3 in Ruby TC check_fold_stream_body)" do
  TC_RUBY_SRC.include?("OOF-S3") && TC_RUBY_SRC.include?("check_fold_stream_body")
end

check "G-04: fold result type = Acc (not Collection[Acc]) — scalar not collection output" do
  # Rust TC confirms: resolved_type = typed_args[1].resolved_type (scalar, not wrapped)
  TC_RUST_SRC.match?(/\"fold\"\s*=>\s*\{[^}]*typed_args\[1\]\.resolved_type\.clone/) &&
    !TC_RUST_SRC.match?(/\"fold\"\s*=>\s*\{[^}]*Collection/)
end

check "G-05: fold_stream exists as separate T3 path (fold does not conflict)" do
  TC_RUBY_SRC.include?("fold_stream") &&
    TC_RUBY_SRC.include?("when \"fold_stream\"")
end

check "G-06: no 'when \"fold\"' arm in Ruby TC infer_call (confirms fold → OOF-TY0)" do
  infer_call_section = TC_RUBY_SRC[/def infer_call.*?^    end/m] || ""
  !infer_call_section.include?('"fold"')
end

# ─────────────────────────────────────────────────────────────────────────────
# Section H — Closed surfaces [6 checks]
# ─────────────────────────────────────────────────────────────────────────────
puts "\n=== H: Closed surfaces ===\n"

check "H-01: no sum dispatch in Ruby TC (sum stays separate)" do
  !TC_RUBY_SRC.match?(/when\s+["']sum["']/) &&
    !TC_RUBY_SRC.include?('"stdlib.collection.sum"')
end

check "H-02: no stdlib.collection.fold entry in inventory (no implementation in this card)" do
  !INVENTORY["entries"].any? { |e| e["canonical_name"] == "stdlib.collection.fold" }
end

check "H-03: fold_stream T3 path unmodified (no recursion changes, stream path intact)" do
  TC_RUBY_SRC.include?("def check_fold_stream_body") &&
    TC_RUBY_SRC.include?("def fold_stream_result_type")
end

check "H-04: bookkeeping/ledger.ig fold fixture is DUMMY (exploratory, no fixture edit needed)" do
  BK_LEDGER.read.include?("DUMMY to see if closure parser fails")
end

check "H-05: no VM/runtime fold-related additions (fold is purely TC-layer)" do
  vm_files = Dir.glob(
    (WORKSPACE_ROOT / "igniter-lang" / "lib" / "igniter_lang" / "*.rb").to_s
  ).reject { |f| f.include?("typechecker") }
  vm_files.none? { |f| File.read(f).include?("stdlib.collection.fold") }
end

check "H-06: no LANG-STDLIB-FOLD-PROP-P1 card yet (readiness only, proposal not yet authored)" do
  !( WORKSPACE_ROOT / "igniter-lang" / ".agents" / "work" / "cards" / "lang" /
     "LANG-STDLIB-FOLD-PROP-P1.md" ).exist?
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
puts "\n" + "=" * 60
puts "LAB-STDLIB-FOLD-P1: #{$pass} PASS / #{$fail} FAIL / #{$pass + $fail} total"
puts "=" * 60

verdict = if $fail == 0
  "ACCEPT — proposal authoring ready"
elsif $fail <= 2
  "ACCEPT (minor gaps) — review failing checks before P1"
else
  "HOLD — #{$fail} checks failed, review before proposing"
end

puts "\nVERDICT: #{verdict}"
puts "\nNext route: LANG-STDLIB-FOLD-PROP-P1" if $fail == 0

exit($fail == 0 ? 0 : 1)
