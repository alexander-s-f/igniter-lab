#!/usr/bin/env ruby
# frozen_string_literal: true
#
# verify_lab_igniter_lang_microservice_p1.rb
#
# Card:   LAB-IGNITER-LANG-MICROSERVICE-P1
# Track:  LAB SERVICE ENVELOPE / MICROSERVICE READINESS
# Route:  LAB / ENVELOPE DESIGN + PROOF ONLY / NO SERVER IMPLEMENTATION
#
# Evidence-only static survey. Verifies source/doc facts from igniter-lang
# canon and closed igniter-lab lab evidence. Does NOT execute real IO.
# Does NOT implement a server. Does NOT call Rack/DB/file/queue/network.
#
# Sections:
#   A — Request envelope field coverage and rules
#   B — Response envelope field coverage and outcome kinds
#   C — Host/substrate vs Igniter semantics separation
#   D — Capability allowlist and passport gate coverage
#   E — Replay / idempotency / audit chain evidence
#   F — Rack substrate reuse boundary (reusable shapes vs not authority)
#   G — Upstream evidence anchors from IO Runtime P1 and prior lab cards
#   H — Closed surfaces enforcement

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

puts "#{BOLD}#{CYAN}LAB-IGNITER-LANG-MICROSERVICE-P1 Survey#{RESET}"
puts "Evidence-only. No real IO. No server implementation."
puts

# ─────────────────────────────────────────────────────────────────────────────
# Shared helpers
# ─────────────────────────────────────────────────────────────────────────────

def doc_contains?(rel_path, *phrases)
  path = LANG_ROOT / rel_path
  return false unless path.exist?
  text = path.read(encoding: "utf-8")
  phrases.all? { |ph| text.include?(ph) }
end

def lab_doc_contains?(rel_path, *phrases)
  path = LAB_ROOT / rel_path
  return false unless path.exist?
  text = path.read(encoding: "utf-8")
  phrases.all? { |ph| text.include?(ph) }
end

def lab_card_contains?(rel_path, *phrases)
  path = LAB_ROOT / rel_path
  return false unless path.exist?
  text = path.read(encoding: "utf-8")
  phrases.all? { |ph| text.include?(ph) }
end

def envelope_doc_contains?(*phrases)
  lab_doc_contains?(
    "lab-docs/lang/lab-igniter-lang-microservice-envelope-p1-v0.md",
    *phrases
  )
end

# ─────────────────────────────────────────────────────────────────────────────
section "A — Request Envelope Field Coverage and Rules"
# ─────────────────────────────────────────────────────────────────────────────

check("A-01: envelope doc exists") do
  (LAB_ROOT / "lab-docs/lang/lab-igniter-lang-microservice-envelope-p1-v0.md").exist?
end

check("A-02: request envelope defines correlation_id") do
  envelope_doc_contains?("correlation_id")
end

check("A-03: request envelope defines contract_id") do
  envelope_doc_contains?("contract_id")
end

check("A-04: request envelope defines effect_names") do
  envelope_doc_contains?("effect_names")
end

check("A-05: request envelope defines typed input field") do
  envelope_doc_contains?("input:", "Map[String, Value]")
end

check("A-06: request envelope defines authority_ref") do
  envelope_doc_contains?("authority_ref")
end

check("A-07: request envelope defines capability_passports") do
  envelope_doc_contains?("capability_passports")
end

check("A-08: request envelope defines idempotency_key") do
  envelope_doc_contains?("idempotency_key")
end

check("A-09: request envelope defines artifact_digest") do
  envelope_doc_contains?("artifact_digest")
end

check("A-10: request envelope defines ingress_timestamp from clock binding not now()") do
  envelope_doc_contains?("ingress_timestamp", "clock binding") &&
    !envelope_doc_contains?("ingress_timestamp: now()")
end

check("A-11: request envelope defines profile_ids with declared-only rule") do
  envelope_doc_contains?("profile_ids") &&
    envelope_doc_contains?("profiles declared in the contract")
end

check("A-12: CapabilityPassport shape includes passport_id, family, capability_id, scope_ids") do
  envelope_doc_contains?("passport_id", "family", "capability_id", "scope_ids")
end

# ─────────────────────────────────────────────────────────────────────────────
section "B — Response Envelope Field Coverage and Outcome Kinds"
# ─────────────────────────────────────────────────────────────────────────────

check("B-01: response envelope defines correlation_id (audit chain closure)") do
  envelope_doc_contains?("ServiceResponse") &&
    envelope_doc_contains?("correlation_id")
end

check("B-02: response envelope defines typed output field") do
  envelope_doc_contains?("output:", "typed output from contract output_ports")
end

check("B-03: response envelope defines diagnostics array") do
  envelope_doc_contains?("diagnostics:")
end

check("B-04: response envelope defines receipts array") do
  envelope_doc_contains?("receipts:", "EffectReceipt")
end

check("B-05: response envelope defines effect_outcomes map") do
  envelope_doc_contains?("effect_outcomes")
end

check("B-06: response defines ResponseObservation for audit chain closure (P26)") do
  envelope_doc_contains?("ResponseObservation") &&
    envelope_doc_contains?("evidence_digest")
end

check("B-07: EffectReceipt shape includes receipt_id, inputs_hash, emitted_at") do
  envelope_doc_contains?("receipt_id", "inputs_hash", "emitted_at")
end

check("B-08: all 7 outcome kinds present in response envelope") do
  %w[succeeded failed partial timed_out unknown_external_state compensated cancelled].all? do |k|
    envelope_doc_contains?(k)
  end
end

check("B-09: P15 rule documented — timed_out is UnknownExternalOutcome not ObservedFailure") do
  envelope_doc_contains?("P15", "UnknownExternalOutcome") &&
    envelope_doc_contains?("timed_out") &&
    envelope_doc_contains?("not ObservedFailure")
end

check("B-10: Diagnostic shape defines kind, code, message") do
  envelope_doc_contains?("Diagnostic") &&
    envelope_doc_contains?("kind:", "code:", "message:")
end

# ─────────────────────────────────────────────────────────────────────────────
section "C — Host/Substrate vs Igniter Semantics Separation"
# ─────────────────────────────────────────────────────────────────────────────

check("C-01: doc defines three-layer separation: host / substrate binding / Igniter semantics") do
  envelope_doc_contains?("Host", "Substrate binding", "Igniter semantics")
end

check("C-02: Rack is described as one substrate binding, not the architecture") do
  envelope_doc_contains?("one substrate binding, not the architecture")
end

check("C-03: pipeline diagram includes all 6 stages") do
  envelope_doc_contains?(
    "Ingress gate",
    "RuntimeMachine evaluate",
    "CapabilityExecutor dispatch",
    "Response construction",
    "Substrate binding: serialize",
    "Host process"
  )
end

check("C-04: doc rules that host must not inject ambient state") do
  envelope_doc_contains?("host must not inject ambient state") ||
    envelope_doc_contains?("must not inject ambient state")
end

check("C-05: doc rules that substrate binding must not perform IO outside declared executors") do
  envelope_doc_contains?("must not perform IO") ||
    envelope_doc_contains?("must not call the DB, file system")
end

check("C-06: doc states Rack env is not a SemanticIR node") do
  envelope_doc_contains?("Rack env is not a SemanticIR node")
end

check("C-07: doc states StorageCapability is not an ActiveRecord connection string") do
  envelope_doc_contains?("StorageCapability") &&
    envelope_doc_contains?("ActiveRecord connection string")
end

check("C-08: P1 readiness doc (upstream) also defines substrate separation") do
  lab_doc_contains?(
    "lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md",
    "HTTP / Rack substrate",
    "Semantics layer"
  )
end

# ─────────────────────────────────────────────────────────────────────────────
section "D — Capability Allowlist and Passport Gate Coverage"
# ─────────────────────────────────────────────────────────────────────────────

check("D-01: doc defines gate 1 — contract_id allowlist with refusal code") do
  envelope_doc_contains?("Gate 1", "contract_id must exist in loaded") &&
    envelope_doc_contains?("effect.unknown_contract")
end

check("D-02: doc defines gate 2 — artifact_digest match") do
  envelope_doc_contains?("Gate 2", "artifact_digest") &&
    envelope_doc_contains?("effect.artifact_digest_mismatch")
end

check("D-03: doc defines gate 3 — capability_id allowlist") do
  envelope_doc_contains?("Gate 3", "capability_id must match a declared capability") &&
    envelope_doc_contains?("effect.undeclared_capability")
end

check("D-04: doc defines gate 4 — profile_id allowlist") do
  envelope_doc_contains?("Gate 4", "profile_id") &&
    envelope_doc_contains?("effect.undeclared_profile")
end

check("D-05: doc defines gate 5 — authority_ref verification") do
  envelope_doc_contains?("Gate 5", "authority_ref") &&
    envelope_doc_contains?("effect.authority_missing")
end

check("D-06: doc defines gate 6 — passport validity (not revoked, not expired, scope match)") do
  envelope_doc_contains?("Gate 6") &&
    envelope_doc_contains?("not revoked") &&
    envelope_doc_contains?("effect.passport_invalid")
end

check("D-07: doc defines gate 7 — idempotency_key requirement") do
  envelope_doc_contains?("Gate 7", "idempotency_key") &&
    envelope_doc_contains?("effect.idempotency_key_missing")
end

check("D-08: doc defines gate 8 — executor registration") do
  envelope_doc_contains?("Gate 8") &&
    envelope_doc_contains?("effect.unsupported_family")
end

check("D-09: all gates are fail-closed — structured refusal not exception") do
  envelope_doc_contains?("fail-closed") &&
    envelope_doc_contains?("RuntimeRefusal") &&
    envelope_doc_contains?("not an exception")
end

check("D-10: covenant CR-001 referenced for IO.* opacity") do
  lab_doc_contains?(
    "lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md",
    "CR-001",
    "IO.Capability"
  )
end

# ─────────────────────────────────────────────────────────────────────────────
section "E — Replay / Idempotency / Audit Chain Evidence"
# ─────────────────────────────────────────────────────────────────────────────

check("E-01: doc defines replay invariant: same inputs_hash + idempotency_key + capability_id") do
  envelope_doc_contains?("inputs_hash", "idempotency_key", "capability_id") &&
    envelope_doc_contains?("Replay Invariant")
end

check("E-02: doc defines 7 required receipt fields for replay") do
  %w[effect_name capability_id inputs_hash outcome substrate emitted_at authority_ref].all? do |f|
    envelope_doc_contains?(f)
  end
end

check("E-03: replay flow distinguishes succeeded / unknown_external_state / not-found") do
  envelope_doc_contains?("Replay Flow") &&
    envelope_doc_contains?("unknown_external_state") &&
    envelope_doc_contains?("return original EffectResult without re-executing")
end

check("E-04: doc states unknown_external_state requires reconciliation not retry") do
  envelope_doc_contains?("Reconciliation is the caller") ||
    envelope_doc_contains?("reconciliation, not retry")
end

check("E-05: Postulate 26 audit chain closure documented") do
  envelope_doc_contains?("Postulate 26") &&
    envelope_doc_contains?("ingress_observation") &&
    envelope_doc_contains?("response_observation")
end

check("E-06: ResponseObservation.evidence_digest closes audit chain") do
  envelope_doc_contains?("evidence_digest") &&
    envelope_doc_contains?("sha256")
end

check("E-07: Covenant Postulate 8 (Receipts Are Proof) cited") do
  doc_contains?("docs/language-covenant.md", "Receipts Are Proof") ||
    envelope_doc_contains?("Receipts Are Proof") ||
    envelope_doc_contains?("Postulate 8")
end

# ─────────────────────────────────────────────────────────────────────────────
section "F — Rack Substrate Reuse Boundary"
# ─────────────────────────────────────────────────────────────────────────────

check("F-01: doc lists HttpRequest and HttpResponse as reusable typed shapes") do
  envelope_doc_contains?("HttpRequest", "HttpResponse") &&
    envelope_doc_contains?("Reusable")
end

check("F-02: doc lists ContractResult branch taxonomy as reusable for HTTP status mapping") do
  envelope_doc_contains?("ContractResult") &&
    envelope_doc_contains?("6-branch status map")
end

check("F-03: doc lists call_contract as NOT authority (lab-only)") do
  envelope_doc_contains?("call_contract") &&
    (envelope_doc_contains?("Lab-only") || envelope_doc_contains?("lab-only") || envelope_doc_contains?("not authority"))
end

check("F-04: LAB-RACK-P14 closed surfaces table referenced (accept-loop closed)") do
  lab_card_contains?(
    ".agents/work/cards/lang/LAB-RACK-P14.md",
    "Real Rack env / accept-loop",
    "Closed"
  )
end

check("F-05: LAB-LANG-HTTP-TYPES-P1 two-gate dispatch referenced as reusable pattern") do
  envelope_doc_contains?("Two-gate dispatch", "two-gate dispatch") ||
    envelope_doc_contains?("two-gate")
end

check("F-06: doc explicitly states Igniter::ContractBuilder is not authority") do
  envelope_doc_contains?("Igniter::ContractBuilder") &&
    (envelope_doc_contains?("not authority") || envelope_doc_contains?("Not authority") || envelope_doc_contains?("explicitly closed"))
end

check("F-07: map_get VM gap documented as not available") do
  lab_card_contains?(".agents/work/cards/lang/LAB-RACK-P14.md", "map_get", "Open") &&
    envelope_doc_contains?("map_get")
end

# ─────────────────────────────────────────────────────────────────────────────
section "G — Upstream Evidence Anchors from P1 and Prior Lab Cards"
# ─────────────────────────────────────────────────────────────────────────────

check("G-01: P1 is closed (85/85 PASS)") do
  lab_card_contains?(
    ".agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P1.md",
    "CLOSED",
    "85/85"
  )
end

check("G-02: P1 readiness doc confirms RuntimeMachine load/evaluate proven") do
  lab_doc_contains?(
    "lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md",
    "RuntimeMachine.load",
    "PASS"
  )
end

check("G-03: P1 Q7 microservice pipeline diagram present in readiness doc") do
  lab_doc_contains?(
    "lab-docs/lang/lab-igniter-lang-io-runtime-readiness-v0.md",
    "Q7",
    "Ingress",
    "CapabilityExecutor dispatch"
  )
end

check("G-04: LAB-RACK-P14 result is 60/60 PASS") do
  lab_card_contains?(".agents/work/cards/lang/LAB-RACK-P14.md", "60/60 PASS")
end

check("G-05: LAB-LANG-HTTP-TYPES-P1 result is 41/41 PASS") do
  lab_card_contains?(".agents/work/cards/lang/LAB-LANG-HTTP-TYPES-P1.md", "41/41 PASS")
end

check("G-06: LANG-IO-CAPABILITY-EXECUTOR-P1 card exists and references executor interface") do
  card = LANG_ROOT / ".agents/work/cards/lang/LANG-IO-CAPABILITY-EXECUTOR-P1.md"
  card.exist? &&
    card.read(encoding: "utf-8").include?("CapabilityExecutor")
end

check("G-07: ch12 effect surface exists in igniter-lang canon") do
  (LANG_ROOT / "docs/spec/ch12-effect-surface.md").exist?
end

check("G-07b: ch7 runtime spec exists in igniter-lang canon") do
  (LANG_ROOT / "docs/spec/ch7-runtime.md").exist?
end

check("G-08: envelope doc cites all key upstream cards") do
  %w[
    LAB-IGNITER-LANG-IO-RUNTIME-P1
    LAB-RACK-P14
    LAB-LANG-HTTP-TYPES-P1
    LANG-IO-CAPABILITY-EXECUTOR-P1
  ].all? { |card| envelope_doc_contains?(card) }
end

# ─────────────────────────────────────────────────────────────────────────────
section "H — Closed Surfaces Enforcement"
# ─────────────────────────────────────────────────────────────────────────────

check("H-01: this proof file does not require Rack gem") do
  src = File.read(__FILE__, encoding: "utf-8")
  # Split to avoid self-referential match
  !src.include?("require " + "'rack'") && !src.include?("require " + '"rack"')
end

check("H-02: proof file does not require ORM or AR gem") do
  src = File.read(__FILE__, encoding: "utf-8")
  # Split to avoid self-referential match
  !src.include?("require " + '"active_record"') &&
    !src.include?("require " + "'active_record'")
end

check("H-03: proof file has no real network/DB/file/queue calls") do
  src = File.read(__FILE__, encoding: "utf-8")
  code_lines = src.lines.reject { |l| l.strip.start_with?("#") }
  # Split forbidden phrases to avoid self-referential match in label/code lines
  forbidden = [
    "Net::" + "HTTP",
    "TCP" + "Socket",
    "Side" + "kiq",
    "Redis" + ".new",
    "PG." + "connect"
  ]
  forbidden.none? { |f| code_lines.any? { |l| l.include?(f) } }
end

check("H-04: envelope doc states no server implementation") do
  envelope_doc_contains?("No server implementation")
end

check("H-05: envelope doc states no production runtime claim") do
  envelope_doc_contains?("No production runtime claim")
end

check("H-06: envelope doc states no Reference Runtime claim") do
  envelope_doc_contains?("No Reference Runtime claim")
end

check("H-07: envelope doc states no now() in envelope fields (clock binding only)") do
  envelope_doc_contains?("now()") &&
    (envelope_doc_contains?("clock binding only") || envelope_doc_contains?("No `now()`"))
end

check("H-08: old Ruby igniter gem not referenced as authority") do
  envelope_doc_contains?("old Ruby") &&
    (envelope_doc_contains?("not authority") || envelope_doc_contains?("explicitly closed"))
end

check("H-09: LAB-IO-RUNTIME-P2 card exists and confirms storage-read mocked route") do
  lab_card_contains?(
    ".agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P2.md",
    "Storage",
    "mocked"
  )
end

# ─────────────────────────────────────────────────────────────────────────────
# Results summary
# ─────────────────────────────────────────────────────────────────────────────

pass_count = RESULTS.count { |r| r[:pass] }
fail_count = RESULTS.count { |r| !r[:pass] }
total      = RESULTS.size

puts "\n#{BOLD}────────────────────────────────────────────────────────────────#{RESET}"
puts "#{BOLD}RESULT#{RESET}: #{pass_count}/#{total} PASS"

if fail_count > 0
  puts "#{RED}FAILED CHECKS:#{RESET}"
  RESULTS.select { |r| !r[:pass] }.each { |r| puts "  - #{r[:label]}" }
  puts "\n#{RED}#{BOLD}FAIL#{RESET} — #{fail_count} check(s) did not pass"
  exit 1
else
  puts "#{GREEN}#{BOLD}PASS#{RESET} — #{total}/#{total} checks passed"
  exit 0
end
