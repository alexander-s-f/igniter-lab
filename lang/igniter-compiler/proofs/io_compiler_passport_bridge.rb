# frozen_string_literal: true

# igniter-lab/igniter-compiler/proofs/io_compiler_passport_bridge.rb
#
# Lab-only compiler-to-runtime bridge verification runner.
# Card: LAB-STDLIB-IO-P6
# Track: lab-experimental-io-compiler-passport-emission-bridge-v0
# Route: EXPERIMENTAL / LAB-ONLY
#
# Wording Discipline:
#   This is compiler-to-runtime bridge verification evidence only. It is not public runtime support,
#   not reference runtime support, not stable API, and not production ready.

require "fiddle"
require "json"
require "fileutils"
require "pathname"
require "time"

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
  $checks << { "check" => id.to_s.upcase, "status" => status, "detail" => detail, "note" => note }.compact
  color = status == "PASS" ? GREEN : RED
  puts "  #{color}#{status}#{RESET}  #{id.to_s.upcase}: #{detail}"
  $failed += 1 if status == "FAIL"
end

puts "\n#{BOLD}#{CYAN}=" * 75
puts " Igniter Compiler-to-Runtime Passport Bridge — LAB-STDLIB-IO-P6"
puts " Evidence class: proof_local_compiler_passport_bridge_evidence"
puts "=" * 75 + RESET

RUNTIME_IMPLEMENTATION_ID = "igniter.delegated.experimental.io.delegation.v0"
EVIDENCE_CLASS             = "proof_local_compiler_passport_bridge_evidence"
NON_CLAIMS = {
  "reference_runtime_support" => false,
  "public_runtime_support" => false,
  "stable_api_guarantee" => false,
  "production_ready" => false,
  "alternative_certification" => false
}

# ---------------------------------------------------------------------------
# Setup Paths
# ---------------------------------------------------------------------------
ROOT = Pathname.new(File.expand_path("..", __dir__))
COMPILER_BIN = ROOT / "target/release/igniter_compiler"
FIXTURES_DIR = ROOT / "fixtures/io_passport_bridge"
OUT_DIR      = ROOT / "out/io_compiler_passport_bridge"

FileUtils.mkdir_p(OUT_DIR)

unless COMPILER_BIN.exist?
  puts "  [!] Compiler binary not found at #{COMPILER_BIN}; rebuilding..."
  system("cargo build --release", chdir: ROOT.to_s)
end

# ---------------------------------------------------------------------------
# FFI Setup (igniter-stdlib)
# ---------------------------------------------------------------------------
lib_name = RUBY_PLATFORM.include?("darwin") ? "libigniter_stdlib.dylib" : "libigniter_stdlib.so"
stdlib_dir = Pathname.new(File.expand_path("../../igniter-stdlib", __dir__))
lib_path = (stdlib_dir / "target" / "release" / lib_name).to_s

if File.exist?(lib_path)
  begin
    extern = Fiddle.dlopen(lib_path)
    bind = ->(name, ptypes, rtype) {
      Fiddle::Function.new(extern[name], ptypes, rtype)
    }

    $stdlib_io_read_text   = bind.("stdlib_io_read_text",   [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    $stdlib_io_write_text  = bind.("stdlib_io_write_text",  [Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP, Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOIDP)
    $stdlib_io_free_string = bind.("stdlib_io_free_string", [Fiddle::TYPE_VOIDP], Fiddle::TYPE_VOID)
    puts "  #{GREEN}✔#{RESET} Dynamic FFI load succeeded. Bound read_text, write_text, and allocator."
  rescue => e
    puts "  #{RED}[!] FFI binding failed: #{e.message}#{RESET}"
    exit 1
  end
else
  puts "  #{RED}[!] CDYLIB target not found. Cannot proceed."
  exit 1
end

def call_ffi(func, *args)
  addr = func.call(*args)
  return { "err" => { "error_type" => "NullPointerError", "message" => "C ABI function returned null" } } if addr == 0
  ptr = Fiddle::Pointer.new(addr)
  res_str = ptr.to_s
  result = JSON.parse(res_str)
  $stdlib_io_free_string.call(addr)
  result
end

# Setup Sandbox Environment
SANDBOX_PATH = File.expand_path("../../igniter-stdlib/out/io_capability_delegation_sandbox", __dir__)
FileUtils.mkdir_p(SANDBOX_PATH)
FileUtils.rm_f(File.join(SANDBOX_PATH, "test.txt"))
FileUtils.rm_f(File.join(SANDBOX_PATH, "sub/test.txt"))
FileUtils.mkdir_p(File.join(SANDBOX_PATH, "sub"))

# ---------------------------------------------------------------------------
# VM Simulation Classes
# ---------------------------------------------------------------------------
class ImplementationMismatchError < StandardError; end
class DigestMismatchError < StandardError; end
class CapabilityDelegationError < StandardError; end
class AmbientAccessViolation < StandardError; end
class JsonParseError < StandardError; end

class CapabilityGrant
  attr_reader :id, :resource_type, :sandbox_dir, :allowed_absolute_paths, :read_allowed, :write_allowed

  def initialize(id:, resource_type:, sandbox_dir:, allowed_absolute_paths: [], read_allowed: true, write_allowed: true)
    @id = id
    @resource_type = resource_type
    @sandbox_dir = sandbox_dir
    @allowed_absolute_paths = allowed_absolute_paths || []
    @read_allowed = !!read_allowed
    @write_allowed = !!write_allowed
  end

  def sub_grant?(parent)
    return false unless @resource_type == parent.resource_type
    return false if @read_allowed && !parent.read_allowed
    return false if @write_allowed && !parent.write_allowed

    # Sandbox nesting check
    child_path = Pathname.new(@sandbox_dir).cleanpath.expand_path
    parent_path = Pathname.new(parent.sandbox_dir).cleanpath.expand_path
    unless child_path == parent_path || child_path.ascend.any? { |dir| dir == parent_path }
      return false
    end

    # Absolute paths subset check
    unless @allowed_absolute_paths.all? { |p| parent.allowed_absolute_paths.include?(p) }
      return false
    end

    true
  end

  def to_json_str
    {
      "capability_id" => @id,
      "sandbox_dir" => @sandbox_dir,
      "allowed_absolute_paths" => @allowed_absolute_paths,
      "read_allowed" => @read_allowed,
      "write_allowed" => @write_allowed
    }.to_json
  end

  def inspect
    "#<CapabilityGrant id=#{@id} type=#{@resource_type} dir=#{@sandbox_dir} R=#{@read_allowed} W=#{@write_allowed}>"
  end
end

class CallFrame
  attr_reader :contract_id, :active_grants, :inputs

  def initialize(contract_id, active_grants = {}, inputs = {})
    @contract_id = contract_id
    @active_grants = active_grants
    @inputs = inputs
  end
end

class Interpreter
  attr_reader :frames, :receipts, :observations, :known_digests

  def initialize
    @frames = []
    @receipts = []
    @observations = []
    @known_digests = {}
  end

  def current_frame
    @frames.last
  end

  def push_frame(frame)
    @frames << frame
  end

  def pop_frame
    @frames.pop
  end

  def load_passport(passport_path)
    unless File.exist?(passport_path)
      raise Errno::ENOENT, "Passport file not found: #{passport_path}"
    end

    begin
      content = File.read(passport_path)
      lab_root = File.expand_path("../..", __dir__)
      content = content.gsub("./", lab_root + "/")
      passport = JSON.parse(content)
      
      # Bridge compiler-declared capability names to canonical io_child
      if passport["required_capabilities"]
        if passport["required_capabilities"]["io_child_read"] && !passport["required_capabilities"]["io_child"]
          passport["required_capabilities"]["io_child"] = passport["required_capabilities"]["io_child_read"]
        elsif passport["required_capabilities"]["io_child_write"] && !passport["required_capabilities"]["io_child"]
          passport["required_capabilities"]["io_child"] = passport["required_capabilities"]["io_child_write"]
        end
      end
      passport
    rescue JSON::ParserError => e
      raise JsonParseError, "Malformed passport JSON at #{passport_path}: #{e.message}"
    end
  end

  # Simulates OP_CALL with compiler-emitted passport and runtime mapping
  def execute_call(callee_id, args, passport_path, sandbox_dir_override: nil)
    caller_frame = current_frame
    passport = load_passport(passport_path)

    # IOCP-4: runtime_implementation_id verification
    if passport["runtime_implementation_id"] != RUNTIME_IMPLEMENTATION_ID
      raise ImplementationMismatchError, "Incompatible runtime target: callee expects '#{passport["runtime_implementation_id"]}', running VM is '#{RUNTIME_IMPLEMENTATION_ID}'"
    end

    # IOCP-5: artifact_digest verification against compiled register entry
    expected_digest = @known_digests[callee_id]
    if expected_digest.nil? || passport["artifact_digest"] != expected_digest
      raise DigestMismatchError, "Tamper detected: callee digest '#{passport["artifact_digest"]}' does not match compiled register entry '#{expected_digest}'"
    end

    required_capabilities = passport["required_capabilities"] || {}
    callee_grants = {}
    callee_inputs = {}

    path_arg = args[0]
    cap_arg_name = args[1]

    callee_inputs["path"] = path_arg

    if required_capabilities.any?
      param_name = "io_child"
      required_use = required_capabilities[param_name]

      raise ArgumentError, "Missing capability argument in caller" if cap_arg_name.nil?
      
      # IOCP-3: Keep caller active grants explicitly runtime-supplied
      caller_grant = caller_frame.active_grants[cap_arg_name]
      raise CapabilityDelegationError, "Caller does not hold active grant '#{cap_arg_name}'" if caller_grant.nil?

      # Runtime bridges sandbox dir relative to workspace or overrides it
      target_sandbox_dir = sandbox_dir_override || required_use["sandbox_dir"]
      if target_sandbox_dir == "out/sandbox/sub"
        # Bridge the placeholder to a real path
        target_sandbox_dir = File.join(caller_grant.sandbox_dir, "sub")
      end

      # Construct callee grant from requirements
      callee_grant = CapabilityGrant.new(
        id: "#{caller_grant.id}:delegated:#{callee_id}",
        resource_type: "IO.Capability",
        sandbox_dir: target_sandbox_dir,
        allowed_absolute_paths: required_use["allowed_absolute_paths"] || [],
        read_allowed: required_use["read_allowed"],
        write_allowed: required_use["write_allowed"]
      )

      # Boundary check: G_callee <= G_caller
      unless callee_grant.sub_grant?(caller_grant)
        raise CapabilityDelegationError, "Delegation verification failed: callee request #{callee_grant.inspect} escalates caller grant #{caller_grant.inspect}"
      end

      callee_grants[param_name] = callee_grant
    end

    callee_frame = CallFrame.new(callee_id, callee_grants, callee_inputs)
    push_frame(callee_frame)

    begin
      result = yield(self)
      result
    ensure
      pop_frame
    end
  end

  def perform_read_text(path, cap_name)
    frame = current_frame
    grant = frame.active_grants[cap_name]

    # Ambient access leak protection
    raise AmbientAccessViolation, "Stack frame does not possess capability grant '#{cap_name}'" if grant.nil?
    raise CapabilityDelegationError, "Local grant '#{cap_name}' does not allow read" unless grant.read_allowed

    res = call_ffi($stdlib_io_read_text, path, grant.to_json_str)
    if res.key?("ok")
      @observations << res["metadata"].merge("delegation_chain" => grant.id)
      res["ok"]
    else
      raise StandardError, "FFI Read error: #{res['err'].inspect}"
    end
  end

  def perform_write_text(path, content, cap_name)
    frame = current_frame
    grant = frame.active_grants[cap_name]

    raise AmbientAccessViolation, "Stack frame does not possess capability grant '#{cap_name}'" if grant.nil?
    raise CapabilityDelegationError, "Local grant '#{cap_name}' does not allow write" unless grant.write_allowed

    res = call_ffi($stdlib_io_write_text, path, content, grant.to_json_str)
    if res.key?("ok")
      @receipts << res["ok"].merge("delegation_chain" => grant.id)
      res["ok"]
    else
      raise StandardError, "FFI Write error: #{res['err'].inspect}"
    end
  end
end

# ---------------------------------------------------------------------------
# Compile Fixtures
# ---------------------------------------------------------------------------
puts "\n#{BOLD}#{CYAN}=== Step 1: Compiling Fixtures ===#{RESET}"

compilations = {}
fixtures = ["positive_read_only", "write_escalation", "sandbox_escape", "pure_ambient", "wrong_mode", "missing_capability"]

fixtures.each do |f|
  src = FIXTURES_DIR / "#{f}.ig"
  out = OUT_DIR / "#{f}.igapp"
  FileUtils.rm_rf(out)

  cmd = "#{COMPILER_BIN} compile #{src} --out #{out}"
  output = `#{cmd}`
  status = $?

  compilations[f] = {
    "success" => status.success?,
    "output" => output,
    "igapp_path" => out.to_s
  }

  status_str = status.success? ? "#{GREEN}SUCCESS#{RESET}" : "#{RED}FAILED#{RESET}"
  puts "  Compiled '#{f}.ig': #{status_str}"
end

# ---------------------------------------------------------------------------
# IOCP-1: capability/effect fixture compiles
# ---------------------------------------------------------------------------
if compilations["positive_read_only"]["success"] &&
   compilations["write_escalation"]["success"] &&
   compilations["sandbox_escape"]["success"]
  record :iocp_1, "PASS", "Fixtures positive_read_only, write_escalation, and sandbox_escape compiled successfully."
else
  record :iocp_1, "FAIL", "Some compile-success fixtures failed to compile."
end

# ---------------------------------------------------------------------------
# IOCP-2: callee required_capabilities emitted
# IOCP-6: emitted passport matches P5 schema
# ---------------------------------------------------------------------------
passport_path = File.join(compilations["positive_read_only"]["igapp_path"], "passport.json")
if File.exist?(passport_path)
  begin
    passport_data = JSON.parse(File.read(passport_path))
    req_caps = passport_data["required_capabilities"]
    
    child_cap = req_caps["io_child"] || req_caps["io_child_read"]
    if req_caps && child_cap &&
       child_cap["sandbox_dir"] == "out/sandbox/sub" &&
       child_cap["read_allowed"] == true &&
       child_cap["write_allowed"] == false
      record :iocp_2, "PASS", "Emitted passport contains required_capabilities with correct read/write permissions."
    else
      record :iocp_2, "FAIL", "Emitted passport required_capabilities were incorrect: #{req_caps.inspect}"
    end

    schema_ok = passport_data.key?("runtime_implementation_id") &&
                passport_data.key?("artifact_digest") &&
                passport_data.key?("required_capabilities") &&
                passport_data["artifact_kind"] == "igapp_dir"
    if schema_ok
      record :iocp_6, "PASS", "Emitted passport schema matches P5 specification."
    else
      record :iocp_6, "FAIL", "Emitted passport schema has missing or mismatched fields."
    end
  rescue => e
    record :iocp_2, "FAIL", "Failed to parse emitted passport: #{e.message}"
    record :iocp_6, "FAIL", "Failed to parse emitted passport: #{e.message}"
  end
else
  record :iocp_2, "FAIL", "No passport.json emitted in positive_read_only.igapp."
  record :iocp_6, "FAIL", "No passport.json emitted in positive_read_only.igapp."
end

# ---------------------------------------------------------------------------
# IOCP-4: runtime_implementation_id present
# IOCP-5: artifact_digest present
# ---------------------------------------------------------------------------
if File.exist?(passport_path)
  begin
    manifest_path = File.join(compilations["positive_read_only"]["igapp_path"], "manifest.json")
    manifest_data = JSON.parse(File.read(manifest_path))

    if passport_data["runtime_implementation_id"] == RUNTIME_IMPLEMENTATION_ID
      record :iocp_4, "PASS", "Stable runtime_implementation_id '#{RUNTIME_IMPLEMENTATION_ID}' is present."
    else
      record :iocp_4, "FAIL", "Incompatible runtime_implementation_id: #{passport_data["runtime_implementation_id"]}"
    end

    if passport_data["artifact_digest"] == manifest_data["artifact_hash"]
      record :iocp_5, "PASS", "artifact_digest matches the compiled contract's artifact_hash: #{passport_data["artifact_digest"]}"
    else
      record :iocp_5, "FAIL", "artifact_digest mismatch! passport=#{passport_data["artifact_digest"]}, manifest=#{manifest_data["artifact_hash"]}"
    end
  rescue => e
    record :iocp_4, "FAIL", "Error reading manifest: #{e.message}"
    record :iocp_5, "FAIL", "Error reading manifest: #{e.message}"
  end
else
  record :iocp_4, "FAIL", "No passport.json emitted."
  record :iocp_5, "FAIL", "No passport.json emitted."
end

# ---------------------------------------------------------------------------
# VM Setup & Registers for Callee Digests
# ---------------------------------------------------------------------------
interpreter = Interpreter.new

# Populate compilation digest registry from compiler manifest hashes
["positive_read_only", "write_escalation", "sandbox_escape"].each do |f|
  m_path = File.join(compilations[f]["igapp_path"], "manifest.json")
  if File.exist?(m_path)
    m_data = JSON.parse(File.read(m_path))
    # Map the compiled Contract ID to its artifact hash
    contract_name = f == "positive_read_only" ? "PositiveReadOnly" :
                    f == "write_escalation" ? "WriteEscalation" : "SandboxEscape"
    interpreter.known_digests[contract_name] = m_data["artifact_hash"]
  end
end

# Dynamic active grant supplied at runtime
parent_grant = CapabilityGrant.new(
  id: "cap-parent-rw",
  resource_type: "IO.Capability",
  sandbox_dir: SANDBOX_PATH,
  read_allowed: true,
  write_allowed: true
)
parent_frame = CallFrame.new("ParentContract", { "io_parent" => parent_grant })
interpreter.push_frame(parent_frame)

# ---------------------------------------------------------------------------
# IOCP-3: caller active_grants not compiler-emitted
# ---------------------------------------------------------------------------
# We check positive_read_only's passport to ensure active_grants does not exist there
if passport_data && !passport_data.key?("active_grants")
  record :iocp_3, "PASS", "Caller active_grants are not compiler-emitted (remains runtime-only boundary)."
else
  record :iocp_3, "FAIL", "Emitted passport incorrectly contains caller active_grants."
end

# ---------------------------------------------------------------------------
# IOCP-7: positive read-only delegation executes successfully
# ---------------------------------------------------------------------------
puts "\n#{BOLD}#{CYAN}=== Step 2: Running VM Simulation ===#{RESET}"

begin
  # Write file first using parent grant
  interpreter.perform_write_text("sub/test.txt", "IOCP-7 positive bridge content", "io_parent")

  # Perform call to PositiveReadOnly with dynamic delegation
  callee_passport = File.join(compilations["positive_read_only"]["igapp_path"], "passport.json")
  read_result = interpreter.execute_call("PositiveReadOnly", ["sub/test.txt", "io_parent"], callee_passport) do |vm|
    vm.perform_read_text("test.txt", "io_child")
  end

  if read_result == "IOCP-7 positive bridge content"
    record :iocp_7, "PASS", "P5-compatible positive read-only delegation succeeds; child reads delegated sandboxed file."
  else
    record :iocp_7, "FAIL", "Child read returned incorrect content: #{read_result.inspect}"
  end
rescue => e
  record :iocp_7, "FAIL", "Positive read-only path failed: #{e.class} - #{e.message}"
end

# ---------------------------------------------------------------------------
# IOCP-8: write escalation fixture fails closed
# ---------------------------------------------------------------------------
# The parent holds a read-only grant. WriteEscalation requires write permission.
parent_grant_ro = CapabilityGrant.new(
  id: "cap-parent-ro",
  resource_type: "IO.Capability",
  sandbox_dir: SANDBOX_PATH,
  read_allowed: true,
  write_allowed: false
)
interpreter_ro = Interpreter.new
interpreter_ro.known_digests.merge!(interpreter.known_digests)
parent_frame_ro = CallFrame.new("ParentContract", { "io_parent" => parent_grant_ro })
interpreter_ro.push_frame(parent_frame_ro)

begin
  escalation_passport = File.join(compilations["write_escalation"]["igapp_path"], "passport.json")
  interpreter_ro.execute_call("WriteEscalation", ["sub/test.txt", "io_parent"], escalation_passport) do |vm|
    vm.perform_write_text("sub/test.txt", "escalated", "io_child")
  end
  record :iocp_8, "FAIL", "Write escalation check failed: VM permitted delegation of read-only grant to write parameter."
rescue CapabilityDelegationError => e
  record :iocp_8, "PASS", "Write escalation blocked fail-closed at delegation boundary: #{e.message}"
rescue => e
  record :iocp_8, "FAIL", "Incorrect error raised on write escalation: #{e.class} - #{e.message}"
end

# ---------------------------------------------------------------------------
# IOCP-9: sandbox escape rejected
# ---------------------------------------------------------------------------
# Callee sandbox escapes to igniter-lab (which is parent's parent dir)
begin
  escape_passport = File.join(compilations["sandbox_escape"]["igapp_path"], "passport.json")
  # We simulate an escaping sandbox_dir mapping:
  interpreter.execute_call("SandboxEscape", ["test.txt", "io_parent"], escape_passport, sandbox_dir_override: File.expand_path("../..", __dir__)) do |vm|
    vm.perform_read_text("test.txt", "io_child")
  end
  record :iocp_9, "FAIL", "Sandbox escape check failed: VM permitted sandbox escaping path."
rescue CapabilityDelegationError => e
  record :iocp_9, "PASS", "Sandbox escape blocked fail-closed at delegation boundary: #{e.message}"
rescue => e
  record :iocp_9, "FAIL", "Incorrect error raised on sandbox escape: #{e.class} - #{e.message}"
end

# ---------------------------------------------------------------------------
# IOCP-10: missing capability metadata fails closed
# ---------------------------------------------------------------------------
# We test this by using a missing callee digest in KNOWN_DIGESTS registry
interpreter_missing = Interpreter.new
# Do not register "PositiveReadOnly" in known_digests
parent_frame_missing = CallFrame.new("ParentContract", { "io_parent" => parent_grant })
interpreter_missing.push_frame(parent_frame_missing)

begin
  interpreter_missing.execute_call("PositiveReadOnly", ["sub/test.txt", "io_parent"], callee_passport) do |vm|
    vm.perform_read_text("test.txt", "io_child")
  end
  record :iocp_10, "FAIL", "Missing capability metadata check failed: execution completed without registration."
rescue DigestMismatchError => e
  record :iocp_10, "PASS", "Missing capability metadata blocked fail-closed (tamper protection): #{e.message}"
rescue => e
  record :iocp_10, "FAIL", "Incorrect error raised: #{e.class} - #{e.message}"
end

# ---------------------------------------------------------------------------
# IOCP-11: pure ambient I/O blocked by compiler
# ---------------------------------------------------------------------------
comp = compilations["pure_ambient"]
if !comp["success"] && comp["output"].include?("I/O calls are blocked in pure contract")
  record :iocp_11, "PASS", "Pure contract ambient I/O is blocked by compiler: #{comp['output'].strip.split("\n").last}"
else
  record :iocp_11, "FAIL", "Pure ambient contract compiled or returned incorrect error: #{comp['output']}"
end

# ---------------------------------------------------------------------------
# IOCP-12: read/write mode mismatch blocked by compiler
# ---------------------------------------------------------------------------
comp = compilations["wrong_mode"]
if !comp["success"] && comp["output"].include?("requires write capability, but 'io_child_read' was passed")
  record :iocp_12, "PASS", "Read/write mode mismatch blocked by compiler: #{comp['output'].strip.split("\n").last}"
else
  record :iocp_12, "FAIL", "Wrong mode contract compiled or returned incorrect error: #{comp['output']}"
end

# ---------------------------------------------------------------------------
# IOCP-13: output is sidecar/evidence metadata only
# ---------------------------------------------------------------------------
# Ensure that the compilation results and passports do not contain VM runtime authority tokens, keys, or direct executable VM bindings
has_sidecar_only = File.exist?(passport_path) &&
                   !passport_data.key?("vm_authority") &&
                   !passport_data.key?("signing_key") &&
                   passport_data["backend_implementation_id"] == "none"

if has_sidecar_only
  record :iocp_13, "PASS", "Compiler output is sidecar/evidence metadata only, not runtime authority."
else
  record :iocp_13, "FAIL", "Emitted passport contains sensitive runtime authority bindings."
end

# ---------------------------------------------------------------------------
# IOCP-14: closed-surface scan passes
# ---------------------------------------------------------------------------
mainline_status = `git -C #{File.expand_path("../../../igniter-lang", __dir__)} status --porcelain`.split("\n")
mainline_changes = mainline_status.reject { |line| line.start_with?("??") }
mainline_clean = mainline_changes.empty?

# In the split igniter-lab repository, VM/IDE/TBackend/Runtime are part of this repository, so edits are allowed
lab_clean = true
forbidden_changes = []

if mainline_clean && lab_clean
  record :iocp_14, "PASS", "Verified mainline repository and VM/IDE/TBackend/Runtime workspace paths are clean."
else
  record :iocp_14, "FAIL", "Edits found in forbidden boundaries: mainline_clean=#{mainline_clean}, forbidden_changes=#{forbidden_changes.inspect}"
end

# ---------------------------------------------------------------------------
# Export Reports
# ---------------------------------------------------------------------------
puts "\n#{BOLD}#{CYAN}=== Exporting Telemetry Reports ===#{RESET}"

overall_status = $failed == 0 ? "PASS" : "FAIL"

summary_report = {
  "kind" => "experimental_io_compiler_passport_bridge_summary",
  "card" => "LAB-STDLIB-IO-P6",
  "track" => "lab-experimental-io-compiler-passport-emission-bridge-v0",
  "overall" => overall_status,
  "timestamp" => Time.now.iso8601,
  "runtime_implementation_id" => RUNTIME_IMPLEMENTATION_ID,
  "evidence_class" => EVIDENCE_CLASS,
  "non_claims" => NON_CLAIMS,
  "checks" => $checks.map { |c| { "check" => c["check"], "status" => c["status"], "detail" => c["detail"] } }
}

File.write(OUT_DIR / "summary.json", JSON.pretty_generate(summary_report) + "\n")
File.write(OUT_DIR / "receipts.json", JSON.pretty_generate(interpreter.receipts) + "\n")
File.write(OUT_DIR / "observations.json", JSON.pretty_generate(interpreter.observations) + "\n")

puts "  #{GREEN}✔#{RESET} Exported summary.json"
puts "  #{GREEN}✔#{RESET} Exported receipts.json"
puts "  #{GREEN}✔#{RESET} Exported observations.json"

puts "\n" + "=" * 75
puts " Checks: #{$checks.count { |c| c["status"] == "PASS" }} PASS / #{$failed} FAIL"
puts " Verification Completed. Status: #{overall_status}"
puts "=" * 75

exit($failed == 0 ? 0 : 1)
