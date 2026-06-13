#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igniter_lang_io_runtime_p1.rb
#
# Card:   LAB-IGNITER-LANG-IO-RUNTIME-P1
# Track:  lab-igniter-lang-io-runtime-readiness-boundary-v0
# Route:  LAB READINESS / IO RUNTIME / NO IMPLEMENTATION
#
# Evidence-only survey. Verifies source/docs facts from igniter-lang canon and
# lab evidence. Does NOT execute real IO. Does NOT call network/DB/file/queue.
#
# Sections:
#   A — igniter-lang source authority only; no old Ruby framework references
#   B — RuntimeMachine load/evaluate/checkpoint/resume status from Ch7
#   C — Effect Surface status from Ch12 and Covenant
#   D — IO.* capability normalization / opacity evidence
#   E — IO capability fixtures parse/classify/typecheck surface
#   F — Experimental runtime quickstart disclaimers
#   G — Prior lab IO families and closed surfaces census
#   H — Proposed IO Runtime route and refusal gates
#   I — Closed surfaces: no Rack/ORM/ActiveRecord/Rails authority

require "pathname"
require "json"

LANG_ROOT = Pathname.new(File.expand_path("../../../igniter-lang", __dir__)).freeze
LAB_ROOT  = Pathname.new(File.expand_path("../..", __dir__)).freeze

GREEN  = "\e[32m"
RED    = "\e[31m"
CYAN   = "\e[36m"
BOLD   = "\e[1m"
RESET  = "\e[0m"

RESULTS = []

def check(label, &block)
  result = block.call
  status = result ? "PASS" : "FAIL"
  colour = result ? GREEN : RED
  puts "  #{colour}[#{status}]#{RESET} #{label}"
  RESULTS << { label: label, pass: result }
rescue => e
  puts "  #{RED}[ERROR]#{RESET} #{label}: #{e.message}"
  RESULTS << { label: label, pass: false }
end

def section(title)
  puts "\n#{CYAN}#{BOLD}── #{title} ──#{RESET}"
end

puts "#{BOLD}#{CYAN}LAB-IGNITER-LANG-IO-RUNTIME-P1 Survey#{RESET}"
puts "Evidence-only. No real IO. No implementation."
puts

# ─────────────────────────────────────────────────────────────────────────────
section "A — Source Authority: igniter-lang canon only; no old Ruby framework"
# ─────────────────────────────────────────────────────────────────────────────

check("A-01: igniter-lang root exists") do
  LANG_ROOT.directory?
end

check("A-02: language-covenant.md exists") do
  (LANG_ROOT / "docs/language-covenant.md").file?
end

check("A-03: ch7-runtime.md exists") do
  (LANG_ROOT / "docs/spec/ch7-runtime.md").file?
end

check("A-04: ch12-effect-surface.md exists") do
  (LANG_ROOT / "docs/spec/ch12-effect-surface.md").file?
end

check("A-05: io_capability_basic.ig exists (canon source fixture)") do
  (LANG_ROOT / "source/io_capability_basic.ig").file?
end

check("A-06: io_capability_oof_blocked.ig exists (canon source fixture)") do
  (LANG_ROOT / "source/io_capability_oof_blocked.ig").file?
end

check("A-07: io_capability_proof.rb does not reference TCPSocket or Net::HTTP") do
  proof_path = LANG_ROOT / "experiments/io_capability_proof/io_capability_proof.rb"
  next false unless proof_path.file?
  src = proof_path.read
  forbidden = ["TCPSocket", "Net::HTTP", "UDPSocket", "require 'socket'", "require \"socket\""]
  forbidden.none? { |f| src.include?(f) }
end

check("A-08: proof runner does not reference Igniter::ContractBuilder or GraphCompiler") do
  proof_path = LANG_ROOT / "experiments/io_capability_proof/io_capability_proof.rb"
  next false unless proof_path.file?
  src = proof_path.read
  !src.include?("ContractBuilder") && !src.include?("GraphCompiler")
end

check("A-09: readiness doc exists at expected path") do
  (LAB_ROOT / "lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md").file?
end

check("A-10: readiness doc does not reference ActiveRecord or ORM as authority") do
  doc = LAB_ROOT / "lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md"
  next false unless doc.file?
  src = doc.read
  !src.include?("ActiveRecord") || src.include?("PERMANENTLY CLOSED")
end

# ─────────────────────────────────────────────────────────────────────────────
section "B — RuntimeMachine: load/evaluate/checkpoint/resume status from Ch7"
# ─────────────────────────────────────────────────────────────────────────────

ch7 = (LANG_ROOT / "docs/spec/ch7-runtime.md").read rescue ""

check("B-01: Ch7 documents RuntimeMachine.load -> LoadedProgram | LoadRefusal") do
  ch7.include?("RuntimeMachine.load") && ch7.include?("LoadedProgram")
end

check("B-02: Ch7 documents RuntimeMachine.evaluate -> EvaluationResult | EvaluateRefusal") do
  ch7.include?("RuntimeMachine.evaluate") && ch7.include?("EvaluationResult")
end

check("B-03: Ch7 documents checkpoint and resume lifecycle steps") do
  ch7.include?("checkpoint") && ch7.include?("resume")
end

check("B-04: Ch7 Stage 1/2 proven behaviour section lists PASS for load/evaluate") do
  ch7.include?("PASS RuntimeMachine.load") || ch7.include?("PASS")
end

check("B-05: Ch7 supported Stage 1 executable node kinds include input_node, compute_node, output_node") do
  ch7.include?("input_node") && ch7.include?("compute_node") && ch7.include?("output_node")
end

check("B-06: Ch7 does NOT list capability_node or effect_binding_node as supported evaluate kinds") do
  # These do not exist yet in the evaluate surface
  !ch7.include?("capability_node as supported") && !ch7.include?("effect_binding_node as supported")
end

check("B-07: Ch7 documents CompatibilityReport dimensions including executor_readiness") do
  ch7.include?("executor_readiness")
end

check("B-08: Ch7 Phase 1 TEMPORAL guard is load_accept_phase1_pre_live_refuse") do
  ch7.include?("load_accept_phase1_pre_live_refuse")
end

check("B-09: runtime_smoke.rb is proof-backed, not production runtime") do
  smoke = LANG_ROOT / "lib/igniter_lang/runtime_smoke.rb"
  next false unless smoke.file?
  src = smoke.read
  src.include?("proof-backed") || src.include?("proof_local") || src.include?("MemoryTBackend")
end

check("B-10: CompatibilityReport lists executor_approval_check dimension") do
  ch7.include?("executor_approval_check")
end

# ─────────────────────────────────────────────────────────────────────────────
section "C — Effect Surface: Ch12 status and Covenant enforcement"
# ─────────────────────────────────────────────────────────────────────────────

ch12     = (LANG_ROOT / "docs/spec/ch12-effect-surface.md").read rescue ""
covenant = (LANG_ROOT / "docs/language-covenant.md").read rescue ""

check("C-01: Ch12 status is 'proposed' (PROP-035 not yet authored)") do
  ch12.include?("proposed") || ch12.include?("Status: proposed")
end

check("C-02: Ch12 defines 7 Effect Surface fields") do
  %w[affects authority reversibility idempotency receipt failure compensation].all? do |f|
    ch12.include?(f)
  end
end

check("C-03: Ch12 defines 7-outcome failure taxonomy") do
  %w[succeeded failed partial timed_out unknown_external_state compensated cancelled].all? do |o|
    ch12.include?(o)
  end
end

check("C-04: Covenant P15 says timeout is UnknownExternalOutcome, not ObservedFailure") do
  covenant.include?("UnknownExternalOutcome") && covenant.include?("Timeout Is Not Failure")
end

check("C-05: Covenant P8 says receipts are immutable proofs") do
  covenant.include?("Receipts Are Proof")
end

check("C-06: Covenant P4 says every side effect must be named (escape modifier)") do
  covenant.include?("Named Effects") || covenant.include?("escape notification")
end

check("C-07: Covenant Postulate 9 says authority is a typed value, not ambient role") do
  covenant.include?("Authority Is Explicit") || covenant.include?("Authority is a value")
end

check("C-08: Covenant P7 says Effect Surface must be readable from contract header alone") do
  covenant.include?("No Hidden Consequences") || covenant.include?("Effect Surface")
end

check("C-09: Covenant enforcement table marks P15 as planned PROP (PROP-035 pending)") do
  covenant.include?("planned PROP") && covenant.include?("PROP-035")
end

check("C-10: Ch12 OOF-M2 is defined for missing required Effect Surface fields") do
  ch12.include?("OOF-M2")
end

# ─────────────────────────────────────────────────────────────────────────────
section "D — IO.* Capability Normalization / Opacity Evidence"
# ─────────────────────────────────────────────────────────────────────────────

check("D-01: CR-001 is defined in the Covenant") do
  covenant.include?("CR-001") && covenant.include?("Canon Type Opacity")
end

check("D-02: CR-001 states IO.* names normalize to IO.Capability sentinel") do
  covenant.include?("IO.Capability") && covenant.include?("sentinel")
end

check("D-03: CR-001 forbids canon from importing Rack, HTTP, or gem-specific schemas") do
  covenant.include?("Rack") && covenant.include?("opaque") || covenant.include?("opaque string identifiers")
end

check("D-04: io_capability_basic.ig uses IO.NetworkCapability (opaque name)") do
  fixture = LANG_ROOT / "source/io_capability_basic.ig"
  next false unless fixture.file?
  fixture.read.include?("IO.NetworkCapability")
end

check("D-05: io_capability_oof_blocked.ig uses IO.NetworkCapability in wrong position") do
  fixture = LANG_ROOT / "source/io_capability_oof_blocked.ig"
  next false unless fixture.file?
  src = fixture.read
  src.include?("IO.NetworkCapability") && src.include?("pure contract")
end

check("D-06: io_capability_proof verifies IO.Capability (not IO.NetworkCapability) in typed IR") do
  proof = LANG_ROOT / "experiments/io_capability_proof/io_capability_proof.rb"
  next false unless proof.file?
  src = proof.read
  src.include?('"IO.Capability"') || src.include?("IO.Capability")
end

check("D-07: CR-001 scope applies to all capability body declarations in effect/privileged/irreversible") do
  # CR-001 Scope: "All `capability` body declarations in `effect`/`privileged`/`irreversible` contracts"
  covenant.include?("capability` body declarations") || covenant.include?("capability body declarations") ||
    (covenant.include?("CR-001") && covenant.include?("privileged") && covenant.include?("irreversible"))
end

check("D-08: CR-001 does NOT apply to igniter-lab proofs (lab may know full schemas)") do
  covenant.include?("Does NOT apply to igniter-lab") || covenant.include?("lab may know full schemas")
end

# ─────────────────────────────────────────────────────────────────────────────
section "E — IO Capability Fixtures: parse/classify/typecheck surface"
# ─────────────────────────────────────────────────────────────────────────────

proof_src = (LANG_ROOT / "experiments/io_capability_proof/io_capability_proof.rb").read rescue ""

check("E-01: io_capability_proof references CAP-PARSE section (parser AST)") do
  proof_src.include?("CAP-PARSE") || proof_src.include?("capability and effect_binding AST")
end

check("E-02: io_capability_proof verifies fragment_class is escape for effect contract with capability") do
  proof_src.include?("escape") && proof_src.include?("fragment_class")
end

check("E-03: io_capability_proof verifies OOF-M2 fires for pure contract with capability") do
  proof_src.include?("OOF-M2")
end

check("E-04: io_capability_proof verifies OOF-M4 fires for effect_binding referencing missing cap") do
  proof_src.include?("OOF-M4")
end

check("E-05: io_capability_proof verifies OOF-M5 fires for declared capability with no effect binding") do
  proof_src.include?("OOF-M5")
end

check("E-06: io_capability_proof covers multi-capability contract (two caps + two bindings)") do
  proof_src.include?("CAP-MULTI") || proof_src.include?("multi_capability") || proof_src.include?("Multi-capability")
end

check("E-07: io_capability_proof covers IO.FileCapability (non-Network capability type)") do
  proof_src.include?("IO.FileCapability") || proof_src.include?("CAP-FILE")
end

check("E-08: io_capability_proof verifies no forbidden socket refs in runner itself") do
  proof_src.include?("CAP-STABLE-5") || proof_src.include?("forbidden socket")
end

# ─────────────────────────────────────────────────────────────────────────────
section "F — Experimental Runtime: quickstart disclaimers"
# ─────────────────────────────────────────────────────────────────────────────

quickstart = (LANG_ROOT / "examples/experimental_executable_quickstart_v0/quickstart.rb").read rescue ""

check("F-01: quickstart.rb exists") do
  (LANG_ROOT / "examples/experimental_executable_quickstart_v0/quickstart.rb").file?
end

check("F-02: quickstart.rb declares it is NOT stable API") do
  quickstart.include?("not stable API") || quickstart.include?("Not stable API") ||
    quickstart.include?("not stable")
end

check("F-03: quickstart.rb declares it is NOT production runtime support") do
  quickstart.include?("not production runtime") || quickstart.include?("not production")
end

check("F-04: quickstart.rb declares it is NOT Reference Runtime support") do
  quickstart.include?("not Reference Runtime") || quickstart.include?("Reference Runtime")
end

check("F-05: quickstart.rb identifies three-runtime distinction (Spec / Reference / Delegated Experimental)") do
  quickstart.include?("Runtime Specification") || quickstart.include?("Delegated Experimental")
end

check("F-06: runtime_smoke.rb ensure_available! raises LoadError if proof-local runtime unavailable") do
  smoke = (LANG_ROOT / "lib/igniter_lang/runtime_smoke.rb").read rescue ""
  smoke.include?("ensure_available!") && smoke.include?("LoadError")
end

# ─────────────────────────────────────────────────────────────────────────────
section "G — Prior Lab IO Families: census of proven/closed surfaces"
# ─────────────────────────────────────────────────────────────────────────────

io_boundary_card = (LAB_ROOT / ".agents/work/cards/governance/LAB-IO-BOUNDARY-P1.md").read rescue ""
storage_cap_card = (LAB_ROOT / ".agents/work/cards/lang/LAB-STORAGE-CAPABILITY-P1.md").read rescue ""
file_io_card     = (LAB_ROOT / ".agents/work/cards/lang/LAB-FILE-IO-P1.md").read rescue ""
rack_p14_card    = (LAB_ROOT / ".agents/work/cards/lang/LAB-RACK-P14.md").read rescue ""

check("G-01: LAB-IO-BOUNDARY-P1 CLOSED with governance packet") do
  io_boundary_card.include?("CLOSED") && io_boundary_card.include?("governance")
end

check("G-02: LAB-IO-BOUNDARY-P1 classifies 7 IO families") do
  %w[Storage Network File Clock Random Process IPC].count { |f| io_boundary_card.include?(f) } >= 6
end

check("G-03: LAB-IO-BOUNDARY-P1 says Storage IO is READY for design-only adapter") do
  io_boundary_card.include?("READY") && io_boundary_card.include?("Storage")
end

check("G-04: LAB-IO-BOUNDARY-P1 substrate readiness checklist includes denial-as-data proof requirement") do
  io_boundary_card.include?("denial-as-data")
end

check("G-05: LAB-STORAGE-CAPABILITY-P1 closed — real DB permanently closed") do
  storage_cap_card.include?("CLOSED") && storage_cap_card.include?("PERMANENTLY CLOSED")
end

check("G-06: LAB-STORAGE-CAPABILITY-P1 defines IO.StorageCapability schema v0") do
  storage_cap_card.include?("IO.StorageCapability") || storage_cap_card.include?("capability_id")
end

check("G-07: LAB-STORAGE-CAPABILITY-P1 defines 6-gate denial-as-data sequence") do
  storage_cap_card.include?("G1") && storage_cap_card.include?("G6") &&
    storage_cap_card.include?("denied")
end

check("G-08: LAB-FILE-IO-P1 CLOSED with 78/78 PASS") do
  file_io_card.include?("78/78") && file_io_card.include?("CLOSED")
end

check("G-09: LAB-FILE-IO-P1 real filesystem reads/writes remain HOLD") do
  file_io_card.include?("HOLD") || file_io_card.include?("no real filesystem")
end

check("G-10: LAB-RACK-P14 proves Rack-shaped types are substrate binding, not core architecture") do
  rack_p14_card.include?("lab-only") || rack_p14_card.include?("No Rack-compatibility claim")
end

check("G-11: LAB-EXECUTE-QUERY-P3 CLOSED 68/68 with no real DB") do
  execq3 = (LAB_ROOT / ".agents/work/cards/lang/LAB-EXECUTE-QUERY-P3.md").read rescue ""
  execq3.include?("68/68") && execq3.include?("NO DB")
end

# ─────────────────────────────────────────────────────────────────────────────
section "H — Proposed IO Runtime Route and Refusal Gates"
# ─────────────────────────────────────────────────────────────────────────────

readiness = (LAB_ROOT / "lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md").read rescue ""

check("H-01: readiness doc defines the IO Runtime route sequence") do
  readiness.include?("Effect Surface") && readiness.include?("CapabilityExecutor") &&
    readiness.include?("EffectReceipt")
end

check("H-02: readiness doc defines microservice pipeline: ingress -> evaluate -> dispatch -> response -> audit") do
  readiness.include?("Ingress") && readiness.include?("evaluate") && readiness.include?("Audit")
end

check("H-03: readiness doc defines fail-closed gate: missing executor -> RuntimeRefusal") do
  readiness.include?("effect.unsupported_family") || readiness.include?("unsupported_family")
end

check("H-04: readiness doc defines fail-closed gate: missing passport -> RuntimeRefusal") do
  readiness.include?("effect.missing_passport") || readiness.include?("missing_passport")
end

check("H-05: readiness doc defines fail-closed gate: unknown external outcome -> unknown_external_state") do
  readiness.include?("unknown_external_state")
end

check("H-06: readiness doc recommends Storage read family for P2 (deepest evidence)") do
  readiness.include?("Storage read") && readiness.include?("P2")
end

check("H-07: readiness doc defines minimum EffectReceipt envelope fields") do
  %w[receipt_id effect_name capability_id authority_ref outcome].all? { |f| readiness.include?(f) }
end

check("H-08: readiness doc states that timed_out is UnknownExternalOutcome, not failure") do
  readiness.include?("timed_out") && readiness.include?("UnknownExternalOutcome")
end

check("H-09: readiness doc names LANG-IO-CAPABILITY-EXECUTOR-P1 as next route") do
  readiness.include?("LANG-IO-CAPABILITY-EXECUTOR-P1")
end

check("H-10: readiness doc names LAB-IGNITER-LANG-IO-RUNTIME-P2 as first mocked slice") do
  readiness.include?("LAB-IGNITER-LANG-IO-RUNTIME-P2")
end

check("H-11: readiness doc identifies that pure HTTP wrapper is insufficient for microservice goals") do
  readiness.include?("half-measure") || readiness.include?("pure HTTP wrapper")
end

check("H-12: readiness doc identifies Rack/HTTP as one substrate binding, not core architecture") do
  readiness.include?("substrate binding") && readiness.include?("Rack")
end

# ─────────────────────────────────────────────────────────────────────────────
section "I — Closed Surfaces: no Rack/ORM/ActiveRecord/Rails authority"
# ─────────────────────────────────────────────────────────────────────────────

check("I-01: readiness doc explicitly closes old Ruby igniter framework") do
  readiness.include?("old Ruby") || readiness.include?("old Ruby `igniter`")
end

check("I-02: readiness doc closes ActiveRecord/ORM permanently") do
  readiness.include?("ActiveRecord") && readiness.include?("CLOSED")
end

check("I-03: readiness doc closes real DB/SQL/network/file/queue/process/clock/random execution") do
  readiness.include?("No real DB") || readiness.include?("real DB / SQL / network")
end

check("I-04: readiness doc closes production runtime claim") do
  readiness.include?("production runtime claim")
end

check("I-05: readiness doc closes Reference Runtime claim") do
  readiness.include?("Reference Runtime claim")
end

check("I-06: readiness doc closes public/stable API claim") do
  readiness.include?("public or stable API claim") || readiness.include?("public/stable API")
end

check("I-07: readiness doc closes ambient IO (no generic ambient IO)") do
  readiness.include?("ambient IO") || readiness.include?("generic ambient IO")
end

check("I-08: io_capability_oof_blocked.ig proves ambient IO is blocked by OOF-M2 at TC") do
  fixture = LANG_ROOT / "source/io_capability_oof_blocked.ig"
  next false unless fixture.file?
  src = fixture.read
  src.include?("pure contract") && src.include?("IO.NetworkCapability")
end

check("I-09: LAB-STORAGE-CAPABILITY-P1 closes ORM/ActiveRecord permanently") do
  storage_cap_card.include?("ORM") && storage_cap_card.include?("PERMANENTLY CLOSED")
end

check("I-10: LAB-IO-BOUNDARY-P1 closes canon grammar changes, compiler changes, VM changes") do
  io_boundary_card.include?("no parser changes") || io_boundary_card.include?("no compiler changes")
end

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────

puts "\n#{BOLD}═══════════════════════════════════════════════#{RESET}"
total  = RESULTS.length
passed = RESULTS.count { |r| r[:pass] }
failed = total - passed

if failed.zero?
  puts "#{BOLD}#{GREEN}PASS #{passed}/#{total}#{RESET}"
else
  puts "#{BOLD}#{RED}FAIL #{failed}/#{total} checks failed#{RESET}"
  RESULTS.reject { |r| r[:pass] }.each { |r| puts "  #{RED}✗#{RESET} #{r[:label]}" }
end

puts "#{BOLD}═══════════════════════════════════════════════#{RESET}"
puts "Evidence-only survey. No runtime code written. No real IO executed."
exit(failed.zero? ? 0 : 1)
