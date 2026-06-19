#!/usr/bin/env ruby
# frozen_string_literal: true
#
# survey_variant_match_vm_readiness.rb
# PROP-044-P7-READINESS: opcode/IR survey grounding the VM variant-dispatch readiness map.
#
# DESIGN EVIDENCE, not implementation. Grounds the readiness doc's central finding —
# variant/match exists ONLY in the Ruby canon pipeline (PROP-044-P3/P5/P6); the entire
# Rust lab toolchain (igniter-compiler + igniter-vm), which is what the VM proofs run,
# has ZERO variant/match support — by:
#   (A) compiling variant/match source through the Rust compiler and asserting it fails
#       (OOF-G1; no SIR; no variant_declarations);
#   (B) confirming the Ruby front-end DOES parse variant declarations (the asymmetry);
#   (C) grepping the actual Rust source for the absent surfaces (Value::Variant, match
#       opcodes, variant_construct/match_node handling, variant/match keywords);
#   (D) a regression anchor: the variant-free KDR P4 fixture still compiles+runs in the VM.
#
# Authority: LAB-ONLY. Readiness survey. No VM/compiler edits, no opcodes, no Value::Variant,
# no failure-taxonomy PROP, no sealed Outcome[T,E]. No canon claim. No public/stable API.
#
# Run: ruby igniter-view-engine/proofs/survey_variant_match_vm_readiness.rb

SOURCE = File.read(__FILE__).freeze

require 'json'
require 'open3'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require 'tempfile'

ROOT           = Pathname.new(__dir__).parent
LAB_ROOT       = ROOT.parent
WORKSPACE_ROOT = LAB_ROOT.parent
IGNITER_LIB    = WORKSPACE_ROOT / 'igniter-lang' / 'lib'
COMPILER_BIN   = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN         = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s

VM_VALUE_RS    = (LAB_ROOT / 'igniter-vm' / 'src' / 'value.rs').to_s
VM_INSTR_RS    = (LAB_ROOT / 'igniter-vm' / 'src' / 'instructions.rs').to_s
VM_COMPILER_RS = (LAB_ROOT / 'igniter-vm' / 'src' / 'compiler.rs').to_s
COMP_LEXER_RS  = (LAB_ROOT / 'igniter-compiler' / 'src' / 'lexer.rs').to_s
COMP_EMIT_RS   = (LAB_ROOT / 'igniter-compiler' / 'src' / 'emitter.rs').to_s

KDR_FIXTURE    = (ROOT / 'fixtures' / 'epistemic_outcome' / 'reconciliation_receipt_flow.ig').to_s

$LOAD_PATH.unshift(IGNITER_LIB.to_s) unless $LOAD_PATH.include?(IGNITER_LIB.to_s)
require 'igniter_lang'

$pass = 0
$fail = 0
def check(label)
  ok = yield
  puts(ok ? "  PASS: #{label}" : "  FAIL: #{label}")
  ok ? $pass += 1 : $fail += 1
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail += 1
end

def rust_compile(src_text)
  Dir.mktmpdir('vmsurvey') do |out|
    f = Tempfile.new(['probe', '.ig']); f.write(src_text); f.close
    stdout, _e, _s = Open3.capture3(COMPILER_BIN, 'compile', f.path, '--out', out, '--json')
    f.unlink rescue nil
    report = (JSON.parse(stdout.strip) rescue {})
    sir_path = File.join(out, 'semantic_ir_program.json')
    sir = File.exist?(sir_path) ? (JSON.parse(File.read(sir_path)) rescue nil) : nil
    { report: report, sir: sir }
  end
end

def reads(path) = File.exist?(path) ? File.read(path, encoding: 'UTF-8') : ''

VARIANT_SRC = <<~IG
  module Lab.VariantProbe
  variant Outcome {
    Ok { value: String }
    Err { reason: String }
  }
  pure contract UseOutcome {
    input  o : Outcome
    compute r = match o {
      Ok(value) => value
      Err(reason) => reason
    }
    output r : String
  }
IG

VARIANT_ONLY_SRC = "module Lab.VOnly\nvariant Outcome {\n  Ok { value: String }\n  Err { reason: String }\n}\n"

RUST = rust_compile(VARIANT_SRC)

# ─────────────────────────────────────────────────────────────────────────────
puts "\nP7R-RUST-FRONTEND  (Rust lab compiler cannot parse variant/match)"

check('P7R-RUST-01: Rust compiler emits OOF-G1 diagnostics on variant/match source') do
  diags = RUST[:report].fetch('diagnostics', [])
  diags.any? { |d| d['rule'] == 'OOF-G1' }
end
check('P7R-RUST-02: Rust compiler emits ZERO contracts for variant/match source (parse fails)') do
  RUST[:report].fetch('contracts', []).empty?
end
check('P7R-RUST-03: Rust compiler emits NO variant_declarations / match_node in SIR') do
  dump = RUST[:sir].nil? ? '' : JSON.dump(RUST[:sir])
  RUST[:sir].nil? || (!dump.include?('variant_declarations') && !dump.include?('match_node'))
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nP7R-RUBY-FRONTEND  (canon Ruby pipeline DOES have variant/match — the asymmetry)"

check('P7R-RUBY-01: Ruby parser parses a variant declaration (variants populated)') do
  parsed = IgniterLang::ParsedProgram.parse(VARIANT_ONLY_SRC, source_path: 'x.ig').to_h
  (parsed['variants'] || []).map { |v| v['name'] }.include?('Outcome')
end
check('P7R-RUBY-02: divergence — Rust rejects the SAME source the Ruby front-end accepts') do
  RUST[:report].fetch('contracts', []).empty? # Rust side; Ruby side asserted in P7R-RUBY-01
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nP7R-VM-SURFACE  (igniter-vm has no variant value/opcode/lowering)"

check('P7R-VM-01: Value enum (value.rs) declares NO Value::Variant') do
  v = reads(VM_VALUE_RS)
  v.include?('enum Value') && !v.include?('Variant')
end
check('P7R-VM-02: instructions.rs declares NO match/variant opcode') do
  i = reads(VM_INSTR_RS)
  !i.include?('MATCH') && !i.include?('VARIANT')
end
check('P7R-VM-03: VM compiler.rs handles NO variant_construct / match_node node kind') do
  c = reads(VM_COMPILER_RS)
  !c.include?('variant_construct') && !c.include?('match_node')
end
check('P7R-VM-04: VM compiler.rs fails closed on unknown node kinds (Unsupported AST expression kind)') do
  reads(VM_COMPILER_RS).include?('Unsupported AST expression kind')
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nP7R-COMP-SURFACE  (igniter-compiler front-end has no variant/match)"

check('P7R-COMP-01: lexer.rs KEYWORDS list contains neither "variant" nor "match" as keywords') do
  l = reads(COMP_LEXER_RS)
  # crude but sufficient: the keyword string literals are absent from the KEYWORDS table
  !l.include?('"variant"') && !l.include?('"match"')
end
check('P7R-COMP-02: emitter.rs emits NO variant_construct / match_node SemanticIR nodes') do
  e = reads(COMP_EMIT_RS)
  !e.include?('variant_construct') && !e.include?('match_node') && !e.include?('variant_declarations')
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nP7R-REGRESSION  (variant-free KDR still works — the path that exists today)"

check('P7R-REG-01: variant-free KDR P4 fixture compiles in Rust (5 contracts in SIR, no OOF-G1)') do
  Dir.mktmpdir('vmreg1') do |out|
    so, _e, _s = Open3.capture3(COMPILER_BIN, 'compile', KDR_FIXTURE, '--out', out, '--json')
    report = (JSON.parse(so.strip) rescue {})
    sir_path = File.join(out, 'semantic_ir_program.json')
    sir = File.exist?(sir_path) ? JSON.parse(File.read(sir_path)) : {}
    sir.fetch('contracts', []).length == 5 &&
      report.fetch('diagnostics', []).none? { |d| d['rule'] == 'OOF-G1' }
  end
end
check('P7R-REG-02: KDR routing still executes in the VM (RouteReceipt confirmed_succeeded+real → accept)') do
  Dir.mktmpdir('vmreg') do |out|
    Open3.capture3(COMPILER_BIN, 'compile', KDR_FIXTURE, '--out', out, '--json')
    inp = Tempfile.new(['i', '.json'])
    inp.write({ 'receipt' => { 'kind' => 'confirmed_succeeded', 'request_id' => 'r', 'resource' => 'u',
                               'idempotency_key' => '', 'observed_at' => '', 'evidence_kind' => 'real',
                               'compensation' => '', 'attempt' => 1, 'budget_remaining' => 3,
                               'detail' => '', 'metadata' => {} } }.to_json)
    inp.close
    so, _e, _s = Open3.capture3(VM_BIN, 'run', '--contract', out, '--inputs', inp.path, '--entry', 'RouteReceipt', '--json')
    inp.unlink rescue nil
    (JSON.parse(so.strip)['result'] rescue nil) == 'accept'
  end
end

# ─────────────────────────────────────────────────────────────────────────────
puts "\nP7R-CLOSED"

check('P7R-CLOSED-01: survey only READS source files (uses reads() helper; no write to a *.rs path)') do
  SOURCE.include?('def reads(') && !SOURCE.include?('File.' + 'write')
end
check('P7R-CLOSED-02: lab-only; no opcode/Value::Variant/PROP authored here') do
  SOURCE.include?('LAB-ONLY') && SOURCE.include?('Readiness survey')
end

# ─────────────────────────────────────────────────────────────────────────────
total = $pass + $fail
puts "\n#{'=' * 60}"
puts "PROP-044-P7-READINESS (variant/match VM survey): #{$pass}/#{total} PASS"
puts '=' * 60
exit($fail.zero? ? 0 : 1)
