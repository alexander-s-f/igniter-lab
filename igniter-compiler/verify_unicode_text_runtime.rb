# verify_unicode_text_runtime.rb
#
# LAB-STR-UNICODE-P2: Unicode Text Runtime Ops
#
# Purpose: Prove end-to-end runtime correctness of the new VM OP_CALL handlers
# for Unicode-aware Text stdlib operations added in LAB-STR-UNICODE-P2.
#
# Changes proved here (igniter-vm/src/vm.rs + Cargo.toml):
#   + unicode-segmentation = "1.11" in Cargo.toml
#   + use unicode_segmentation::UnicodeSegmentation import
#   + stdlib.text.rune_length   — s.chars().count()
#   + stdlib.text.grapheme_length — s.graphemes(true).count() (UAX #29)
#   + stdlib.text.byte_slice    — clamp, half-open, invalid boundary → ""
#   + stdlib.text.rune_slice    — chars().skip/take
#   + stdlib.text.grapheme_slice — graphemes(true).collect()[start..end]
#   + stdlib.text.ends_with     — s.ends_with(suffix)
#   + stdlib.text.replace       — empty pattern → error; replacen(p, r, 1)
#   + stdlib.text.replace_all   — empty pattern → error; replace(p, r)
#   + stdlib.text.split (guard) — empty delimiter → operational error
#
# Proof scope:
#   UNI-DEP      — Cargo.toml and vm.rs source contain the dep/import
#   UNI-LENGTH   — byte/rune/grapheme counts distinct; UAX#29 grapheme clusters
#   UNI-SLICE    — byte_slice, rune_slice, grapheme_slice; bounds clamping
#   UNI-REPLACE  — replace (first-match), replace_all, empty-pattern error
#   UNI-SPLIT    — empty delimiter is a runtime operational error
#   UNI-CLOSED   — closed-surface scan: no real TCP, no normalization claim
#   UNI-REG      — regression: byte_length + starts_with + split still work
#
# Policy anchors (LAB-STR-UNICODE-P1, design-locked):
#   - Text = valid UTF-8 at all runtime boundaries (Value::String(Arc<str>))
#   - byte: UTF-8 octet count, s.len()
#   - rune: Unicode scalar value count, s.chars().count()
#   - grapheme: UAX #29 Extended Grapheme Cluster, unicode-segmentation
#   - slice bounds: [start, end) half-open; clamp negatives→0, over-end→len
#   - byte_slice on invalid UTF-8 boundary: return ""
#   - split("") / replace("") / replace_all(""): runtime operational error
#
# CLOSED: canon grammar, igniter-org, real TCP, normalization, `length` legacy,
#         regex, locale folding, tokenizer, production/release gates.
#
# Authority: lab-only evidence — no canon claim, no stable-API surface.
# Card: LAB-STR-UNICODE-P2
# Date: 2026-06-08

require 'json'
require 'tmpdir'
require 'fileutils'
require 'pathname'

ROOT         = Pathname.new(__dir__)
COMP         = ROOT / "target/release/igniter_compiler"
VM_BIN       = ROOT.parent / "igniter-vm/target/release/igniter-vm"
VM_CARGO     = ROOT.parent / "igniter-vm/Cargo.toml"
VM_SRC       = ROOT.parent / "igniter-vm/src/vm.rs"

$pass_count = 0
$fail_count = 0

def pass(msg)  = (puts "[+] PASS: #{msg}"; $pass_count += 1)
def fail!(msg) = (puts "[!] FAIL: #{msg}"; $fail_count += 1)

def compile_src(src, label)
  tmp = Dir.mktmpdir("uni_#{label}")
  ig  = File.join(tmp, "#{label}.ig")
  out = File.join(tmp, "#{label}.igapp")
  File.write(ig, src)
  result = `#{COMP} compile #{ig} --out #{out} 2>&1`
  [result, out, tmp]
end

def run_vm(igapp_path, inputs_hash)
  tmp = Dir.mktmpdir("uni_vm")
  inputs_file = File.join(tmp, "inputs.json")
  File.write(inputs_file, JSON.generate(inputs_hash))
  out = `#{VM_BIN} run --contract #{igapp_path} --inputs #{inputs_file} --json 2>/dev/null`
  FileUtils.rm_rf(tmp)
  # Force UTF-8: backtick output is ASCII-8BIT; VM may return non-ASCII in result values
  JSON.parse(out.force_encoding('UTF-8')) rescue { 'status' => 'parse_error', 'raw' => out[0, 200] }
end

# ── source content ──────────────────────────────────────────────────────────────
VM_SRC_TEXT   = File.read(VM_SRC)   rescue ''
VM_CARGO_TEXT = File.read(VM_CARGO) rescue ''

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-DEP — dependency and import presence
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-DEP: unicode-segmentation dependency and import ===\n"

check_dep = VM_CARGO_TEXT.include?('unicode-segmentation')
check_dep ? pass("UNI-DEP-01: Cargo.toml contains unicode-segmentation dep") \
           : fail!("UNI-DEP-01: Cargo.toml missing unicode-segmentation dep")

check_import = VM_SRC_TEXT.include?('use unicode_segmentation::UnicodeSegmentation')
check_import ? pass("UNI-DEP-02: vm.rs contains UnicodeSegmentation import") \
             : fail!("UNI-DEP-02: vm.rs missing UnicodeSegmentation import")

check_rl = VM_SRC_TEXT.include?('"stdlib.text.rune_length"')
check_rl ? pass("UNI-DEP-03: vm.rs contains stdlib.text.rune_length handler") \
          : fail!("UNI-DEP-03: vm.rs missing stdlib.text.rune_length handler")

check_gl = VM_SRC_TEXT.include?('"stdlib.text.grapheme_length"')
check_gl ? pass("UNI-DEP-04: vm.rs contains stdlib.text.grapheme_length handler") \
          : fail!("UNI-DEP-04: vm.rs missing stdlib.text.grapheme_length handler")

check_gs = VM_SRC_TEXT.include?('"stdlib.text.grapheme_slice"')
check_gs ? pass("UNI-DEP-05: vm.rs contains stdlib.text.grapheme_slice handler") \
          : fail!("UNI-DEP-05: vm.rs missing stdlib.text.grapheme_slice handler")

check_rep = VM_SRC_TEXT.include?('"stdlib.text.replace"')
check_rep ? pass("UNI-DEP-06: vm.rs contains stdlib.text.replace handler") \
           : fail!("UNI-DEP-06: vm.rs missing stdlib.text.replace handler")

check_repa = VM_SRC_TEXT.include?('"stdlib.text.replace_all"')
check_repa ? pass("UNI-DEP-07: vm.rs contains stdlib.text.replace_all handler") \
            : fail!("UNI-DEP-07: vm.rs missing stdlib.text.replace_all handler")

check_ew = VM_SRC_TEXT.include?('"stdlib.text.ends_with"')
check_ew ? pass("UNI-DEP-08: vm.rs contains stdlib.text.ends_with handler") \
          : fail!("UNI-DEP-08: vm.rs missing stdlib.text.ends_with handler")

check_split_guard = VM_SRC_TEXT.include?('empty delimiter is an operational error')
check_split_guard ? pass("UNI-DEP-09: vm.rs split handler contains empty-delimiter guard") \
                  : fail!("UNI-DEP-09: vm.rs split handler missing empty-delimiter guard")

check_rep_guard = VM_SRC_TEXT.include?('empty pattern is an operational error')
check_rep_guard ? pass("UNI-DEP-10: vm.rs replace handler contains empty-pattern guard") \
                : fail!("UNI-DEP-10: vm.rs replace handler missing empty-pattern guard")

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-LENGTH — byte / rune / grapheme length distinction
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-LENGTH: byte / rune / grapheme length (runtime) ===\n"

# "café" NFC: c(1) + a(1) + f(1) + é(2) = 5 bytes, 4 runes, 4 graphemes
# (U+00E9 = 2 UTF-8 bytes; single codepoint, single grapheme)
SRC_BYTE_LEN = <<~IGNITER
  module Unicode.Length
  pure contract ByteLenProof {
    input s : String
    compute result = byte_length(s)
    output result : Integer
  }
IGNITER

SRC_RUNE_LEN = <<~IGNITER
  module Unicode.Length
  pure contract RuneLenProof {
    input s : String
    compute result = rune_length(s)
    output result : Integer
  }
IGNITER

SRC_GRAPHEME_LEN = <<~IGNITER
  module Unicode.Length
  pure contract GraphemeLenProof {
    input s : String
    compute result = grapheme_length(s)
    output result : Integer
  }
IGNITER

# Compile all length contracts
_, byte_len_app, tmp1 = compile_src(SRC_BYTE_LEN, "byte_len")
compiled_byte = File.exist?(byte_len_app)
FileUtils.rm_rf(tmp1) unless compiled_byte
compiled_byte ? pass("UNI-LENGTH-01: byte_length contract compiles") \
              : fail!("UNI-LENGTH-01: byte_length contract failed to compile")

_, rune_len_app, tmp2 = compile_src(SRC_RUNE_LEN, "rune_len")
compiled_rune = File.exist?(rune_len_app)
FileUtils.rm_rf(tmp2) unless compiled_rune
compiled_rune ? pass("UNI-LENGTH-02: rune_length contract compiles") \
              : fail!("UNI-LENGTH-02: rune_length contract failed to compile")

_, grapheme_len_app, tmp3 = compile_src(SRC_GRAPHEME_LEN, "grapheme_len")
compiled_grapheme = File.exist?(grapheme_len_app)
FileUtils.rm_rf(tmp3) unless compiled_grapheme
compiled_grapheme ? pass("UNI-LENGTH-03: grapheme_length contract compiles") \
                  : fail!("UNI-LENGTH-03: grapheme_length contract failed to compile")

# Runtime: "café" (NFC: U+0063 U+0061 U+0066 U+00E9) = 5 bytes, 4 runes, 4 graphemes
cafe_nfc = "café"

if compiled_byte
  r = run_vm(byte_len_app, { 's' => cafe_nfc })
  r['result'] == 5 ? pass("UNI-LENGTH-04: byte_length('café') = 5 (UTF-8 byte count)") \
                   : fail!("UNI-LENGTH-04: byte_length('café') expected 5, got #{r['result']} (status=#{r['status']})")
  FileUtils.rm_rf(File.dirname(byte_len_app))
end

if compiled_rune
  r = run_vm(rune_len_app, { 's' => cafe_nfc })
  r['result'] == 4 ? pass("UNI-LENGTH-05: rune_length('café') = 4 (Unicode scalar value count)") \
                   : fail!("UNI-LENGTH-05: rune_length('café') expected 4, got #{r['result']} (status=#{r['status']})")
  # Note: do NOT clean up rune_len_app yet — LENGTH-07 uses it again below
end

if compiled_grapheme
  r = run_vm(grapheme_len_app, { 's' => cafe_nfc })
  r['result'] == 4 ? pass("UNI-LENGTH-06: grapheme_length('café') = 4 (UAX#29 grapheme clusters)") \
                   : fail!("UNI-LENGTH-06: grapheme_length('café') expected 4, got #{r['result']} (status=#{r['status']})")
end

# UAX #29 key property: "é" = e + combining acute = 2 runes, 1 grapheme
# "éx" = 3 runes, 2 graphemes
e_combining = "éx"  # NFD-style: e + U+0301 (combining acute) + x

if compiled_rune
  r = run_vm(rune_len_app, { 's' => e_combining })
  r['result'] == 3 ? pass("UNI-LENGTH-07: rune_length('e\\u0301x') = 3 (3 codepoints)") \
                   : fail!("UNI-LENGTH-07: rune_length('e\\u0301x') expected 3, got #{r['result'].inspect} (status=#{r['status']})")
  FileUtils.rm_rf(File.dirname(rune_len_app)) rescue nil  # cleanup deferred to here from LENGTH-05
end

if compiled_grapheme
  r = run_vm(grapheme_len_app, { 's' => e_combining })
  r['result'] == 2 ? pass("UNI-LENGTH-08: grapheme_length('e\\u0301x') = 2 (UAX#29: e+combining = 1 grapheme)") \
                   : fail!("UNI-LENGTH-08: grapheme_length('e\\u0301x') expected 2, got #{r['result']}")
  FileUtils.rm_rf(File.dirname(grapheme_len_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-SLICE — byte_slice, rune_slice, grapheme_slice
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-SLICE: byte_slice / rune_slice / grapheme_slice (runtime) ===\n"

SRC_BYTE_SLICE = <<~IGNITER
  module Unicode.Slice
  pure contract ByteSliceProof {
    input s : String
    input start_idx : Integer
    input end_idx : Integer
    compute result = byte_slice(s, start_idx, end_idx)
    output result : Text
  }
IGNITER

SRC_RUNE_SLICE = <<~IGNITER
  module Unicode.Slice
  pure contract RuneSliceProof {
    input s : String
    input start_idx : Integer
    input end_idx : Integer
    compute result = rune_slice(s, start_idx, end_idx)
    output result : Text
  }
IGNITER

SRC_GRAPHEME_SLICE = <<~IGNITER
  module Unicode.Slice
  pure contract GraphemeSliceProof {
    input s : String
    input start_idx : Integer
    input end_idx : Integer
    compute result = grapheme_slice(s, start_idx, end_idx)
    output result : Text
  }
IGNITER

_, byte_slice_app, tmp4   = compile_src(SRC_BYTE_SLICE,     "byte_slice")
_, rune_slice_app, tmp5   = compile_src(SRC_RUNE_SLICE,     "rune_slice")
_, grapheme_slice_app, tmp6 = compile_src(SRC_GRAPHEME_SLICE, "grapheme_slice")

compiled_bs = File.exist?(byte_slice_app)
compiled_rs = File.exist?(rune_slice_app)
compiled_gs = File.exist?(grapheme_slice_app)

FileUtils.rm_rf(tmp4) unless compiled_bs
FileUtils.rm_rf(tmp5) unless compiled_rs
FileUtils.rm_rf(tmp6) unless compiled_gs

compiled_bs ? pass("UNI-SLICE-01: byte_slice contract compiles") \
            : fail!("UNI-SLICE-01: byte_slice contract failed to compile")
compiled_rs ? pass("UNI-SLICE-02: rune_slice contract compiles") \
            : fail!("UNI-SLICE-02: rune_slice contract failed to compile")
compiled_gs ? pass("UNI-SLICE-03: grapheme_slice contract compiles") \
            : fail!("UNI-SLICE-03: grapheme_slice contract failed to compile")

# byte_slice("hello", 1, 4) = "ell"
if compiled_bs
  r = run_vm(byte_slice_app, { 's' => 'hello', 'start_idx' => 1, 'end_idx' => 4 })
  r['result'] == 'ell' ? pass("UNI-SLICE-04: byte_slice('hello', 1, 4) = 'ell'") \
                        : fail!("UNI-SLICE-04: byte_slice('hello', 1, 4) expected 'ell', got #{r['result'].inspect}")
end

# byte_slice("café", 3, 4) — byte 3 is mid-codepoint of U+00E9 (2 bytes: 0xC3 0xA9) → ""
if compiled_bs
  r = run_vm(byte_slice_app, { 's' => 'café', 'start_idx' => 3, 'end_idx' => 4 })
  r['result'] == '' ? pass("UNI-SLICE-05: byte_slice mid-codepoint boundary returns '' (fail-closed)") \
                    : fail!("UNI-SLICE-05: byte_slice mid-codepoint boundary expected '', got #{r['result'].inspect}")
end

# byte_slice bounds clamping: start < 0 → 0; end > len → len
if compiled_bs
  r = run_vm(byte_slice_app, { 's' => 'hello', 'start_idx' => -5, 'end_idx' => 100 })
  r['result'] == 'hello' ? pass("UNI-SLICE-06: byte_slice negative/over-end clamps to full string") \
                          : fail!("UNI-SLICE-06: byte_slice clamp expected 'hello', got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(byte_slice_app)) rescue nil
end

# rune_slice("café", 0, 3) = "caf"  (first 3 runes)
if compiled_rs
  r = run_vm(rune_slice_app, { 's' => 'café', 'start_idx' => 0, 'end_idx' => 3 })
  r['result'] == 'caf' ? pass("UNI-SLICE-07: rune_slice('café', 0, 3) = 'caf'") \
                        : fail!("UNI-SLICE-07: rune_slice('café', 0, 3) expected 'caf', got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(rune_slice_app)) rescue nil
end

# grapheme_slice("éx", 0, 2) = "éx" (both graphemes)
# grapheme_slice("éx", 0, 1) = "é"  (first grapheme only)
if compiled_gs
  r1 = run_vm(grapheme_slice_app, { 's' => e_combining, 'start_idx' => 0, 'end_idx' => 1 })
  # First grapheme = e + U+0301 (2 codepoints, 1 grapheme cluster)
  r1['result'] == "é" ? pass("UNI-SLICE-08: grapheme_slice('e\\u0301x', 0, 1) = 'e\\u0301' (1 grapheme cluster)") \
                            : fail!("UNI-SLICE-08: grapheme_slice first cluster expected 'e\\u0301', got #{r1['result'].inspect}")

  r2 = run_vm(grapheme_slice_app, { 's' => e_combining, 'start_idx' => 1, 'end_idx' => 2 })
  r2['result'] == 'x' ? pass("UNI-SLICE-09: grapheme_slice('e\\u0301x', 1, 2) = 'x' (second grapheme)") \
                      : fail!("UNI-SLICE-09: grapheme_slice second grapheme expected 'x', got #{r2['result'].inspect}")
  FileUtils.rm_rf(File.dirname(grapheme_slice_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-REPLACE — replace (first-match), replace_all, empty-pattern error
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-REPLACE: replace / replace_all / empty-pattern error (runtime) ===\n"

SRC_REPLACE = <<~IGNITER
  module Unicode.Replace
  pure contract ReplaceProof {
    input s : String
    input pattern : String
    input replacement : String
    compute result = replace(s, pattern, replacement)
    output result : Text
  }
IGNITER

SRC_REPLACE_ALL = <<~IGNITER
  module Unicode.Replace
  pure contract ReplaceAllProof {
    input s : String
    input pattern : String
    input replacement : String
    compute result = replace_all(s, pattern, replacement)
    output result : Text
  }
IGNITER

_, replace_app, tmp7     = compile_src(SRC_REPLACE,     "replace")
_, replace_all_app, tmp8 = compile_src(SRC_REPLACE_ALL, "replace_all")

compiled_rep  = File.exist?(replace_app)
compiled_repa = File.exist?(replace_all_app)

FileUtils.rm_rf(tmp7) unless compiled_rep
FileUtils.rm_rf(tmp8) unless compiled_repa

compiled_rep  ? pass("UNI-REPLACE-01: replace contract compiles") \
              : fail!("UNI-REPLACE-01: replace contract failed to compile")
compiled_repa ? pass("UNI-REPLACE-02: replace_all contract compiles") \
              : fail!("UNI-REPLACE-02: replace_all contract failed to compile")

# replace is first-match: "banana" → "bXnana" (only first 'a' replaced)
if compiled_rep
  r = run_vm(replace_app, { 's' => 'banana', 'pattern' => 'a', 'replacement' => 'X' })
  r['result'] == 'bXnana' ? pass("UNI-REPLACE-03: replace('banana', 'a', 'X') = 'bXnana' (first-match only)") \
                          : fail!("UNI-REPLACE-03: replace first-match expected 'bXnana', got #{r['result'].inspect}")
end

# replace_all: "banana" → "bXnXnX"
if compiled_repa
  r = run_vm(replace_all_app, { 's' => 'banana', 'pattern' => 'a', 'replacement' => 'X' })
  r['result'] == 'bXnXnX' ? pass("UNI-REPLACE-04: replace_all('banana', 'a', 'X') = 'bXnXnX' (all occurrences)") \
                           : fail!("UNI-REPLACE-04: replace_all expected 'bXnXnX', got #{r['result'].inspect}")
end

# replace with empty pattern → runtime operational error
if compiled_rep
  r = run_vm(replace_app, { 's' => 'hello', 'pattern' => '', 'replacement' => 'X' })
  error_ok = r['status'] == 'error' && r.fetch('error', '').include?('empty pattern')
  error_ok ? pass("UNI-REPLACE-05: replace('hello', '', 'X') → runtime operational error (empty pattern)") \
           : fail!("UNI-REPLACE-05: replace empty-pattern expected error, got status=#{r['status']} error=#{r['error'].inspect}")
  FileUtils.rm_rf(File.dirname(replace_app)) rescue nil
end

# replace_all with empty pattern → runtime operational error
if compiled_repa
  r = run_vm(replace_all_app, { 's' => 'hello', 'pattern' => '', 'replacement' => 'X' })
  error_ok = r['status'] == 'error' && r.fetch('error', '').include?('empty pattern')
  error_ok ? pass("UNI-REPLACE-06: replace_all('hello', '', 'X') → runtime operational error (empty pattern)") \
           : fail!("UNI-REPLACE-06: replace_all empty-pattern expected error, got status=#{r['status']} error=#{r['error'].inspect}")
  FileUtils.rm_rf(File.dirname(replace_all_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-SPLIT — empty delimiter is runtime operational error
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-SPLIT: empty delimiter runtime error ===\n"

SRC_SPLIT_RT = <<~IGNITER
  module Unicode.Split
  pure contract SplitRtProof {
    input s : String
    input sep : String
    compute parts : Collection[Text] = split(s, sep)
    output parts : Collection[Text]
  }
IGNITER

result_split, split_rt_app, tmp9 = compile_src(SRC_SPLIT_RT, "split_rt")
compiled_split_rt = File.exist?(split_rt_app)
FileUtils.rm_rf(tmp9) unless compiled_split_rt

compiled_split_rt ? pass("UNI-SPLIT-01: split runtime contract compiles (variable delimiter)") \
                  : fail!("UNI-SPLIT-01: split runtime contract failed to compile")

# Normal split works
if compiled_split_rt
  r = run_vm(split_rt_app, { 's' => 'a,b,c', 'sep' => ',' })
  r_ok = r['status'] == 'success' && r['result'] == ['a', 'b', 'c']
  r_ok ? pass("UNI-SPLIT-02: split('a,b,c', ',') = ['a','b','c'] (normal case)") \
       : fail!("UNI-SPLIT-02: split normal case expected ['a','b','c'], got #{r['result'].inspect}")
end

# Empty delimiter → runtime operational error (v0 policy: no fallback to Rust default)
if compiled_split_rt
  r = run_vm(split_rt_app, { 's' => 'hello', 'sep' => '' })
  error_ok = r['status'] == 'error' && r.fetch('error', '').include?('empty delimiter')
  error_ok ? pass("UNI-SPLIT-03: split('hello', '') → runtime operational error (empty delimiter, v0 policy)") \
           : fail!("UNI-SPLIT-03: split empty-delimiter expected error, got status=#{r['status']} error=#{r['error'].inspect}")
  FileUtils.rm_rf(File.dirname(split_rt_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-CLOSED — ends_with + no normalization claim
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-CLOSED: ends_with runtime + no implicit normalization ===\n"

SRC_ENDS_WITH = <<~IGNITER
  module Unicode.Closed
  pure contract EndsWithProof {
    input s : String
    compute result = ends_with(s, "world")
    output result : Bool
  }
IGNITER

_, ew_app, tmp10 = compile_src(SRC_ENDS_WITH, "ends_with")
compiled_ew = File.exist?(ew_app)
FileUtils.rm_rf(tmp10) unless compiled_ew

compiled_ew ? pass("UNI-CLOSED-01: ends_with contract compiles") \
            : fail!("UNI-CLOSED-01: ends_with contract failed to compile")

if compiled_ew
  r_yes = run_vm(ew_app, { 's' => 'hello world' })
  r_yes['result'] == true ? pass("UNI-CLOSED-02: ends_with('hello world', 'world') = true") \
                          : fail!("UNI-CLOSED-02: ends_with positive expected true, got #{r_yes['result'].inspect}")

  r_no = run_vm(ew_app, { 's' => 'hello' })
  r_no['result'] == false ? pass("UNI-CLOSED-03: ends_with('hello', 'world') = false") \
                          : fail!("UNI-CLOSED-03: ends_with negative expected false, got #{r_no['result'].inspect}")
  FileUtils.rm_rf(File.dirname(ew_app)) rescue nil
end

# No normalization: NFC 'é' (U+00E9) ≠ NFD 'é' (U+0065 + U+0301)
# byte_length proves they are distinct byte sequences (NFC=2 bytes, NFD=3 bytes)
SRC_BYTE_LEN2 = <<~IGNITER
  module Unicode.Closed
  pure contract ByteLenProof2 {
    input s : String
    compute result = byte_length(s)
    output result : Integer
  }
IGNITER

_, bl2_app, tmp11 = compile_src(SRC_BYTE_LEN2, "byte_len2")
compiled_bl2 = File.exist?(bl2_app)
FileUtils.rm_rf(tmp11) unless compiled_bl2

if compiled_bl2
  nfc_e = "é"     # U+00E9 NFC: 2 UTF-8 bytes
  nfd_e = "é"    # U+0065 + U+0301 NFD: 3 UTF-8 bytes
  r_nfc = run_vm(bl2_app, { 's' => nfc_e })
  r_nfd = run_vm(bl2_app, { 's' => nfd_e })
  no_norm = (r_nfc['result'] == 2 && r_nfd['result'] == 3)
  no_norm ? pass("UNI-CLOSED-04: no implicit normalization — NFC é=2 bytes, NFD e+combining=3 bytes (distinct)") \
          : fail!("UNI-CLOSED-04: normalization check failed — NFC=#{r_nfc['result']}, NFD=#{r_nfd['result']}")
  FileUtils.rm_rf(File.dirname(bl2_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# UNI-REG — regression: existing ops unaffected
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n=== UNI-REG: regression — existing text ops unaffected ===\n"

SRC_BYTE_LEN_REG = <<~IGNITER
  module Unicode.Reg
  pure contract ByteLenReg {
    input s : String
    compute result = byte_length(s)
    output result : Integer
  }
IGNITER

SRC_STARTS_WITH_REG = <<~IGNITER
  module Unicode.Reg
  pure contract StartsWithReg {
    input s : String
    compute result = starts_with(s, "/api/")
    output result : Bool
  }
IGNITER

SRC_TRIM_REG = <<~IGNITER
  module Unicode.Reg
  pure contract TrimReg {
    input s : String
    compute result = trim(s)
    output result : Text
  }
IGNITER

_, bl_reg_app, tmp12 = compile_src(SRC_BYTE_LEN_REG,    "byte_len_reg")
_, sw_reg_app, tmp13 = compile_src(SRC_STARTS_WITH_REG, "starts_with_reg")
_, tr_reg_app, tmp14 = compile_src(SRC_TRIM_REG,        "trim_reg")

compiled_bl_reg = File.exist?(bl_reg_app)
compiled_sw_reg = File.exist?(sw_reg_app)
compiled_tr_reg = File.exist?(tr_reg_app)

FileUtils.rm_rf(tmp12) unless compiled_bl_reg
FileUtils.rm_rf(tmp13) unless compiled_sw_reg
FileUtils.rm_rf(tmp14) unless compiled_tr_reg

if compiled_bl_reg
  r = run_vm(bl_reg_app, { 's' => 'hello' })
  r['result'] == 5 ? pass("UNI-REG-01: byte_length('hello') = 5 (existing op unaffected)") \
                   : fail!("UNI-REG-01: byte_length regression expected 5, got #{r['result']}")
  FileUtils.rm_rf(File.dirname(bl_reg_app)) rescue nil
end

if compiled_sw_reg
  r = run_vm(sw_reg_app, { 's' => '/api/users' })
  r['result'] == true ? pass("UNI-REG-02: starts_with('/api/users', '/api/') = true (existing op unaffected)") \
                      : fail!("UNI-REG-02: starts_with regression expected true, got #{r['result']}")
  FileUtils.rm_rf(File.dirname(sw_reg_app)) rescue nil
end

if compiled_tr_reg
  r = run_vm(tr_reg_app, { 's' => '  hello  ' })
  r['result'] == 'hello' ? pass("UNI-REG-03: trim('  hello  ') = 'hello' (existing op unaffected)") \
                         : fail!("UNI-REG-03: trim regression expected 'hello', got #{r['result'].inspect}")
  FileUtils.rm_rf(File.dirname(tr_reg_app)) rescue nil
end

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
puts "\n" + "═" * 72
total = $pass_count + $fail_count
puts "LAB-STR-UNICODE-P2: #{$pass_count}/#{total} PASS"
if $fail_count > 0
  puts "\nFailed checks:"
end

exit($fail_count > 0 ? 1 : 0)
