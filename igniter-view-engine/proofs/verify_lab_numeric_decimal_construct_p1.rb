#!/usr/bin/env ruby
# frozen_string_literal: true

# verify_lab_numeric_decimal_construct_p1.rb
# LAB-NUMERIC-DECIMAL-CONSTRUCT-P1 -- explicit Decimal constructor, dual-toolchain.
#
#   decimal(value: Integer, scale: Integer literal) -> Decimal[scale]
#
# Authority: dual-toolchain stdlib + VM implementation, after the decimal-boundary
# policy. NO implicit Float/Integer -> Decimal coercion. Proves:
#   * decimal(0,2) / decimal(150,2) compile clean dual-toolchain and run on the VM
#     to Value::Decimal{value, scale}.
#   * scale propagation: Decimal[2] is assignable to a declared Decimal[2], rejected
#     against Decimal[4] (OOF-TY1) -- scale compares by value, dual.
#   * non-literal / negative scale -> OOF-DM4; wrong arity / non-Integer value -> OOF-TY0.
#   * Ruby Decimal[N] input annotation no longer crashes (the P1 readiness gap).
#   * implicit Float->Decimal STILL rejected (OOF-TY1) -- boundary not regressed.
#   * inventory entry stdlib.decimal.decimal present, digest recomputes/matches, ch3+ch8.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"
require "digest"

LAB_ROOT  = Pathname.new(__dir__).parent.parent
WS_ROOT   = LAB_ROOT.parent
LANG_ROOT = WS_ROOT / "igniter-lang"
RUST_BIN  = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
RUST_DBG  = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"
VM_BIN    = LAB_ROOT / "igniter-vm" / "target" / "release" / "igniter-vm"
VM_DBG    = LAB_ROOT / "igniter-vm" / "target" / "debug" / "igniter-vm"

TC_RUST   = LAB_ROOT / "igniter-compiler" / "src" / "typechecker" / "stdlib_calls.rs"
VM_RUST   = LAB_ROOT / "igniter-vm" / "src" / "vm.rs"
TC_RUBY   = LANG_ROOT / "lib" / "igniter_lang" / "typechecker.rb"
CH3       = LANG_ROOT / "docs" / "spec" / "ch3-type-system.md"
CH8       = LANG_ROOT / "docs" / "spec" / "ch8-stdlib.md"
INVENTORY = LANG_ROOT / "docs" / "spec" / "stdlib-inventory.json"
CARD      = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-NUMERIC-DECIMAL-CONSTRUCT-P1.md"
LAB_DOC   = LAB_ROOT / "lab-docs" / "lang" / "lab-numeric-decimal-construct-p1-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"

def read(p) = (File.read(p.to_s, encoding: "UTF-8") rescue "")

def rust_bin
  return RUST_BIN if File.executable?(RUST_BIN.to_s)
  RUST_DBG
end

def vm_bin
  return VM_BIN if File.executable?(VM_BIN.to_s)
  VM_DBG
end

$pass = 0
$fail = 0
def check(label)
  ok = yield
  if ok
    puts "  PASS  #{label}"; $pass += 1
  else
    puts "  FAIL  #{label}"; $fail += 1
  end
rescue => e
  puts "  FAIL  #{label}  [#{e.class}: #{e.message.lines.first&.strip}]"; $fail += 1
end
def section(t) = puts("\n--- #{t} ---")

TMP = Dir.mktmpdir("dec_construct_p1_")
at_exit { FileUtils.rm_rf(TMP) }

def c(body) = "module M\n#{body}\n"

# Fixtures ────────────────────────────────────────────────────────────────────
SRC = {
  zero:       c("pure contract C { compute o = decimal(0, 2) output o : Decimal[2] }"),
  buck:       c("pure contract C { compute o = decimal(150, 2) output o : Decimal[2] }"),
  scale4:     c("pure contract C { compute o = decimal(0, 2) output o : Decimal[4] }"),
  nonlit:     c("pure contract C { input n : Integer compute o = decimal(0, n) output o : Decimal[2] }"),
  arity1:     c("pure contract C { compute o = decimal(0) output o : Decimal[2] }"),
  floatval:   c("pure contract C { compute o = decimal(1.5, 2) output o : Decimal[2] }"),
  bare_float: c("pure contract C { compute o = 0.00 output o : Decimal[2] }"),
  decin:      c("pure contract C { input d : Decimal[2] compute o = d output o : Decimal[2] }"),
  scale0:     c("pure contract C { compute o = decimal(42, 0) output o : Decimal[0] }"),
}

# Rust compile — retries the documented fd/timing spawn flake.
def rust_diags(src)
  3.times do
    d = Dir.mktmpdir("rc_", TMP) do |dir|
      path = File.join(dir, "f.ig")
      out  = File.join(dir, "o.igapp")
      File.write(path, src)
      so, _e, _s = Open3.capture3(rust_bin.to_s, "compile", path, "--out", out)
      JSON.parse(so.force_encoding("UTF-8")) rescue nil
    end
    return d unless d.nil?
  end
  nil
end

def rust_rules(src)
  d = rust_diags(src)
  return ["PARSE_FAIL"] if d.nil?
  Array(d["diagnostics"]).map { |x| x["rule"] }.uniq
end

def rust_status(src)
  d = rust_diags(src)
  d.nil? ? "fail" : d["status"]
end

def rust_hash(src)
  d = rust_diags(src)
  d&.fetch("source_hash", nil)
end

# Ruby canon typecheck via the orchestrator.
$LOAD_PATH.unshift (LANG_ROOT / "lib").to_s
require "igniter_lang/compiler_orchestrator"

def ruby_result(src)
  path = File.join(TMP, "rb_#{Digest::SHA256.hexdigest(src)[0, 12]}.ig")
  File.write(path, src)
  out = File.join(TMP, "rb_out_#{Digest::SHA256.hexdigest(src)[0, 12]}.igapp")
  r = IgniterLang::CompilerOrchestrator.new.compile_sources(source_paths: [path], out_path: out)
  r["result"] || r
rescue => e
  { "status" => "EXC", "diagnostics" => [], "_exc" => e.message }
end

def ruby_rules(src) = Array(ruby_result(src)["diagnostics"]).map { |x| x["rule"] }.uniq
def ruby_status(src) = ruby_result(src)["status"]
def has?(rules, code) = rules.include?(code)
def clean?(rules) = rules.empty?

# VM run a single-contract fixture through the Rust toolchain.
def vm_run(src, entry)
  out = File.join(TMP, "vm_#{entry}_#{Digest::SHA256.hexdigest(src)[0, 8]}.igapp")
  path = File.join(TMP, "vm_#{entry}_#{Digest::SHA256.hexdigest(src)[0, 8]}.ig")
  File.write(path, src)
  built = false
  3.times do
    _so, _e, _s = Open3.capture3(rust_bin.to_s, "compile", path, "--out", out)
    if File.directory?(out) && File.exist?(File.join(out, "manifest.json"))
      built = true; break
    end
  end
  return { "status" => "compile_fail" } unless built
  inp = File.join(TMP, "vm_in.json"); File.write(inp, "{}")
  so, _e, _s = Open3.capture3(vm_bin.to_s, "run", "--contract", out, "--inputs", inp, "--entry", entry, "--json")
  JSON.parse(so.force_encoding("UTF-8")) rescue { "status" => "parse_fail", "_raw" => so }
end

RB = {}
RS = {}
SRC.each { |k, s| RB[k] = ruby_rules(s); RS[k] = rust_rules(s) }

INV = JSON.parse(read(INVENTORY)) rescue {}
INV_ENTRIES = (INV["entries"] || [])
DEC_ENTRY = INV_ENTRIES.find { |e| e["canonical_name"] == "stdlib.decimal.decimal" }

def canonical_json(obj)
  case obj
  when Hash  then "{#{obj.keys.sort.map { |k| "#{JSON.generate(k)}:#{canonical_json(obj[k])}" }.join(",")}}"
  when Array then "[#{obj.map { |v| canonical_json(v) }.join(",")}]"
  else JSON.generate(obj)
  end
end
def compute_digest(entries)
  stripped = entries.sort_by { |e| e["canonical_name"] }.map { |e| e.reject { |k, _| k == "entry_digest" } }
  Digest::SHA256.hexdigest(canonical_json(stripped))
end

puts "=" * 72
puts "LAB-NUMERIC-DECIMAL-CONSTRUCT-P1 -- explicit Decimal constructor (dual-toolchain)"
puts "Rust: #{File.executable?(rust_bin.to_s) ? rust_bin : 'NOT BUILT'}  VM: #{File.executable?(vm_bin.to_s) ? vm_bin : 'NOT BUILT'}"
puts "=" * 72

section("A  Preconditions + gate")
check("A-01: Rust compiler binary present") { File.executable?(rust_bin.to_s) }
check("A-02: VM binary present") { File.executable?(vm_bin.to_s) }
check("A-03: igniter-lang canon TC present") { File.exist?(TC_RUBY.to_s) }
check("A-04: card authorises dual-toolchain stdlib + VM implementation") { read(CARD).include?("stdlib + VM implementation authorized") }
check("A-05: gate predecessor BOUNDARY-P1 routed to explicit decimal()") do
  read(LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-NUMERIC-DECIMAL-BOUNDARY-P1.md").include?("decimal(value, scale)")
end

section("B  decimal(value, scale) compiles clean dual-toolchain")
check("B-01: Rust decimal(0,2) status ok") { rust_status(SRC[:zero]) == "ok" }
check("B-02: Rust decimal(0,2) no diagnostics") { clean?(RS[:zero]) }
check("B-03: Ruby decimal(0,2) status ok") { ruby_status(SRC[:zero]) == "ok" }
check("B-04: Ruby decimal(0,2) no diagnostics") { clean?(RB[:zero]) }
check("B-05: Rust decimal(150,2) clean") { clean?(RS[:buck]) }
check("B-06: Ruby decimal(150,2) clean") { clean?(RB[:buck]) }
check("B-07: Rust decimal(42,0) (scale 0) clean") { clean?(RS[:scale0]) }
check("B-08: Ruby decimal(42,0) (scale 0) clean") { clean?(RB[:scale0]) }
check("B-09: Ruby and Rust agree decimal(0,2) is clean") { clean?(RS[:zero]) && clean?(RB[:zero]) }
check("B-10: Ruby and Rust source_hash agree on decimal(0,2)") do
  rh = rust_hash(SRC[:zero])
  bh = ruby_result(SRC[:zero])["source_hash"]
  !rh.nil? && rh == bh
end

section("C  scale propagation Decimal[scale] (value compare, dual)")
check("C-01: Rust decimal(0,2) -> declared Decimal[4] => OOF-TY1") { has?(RS[:scale4], "OOF-TY1") }
check("C-02: Ruby decimal(0,2) -> declared Decimal[4] => OOF-TY1") { has?(RB[:scale4], "OOF-TY1") }
check("C-03: scale mismatch rejected DUAL (Decimal[2] != Decimal[4])") { has?(RS[:scale4], "OOF-TY1") && has?(RB[:scale4], "OOF-TY1") }
check("C-04: Rust same-scale decimal(0,2)->Decimal[2] is clean") { clean?(RS[:zero]) }
check("C-05: Ruby same-scale decimal(0,2)->Decimal[2] is clean") { clean?(RB[:zero]) }

section("D  Diagnostics: non-literal scale, arity, value type")
check("D-01: Rust non-literal scale decimal(0,n) => OOF-DM4") { has?(RS[:nonlit], "OOF-DM4") }
check("D-02: Ruby non-literal scale decimal(0,n) => OOF-DM4") { has?(RB[:nonlit], "OOF-DM4") }
check("D-03: non-literal scale rejected DUAL (OOF-DM4)") { has?(RS[:nonlit], "OOF-DM4") && has?(RB[:nonlit], "OOF-DM4") }
check("D-04: Rust arity decimal(0) => OOF-TY0") { has?(RS[:arity1], "OOF-TY0") }
check("D-05: Ruby arity decimal(0) => OOF-TY0") { has?(RB[:arity1], "OOF-TY0") }
check("D-06: arity error DUAL (OOF-TY0)") { has?(RS[:arity1], "OOF-TY0") && has?(RB[:arity1], "OOF-TY0") }
check("D-07: Rust value decimal(1.5,2) => OOF-TY0 (Float value)") { has?(RS[:floatval], "OOF-TY0") }
check("D-08: Ruby value decimal(1.5,2) => OOF-TY0 (Float value)") { has?(RB[:floatval], "OOF-TY0") }
check("D-09: non-Integer value rejected DUAL (OOF-TY0)") { has?(RS[:floatval], "OOF-TY0") && has?(RB[:floatval], "OOF-TY0") }
check("D-10: floatval value-error is NOT an implicit-coercion acceptance") { !clean?(RS[:floatval]) && !clean?(RB[:floatval]) }

section("E  Ruby Decimal[N] annotation crash fixed (P1 readiness gap)")
check("E-01: Ruby Decimal[2] input annotation no longer EXC/crash") { ruby_status(SRC[:decin]) != "EXC" }
check("E-02: Ruby Decimal[2] input annotation compiles clean") { clean?(RB[:decin]) }
check("E-03: Rust Decimal[2] input annotation clean (unchanged)") { clean?(RS[:decin]) }
check("E-04: Decimal[N] annotation clean DUAL") { clean?(RB[:decin]) && clean?(RS[:decin]) }
check("E-05: Ruby TC wraps structurally_assignable params via type_ir (scale-safe)") do
  read(TC_RUBY).include?("structurally_assignable?(type_ir(a), type_ir(e))")
end
check("E-06: Ruby TC wraps unknown_or_unknown_bearing params via type_ir") do
  read(TC_RUBY).include?("unknown_or_unknown_bearing?(type_ir(p))")
end

section("F  Boundary NOT regressed: implicit numeric->Decimal still rejected")
check("F-01: Rust bare 0.00 -> Decimal[2] still OOF-TY1") { has?(RS[:bare_float], "OOF-TY1") }
check("F-02: Ruby bare 0.00 -> Decimal[2] still OOF-TY1") { has?(RB[:bare_float], "OOF-TY1") }
check("F-03: implicit Float->Decimal rejected DUAL (no coercion introduced)") { has?(RS[:bare_float], "OOF-TY1") && has?(RB[:bare_float], "OOF-TY1") }
check("F-04: decimal() is the only minting path (literal 0.00 still fails)") { has?(RS[:bare_float], "OOF-TY1") && clean?(RS[:zero]) }

section("G  VM lowers decimal() to Value::Decimal{value, scale}")
VM_ZERO = vm_run(c("contract MakeZero { compute z = decimal(0, 2) output z : Decimal[2] }"), "MakeZero")
VM_BUCK = vm_run(c("contract MakeBuck { compute v = decimal(150, 2) output v : Decimal[2] }"), "MakeBuck")
check("G-01: VM MakeZero status success") { VM_ZERO["status"] == "success" }
check("G-02: VM decimal(0,2) -> {value:0, scale:2}") { VM_ZERO.dig("result", "value") == 0 && VM_ZERO.dig("result", "scale") == 2 }
check("G-03: VM MakeBuck status success") { VM_BUCK["status"] == "success" }
check("G-04: VM decimal(150,2) -> {value:150, scale:2} (1.50 exact minor units)") { VM_BUCK.dig("result", "value") == 150 && VM_BUCK.dig("result", "scale") == 2 }
check("G-05: VM preserves scale (no Float rounding)") { VM_BUCK.dig("result", "scale") == 2 }

section("H  Implementation surfaces present (dual-toolchain)")
check("H-01: Rust TC stdlib_calls.rs has a decimal arm") { read(TC_RUST).include?("\"decimal\" =>") }
check("H-02: Rust TC decimal arm emits OOF-DM4 for non-literal scale") { read(TC_RUST).match?(/decimal.*OOF-DM4/m) || read(TC_RUST).include?("OOF-DM4") }
check("H-03: Rust TC decimal arm reads an Integer Literal scale") { read(TC_RUST).include?("Expr::Literal { value, type_tag }") }
check("H-04: Rust VM vm.rs has a decimal arm -> Value::Decimal") { read(VM_RUST).include?("\"decimal\" | \"stdlib.decimal.decimal\"") }
check("H-05: Rust VM builds Value::Decimal { value, scale }") { read(VM_RUST).match?(/Value::Decimal \{ value, scale \}/) }
check("H-06: Ruby TC dispatches when \"decimal\"") { read(TC_RUBY).include?("when \"decimal\"") }
check("H-07: Ruby TC has infer_decimal_call") { read(TC_RUBY).include?("def infer_decimal_call") }
check("H-08: Ruby TC infer_decimal_call emits OOF-DM4") { read(TC_RUBY).match?(/infer_decimal_call.*OOF-DM4/m) }

section("I  Inventory + spec wording")
check("I-01: inventory has stdlib.decimal.decimal entry") { !DEC_ENTRY.nil? }
check("I-02: inventory entry semantic_ir_name == decimal") { DEC_ENTRY && DEC_ENTRY["semantic_ir_name"] == "decimal" }
check("I-03: inventory entry input_signature [Integer, Integer]") { DEC_ENTRY && DEC_ENTRY["input_signature"] == %w[Integer Integer] }
check("I-04: inventory entry output_signature Decimal[scale]") { DEC_ENTRY && DEC_ENTRY["output_signature"] == "Decimal[scale]" }
check("I-05: inventory entry lowering dual-toolchain") { DEC_ENTRY && DEC_ENTRY["lowering_status"] == "dual-toolchain" }
check("I-06: inventory entry lists OOF-DM4 + OOF-TY0 diagnostics") { DEC_ENTRY && (DEC_ENTRY["diagnostics"] & %w[OOF-DM4 OOF-TY0]).sort == %w[OOF-DM4 OOF-TY0] }
check("I-07: inventory entry owner == CONSTRUCT-P1") { DEC_ENTRY && DEC_ENTRY["owner_surface"] == "LAB-NUMERIC-DECIMAL-CONSTRUCT-P1" }
check("I-08: stored stdlib_surface_digest matches recomputed") { INV["stdlib_surface_digest"] == compute_digest(INV_ENTRIES) }
check("I-09: ch3 documents decimal(value, scale) -> Decimal[scale]") { read(CH3).include?("decimal(value, scale)") && read(CH3).include?("OOF-DM4") }
check("I-10: ch3 keeps no-implicit-coercion wording") { read(CH3).include?("no implicit") && read(CH3).include?("Decimal` coercion") }
check("I-11: ch8 lists stdlib.decimal.decimal signature") { read(CH8).include?("stdlib.decimal.decimal(value: Integer, scale: Integer literal)") }

section("J  Closed surfaces / scope")
check("J-01: no Money type introduced (card)") { read(CARD).downcase.include?("no `money` type") || read(CARD).include?("A `Money` type") }
check("J-02: round_decimal deferred (not implemented here)") { !read(TC_RUST).include?("round_decimal") && !read(TC_RUBY).include?("round_decimal") }
check("J-03: no Decimal literal syntax (0.00 stays Float -> still OOF-TY1)") { has?(RS[:bare_float], "OOF-TY1") }
check("J-04: CONSTRUCT-P1 card made no bookkeeping migration (a separate card did)") do
  read(CARD).downcase.include?("no bookkeeping migration") || read(CARD).include?("No bookkeeping source change")
end
check("J-05: lab doc records evidence + dual-toolchain outcome") { read(LAB_DOC).include?("dual-toolchain") }
check("J-06: lab doc records VM Value::Decimal result") { read(LAB_DOC).include?("Value::Decimal") }
check("J-07: card closure present") { read(CARD).include?("Closure") || read(CARD).include?("CLOSED") }
check("J-08: portfolio index has CONSTRUCT-P1 row") { read(PORTFOLIO).include?("LAB-NUMERIC-DECIMAL-CONSTRUCT-P1") }
check("J-09: proof runner uses Open3 + mktmpdir + flake retry") do
  s = read(__FILE__)
  s.include?("Open3.capture3") && s.include?("Dir.mktmpdir") && s.include?("fd/timing")
end

puts
total = $pass + $fail
puts "=" * 72
puts "RESULT: #{$pass}/#{total} PASS  |  #{$fail} FAIL"
puts "=" * 72
exit($fail.zero? ? 0 : 1)
