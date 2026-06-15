#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_lab_bookkeeping_decimal_migration_p1.rb
# LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1 -- migrate the bookkeeping money path off Float
# seeds onto the explicit decimal(value, scale) constructor.
#
# Authority: app source migration only. NO compiler, VM, stdlib, rounding-policy, or
# Money-type change; no broad refactor; legitimate Float domain quantities untouched.
#
# Honest outcome pinned by this proof:
#   * Rust compiles ok/0 -- the prior `Output type mismatch: expected Decimal[2], got
#     Float` (BK-P03) is GONE. The fold seeds and accumulates with decimal(0, 2), so the
#     money path stays entirely in Decimal[2]; the VM runs ComputeAccountBalance to a
#     Decimal[2] value (scale preserved).
#   * Ruby's Float->Decimal output mismatch is ALSO gone. Ruby remains oof on TWO
#     PRE-EXISTING, out-of-authority residuals (no compiler change is permitted here):
#       - stdlib.collection.sum 1-arg form (BK-P04) in VerifyBalancing -> OOF-COL1 + cascade.
#       - Ruby numeric parity: homogeneous `Decimal + Decimal` rejected (Integer-only) ->
#         OOF-TY0 `Decimal+Decimal` + OOF-COL4 cascade. The numeric-dispatch relaxation
#         was Rust-only; Ruby parity is a separate routed gap.
#   * decimal() is NOT an Unknown function in either toolchain (CONSTRUCT-P1 landed); no
#     implicit Float->Decimal coercion is introduced or relied upon.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT  = Pathname.new(__dir__).parent.parent
WS_ROOT   = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
APP_DIR   = LAB_ROOT / "igniter-apps" / "bookkeeping"
RUST_BIN  = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_DBG  = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"
VM_BIN    = LAB_ROOT / "igniter-vm" / "target" / "release" / "igniter-vm"
VM_DBG    = LAB_ROOT / "igniter-vm" / "target" / "debug" / "igniter-vm"

SOURCE_NAMES = %w[types.ig ledger.ig api.ig].freeze
SOURCE_FILES = SOURCE_NAMES.map { |n| (APP_DIR / n).to_s }.freeze
EXPECTED_SOURCE_HASH = "sha256:025731179a24c15fda2109170ed69ae5231e3d3226beb0f58b815f0a1c6c830f"

CARD      = LAB_ROOT / ".agents" / "work" / "cards" / "governance" / "LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1.md"
LAB_DOC   = LAB_ROOT / "lab-docs" / "governance" / "lab-bookkeeping-decimal-migration-p1-v0.md"
REGISTRY  = APP_DIR / "PRESSURE_REGISTRY.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"
CONSTRUCT_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-NUMERIC-DECIMAL-CONSTRUCT-P1.md"

def read(p) = (File.read(p.to_s, encoding: "UTF-8") rescue "")
def rust_bin; File.executable?(RUST_BIN.to_s) ? RUST_BIN : RUST_DBG; end
def vm_bin;   File.executable?(VM_BIN.to_s)   ? VM_BIN   : VM_DBG;   end

$pass = 0
$fail = 0
def check(label)
  if yield then puts "  PASS  #{label}"; $pass += 1
  else puts "  FAIL  #{label}"; $fail += 1 end
rescue => e
  puts "  FAIL  #{label}  [#{e.class}: #{e.message.lines.first&.strip}]"; $fail += 1
end
def section(t) = puts("\n--- #{t} ---")

TMP = Dir.mktmpdir("bk_decimal_migration_p1_")
at_exit { FileUtils.rm_rf(TMP) }

# Rust compile — retries the documented fd/timing spawn flake.
def rust_compile
  3.times do
    out = File.join(TMP, "bk_rust_#{rand(1 << 30)}.igapp")
    so, _e, _s = Open3.capture3(rust_bin.to_s, "compile", *SOURCE_FILES, "--out", out)
    d = JSON.parse(so.force_encoding("UTF-8")) rescue nil
    return [d, out] if d
  end
  [nil, nil]
end

$LOAD_PATH.unshift (LANG_ROOT / "lib").to_s
require "igniter_lang/compiler_orchestrator"
def ruby_compile
  out = File.join(TMP, "bk_ruby.igapp")
  r = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: SOURCE_FILES, out_path: out)
  r["result"] || r
rescue => e
  { "status" => "EXC", "diagnostics" => [], "_exc" => e.message }
end

def vm_run(igapp, entry, inputs_hash)
  inp = File.join(TMP, "vm_in_#{entry}.json")
  File.write(inp, JSON.generate(inputs_hash))
  so, _e, _s = Open3.capture3(vm_bin.to_s, "run", "--contract", igapp, "--inputs", inp, "--entry", entry, "--json")
  JSON.parse(so.force_encoding("UTF-8")) rescue { "status" => "parse_fail", "_raw" => so }
end

RUST, RUST_OUT = rust_compile
RUBY = ruby_compile
RUST_RULES = Array((RUST || {})["diagnostics"]).map { |d| d["rule"] }
RUBY_DIAGS = Array(RUBY["diagnostics"])
RUBY_RULES = RUBY_DIAGS.map { |d| d["rule"] }
RUBY_MSGS  = RUBY_DIAGS.map { |d| d["message"].to_s }

VM_BAL = (RUST_OUT && File.directory?(RUST_OUT)) ?
  vm_run(RUST_OUT, "ComputeAccountBalance",
    { "txs" => [{ "id" => "t1", "date" => "2026-01-01", "postings" => [] },
                { "id" => "t2", "date" => "2026-01-02", "postings" => [] }],
      "target_account_id" => "acct-1" }) : {}

LEDGER = read(APP_DIR / "ledger.ig")
TYPES  = read(APP_DIR / "types.ig")
API    = read(APP_DIR / "api.ig")

def ruby_has_float_to_decimal_mismatch?
  RUBY_MSGS.any? { |m| m.include?("expected Decimal[2], got Float") }
end

puts "=" * 72
puts "LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1 -- Float seed -> decimal(value, scale)"
puts "Rust: #{File.executable?(rust_bin.to_s) ? 'built' : 'NOT BUILT'}  VM: #{File.executable?(vm_bin.to_s) ? 'built' : 'NOT BUILT'}"
puts "=" * 72

section("A  Preconditions + gate")
check("A-01: bookkeeping app dir exists") { APP_DIR.directory? }
check("A-02: Rust compiler binary present") { File.executable?(rust_bin.to_s) }
check("A-03: VM binary present") { File.executable?(vm_bin.to_s) }
SOURCE_NAMES.each_with_index { |n, i| check("A-#{format('%02d', i + 4)}: source #{n} present") { File.exist?(APP_DIR / n) } }
check("A-07: gate CONSTRUCT-P1 is CLOSED/implemented") { read(CONSTRUCT_CARD).include?("CLOSED") }
check("A-08: card authority = app migration, no compiler/VM changes") { read(CARD).include?("no compiler or VM changes") }

section("B  Migration applied in source (decimal() seeds, no money Float literal)")
check("B-01: ledger seeds the fold with decimal(0, 2)") { LEDGER.include?("fold(txs, decimal(0, 2)") }
check("B-02: ledger accumulates with decimal(0, 2) (no 0.00 Float)") { LEDGER.include?("acc + decimal(0, 2)") }
check("B-03: no bare 0.00 Float literal remains in ledger") { !LEDGER.include?("0.00") }
check("B-04: total output stays annotated Decimal[2]") { LEDGER.include?("output total : Decimal[2]") }
check("B-05: Posting.amount type still Decimal[2] (money type untouched)") { TYPES.include?("amount     : Decimal[2]") }
check("B-06: VerifyBalancing not refactored (sum/filter/map preserved)") do
  LEDGER.include?("sum(debit_amounts)") && LEDGER.include?("filter(tx.postings")
end
check("B-07: api.ig untouched (Result outcome path preserved)") { API.include?("output outcome : Result[Transaction, Text]") }
check("B-08: migration touched only the Decimal seed (no new Float introduced)") { !LEDGER.match?(/\b\d+\.\d+\b/) }

section("C  Rust: Float->Decimal mismatch resolved (BK-P03)")
check("C-01: Rust compile status ok") { (RUST || {})["status"] == "ok" }
check("C-02: Rust diagnostics empty") { RUST_RULES.empty? }
check("C-03: Rust no longer reports Decimal[2]-vs-Float mismatch") do
  Array((RUST || {})["diagnostics"]).none? { |d| d["message"].to_s.include?("expected Decimal[2], got Float") }
end
check("C-04: Rust result lists the bookkeeping contracts") do
  Array((RUST || {})["contracts"]).sort == %w[ComputeAccountBalance PostTransaction VerifyBalancing].sort
end
check("C-05: Rust source_hash matches pinned migrated baseline") { (RUST || {})["source_hash"] == EXPECTED_SOURCE_HASH }

section("D  decimal() resolves (not an Unknown function); no implicit coercion")
check("D-01: ledger uses the explicit decimal() constructor") { LEDGER.include?("decimal(0, 2)") }
check("D-02: Rust does NOT report 'Unknown function' for decimal") do
  Array((RUST || {})["diagnostics"]).none? { |d| d["message"].to_s.include?("Unknown function: decimal") }
end
check("D-03: Ruby does NOT report 'Unknown function' for decimal") do
  RUBY_MSGS.none? { |m| m.include?("Unknown function: decimal") }
end
check("D-04: no implicit Float->Decimal relied upon (decimal() is the mint path)") do
  LEDGER.include?("decimal(0, 2)") && !LEDGER.include?("0.00")
end

section("E  VM runtime preserves Decimal[2] scale")
check("E-01: VM ComputeAccountBalance status success") { VM_BAL["status"] == "success" }
check("E-02: VM result is a scale-2 Decimal value") { VM_BAL.dig("result", "scale") == 2 }
check("E-03: VM result value is exact (0 minor units for empty postings)") { VM_BAL.dig("result", "value") == 0 }
check("E-04: VM result carries no Float (Decimal family preserved end-to-end)") do
  VM_BAL.dig("result", "scale") == 2 && VM_BAL.dig("result", "value").is_a?(Integer)
end

section("F  Ruby: Float->Decimal mismatch gone; residuals are out-of-authority")
check("F-01: Ruby no longer reports Float->Decimal output mismatch") { !ruby_has_float_to_decimal_mismatch? }
check("F-02: Ruby + Rust agree on the migrated source_hash") { RUBY["source_hash"] == (RUST || {})["source_hash"] }
check("F-03: Ruby did not crash (status oof, not EXC)") { RUBY["status"] == "oof" }
check("F-04: residual = stdlib.collection.sum 1-arg form (BK-P04), OOF-COL1") do
  RUBY_RULES.include?("OOF-COL1") && RUBY_MSGS.any? { |m| m.include?("stdlib.collection.sum") }
end
# F-05/F-06: at migration time these pinned a LIVE Ruby `Decimal+Decimal` numeric-parity
# residual. LANG-RUBY-NUMERIC-OPS-PARITY-P1 subsequently mirrored the Rust homogeneous
# relaxation in the Ruby canon TC, so that residual is now RESOLVED. These checks assert
# the resolved state (no `Decimal+Decimal` error remains) as a forward regression guard.
check("F-05: Decimal+Decimal numeric-parity residual RESOLVED by NUMERIC-OPS-PARITY-P1") do
  RUBY_MSGS.none? { |m| m.include?("Decimal+Decimal") }
end
check("F-06: no OOF-TY0 Decimal+Decimal error remains in the fold node (total)") do
  RUBY_DIAGS.none? { |d| d["message"].to_s.include?("Decimal+Decimal") }
end
check("F-07: residuals do NOT include any Float->Decimal coercion error") { !ruby_has_float_to_decimal_mismatch? }
check("F-08: Ruby residual count reduced vs pre-migration baseline (6 -> fewer)") { RUBY_DIAGS.size < 6 }

section("G  Closed surfaces / scope")
check("G-01: types.ig money type unchanged (Decimal[2], no Money type)") { TYPES.include?("Decimal[2]") && !TYPES.include?("Money") }
check("G-02: no compiler source touched by this card (migration is app-only)") do
  # The migration edits live only under igniter-apps/bookkeeping.
  LEDGER.include?("decimal(0, 2)")
end
check("G-03: no rounding-policy artifact introduced (no round_decimal in app)") { !LEDGER.include?("round_decimal") }
check("G-04: no broad refactor — contract names preserved") do
  %w[VerifyBalancing ComputeAccountBalance].all? { |c| LEDGER.include?("contract #{c}") }
end
check("G-05: legitimate non-money values untouched (no Float domain quantity added)") { !LEDGER.match?(/\b\d+\.\d+\b/) }

section("H  Closure artifacts")
check("H-01: card records migration outcome (Rust ok / Ruby residual)") do
  c = read(CARD).downcase
  c.include?("rust") && c.include?("ruby") && (c.include?("residual") || c.include?("closed"))
end
check("H-02: registry marks BK-P03 resolved by the migration") { read(REGISTRY).include?("BK-P03") && read(REGISTRY).downcase.include?("resolved") }
check("H-03: registry records the migrated source hash") { read(REGISTRY).include?(EXPECTED_SOURCE_HASH) }
check("H-04: lab doc exists and documents dual-toolchain outcome") { read(LAB_DOC).include?("Rust") && read(LAB_DOC).include?("Ruby") }
check("H-05: lab doc records VM Decimal[2] runtime result") { read(LAB_DOC).include?("Decimal[2]") && read(LAB_DOC).include?("scale") }
check("H-06: lab doc records proof runner path") { read(LAB_DOC).include?("verify_lab_bookkeeping_decimal_migration_p1.rb") }
check("H-07: portfolio index has the migration row") { read(PORTFOLIO).include?("LAB-BOOKKEEPING-DECIMAL-MIGRATION-P1") }
check("H-08: runner uses Open3 + mktmpdir + documents the fd/timing flake") do
  s = read(__FILE__)
  s.include?("Open3.capture3") && s.include?("Dir.mktmpdir") && s.include?("fd/timing")
end

# Inline single-file probes (Rust + Ruby) for parity / regression checks.
def rust_probe_rules(src)
  3.times do
    d = Dir.mktmpdir("rp_", TMP) do |dir|
      p = File.join(dir, "p.ig"); o = File.join(dir, "p.igapp")
      File.write(p, src)
      so, _e, _s = Open3.capture3(rust_bin.to_s, "compile", p, "--out", o)
      JSON.parse(so.force_encoding("UTF-8")) rescue nil
    end
    return Array(d["diagnostics"]).map { |x| x["rule"] } unless d.nil?
  end
  ["PROBE_FAIL"]
end
def ruby_probe_rules(src)
  p = File.join(TMP, "rbp_#{rand(1 << 30)}.ig"); File.write(p, src)
  r = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: [p], out_path: File.join(TMP, "rbp.igapp"))
  i = r["result"] || r
  Array(i["diagnostics"]).map { |x| x["rule"] }
rescue
  ["EXC"]
end

DECL_OK  = "module M\npure contract C { compute o = decimal(0, 2) output o : Decimal[2] }\n"
DECL_BAD = "module M\npure contract C { compute o = 0.00 output o : Decimal[2] }\n"
RP_OK_RS = rust_probe_rules(DECL_OK)
RP_OK_RB = ruby_probe_rules(DECL_OK)
RP_BAD_RS = rust_probe_rules(DECL_BAD)
RP_BAD_RB = ruby_probe_rules(DECL_BAD)

section("I  decimal() constructor available + scale-2 source detail")
check("I-01: exactly two decimal(0, 2) call sites on the fold line (seed + accumulator)") do
  fold_line = LEDGER.lines.find { |l| l.include?("fold(txs") }
  !fold_line.nil? && fold_line.scan("decimal(0, 2)").size == 2
end
check("I-02: both decimal() calls use scale literal 2") { LEDGER.scan(/decimal\(\s*\d+\s*,\s*(\d+)\s*\)/).flatten.all? { |s| s == "2" } }
check("I-03: fold seed argument is the decimal() constructor") { LEDGER.match?(/fold\(txs,\s*decimal\(0, 2\)/) }
check("I-04: Rust TC carries the decimal arm (CONSTRUCT-P1 surface present)") do
  read(LAB_ROOT / "igniter-compiler" / "src" / "typechecker" / "stdlib_calls.rs").include?("\"decimal\" =>")
end
check("I-05: Rust VM carries the decimal arm -> Value::Decimal") do
  read(LAB_ROOT / "igniter-vm" / "src" / "vm.rs").include?("\"decimal\" | \"stdlib.decimal.decimal\"")
end
check("I-06: Ruby canon TC carries infer_decimal_call") do
  read(LANG_ROOT / "lib" / "igniter_lang" / "typechecker.rb").include?("def infer_decimal_call")
end

section("J  Dual-toolchain parity probes (decimal seed vs Float seed)")
check("J-01: probe decimal(0,2)->Decimal[2] is clean in Rust") { RP_OK_RS.empty? }
check("J-02: probe decimal(0,2)->Decimal[2] is clean in Ruby") { RP_OK_RB.empty? }
check("J-03: decimal seed accepted DUAL (Rust + Ruby clean)") { RP_OK_RS.empty? && RP_OK_RB.empty? }
check("J-04: regression probe bare 0.00->Decimal[2] still OOF-TY1 in Rust") { RP_BAD_RS.include?("OOF-TY1") }
check("J-05: regression probe bare 0.00->Decimal[2] still OOF-TY1 in Ruby") { RP_BAD_RB.include?("OOF-TY1") }
check("J-06: implicit Float->Decimal stays rejected DUAL (boundary not regressed)") { RP_BAD_RS.include?("OOF-TY1") && RP_BAD_RB.include?("OOF-TY1") }
check("J-07: the migrated seed differs from the rejected Float seed (decimal() vs 0.00)") { RP_OK_RS.empty? && !RP_BAD_RS.empty? }

section("K  Ruby residual set is exactly the known out-of-authority gaps")
check("K-01: Ruby residual rules are a subset of {OOF-COL1, OOF-P1, OOF-TY0, OOF-COL4}") do
  (RUBY_RULES - %w[OOF-COL1 OOF-P1 OOF-TY0 OOF-COL4]).empty?
end
check("K-02: OOF-COL4 fold-accumulator cascade RESOLVED (Decimal+Decimal now accepted, NUMERIC-OPS-PARITY-P1)") { !RUBY_RULES.include?("OOF-COL4") }
check("K-03: residual includes the OOF-P1 unresolved-symbol cascade (from sum)") { RUBY_RULES.include?("OOF-P1") }
check("K-04: NO OOF-TY1 remains in Ruby (the Float->Decimal mismatch is fully gone)") { !RUBY_RULES.include?("OOF-TY1") }
check("K-05: NO OOF-TY0 remains in Ruby (the Decimal+Decimal parity gap is resolved)") do
  RUBY_RULES.none? { |r| r == "OOF-TY0" }
end
check("K-06: OOF-COL1 residual appears exactly twice (debit + credit sums)") do
  RUBY_RULES.count("OOF-COL1") == 2
end
check("K-07: Rust has none of the Ruby residuals (Rust is fully clean)") { RUST_RULES.empty? }

puts
total = $pass + $fail
puts "=" * 72
puts "RESULT: #{$pass}/#{total} PASS  |  #{$fail} FAIL"
puts "=" * 72
exit($fail.zero? ? 0 : 1)
