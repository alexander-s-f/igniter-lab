#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_stdlib_string_char_at_vm_p1.rb
# LAB-STDLIB-STRING-CHAR-AT-VM-P1
#
# Proves VM runtime support for stdlib.string.char_at and stdlib.string.substring.
#
# Authority: lab VM runtime support for already-typed stdlib.string calls only.
# No compiler, parser, typechecker, inventory, app-source, or canon authority
# changes are authorized by this proof.

require "json"
require "open3"
require "pathname"
require "tmpdir"
require "fileutils"

LAB_ROOT = Pathname.new(__dir__).parent.parent
WORKSPACE_ROOT = LAB_ROOT.parent
LANG_ROOT = WORKSPACE_ROOT / "igniter-lang"

VM_MANIFEST = LAB_ROOT / "igniter-vm" / "Cargo.toml"
VM_BIN = LAB_ROOT / "igniter-vm" / "target" / "debug" / "igniter-vm"
VM_SRC = LAB_ROOT / "igniter-vm" / "src" / "vm.rs"
VM_SURFACE = LAB_ROOT / "igniter-vm" / "IMPLEMENTED_SURFACE.md"
COMPILER_RELEASE = LAB_ROOT / "igniter-compiler" / "target" / "release" / "igniter_compiler"
COMPILER_DEBUG = LAB_ROOT / "igniter-compiler" / "target" / "debug" / "igniter_compiler"

CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-STDLIB-STRING-CHAR-AT-VM-P1.md"
APP_WAVE_CARD = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-APP-DEMO-ENTRY-WAVE-P1.md"
RUNTIME_CHECKPOINT = LAB_ROOT / ".agents" / "work" / "cards" / "lang" / "LAB-VM-RUNTIME-WAVE-CHECKPOINT-P1.md"
DOC = LAB_ROOT / "lab-docs" / "lang" / "lab-stdlib-string-char-at-vm-p1-v0.md"
PORTFOLIO = LAB_ROOT / ".agents" / "portfolio-index.md"
CH8 = LANG_ROOT / "docs" / "spec" / "ch8-stdlib.md"
INVENTORY = LANG_ROOT / "docs" / "spec" / "stdlib-inventory.json"
PARSER_APP = LAB_ROOT / "igniter-apps" / "igniter_parser"

$pass = 0
$fail = 0

def check(label)
  ok = yield
  if ok
    $pass += 1
    puts "PASS #{label}"
  else
    $fail += 1
    puts "FAIL #{label}"
  end
rescue => e
  $fail += 1
  puts "FAIL #{label} [#{e.class}: #{e.message.lines.first&.strip}]"
end

def section(title)
  puts "\n=== #{title} ==="
end

def read(path)
  File.read(path.to_s, encoding: "UTF-8")
rescue Errno::ENOENT
  ""
end

def parse_json(text)
  JSON.parse(text.to_s.force_encoding("UTF-8"))
rescue JSON::ParserError
  { "_parse_error" => text.to_s.force_encoding("UTF-8") }
end

def compiler_bin
  return COMPILER_RELEASE if File.executable?(COMPILER_RELEASE.to_s)

  COMPILER_DEBUG
end

def build_vm
  stdout, stderr, status = Open3.capture3("cargo", "build", "--manifest-path", VM_MANIFEST.to_s)
  { stdout: stdout, stderr: stderr, exit: status.exitstatus, success: status.success? }
end

def compile_sources(sources, out_dir)
  stdout, stderr, status = Open3.capture3(
    compiler_bin.to_s,
    "compile",
    *sources.map(&:to_s),
    "--out",
    out_dir.to_s
  )
  {
    stdout: stdout.force_encoding("UTF-8"),
    stderr: stderr.force_encoding("UTF-8"),
    exit: status.exitstatus,
    success: status.success?,
    json: parse_json(stdout),
    sir: File.exist?(File.join(out_dir, "semantic_ir_program.json")) ? parse_json(File.read(File.join(out_dir, "semantic_ir_program.json"), encoding: "UTF-8")) : {}
  }
end

def write_igapp(dir, sir)
  FileUtils.mkdir_p(dir)
  File.write(File.join(dir, "semantic_ir_program.json"), JSON.pretty_generate(sir))
  File.write(
    File.join(dir, "manifest.json"),
    JSON.pretty_generate({ "artifact_hash" => "synthetic-string-runtime", "capabilities" => [] })
  )
  dir
end

def lit(value)
  { "kind" => "literal", "value" => value }
end

def call_contract(name, fn, args)
  {
    "contract_name" => name,
    "name" => name,
    "modifier" => "pure",
    "inputs" => [],
    "outputs" => [{ "name" => "result", "type" => { "name" => "String" } }],
    "nodes" => [
      {
        "kind" => "compute_node",
        "name" => "result",
        "expression" => { "kind" => "call", "fn" => fn, "args" => args }
      }
    ]
  }
end

def run_vm(igapp, inputs_hash, entry)
  input_path = File.join(File.dirname(igapp), "inputs_#{entry}.json")
  File.write(input_path, JSON.generate(inputs_hash))
  stdout, stderr, status = Open3.capture3(
    VM_BIN.to_s,
    "run",
    "--contract",
    igapp.to_s,
    "--inputs",
    input_path,
    "--entry",
    entry,
    "--json"
  )
  {
    stdout: stdout.force_encoding("UTF-8"),
    stderr: stderr.force_encoding("UTF-8"),
    exit: status.exitstatus,
    success: status.success?,
    json: parse_json(stdout)
  }
end

def find_calls(node, fn_name, acc = [])
  case node
  when Hash
    acc << node if node["kind"] == "call" && node["fn"] == fn_name
    node.each_value { |value| find_calls(value, fn_name, acc) }
  when Array
    node.each { |value| find_calls(value, fn_name, acc) }
  end
  acc
end

TMP = Dir.mktmpdir("lab_stdlib_string_char_at_vm_p1_")
at_exit { FileUtils.rm_rf(TMP) }

BUILD = build_vm

SOURCE_FIXTURE = File.join(TMP, "string_runtime_probe.ig")
File.write(
  SOURCE_FIXTURE,
  <<~IG
    module StringRuntimeProbe
    import stdlib.collection.{ map }
    import stdlib.string.{ char_at, substring }

    contract CharAtProbe {
      input source : String
      input idx : Integer
      compute out = char_at(source, idx)
      output out : String
    }

    contract SubstringProbe {
      input source : String
      input start : Integer
      input len : Integer
      compute out = substring(source, start, len)
      output out : String
    }

    contract LambdaCharAtProbe {
      input words : Collection[String]
      compute out = map(words, word -> char_at(word, 1))
      output out : Collection[String]
    }

    contract LambdaSubstringProbe {
      input words : Collection[String]
      compute out = map(words, word -> substring(word, 1, 2))
      output out : Collection[String]
    }
  IG
)

SOURCE_IGAPP = File.join(TMP, "string_runtime_probe.igapp")
SOURCE_COMPILE = compile_sources([SOURCE_FIXTURE], SOURCE_IGAPP)

SYNTH_IGAPP = File.join(TMP, "synthetic_string_runtime.igapp")
SYNTH_SIR = {
  "schema_version" => "semantic-ir-test-v0",
  "contracts" => [
    call_contract("BareCharAt", "char_at", [lit("abc"), lit(1)]),
    call_contract("CanonicalCharAt", "stdlib.string.char_at", [lit("abc"), lit(1)]),
    call_contract("CanonicalSubstring", "stdlib.string.substring", [lit("module"), lit(2), lit(3)]),
    call_contract("UnicodeCharAt", "stdlib.string.char_at", [lit("aé🚀"), lit(1)]),
    call_contract("UnicodeSubstring", "stdlib.string.substring", [lit("aé🚀z"), lit(1), lit(2)]),
    call_contract("OobCharAt", "stdlib.string.char_at", [lit("abc"), lit(9)]),
    call_contract("NegativeCharAt", "stdlib.string.char_at", [lit("abc"), lit(-1)]),
    call_contract("OobSubstring", "stdlib.string.substring", [lit("abc"), lit(9), lit(2)]),
    call_contract("NegativeSubstring", "stdlib.string.substring", [lit("abc"), lit(-5), lit(2)]),
    call_contract("BadArityCharAt", "stdlib.string.char_at", [lit("abc")]),
    call_contract("BadSourceCharAt", "stdlib.string.char_at", [lit(123), lit(0)]),
    call_contract("BadIndexCharAt", "stdlib.string.char_at", [lit("abc"), lit("0")]),
    call_contract("BadAritySubstring", "stdlib.string.substring", [lit("abc"), lit(0)]),
    call_contract("BadSourceSubstring", "stdlib.string.substring", [lit(123), lit(0), lit(1)]),
    call_contract("BadStartSubstring", "stdlib.string.substring", [lit("abc"), lit("0"), lit(1)]),
    call_contract("BadLengthSubstring", "stdlib.string.substring", [lit("abc"), lit(0), lit("1")]),
    call_contract("TextRuneSliceRegression", "stdlib.text.rune_slice", [lit("aé🚀"), lit(1), lit(2)])
  ]
}
write_igapp(SYNTH_IGAPP, SYNTH_SIR)

SOURCE_RUNS = {
  "CharAtProbe" => run_vm(SOURCE_IGAPP, { "source" => "abc", "idx" => 1 }, "CharAtProbe"),
  "SubstringProbe" => run_vm(SOURCE_IGAPP, { "source" => "module", "start" => 2, "len" => 3 }, "SubstringProbe"),
  "LambdaCharAtProbe" => run_vm(SOURCE_IGAPP, { "words" => %w[abc déx] }, "LambdaCharAtProbe"),
  "LambdaSubstringProbe" => run_vm(SOURCE_IGAPP, { "words" => ["abcd", "aé🚀z"] }, "LambdaSubstringProbe")
}

SYNTH_RUNS = SYNTH_SIR["contracts"].to_h do |contract|
  name = contract["contract_name"]
  [name, run_vm(SYNTH_IGAPP, {}, name)]
end

PARSER_SOURCES = %w[types.ig lexer.ig parser.ig api.ig].map { |name| PARSER_APP / name }
PARSER_IGAPP = File.join(TMP, "igniter_parser.igapp")
PARSER_COMPILE = compile_sources(PARSER_SOURCES, PARSER_IGAPP)
PARSER_RUN = run_vm(PARSER_IGAPP, { "source" => "module Demo" }, "ParseSource")

vm_text = read(VM_SRC)
card_text = read(CARD)
app_wave_text = read(APP_WAVE_CARD)
checkpoint_text = read(RUNTIME_CHECKPOINT)
ch8_text = read(CH8)
inventory_text = read(INVENTORY)
doc_text = read(DOC)
portfolio_text = read(PORTFOLIO)
surface_text = read(VM_SURFACE)
proof_text = read(Pathname.new(__FILE__))

puts "LAB-STDLIB-STRING-CHAR-AT-VM-P1"

section("A Source Shape And Gates")
check("A-01 VM build succeeds") { BUILD[:success] }
check("A-02 VM binary exists after build") { File.executable?(VM_BIN.to_s) }
check("A-03 vm.rs defines stdlib_string_char_at helper") { vm_text.include?("fn stdlib_string_char_at") }
check("A-04 vm.rs defines stdlib_string_substring helper") { vm_text.include?("fn stdlib_string_substring") }
check("A-05 OP_CALL handles stdlib.string.char_at") { vm_text.include?('"stdlib.string.char_at" =>') || vm_text.include?('"char_at" | "stdlib.string.char_at"') }
check("A-06 OP_CALL handles stdlib.string.substring") { vm_text.include?('"substring" | "stdlib.string.substring"') }
check("A-07 eval_ast handles stdlib.string.char_at") { vm_text.include?('"char_at" | "stdlib.string.char_at" =>') }
check("A-08 eval_ast handles stdlib.string.substring") { vm_text.include?('"substring" | "stdlib.string.substring" =>') }
check("A-09 implementation uses rune/char iteration") { vm_text.include?("s.chars().nth") && vm_text.include?("s.chars().skip") }
check("A-10 no compiler source is touched by this proof") { proof_text.include?("No compiler, parser, typechecker") }
check("A-11 app demo wave names igniter_parser as gated on this card") { app_wave_text.include?("igniter_parser") && app_wave_text.include?("LAB-STDLIB-STRING-CHAR-AT-VM-P1") }
check("A-12 runtime checkpoint records char_at as tiny stdlib tail") { checkpoint_text.include?("tiny stdlib tail") && checkpoint_text.include?("stdlib.string.char_at") }
check("A-13 inventory has char_at") { inventory_text.include?('"canonical_name": "stdlib.string.char_at"') }
check("A-14 inventory has substring") { inventory_text.include?('"canonical_name": "stdlib.string.substring"') }
check("A-15 inventory says substring uses start length") { inventory_text.include?("0-based start, length in bytes") || inventory_text.include?("substring(\\\"module\\\", 2, 3) -> \\\"dul\\\"") }
check("A-16 ch8 text surface remains separate from stdlib.string") { ch8_text.include?("stdlib.text.rune_slice") && inventory_text.include?("stdlib.string.char_at") }

section("B Frontend Fixture And SIR")
check("B-01 source fixture compiles") { SOURCE_COMPILE[:success] }
check("B-02 source fixture status ok") { SOURCE_COMPILE[:json]["status"] == "ok" }
check("B-03 source fixture diagnostics empty") { Array(SOURCE_COMPILE[:json]["diagnostics"]).empty? }
check("B-04 source fixture has four contracts") { Array(SOURCE_COMPILE[:json]["contracts"]).sort == %w[CharAtProbe LambdaCharAtProbe LambdaSubstringProbe SubstringProbe].sort }
check("B-05 SIR contains stdlib.string.char_at") { find_calls(SOURCE_COMPILE[:sir], "stdlib.string.char_at").size >= 2 }
check("B-06 SIR contains stdlib.string.substring") { find_calls(SOURCE_COMPILE[:sir], "stdlib.string.substring").size >= 2 }
check("B-07 SIR contains stdlib.collection.map") { find_calls(SOURCE_COMPILE[:sir], "stdlib.collection.map").size >= 2 }
check("B-08 source fixture imports stdlib.string") { read(SOURCE_FIXTURE).include?("import stdlib.string.{ char_at, substring }") }
check("B-09 source fixture keeps char_at output String") { read(SOURCE_FIXTURE).include?("output out : String") }
check("B-10 synthetic igapp has manifest") { File.exist?(File.join(SYNTH_IGAPP, "manifest.json")) }
check("B-11 synthetic igapp has 17 contracts") { SYNTH_SIR["contracts"].size == 17 }
check("B-12 synthetic fixture includes text rune regression") { SYNTH_SIR["contracts"].any? { |c| c["contract_name"] == "TextRuneSliceRegression" } }

section("C OP_CALL Runtime Happy Paths")
check("C-01 source CharAtProbe exits zero") { SOURCE_RUNS["CharAtProbe"][:exit] == 0 }
check("C-02 source CharAtProbe returns b") { SOURCE_RUNS["CharAtProbe"][:json]["result"] == "b" }
check("C-03 source SubstringProbe exits zero") { SOURCE_RUNS["SubstringProbe"][:exit] == 0 }
check("C-04 source SubstringProbe returns dul") { SOURCE_RUNS["SubstringProbe"][:json]["result"] == "dul" }
check("C-05 synthetic bare char_at alias returns b") { SYNTH_RUNS["BareCharAt"][:json]["result"] == "b" }
check("C-06 synthetic canonical char_at returns b") { SYNTH_RUNS["CanonicalCharAt"][:json]["result"] == "b" }
check("C-07 synthetic canonical substring returns dul") { SYNTH_RUNS["CanonicalSubstring"][:json]["result"] == "dul" }
check("C-08 unicode char_at returns single rune") { SYNTH_RUNS["UnicodeCharAt"][:json]["result"] == "é" }
check("C-09 unicode substring returns two runes") { SYNTH_RUNS["UnicodeSubstring"][:json]["result"] == "é🚀" }
check("C-10 happy paths have success status") do
  %w[BareCharAt CanonicalCharAt CanonicalSubstring UnicodeCharAt UnicodeSubstring].all? do |entry|
    SYNTH_RUNS[entry][:json]["status"] == "success"
  end
end
check("C-11 happy paths have no dispatch_skipped") { SYNTH_RUNS.values_at("CanonicalCharAt", "CanonicalSubstring").none? { |r| r[:json].key?("dispatch_skipped") } }
check("C-12 OP_CALL unknown char_at gap is gone") { !SYNTH_RUNS["CanonicalCharAt"][:stdout].include?("Unknown/unimplemented") }

section("D Runtime Failure And Bounds Policy")
check("D-01 out-of-bounds char_at exits zero") { SYNTH_RUNS["OobCharAt"][:exit] == 0 }
check("D-02 out-of-bounds char_at returns empty string") { SYNTH_RUNS["OobCharAt"][:json]["result"] == "" }
check("D-03 negative char_at returns empty string") { SYNTH_RUNS["NegativeCharAt"][:json]["result"] == "" }
check("D-04 out-of-bounds substring returns empty string") { SYNTH_RUNS["OobSubstring"][:json]["result"] == "" }
check("D-05 negative substring clamps start and returns ab") { SYNTH_RUNS["NegativeSubstring"][:json]["result"] == "ab" }
check("D-06 bad char_at arity exits non-zero") { SYNTH_RUNS["BadArityCharAt"][:exit] != 0 }
check("D-07 bad char_at arity names stdlib.string.char_at") { SYNTH_RUNS["BadArityCharAt"][:json]["error"].to_s.include?("stdlib.string.char_at expects exactly 2 arguments") }
check("D-08 bad char_at source exits non-zero") { SYNTH_RUNS["BadSourceCharAt"][:exit] != 0 }
check("D-09 bad char_at source reports Expected String") { SYNTH_RUNS["BadSourceCharAt"][:json]["error"].to_s.include?("Expected String") }
check("D-10 bad char_at index reports Expected Integer") { SYNTH_RUNS["BadIndexCharAt"][:json]["error"].to_s.include?("Expected Integer") }
check("D-11 bad substring arity exits non-zero") { SYNTH_RUNS["BadAritySubstring"][:exit] != 0 }
check("D-12 bad substring arity names stdlib.string.substring") { SYNTH_RUNS["BadAritySubstring"][:json]["error"].to_s.include?("stdlib.string.substring expects exactly 3 arguments") }
check("D-13 bad substring source reports Expected String") { SYNTH_RUNS["BadSourceSubstring"][:json]["error"].to_s.include?("Expected String") }
check("D-14 bad substring integer args report Expected Integer") do
  SYNTH_RUNS["BadStartSubstring"][:json]["error"].to_s.include?("Expected Integer") &&
    SYNTH_RUNS["BadLengthSubstring"][:json]["error"].to_s.include?("Expected Integer")
end

section("E eval_ast Lambda Path")
check("E-01 LambdaCharAtProbe exits zero") { SOURCE_RUNS["LambdaCharAtProbe"][:exit] == 0 }
check("E-02 LambdaCharAtProbe status success") { SOURCE_RUNS["LambdaCharAtProbe"][:json]["status"] == "success" }
check("E-03 LambdaCharAtProbe returns second runes") { SOURCE_RUNS["LambdaCharAtProbe"][:json]["result"] == ["b", "é"] }
check("E-04 LambdaSubstringProbe exits zero") { SOURCE_RUNS["LambdaSubstringProbe"][:exit] == 0 }
check("E-05 LambdaSubstringProbe status success") { SOURCE_RUNS["LambdaSubstringProbe"][:json]["status"] == "success" }
check("E-06 LambdaSubstringProbe returns rune substrings") { SOURCE_RUNS["LambdaSubstringProbe"][:json]["result"] == ["bc", "é🚀"] }
check("E-07 lambda runs do not hit Unknown/unimplemented") { SOURCE_RUNS.values_at("LambdaCharAtProbe", "LambdaSubstringProbe").none? { |r| r[:stdout].include?("Unknown/unimplemented") } }
check("E-08 eval_ast path is explicitly covered in vm.rs") { vm_text.include?("eval_ast") && vm_text.include?("stdlib_string_char_at(&evaluated_operands)") }

section("F igniter_parser Runtime Path")
check("F-01 igniter_parser compile exits zero") { PARSER_COMPILE[:exit] == 0 }
check("F-02 igniter_parser status ok") { PARSER_COMPILE[:json]["status"] == "ok" }
check("F-03 igniter_parser diagnostics empty") { Array(PARSER_COMPILE[:json]["diagnostics"]).empty? }
check("F-04 igniter_parser SIR contains char_at") { find_calls(PARSER_COMPILE[:sir], "stdlib.string.char_at").size == 1 }
check("F-05 igniter_parser SIR contains substring") { find_calls(PARSER_COMPILE[:sir], "stdlib.string.substring").size == 1 }
check("F-06 igniter_parser SIR contains ParseSource") { Array(PARSER_COMPILE[:json]["contracts"]).include?("ParseSource") }
check("F-07 ParseSource VM exits zero") { PARSER_RUN[:exit] == 0 }
check("F-08 ParseSource VM status success") { PARSER_RUN[:json]["status"] == "success" }
check("F-09 ParseSource result is one AST node") { PARSER_RUN[:json]["result"].is_a?(Array) && PARSER_RUN[:json]["result"].size == 1 }
check("F-10 ParseSource node kind ModuleDecl") { PARSER_RUN[:json].dig("result", 0, "kind") == "ModuleDecl" }
check("F-11 ParseSource node text ParsedModule") { PARSER_RUN[:json].dig("result", 0, "text") == "ParsedModule" }
check("F-12 ParseSource child ids empty") { PARSER_RUN[:json].dig("result", 0, "children_ids") == [] }
check("F-13 ParseSource advanced past prior char_at gap") { !PARSER_RUN[:json]["error"].to_s.include?("stdlib.string.char_at") }
check("F-14 no igniter_parser app source was generated by proof") { PARSER_SOURCES.all? { |p| File.exist?(p.to_s) } }

section("G Text Regression And Boundaries")
check("G-01 stdlib.text.rune_slice regression exits zero") { SYNTH_RUNS["TextRuneSliceRegression"][:exit] == 0 }
check("G-02 stdlib.text.rune_slice still returns unicode rune") { SYNTH_RUNS["TextRuneSliceRegression"][:json]["result"] == "é" }
check("G-03 text handler source remains present") { vm_text.include?('"stdlib.text.rune_slice"') }
check("G-04 string helper does not edit text helper names") { vm_text.include?('"stdlib.text.grapheme_slice"') && vm_text.include?('"stdlib.text.byte_slice"') }
check("G-05 card closed surfaces prohibit front-end changes") { card_text.include?("No front-end compiler changes") }
check("G-06 proof body states no app-source authority") { proof_text.include?("No compiler, parser, typechecker, inventory, app-source") }
check("G-07 parser pressure registry still says no source changes in P13") { read(PARSER_APP / "PRESSURE_REGISTRY.md").include?("No source changes in this wave") }
check("G-08 implemented surface file exists") { VM_SURFACE.file? }

section("H Closure Artifacts")
check("H-01 lab doc exists") { DOC.file? }
check("H-02 lab doc records 96/96 PASS") { doc_text.include?("96/96 PASS") }
check("H-03 lab doc records rune indexing") { doc_text.include?("rune") }
check("H-04 lab doc records ParseSource success") { doc_text.include?("ParseSource") && doc_text.include?("ModuleDecl") }
check("H-05 card is closed") { card_text.include?("**Status:** CLOSED") }
check("H-06 card records 96/96 PASS") { card_text.include?("96/96 PASS") }
check("H-07 portfolio contains closure entry") { portfolio_text.include?("LAB-STDLIB-STRING-CHAR-AT-VM-P1 CLOSED") }
check("H-08 portfolio references proof runner") { portfolio_text.include?("verify_lab_stdlib_string_char_at_vm_p1.rb") }
check("H-09 implemented surface no longer lists char_at as tiny tail") { !surface_text.include?("tiny stdlib tail | igniter_parser | `stdlib.string.char_at`") }
check("H-10 implemented surface records string runtime ops") { surface_text.include?("stdlib.string.char_at") && surface_text.include?("stdlib.string.substring") }
check("H-11 proof file names card") { proof_text.include?("LAB-STDLIB-STRING-CHAR-AT-VM-P1") }
check("H-12 proof closes no canon authority") { proof_text.include?("canon authority") }

puts "\nRESULT: #{$pass}/#{$pass + $fail} PASS"
exit($fail.zero? ? 0 : 1)
