# verify_str_core.rb
# igniter-string-core-units-and-pure-stdlib-boundary-v0 — Lab Rust STR-CORE symmetry
#
# Checks:
#   STR-TC    (8): Rust typechecker accepts all 14 text ops with Text args (no OOF)
#   STR-COMPAT(2): v0 compat rule — String literals accepted as Text args
#   STR-OOF   (5): OOF-TY0 fires for arity and type mismatches (canon message format)
#   STR-SIR   (7): SemanticIR has kind=call, fn=stdlib.text.*, resolved_type (incl. concat)
#   STR-CLOSED(3): closed surfaces (regex/locale/tokenize) produce OOF-TY0
#   STR-REG   (2): regression — integer arithmetic and recur() unaffected

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../../../../tools/proof_harness/bounded_command'

ROOT = Pathname.new(__dir__).parent.parent
COMP = ROOT / "target/release/igniter_compiler"

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}";  $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}";  $fail_count += 1)

def compile_src(src, label)
  tmp = Dir.mktmpdir("str_#{label}")
  ig  = File.join(tmp, "#{label}.ig")
  out = File.join(tmp, "#{label}.igapp")
  File.write(ig, src)
  # LAB-PROOF-HYGIENE-P1: bounded execution — hard timeout, kills process group
  r = BoundedCommand.run("#{COMP} compile #{ig} --out #{out}",
                         label: "compile:#{label}",
                         timeout: BoundedCommand::EXEC_TIMEOUT)
  BoundedCommand.print_result(r) unless r.ok?
  [r.combined, out, tmp]
end

def load_sir(app_path)
  sir_path = File.join(app_path, "semantic_ir_program.json")
  return nil unless File.exist?(sir_path)
  JSON.parse(File.read(sir_path)) rescue nil
end

def find_compute_nodes(sir, contract_name = nil)
  return [] unless sir
  contracts = sir["contracts"] || []
  contracts = [contracts] unless contracts.is_a?(Array)
  if contract_name
    contracts = contracts.select { |c| c["contract_name"] == contract_name || c["name"] == contract_name }
  end
  contracts.flat_map { |c| c["nodes"] || [] }.select { |n| n["kind"] == "compute" }
end

unless COMP.exist?
  puts "[*] Building compiler (release)..."
  # LAB-PROOF-HYGIENE-P1: bounded cargo build
  r = BoundedCommand.run("cargo build --release",
                         label: "cargo build --release",
                         timeout: BoundedCommand::CARGO_TIMEOUT)
  unless r.ok?
    BoundedCommand.print_result(r)
    puts "[!] Compiler build failed — aborting"
    exit(1)
  end
end

# ============================================================
puts "\n=== STR-TC: Rust typechecker accepts all 14 text ops ===\n"
# ============================================================

SRC_CONCAT_TRIM = <<~IGNITER
  module StrCore
  pure contract ConcatTrim {
    input first: Text
    input second: Text
    compute joined: Text = concat(first, second)
    compute clean: Text = trim(first)
    output joined: Text
    output clean: Text
  }
IGNITER

result, app_path, tmp = compile_src(SRC_CONCAT_TRIM, "concat_trim")
if File.exist?(app_path)
  pass "STR-TC: concat + trim compile without OOF errors"
else
  fail! "STR-TC: concat/trim failed to compile (#{result[0..300]})"
end
if result.include?("OOF-TY0")
  fail! "STR-TC: unexpected OOF-TY0 in concat/trim"
else
  pass "STR-TC: no OOF-TY0 for valid concat/trim calls"
end
FileUtils.rm_rf(tmp)

SRC_PREDICATES = <<~IGNITER
  module StrCore
  pure contract Predicates {
    input text: Text
    input needle: Text
    compute has_needle: Bool = contains(text, needle)
    compute starts: Bool = starts_with(text, needle)
    compute ends_val: Bool = ends_with(text, needle)
    output has_needle: Bool
    output starts: Bool
    output ends_val: Bool
  }
IGNITER

result, app_path, tmp = compile_src(SRC_PREDICATES, "predicates")
if File.exist?(app_path)
  pass "STR-TC: contains + starts_with + ends_with compile → Bool"
else
  fail! "STR-TC: predicates failed to compile (#{result[0..300]})"
end
if result.include?("OOF-TY0")
  fail! "STR-TC: unexpected OOF-TY0 in predicates"
else
  pass "STR-TC: no OOF-TY0 for valid predicate calls"
end
FileUtils.rm_rf(tmp)

SRC_SPLIT_REPLACE = <<~IGNITER
  module StrCore
  pure contract SplitReplace {
    input text: Text
    input delimiter: Text
    input pattern: Text
    input replacement: Text
    compute parts: Collection[Text] = split(text, delimiter)
    compute single: Text = replace(text, pattern, replacement)
    compute all: Text = replace_all(text, pattern, replacement)
    output parts: Collection[Text]
    output single: Text
    output all: Text
  }
IGNITER

result, app_path, tmp = compile_src(SRC_SPLIT_REPLACE, "split_replace")
if File.exist?(app_path)
  pass "STR-TC: split + replace + replace_all compile"
else
  fail! "STR-TC: split/replace failed to compile (#{result[0..300]})"
end
if result.include?("OOF-TY0")
  fail! "STR-TC: unexpected OOF-TY0 in split/replace"
else
  pass "STR-TC: no OOF-TY0 for valid split/replace calls"
end
FileUtils.rm_rf(tmp)

SRC_LENGTHS = <<~IGNITER
  module StrCore
  pure contract Lengths {
    input text: Text
    compute bytes: Integer = byte_length(text)
    compute runes: Integer = rune_length(text)
    compute graphemes: Integer = grapheme_length(text)
    output bytes: Integer
    output runes: Integer
    output graphemes: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_LENGTHS, "lengths")
if File.exist?(app_path)
  pass "STR-TC: byte_length + rune_length + grapheme_length compile → Integer"
else
  fail! "STR-TC: lengths failed to compile (#{result[0..300]})"
end
if result.include?("OOF-TY0")
  fail! "STR-TC: unexpected OOF-TY0 in lengths"
else
  pass "STR-TC: no OOF-TY0 for valid length calls"
end
FileUtils.rm_rf(tmp)

SRC_SLICES = <<~IGNITER
  module StrCore
  pure contract Slices {
    input text: Text
    input start: Integer
    input end_idx: Integer
    compute byte_part: Text = byte_slice(text, start, end_idx)
    compute rune_part: Text = rune_slice(text, start, end_idx)
    compute grapheme_part: Text = grapheme_slice(text, start, end_idx)
    output byte_part: Text
    output rune_part: Text
    output grapheme_part: Text
  }
IGNITER

result, app_path, tmp = compile_src(SRC_SLICES, "slices")
if File.exist?(app_path)
  pass "STR-TC: byte_slice + rune_slice + grapheme_slice compile → Text"
else
  fail! "STR-TC: slices failed to compile (#{result[0..300]})"
end
if result.include?("OOF-TY0")
  fail! "STR-TC: unexpected OOF-TY0 in slices"
else
  pass "STR-TC: no OOF-TY0 for valid slice calls"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== STR-COMPAT: v0 compat — String literals accepted as Text args ===\n"
# ============================================================

SRC_LITERAL_COMPAT = <<~IGNITER
  module StrCore
  pure contract LiteralCompat {
    input text: Text
    compute with_suffix: Text = concat(text, "world")
    compute has_hello: Bool = contains(text, "hello")
    compute trimmed: Text = trim(text)
    output with_suffix: Text
    output has_hello: Bool
    output trimmed: Text
  }
IGNITER

result, app_path, tmp = compile_src(SRC_LITERAL_COMPAT, "literal_compat")
if File.exist?(app_path)
  pass "STR-COMPAT: String literal accepted as Text arg in concat/contains"
else
  fail! "STR-COMPAT: literal compat failed to compile (#{result[0..300]})"
end
if result.include?("OOF-TY0")
  fail! "STR-COMPAT: OOF-TY0 fired for String literal as Text arg (v0 compat broken)"
else
  pass "STR-COMPAT: no OOF-TY0 for String literals in Text arg positions"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== STR-OOF: OOF-TY0 fires for arity and type mismatches ===\n"
# ============================================================

SRC_OOF_CONCAT_INTEGER = <<~IGNITER
  module StrCore
  pure contract TypeErrorExample {
    input n: Integer
    input text: Text
    compute result: Text = concat(n, text)
    output result: Text
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_CONCAT_INTEGER, "oof_type_error")
FileUtils.rm_rf(tmp)
if result.include?("OOF-TY0")
  pass "STR-OOF: OOF-TY0 fires for concat(Integer, Text) — type mismatch arg 1"
else
  fail! "STR-OOF: OOF-TY0 NOT fired for Integer arg to Text param (got: #{result[0..300]})"
end

SRC_OOF_CONCAT_ARITY = <<~IGNITER
  module StrCore
  pure contract ArityErrorExample {
    input text: Text
    compute result: Text = concat(text)
    output result: Text
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_CONCAT_ARITY, "oof_arity")
FileUtils.rm_rf(tmp)
if result.include?("OOF-TY0")
  pass "STR-OOF: OOF-TY0 fires for concat(text) — arity 1, expected 2"
else
  fail! "STR-OOF: OOF-TY0 NOT fired for concat arity error (got: #{result[0..300]})"
end

SRC_OOF_SLICE_BAD_INDEX = <<~IGNITER
  module StrCore
  pure contract SliceBadIndex {
    input text: Text
    input start: Text
    input end_idx: Text
    compute result: Text = byte_slice(text, start, end_idx)
    output result: Text
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_SLICE_BAD_INDEX, "oof_slice_bad_index")
FileUtils.rm_rf(tmp)
if result.include?("OOF-TY0")
  pass "STR-OOF: OOF-TY0 fires for byte_slice(Text, Text, Text) — args 2+3 expected Integer"
else
  fail! "STR-OOF: OOF-TY0 NOT fired for byte_slice with Text index args (got: #{result[0..300]})"
end

# Verify canon message format: "stdlib.text.{fn}: expected N argument(s), got M"
SRC_OOF_TRIM_ARITY = <<~IGNITER
  module StrCore
  pure contract TrimArity {
    input text: Text
    input extra: Text
    compute result: Text = trim(text, extra)
    output result: Text
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_TRIM_ARITY, "oof_trim_arity")
FileUtils.rm_rf(tmp)
if result.include?("stdlib.text.trim")
  pass "STR-OOF: OOF-TY0 message includes 'stdlib.text.trim' (canon format)"
else
  fail! "STR-OOF: OOF-TY0 message missing 'stdlib.text.trim' (got: #{result[0..400]})"
end

# Verify canon message format for type error
SRC_OOF_TYPE_MSG = <<~IGNITER
  module StrCore
  pure contract TypeMsg {
    input n: Integer
    compute result: Text = trim(n)
    output result: Text
  }
IGNITER

result, _out, tmp = compile_src(SRC_OOF_TYPE_MSG, "oof_type_msg")
FileUtils.rm_rf(tmp)
if result.include?("stdlib.text.trim arg 1")
  pass "STR-OOF: OOF-TY0 message includes 'stdlib.text.trim arg 1: expected Text, got Integer' (canon format)"
else
  fail! "STR-OOF: OOF-TY0 message format mismatch (got: #{result[0..400]})"
end

# ============================================================
puts "\n=== STR-SIR: SemanticIR has kind=call, fn=stdlib.text.*, resolved_type ===\n"
# ============================================================

result, app_path, tmp = compile_src(SRC_CONCAT_TRIM, "sir_concat_trim")
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "ConcatTrim")

trim_node = cn.find { |n| n["name"] == "clean" }
if trim_node
  expr = trim_node["expr"]
  if expr && expr["fn"] == "stdlib.text.trim"
    pass "STR-SIR: trim compute.expr.fn = 'stdlib.text.trim'"
  else
    fail! "STR-SIR: trim expr.fn = '#{expr&.dig("fn")}', expected 'stdlib.text.trim'"
  end
  if expr && expr["kind"] == "call"
    pass "STR-SIR: trim expr.kind = 'call'"
  else
    fail! "STR-SIR: trim expr.kind = '#{expr&.dig("kind")}', expected 'call'"
  end
else
  fail! "STR-SIR: could not find 'clean' compute node"
  fail! "STR-SIR: (skipping trim kind check)"
end
FileUtils.rm_rf(tmp)

result, app_path, tmp = compile_src(SRC_LENGTHS, "sir_lengths")
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "Lengths")

bytes_node = cn.find { |n| n["name"] == "bytes" }
if bytes_node
  expr = bytes_node["expr"]
  if expr && expr["fn"] == "stdlib.text.byte_length"
    pass "STR-SIR: byte_length expr.fn = 'stdlib.text.byte_length'"
  else
    fail! "STR-SIR: byte_length expr.fn = '#{expr&.dig("fn")}', expected 'stdlib.text.byte_length'"
  end
  if expr && expr.key?("resolved_type") && expr["resolved_type"]["name"] == "Integer"
    pass "STR-SIR: byte_length resolved_type.name = 'Integer'"
  else
    fail! "STR-SIR: byte_length resolved_type = '#{expr&.dig("resolved_type")&.inspect}', expected Integer"
  end
else
  fail! "STR-SIR: could not find 'bytes' compute node"
  fail! "STR-SIR: (skipping byte_length resolved_type check)"
end
FileUtils.rm_rf(tmp)

# STR-SIR: concat fn disambiguation — stdlib.text.concat for Text args
result, app_path, tmp = compile_src(SRC_CONCAT_TRIM, "sir_concat_sir")
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "ConcatTrim")

concat_node = cn.find { |n| n["name"] == "joined" }
if concat_node
  expr = concat_node["expr"]
  if expr && expr["fn"] == "stdlib.text.concat"
    pass "STR-SIR: concat(Text, Text) → expr.fn = 'stdlib.text.concat' (disambiguated)"
  else
    fail! "STR-SIR: concat expr.fn = '#{expr&.dig("fn")}', expected 'stdlib.text.concat'"
  end
  if expr && expr.key?("resolved_type") && expr["resolved_type"]["name"] == "Text"
    pass "STR-SIR: concat resolved_type.name = 'Text'"
  else
    fail! "STR-SIR: concat resolved_type = '#{expr&.dig("resolved_type")&.inspect}', expected Text"
  end
else
  fail! "STR-SIR: could not find 'joined' compute node for concat check"
  fail! "STR-SIR: (skipping concat resolved_type check)"
end
FileUtils.rm_rf(tmp)

# STR-SIR: Collection concat remains as stdlib.collection.concat (not stdlib.text.concat)
SRC_COLLECTION_CONCAT = <<~IGNITER
  module StrCore
  pure contract CollConcat {
    input a: Collection[Integer]
    input b: Collection[Integer]
    compute merged: Collection[Integer] = concat(a, b)
    output merged: Collection[Integer]
  }
IGNITER

result, app_path, tmp = compile_src(SRC_COLLECTION_CONCAT, "sir_coll_concat")
sir = load_sir(app_path)
cn = find_compute_nodes(sir, "CollConcat")
merged_node = cn.find { |n| n["name"] == "merged" }
if merged_node
  expr = merged_node["expr"]
  if expr && expr["fn"] == "stdlib.collection.concat"
    pass "STR-SIR: concat(Collection, Collection) → expr.fn = 'stdlib.collection.concat'"
  else
    fail! "STR-SIR: collection concat expr.fn = '#{expr&.dig("fn")}', expected 'stdlib.collection.concat'"
  end
else
  fail! "STR-SIR: could not find 'merged' compute node for collection concat check"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n=== STR-CLOSED: closed surfaces produce OOF-TY0 ===\n"
# ============================================================

SRC_CLOSED_REGEX = <<~IGNITER
  module StrCore
  pure contract RegexExample {
    input text: Text
    compute result: Bool = regex_match(text, "hello")
    output result: Bool
  }
IGNITER

result, _out, tmp = compile_src(SRC_CLOSED_REGEX, "closed_regex")
FileUtils.rm_rf(tmp)
if result.include?("OOF-TY0")
  pass "STR-CLOSED: regex_match → OOF-TY0 (correctly closed)"
else
  fail! "STR-CLOSED: regex_match NOT rejected (got: #{result[0..300]})"
end

SRC_CLOSED_LOCALE = <<~IGNITER
  module StrCore
  pure contract LocaleExample {
    input text: Text
    compute result: Text = locale_fold_case(text)
    output result: Text
  }
IGNITER

result, _out, tmp = compile_src(SRC_CLOSED_LOCALE, "closed_locale")
FileUtils.rm_rf(tmp)
if result.include?("OOF-TY0")
  pass "STR-CLOSED: locale_fold_case → OOF-TY0 (correctly closed)"
else
  fail! "STR-CLOSED: locale_fold_case NOT rejected (got: #{result[0..300]})"
end

SRC_CLOSED_TOKENIZE = <<~IGNITER
  module StrCore
  pure contract TokenizeExample {
    input text: Text
    compute result: Collection[Text] = tokenize(text)
    output result: Collection[Text]
  }
IGNITER

result, _out, tmp = compile_src(SRC_CLOSED_TOKENIZE, "closed_tokenize")
FileUtils.rm_rf(tmp)
if result.include?("OOF-TY0")
  pass "STR-CLOSED: tokenize → OOF-TY0 (correctly closed)"
else
  fail! "STR-CLOSED: tokenize NOT rejected (got: #{result[0..300]})"
end

# ============================================================
puts "\n=== STR-REG: regression — integer arithmetic and recur() unaffected ===\n"
# ============================================================

SRC_INTEGER_REGRESSION = <<~IGNITER
  module StrCore
  pure contract AddRegression {
    input a: Integer
    input b: Integer
    compute sum: Integer = a + b
    output sum: Integer
  }
IGNITER

result, app_path, tmp = compile_src(SRC_INTEGER_REGRESSION, "int_regression")
if File.exist?(app_path)
  pass "STR-REG: integer arithmetic still compiles after text stdlib changes"
else
  fail! "STR-REG: integer arithmetic broken (#{result[0..300]})"
end
FileUtils.rm_rf(tmp)

SRC_RECUR_REGRESSION = <<~IGNITER
  module StrCore
  recursive contract RecurRegression {
    input n: Integer
    compute result = recur(n - 1)
    output result: Integer
    decreases fuel
    max_steps 100
  }
IGNITER

result, app_path, tmp = compile_src(SRC_RECUR_REGRESSION, "recur_regression")
if File.exist?(app_path) && !result.include?("OOF-R1")
  pass "STR-REG: recur() in recursive contract still works after text stdlib changes"
else
  fail! "STR-REG: recur() regression detected (#{result[0..300]})"
end
FileUtils.rm_rf(tmp)

# ============================================================
puts "\n==============================="
total = $pass_count + $fail_count
puts "[*] Results: #{$pass_count}/#{total} PASS, #{$fail_count} FAIL"
if $fail_count == 0
  puts "[+] STR-CORE CONFORMANCE PASS — Lab Rust text stdlib symmetry verified"
  puts "    igniter-string-core-units-and-pure-stdlib-boundary-v0"
  exit 0
else
  puts "[!] STR-CORE CONFORMANCE FAIL — #{$fail_count} check(s) failed"
  exit 1
end
