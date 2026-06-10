#!/usr/bin/env ruby
# frozen_string_literal: true
# encoding: utf-8
#
# verify_prop044_p9_reserved_fields.rb — PROP-044-P9 proof script
#
# Proves that compiler-owned variant runtime fields (`__arm`, `__variant`, and
# all `__*`-prefixed names) are reserved from user-authored Igniter source.
# OOF-KIND6 fires when any user source declares or constructs a field with the
# `__` prefix in:
#   - type declarations
#   - variant arm payload fields
#   - record literals
#
# Decision locked: BROAD RESERVATION — all `__*` field names reserved.
# No existing fixture relies on double-underscore user field names.
# `"__absent__"` in map_vm_ops.ig is a string literal VALUE, not a field name.
#
# Sections:
#   RESERVE-SCAN    (5)  — no existing user fixture relies on __* field names
#   RESERVE-TYPE    (5)  — type Foo { __arm: String } → OOF-KIND6
#   RESERVE-RECORD  (5)  — { __arm: "Fake" } record literal → OOF-KIND6
#   RESERVE-VARIANT (5)  — variant Foo { Bar { __arm: String } } → OOF-KIND6
#   RESERVE-ALLOW   (6)  — normal records/variants/match compile clean
#   RESERVE-PATHB   (5)  — compiler-lowered variant records execute correctly
#   RESERVE-CLOSED  (5)  — no VM/opcode/Value/ABI changes
#
# Total: 36 checks
#
# Run: ruby igniter-lab/igniter-view-engine/proofs/verify_prop044_p9_reserved_fields.rb
#
# Authority: lab_only — PROP-044-P9 governance lock.

require 'json'
require 'open3'
require 'tempfile'
require 'pathname'
require 'fileutils'

ROOT         = Pathname.new(__dir__).parent
LAB_ROOT     = ROOT.parent
COMPILER_BIN = (LAB_ROOT / 'igniter-compiler' / 'target' / 'release' / 'igniter_compiler').to_s
VM_BIN       = (LAB_ROOT / 'igniter-vm' / 'target' / 'release' / 'igniter-vm').to_s
FIXTURE_DIR  = (ROOT / 'fixtures' / 'reserved_fields').to_s
EPISTEMIC_DIR = (ROOT / 'fixtures' / 'epistemic_outcome').to_s
VM_SRC_DIR   = (LAB_ROOT / 'igniter-vm' / 'src').to_s
RUST_TC_SRC  = (LAB_ROOT / 'igniter-compiler' / 'src' / 'typechecker.rs').to_s
RUBY_TC_SRC  = (LAB_ROOT.parent / 'igniter-lang' / 'lib' / 'igniter_lang' / 'typechecker.rb').to_s

$pass_count = 0
$fail_count = 0

def check(label)
  result = yield
  if result
    puts "  PASS: #{label}"
    $pass_count += 1
  else
    puts "  FAIL: #{label}"
    $fail_count += 1
  end
rescue => e
  puts "  ERROR: #{label} — #{e.class}: #{e.message.lines.first&.strip}"
  $fail_count += 1
end

$compile_cache = {}

def compile(path, tag = nil)
  key = path.to_s
  return $compile_cache[key] if $compile_cache.key?(key)
  tag ||= File.basename(path, '.ig').gsub(/[^a-z0-9_]/, '_')
  out_dir = "/tmp/p9_rsv_#{tag}"
  FileUtils.mkdir_p(out_dir)
  stdout, _stderr, _st = Open3.capture3(COMPILER_BIN, 'compile', path.to_s, '--out', out_dir, '--json')
  result = JSON.parse(stdout.force_encoding('UTF-8'))
  $compile_cache[key] = result
end

def vm_run(igapp_dir, contract_name, inputs)
  tmpfile = Tempfile.new(['p9_rsv_', '.json'])
  tmpfile.write(inputs.to_json)
  tmpfile.close
  stdout, _stderr, _st = Open3.capture3(
    VM_BIN, 'run',
    '--contract', igapp_dir,
    '--inputs',   tmpfile.path,
    '--entry',    contract_name,
    '--json'
  )
  tmpfile.unlink rescue nil
  JSON.parse(stdout.force_encoding('UTF-8'))
rescue => e
  { 'status' => 'vm_error', 'error' => e.message }
end

def has_oof6?(result)
  (result['diagnostics'] || []).any? { |d| d['rule'] == 'OOF-KIND6' }
end

def oof6_messages(result)
  (result['diagnostics'] || []).select { |d| d['rule'] == 'OOF-KIND6' }.map { |d| d['message'] }
end

# ── RESERVE-SCAN ──────────────────────────────────────────────────────────────
puts "\nRESERVE-SCAN — No existing user fixture relies on __* field names"

all_ig = Dir.glob(File.join(ROOT.parent.to_s, 'fixtures', '**', '*.ig'))

check("no user fixture declares __arm as a type field name (not in comment)") do
  all_ig.none? do |f|
    File.readlines(f).any? do |line|
      !line.strip.start_with?('--') && line.match?(/^\s*__arm\s*:/)
    end
  end
end

check("no user fixture declares __variant as a type field name (not in comment)") do
  all_ig.none? do |f|
    File.readlines(f).any? do |line|
      !line.strip.start_with?('--') && line.match?(/^\s*__variant\s*:/)
    end
  end
end

check("'__absent__' in map_vm_ops.ig is a string literal value, not a field name") do
  map_fixture = File.join(ROOT.to_s, 'fixtures', 'vm_map', 'map_vm_ops.ig')
  if File.exist?(map_fixture)
    lines = File.readlines(map_fixture, encoding: 'UTF-8')
    # String literal values ("__absent__") must NOT appear as record field keys
    no_field = lines.none? { |l| !l.strip.start_with?('--') && l.match?(/^\s*__absent__\s*:/) }
    has_value = lines.any? { |l| l.include?('"__absent__"') }
    no_field && has_value
  else
    true
  end
end

check("outcome_variant.ig (11-arm variant) compiles clean — no __* fields present") do
  r = compile(File.join(EPISTEMIC_DIR, 'outcome_variant.ig'), 'scan_outvar')
  r['status'] == 'ok' && !has_oof6?(r)
end

check("reserved_fields_valid.ig compiles clean — normal records/variants pass") do
  r = compile(File.join(FIXTURE_DIR, 'reserved_fields_valid.ig'))
  r['status'] == 'ok' && !has_oof6?(r)
end

# ── RESERVE-TYPE ──────────────────────────────────────────────────────────────
puts "\nRESERVE-TYPE — type declaration with __* field → OOF-KIND6"

type_result = compile(File.join(FIXTURE_DIR, 'reserved_type_field.ig'))

check("reserved_type_field.ig: status=oof") do
  type_result['status'] == 'oof'
end

check("reserved_type_field.ig: OOF-KIND6 fires") do
  has_oof6?(type_result)
end

check("reserved_type_field.ig: OOF-KIND6 message names '__arm'") do
  oof6_messages(type_result).any? { |m| m.include?('__arm') }
end

check("reserved_type_field.ig: OOF-KIND6 message names the type 'BadRecord'") do
  oof6_messages(type_result).any? { |m| m.include?('BadRecord') }
end

name_result = compile(File.join(FIXTURE_DIR, 'reserved_variant_name_field.ig'))

check("reserved_variant_name_field.ig: OOF-KIND6 fires for __variant field") do
  has_oof6?(name_result) && oof6_messages(name_result).any? { |m| m.include?('__variant') }
end

# ── RESERVE-RECORD ────────────────────────────────────────────────────────────
puts "\nRESERVE-RECORD — record literal with __* field → OOF-KIND6"

record_result = compile(File.join(FIXTURE_DIR, 'reserved_record_literal.ig'))

check("reserved_record_literal.ig: status=oof") do
  record_result['status'] == 'oof'
end

check("reserved_record_literal.ig: OOF-KIND6 fires") do
  has_oof6?(record_result)
end

check("reserved_record_literal.ig: OOF-KIND6 fires for __arm field in literal") do
  oof6_messages(record_result).any? { |m| m.include?('__arm') }
end

check("reserved_record_literal.ig: OOF-KIND6 fires for __variant field in literal") do
  oof6_messages(record_result).any? { |m| m.include?('__variant') }
end

check("reserved_record_literal.ig: exactly 2 OOF-KIND6 diagnostics (__arm + __variant)") do
  oof6_messages(record_result).length == 2
end

# ── RESERVE-VARIANT ───────────────────────────────────────────────────────────
puts "\nRESERVE-VARIANT — variant arm payload with __* field → OOF-KIND6"

variant_result = compile(File.join(FIXTURE_DIR, 'reserved_variant_field.ig'))

check("reserved_variant_field.ig: status=oof") do
  variant_result['status'] == 'oof'
end

check("reserved_variant_field.ig: OOF-KIND6 fires") do
  has_oof6?(variant_result)
end

check("reserved_variant_field.ig: OOF-KIND6 message names the arm 'ClashArm'") do
  oof6_messages(variant_result).any? { |m| m.include?('ClashArm') }
end

check("reserved_variant_field.ig: OOF-KIND6 message names variant 'BadVariant'") do
  oof6_messages(variant_result).any? { |m| m.include?('BadVariant') }
end

check("reserved_variant_field.ig: GoodArm (no __* field) does not trigger OOF-KIND6") do
  oof6_messages(variant_result).none? { |m| m.include?('GoodArm') }
end

# ── RESERVE-ALLOW ─────────────────────────────────────────────────────────────
puts "\nRESERVE-ALLOW — normal records, variants, match are not affected"

valid_result = compile(File.join(FIXTURE_DIR, 'reserved_fields_valid.ig'))

check("reserved_fields_valid.ig: status=ok") do
  valid_result['status'] == 'ok'
end

check("reserved_fields_valid.ig: no diagnostics at all") do
  (valid_result['diagnostics'] || []).empty?
end

check("reserved_fields_valid.ig: kind/value/attempt fields pass (not reserved)") do
  (valid_result['diagnostics'] || []).none? { |d| d['rule'] == 'OOF-KIND6' }
end

check("outcome_variant_oof_kind1.ig still fires OOF-KIND1 (not OOF-KIND6)") do
  r = compile(File.join(EPISTEMIC_DIR, 'outcome_variant_oof_kind1.ig'), 'allow_oof1')
  (r['diagnostics'] || []).any? { |d| d['rule'] == 'OOF-KIND1' } &&
    (r['diagnostics'] || []).none? { |d| d['rule'] == 'OOF-KIND6' }
end

check("outcome_variant.ig (11 arms with payload fields): still status=ok after P9 changes") do
  r = compile(File.join(EPISTEMIC_DIR, 'outcome_variant.ig'), 'allow_outvar2')
  r['status'] == 'ok' && !has_oof6?(r)
end

# map_vm_ops.ig — contains "__absent__" as a string VALUE in or_else; must still compile
map_result = compile(File.join(ROOT.to_s, 'fixtures', 'vm_map', 'map_vm_ops.ig'), 'allow_map')
check("map_vm_ops.ig: or_else(opt, \"__absent__\") still compiles — string value, not field name") do
  map_result['status'] == 'ok' && !has_oof6?(map_result)
end

# ── RESERVE-PATHB ─────────────────────────────────────────────────────────────
puts "\nRESERVE-PATHB — compiler-generated variant records still execute in VM"

# Reuse the outcome_variant fixture for end-to-end VM execution
# This proves that the reservation doesn't break Path B lowering.
out_dir = '/tmp/p9_pathb_outvar'
FileUtils.mkdir_p(out_dir)
pathb_r = compile(File.join(EPISTEMIC_DIR, 'outcome_variant.ig'), 'pathb_main')
check("outcome_variant.ig compiles to igapp for VM execution") do
  pathb_r['status'] == 'ok' && pathb_r['igapp_path']
end

igapp_dir = pathb_r['igapp_path'] || '/tmp/p9_pathb_outvar'

check("RouteOutcome: ConfirmedSucceededReal → 'accept' (Path B __arm discriminant works)") do
  r = vm_run(igapp_dir, 'RouteOutcome',
    { 'outcome' => { '__arm' => 'ConfirmedSucceededReal', '__variant' => 'ReconciliationOutcome',
                     'request_id' => 'req-1', 'resource' => 'pay/1' } })
  r['status'] == 'success' && r['result'] == 'accept'
end

check("RouteOutcome: ConfirmedSucceededModel → 'needs_human_review' (not accept)") do
  r = vm_run(igapp_dir, 'RouteOutcome',
    { 'outcome' => { '__arm' => 'ConfirmedSucceededModel', '__variant' => 'ReconciliationOutcome',
                     'request_id' => 'req-2', 'resource' => 'pay/2' } })
  r['status'] == 'success' && r['result'] == 'needs_human_review'
end

check("RouteOutcome: StillUnknownWithBudget → 'reconcile_again'") do
  r = vm_run(igapp_dir, 'RouteOutcome',
    { 'outcome' => { '__arm' => 'StillUnknownWithBudget', '__variant' => 'ReconciliationOutcome',
                     'request_id' => 'req-3', 'attempt' => 2, 'budget_remaining' => 3 } })
  r['status'] == 'success' && r['result'] == 'reconcile_again'
end

check("RouteOutcome: ReconciliationError → 'hold'") do
  r = vm_run(igapp_dir, 'RouteOutcome',
    { 'outcome' => { '__arm' => 'ReconciliationError', '__variant' => 'ReconciliationOutcome',
                     'request_id' => 'req-4', 'detail' => 'timeout' } })
  r['status'] == 'success' && r['result'] == 'hold'
end

# ── RESERVE-CLOSED ────────────────────────────────────────────────────────────
puts "\nRESERVE-CLOSED — closed surfaces unchanged"

check("VM instructions.rs: no OP_MATCH opcode") do
  src = File.read(File.join(VM_SRC_DIR, 'instructions.rs')).force_encoding('UTF-8')
  !src.include?('OP_MATCH')
end

check("VM value.rs: no Value::Variant") do
  src = File.read(File.join(VM_SRC_DIR, 'value.rs')).force_encoding('UTF-8')
  !src.include?('Variant')
end

check("Rust TypeChecker: OOF-KIND6 check targets starts_with('__')") do
  src = File.read(RUST_TC_SRC).force_encoding('UTF-8')
  src.include?('OOF-KIND6') && src.include?('starts_with("__")')
end

check("Ruby TypeChecker: OOF-KIND6 check targets start_with?(\"__\")") do
  src = File.read(RUBY_TC_SRC).force_encoding('UTF-8')
  src.include?('OOF-KIND6') && src.include?('start_with?("__")')
end

check("No new runtime ABI: __arm/__variant not exported as public API in compiler sources") do
  # Compiler should reference __arm/__variant only in Path B lowering, not in public API docs
  # The reservation is a guard, not a promoted API surface.
  rust_tc = File.read(RUST_TC_SRC).force_encoding('UTF-8')
  # OOF-KIND6 message must NOT say "public API" or "stable"
  oof6_lines = rust_tc.lines.select { |l| l.include?('OOF-KIND6') }
  oof6_lines.none? { |l| l.match?(/public.api|stable.abi/i) }
end

# ── Summary ───────────────────────────────────────────────────────────────────
puts "\n" + "─" * 60
total = $pass_count + $fail_count
puts "#{$pass_count}/#{total} PASS"
if $fail_count == 0
  puts "PROP-044-P9: ALL PASS"
else
  puts "PROP-044-P9: #{$fail_count} FAILURE(S)"
  exit 1
end
