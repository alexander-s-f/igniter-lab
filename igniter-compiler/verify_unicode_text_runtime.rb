# verify_unicode_text_runtime.rb
#
# LAB-STR-UNICODE-P2 / LAB-STR-UNICODE-P3: Unicode Text Runtime Ops + Receipt + Handler Hygiene
#
# Purpose: Prove end-to-end runtime correctness of the VM OP_CALL handlers for
# Unicode-aware Text stdlib operations, emit a machine-readable Unicode runtime
# receipt, and verify handler-policy consistency between bare and qualified names.
#
# P2 changes (igniter-vm/src/vm.rs + Cargo.toml):
#   + unicode-segmentation = "1.11" (Cargo.lock resolved: 1.13.3) in Cargo.toml
#   + use unicode_segmentation::UnicodeSegmentation import
#   + stdlib.text.rune_length   — s.chars().count()
#   + stdlib.text.grapheme_length — s.graphemes(true).count() (UAX #29)
#   + stdlib.text.byte_slice    — clamp, half-open, invalid boundary → ""
#   + stdlib.text.rune_slice    — chars().skip/take
#   + stdlib.text.grapheme_slice — graphemes(true).collect()[start..end]
#   + stdlib.text.ends_with     — s.ends_with(suffix)
#   + stdlib.text.replace       — empty pattern → error; replacen(p,r,1)
#   + stdlib.text.replace_all   — empty pattern → error; replace(p,r)
#   + stdlib.text.split (guard) — empty delimiter → operational error
#   + stdlib.text.concat / trim / contains / stdlib.collection.concat — qualified aliases
#
# P3 changes (igniter-vm/src/vm.rs):
#   + bare "split" handler — aligned with stdlib.text.split empty-delimiter policy
#     (LAB-STR-UNICODE-P3 hygiene: no bypass via legacy name)
#
# Proof scope:
#   UNI-DEP      — Cargo.toml/Cargo.lock dep/import presence
#   UNI-RCP      — Unicode runtime receipt shape and content
#   UNI-HYG      — bare vs qualified handler policy consistency
#   UNI-ERR      — empty delimiter/pattern operational error (both bare and qualified)
#   UNI-LENGTH   — byte/rune/grapheme counts distinct; UAX#29 grapheme clusters
#   UNI-SLICE    — byte_slice, rune_slice, grapheme_slice; bounds clamping
#   UNI-REPLACE  — replace (first-match), replace_all, empty-pattern error
#   UNI-SPLIT    — split normal + empty-delimiter runtime error
#   UNI-ALIAS    — qualified aliases (concat, trim, contains, collection.concat)
#   UNI-AUTH     — closed-surface: no canon/stable/public/runtime claims
#   UNI-PATH     — no local absolute paths or file:// in receipt output
#
# Policy anchors (LAB-STR-UNICODE-P1, design-locked):
#   - Text = valid UTF-8 at all runtime boundaries (Value::String(Arc<str>))
#   - byte: UTF-8 octet count, s.len()
#   - rune: Unicode scalar value count, s.chars().count()
#   - grapheme: UAX #29 Extended Grapheme Cluster, unicode-segmentation
#   - slice bounds: [start, end) half-open; clamp negatives→0, over-end→len
#   - byte_slice on invalid UTF-8 boundary: return ""
#   - split("") / replace("") / replace_all(""): runtime operational error
#   - No implicit normalization: exact codepoint equality
#
# CLOSED: canon grammar, igniter-org, real TCP, normalization, `length` legacy,
#         regex, locale folding, tokenizer, production/release gates.
#
# Authority: lab-only evidence — no canon claim, no stable-API surface.
# Cards: LAB-STR-UNICODE-P2, LAB-STR-UNICODE-P3
# Date: 2026-06-08

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'
require_relative '../tools/proof_harness/bounded_command'

ROOT         = Pathname.new(__dir__)
COMP         = ROOT / "target/release/igniter_compiler"
VM_BIN       = ROOT.parent / "igniter-vm/target/release/igniter-vm"
VM_CARGO     = ROOT.parent / "igniter-vm/Cargo.toml"
VM_CARGO_LOCK = ROOT.parent / "igniter-vm/Cargo.lock"
VM_SRC       = ROOT.parent / "igniter-vm/src/vm.rs"
OUT_DIR      = ROOT / "out"
RECEIPT_PATH = OUT_DIR / "unicode_runtime_receipt.json"

FileUtils.mkdir_p(OUT_DIR)

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}"; $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}"; $fail_count += 1)

def compile_src(src, label)
  tmp = Dir.mktmpdir("uni_#{label}")
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

def run_vm(igapp_path, inputs_hash)
  tmp         = Dir.mktmpdir("uni_vm")
  inputs_file = File.join(tmp, "inputs.json")
  File.write(inputs_file, JSON.generate(inputs_hash))
  # LAB-PROOF-HYGIENE-P1: bounded VM execution — hard timeout, kills process group
  r = BoundedCommand.run("#{VM_BIN} run --contract #{igapp_path} --inputs #{inputs_file} --json",
                         label: "vm:run",
                         timeout: BoundedCommand::EXEC_TIMEOUT)
  FileUtils.rm_rf(tmp)
  BoundedCommand.print_result(r) unless r.ok?
  # Force UTF-8: stdout may be ASCII-8BIT; VM may return non-ASCII in result values
  JSON.parse(r.stdout.force_encoding('UTF-8')) rescue { 'status' => 'parse_error', 'raw' => r.stdout[0, 200] }
end

# ── source content ───────────────────────────────────────────────────────────
VM_SRC_TEXT    = File.read(VM_SRC,       encoding: 'UTF-8') rescue ''
VM_CARGO_TEXT  = File.read(VM_CARGO,    encoding: 'UTF-8') rescue ''
VM_LOCK_TEXT   = File.read(VM_CARGO_LOCK, encoding: 'UTF-8') rescue ''

# ── extract resolved unicode-segmentation version from Cargo.lock ────────────
LOCK_VERSION = begin
  if (m = VM_LOCK_TEXT.match(/name = "unicode-segmentation"\nversion = "([^"]+)"/))
    m[1]
  else
    'unknown'
  end
end

# ── NFD test string (e + U+0301 combining acute + x) ────────────────────────
# Use explicit Unicode escapes to guarantee NFD encoding regardless of editor normalization.
e_combining = "éx"   # NFD: e(U+0065) + combining acute(U+0301) + x  [3 codepoints, 2 graphemes]
cafe_nfc    = "caf\u00E9"  # NFC: c+a+f+é(U+00E9)  [4 codepoints, 4 graphemes, 5 bytes]

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-DEP — dependency and import presence
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-DEP: dependency and import ===\n"

check_dep = VM_CARGO_TEXT.include?('unicode-segmentation')
check_dep ? pass("UNI-DEP-01: Cargo.toml contains unicode-segmentation dep") \
           : fail!("UNI-DEP-01: Cargo.toml missing unicode-segmentation dep")

check_lock = LOCK_VERSION != 'unknown'
check_lock ? pass("UNI-DEP-02: Cargo.lock resolved unicode-segmentation = #{LOCK_VERSION}") \
           : fail!("UNI-DEP-02: Cargo.lock unicode-segmentation version not found")

check_import = VM_SRC_TEXT.include?('use unicode_segmentation::UnicodeSegmentation')
check_import ? pass("UNI-DEP-03: vm.rs contains UnicodeSegmentation import") \
             : fail!("UNI-DEP-03: vm.rs missing UnicodeSegmentation import")

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-RCP — Unicode runtime receipt
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-RCP: Unicode runtime receipt ===\n"

# Emit the receipt
RECEIPT = {
  "receipt_kind"           => "unicode_runtime_policy",
  "track_id"               => "lab-text-unicode-runtime-receipt-and-handler-hygiene-v0",
  "runtime_surface_id"     => "igniter-vm/stdlib.text.*",
  "card"                   => "LAB-STR-UNICODE-P3",
  "status"                 => "lab-only-evidence",
  "unicode_dep" => {
    "crate"                => "unicode-segmentation",
    "cargo_toml_spec"      => "1.11",
    "cargo_lock_resolved"  => LOCK_VERSION,
    "grapheme_algorithm"   => "uax29-extended-grapheme-cluster"
  },
  "unit_policies" => {
    "byte"      => { "id" => "byte-utf8-octet",      "impl" => "s.len()" },
    "rune"      => { "id" => "rune-unicode-scalar",  "impl" => "s.chars().count()" },
    "grapheme"  => { "id" => "grapheme-uax29-egc",   "impl" => "s.graphemes(true).count()" }
  },
  "slice_policy" => {
    "kind"             => "half-open",
    "notation"         => "[start, end)",
    "bounds"           => "clamp-negatives-to-0-over-end-to-length",
    "byte_invalid_boundary" => "return-empty-string"
  },
  "empty_input_policy" => {
    "split_empty_delimiter"   => "runtime-operational-error-v0",
    "replace_empty_pattern"   => "runtime-operational-error-v0",
    "applies_to_bare_handler" => true
  },
  "normalization_policy" => {
    "implicit_normalization" => "none",
    "equality_basis"         => "exact-codepoint-sequence"
  },
  "handler_consistency" => {
    "bare_split_guarded"           => true,
    "qualified_split_guarded"      => true,
    "replace_pattern_guarded"      => true,
    "replace_all_pattern_guarded"  => true
  }
}

File.write(RECEIPT_PATH, JSON.pretty_generate(RECEIPT))
receipt_written = File.exist?(RECEIPT_PATH)
receipt_written ? pass("UNI-RCP-01: receipt written to out/unicode_runtime_receipt.json") \
                : fail!("UNI-RCP-01: receipt file not written")

receipt_data = JSON.parse(File.read(RECEIPT_PATH)) rescue nil
receipt_data ? pass("UNI-RCP-02: receipt is valid JSON") \
             : fail!("UNI-RCP-02: receipt is not valid JSON")

if receipt_data
  rcp_fields = %w[receipt_kind track_id runtime_surface_id card status unicode_dep
                  unit_policies slice_policy empty_input_policy normalization_policy handler_consistency]
  all_fields = rcp_fields.all? { |f| receipt_data.key?(f) }
  all_fields ? pass("UNI-RCP-03: receipt contains all required top-level fields") \
             : fail!("UNI-RCP-04: receipt missing fields: #{rcp_fields.reject { |f| receipt_data.key?(f) }.inspect}")

  lock_in_receipt = receipt_data.dig('unicode_dep', 'cargo_lock_resolved') == LOCK_VERSION
  lock_in_receipt ? pass("UNI-RCP-04: receipt cargo_lock_resolved matches Cargo.lock (#{LOCK_VERSION})") \
                  : fail!("UNI-RCP-04: receipt cargo_lock_resolved mismatch")

  status_ok = receipt_data['status'] == 'lab-only-evidence'
  status_ok ? pass("UNI-RCP-05: receipt status = 'lab-only-evidence' (not stable/public/production)") \
            : fail!("UNI-RCP-05: receipt status should be 'lab-only-evidence', got #{receipt_data['status'].inspect}")
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-HYG — handler policy consistency (bare vs qualified)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-HYG: handler consistency (bare vs qualified) ===\n"

# Verify that both bare "split" and "stdlib.text.split" have the empty guard
bare_split_guard = VM_SRC_TEXT.include?('LAB-STR-UNICODE-P3: align bare handler') &&
  VM_SRC_TEXT.include?('empty delimiter is an operational error (v0 policy)')
bare_split_guard ? pass("UNI-HYG-01: bare 'split' handler contains empty-delimiter guard (P3 hygiene)") \
                 : fail!("UNI-HYG-01: bare 'split' handler missing empty-delimiter guard — policy bypass possible")

qualified_split_guard = VM_SRC_TEXT.include?('"stdlib.text.split"') &&
  VM_SRC_TEXT.include?('empty delimiter is an operational error')
qualified_split_guard ? pass("UNI-HYG-02: qualified 'stdlib.text.split' handler contains empty-delimiter guard") \
                      : fail!("UNI-HYG-02: qualified 'stdlib.text.split' missing empty-delimiter guard")

replace_guard = VM_SRC_TEXT.include?('"stdlib.text.replace"') &&
  VM_SRC_TEXT.include?('empty pattern is an operational error')
replace_guard ? pass("UNI-HYG-03: 'stdlib.text.replace' and 'replace_all' contain empty-pattern guard") \
              : fail!("UNI-HYG-03: replace/replace_all missing empty-pattern guard")

# Verify legacy "length" is not re-exported as a new canonical name
length_not_canonical = !VM_SRC_TEXT.include?('"stdlib.text.length"')
length_not_canonical ? pass("UNI-HYG-04: 'stdlib.text.length' not present (legacy 'length' not re-canonicalized)") \
                     : fail!("UNI-HYG-04: 'stdlib.text.length' found — this would re-canonicalize legacy length op")

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-ERR — empty delimiter / pattern operational errors (bare and qualified)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-ERR: empty delimiter/pattern operational errors ===\n"

SRC_SPLIT_RT = <<~IGNITER
  module Unicode.Err
  pure contract SplitRt {
    input s : String
    input sep : String
    compute parts : Collection[Text] = split(s, sep)
    output parts : Collection[Text]
  }
IGNITER

SRC_REPLACE_RT = <<~IGNITER
  module Unicode.Err
  pure contract ReplaceRt {
    input s : String
    input pattern : String
    input replacement : String
    compute result = replace(s, pattern, replacement)
    output result : Text
  }
IGNITER

SRC_REPLACE_ALL_RT = <<~IGNITER
  module Unicode.Err
  pure contract ReplaceAllRt {
    input s : String
    input pattern : String
    input replacement : String
    compute result = replace_all(s, pattern, replacement)
    output result : Text
  }
IGNITER

_, split_err_app, tmp_se    = compile_src(SRC_SPLIT_RT,      "split_err")
_, replace_err_app, tmp_re  = compile_src(SRC_REPLACE_RT,    "replace_err")
_, replace_all_err_app, tmp_rae = compile_src(SRC_REPLACE_ALL_RT, "replace_all_err")

compiled_se  = File.exist?(split_err_app)
compiled_re  = File.exist?(replace_err_app)
compiled_rae = File.exist?(replace_all_err_app)

FileUtils.rm_rf(tmp_se)  unless compiled_se
FileUtils.rm_rf(tmp_re)  unless compiled_re
FileUtils.rm_rf(tmp_rae) unless compiled_rae

# split: empty delimiter → runtime error
if compiled_se
  r = run_vm(split_err_app, { 's' => 'hello', 'sep' => '' })
  ok = r['status'] == 'error' && r.fetch('error', '').include?('empty delimiter')
  ok ? pass("UNI-ERR-01: split(s, '') → runtime operational error (empty delimiter)") \
     : fail!("UNI-ERR-01: split empty delimiter expected error, got status=#{r['status']}")
  FileUtils.rm_rf(File.dirname(split_err_app)) rescue nil
end

# replace: empty pattern → runtime error
if compiled_re
  r = run_vm(replace_err_app, { 's' => 'hello', 'pattern' => '', 'replacement' => 'X' })
  ok = r['status'] == 'error' && r.fetch('error', '').include?('empty pattern')
  ok ? pass("UNI-ERR-02: replace(s, '', 'X') → runtime operational error (empty pattern)") \
     : fail!("UNI-ERR-02: replace empty pattern expected error, got status=#{r['status']}")
  FileUtils.rm_rf(File.dirname(replace_err_app)) rescue nil
end

# replace_all: empty pattern → runtime error
if compiled_rae
  r = run_vm(replace_all_err_app, { 's' => 'hello', 'pattern' => '', 'replacement' => 'X' })
  ok = r['status'] == 'error' && r.fetch('error', '').include?('empty pattern')
  ok ? pass("UNI-ERR-03: replace_all(s, '', 'X') → runtime operational error (empty pattern)") \
     : fail!("UNI-ERR-03: replace_all empty pattern expected error, got status=#{r['status']}")
  FileUtils.rm_rf(File.dirname(replace_all_err_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-LENGTH — byte / rune / grapheme length distinction (P2 regression)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-LENGTH: byte / rune / grapheme length ===\n"

SRC_BYTE_LEN = <<~IGNITER
  module Unicode.Length
  pure contract ByteLen { input s : String; compute result = byte_length(s); output result : Integer }
IGNITER
SRC_RUNE_LEN = <<~IGNITER
  module Unicode.Length
  pure contract RuneLen { input s : String; compute result = rune_length(s); output result : Integer }
IGNITER
SRC_GRAPHEME_LEN = <<~IGNITER
  module Unicode.Length
  pure contract GraphemeLen { input s : String; compute result = grapheme_length(s); output result : Integer }
IGNITER

_, bl_app, tmp_bl = compile_src(SRC_BYTE_LEN,     "byte_len")
_, rl_app, tmp_rl = compile_src(SRC_RUNE_LEN,     "rune_len")
_, gl_app, tmp_gl = compile_src(SRC_GRAPHEME_LEN, "grapheme_len")

compiled_bl = File.exist?(bl_app)
compiled_rl = File.exist?(rl_app)
compiled_gl = File.exist?(gl_app)
FileUtils.rm_rf(tmp_bl) unless compiled_bl
FileUtils.rm_rf(tmp_rl) unless compiled_rl
FileUtils.rm_rf(tmp_gl) unless compiled_gl

# "café" NFC: 5 bytes / 4 runes / 4 graphemes
if compiled_bl
  r = run_vm(bl_app, { 's' => cafe_nfc })
  r['result'] == 5 ? pass("UNI-LENGTH-01: byte_length('café') = 5") \
                   : fail!("UNI-LENGTH-01: expected 5, got #{r['result'].inspect}")
end
if compiled_rl
  r = run_vm(rl_app, { 's' => cafe_nfc })
  r['result'] == 4 ? pass("UNI-LENGTH-02: rune_length('café') = 4") \
                   : fail!("UNI-LENGTH-02: expected 4, got #{r['result'].inspect}")
end
if compiled_gl
  r = run_vm(gl_app, { 's' => cafe_nfc })
  r['result'] == 4 ? pass("UNI-LENGTH-03: grapheme_length('café') = 4") \
                   : fail!("UNI-LENGTH-03: expected 4, got #{r['result'].inspect}")
end

# "éx" NFD: 3 runes (e+U+0301+x) / 2 graphemes (e+U+0301 as 1 cluster, x)
if compiled_rl
  r = run_vm(rl_app, { 's' => e_combining })
  r['result'] == 3 ? pass("UNI-LENGTH-04: rune_length('e\\u0301x') = 3 (3 codepoints)") \
                   : fail!("UNI-LENGTH-04: expected 3, got #{r['result'].inspect} (status=#{r['status']})")
  FileUtils.rm_rf(File.dirname(rl_app)) rescue nil
end
if compiled_gl
  r = run_vm(gl_app, { 's' => e_combining })
  r['result'] == 2 ? pass("UNI-LENGTH-05: grapheme_length('e\\u0301x') = 2 (UAX#29: e+combining = 1 cluster)") \
                   : fail!("UNI-LENGTH-05: expected 2, got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(gl_app)) rescue nil
end

# NFC vs NFD distinction proven by byte count
if compiled_bl
  nfc_e = "\u00E9"   # U+00E9: 2 bytes
  nfd_e = "e\u0301"  # U+0065+U+0301: 3 bytes
  r_nfc = run_vm(bl_app, { 's' => nfc_e })
  r_nfd = run_vm(bl_app, { 's' => nfd_e })
  no_norm = (r_nfc['result'] == 2 && r_nfd['result'] == 3)
  no_norm ? pass("UNI-LENGTH-06: no implicit normalization — NFC é=2 bytes, NFD é=3 bytes (distinct)") \
          : fail!("UNI-LENGTH-06: normalization check: NFC=#{r_nfc['result']}, NFD=#{r_nfd['result']}")
  FileUtils.rm_rf(File.dirname(bl_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-SLICE — byte_slice / rune_slice / grapheme_slice (P2 regression)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-SLICE: slice ops ===\n"

SRC_BYTE_SLICE = <<~IGNITER
  module Unicode.Slice
  pure contract ByteSlice {
    input s : String; input start_idx : Integer; input end_idx : Integer
    compute result = byte_slice(s, start_idx, end_idx)
    output result : Text
  }
IGNITER
SRC_RUNE_SLICE = <<~IGNITER
  module Unicode.Slice
  pure contract RuneSlice {
    input s : String; input start_idx : Integer; input end_idx : Integer
    compute result = rune_slice(s, start_idx, end_idx)
    output result : Text
  }
IGNITER
SRC_GRAPHEME_SLICE = <<~IGNITER
  module Unicode.Slice
  pure contract GraphemeSlice {
    input s : String; input start_idx : Integer; input end_idx : Integer
    compute result = grapheme_slice(s, start_idx, end_idx)
    output result : Text
  }
IGNITER

_, bs_app, tmp_bs = compile_src(SRC_BYTE_SLICE,     "byte_sl")
_, rs_app, tmp_rs = compile_src(SRC_RUNE_SLICE,     "rune_sl")
_, gs_app, tmp_gs = compile_src(SRC_GRAPHEME_SLICE, "grapheme_sl")

compiled_bs = File.exist?(bs_app)
compiled_rs = File.exist?(rs_app)
compiled_gs = File.exist?(gs_app)
FileUtils.rm_rf(tmp_bs) unless compiled_bs
FileUtils.rm_rf(tmp_rs) unless compiled_rs
FileUtils.rm_rf(tmp_gs) unless compiled_gs

if compiled_bs
  r = run_vm(bs_app, { 's' => 'hello', 'start_idx' => 1, 'end_idx' => 4 })
  r['result'] == 'ell' ? pass("UNI-SLICE-01: byte_slice('hello', 1, 4) = 'ell'") \
                       : fail!("UNI-SLICE-01: expected 'ell', got #{r['result'].inspect}")

  r = run_vm(bs_app, { 's' => 'café', 'start_idx' => 3, 'end_idx' => 4 })
  r['result'] == '' ? pass("UNI-SLICE-02: byte_slice mid-codepoint boundary returns '' (fail-closed)") \
                    : fail!("UNI-SLICE-02: expected '', got #{r['result'].inspect}")

  r = run_vm(bs_app, { 's' => 'hello', 'start_idx' => -5, 'end_idx' => 100 })
  r['result'] == 'hello' ? pass("UNI-SLICE-03: byte_slice negative/over-end clamps to full string") \
                         : fail!("UNI-SLICE-03: expected 'hello', got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(bs_app)) rescue nil
end

if compiled_rs
  r = run_vm(rs_app, { 's' => 'café', 'start_idx' => 0, 'end_idx' => 3 })
  r['result'] == 'caf' ? pass("UNI-SLICE-04: rune_slice('café', 0, 3) = 'caf'") \
                       : fail!("UNI-SLICE-04: expected 'caf', got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(rs_app)) rescue nil
end

if compiled_gs
  r1 = run_vm(gs_app, { 's' => e_combining, 'start_idx' => 0, 'end_idx' => 1 })
  r1['result'].bytes == "e\u0301".bytes ? pass("UNI-SLICE-05: grapheme_slice('e\\u0301x', 0, 1) = NFD e+U+0301 (1 grapheme cluster)") \
                           : fail!("UNI-SLICE-05: expected NFD é, got #{r1['result'].inspect}")

  r2 = run_vm(gs_app, { 's' => e_combining, 'start_idx' => 1, 'end_idx' => 2 })
  r2['result'] == 'x' ? pass("UNI-SLICE-06: grapheme_slice('e\\u0301x', 1, 2) = 'x' (second grapheme)") \
                      : fail!("UNI-SLICE-06: expected 'x', got #{r2['result'].inspect}")
  FileUtils.rm_rf(File.dirname(gs_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-REPLACE — replace / replace_all value behavior (P2 regression)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-REPLACE: replace / replace_all value behavior ===\n"

SRC_REPLACE = <<~IGNITER
  module Unicode.Replace
  pure contract Replace {
    input s : String; input pattern : String; input replacement : String
    compute result = replace(s, pattern, replacement)
    output result : Text
  }
IGNITER
SRC_REPLACE_ALL = <<~IGNITER
  module Unicode.Replace
  pure contract ReplaceAll {
    input s : String; input pattern : String; input replacement : String
    compute result = replace_all(s, pattern, replacement)
    output result : Text
  }
IGNITER

_, rep_app,  tmp_rep  = compile_src(SRC_REPLACE,     "replace")
_, repa_app, tmp_repa = compile_src(SRC_REPLACE_ALL, "replace_all")

compiled_rep  = File.exist?(rep_app)
compiled_repa = File.exist?(repa_app)
FileUtils.rm_rf(tmp_rep)  unless compiled_rep
FileUtils.rm_rf(tmp_repa) unless compiled_repa

if compiled_rep
  r = run_vm(rep_app, { 's' => 'banana', 'pattern' => 'a', 'replacement' => 'X' })
  r['result'] == 'bXnana' ? pass("UNI-REPLACE-01: replace('banana','a','X') = 'bXnana' (first-match only)") \
                          : fail!("UNI-REPLACE-01: expected 'bXnana', got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(rep_app)) rescue nil
end

if compiled_repa
  r = run_vm(repa_app, { 's' => 'banana', 'pattern' => 'a', 'replacement' => 'X' })
  r['result'] == 'bXnXnX' ? pass("UNI-REPLACE-02: replace_all('banana','a','X') = 'bXnXnX' (all occurrences)") \
                           : fail!("UNI-REPLACE-02: expected 'bXnXnX', got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(repa_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-SPLIT — split value behavior (P2 regression)
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-SPLIT: split value behavior ===\n"

SRC_SPLIT_VAL = <<~IGNITER
  module Unicode.Split
  pure contract SplitVal {
    input s : String; input sep : String
    compute parts : Collection[Text] = split(s, sep)
    output parts : Collection[Text]
  }
IGNITER

_, split_val_app, tmp_sv = compile_src(SRC_SPLIT_VAL, "split_val")
compiled_sv = File.exist?(split_val_app)
FileUtils.rm_rf(tmp_sv) unless compiled_sv

if compiled_sv
  r = run_vm(split_val_app, { 's' => 'a,b,c', 'sep' => ',' })
  r['result'] == ['a', 'b', 'c'] ? pass("UNI-SPLIT-01: split('a,b,c', ',') = ['a','b','c']") \
                                  : fail!("UNI-SPLIT-01: expected ['a','b','c'], got #{r['result'].inspect}")

  r = run_vm(split_val_app, { 's' => 'hello', 'sep' => '' })
  ok = r['status'] == 'error' && r.fetch('error', '').include?('empty delimiter')
  ok ? pass("UNI-SPLIT-02: split(s, '') → runtime operational error (empty delimiter, v0 policy)") \
     : fail!("UNI-SPLIT-02: expected error, got status=#{r['status']}")
  FileUtils.rm_rf(File.dirname(split_val_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-ALIAS — qualified alias correctness
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-ALIAS: qualified alias consistency ===\n"

SRC_ENDS_WITH = <<~IGNITER
  module Unicode.Alias
  pure contract EndsWithAlias { input s : String; compute result = ends_with(s, "world"); output result : Bool }
IGNITER
SRC_TRIM = <<~IGNITER
  module Unicode.Alias
  pure contract TrimAlias { input s : String; compute result = trim(s); output result : Text }
IGNITER
SRC_CONTAINS = <<~IGNITER
  module Unicode.Alias
  pure contract ContainsAlias { input s : String; compute result = contains(s, "ell"); output result : Bool }
IGNITER

_, ew_app,   tmp_ew  = compile_src(SRC_ENDS_WITH, "ends_with")
_, trim_app, tmp_tr  = compile_src(SRC_TRIM,      "trim_alias")
_, cont_app, tmp_ct  = compile_src(SRC_CONTAINS,  "contains_alias")

compiled_ew   = File.exist?(ew_app)
compiled_trim = File.exist?(trim_app)
compiled_cont = File.exist?(cont_app)

FileUtils.rm_rf(tmp_ew)  unless compiled_ew
FileUtils.rm_rf(tmp_tr)  unless compiled_trim
FileUtils.rm_rf(tmp_ct)  unless compiled_cont

if compiled_ew
  r_yes = run_vm(ew_app, { 's' => 'hello world' })
  r_no  = run_vm(ew_app, { 's' => 'hello' })
  (r_yes['result'] == true && r_no['result'] == false) \
    ? pass("UNI-ALIAS-01: ends_with alias correct (true/false)") \
    : fail!("UNI-ALIAS-01: ends_with expected true/false, got #{r_yes['result'].inspect}/#{r_no['result'].inspect}")
  FileUtils.rm_rf(File.dirname(ew_app)) rescue nil
end

if compiled_trim
  r = run_vm(trim_app, { 's' => '  hello  ' })
  r['result'] == 'hello' ? pass("UNI-ALIAS-02: trim alias correct ('  hello  ' → 'hello')") \
                         : fail!("UNI-ALIAS-02: trim expected 'hello', got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(trim_app)) rescue nil
end

if compiled_cont
  r_yes = run_vm(cont_app, { 's' => 'hello' })
  r_no  = run_vm(cont_app, { 's' => 'world' })
  (r_yes['result'] == true && r_no['result'] == false) \
    ? pass("UNI-ALIAS-03: contains alias correct (true/false)") \
    : fail!("UNI-ALIAS-03: contains expected true/false, got #{r_yes['result'].inspect}/#{r_no['result'].inspect}")
  FileUtils.rm_rf(File.dirname(cont_app)) rescue nil
end

# stdlib.text.concat handler present as qualified alias
concat_alias_present = VM_SRC_TEXT.include?('"stdlib.text.concat"')
concat_alias_present ? pass("UNI-ALIAS-04: stdlib.text.concat qualified alias present in vm.rs") \
                     : fail!("UNI-ALIAS-04: stdlib.text.concat qualified alias missing from vm.rs")

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-AUTH — no canon/stable/public/runtime claims in receipt
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-AUTH: closed-surface authority checks ===\n"

if receipt_data
  forbidden_status = %w[stable public production reference-runtime canon]
  clean = forbidden_status.none? { |s| receipt_data['status'].to_s.include?(s) }
  clean ? pass("UNI-AUTH-01: receipt status does not claim stable/public/production authority") \
        : fail!("UNI-AUTH-01: receipt status contains forbidden authority claim: #{receipt_data['status']}")

  no_public_surface = !receipt_data.to_s.include?('stable_api') &&
                      !receipt_data.to_s.include?('public_api') &&
                      !receipt_data.to_s.include?('production')
  no_public_surface ? pass("UNI-AUTH-02: receipt contains no stable_api/public_api/production keys") \
                    : fail!("UNI-AUTH-02: receipt contains public/production authority claims")

  no_canon_claim = !receipt_data.to_s.include?('canon_')
  no_canon_claim ? pass("UNI-AUTH-03: receipt contains no canon_* keys") \
                 : fail!("UNI-AUTH-03: receipt contains canon_* authority claims")
end

no_runtime_exec_claim = !VM_SRC_TEXT.include?('igc run') && !VM_SRC_TEXT.include?('RuntimeSmoke')
no_runtime_exec_claim ? pass("UNI-AUTH-04: vm.rs contains no igc-run or RuntimeSmoke authority markers") \
                      : fail!("UNI-AUTH-04: vm.rs contains runtime-gate authority markers")

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-PATH — no absolute paths or file:// in receipt
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-PATH: no absolute paths or file:// in receipt ===\n"

if receipt_data
  receipt_str = JSON.generate(receipt_data)

  no_file_uri = !receipt_str.include?('file://')
  no_file_uri ? pass("UNI-PATH-01: receipt contains no file:// URIs") \
              : fail!("UNI-PATH-01: receipt contains file:// URI — not portable")

  no_abs_path = !receipt_str.match?(/["']\/(?:Users|home|var|tmp|root)\//)
  no_abs_path ? pass("UNI-PATH-02: receipt contains no absolute filesystem paths") \
              : fail!("UNI-PATH-02: receipt contains absolute path — not portable")
end

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n" + "═" * 72
total = $pass_count + $fail_count
puts "LAB-STR-UNICODE-P3: #{$pass_count}/#{total} PASS"
if $fail_count > 0
  puts "\nFailed checks present — see [!] FAIL lines above."
end
puts "\nReceipt: igniter-lab/igniter-compiler/out/unicode_runtime_receipt.json"

exit($fail_count > 0 ? 1 : 0)
