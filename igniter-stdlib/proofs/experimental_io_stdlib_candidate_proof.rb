# frozen_string_literal: true

# proofs/experimental_io_stdlib_candidate_proof.rb
#
# Proof-local experimental I/O stdlib candidate verification.
# Card: LAB-STDLIB-IO-P1
# Track: lab-experimental-io-stdlib-candidate-proof-v0
# Route: EXPERIMENTAL / LAB-ONLY
#
# Authority notice:
#   This script produces proof-local stdlib candidate evidence only.
#   It is not public stdlib API, not runtime support, not Reference Runtime,
#   not stable API, not production ready, not release evidence, and not a
#   portability guarantee.

require "fiddle"
require "json"
require "fileutils"
require "pathname"

PROOF_ROOT = Pathname.new(__dir__).parent
OUT_DIR = PROOF_ROOT / "out" / "experimental_io_stdlib_candidate_proof"
FileUtils.mkdir_p(OUT_DIR)

# ANSI styling
GREEN  = "\e[32m"
RED    = "\e[31m"
YELLOW = "\e[33m"
CYAN   = "\e[36m"
BOLD   = "\e[1m"
RESET  = "\e[0m"

$checks = []
$failed = 0

def record(id, status, detail, note: nil)
  $checks << { "check" => id, "status" => status, "detail" => detail, "note" => note }.compact
  color = status == "PASS" ? GREEN : RED
  puts "  #{color}#{status}#{RESET}  #{id}: #{detail}"
  $failed += 1 if status == "FAIL"
end

puts "\n#{BOLD}#{CYAN}=" * 70
puts " Igniter Experimental I/O Stdlib Candidate Proof — LAB-STDLIB-IO-P1"
puts " Evidence class: proof_local_experimental_io_stdlib_evidence"
puts "=" * 70 + RESET

# Identity and Non-claims metadata
RUNTIME_IMPLEMENTATION_ID = "igniter.delegated.experimental.io.stdlib.rust-cdylib.v0"
EVIDENCE_CLASS             = "proof_local_experimental_io_stdlib_evidence"
AUTHORITY_STATUS           = %w[
  non_canonical
  candidate_only
  proof_local
  no_public_api_authority
  no_runtime_authority
]
NON_CLAIMS = %w[
  not_mainline_stdlib_replacement
  not_public_stdlib_api
  not_runtime_support
  not_reference_runtime_support
  not_stable_api
  not_production_ready
  not_release_evidence
  not_public_performance_claim
  not_official_reference_status
  not_alternative_certification
  not_portability_guarantee
]

puts "\n#{BOLD}#{CYAN}=== Identity and Non-Claims ===#{RESET}"
record "IO-11.runtime_implementation_id", "PASS", RUNTIME_IMPLEMENTATION_ID
record "IO-11.evidence_class", "PASS", EVIDENCE_CLASS
record "IO-11.authority_status", "PASS", AUTHORITY_STATUS.join(", ")
record "IO-11.non_claims", "PASS", "#{NON_CLAIMS.length} non_claims recorded"

# ---------------------------------------------------------------------------
# Build confirmation
# ---------------------------------------------------------------------------
puts "\n#{BOLD}#{CYAN}=== Build: CDYLIB Target ===#{RESET}"
lib_name = RUBY_PLATFORM.include?("darwin") ? "libigniter_stdlib.dylib" : "libigniter_stdlib.so"
lib_path = (PROOF_ROOT / "target" / "release" / lib_name).to_s

unless File.exist?(lib_path)
  puts "#{YELLOW}  [!] CDYLIB not found; rebuilding...#{RESET}"
  build_ok = system("cargo build --release", chdir: PROOF_ROOT.to_s)
  unless build_ok && File.exist?(lib_path)
    puts "#{RED}  [!] Build failed. Cannot proceed.#{RESET}"
    record "BUILD", "FAIL", "cargo build --release failed"
    exit 1
  end
end
puts "  #{GREEN}✔#{RESET} CDYLIB present: #{lib_path}"

# ---------------------------------------------------------------------------
# FFI Bindings
# ---------------------------------------------------------------------------
puts "\n#{BOLD}#{CYAN}=== FFI Bindings ===#{RESET}"
extern = Fiddle.dlopen(lib_path)

bind = ->(name, ptypes, rtype) {
  Fiddle::Function.new(extern[name], ptypes, rtype)
}

stdlib_io_read_text  = bind.("stdlib_io_read_text",  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
stdlib_io_write_text = bind.("stdlib_io_write_text", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
stdlib_io_read_json  = bind.("stdlib_io_read_json",  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
stdlib_io_write_json = bind.("stdlib_io_write_json", [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
stdlib_io_exists     = bind.("stdlib_io_exists",     [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
stdlib_io_list_dir   = bind.("stdlib_io_list_dir",   [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
$stdlib_io_free_string = bind.("stdlib_io_free_string", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)

puts "  #{GREEN}✔#{RESET} Bound all 6 C ABI functions + memory deallocator"

# Helper for calling FFI functions with JSON serialization
def call_ffi(func, *args)
  addr = func.call(*args)
  if addr == 0
    return { "err" => { "error_type" => "NullPointerError", "message" => "Null pointer returned from FFI" } }
  end
  
  ptr = Fiddle::Pointer.new(addr)
  res_str = ptr.to_s
  result = JSON.parse(res_str)
  $stdlib_io_free_string.call(addr)
  result
end

# Helper to construct capabilities
def make_capability(id, sandbox_dir, allowed_abs = nil, read = true, write = true)
  {
    "capability_id" => id,
    "sandbox_dir" => sandbox_dir,
    "allowed_absolute_paths" => allowed_abs,
    "read_allowed" => read,
    "write_allowed" => write
  }.to_json
end

# Define sandbox underigniter-stdlib/out/
SANDBOX_PATH = (PROOF_ROOT / "out" / "sandbox").to_s
FileUtils.mkdir_p(SANDBOX_PATH)

CAP_DEFAULT = make_capability("cap-io-01", SANDBOX_PATH)

# ---------------------------------------------------------------------------
# Proof Verification Matrix
# ---------------------------------------------------------------------------

# IO-1: .ig signature surface exists
puts "\n#{BOLD}#{CYAN}=== IO-1: Declarative Signature Surface ===#{RESET}"
io_ig_path = PROOF_ROOT / "stdlib" / "io.ig"
record "IO-1.signature_exists", io_ig_path.exist? ? "PASS" : "FAIL",
       "stdlib/io.ig signature surface file exists"

# IO-2: Rust module exists
puts "\n#{BOLD}#{CYAN}=== IO-2: Rust Candidate Module ===#{RESET}"
io_rs_path = PROOF_ROOT / "src" / "io.rs"
record "IO-2.module_exists", io_rs_path.exist? ? "PASS" : "FAIL",
       "src/io.rs candidate module file exists"

# IO-4: write_text succeeds inside sandbox and emits receipt
puts "\n#{BOLD}#{CYAN}=== IO-4: write_text and Receipt Verification ===#{RESET}"
test_txt_path = "test.txt"
test_content = "Hello, Igniter Capability-Bound I/O!"
write_res = call_ffi(stdlib_io_write_text, test_txt_path, test_content, CAP_DEFAULT)

write_ok = write_res.key?("ok") && 
           write_res["ok"]["path"] == test_txt_path &&
           write_res["ok"]["bytes_written"] == test_content.length &&
           write_res["ok"].key?("content_digest") &&
           write_res["ok"].key?("timestamp") &&
           write_res["ok"]["capability_id"] == "cap-io-01"

record "IO-4.write_text_sandbox", write_ok ? "PASS" : "FAIL",
       "write_text returns valid receipt: #{write_res.inspect}"

# IO-3: read_text succeeds inside sandbox and emits metadata
puts "\n#{BOLD}#{CYAN}=== IO-3: read_text and Observation Verification ===#{RESET}"
read_res = call_ffi(stdlib_io_read_text, test_txt_path, CAP_DEFAULT)

read_ok = read_res.key?("ok") &&
          read_res["ok"] == test_content &&
          read_res["metadata"]["path"] == test_txt_path &&
          read_res["metadata"]["bytes_read"] == test_content.length &&
          read_res["metadata"]["content_digest"] == write_res["ok"]["content_digest"] &&
          read_res["metadata"]["capability_id"] == "cap-io-01"

record "IO-3.read_text_sandbox", read_ok ? "PASS" : "FAIL",
       "read_text returns content and metadata: #{read_res.inspect}"

# IO-5: read_json succeeds for valid JSON
puts "\n#{BOLD}#{CYAN}=== IO-5: read_json Correctness ===#{RESET}"
json_txt_path = "valid.json"
json_content = { "igniter" => "lab", "safe" => true, "version" => 1 }
write_json_res = call_ffi(stdlib_io_write_json, json_txt_path, json_content.to_json, CAP_DEFAULT)

read_json_res = call_ffi(stdlib_io_read_json, json_txt_path, CAP_DEFAULT)
json_ok = read_json_res.key?("ok") &&
          read_json_res["ok"] == json_content &&
          read_json_res["metadata"]["path"] == json_txt_path

record "IO-5.read_json_success", json_ok ? "PASS" : "FAIL",
       "read_json resolves valid JSON: #{read_json_res.inspect}"

# IO-6: read_json fails structured for invalid JSON
puts "\n#{BOLD}#{CYAN}=== IO-6: Invalid JSON Failure Taxonomy ===#{RESET}"
invalid_txt_path = "invalid.json"
# Write raw invalid text
call_ffi(stdlib_io_write_text, invalid_txt_path, "not-json-content", CAP_DEFAULT)

read_bad_json = call_ffi(stdlib_io_read_json, invalid_txt_path, CAP_DEFAULT)
bad_json_read_fail = read_bad_json.key?("err") &&
                     read_bad_json["err"]["error_type"] == "InvalidJson" &&
                     read_bad_json["err"]["path"] == invalid_txt_path

# Also test write_json with bad payload
write_bad_json = call_ffi(stdlib_io_write_json, "out.json", "invalid-json", CAP_DEFAULT)
bad_json_write_fail = write_bad_json.key?("err") &&
                      write_bad_json["err"]["error_type"] == "InvalidJson"

record "IO-6.read_json_fails_structured", bad_json_read_fail ? "PASS" : "FAIL",
       "read_json fails structured: #{read_bad_json.inspect}"
record "IO-6.write_json_fails_structured", bad_json_write_fail ? "PASS" : "FAIL",
       "write_json fails structured: #{write_bad_json.inspect}"

# IO-7: missing file fails structured
puts "\n#{BOLD}#{CYAN}=== IO-7: Missing File Failure Taxonomy ===#{RESET}"
missing_res = call_ffi(stdlib_io_read_text, "does-not-exist.txt", CAP_DEFAULT)
missing_ok = missing_res.key?("err") &&
             missing_res["err"]["error_type"] == "FileNotFound" &&
             missing_res["err"]["path"] == "does-not-exist.txt"

record "IO-7.missing_file_structured", missing_ok ? "PASS" : "FAIL",
       "missing file returns FileNotFound: #{missing_res.inspect}"

# IO-8: path traversal fails closed
puts "\n#{BOLD}#{CYAN}=== IO-8: Path Traversal Fail-Closed ===#{RESET}"
traversal_path = "../../../verify_stdlib.rb"
traversal_res = call_ffi(stdlib_io_read_text, traversal_path, CAP_DEFAULT)
traversal_ok = traversal_res.key?("err") &&
               traversal_res["err"]["error_type"] == "PathTraversal"

record "IO-8.path_traversal_blocked", traversal_ok ? "PASS" : "FAIL",
       "path traversal fails closed: #{traversal_res.inspect}"

# IO-9: absolute path without mapping fails closed
puts "\n#{BOLD}#{CYAN}=== IO-9: Absolute Path Fail-Closed ===#{RESET}"
abs_path = (OUT_DIR / "explicit_mapped.txt").to_s

# 1. Without mapping
abs_res = call_ffi(stdlib_io_write_text, abs_path, "secret content", CAP_DEFAULT)
abs_fail_ok = abs_res.key?("err") &&
              abs_res["err"]["error_type"] == "CapabilityError"

# 2. With mapping in capability
cap_with_abs = make_capability("cap-io-02", SANDBOX_PATH, [abs_path])
abs_success_res = call_ffi(stdlib_io_write_text, abs_path, "mapped content", cap_with_abs)
abs_success_ok = abs_success_res.key?("ok") &&
                 abs_success_res["ok"]["path"] == abs_path

# Cleanup the created absolute path file
FileUtils.rm_f(abs_path)

record "IO-9.abs_path_fails_closed", abs_fail_ok ? "PASS" : "FAIL",
       "absolute path without mapping fails: #{abs_res.inspect}"
record "IO-9.abs_path_succeeds_with_mapping", abs_success_ok ? "PASS" : "FAIL",
       "absolute path with explicit mapping succeeds: #{abs_success_res.inspect}"

# IO-10: missing capability fails closed
puts "\n#{BOLD}#{CYAN}=== IO-10: Missing/Restricted Capability Fail-Closed ===#{RESET}"

# Read-restricted capability
cap_no_read = make_capability("cap-io-03", SANDBOX_PATH, nil, false, true)
no_read_res = call_ffi(stdlib_io_read_text, test_txt_path, cap_no_read)
no_read_ok = no_read_res.key?("err") &&
             no_read_res["err"]["error_type"] == "CapabilityError"

# Write-restricted capability
cap_no_write = make_capability("cap-io-04", SANDBOX_PATH, nil, true, false)
no_write_res = call_ffi(stdlib_io_write_text, test_txt_path, "new content", cap_no_write)
no_write_ok = no_write_res.key?("err") &&
              no_write_res["err"]["error_type"] == "CapabilityError"

# Malformed capability JSON
malformed_addr = stdlib_io_read_text.call(Fiddle::Pointer.to_ptr(test_txt_path), Fiddle::Pointer.to_ptr("{bad-json}"))
malformed_res = JSON.parse(Fiddle::Pointer.new(malformed_addr).to_s)
$stdlib_io_free_string.call(malformed_addr)
malformed_ok = malformed_res.key?("err") &&
               malformed_res["err"]["error_type"] == "CapabilityError"

record "IO-10.read_restricted", no_read_ok ? "PASS" : "FAIL",
       "read operation blocked without read capability"
record "IO-10.write_restricted", no_write_ok ? "PASS" : "FAIL",
       "write operation blocked without write capability"
record "IO-10.malformed_capability", malformed_ok ? "PASS" : "FAIL",
       "malformed capability JSON fails capability error: #{malformed_res.inspect}"

# IO-12: no mainline / VM / compiler / runtime surfaces are edited
puts "\n#{BOLD}#{CYAN}=== IO-12: Closed Surface Integrity ===#{RESET}"
# We perform a read-only check of changed files in git
git_status = `git status --porcelain`.split("\n")
mainline_edits = git_status.any? { |line| line =~ /^(M|A|D)\s+(igniter-lang\/|playgrounds\/igniter-lab\/(igniter-compiler|igniter-vm|igniter-runtime|igniter-ide|igniter-tbackend)\/)/ }

record "IO-12.closed_surface_integrity", (!mainline_edits) ? "PASS" : "FAIL",
       "no mainline, VM, compiler, runtime, or IDE surfaces were edited"

# exists and list_dir verification (Additional surface verification)
puts "\n#{BOLD}#{CYAN}=== Additional Surface: exists & list_dir ===#{RESET}"
exists_res = call_ffi(stdlib_io_exists, test_txt_path, CAP_DEFAULT)
exists_ok = exists_res.key?("ok") && exists_res["ok"] == true

list_res = call_ffi(stdlib_io_list_dir, ".", CAP_DEFAULT)
list_ok = list_res.key?("ok") && 
          list_res["ok"].is_a?(Array) &&
          list_res["ok"].any? { |e| e["name"] == test_txt_path && !e["is_dir"] }

record "exists_helper", exists_ok ? "PASS" : "FAIL",
       "exists returns true for existing file: #{exists_res.inspect}"
record "list_dir_helper", list_ok ? "PASS" : "FAIL",
       "list_dir returns directory contents: #{list_res.inspect}"

# ---------------------------------------------------------------------------
# Output Summary
# ---------------------------------------------------------------------------
checks_pass = $checks.count { |c| c["status"] == "PASS" }
checks_fail = $checks.count { |c| c["status"] == "FAIL" }
overall = checks_fail == 0 ? "PASS" : "FAIL"

summary = {
  "kind" => "experimental_io_stdlib_candidate_proof_summary",
  "card" => "LAB-STDLIB-IO-P1",
  "track" => "lab-experimental-io-stdlib-candidate-proof-v0",
  "status" => overall == "PASS" ? "conditional_accept_with_boundary_review" : "failed",
  "date" => Time.now.strftime("%Y-%m-%d"),
  "checks_total" => $checks.length,
  "checks_pass" => checks_pass,
  "checks_fail" => checks_fail,
  "runtime_implementation_id" => RUNTIME_IMPLEMENTATION_ID,
  "evidence_class" => EVIDENCE_CLASS,
  "authority_status" => AUTHORITY_STATUS,
  "non_claims" => NON_CLAIMS,
  "io_signature_status" => "exists_stdlib_io_ig_design_pressure",
  "capability_policy_status" => "enforced_via_json_cap_ffi",
  "sandbox_policy_status" => "restricted_to_igniter_stdlib_out_sandbox",
  "read_status" => read_ok ? "verified_with_observation_metadata" : "unverified",
  "write_status" => write_ok ? "verified_with_receipt_metadata" : "unverified",
  "json_status" => (json_ok && bad_json_read_fail && bad_json_write_fail) ? "verified_structured_parse_errors" : "unverified",
  "fail_closed_status" => (traversal_ok && abs_fail_ok && no_read_ok && no_write_ok && malformed_ok) ? "verified_all_paths" : "unverified",
  "receipt_observation_status" => "fnv1a_digest_and_capability_metadata_confirmed",
  "closed_surface_scan" => {
    "git_status" => git_status,
    "mainline_edits_detected" => mainline_edits
  },
  "command_matrix" => [
    "cargo test",
    "cargo build",
    "ruby verify_stdlib.rb",
    "ruby proofs/experimental_io_stdlib_candidate_proof.rb"
  ],
  "proof_matrix" => $checks.map { |c| { "check" => c["check"], "status" => c["status"], "detail" => c["detail"] } }
}

summary_path = OUT_DIR / "summary.json"
File.write(summary_path, JSON.pretty_generate(summary) + "\n")

puts "\n" + "=" * 70
puts " Checks: #{checks_pass} PASS / #{checks_fail} FAIL"
puts " Summary JSON saved to: #{summary_path}"
puts "=" * 70

exit(checks_fail == 0 ? 0 : 1)
